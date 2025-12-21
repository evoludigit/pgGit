-- ============================================
-- pgGit Audit Layer: Extraction Functions
-- ============================================
-- Functions to extract DDL changes from pggit_v2 commits

-- ============================================
-- EXTRACTION FUNCTIONS
-- ============================================

-- Function: Extract changes between two commits
-- This is the core function that analyzes pggit_v2 commits and extracts DDL changes
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
BEGIN
    -- Get tree SHAs from commits
    SELECT tree_sha INTO v_old_tree_sha
    FROM pggit_v2.commit_graph
    WHERE commit_sha = p_old_commit_sha;

    SELECT tree_sha INTO v_new_tree_sha
    FROM pggit_v2.commit_graph
    WHERE commit_sha = p_new_commit_sha;

    -- If old tree doesn't exist, treat as initial commit (all objects are CREATE)
    IF v_old_tree_sha IS NULL THEN
        -- Get all objects from new tree
        FOR v_change_record IN
            SELECT
                te.path,
                o.content as new_definition,
                cg.author,
                cg.committed_at,
                cg.message as commit_message
            FROM pggit_v2.tree_entries te
            JOIN pggit_v2.objects o ON o.sha = te.object_sha AND o.type = 'blob'
            JOIN pggit_v2.commit_graph cg ON cg.commit_sha = p_new_commit_sha
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
                CASE
                    WHEN v_change_record.new_definition LIKE 'CREATE TABLE%' THEN 'TABLE'
                    WHEN v_change_record.new_definition LIKE 'CREATE FUNCTION%' THEN 'FUNCTION'
                    WHEN v_change_record.new_definition LIKE 'CREATE VIEW%' THEN 'VIEW'
                    WHEN v_change_record.new_definition LIKE 'CREATE INDEX%' THEN 'INDEX'
                    ELSE 'UNKNOWN'
                END,
                'CREATE'::TEXT,
                NULL::TEXT,
                v_change_record.new_definition,
                v_change_record.author,
                v_change_record.committed_at,
                v_change_record.commit_message;
        END LOOP;
    ELSE
        -- Compare trees to find changes
        FOR v_change_record IN
            SELECT * FROM pggit_v2.diff_trees(v_old_tree_sha, v_new_tree_sha)
        LOOP
            v_new_change_id := gen_random_uuid();

            -- Get commit metadata
            SELECT author, committed_at, message INTO v_change_record.author, v_change_record.committed_at, v_change_record.commit_message
            FROM pggit_v2.commit_graph
            WHERE commit_sha = p_new_commit_sha;

            RETURN QUERY
            SELECT
                v_new_change_id,
                p_new_commit_sha,
                split_part(v_change_record.path, '.', 1),
                split_part(v_change_record.path, '.', 2),
                CASE
                    WHEN (SELECT content FROM pggit_v2.objects WHERE sha = COALESCE(v_change_record.new_sha, v_change_record.old_sha))
                         LIKE 'CREATE TABLE%' THEN 'TABLE'
                    WHEN (SELECT content FROM pggit_v2.objects WHERE sha = COALESCE(v_change_record.new_sha, v_change_record.old_sha))
                         LIKE 'CREATE FUNCTION%' THEN 'FUNCTION'
                    WHEN (SELECT content FROM pggit_v2.objects WHERE sha = COALESCE(v_change_record.new_sha, v_change_record.old_sha))
                         LIKE 'CREATE VIEW%' THEN 'VIEW'
                    WHEN (SELECT content FROM pggit_v2.objects WHERE sha = COALESCE(v_change_record.new_sha, v_change_record.old_sha))
                         LIKE 'CREATE INDEX%' THEN 'INDEX'
                    ELSE 'UNKNOWN'
                END,
                CASE
                    WHEN v_change_record.change_type = 'add' THEN 'CREATE'
                    WHEN v_change_record.change_type = 'delete' THEN 'DROP'
                    WHEN v_change_record.change_type = 'modify' THEN 'ALTER'
                END,
                CASE WHEN v_change_record.change_type IN ('modify', 'delete')
                     THEN (SELECT content FROM pggit_v2.objects WHERE sha = v_change_record.old_sha)
                     ELSE NULL
                END,
                CASE WHEN v_change_record.change_type IN ('modify', 'add')
                     THEN (SELECT content FROM pggit_v2.objects WHERE sha = v_change_record.new_sha)
                     ELSE NULL
                END,
                v_change_record.author,
                v_change_record.committed_at,
                v_change_record.commit_message;
        END LOOP;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function: Backfill audit data from v1 history
