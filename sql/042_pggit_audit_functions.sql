-- ============================================
-- pgGit Audit Layer: Extraction Functions
-- ============================================
-- Functions to extract DDL changes from pggit_v0 commits

-- ============================================
-- EXTRACTION FUNCTIONS
-- ============================================

-- Function: Extract changes between two commits
-- This is the core function that analyzes pggit_v0 commits and extracts DDL changes
CREATE OR REPLACE FUNCTION pggit_audit.extract_changes_between_commits(
    p_old_commit_sha TEXT,
    p_new_commit_sha TEXT
) RETURNS TABLE (
    change_id UUID,
    commit_sha TEXT,
    object_schema TEXT,
    object_name TEXT,
    object_type TEXT,
    change_type TEXT,
    old_definition TEXT,
    new_definition TEXT,
    author TEXT,
    committed_at TIMESTAMP,
    commit_message TEXT
) AS $$
DECLARE
    v_old_tree_sha TEXT;
    v_new_tree_sha TEXT;
    v_change_record RECORD;
    v_new_change_id UUID;
    v_commit_author TEXT;
    v_commit_timestamp TIMESTAMP;
    v_commit_message TEXT;
BEGIN
    -- Validate input parameters
    IF p_old_commit_sha IS NULL OR p_new_commit_sha IS NULL THEN
        RAISE EXCEPTION 'Commit SHAs cannot be NULL';
    END IF;

    IF p_old_commit_sha = p_new_commit_sha THEN
        RAISE EXCEPTION 'Old and new commit SHAs cannot be the same';
    END IF;

    -- Get tree SHAs from commits with validation
    SELECT tree_sha INTO v_old_tree_sha
    FROM pggit_v0.commit_graph
    WHERE commit_sha = p_old_commit_sha;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Old commit SHA % not found in pggit_v0.commit_graph', p_old_commit_sha;
    END IF;

    SELECT tree_sha INTO v_new_tree_sha
    FROM pggit_v0.commit_graph
    WHERE commit_sha = p_new_commit_sha;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'New commit SHA % not found in pggit_v0.commit_graph', p_new_commit_sha;
    END IF;

    -- Get commit metadata once (more efficient)
    SELECT author, committed_at, message INTO v_commit_author, v_commit_timestamp, v_commit_message
    FROM pggit_v0.commit_graph
    WHERE commit_sha = p_new_commit_sha;

    -- If old tree doesn't exist, treat as initial commit (all objects are CREATE)
    IF v_old_tree_sha IS NULL THEN
        -- Process all objects from new tree as CREATE operations
        FOR v_change_record IN
            SELECT
                te.path,
                o.content as new_definition
            FROM pggit_v0.tree_entries te
            JOIN pggit_v0.objects o ON o.sha = te.object_sha AND o.type = 'blob'
            WHERE te.tree_sha = v_new_tree_sha
        LOOP
            -- Parse path to get schema and object name
            v_new_change_id := gen_random_uuid();

            RETURN QUERY
            SELECT
                v_new_change_id,
                p_new_commit_sha,
                split_part(v_change_record.path, '.', 1),
                split_part(v_change_record.path, '.', 2),
                pggit_audit.determine_object_type(v_change_record.new_definition),
                'CREATE'::TEXT,
                NULL::TEXT,
                v_change_record.new_definition,
                v_commit_author,
                v_commit_timestamp,
                v_commit_message;
        END LOOP;
    ELSE
        -- Compare trees to find changes
        FOR v_change_record IN
            SELECT * FROM pggit_v0.diff_trees(v_old_tree_sha, v_new_tree_sha)
        LOOP
            v_new_change_id := gen_random_uuid();

            RETURN QUERY
            SELECT
                v_new_change_id,
                p_new_commit_sha,
                split_part(v_change_record.path, '.', 1),
                split_part(v_change_record.path, '.', 2),
                pggit_audit.determine_object_type(
                    COALESCE(
                        (SELECT content FROM pggit_v0.objects WHERE sha = v_change_record.new_sha),
                        (SELECT content FROM pggit_v0.objects WHERE sha = v_change_record.old_sha)
                    )
                ),
                CASE
                    WHEN v_change_record.change_type = 'add' THEN 'CREATE'
                    WHEN v_change_record.change_type = 'delete' THEN 'DROP'
                    WHEN v_change_record.change_type = 'modify' THEN 'ALTER'
                    ELSE 'UNKNOWN'
                END,
                CASE WHEN v_change_record.change_type IN ('modify', 'delete')
                     THEN (SELECT content FROM pggit_v0.objects WHERE sha = v_change_record.old_sha)
                     ELSE NULL
                END,
                CASE WHEN v_change_record.change_type IN ('modify', 'add')
                     THEN (SELECT content FROM pggit_v0.objects WHERE sha = v_change_record.new_sha)
                     ELSE NULL
                END,
                v_commit_author,
                v_commit_timestamp,
                v_commit_message;
        END LOOP;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function: Backfill audit data from v1 history
