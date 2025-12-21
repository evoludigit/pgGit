-- ============================================
-- pgGit Migration Execution: Production Cutover
-- ============================================
-- Production migration scripts, rollback procedures,
-- verification tools, and runbook documentation

-- ============================================
-- PRODUCTION MIGRATION SCRIPT
-- ============================================

-- Function: Execute complete production migration
CREATE OR REPLACE FUNCTION pggit_migration.execute_production_migration(
    p_migration_name TEXT DEFAULT 'PRODUCTION_CUTOVER_' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MISS'),
    p_batch_size INTEGER DEFAULT 50,
    p_verify_after BOOLEAN DEFAULT true,
    p_created_by TEXT DEFAULT CURRENT_USER
) RETURNS TABLE (
    phase TEXT,
    status TEXT,
    details TEXT,
    duration INTERVAL,
    success BOOLEAN
) AS $$
DECLARE
    v_migration_id UUID;
    v_start_time TIMESTAMP;
    v_phase_start TIMESTAMP;
    v_backfill_result RECORD;
    v_verify_result RECORD;
    v_success BOOLEAN := true;
    v_error_msg TEXT;
BEGIN
    v_start_time := clock_timestamp();

    -- ========================================================================
    -- PHASE 1: INITIALIZATION
    -- ========================================================================

    v_phase_start := clock_timestamp();
    BEGIN
        RETURN QUERY SELECT 'INITIALIZATION'::TEXT, 'STARTING'::TEXT, 'Setting up migration tracking'::TEXT, NULL::INTERVAL, NULL::BOOLEAN;

        -- Initialize migration tracking
        SELECT pggit_migration.initialize_migration(p_migration_name, false, p_created_by)
        INTO v_migration_id;

        RETURN QUERY SELECT 'INITIALIZATION'::TEXT, 'COMPLETED'::TEXT,
                          format('Migration initialized with ID: %s', v_migration_id)::TEXT,
                          clock_timestamp() - v_phase_start, true;
    EXCEPTION WHEN OTHERS THEN
        v_success := false;
        v_error_msg := SQLERRM;
        RETURN QUERY SELECT 'INITIALIZATION'::TEXT, 'FAILED'::TEXT,
                          format('Initialization failed: %s', v_error_msg)::TEXT,
                          clock_timestamp() - v_phase_start, false;
        RETURN;
    END;

    -- ========================================================================
    -- PHASE 2: PRE-MIGRATION VERIFICATION
    -- ========================================================================

    v_phase_start := clock_timestamp();
    BEGIN
        RETURN QUERY SELECT 'PRE_MIGRATION_CHECKS'::TEXT, 'STARTING'::TEXT, 'Running pre-migration verification'::TEXT, NULL::INTERVAL, NULL::BOOLEAN;

        -- Verify system readiness
        IF (SELECT COUNT(*) FROM pggit_migration.dry_run_migration(5) WHERE status IN ('NOT_READY', 'FAILED')) > 0 THEN
            RAISE EXCEPTION 'Pre-migration checks failed - system not ready for migration';
        END IF;

        -- Verify pggit_v0 has commits
        IF (SELECT COUNT(*) FROM pggit_v0.commit_graph) = 0 THEN
            RAISE EXCEPTION 'No commits found in pggit_v0 - cannot proceed with migration';
        END IF;

        RETURN QUERY SELECT 'PRE_MIGRATION_CHECKS'::TEXT, 'PASSED'::TEXT,
                          'All pre-migration checks completed successfully'::TEXT,
                          clock_timestamp() - v_phase_start, true;
    EXCEPTION WHEN OTHERS THEN
        v_success := false;
        v_error_msg := SQLERRM;
        RETURN QUERY SELECT 'PRE_MIGRATION_CHECKS'::TEXT, 'FAILED'::TEXT,
                          format('Pre-migration checks failed: %s', v_error_msg)::TEXT,
                          clock_timestamp() - v_phase_start, false;
        RETURN;
    END;

    -- ========================================================================
    -- PHASE 3: BACKFILL EXECUTION
    -- ========================================================================

    v_phase_start := clock_timestamp();
    BEGIN
        RETURN QUERY SELECT 'BACKFILL_EXECUTION'::TEXT, 'STARTING'::TEXT,
                          format('Starting backfill with batch size: %s', p_batch_size)::TEXT,
                          NULL::INTERVAL, NULL::BOOLEAN;

        -- Execute the backfill
        SELECT * INTO v_backfill_result
        FROM pggit_migration.backfill_audit_from_v1(v_migration_id, p_batch_size);

        -- Check results
        IF v_backfill_result.errors > 0 THEN
            RETURN QUERY SELECT 'BACKFILL_EXECUTION'::TEXT, 'COMPLETED_WITH_ERRORS'::TEXT,
                              format('Backfill completed: %s processed, %s errors, %s warnings',
                                    v_backfill_result.processed, v_backfill_result.errors, v_backfill_result.warnings)::TEXT,
                              clock_timestamp() - v_phase_start, true;
        ELSE
            RETURN QUERY SELECT 'BACKFILL_EXECUTION'::TEXT, 'COMPLETED'::TEXT,
                              format('Backfill completed successfully: %s processed, %s warnings',
                                    v_backfill_result.processed, v_backfill_result.warnings)::TEXT,
                              clock_timestamp() - v_phase_start, true;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_success := false;
        v_error_msg := SQLERRM;
        RETURN QUERY SELECT 'BACKFILL_EXECUTION'::TEXT, 'FAILED'::TEXT,
                          format('Backfill execution failed: %s', v_error_msg)::TEXT,
                          clock_timestamp() - v_phase_start, false;
        RETURN;
    END;

    -- ========================================================================
    -- PHASE 4: POST-MIGRATION VERIFICATION
    -- ========================================================================

    IF p_verify_after THEN
        v_phase_start := clock_timestamp();
        BEGIN
            RETURN QUERY SELECT 'POST_MIGRATION_VERIFICATION'::TEXT, 'STARTING'::TEXT, 'Running post-migration verification'::TEXT, NULL::INTERVAL, NULL::BOOLEAN;

            -- Run verification checks
            INSERT INTO pggit_migration.migration_verification (
                migration_id, verification_type, status, details, verified_by
            )
            SELECT
                v_migration_id,
                check_name,
                CASE WHEN status IN ('PASSED', 'HEALTHY') THEN 'PASSED'
                     WHEN status = 'WARNING' THEN 'WARNING'
                     ELSE 'FAILED' END,
                jsonb_build_object('details', details, 'recommendation', recommendation),
                p_created_by
            FROM pggit_migration.verify_migration(v_migration_id);

            -- Check if verification passed
            IF EXISTS (SELECT 1 FROM pggit_migration.migration_verification
                      WHERE migration_id = v_migration_id AND status = 'FAILED') THEN
                RAISE EXCEPTION 'Post-migration verification failed - check verification results';
            END IF;

            RETURN QUERY SELECT 'POST_MIGRATION_VERIFICATION'::TEXT, 'PASSED'::TEXT,
                              'All post-migration checks completed successfully'::TEXT,
                              clock_timestamp() - v_phase_start, true;
        EXCEPTION WHEN OTHERS THEN
            v_success := false;
            v_error_msg := SQLERRM;
            RETURN QUERY SELECT 'POST_MIGRATION_VERIFICATION'::TEXT, 'FAILED'::TEXT,
                              format('Post-migration verification failed: %s', v_error_msg)::TEXT,
                              clock_timestamp() - v_phase_start, false;
            RETURN;
        END;
    END IF;

    -- ========================================================================
    -- PHASE 5: FINALIZATION
    -- ========================================================================

    v_phase_start := clock_timestamp();
    BEGIN
        -- Mark migration as completed
        UPDATE pggit_migration.migration_status
        SET status = CASE WHEN v_success THEN 'COMPLETED' ELSE 'FAILED' END,
            completed_at = CURRENT_TIMESTAMP,
            notes = CASE WHEN v_success THEN 'Migration completed successfully'
                        ELSE 'Migration failed - check error logs' END
        WHERE migration_id = v_migration_id;

        RETURN QUERY SELECT 'FINALIZATION'::TEXT, 'COMPLETED'::TEXT,
                          format('Migration %s finalized with status: %s',
                                CASE WHEN v_success THEN 'completed successfully' ELSE 'failed' END,
                                CASE WHEN v_success THEN 'SUCCESS' ELSE 'FAILED' END)::TEXT,
                          clock_timestamp() - v_phase_start, v_success;

        -- Overall completion
        RETURN QUERY SELECT 'OVERALL_MIGRATION'::TEXT,
                          CASE WHEN v_success THEN 'SUCCESS' ELSE 'FAILED' END,
                          format('Total migration time: %s', clock_timestamp() - v_start_time)::TEXT,
                          clock_timestamp() - v_start_time, v_success;
    END;