-- This function converts pggit v1 history to pggit_audit.changes records
CREATE OR REPLACE FUNCTION pggit_audit.backfill_from_v1_history()
RETURNS TABLE(processed INT, errors INT) AS $$
DECLARE
    v_history_record RECORD;
    v_processed_count INT := 0;
    v_error_count INT := 0;
    v_current_schema_state JSONB := '{}'::JSONB;
    v_change_id UUID;
BEGIN
    -- Process each v1 history record in chronological order
    FOR v_history_record IN
        SELECT * FROM pggit.history
        ORDER BY created_at, id
    LOOP
        BEGIN
            -- For now, create a simple audit record
            -- In production, this would analyze the DDL and create proper change records
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
                'unknown',  -- Would need to parse from DDL
                'unknown',  -- Would need to parse from DDL
                'UNKNOWN',  -- Would need to parse from DDL
                'UNKNOWN',  -- Would need to parse from DDL
                v_history_record.sql_executed,
                v_history_record.created_by,
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

    RETURN QUERY SELECT v_processed_count, v_error_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

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
    FROM pggit_v2.commit_graph
    WHERE commit_sha = p_commit_sha;

    IF v_tree_sha IS NULL THEN
        RETURN NULL;
    END IF;

    -- Get blob SHA for object
    SELECT object_sha INTO v_blob_sha
    FROM pggit_v2.tree_entries
    WHERE tree_sha = v_tree_sha
      AND path = p_schema_name || '.' || p_object_name;

    IF v_blob_sha IS NULL THEN
        RETURN NULL;
    END IF;

    -- Get DDL content
    SELECT content INTO v_ddl
    FROM pggit_v2.objects
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

-- Function: Extract and store changes for a commit range
CREATE OR REPLACE FUNCTION pggit_audit.process_commit_range(
    p_old_commit_sha TEXT,
    p_new_commit_sha TEXT
) RETURNS INTEGER AS $$
DECLARE
    v_change_count INT := 0;
BEGIN
    -- Insert extracted changes into audit tables
    INSERT INTO pggit_audit.changes (
        change_id, commit_sha, object_schema, object_name, object_type,
        change_type, old_definition, new_definition,
        author, committed_at, commit_message
    )
    SELECT
        change_id, commit_sha, object_schema, object_name, object_type,
        change_type, old_definition, new_definition,
        author, committed_at, commit_message
    FROM pggit_audit.extract_changes_between_commits(p_old_commit_sha, p_new_commit_sha);

    GET DIAGNOSTICS v_change_count = ROW_COUNT;
    RETURN v_change_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- VALIDATION FUNCTIONS
-- ============================================

-- Function: Validate audit data integrity
CREATE OR REPLACE FUNCTION pggit_audit.validate_audit_integrity()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT
) AS $$
BEGIN
    -- Check 1: All changes have valid commit SHAs
    RETURN QUERY
    SELECT
        'commit_sha_references'::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END,
        'All changes reference valid pggit_v2 commits'::TEXT
    FROM pggit_audit.changes c
    LEFT JOIN pggit_v2.objects o ON o.sha = c.commit_sha AND o.type = 'commit'
    WHERE o.sha IS NULL;

    -- Check 2: No orphaned compliance logs
    RETURN QUERY
    SELECT
        'compliance_log_references'::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END,
        'All compliance logs reference valid changes'::TEXT
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
        'Object versions are properly sequenced'::TEXT
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

END;
$$ LANGUAGE plpgsql;

-- ============================================
-- METADATA
-- ============================================

COMMENT ON FUNCTION pggit_audit.extract_changes_between_commits IS 'Extract DDL changes between two pggit_v2 commits';
COMMENT ON FUNCTION pggit_audit.backfill_from_v1_history IS 'Convert pggit v1 history to audit records';
COMMENT ON FUNCTION pggit_audit.get_object_ddl_at_commit IS 'Get DDL definition for object at specific commit';
COMMENT ON FUNCTION pggit_audit.compare_object_versions IS 'Compare object DDL between two commits';
COMMENT ON FUNCTION pggit_audit.process_commit_range IS 'Extract and store changes for commit range';
COMMENT ON FUNCTION pggit_audit.validate_audit_integrity IS 'Validate audit data integrity';