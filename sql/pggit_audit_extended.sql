-- ============================================
-- pgGit Audit Layer: Extended Extraction Functions
-- ============================================
-- Comprehensive DDL extraction for all database object types
-- Advanced parsing and dependency tracking

-- ============================================
-- ADVANCED OBJECT TYPE DETECTION
-- ============================================

-- Function: Advanced object type detection with context
CREATE OR REPLACE FUNCTION pggit_audit.advanced_determine_object_type(
    p_ddl_content TEXT,
    p_context_path TEXT DEFAULT NULL
) RETURNS TABLE (
    object_type TEXT,
    object_schema TEXT,
    object_name TEXT,
    confidence_level TEXT, -- HIGH, MEDIUM, LOW
    parsing_method TEXT    -- REGEX, CONTEXT, FALLBACK
) AS $$
DECLARE
    v_upper_ddl TEXT;
    v_matches TEXT[];
    v_schema TEXT := 'public';
    v_name TEXT;
    v_confidence TEXT := 'LOW';
    v_method TEXT := 'FALLBACK';
BEGIN
    IF p_ddl_content IS NULL THEN
        RETURN QUERY SELECT 'UNKNOWN'::TEXT, 'unknown'::TEXT, 'unknown'::TEXT, 'LOW'::TEXT, 'NULL_CONTENT'::TEXT;
        RETURN;
    END IF;

    v_upper_ddl := upper(trim(p_ddl_content));

    -- High confidence detections (explicit keywords)
    IF v_upper_ddl LIKE 'CREATE TABLE%' THEN
        v_matches := regexp_match(p_ddl_content, 'CREATE\s+TABLE\s+(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?', 'i');
        IF v_matches IS NOT NULL THEN
            v_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
            v_name := v_matches[4];
            v_confidence := 'HIGH';
            v_method := 'REGEX';
        END IF;

    ELSIF v_upper_ddl LIKE 'CREATE OR REPLACE FUNCTION%' OR v_upper_ddl LIKE 'CREATE FUNCTION%' THEN
        v_matches := regexp_match(p_ddl_content, 'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?\s*\(', 'i');
        IF v_matches IS NOT NULL THEN
            v_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
            v_name := v_matches[4];
            v_confidence := 'HIGH';
            v_method := 'REGEX';
        END IF;

    ELSIF v_upper_ddl LIKE 'CREATE VIEW%' THEN
        v_matches := regexp_match(p_ddl_content, 'CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?', 'i');
        IF v_matches IS NOT NULL THEN
            v_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
            v_name := v_matches[4];
            v_confidence := 'HIGH';
            v_method := 'REGEX';
        END IF;

    ELSIF v_upper_ddl LIKE 'CREATE INDEX%' THEN
        v_matches := regexp_match(p_ddl_content, 'CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?', 'i');
        IF v_matches IS NOT NULL THEN
            v_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
            v_name := v_matches[4];
            v_confidence := 'HIGH';
            v_method := 'REGEX';
        END IF;

    ELSIF v_upper_ddl LIKE 'CREATE SEQUENCE%' THEN
        v_matches := regexp_match(p_ddl_content, 'CREATE\s+SEQUENCE\s+(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?', 'i');
        IF v_matches IS NOT NULL THEN
            v_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
            v_name := v_matches[4];
            v_confidence := 'HIGH';
            v_method := 'REGEX';
        END IF;

    ELSIF v_upper_ddl LIKE 'CREATE TYPE%' THEN
        v_matches := regexp_match(p_ddl_content, 'CREATE\s+TYPE\s+(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?', 'i');
        IF v_matches IS NOT NULL THEN
            v_schema := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public');
            v_name := v_matches[4];
            v_confidence := 'HIGH';
            v_method := 'REGEX';
        END IF;

    ELSIF v_upper_ddl LIKE 'CREATE TRIGGER%' THEN
        v_matches := regexp_match(p_ddl_content, 'CREATE\s+TRIGGER\s+(\w+)', 'i');
        IF v_matches IS NOT NULL THEN
            v_name := v_matches[1];
            v_confidence := 'HIGH';
            v_method := 'REGEX';
        END IF;

    -- Medium confidence detections (context-dependent)
    ELSIF p_context_path IS NOT NULL THEN
        -- Use path context for additional hints
        IF p_context_path LIKE '%.%' THEN
            v_schema := split_part(p_context_path, '.', 1);
            v_name := split_part(p_context_path, '.', 2);
            v_confidence := 'MEDIUM';
            v_method := 'CONTEXT';
        END IF;

        -- Try to infer from DDL keywords even without full regex match
        IF v_upper_ddl LIKE '%TABLE%' AND v_upper_ddl LIKE '%CONSTRAINT%' THEN
            RETURN QUERY SELECT 'CONSTRAINT'::TEXT, v_schema, v_name, 'MEDIUM'::TEXT, 'CONTEXT_INFERENCE'::TEXT;
            RETURN;
        END IF;

    END IF;

    -- Fallback: use basic detection
    DECLARE
        v_basic_type TEXT;
    BEGIN
        v_basic_type := pggit_audit.determine_object_type(p_ddl_content);
        IF v_basic_type != 'UNKNOWN' THEN
            v_confidence := 'MEDIUM';
            v_method := 'BASIC_FALLBACK';
        END IF;

        RETURN QUERY SELECT v_basic_type, v_schema, COALESCE(v_name, 'unknown'), v_confidence, v_method;
    END;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- COMPLEX DDL PARSING