-- This function converts pggit v1 history to pggit_audit.changes records
-- Implements robust DDL parsing for production use
CREATE OR REPLACE FUNCTION pggit_audit.backfill_from_v1_history()
RETURNS TABLE(processed INT, errors INT, warnings INT) AS $$
DECLARE
    v_history_record RECORD;
    v_processed_count INT := 0;
    v_error_count INT := 0;
    v_warning_count INT := 0;
    v_change_id UUID;
    v_object_schema TEXT;
    v_object_name TEXT;
    v_object_type TEXT;
    v_change_type TEXT;
    v_parse_success BOOLEAN;
    v_ddl_upper TEXT;
    v_matches TEXT[];
BEGIN
    -- Process each v1 history record in chronological order
    FOR v_history_record IN
        SELECT * FROM pggit.history
        ORDER BY created_at, id
    LOOP
        BEGIN
            -- Initialize parsing variables
            v_object_schema := NULL;
            v_object_name := NULL;
            v_object_type := NULL;
            v_change_type := NULL;
            v_parse_success := false;
            v_ddl_upper := upper(trim(v_history_record.sql_executed));

            -- Comprehensive DDL parsing with multiple patterns
            -- TABLE operations
            IF v_ddl_upper ~ '^CREATE\s+(?:OR\s+REPLACE\s+)?TABLE\s+' THEN
                v_object_type := 'TABLE';
                v_change_type := 'CREATE';
                v_matches := regexp_match(v_history_record.sql_executed, 'CREATE\s+(?:OR\s+REPLACE\s+)?TABLE\s+(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?', 'i');
                IF v_matches IS NOT NULL THEN
                    v_object_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
                    v_object_name := v_matches[4];
                    v_parse_success := true;
                END IF;

            ELSIF v_ddl_upper ~ '^ALTER\s+TABLE\s+' THEN
                v_object_type := 'TABLE';
                v_change_type := 'ALTER';
                v_matches := regexp_match(v_history_record.sql_executed, 'ALTER\s+TABLE\s+(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?', 'i');
                IF v_matches IS NOT NULL THEN
                    v_object_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
                    v_object_name := v_matches[4];
                    v_parse_success := true;
                END IF;

            ELSIF v_ddl_upper ~ '^DROP\s+TABLE\s+' THEN
                v_object_type := 'TABLE';
                v_change_type := 'DROP';
                v_matches := regexp_match(v_history_record.sql_executed, 'DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?', 'i');
                IF v_matches IS NOT NULL THEN
                    v_object_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
                    v_object_name := v_matches[4];
                    v_parse_success := true;
                END IF;

            -- FUNCTION operations
            ELSIF v_ddl_upper ~ '^CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+' THEN
                v_object_type := 'FUNCTION';
                v_change_type := 'CREATE';
                v_matches := regexp_match(v_history_record.sql_executed, 'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?\s*\(', 'i');
                IF v_matches IS NOT NULL THEN
                    v_object_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
                    v_object_name := v_matches[4];
                    v_parse_success := true;
                END IF;

            ELSIF v_ddl_upper ~ '^DROP\s+FUNCTION\s+' THEN
                v_object_type := 'FUNCTION';
                v_change_type := 'DROP';
                v_matches := regexp_match(v_history_record.sql_executed, 'DROP\s+FUNCTION\s+(?:IF\s+EXISTS\s+)?(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?\s*\(', 'i');
                IF v_matches IS NOT NULL THEN
                    v_object_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
                    v_object_name := v_matches[4];
                    v_parse_success := true;
                END IF;

            -- VIEW operations
            ELSIF v_ddl_upper ~ '^CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+' THEN
                v_object_type := 'VIEW';
                v_change_type := 'CREATE';
                v_matches := regexp_match(v_history_record.sql_executed, 'CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?', 'i');
                IF v_matches IS NOT NULL THEN
                    v_object_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
                    v_object_name := v_matches[4];
                    v_parse_success := true;
                END IF;

            ELSIF v_ddl_upper ~ '^DROP\s+VIEW\s+' THEN
                v_object_type := 'VIEW';
                v_change_type := 'DROP';
                v_matches := regexp_match(v_history_record.sql_executed, 'DROP\s+VIEW\s+(?:IF\s+EXISTS\s+)?(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?', 'i');
                IF v_matches IS NOT NULL THEN
                    v_object_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
                    v_object_name := v_matches[4];
                    v_parse_success := true;
                END IF;

            -- INDEX operations
            ELSIF v_ddl_upper ~ '^CREATE\s+(?:UNIQUE\s+)?INDEX\s+' THEN
                v_object_type := 'INDEX';
                v_change_type := 'CREATE';
                v_matches := regexp_match(v_history_record.sql_executed, 'CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:CONCURRENTLY\s+)?(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?', 'i');
                IF v_matches IS NOT NULL THEN
                    v_object_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
                    v_object_name := v_matches[4];
                    v_parse_success := true;
                END IF;

            ELSIF v_ddl_upper ~ '^DROP\s+INDEX\s+' THEN
                v_object_type := 'INDEX';
                v_change_type := 'DROP';
                v_matches := regexp_match(v_history_record.sql_executed, 'DROP\s+INDEX\s+(?:CONCURRENTLY\s+)?(?:IF\s+EXISTS\s+)?(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?', 'i');
                IF v_matches IS NOT NULL THEN
                    v_object_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
                    v_object_name := v_matches[4];
                    v_parse_success := true;
                END IF;

            -- SEQUENCE operations
            ELSIF v_ddl_upper ~ '^CREATE\s+SEQUENCE\s+' THEN
                v_object_type := 'SEQUENCE';
                v_change_type := 'CREATE';
                v_matches := regexp_match(v_history_record.sql_executed, 'CREATE\s+SEQUENCE\s+(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?', 'i');
                IF v_matches IS NOT NULL THEN
                    v_object_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
                    v_object_name := v_matches[4];
                    v_parse_success := true;
                END IF;

            ELSIF v_ddl_upper ~ '^DROP\s+SEQUENCE\s+' THEN
                v_object_type := 'SEQUENCE';
                v_change_type := 'DROP';
                v_matches := regexp_match(v_history_record.sql_executed, 'DROP\s+SEQUENCE\s+(?:IF\s+EXISTS\s+)?(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?', 'i');
                IF v_matches IS NOT NULL THEN
                    v_object_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
                    v_object_name := v_matches[4];
                    v_parse_success := true;
                END IF;
            END IF;

            -- Handle parsing results
            IF NOT v_parse_success THEN
                -- Try to extract minimal info from change_description
                IF v_history_record.change_description ~* 'table\s+(\w+\.)?(\w+)' THEN
                    v_object_type := COALESCE(v_object_type, 'TABLE');
                    v_matches := regexp_match(v_history_record.change_description, 'table\s+(\w+\.)?(\w+)', 'i');
                    v_object_schema := COALESCE(v_matches[1], 'public');
                    v_object_name := COALESCE(v_matches[2], 'unknown');
                    v_change_type := COALESCE(v_change_type, 'UNKNOWN');
                    v_warning_count := v_warning_count + 1;
                    RAISE WARNING 'Used fallback parsing for history record %: %', v_history_record.id, left(v_history_record.sql_executed, 100);
                ELSE
                    -- Complete fallback
                    v_object_schema := 'unknown';
                    v_object_name := 'unknown';
                    v_object_type := 'UNKNOWN';
                    v_change_type := 'UNKNOWN';
                    v_warning_count := v_warning_count + 1;
                    RAISE WARNING 'Could not parse DDL for history record %: %', v_history_record.id, left(v_history_record.sql_executed, 100);
                END IF;
            END IF;

            -- Validate required fields
            IF v_object_schema IS NULL OR v_object_name IS NULL THEN
                RAISE EXCEPTION 'Failed to extract schema/name from DDL: %', left(v_history_record.sql_executed, 200);
            END IF;

            v_change_id := gen_random_uuid();

            INSERT INTO pggit_audit.changes (
                change_id,
                commit_sha,
                object_schema,
                object_name,
                object_type,
                change_type,
                new_definition,
                author,
                committed_at,
                commit_message,
                backfilled_from_v1,
                verified
            ) VALUES (
                v_change_id,
                COALESCE(v_history_record.commit_hash, 'unknown'),
                v_object_schema,
                v_object_name,
                COALESCE(v_object_type, 'UNKNOWN'),
                COALESCE(v_change_type, 'UNKNOWN'),
                v_history_record.sql_executed,
                COALESCE(v_history_record.created_by, 'unknown'),
                v_history_record.created_at,
                'Backfilled from v1: ' || COALESCE(v_history_record.change_description, 'Unknown change'),
                true,
                false
            );

            v_processed_count := v_processed_count + 1;

        EXCEPTION WHEN OTHERS THEN
            v_error_count := v_error_count + 1;
            RAISE WARNING 'Error processing history record %: %', v_history_record.id, SQLERRM;
        END;
    END LOOP;

    RETURN QUERY SELECT v_processed_count, v_error_count, v_warning_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