END;
$$ LANGUAGE plpgsql;

-- ============================================
-- ROLLBACK PROCEDURES
-- ============================================

-- Function: Rollback migration (emergency rollback)
CREATE OR REPLACE FUNCTION pggit_migration.rollback_migration(
    p_migration_id UUID,
    p_force BOOLEAN DEFAULT false,
    p_rollback_by TEXT DEFAULT CURRENT_USER
) RETURNS TABLE (
    phase TEXT,
    status TEXT,
    details TEXT,
    success BOOLEAN
) AS $$
DECLARE
    v_migration RECORD;
    v_changes_deleted INTEGER := 0;
    v_objects_deleted INTEGER := 0;
BEGIN
    -- Get migration details
    SELECT * INTO v_migration
    FROM pggit_migration.migration_status
    WHERE migration_id = p_migration_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'VALIDATION'::TEXT, 'FAILED'::TEXT, 'Migration not found'::TEXT, false;
        RETURN;
    END IF;

    IF v_migration.status NOT IN ('RUNNING', 'COMPLETED', 'COMPLETED_WITH_ERRORS', 'FAILED') THEN
        RETURN QUERY SELECT 'VALIDATION'::TEXT, 'FAILED'::TEXT,
                          format('Cannot rollback migration in status: %s', v_migration.status)::TEXT, false;
        RETURN;
    END IF;

    -- Safety check
    IF NOT p_force AND v_migration.status = 'COMPLETED' AND v_migration.completed_at > CURRENT_TIMESTAMP - INTERVAL '1 hour' THEN
        RETURN QUERY SELECT 'SAFETY_CHECK'::TEXT, 'BLOCKED'::TEXT,
                          'Cannot rollback completed migration within 1 hour unless forced'::TEXT, false;
        RETURN;
    END IF;

    RETURN QUERY SELECT 'ROLLBACK'::TEXT, 'STARTING'::TEXT,
                      format('Starting rollback of migration: %s', p_migration_id)::TEXT, NULL::BOOLEAN;

    -- ========================================================================
    -- PHASE 1: DELETE CREATED AUDIT DATA
    -- ========================================================================

    BEGIN
        -- Delete changes created by this migration
        DELETE FROM pggit_audit.changes
        WHERE change_id IN (
            SELECT ac.change_id
            FROM pggit_audit.changes ac
            JOIN pggit_migration.migration_commits mc ON mc.commit_sha = ac.commit_sha
            WHERE mc.migration_id = p_migration_id
        );

        GET DIAGNOSTICS v_changes_deleted = ROW_COUNT;

        -- Delete object versions created by this migration
        DELETE FROM pggit_audit.object_versions
        WHERE commit_sha IN (
            SELECT commit_sha FROM pggit_migration.migration_commits
            WHERE migration_id = p_migration_id
        );

        GET DIAGNOSTICS v_objects_deleted = ROW_COUNT;

        RETURN QUERY SELECT 'DATA_CLEANUP'::TEXT, 'COMPLETED'::TEXT,
                          format('Deleted %s changes and %s object versions', v_changes_deleted, v_objects_deleted)::TEXT, true;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 'DATA_CLEANUP'::TEXT, 'FAILED'::TEXT,
                          format('Data cleanup failed: %s', SQLERRM)::TEXT, false;
        RETURN;
    END;

    -- ========================================================================
    -- PHASE 2: UPDATE MIGRATION STATUS
    -- ========================================================================

    BEGIN
        UPDATE pggit_migration.migration_status
        SET status = 'ROLLED_BACK',
            completed_at = CURRENT_TIMESTAMP,
            notes = format('Rolled back by %s at %s. Deleted %s changes, %s objects',
                          p_rollback_by, CURRENT_TIMESTAMP, v_changes_deleted, v_objects_deleted)
        WHERE migration_id = p_migration_id;

        RETURN QUERY SELECT 'STATUS_UPDATE'::TEXT, 'COMPLETED'::TEXT,
                          'Migration status updated to ROLLED_BACK'::TEXT, true;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 'STATUS_UPDATE'::TEXT, 'FAILED'::TEXT,
                          format('Status update failed: %s', SQLERRM)::TEXT, false;
    END;

    RETURN QUERY SELECT 'ROLLBACK'::TEXT, 'COMPLETED'::TEXT,
                      format('Rollback completed successfully - %s changes and %s objects removed',
                            v_changes_deleted, v_objects_deleted)::TEXT, true;