-- ============================================

-- Function: Parse complex ALTER statements
CREATE OR REPLACE FUNCTION pggit_audit.parse_alter_statement(
    p_ddl_content TEXT
) RETURNS TABLE (
    operation_type TEXT,     -- ADD, DROP, ALTER, RENAME, etc.
    object_type TEXT,        -- COLUMN, CONSTRAINT, INDEX, etc.
    object_name TEXT,        -- Name of the affected object
    definition TEXT,         -- The DDL fragment
    parent_object TEXT       -- The table/view being altered
) AS $$
DECLARE
    v_upper_ddl TEXT;
    v_table_name TEXT;
    v_matches TEXT[];
BEGIN
    v_upper_ddl := upper(trim(p_ddl_content));

    -- Extract table name
    v_matches := regexp_match(p_ddl_content, 'ALTER\s+TABLE\s+(?:"([^"]+)"\.|"([^"]+)"\.|(\w+)\.)?"?(\w+)"?', 'i');
    IF v_matches IS NOT NULL THEN
        v_table_name := COALESCE(v_matches[1], v_matches[2], v_matches[3], 'public') || '.' || v_matches[4];
    ELSE
        -- Not a table ALTER, return empty
        RETURN;
    END IF;

    -- Parse ADD COLUMN
    IF v_upper_ddl LIKE '%ADD%COLUMN%' THEN
        v_matches := regexp_match(p_ddl_content, 'ADD\s+COLUMN\s+(\w+)', 'i');
        IF v_matches IS NOT NULL THEN
            RETURN QUERY SELECT 'ADD'::TEXT, 'COLUMN'::TEXT, v_matches[1], p_ddl_content, v_table_name;
        END IF;

    -- Parse DROP COLUMN
    ELSIF v_upper_ddl LIKE '%DROP%COLUMN%' THEN
        v_matches := regexp_match(p_ddl_content, 'DROP\s+COLUMN\s+(?:(?:IF\s+EXISTS\s+)?(\w+))', 'i');
        IF v_matches IS NOT NULL THEN
            RETURN QUERY SELECT 'DROP'::TEXT, 'COLUMN'::TEXT, v_matches[1], p_ddl_content, v_table_name;
        END IF;

    -- Parse ALTER COLUMN
    ELSIF v_upper_ddl LIKE '%ALTER%COLUMN%' THEN
        v_matches := regexp_match(p_ddl_content, 'ALTER\s+COLUMN\s+(\w+)', 'i');
        IF v_matches IS NOT NULL THEN
            RETURN QUERY SELECT 'ALTER'::TEXT, 'COLUMN'::TEXT, v_matches[1], p_ddl_content, v_table_name;
        END IF;

    -- Parse ADD CONSTRAINT
    ELSIF v_upper_ddl LIKE '%ADD%CONSTRAINT%' THEN
        v_matches := regexp_match(p_ddl_content, 'ADD\s+CONSTRAINT\s+(\w+)', 'i');
        IF v_matches IS NOT NULL THEN
            RETURN QUERY SELECT 'ADD'::TEXT, 'CONSTRAINT'::TEXT, v_matches[1], p_ddl_content, v_table_name;
        END IF;

    -- Parse DROP CONSTRAINT
    ELSIF v_upper_ddl LIKE '%DROP%CONSTRAINT%' THEN
        v_matches := regexp_match(p_ddl_content, 'DROP\s+CONSTRAINT\s+(?:(?:IF\s+EXISTS\s+)?(\w+))', 'i');
        IF v_matches IS NOT NULL THEN
            RETURN QUERY SELECT 'DROP'::TEXT, 'CONSTRAINT'::TEXT, v_matches[1], p_ddl_content, v_table_name;
        END IF;

    -- Parse RENAME
    ELSIF v_upper_ddl LIKE '%RENAME%' THEN
        IF v_upper_ddl LIKE '%RENAME%COLUMN%' THEN
            v_matches := regexp_match(p_ddl_content, 'RENAME\s+COLUMN\s+(\w+)\s+TO\s+(\w+)', 'i');
            IF v_matches IS NOT NULL THEN
                RETURN QUERY SELECT 'RENAME'::TEXT, 'COLUMN'::TEXT, v_matches[1] || '->' || v_matches[2], p_ddl_content, v_table_name;
            END IF;
        ELSIF v_upper_ddl LIKE '%RENAME%TO%' THEN
            v_matches := regexp_match(p_ddl_content, 'RENAME\s+TO\s+(\w+)', 'i');
            IF v_matches IS NOT NULL THEN
                RETURN QUERY SELECT 'RENAME'::TEXT, 'TABLE'::TEXT, v_matches[1], p_ddl_content, v_table_name;
            END IF;
        END IF;

    -- Default: return the whole statement as ALTER
    ELSE
        RETURN QUERY SELECT 'ALTER'::TEXT, 'TABLE'::TEXT, '', p_ddl_content, v_table_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- DEPENDENCY TRACKING