-- Function: Determine object type from DDL content
CREATE OR REPLACE FUNCTION pggit_audit.determine_object_type(
    p_ddl_content TEXT
) RETURNS TEXT AS $$
DECLARE
    v_upper_ddl TEXT;
BEGIN
    IF p_ddl_content IS NULL THEN
        RETURN 'UNKNOWN';
    END IF;

    v_upper_ddl := upper(trim(p_ddl_content));

    -- Comprehensive object type detection
    RETURN CASE
        WHEN v_upper_ddl LIKE 'CREATE TABLE%' THEN 'TABLE'
        WHEN v_upper_ddl LIKE 'CREATE OR REPLACE FUNCTION%' THEN 'FUNCTION'
        WHEN v_upper_ddl LIKE 'CREATE FUNCTION%' THEN 'FUNCTION'
        WHEN v_upper_ddl LIKE 'CREATE OR REPLACE PROCEDURE%' THEN 'PROCEDURE'
        WHEN v_upper_ddl LIKE 'CREATE PROCEDURE%' THEN 'PROCEDURE'
        WHEN v_upper_ddl LIKE 'CREATE OR REPLACE VIEW%' THEN 'VIEW'
        WHEN v_upper_ddl LIKE 'CREATE VIEW%' THEN 'VIEW'
        WHEN v_upper_ddl LIKE 'CREATE MATERIALIZED VIEW%' THEN 'MATERIALIZED_VIEW'
        WHEN v_upper_ddl LIKE 'CREATE UNIQUE INDEX%' THEN 'INDEX'
        WHEN v_upper_ddl LIKE 'CREATE INDEX%' THEN 'INDEX'
        WHEN v_upper_ddl LIKE 'CREATE TYPE%' THEN 'TYPE'
        WHEN v_upper_ddl LIKE 'CREATE SEQUENCE%' THEN 'SEQUENCE'
        WHEN v_upper_ddl LIKE 'CREATE TRIGGER%' THEN 'TRIGGER'
        WHEN v_upper_ddl LIKE 'CREATE SCHEMA%' THEN 'SCHEMA'
        WHEN v_upper_ddl LIKE 'CREATE EXTENSION%' THEN 'EXTENSION'
        ELSE 'UNKNOWN'
    END;
