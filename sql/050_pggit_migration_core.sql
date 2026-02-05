-- ============================================
-- pgGit Migration Tooling: Core Migration Engine
-- ============================================
-- Automated migration from pggit v1 to pggit v2 + pggit_audit
-- Handles backfill, verification, and production cutover

-- ============================================
-- MIGRATION SCHEMA AND TABLES
-- ============================================

-- Drop existing schema if it exists
DROP SCHEMA IF EXISTS pggit_migration CASCADE;
CREATE SCHEMA pggit_migration;

-- Table: migration_status
-- Tracks overall migration progress and status
CREATE TABLE pggit_migration.migration_status (
    migration_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    migration_name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'PENDING', -- PENDING, RUNNING, COMPLETED, FAILED, ROLLED_BACK
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    dry_run BOOLEAN DEFAULT false,
    total_commits INTEGER DEFAULT 0,
    processed_commits INTEGER DEFAULT 0,
    total_changes INTEGER DEFAULT 0,
    created_changes INTEGER DEFAULT 0,
    errors INTEGER DEFAULT 0,
    warnings INTEGER DEFAULT 0,
    created_by TEXT,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table: migration_commits
-- Tracks processing of individual commits during migration
CREATE TABLE pggit_migration.migration_commits (
    commit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    migration_id UUID NOT NULL REFERENCES pggit_migration.migration_status(migration_id),
    commit_sha TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'PENDING', -- PENDING, PROCESSING, COMPLETED, FAILED, SKIPPED
    changes_created INTEGER DEFAULT 0,
    errors TEXT[], -- Array of error messages
    processing_time INTERVAL,
    processed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(migration_id, commit_sha)
);

-- Table: migration_errors
-- Detailed error tracking during migration
CREATE TABLE pggit_migration.migration_errors (
    error_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    migration_id UUID REFERENCES pggit_migration.migration_status(migration_id),
    commit_sha TEXT,
    error_type TEXT, -- DDL_PARSING, DB_ERROR, VALIDATION_ERROR, etc.
    error_message TEXT NOT NULL,
    error_details JSONB, -- Additional context
    occurred_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved BOOLEAN DEFAULT false,
    resolution_notes TEXT
);

-- Table: migration_verification
-- Verification results after migration
CREATE TABLE pggit_migration.migration_verification (
    verification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    migration_id UUID NOT NULL REFERENCES pggit_migration.migration_status(migration_id),
    verification_type TEXT NOT NULL, -- DATA_INTEGRITY, PERFORMANCE, COMPLIANCE
    status TEXT NOT NULL, -- PASSED, FAILED, WARNING
    details JSONB,
    verified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    verified_by TEXT
);

-- ============================================
-- PERFORMANCE INDICES
-- ============================================

CREATE INDEX idx_migration_status_status ON pggit_migration.migration_status(status);
CREATE INDEX idx_migration_status_started ON pggit_migration.migration_status(started_at DESC);
CREATE INDEX idx_migration_commits_migration ON pggit_migration.migration_commits(migration_id);
CREATE INDEX idx_migration_commits_status ON pggit_migration.migration_commits(status);
CREATE INDEX idx_migration_commits_sha ON pggit_migration.migration_commits(commit_sha);
CREATE INDEX idx_migration_errors_migration ON pggit_migration.migration_errors(migration_id);
CREATE INDEX idx_migration_errors_type ON pggit_migration.migration_errors(error_type);
CREATE INDEX idx_migration_verification_migration ON pggit_migration.migration_verification(migration_id);

-- ============================================
-- CORE MIGRATION ENGINE
-- ============================================

-- Function: Initialize migration tracking
CREATE OR REPLACE FUNCTION pggit_migration.initialize_migration(
    p_migration_name TEXT,
    p_dry_run BOOLEAN DEFAULT false,
    p_created_by TEXT DEFAULT CURRENT_USER
) RETURNS UUID AS $$
DECLARE
    v_migration_id UUID;
    v_total_commits INTEGER;
BEGIN
    -- Count total commits to process
    SELECT COUNT(*) INTO v_total_commits
    FROM pggit_v0.commit_graph;

    -- Create migration record
    INSERT INTO pggit_migration.migration_status (
        migration_name, status, dry_run, total_commits, created_by
    ) VALUES (
        p_migration_name, 'INITIALIZED', p_dry_run, v_total_commits, p_created_by
    ) RETURNING migration_id INTO v_migration_id;

    -- Initialize commit tracking
    INSERT INTO pggit_migration.migration_commits (migration_id, commit_sha)
    SELECT v_migration_id, commit_sha
    FROM pggit_v0.commit_graph
    ORDER BY committed_at;

    RETURN v_migration_id;
END;
$$ LANGUAGE plpgsql;

-- Function: Backfill audit data from pggit v1 with proper error handling
CREATE OR REPLACE FUNCTION pggit_migration.backfill_audit_from_v1(
    p_migration_id UUID,
    p_batch_size INTEGER DEFAULT 100
) RETURNS TABLE (
    processed INTEGER,
    errors INTEGER,
    warnings INTEGER,
    duration INTERVAL
) AS $$
DECLARE
    v_start_time TIMESTAMP := clock_timestamp();
    v_processed_count INTEGER := 0;
    v_error_count INTEGER := 0;
    v_warning_count INTEGER := 0;
    v_batch_commits TEXT[];
    v_commit_record RECORD;
    v_changes_count INTEGER;
BEGIN
    -- Update migration status to RUNNING
    UPDATE pggit_migration.migration_status
    SET status = 'RUNNING', started_at = CURRENT_TIMESTAMP
    WHERE migration_id = p_migration_id;

    -- Process commits in batches
    FOR v_batch_commits IN
        SELECT array_agg(commit_sha)
        FROM pggit_migration.migration_commits
        WHERE migration_id = p_migration_id
          AND status = 'PENDING'
        GROUP BY (row_number() OVER (ORDER BY commit_sha) - 1) / p_batch_size
    LOOP
        -- Process each commit in the batch
        FOREACH v_commit_record.commit_sha IN ARRAY v_batch_commits LOOP
            BEGIN
                -- Mark commit as processing
                UPDATE pggit_migration.migration_commits
                SET status = 'PROCESSING'
                WHERE migration_id = p_migration_id AND commit_sha = v_commit_record.commit_sha;

                -- Extract and store changes for this commit
                SELECT changes_processed INTO v_changes_count
                FROM pggit_audit.process_commit_range(
                    (SELECT tree_sha FROM pggit_v0.commit_graph WHERE commit_sha = v_commit_record.commit_sha),
                    v_commit_record.commit_sha,
                    false  -- Not dry run
                );

                -- Mark commit as completed
                UPDATE pggit_migration.migration_commits
                SET status = 'COMPLETED',
                    changes_created = v_changes_count,
                    processed_at = CURRENT_TIMESTAMP,
                    processing_time = CURRENT_TIMESTAMP - (SELECT started_at FROM pggit_migration.migration_status WHERE migration_id = p_migration_id)
                WHERE migration_id = p_migration_id AND commit_sha = v_commit_record.commit_sha;

                v_processed_count := v_processed_count + 1;

            EXCEPTION WHEN OTHERS THEN
                -- Record error
                INSERT INTO pggit_migration.migration_errors (
                    migration_id, commit_sha, error_type, error_message, error_details
                ) VALUES (
                    p_migration_id, v_commit_record.commit_sha, 'PROCESSING_ERROR',
                    SQLERRM, jsonb_build_object('state', SQLSTATE, 'detail', SQLERRM)
                );

                -- Mark commit as failed
                UPDATE pggit_migration.migration_commits
                SET status = 'FAILED',
                    errors = array_append(errors, SQLERRM),
                    processed_at = CURRENT_TIMESTAMP
                WHERE migration_id = p_migration_id AND commit_sha = v_commit_record.commit_sha;

                v_error_count := v_error_count + 1;
            END;
        END LOOP;
    END LOOP;

    -- Update migration status
    UPDATE pggit_migration.migration_status
    SET status = CASE WHEN v_error_count = 0 THEN 'COMPLETED' ELSE 'COMPLETED_WITH_ERRORS' END,
        completed_at = CURRENT_TIMESTAMP,
        processed_commits = v_processed_count,
        created_changes = (SELECT SUM(changes_created) FROM pggit_migration.migration_commits WHERE migration_id = p_migration_id),
        errors = v_error_count,
        warnings = v_warning_count
    WHERE migration_id = p_migration_id;

    RETURN QUERY SELECT v_processed_count, v_error_count, v_warning_count, (clock_timestamp() - v_start_time)::INTERVAL;
END;
$$ LANGUAGE plpgsql;

-- Function: Verify migration integrity and completeness
CREATE OR REPLACE FUNCTION pggit_migration.verify_migration(
    p_migration_id UUID
) RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT,
    recommendation TEXT
) AS $$
DECLARE
    v_migration RECORD;