-- ============================================

-- Function: Analyze object dependencies
CREATE OR REPLACE FUNCTION pggit_audit.analyze_dependencies(
    p_schema_name TEXT,
    p_object_name TEXT,
    p_object_type TEXT
) RETURNS TABLE (
    dependency_type TEXT,    -- DEPENDS_ON, DEPENDED_BY
    related_schema TEXT,
    related_object TEXT,
    related_type TEXT,
    dependency_reason TEXT
) AS $$
BEGIN
    -- For tables: find dependent objects
    IF upper(p_object_type) = 'TABLE' THEN
        -- Indexes on this table
        RETURN QUERY
        SELECT
            'DEPENDED_BY'::TEXT,
            i.schemaname,
            i.indexrelname,
            'INDEX'::TEXT,
            'Index on table'::TEXT
        FROM pg_stat_user_indexes i
        WHERE i.schemaname = p_schema_name
          AND i.relname = p_object_name;

        -- Triggers on this table
        RETURN QUERY
        SELECT
            'DEPENDED_BY'::TEXT,
            t.event_object_schema,
            t.trigger_name,
            'TRIGGER'::TEXT,
            'Trigger on table'::TEXT
        FROM information_schema.triggers t
        WHERE t.event_object_schema = p_schema_name
          AND t.event_object_table = p_object_name;

        -- Constraints on this table
        RETURN QUERY
        SELECT
            'DEPENDED_BY'::TEXT,
            tc.table_schema,
            tc.constraint_name,
            'CONSTRAINT'::TEXT,
            'Constraint on table'::TEXT
        FROM information_schema.table_constraints tc
        WHERE tc.table_schema = p_schema_name
          AND tc.table_name = p_object_name;

    -- For functions: find what they depend on (basic analysis)
    ELSIF upper(p_object_type) = 'FUNCTION' THEN
        -- This would require parsing function source code
        -- For now, return empty (could be extended)
        NULL;

    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- EXTENDED EXTRACTION FUNCTIONS
-- ============================================