END;
$$ LANGUAGE plpgsql;

-- Function: Validate change record completeness
CREATE OR REPLACE FUNCTION pggit_audit.validate_change_record(
    p_change_id UUID
) RETURNS TABLE (
    validation_result TEXT,
    issues TEXT[]
) AS $$
DECLARE
    v_issues TEXT[] := '{}';
    v_change RECORD;
BEGIN
    -- Get change record
    SELECT * INTO v_change
    FROM pggit_audit.changes
    WHERE change_id = p_change_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'NOT_FOUND'::TEXT, ARRAY['Change record does not exist'];
        RETURN;
    END IF;

    -- Validate required fields
    IF v_change.object_schema IS NULL OR v_change.object_schema = '' THEN
        v_issues := array_append(v_issues, 'Missing or empty object_schema');
    END IF;

    IF v_change.object_name IS NULL OR v_change.object_name = '' THEN
        v_issues := array_append(v_issues, 'Missing or empty object_name');
    END IF;

    IF v_change.object_type IS NULL OR v_change.object_type = '' THEN
        v_issues := array_append(v_issues, 'Missing or empty object_type');
    END IF;

    IF v_change.change_type IS NULL OR v_change.change_type = '' THEN
        v_issues := array_append(v_issues, 'Missing or empty change_type');
    END IF;

    -- Validate change_type logic
    IF v_change.change_type = 'CREATE' AND v_change.old_definition IS NOT NULL THEN
        v_issues := array_append(v_issues, 'CREATE operations should not have old_definition');
    END IF;

    IF v_change.change_type = 'DROP' AND v_change.new_definition IS NOT NULL THEN
        v_issues := array_append(v_issues, 'DROP operations should not have new_definition');
    END IF;

    IF v_change.change_type = 'ALTER' AND (v_change.old_definition IS NULL OR v_change.new_definition IS NULL) THEN
        v_issues := array_append(v_issues, 'ALTER operations should have both old_definition and new_definition');
    END IF;

    -- Validate commit_sha references
    IF v_change.commit_sha != 'unknown' THEN
        IF NOT EXISTS (SELECT 1 FROM pggit_v0.objects WHERE sha = v_change.commit_sha AND type = 'commit') THEN
            v_issues := array_append(v_issues, 'commit_sha does not reference a valid pggit_v0 commit');
        END IF;
    END IF;

    -- Return validation result
    IF array_length(v_issues, 1) IS NULL THEN
        RETURN QUERY SELECT 'VALID'::TEXT, v_issues;
    ELSE
        RETURN QUERY SELECT 'INVALID'::TEXT, v_issues;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function: Get DDL for object at specific commit