END;
$$ LANGUAGE plpgsql;

-- ============================================
-- VERIFICATION AND TESTING TOOLS
-- ============================================

-- Function: Comprehensive migration verification
CREATE OR REPLACE FUNCTION pggit_migration.comprehensive_migration_verification(
    p_migration_id UUID
) RETURNS TABLE (
    verification_area TEXT,
    severity TEXT,
    status TEXT,
    details TEXT,
    recommendation TEXT,
    auto_fix_possible BOOLEAN
) AS $$
DECLARE
    v_migration RECORD;
    v_check_count INTEGER;
BEGIN
    -- Get migration details
    SELECT * INTO v_migration
    FROM pggit_migration.migration_status
    WHERE migration_id = p_migration_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'MIGRATION_EXISTS'::TEXT, 'CRITICAL'::TEXT, 'FAILED'::TEXT,
                          'Migration record not found'::TEXT, 'Verify migration ID'::TEXT, false;
        RETURN;
    END IF;

    -- ========================================================================
    -- DATA INTEGRITY CHECKS
    -- ========================================================================

    -- Check for orphaned audit records
    SELECT COUNT(*) INTO v_check_count
    FROM pggit_audit.changes c
    LEFT JOIN pggit_migration.migration_commits mc ON mc.commit_sha = c.commit_sha AND mc.migration_id = p_migration_id
    WHERE c.backfilled_from_v1 = true AND mc.commit_sha IS NULL;

    RETURN QUERY SELECT 'DATA_INTEGRITY'::TEXT,
                      CASE WHEN v_check_count > 0 THEN 'HIGH' ELSE 'LOW' END,
                      CASE WHEN v_check_count = 0 THEN 'PASSED' ELSE 'FAILED' END,
                      format('Found %s orphaned audit records', v_check_count)::TEXT,
                      CASE WHEN v_check_count = 0 THEN 'Data integrity verified'
                          ELSE 'Clean up orphaned records or re-run migration' END,
                      v_check_count > 0;

    -- Check for missing audit records
    SELECT COUNT(*) INTO v_check_count
    FROM pggit_migration.migration_commits mc
    LEFT JOIN pggit_audit.changes c ON c.commit_sha = mc.commit_sha
    WHERE mc.migration_id = p_migration_id
      AND mc.status = 'COMPLETED'
      AND c.change_id IS NULL;

    RETURN QUERY SELECT 'DATA_COMPLETENESS'::TEXT,
                      CASE WHEN v_check_count > 0 THEN 'MEDIUM' ELSE 'LOW' END,
                      CASE WHEN v_check_count = 0 THEN 'PASSED' ELSE 'FAILED' END,
                      format('Found %s commits without audit records', v_check_count)::TEXT,
                      CASE WHEN v_check_count = 0 THEN 'All commits have audit records'
                          ELSE 'Re-run extraction for missing commits' END,
                      true;

    -- ========================================================================
    -- PERFORMANCE CHECKS
    -- ========================================================================

    -- Check migration duration
    IF v_migration.completed_at IS NOT NULL AND v_migration.started_at IS NOT NULL THEN
        RETURN QUERY SELECT 'PERFORMANCE'::TEXT,
                          CASE WHEN EXTRACT(EPOCH FROM (v_migration.completed_at - v_migration.started_at)) > 3600 THEN 'MEDIUM'
                              ELSE 'LOW' END,
                          CASE WHEN EXTRACT(EPOCH FROM (v_migration.completed_at - v_migration.started_at)) <= 3600 THEN 'PASSED'
                              ELSE 'SLOW' END,
                          format('Migration took %s', v_migration.completed_at - v_migration.started_at)::TEXT,
                          CASE WHEN EXTRACT(EPOCH FROM (v_migration.completed_at - v_migration.started_at)) <= 3600 THEN 'Performance acceptable'
                              ELSE 'Consider optimization for future migrations' END,
                          false;
    END IF;

    -- ========================================================================
    -- CONSISTENCY CHECKS
    -- ========================================================================

    -- Check for duplicate changes
    SELECT COUNT(*) INTO v_check_count
    FROM (
        SELECT commit_sha, object_schema, object_name, COUNT(*) as cnt
        FROM pggit_audit.changes
        GROUP BY commit_sha, object_schema, object_name
        HAVING COUNT(*) > 1
    ) duplicates;

    RETURN QUERY SELECT 'DATA_CONSISTENCY'::TEXT,
                      CASE WHEN v_check_count > 0 THEN 'HIGH' ELSE 'LOW' END,
                      CASE WHEN v_check_count = 0 THEN 'PASSED' ELSE 'FAILED' END,
                      format('Found %s duplicate change records', v_check_count)::TEXT,
                      CASE WHEN v_check_count = 0 THEN 'No duplicate records found'
                          ELSE 'Remove duplicate records and prevent future duplicates' END,
                      true;

    -- ========================================================================
    -- COMPLIANCE CHECKS
    -- ========================================================================

    -- Check verification status
    SELECT COUNT(*) INTO v_check_count
    FROM pggit_audit.changes c
    JOIN pggit_migration.migration_commits mc ON mc.commit_sha = c.commit_sha
    WHERE mc.migration_id = p_migration_id
      AND c.verified = false;

    RETURN QUERY SELECT 'COMPLIANCE'::TEXT,
                      CASE WHEN v_check_count > 0 THEN 'MEDIUM' ELSE 'LOW' END,
                      CASE WHEN v_check_count = 0 THEN 'PASSED' ELSE 'WARNING' END,
                      format('%s changes pending verification', v_check_count)::TEXT,
                      CASE WHEN v_check_count = 0 THEN 'All changes verified'
                          ELSE 'Complete verification process for compliance' END,
                      false;