-- Function: Extended change extraction with full object support
CREATE OR REPLACE FUNCTION pggit_audit.extract_changes_extended(
    p_old_commit_sha TEXT,
    p_new_commit_sha TEXT,
    p_include_dependencies BOOLEAN DEFAULT false
) RETURNS TABLE (
    change_id UUID,
    commit_sha TEXT,
    object_schema TEXT,
    object_name TEXT,
    object_type TEXT,
    change_type TEXT,
    operation_type TEXT,    -- For complex operations
    parent_object TEXT,     -- For dependent objects
    old_definition TEXT,
    new_definition TEXT,
    dependencies JSONB,     -- Related objects affected
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
    v_dependencies JSONB;
    v_alter_operations RECORD;
BEGIN
    -- Validate inputs
    IF p_old_commit_sha IS NULL OR p_new_commit_sha IS NULL THEN
        RAISE EXCEPTION 'Commit SHAs cannot be NULL';
    END IF;

    -- Get tree SHAs with validation
    SELECT tree_sha INTO v_old_tree_sha
    FROM pggit_v2.commit_graph
    WHERE commit_sha = p_old_commit_sha;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Old commit SHA % not found in pggit_v2.commit_graph', p_old_commit_sha;
    END IF;

    SELECT tree_sha INTO v_new_tree_sha
    FROM pggit_v2.commit_graph
    WHERE commit_sha = p_new_commit_sha;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'New commit SHA % not found in pggit_v2.commit_graph', p_new_commit_sha;
    END IF;

    -- Get commit metadata
    SELECT author, committed_at, message INTO v_commit_author, v_commit_timestamp, v_commit_message
    FROM pggit_v2.commit_graph
    WHERE commit_sha = p_new_commit_sha;

    -- Handle initial commit (all objects are CREATE)
    IF v_old_tree_sha IS NULL THEN
        FOR v_change_record IN
            SELECT
                te.path,
                o.content as new_definition
            FROM pggit_v2.tree_entries te
            JOIN pggit_v2.objects o ON o.sha = te.object_sha AND o.type = 'blob'
            WHERE te.tree_sha = v_new_tree_sha
        LOOP
            v_new_change_id := gen_random_uuid();

            -- Get dependencies if requested
            IF p_include_dependencies THEN
                SELECT jsonb_agg(jsonb_build_object(
                    'type', dep.dependency_type,
                    'schema', dep.related_schema,
                    'object', dep.related_object,
                    'object_type', dep.related_type,
                    'reason', dep.dependency_reason
                ))
                INTO v_dependencies
                FROM pggit_audit.analyze_dependencies(
                    split_part(v_change_record.path, '.', 1),
                    split_part(v_change_record.path, '.', 2),
                    'UNKNOWN'  -- Will be determined below
                ) dep;
            END IF;

            RETURN QUERY
            SELECT
                v_new_change_id,
                p_new_commit_sha,
                split_part(v_change_record.path, '.', 1),
                split_part(v_change_record.path, '.', 2),
                (SELECT object_type FROM pggit_audit.advanced_determine_object_type(v_change_record.new_definition, v_change_record.path) LIMIT 1),
                'CREATE'::TEXT,
                NULL::TEXT,  -- operation_type
                NULL::TEXT,  -- parent_object
                NULL::TEXT,  -- old_definition
                v_change_record.new_definition,
                COALESCE(v_dependencies, '[]'::JSONB),
                v_commit_author,
                v_commit_timestamp,
                v_commit_message;
        END LOOP;
    ELSE
        -- Process tree differences
        FOR v_change_record IN
            SELECT * FROM pggit_v2.diff_trees(v_old_tree_sha, v_new_tree_sha)
        LOOP
            v_new_change_id := gen_random_uuid();
            v_dependencies := '[]'::JSONB;

            -- Analyze the DDL for complex operations
            SELECT * INTO v_alter_operations
            FROM pggit_audit.parse_alter_statement(
                COALESCE(
                    (SELECT content FROM pggit_v2.objects WHERE sha = v_change_record.new_sha),
                    (SELECT content FROM pggit_v2.objects WHERE sha = v_change_record.old_sha)
                )
            )
            LIMIT 1;

            -- Get dependencies if requested
            IF p_include_dependencies AND v_alter_operations.operation_type IS NOT NULL THEN
                SELECT jsonb_agg(jsonb_build_object(
                    'operation', dep.operation_type,
                    'object_type', dep.object_type,
                    'object_name', dep.object_name,
                    'definition', dep.definition,
                    'parent', dep.parent_object
                ))
                INTO v_dependencies
                FROM pggit_audit.parse_alter_statement(
                    COALESCE(
                        (SELECT content FROM pggit_v2.objects WHERE sha = v_change_record.new_sha),
                        (SELECT content FROM pggit_v2.objects WHERE sha = v_change_record.old_sha)
                    )
                ) dep;
            END IF;

            RETURN QUERY
            SELECT
                v_new_change_id,
                p_new_commit_sha,
                split_part(v_change_record.path, '.', 1),
                split_part(v_change_record.path, '.', 2),
                (SELECT object_type FROM pggit_audit.advanced_determine_object_type(
                    COALESCE(
                        (SELECT content FROM pggit_v2.objects WHERE sha = v_change_record.new_sha),
                        (SELECT content FROM pggit_v2.objects WHERE sha = v_change_record.old_sha)
                    ),
                    v_change_record.path
                ) LIMIT 1),
                CASE
                    WHEN v_change_record.change_type = 'add' THEN 'CREATE'
                    WHEN v_change_record.change_type = 'delete' THEN 'DROP'
                    WHEN v_change_record.change_type = 'modify' THEN 'ALTER'
                    ELSE 'UNKNOWN'
                END,
                v_alter_operations.operation_type,
                v_alter_operations.parent_object,
                CASE WHEN v_change_record.change_type IN ('modify', 'delete')
                     THEN (SELECT content FROM pggit_v2.objects WHERE sha = v_change_record.old_sha)
                     ELSE NULL
                END,
                CASE WHEN v_change_record.change_type IN ('modify', 'add')
                     THEN (SELECT content FROM pggit_v2.objects WHERE sha = v_change_record.new_sha)
                     ELSE NULL
                END,
                v_dependencies,
                v_commit_author,
                v_commit_timestamp,
                v_commit_message;
        END LOOP;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- COMPREHENSIVE TESTING FRAMEWORK
-- ============================================

-- Function: Test DDL parsing with various scenarios
CREATE OR REPLACE FUNCTION pggit_audit.test_ddl_parsing()
RETURNS TABLE (
    test_case TEXT,
    ddl_input TEXT,
    expected_type TEXT,
    actual_type TEXT,
    expected_schema TEXT,
    actual_schema TEXT,
    expected_name TEXT,
    actual_name TEXT,
    result TEXT
) AS $$
DECLARE
    v_result RECORD;
BEGIN
    -- Test case 1: Basic table
    SELECT * INTO v_result
    FROM pggit_audit.advanced_determine_object_type('CREATE TABLE users (id INT);', 'public.users')
    LIMIT 1;

    RETURN QUERY SELECT
        'Basic table'::TEXT,
        'CREATE TABLE users (id INT);'::TEXT,
        'TABLE'::TEXT,
        v_result.object_type,
        'public'::TEXT,
        v_result.object_schema,
        'users'::TEXT,
        v_result.object_name,
        CASE WHEN v_result.object_type = 'TABLE' AND v_result.object_schema = 'public' AND v_result.object_name = 'users'
             THEN 'PASS' ELSE 'FAIL' END;

    -- Test case 2: Schema-qualified function
    SELECT * INTO v_result
    FROM pggit_audit.advanced_determine_object_type('CREATE FUNCTION auth.get_user(id INTEGER) RETURNS TEXT AS $tag$ SELECT 1 $tag$ LANGUAGE sql;', 'auth.get_user')
    LIMIT 1;

    RETURN QUERY SELECT
        'Schema-qualified function'::TEXT,
        'CREATE FUNCTION auth.get_user(id INTEGER) RETURNS TEXT AS $tag$ SELECT 1 $tag$ LANGUAGE sql;'::TEXT,
        'FUNCTION'::TEXT,
        v_result.object_type,
        'auth'::TEXT,
        v_result.object_schema,
        'get_user'::TEXT,
        v_result.object_name,
        CASE WHEN v_result.object_type = 'FUNCTION' AND v_result.object_schema = 'auth' AND v_result.object_name = 'get_user'
             THEN 'PASS' ELSE 'FAIL' END;

    -- Test case 3: Complex ALTER statement
    SELECT * INTO v_result
    FROM pggit_audit.parse_alter_statement('ALTER TABLE users ADD COLUMN email TEXT NOT NULL DEFAULT '''';')
    LIMIT 1;

    RETURN QUERY SELECT
        'Complex ALTER'::TEXT,
        'ALTER TABLE users ADD COLUMN email TEXT NOT NULL DEFAULT '''';'::TEXT,
        'ADD'::TEXT,
        v_result.operation_type,
        'public.users'::TEXT,
        v_result.parent_object,
        'email'::TEXT,
        v_result.object_name,
        CASE WHEN v_result.operation_type = 'ADD' AND v_result.object_type = 'COLUMN' AND v_result.object_name = 'email'
             THEN 'PASS' ELSE 'FAIL' END;

    -- Test case 4: Quoted identifiers
    SELECT * INTO v_result
    FROM pggit_audit.advanced_determine_object_type('CREATE TABLE "MySchema"."UserTable" (id INT);', '"MySchema"."UserTable"')
    LIMIT 1;

    RETURN QUERY SELECT
        'Quoted identifiers'::TEXT,
        'CREATE TABLE "MySchema"."UserTable" (id INT);'::TEXT,
        'TABLE'::TEXT,
        v_result.object_type,
        'MySchema'::TEXT,
        v_result.object_schema,
        'UserTable'::TEXT,
        v_result.object_name,
        CASE WHEN v_result.object_type = 'TABLE' AND v_result.object_schema = 'MySchema' AND v_result.object_name = 'UserTable'
             THEN 'PASS' ELSE 'FAIL' END;
END;
$$ LANGUAGE plpgsql;

-- Function: Comprehensive validation of audit data
CREATE OR REPLACE FUNCTION pggit_audit.comprehensive_validation()
RETURNS TABLE (
    validation_area TEXT,
    test_count INT,
    passed_count INT,
    failed_count INT,
    pass_rate NUMERIC
) AS $$
DECLARE
    v_total_tests INT := 0;
    v_passed_tests INT := 0;
    v_failed_tests INT := 0;
BEGIN
    -- DDL parsing tests
    SELECT
        COUNT(*) FILTER (WHERE result = 'PASS'),
        COUNT(*) FILTER (WHERE result = 'FAIL')
    INTO v_passed_tests, v_failed_tests
    FROM pggit_audit.test_ddl_parsing();

    v_total_tests := v_passed_tests + v_failed_tests;

    RETURN QUERY SELECT
        'DDL Parsing'::TEXT,
        v_total_tests,
        v_passed_tests,
        v_failed_tests,
        ROUND((v_passed_tests::NUMERIC / NULLIF(v_total_tests, 0)) * 100, 2);

    -- Reset counters
    v_total_tests := 0;
    v_passed_tests := 0;
    v_failed_tests := 0;

    -- Audit integrity tests
    SELECT
        COUNT(*) FILTER (WHERE status = 'PASS'),
        COUNT(*) FILTER (WHERE status IN ('FAIL', 'WARN'))
    INTO v_passed_tests, v_failed_tests
    FROM pggit_audit.validate_audit_integrity();

    v_total_tests := v_passed_tests + v_failed_tests;

    RETURN QUERY SELECT
        'Audit Integrity'::TEXT,
        v_total_tests,
        v_passed_tests,
        v_failed_tests,
        ROUND((v_passed_tests::NUMERIC / NULLIF(v_total_tests, 0)) * 100, 2);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PERFORMANCE OPTIMIZATIONS
-- ============================================

-- Function: Batch process multiple commit ranges efficiently
CREATE OR REPLACE FUNCTION pggit_audit.batch_process_commits(
    p_commit_ranges JSONB  -- Array of {old_commit, new_commit} objects
) RETURNS TABLE (
    range_index INT,
    old_commit TEXT,
    new_commit TEXT,
    changes_processed INT,
    processing_time INTERVAL,
    success BOOLEAN,
    error_message TEXT
) AS $$
DECLARE
    v_range RECORD;
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_changes_count INT;
    v_range_index INT := 0;
    v_success BOOLEAN;
    v_error_msg TEXT;
BEGIN
    FOR v_range IN
        SELECT
            (value->>'old_commit')::TEXT as old_commit,
            (value->>'new_commit')::TEXT as new_commit
        FROM jsonb_array_elements(p_commit_ranges)
    LOOP
        v_range_index := v_range_index + 1;
        v_start_time := clock_timestamp();
        v_success := true;
        v_error_msg := NULL;
        v_changes_count := 0;

        BEGIN
            -- Process the commit range
            SELECT changes_processed INTO v_changes_count
            FROM pggit_audit.process_commit_range(v_range.old_commit, v_range.new_commit, false);

            EXCEPTION WHEN OTHERS THEN
                v_success := false;
                v_error_msg := SQLERRM;
        END;

        v_end_time := clock_timestamp();

        RETURN QUERY SELECT
            v_range_index,
            v_range.old_commit,
            v_range.new_commit,
            v_changes_count,
            (v_end_time - v_start_time)::INTERVAL,
            v_success,
            v_error_msg;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- INTEGRATION HELPERS
-- ============================================

-- Function: Full sync from pggit_v2 (for initial population)
CREATE OR REPLACE FUNCTION pggit_audit.full_sync_from_pggit_v2(
    p_start_commit_sha TEXT DEFAULT NULL,
    p_end_commit_sha TEXT DEFAULT NULL,
    p_batch_size INT DEFAULT 10
) RETURNS TABLE (
    commits_processed INT,
    changes_created INT,
    duration INTERVAL,
    success BOOLEAN,
    last_commit_processed TEXT
) AS $$
DECLARE
    v_start_time TIMESTAMP := clock_timestamp();
    v_commits_processed INT := 0;
    v_changes_created INT := 0;
    v_last_commit TEXT;
    v_commit_ranges JSONB := '[]'::JSONB;
    v_batch_result RECORD;
    v_prev_commit TEXT := NULL;
BEGIN
    -- Build commit ranges for batch processing
    FOR v_last_commit IN
        SELECT commit_sha
        FROM pggit_v2.commit_graph
        WHERE (p_start_commit_sha IS NULL OR commit_sha >= p_start_commit_sha)
          AND (p_end_commit_sha IS NULL OR commit_sha <= p_end_commit_sha)
        ORDER BY committed_at
    LOOP
        IF v_prev_commit IS NOT NULL THEN
            v_commit_ranges := v_commit_ranges || jsonb_build_object(
                'old_commit', v_prev_commit,
                'new_commit', v_last_commit
            )::JSONB;
        END IF;
        v_prev_commit := v_last_commit;
    END LOOP;

    -- Process in batches
    FOR v_batch_result IN
        SELECT * FROM pggit_audit.batch_process_commits(v_commit_ranges)
        WHERE success = true
    LOOP
        v_commits_processed := v_commits_processed + 1;
        v_changes_created := v_changes_created + v_batch_result.changes_processed;
    END LOOP;

    RETURN QUERY SELECT
        v_commits_processed,
        v_changes_created,
        (clock_timestamp() - v_start_time)::INTERVAL,
        true,
        v_last_commit;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- METADATA
-- ============================================

COMMENT ON FUNCTION pggit_audit.advanced_determine_object_type IS 'Advanced object type detection with context and confidence levels';
COMMENT ON FUNCTION pggit_audit.parse_alter_statement IS 'Parse complex ALTER statements into component operations';
COMMENT ON FUNCTION pggit_audit.analyze_dependencies IS 'Analyze object dependencies and relationships';
COMMENT ON FUNCTION pggit_audit.extract_changes_extended IS 'Extended change extraction with full object support and dependencies';
COMMENT ON FUNCTION pggit_audit.test_ddl_parsing IS 'Comprehensive testing of DDL parsing functionality';
COMMENT ON FUNCTION pggit_audit.comprehensive_validation IS 'Complete validation of audit system integrity';
COMMENT ON FUNCTION pggit_audit.batch_process_commits IS 'Efficient batch processing of multiple commit ranges';
COMMENT ON FUNCTION pggit_audit.full_sync_from_pggit_v2 IS 'Complete synchronization from pggit_v2 commit history';