CREATE OR REPLACE FUNCTION pggit_audit.get_object_ddl_at_commit(
    p_commit_sha TEXT,
    p_schema_name TEXT,
    p_object_name TEXT
) RETURNS TEXT AS $$
DECLARE
    v_tree_sha TEXT;
    v_blob_sha TEXT;
    v_ddl TEXT;
BEGIN
    -- Get tree SHA for commit
    SELECT tree_sha INTO v_tree_sha
    FROM pggit_v0.commit_graph
    WHERE commit_sha = p_commit_sha;

    IF v_tree_sha IS NULL THEN
        RETURN NULL;
    END IF;

    -- Get blob SHA for object
    SELECT object_sha INTO v_blob_sha
    FROM pggit_v0.tree_entries
    WHERE tree_sha = v_tree_sha
      AND path = p_schema_name || '.' || p_object_name;

    IF v_blob_sha IS NULL THEN
        RETURN NULL;
    END IF;

    -- Get DDL content
    SELECT content INTO v_ddl
    FROM pggit_v0.objects
    WHERE sha = v_blob_sha AND type = 'blob';

    RETURN v_ddl;
END;
$$ LANGUAGE plpgsql;

-- Function: Compare object versions between commits
CREATE OR REPLACE FUNCTION pggit_audit.compare_object_versions(
    p_old_commit_sha TEXT,
    p_new_commit_sha TEXT,
    p_schema_name TEXT,
    p_object_name TEXT
) RETURNS TABLE (
    old_ddl TEXT,
    new_ddl TEXT,
    has_changes BOOLEAN
) AS $$
DECLARE
    v_old_ddl TEXT;
    v_new_ddl TEXT;
BEGIN
    -- Get DDL at both commits
    v_old_ddl := pggit_audit.get_object_ddl_at_commit(p_old_commit_sha, p_schema_name, p_object_name);
    v_new_ddl := pggit_audit.get_object_ddl_at_commit(p_new_commit_sha, p_schema_name, p_object_name);

    RETURN QUERY
    SELECT
        v_old_ddl,
        v_new_ddl,
        (v_old_ddl IS DISTINCT FROM v_new_ddl);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- BATCH PROCESSING FUNCTIONS