END;
$$ LANGUAGE plpgsql;

-- ============================================
-- MONITORING AND ALERTING
-- ============================================

-- Function: Migration health dashboard
CREATE OR REPLACE FUNCTION pggit_migration.migration_health_dashboard()
RETURNS TABLE (
    metric TEXT,
    current_value TEXT,
    status TEXT,
    trend TEXT,
    alert_level TEXT
) AS $$
BEGIN
    -- Active migrations
    RETURN QUERY SELECT
        'ACTIVE_MIGRATIONS'::TEXT,
        COUNT(*)::TEXT,
        CASE WHEN COUNT(*) = 0 THEN 'NORMAL' WHEN COUNT(*) = 1 THEN 'INFO' ELSE 'WARNING' END,
        'Current'::TEXT,
        CASE WHEN COUNT(*) > 1 THEN 'MEDIUM' ELSE 'LOW' END
    FROM pggit_migration.migration_status
    WHERE status IN ('RUNNING', 'INITIALIZED');

    -- Failed migrations (last 24 hours)
    RETURN QUERY SELECT
        'FAILED_MIGRATIONS_24H'::TEXT,
        COUNT(*)::TEXT,
        CASE WHEN COUNT(*) = 0 THEN 'NORMAL' ELSE 'CRITICAL' END,
        'Last 24h'::TEXT,
        CASE WHEN COUNT(*) > 0 THEN 'CRITICAL' ELSE 'LOW' END
    FROM pggit_migration.migration_status
    WHERE status = 'FAILED'
      AND started_at > CURRENT_TIMESTAMP - INTERVAL '24 hours';

    -- Migration errors (last hour)
    RETURN QUERY SELECT
        'MIGRATION_ERRORS_1H'::TEXT,
        COUNT(*)::TEXT,
        CASE WHEN COUNT(*) = 0 THEN 'NORMAL' WHEN COUNT(*) < 10 THEN 'INFO' ELSE 'HIGH' END,
        'Last 1h'::TEXT,
        CASE WHEN COUNT(*) >= 10 THEN 'HIGH' WHEN COUNT(*) > 0 THEN 'MEDIUM' ELSE 'LOW' END
    FROM pggit_migration.migration_errors
    WHERE occurred_at > CURRENT_TIMESTAMP - INTERVAL '1 hour';

    -- Unverified changes
    RETURN QUERY SELECT
        'UNVERIFIED_CHANGES'::TEXT,
        COUNT(*)::TEXT,
        CASE WHEN COUNT(*) < 100 THEN 'NORMAL' WHEN COUNT(*) < 1000 THEN 'INFO' ELSE 'MEDIUM' END,
        'Current'::TEXT,
        CASE WHEN COUNT(*) >= 1000 THEN 'MEDIUM' ELSE 'LOW' END
    FROM pggit_audit.changes
    WHERE verified = false;

    -- Data growth
    RETURN QUERY SELECT
        'AUDIT_DATA_SIZE'::TEXT,
        pg_size_pretty(pg_total_relation_size('pggit_audit.changes'))::TEXT,
        'INFO'::TEXT,
        'Current'::TEXT,
        'LOW'::TEXT;