BEGIN
    -- Get migration details
    SELECT * INTO v_migration
    FROM pggit_migration.migration_status
    WHERE migration_id = p_migration_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'MIGRATION_EXISTS'::TEXT, 'FAILED'::TEXT, 'Migration not found'::TEXT, 'Check migration ID'::TEXT;
        RETURN;
    END IF;

    -- Check: All commits processed
    RETURN QUERY
    SELECT
        'COMMITS_PROCESSED'::TEXT,
        CASE WHEN v_migration.processed_commits = v_migration.total_commits THEN 'PASSED' ELSE 'FAILED' END,
        format('%s/%s commits processed', v_migration.processed_commits, v_migration.total_commits)::TEXT,
        CASE WHEN v_migration.processed_commits = v_migration.total_commits THEN 'Migration complete' ELSE 'Re-run migration for remaining commits' END;

    -- Check: No critical errors
    RETURN QUERY
    SELECT
        'CRITICAL_ERRORS'::TEXT,
        CASE WHEN v_migration.errors = 0 THEN 'PASSED' ELSE 'FAILED' END,
        format('%s errors encountered', v_migration.errors)::TEXT,
        CASE WHEN v_migration.errors = 0 THEN 'No errors detected' ELSE 'Review error logs and fix issues' END;

    -- Check: Audit data integrity
    RETURN QUERY
    SELECT
        'AUDIT_INTEGRITY'::TEXT,
        CASE WHEN (
            SELECT COUNT(*) FROM pggit_audit.validate_audit_integrity()
            WHERE status IN ('CRITICAL', 'DEGRADED')
        ) = 0 THEN 'PASSED' ELSE 'FAILED' END,
        'Audit data integrity validation'::TEXT,
        'Run pggit_audit.validate_audit_integrity() for details'::TEXT;

    -- Check: Changes created
    RETURN QUERY
    SELECT
        'CHANGES_CREATED'::TEXT,
        CASE WHEN v_migration.created_changes > 0 THEN 'PASSED' ELSE 'WARNING' END,
        format('%s changes created', v_migration.created_changes)::TEXT,
        CASE WHEN v_migration.created_changes > 0 THEN 'Changes successfully extracted' ELSE 'No changes found - verify pggit_v0 data' END;

    -- Check: Performance acceptable
    RETURN QUERY
    SELECT
        'PERFORMANCE'::TEXT,
        CASE WHEN EXTRACT(EPOCH FROM (v_migration.completed_at - v_migration.started_at)) < 3600 THEN 'PASSED' ELSE 'WARNING' END,
        format('Migration took %s', v_migration.completed_at - v_migration.started_at)::TEXT,
        CASE WHEN EXTRACT(EPOCH FROM (v_migration.completed_at - v_migration.started_at)) < 3600 THEN 'Performance acceptable' ELSE 'Consider optimization for production' END;