-- ============================================

-- Function: Extract and store changes for a commit range with validation
CREATE OR REPLACE FUNCTION pggit_audit.process_commit_range(
    p_old_commit_sha TEXT,
    p_new_commit_sha TEXT,
    p_validate_changes BOOLEAN DEFAULT true
) RETURNS TABLE (
    changes_processed INT,
    validation_errors INT,
    validation_warnings INT
) AS $$
DECLARE
    v_change_count INT := 0;
    v_validation_errors INT := 0;
    v_validation_warnings INT := 0;
    v_change_record RECORD;
    v_validation_result RECORD;
BEGIN
    -- Insert extracted changes into audit tables
    FOR v_change_record IN
        SELECT * FROM pggit_audit.extract_changes_between_commits(p_old_commit_sha, p_new_commit_sha)
    LOOP
        -- Insert the change record
        INSERT INTO pggit_audit.changes (
            change_id, commit_sha, object_schema, object_name, object_type,
            change_type, old_definition, new_definition,
            author, committed_at, commit_message
        ) VALUES (
            v_change_record.change_id, v_change_record.commit_sha,
            v_change_record.object_schema, v_change_record.object_name, v_change_record.object_type,
            v_change_record.change_type, v_change_record.old_definition, v_change_record.new_definition,
            v_change_record.author, v_change_record.committed_at, v_change_record.commit_message
        );

        v_change_count := v_change_count + 1;

        -- Validate if requested
        IF p_validate_changes THEN
            SELECT * INTO v_validation_result
            FROM pggit_audit.validate_change_record(v_change_record.change_id);

            IF v_validation_result.validation_result = 'INVALID' THEN
                v_validation_errors := v_validation_errors + 1;
                -- Log validation errors but don't fail the operation
                RAISE WARNING 'Validation failed for change %: %', v_change_record.change_id, array_to_string(v_validation_result.issues, ', ');
            END IF;
        END IF;
    END LOOP;

    RETURN QUERY SELECT v_change_count, v_validation_errors, v_validation_warnings;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- VALIDATION FUNCTIONS
-- ============================================

-- Function: Validate audit data integrity (comprehensive)
CREATE OR REPLACE FUNCTION pggit_audit.validate_audit_integrity()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT,
    severity TEXT
) AS $$
BEGIN
    -- Check 1: All changes have valid commit SHAs (except 'unknown' for backfilled)
    RETURN QUERY
    SELECT
        'commit_sha_references'::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'WARN'
        END,
        format('Found %s changes with invalid commit SHAs', COUNT(*))::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'LOW'
            ELSE 'MEDIUM'
        END
    FROM pggit_audit.changes c
    WHERE c.commit_sha != 'unknown'
      AND NOT EXISTS (SELECT 1 FROM pggit_v0.objects WHERE sha = c.commit_sha AND type = 'commit');

    -- Check 2: No orphaned compliance logs
    RETURN QUERY
    SELECT
        'compliance_log_references'::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END,
        format('Found %s orphaned compliance log entries', COUNT(*))::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'LOW'
            ELSE 'HIGH'
        END
    FROM pggit_audit.compliance_log cl
    LEFT JOIN pggit_audit.changes c ON c.change_id = cl.change_id
    WHERE c.change_id IS NULL;

    -- Check 3: Object versions are sequential
    RETURN QUERY
    SELECT
        'object_version_sequence'::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END,
        format('Found %s objects with non-sequential version numbers', COUNT(DISTINCT object_schema || '.' || object_name))::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'LOW'
            ELSE 'HIGH'
        END
    FROM (
        SELECT
            object_schema,
            object_name,
            version_number,
            LAG(version_number) OVER (PARTITION BY object_schema, object_name ORDER BY version_number) as prev_version
        FROM pggit_audit.object_versions
    ) v
    WHERE v.version_number != v.prev_version + 1
      AND v.prev_version IS NOT NULL;

    -- Check 4: All changes have required fields
    RETURN QUERY
    SELECT
        'required_fields'::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END,
        format('Found %s changes with missing required fields', COUNT(*))::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'LOW'
            ELSE 'HIGH'
        END
    FROM pggit_audit.changes
    WHERE object_schema IS NULL OR object_schema = ''
       OR object_name IS NULL OR object_name = ''
       OR object_type IS NULL OR object_type = ''
       OR change_type IS NULL OR change_type = '';

    -- Check 5: Change type consistency
    RETURN QUERY
    SELECT
        'change_type_consistency'::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'WARN'
        END,
        format('Found %s changes with inconsistent old/new definition patterns', COUNT(*))::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'LOW'
            ELSE 'MEDIUM'
        END
    FROM pggit_audit.changes
    WHERE (change_type = 'CREATE' AND old_definition IS NOT NULL)
       OR (change_type = 'DROP' AND new_definition IS NOT NULL)
       OR (change_type = 'ALTER' AND (old_definition IS NULL OR new_definition IS NULL));

    -- Check 6: Backfilled data quality
    RETURN QUERY
    SELECT
        'backfilled_data_quality'::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'WARN'
        END,
        format('Found %s backfilled changes with unknown object info', COUNT(*))::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'LOW'
            ELSE 'MEDIUM'
        END
    FROM pggit_audit.changes
    WHERE backfilled_from_v1 = true
      AND (object_schema = 'unknown' OR object_name = 'unknown' OR object_type = 'UNKNOWN');

    -- Check 7: Compliance log immutability
    RETURN QUERY
    SELECT
        'compliance_log_immutability'::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END,
        format('Found %s compliance log entries that should be immutable', COUNT(*))::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'LOW'
            ELSE 'CRITICAL'
        END
    FROM pggit_audit.compliance_log
    WHERE created_at != verified_at;  -- This is a basic check; real immutability is enforced by trigger