END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PRODUCTION RUNBOOK DOCUMENTATION
-- ============================================

/*
PRODUCTION MIGRATION RUNBOOK
===========================

PRE-MIGRATION CHECKLIST:
□ Verify pggit v1 is running normally
□ Confirm pggit v2 is installed and configured
□ Run dry-run migration test
□ Backup production database
□ Schedule 6-hour maintenance window
□ Notify stakeholders of maintenance window

MIGRATION EXECUTION:
1. Start maintenance window
2. Disable pggit v1 event triggers
3. Execute production migration script
4. Monitor migration progress
5. Verify migration results
6. Enable pggit v2 + pggit_audit
7. End maintenance window

ROLLBACK PROCEDURE (if needed):
1. Execute rollback script
2. Re-enable pggit v1 event triggers
3. Verify system returns to pre-migration state
4. Investigate and fix issues
5. Schedule new migration attempt

POST-MIGRATION VERIFICATION:
□ All commits processed successfully
□ No critical errors in migration logs
□ Audit data integrity verified
□ Performance meets requirements
□ Compliance verification completed

MONITORING:
- Check migration health dashboard daily for first week
- Monitor audit data growth
- Verify compliance verification progress
- Alert on any migration errors

CONTACTS:
- DBA Team: For database issues
- DevOps: For infrastructure issues
- Security: For compliance verification
- Product Owner: For business decisions

SUCCESS CRITERIA:
- Migration completes within 6-hour window
- Zero data loss
- All audit trails preserved
- System performance maintained
- Compliance requirements met
*/