END;
$$ LANGUAGE plpgsql;

-- ============================================
-- DRY-RUN CAPABILITIES
-- ============================================

-- Function: Dry-run migration to validate readiness
CREATE OR REPLACE FUNCTION pggit_migration.dry_run_migration(
    p_sample_size INTEGER DEFAULT 10
) RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT,
    readiness_score INTEGER -- 0-100
) AS $$
DECLARE
    v_sample_commits TEXT[];
    v_test_migration_id UUID;
    v_results RECORD;
    v_score INTEGER := 0;
BEGIN
    -- Sample commits for testing
    SELECT array_agg(commit_sha) INTO v_sample_commits
    FROM pggit_v0.commit_graph
    ORDER BY committed_at DESC
    LIMIT p_sample_size;

    IF v_sample_commits IS NULL OR array_length(v_sample_commits, 1) = 0 THEN
        RETURN QUERY SELECT 'COMMIT_AVAILABILITY'::TEXT, 'FAILED'::TEXT, 'No commits found in pggit_v0'::TEXT, 0;
        RETURN;
    END IF;

    -- Initialize test migration
    SELECT pggit_migration.initialize_migration('DRY_RUN_TEST_' || CURRENT_TIMESTAMP, true)
    INTO v_test_migration_id;

    -- Test processing sample commits
    FOREACH v_results.commit_sha IN ARRAY v_sample_commits LOOP
        BEGIN
            -- Test change extraction
            PERFORM pggit_audit.extract_changes_between_commits(
                (SELECT tree_sha FROM pggit_v0.commit_graph WHERE commit_sha = v_results.commit_sha LIMIT 1),
                v_results.commit_sha
            );
            v_score := v_score + 10;
        EXCEPTION WHEN OTHERS THEN
            v_score := v_score + 1; -- Partial credit for attempt
        END;
    END LOOP;

    -- Test schema readiness
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_audit') THEN
        v_score := v_score + 20;
        RETURN QUERY SELECT 'AUDIT_SCHEMA'::TEXT, 'READY'::TEXT, 'pggit_audit schema exists'::TEXT, v_score;
    ELSE
        RETURN QUERY SELECT 'AUDIT_SCHEMA'::TEXT, 'NOT_READY'::TEXT, 'pggit_audit schema missing'::TEXT, v_score - 20;
    END IF;

    -- Test function availability
    IF EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema = 'pggit_audit' AND routine_name = 'extract_changes_between_commits') THEN
        v_score := v_score + 20;
        RETURN QUERY SELECT 'EXTRACTION_FUNCTIONS'::TEXT, 'READY'::TEXT, 'Extraction functions available'::TEXT, v_score;
    ELSE
        RETURN QUERY SELECT 'EXTRACTION_FUNCTIONS'::TEXT, 'NOT_READY'::TEXT, 'Extraction functions missing'::TEXT, v_score - 20;
    END IF;

    -- Test data integrity
    IF (SELECT COUNT(*) FROM pggit_audit.validate_audit_integrity() WHERE status = 'CRITICAL') = 0 THEN
        v_score := v_score + 20;
        RETURN QUERY SELECT 'DATA_INTEGRITY'::TEXT, 'READY'::TEXT, 'Data integrity checks passed'::TEXT, v_score;
    ELSE
        RETURN QUERY SELECT 'DATA_INTEGRITY'::TEXT, 'ISSUES'::TEXT, 'Data integrity issues found'::TEXT, v_score - 10;
    END IF;

    -- Overall readiness
    RETURN QUERY SELECT
        'OVERALL_READINESS'::TEXT,
        CASE WHEN v_score >= 80 THEN 'READY' WHEN v_score >= 60 THEN 'MARGINAL' ELSE 'NOT_READY' END,
        format('Readiness score: %s/100', v_score)::TEXT,
        v_score;

    -- Cleanup test migration
    DELETE FROM pggit_migration.migration_commits WHERE migration_id = v_test_migration_id;
    DELETE FROM pggit_migration.migration_status WHERE migration_id = v_test_migration_id;