END;
$$ LANGUAGE plpgsql;

-- ============================================
-- METADATA
-- ============================================

-- Function: Generate audit summary report
CREATE OR REPLACE FUNCTION pggit_audit.generate_audit_report(
    p_start_date TIMESTAMP DEFAULT NULL,
    p_end_date TIMESTAMP DEFAULT NULL
) RETURNS TABLE (
    metric TEXT,
    value TEXT,
    details TEXT
) AS $$
DECLARE
    v_start_date TIMESTAMP := COALESCE(p_start_date, CURRENT_TIMESTAMP - INTERVAL '30 days');
    v_end_date TIMESTAMP := COALESCE(p_end_date, CURRENT_TIMESTAMP);
BEGIN
    -- Total changes in period
    RETURN QUERY
    SELECT
        'total_changes'::TEXT,
        COUNT(*)::TEXT,
        format('Changes between %s and %s', v_start_date, v_end_date)::TEXT
    FROM pggit_audit.changes
    WHERE committed_at BETWEEN v_start_date AND v_end_date;

    -- Changes by type
    RETURN QUERY
    SELECT
        'changes_by_type'::TEXT,
        change_type || ': ' || COUNT(*)::TEXT,
        'Breakdown of change types'::TEXT
    FROM pggit_audit.changes
    WHERE committed_at BETWEEN v_start_date AND v_end_date
    GROUP BY change_type
    ORDER BY COUNT(*) DESC;

    -- Objects by type
    RETURN QUERY
    SELECT
        'objects_by_type'::TEXT,
        object_type || ': ' || COUNT(*)::TEXT,
        'Breakdown of object types'::TEXT
    FROM pggit_audit.changes
    WHERE committed_at BETWEEN v_start_date AND v_end_date
    GROUP BY object_type
    ORDER BY COUNT(*) DESC;

    -- Verification status
    RETURN QUERY
    SELECT
        'verification_status'::TEXT,
        CASE WHEN verified THEN 'verified' ELSE 'unverified' END || ': ' || COUNT(*)::TEXT,
        'Verification completeness'::TEXT
    FROM pggit_audit.changes
    WHERE committed_at BETWEEN v_start_date AND v_end_date
    GROUP BY verified;

    -- Backfilled vs native changes
    RETURN QUERY
    SELECT
        'change_source'::TEXT,
        CASE WHEN backfilled_from_v1 THEN 'backfilled' ELSE 'native' END || ': ' || COUNT(*)::TEXT,
        'Source of changes'::TEXT
    FROM pggit_audit.changes
    WHERE committed_at BETWEEN v_start_date AND v_end_date
    GROUP BY backfilled_from_v1;

    -- Top contributors
    RETURN QUERY
    SELECT
        'top_contributors'::TEXT,
        COALESCE(author, 'unknown') || ': ' || COUNT(*)::TEXT,
        'Most active authors'::TEXT
    FROM pggit_audit.changes
    WHERE committed_at BETWEEN v_start_date AND v_end_date
    GROUP BY author
    ORDER BY COUNT(*) DESC
    LIMIT 5;