-- ============================================
-- UTILITY SCRIPTS FOR RUNBOOK
-- ============================================

-- Function: Pre-migration health check
CREATE OR REPLACE FUNCTION pggit_migration.pre_migration_health_check()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT,
    blocking BOOLEAN
) AS $$
BEGIN
    -- Check database connectivity
    RETURN QUERY SELECT 'DATABASE_CONNECTIVITY'::TEXT, 'PASSED'::TEXT, 'Database connection successful'::TEXT, false;

    -- Check pggit v1 schema
    RETURN QUERY SELECT
        'PGGIT_V1_SCHEMA'::TEXT,
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit') THEN 'PASSED' ELSE 'FAILED' END,
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit') THEN 'pggit v1 schema found' ELSE 'pggit v1 schema missing' END,
        NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit');

    -- Check pggit v2 schema
    RETURN QUERY SELECT
        'PGGIT_V2_SCHEMA'::TEXT,
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_v0') THEN 'PASSED' ELSE 'FAILED' END,
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_v0') THEN 'pggit_v0 schema found' ELSE 'pggit_v0 schema missing' END,
        NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_v0');

    -- Check audit schema
    RETURN QUERY SELECT
        'AUDIT_SCHEMA'::TEXT,
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_audit') THEN 'PASSED' ELSE 'FAILED' END,
        CASE WHEN EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_audit') THEN 'pggit_audit schema found' ELSE 'pggit_audit schema missing' END,
        NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_audit');

    -- Check available disk space (rough estimate)
    RETURN QUERY SELECT
        'DISK_SPACE'::TEXT,
        'INFO'::TEXT,
        'Ensure adequate disk space for audit data (estimate 2x pggit v1 size)'::TEXT,
        false;

    -- Check maintenance window
    RETURN QUERY SELECT
        'MAINTENANCE_WINDOW'::TEXT,
        'INFO'::TEXT,
        'Ensure 6-hour maintenance window is scheduled and communicated'::TEXT,
        false;

END;
$$ LANGUAGE plpgsql;