END;
$$ LANGUAGE plpgsql;

-- ============================================
-- MONITORING AND STATUS FUNCTIONS
-- ============================================

-- Function: Get migration progress and status
CREATE OR REPLACE FUNCTION pggit_migration.get_migration_status(
    p_migration_id UUID DEFAULT NULL
) RETURNS TABLE (
    migration_id UUID,
    migration_name TEXT,
    status TEXT,
    progress_percentage NUMERIC,
    processed_commits INTEGER,
    total_commits INTEGER,
    created_changes INTEGER,
    errors INTEGER,
    warnings INTEGER,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    duration INTERVAL,
    eta INTERVAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ms.migration_id,
        ms.migration_name,
        ms.status,
        CASE WHEN ms.total_commits > 0 THEN (ms.processed_commits::NUMERIC / ms.total_commits) * 100 ELSE 0 END,
        ms.processed_commits,
        ms.total_commits,
        ms.created_changes,
        ms.errors,
        ms.warnings,
        ms.started_at,
        ms.completed_at,
        ms.completed_at - ms.started_at,
        CASE WHEN ms.processed_commits > 0 AND ms.started_at IS NOT NULL
             THEN ((ms.total_commits - ms.processed_commits) * (CURRENT_TIMESTAMP - ms.started_at) / ms.processed_commits)
             ELSE NULL END
    FROM pggit_migration.migration_status ms
    WHERE (p_migration_id IS NULL OR ms.migration_id = p_migration_id)
    ORDER BY ms.started_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Function: Get detailed migration errors
CREATE OR REPLACE FUNCTION pggit_migration.get_migration_errors(
    p_migration_id UUID,
    p_limit INTEGER DEFAULT 50
) RETURNS TABLE (
    commit_sha TEXT,
    error_type TEXT,
    error_message TEXT,
    error_details JSONB,
    occurred_at TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        me.commit_sha,
        me.error_type,
        me.error_message,
        me.error_details,
        me.occurred_at
    FROM pggit_migration.migration_errors me
    WHERE me.migration_id = p_migration_id
    ORDER BY me.occurred_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

-- Function: Clean up old migration data
CREATE OR REPLACE FUNCTION pggit_migration.cleanup_old_migrations(
    p_retention_days INTEGER DEFAULT 30,
    p_dry_run BOOLEAN DEFAULT true
) RETURNS TABLE (
    operation TEXT,
    records_affected INTEGER,
    details TEXT
) AS $$
DECLARE
    v_cutoff_date TIMESTAMP := CURRENT_TIMESTAMP - (p_retention_days || ' days')::INTERVAL;
    v_deleted_status INTEGER := 0;
    v_deleted_commits INTEGER := 0;
    v_deleted_errors INTEGER := 0;
    v_deleted_verification INTEGER := 0;
BEGIN
    -- Count records to be deleted
    SELECT COUNT(*) INTO v_deleted_status
    FROM pggit_migration.migration_status
    WHERE completed_at < v_cutoff_date;

    SELECT COUNT(*) INTO v_deleted_commits
    FROM pggit_migration.migration_commits mc
    JOIN pggit_migration.migration_status ms ON mc.migration_id = ms.migration_id
    WHERE ms.completed_at < v_cutoff_date;

    SELECT COUNT(*) INTO v_deleted_errors
    FROM pggit_migration.migration_errors me
    JOIN pggit_migration.migration_status ms ON me.migration_id = ms.migration_id
    WHERE ms.completed_at < v_cutoff_date;

    SELECT COUNT(*) INTO v_deleted_verification
    FROM pggit_migration.migration_verification mv
    JOIN pggit_migration.migration_status ms ON mv.migration_id = ms.migration_id
    WHERE ms.completed_at < v_cutoff_date;

    RETURN QUERY SELECT 'STATUS_RECORDS'::TEXT, v_deleted_status, format('Migration status records older than %s days', p_retention_days)::TEXT;
    RETURN QUERY SELECT 'COMMIT_RECORDS'::TEXT, v_deleted_commits, 'Associated commit processing records'::TEXT;
    RETURN QUERY SELECT 'ERROR_RECORDS'::TEXT, v_deleted_errors, 'Migration error records'::TEXT;
    RETURN QUERY SELECT 'VERIFICATION_RECORDS'::TEXT, v_deleted_verification, 'Migration verification records'::TEXT;

    IF NOT p_dry_run THEN
        -- Perform actual deletion
        DELETE FROM pggit_migration.migration_errors
        WHERE migration_id IN (
            SELECT migration_id FROM pggit_migration.migration_status
            WHERE completed_at < v_cutoff_date
        );

        DELETE FROM pggit_migration.migration_verification
        WHERE migration_id IN (
            SELECT migration_id FROM pggit_migration.migration_status
            WHERE completed_at < v_cutoff_date
        );

        DELETE FROM pggit_migration.migration_commits
        WHERE migration_id IN (
            SELECT migration_id FROM pggit_migration.migration_status
            WHERE completed_at < v_cutoff_date
        );

        DELETE FROM pggit_migration.migration_status
        WHERE completed_at < v_cutoff_date;

        RETURN QUERY SELECT 'CLEANUP_COMPLETED'::TEXT, v_deleted_status + v_deleted_commits + v_deleted_errors + v_deleted_verification, 'Records deleted'::TEXT;
    ELSE
        RETURN QUERY SELECT 'DRY_RUN_MODE'::TEXT, 0, 'No changes made - use dry_run=false to execute'::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- METADATA AND DOCUMENTATION
-- ============================================

COMMENT ON SCHEMA pggit_migration_v0 IS 'Migration tooling for pggit v1 to v2 conversion';
COMMENT ON TABLE pggit_migration.migration_status IS 'Overall migration progress and status tracking';
COMMENT ON TABLE pggit_migration.migration_commits IS 'Individual commit processing status';
COMMENT ON TABLE pggit_migration.migration_errors IS 'Detailed error tracking during migration';
COMMENT ON TABLE pggit_migration.migration_verification IS 'Post-migration verification results';

COMMENT ON FUNCTION pggit_migration.initialize_migration IS 'Initialize migration tracking and commit enumeration';
COMMENT ON FUNCTION pggit_migration.backfill_audit_from_v1 IS 'Execute the actual migration from v1 to audit data';
COMMENT ON FUNCTION pggit_migration.verify_migration IS 'Verify migration integrity and completeness';
COMMENT ON FUNCTION pggit_migration.dry_run_migration IS 'Test migration readiness without making changes';
COMMENT ON FUNCTION pggit_migration.get_migration_status IS 'Get detailed migration progress and status';
COMMENT ON FUNCTION pggit_migration.get_migration_errors IS 'Retrieve detailed migration error information';
COMMENT ON FUNCTION pggit_migration.cleanup_old_migrations IS 'Clean up old migration tracking data';

-- ============================================
-- INITIALIZATION COMPLETE
-- ============================================

DO $$
BEGIN
    RAISE NOTICE 'pgGit Migration Core initialized successfully';
    RAISE NOTICE 'Schema: pggit_migration created with migration tracking tables';
    RAISE NOTICE 'Ready for pggit v1 to v2 migration execution';
END $$;</content>
<parameter name="filePath">sql/pggit_migration_core.sql