END;
$$ LANGUAGE plpgsql;

-- Function: Cleanup old audit data (with retention policy)
CREATE OR REPLACE FUNCTION pggit_audit.cleanup_old_audit_data(
    p_retention_days INT DEFAULT 365,
    p_dry_run BOOLEAN DEFAULT true
) RETURNS TABLE (
    operation TEXT,
    records_affected INT,
    details TEXT
) AS $$
DECLARE
    v_cutoff_date TIMESTAMP := CURRENT_TIMESTAMP - (p_retention_days || ' days')::INTERVAL;
    v_changes_count INT := 0;
    v_versions_count INT := 0;
    v_compliance_count INT := 0;
BEGIN
    -- Count records that would be affected
    SELECT COUNT(*) INTO v_changes_count
    FROM pggit_audit.changes
    WHERE committed_at < v_cutoff_date
      AND verified = true  -- Only cleanup verified old data
      AND backfilled_from_v1 = true;  -- Prefer to keep native changes

    SELECT COUNT(*) INTO v_versions_count
    FROM pggit_audit.object_versions
    WHERE created_at < v_cutoff_date;

    SELECT COUNT(*) INTO v_compliance_count
    FROM pggit_audit.compliance_log
    WHERE verified_at < v_cutoff_date;

    -- Report what would be cleaned up
    RETURN QUERY SELECT 'changes_to_cleanup'::TEXT, v_changes_count, format('Changes older than %s days', p_retention_days)::TEXT;
    RETURN QUERY SELECT 'versions_to_cleanup'::TEXT, v_versions_count, format('Object versions older than %s days', p_retention_days)::TEXT;
    RETURN QUERY SELECT 'compliance_to_cleanup'::TEXT, v_compliance_count, format('Compliance logs older than %s days', p_retention_days)::TEXT;

    -- Perform cleanup if not dry run
    IF NOT p_dry_run THEN
        -- Note: This is simplified - real implementation would need transaction handling
        -- and careful consideration of referential integrity
        DELETE FROM pggit_audit.compliance_log WHERE verified_at < v_cutoff_date;
        DELETE FROM pggit_audit.object_versions WHERE created_at < v_cutoff_date;
        DELETE FROM pggit_audit.changes
        WHERE committed_at < v_cutoff_date
          AND verified = true
          AND backfilled_from_v1 = true;

        RETURN QUERY SELECT 'cleanup_completed'::TEXT, v_changes_count + v_versions_count + v_compliance_count, 'Records removed'::TEXT;
    ELSE
        RETURN QUERY SELECT 'dry_run_mode'::TEXT, 0, 'No changes made - use dry_run=false to execute'::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit_audit.extract_changes_between_commits IS 'Extract DDL changes between two pggit_v0 commits';
COMMENT ON FUNCTION pggit_audit.backfill_from_v1_history IS 'Convert pggit v1 history to audit records';
COMMENT ON FUNCTION pggit_audit.get_object_ddl_at_commit IS 'Get DDL definition for object at specific commit';
COMMENT ON FUNCTION pggit_audit.compare_object_versions IS 'Compare object DDL between two commits';
COMMENT ON FUNCTION pggit_audit.process_commit_range IS 'Extract and store changes for commit range with validation';
COMMENT ON FUNCTION pggit_audit.validate_audit_integrity IS 'Validate audit data integrity comprehensively';
COMMENT ON FUNCTION pggit_audit.determine_object_type IS 'Determine object type from DDL content';
COMMENT ON FUNCTION pggit_audit.validate_change_record IS 'Validate completeness of change record';
COMMENT ON FUNCTION pggit_audit.generate_audit_report IS 'Generate comprehensive audit summary report';
COMMENT ON FUNCTION pggit_audit.cleanup_old_audit_data IS 'Cleanup old audit data with retention policy';