-- Function: Generate migration report
CREATE OR REPLACE FUNCTION pggit_migration.generate_migration_report(
    p_migration_id UUID
) RETURNS TEXT AS $$
DECLARE
    v_migration RECORD;
    v_report TEXT := '';
BEGIN
    -- Get migration details
    SELECT * INTO v_migration
    FROM pggit_migration.migration_status
    WHERE migration_id = p_migration_id;

    IF NOT FOUND THEN
        RETURN 'Migration not found';
    END IF;

    -- Build report
    v_report := v_report || format('MIGRATION REPORT%n') || '=' * 50 || format('%n%n');
    v_report := v_report || format('Migration ID: %s%n', p_migration_id);
    v_report := v_report || format('Migration Name: %s%n', v_migration.migration_name);
    v_report := v_report || format('Status: %s%n', v_migration.status);
    v_report := v_report || format('Started: %s%n', v_migration.started_at);
    v_report := v_report || format('Completed: %s%n', v_migration.completed_at);
    v_report := v_report || format('Duration: %s%n', v_migration.completed_at - v_migration.started_at);
    v_report := v_report || format('Dry Run: %s%n', v_migration.dry_run);
    v_report := v_report || format('Created By: %s%n%n', v_migration.created_by);

    v_report := v_report || format('STATISTICS:%n');
    v_report := v_report || format('Total Commits: %s%n', v_migration.total_commits);
    v_report := v_report || format('Processed Commits: %s%n', v_migration.processed_commits);
    v_report := v_report || format('Created Changes: %s%n', v_migration.created_changes);
    v_report := v_report || format('Errors: %s%n', v_migration.errors);
    v_report := v_report || format('Warnings: %s%n%n', v_migration.warnings);

    -- Add verification results
    v_report := v_report || format('VERIFICATION RESULTS:%n');
    SELECT string_agg(format('%s: %s - %s', check_name, status, details), E'\n')
    INTO v_report
    FROM pggit_migration.verify_migration(p_migration_id);

    -- Add top errors if any
    IF v_migration.errors > 0 THEN
        v_report := v_report || format('%n%nTOP ERRORS:%n');
        SELECT string_agg(format('%s: %s', error_type, left(error_message, 100)), E'\n')
        INTO v_report
        FROM (SELECT * FROM pggit_migration.get_migration_errors(p_migration_id, 5)) errors;
    END IF;

    v_report := v_report || format('%n%nReport generated: %s', CURRENT_TIMESTAMP);

    RETURN v_report;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- METADATA AND PERMISSIONS
-- ============================================

COMMENT ON SCHEMA pggit_migration_v0 IS 'Migration tooling for pggit v1 to v2 conversion';
COMMENT ON FUNCTION pggit_migration.execute_production_migration IS 'Execute complete production migration with all phases';
COMMENT ON FUNCTION pggit_migration.rollback_migration IS 'Emergency rollback procedure for failed migrations';
COMMENT ON FUNCTION pggit_migration.comprehensive_migration_verification IS 'Complete post-migration verification with auto-fix detection';
COMMENT ON FUNCTION pggit_migration.migration_health_dashboard IS 'Real-time migration health monitoring dashboard';
COMMENT ON FUNCTION pggit_migration.pre_migration_health_check IS 'Pre-migration readiness verification';
COMMENT ON FUNCTION pggit_migration.generate_migration_report IS 'Generate comprehensive migration report for documentation';

-- Grant appropriate permissions
GRANT USAGE ON SCHEMA pggit_migration TO PUBLIC;
GRANT SELECT ON ALL TABLES IN SCHEMA pggit_migration TO PUBLIC;
GRANT INSERT, UPDATE ON pggit_migration.migration_status TO PUBLIC;
GRANT INSERT ON pggit_migration.migration_errors TO PUBLIC;
GRANT INSERT ON pggit_migration.migration_verification TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pggit_migration TO PUBLIC;

-- ============================================
-- INITIALIZATION COMPLETE
-- ============================================

DO $$
BEGIN
    RAISE NOTICE 'pgGit Migration Execution initialized successfully';
    RAISE NOTICE 'Production cutover scripts and rollback procedures ready';
    RAISE NOTICE 'Run pre_migration_health_check() before production migration';
END $$;</content>
<parameter name="filePath">sql/pggit_migration_execution.sql