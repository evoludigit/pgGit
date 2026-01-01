-- =====================================================
-- pgGit Backup Recovery Workflows
-- Phase 3: Recovery Planning & Execution
-- =====================================================
--
-- This module provides recovery planning, backup verification,
-- and retention policy management for disaster recovery and
-- point-in-time cloning scenarios.
--

-- =====================================================
-- Helper Functions
-- =====================================================

-- Helper function for JSONB retention policy validation
CREATE OR REPLACE FUNCTION pggit.validate_retention_policy(
    p_policy JSONB
)
RETURNS TABLE (
    full_days INTEGER,
    incremental_days INTEGER
) AS $$
DECLARE
    v_full_days INTEGER;
    v_incr_days INTEGER;
BEGIN
    -- Handle NULL policy with safe defaults
    IF p_policy IS NULL THEN
        p_policy := '{"full_days": 30, "incremental_days": 7}'::JSONB;
    END IF;

    -- Validate required keys exist
    IF NOT (p_policy ? 'full_days') THEN
        RAISE EXCEPTION 'Policy missing required key: full_days'
            USING ERRCODE = '22023',  -- invalid_parameter_value
                  HINT = 'Provide JSON like: {"full_days": 30, "incremental_days": 7}';
    END IF;

    IF NOT (p_policy ? 'incremental_days') THEN
        RAISE EXCEPTION 'Policy missing required key: incremental_days'
            USING ERRCODE = '22023';
    END IF;

    -- Extract and validate values with type safety
    BEGIN
        v_full_days := (p_policy->>'full_days')::INTEGER;
        v_incr_days := (p_policy->>'incremental_days')::INTEGER;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Invalid policy format: %', SQLERRM
            USING ERRCODE = '22023',
                  HINT = 'Ensure days are valid integers';
    END;

    -- Range validation
    IF v_full_days < 1 OR v_full_days > 3650 THEN
        RAISE EXCEPTION 'full_days out of range: % (must be 1-3650)', v_full_days
            USING ERRCODE = '22003';
    END IF;

    IF v_incr_days < 1 OR v_incr_days > 365 THEN
        RAISE EXCEPTION 'incremental_days out of range: % (must be 1-365)', v_incr_days
            USING ERRCODE = '22003';
    END IF;

    RETURN QUERY SELECT v_full_days, v_incr_days;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.validate_retention_policy IS
'Reusable helper for validating retention policy JSONB structures';

-- =====================================================
-- Recovery Planning
-- =====================================================

-- Find best backup for a given commit
CREATE OR REPLACE FUNCTION pggit.find_backup_for_commit(
    p_commit_hash TEXT
)
RETURNS TABLE (
    backup_id UUID,
    backup_name TEXT,
    backup_type TEXT,
    backup_tool TEXT,
    location TEXT,
    time_distance_seconds BIGINT,
    exact_match BOOLEAN
) AS $$
BEGIN
    -- ✅ INPUT VALIDATION: NULL and empty string checks for commit hash
    IF p_commit_hash IS NULL THEN
        RAISE EXCEPTION 'Parameter p_commit_hash cannot be NULL'
            USING ERRCODE = '22004',  -- null_value_not_allowed
                  HINT = 'Provide a commit hash string';
    END IF;

    IF p_commit_hash = '' THEN
        RAISE EXCEPTION 'Parameter p_commit_hash cannot be empty'
            USING ERRCODE = '22023',  -- invalid_parameter_value
                  HINT = 'Provide a non-empty commit hash';
    END IF;

    -- Find backups for this exact commit, or closest in time
    RETURN QUERY
    WITH commit_info AS (
        SELECT hash, committed_at
        FROM pggit.commits
        WHERE hash = p_commit_hash
    )
    SELECT
        b.backup_id,
        b.backup_name,
        b.backup_type,
        b.backup_tool,
        b.location,
        ABS(EXTRACT(EPOCH FROM (b.completed_at - ci.committed_at)))::BIGINT AS time_distance,
        (b.commit_hash = p_commit_hash) AS exact_match
    FROM pggit.backups b, commit_info ci
    WHERE b.status = 'completed'
      AND (
          b.commit_hash = p_commit_hash  -- Exact match
          OR b.completed_at <= ci.committed_at + INTERVAL '1 hour'  -- Close in time
      )
    ORDER BY exact_match DESC, time_distance ASC
    LIMIT 5;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.find_backup_for_commit IS
'Find the best backup for restoring to a specific commit';

-- Generate comprehensive recovery plan
CREATE OR REPLACE FUNCTION pggit.generate_recovery_plan(
    p_target_commit TEXT,
    p_recovery_mode TEXT DEFAULT 'disaster',  -- 'disaster' or 'clone'
    p_preferred_tool TEXT DEFAULT NULL,
    p_clone_target TEXT DEFAULT NULL  -- For clone mode: target database/cluster
)
RETURNS TABLE (
    step_number INTEGER,
    step_type TEXT,
    description TEXT,
    command TEXT,
    details JSONB
) AS $$
DECLARE
    v_backup RECORD;
    v_step INTEGER := 0;
BEGIN
    -- ✅ INPUT VALIDATION: NULL, empty string, and enum checks for recovery plan
    IF p_target_commit IS NULL THEN
        RAISE EXCEPTION 'Parameter p_target_commit cannot be NULL'
            USING ERRCODE = '22004',  -- null_value_not_allowed
                  HINT = 'Provide a target commit hash string';
    END IF;

    IF p_target_commit = '' THEN
        RAISE EXCEPTION 'Parameter p_target_commit cannot be empty'
            USING ERRCODE = '22023',  -- invalid_parameter_value
                  HINT = 'Provide a non-empty commit hash';
    END IF;

    IF p_recovery_mode IS NULL THEN
        p_recovery_mode := 'disaster';  -- Safe default for recovery operations
    END IF;

    IF p_recovery_mode NOT IN ('disaster', 'clone') THEN
        RAISE EXCEPTION 'Invalid recovery mode: %. Use "disaster" or "clone"', p_recovery_mode
            USING ERRCODE = '22023',  -- invalid_parameter_value
                  HINT = 'Valid modes are: disaster, clone';
    END IF;

    -- Validate recovery mode
    IF p_recovery_mode NOT IN ('disaster', 'clone') THEN
        RAISE EXCEPTION 'Invalid recovery mode: %. Use "disaster" or "clone"', p_recovery_mode;
    END IF;

    -- Find best backup
    SELECT * INTO v_backup
    FROM pggit.find_backup_for_commit(p_target_commit)
    WHERE (p_preferred_tool IS NULL OR backup_tool = p_preferred_tool)
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No suitable backup found for commit %', p_target_commit;
    END IF;

    IF p_recovery_mode = 'disaster' THEN
        -- DISASTER RECOVERY MODE (requires downtime)

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'prepare'::TEXT,
            '🛑 Stop PostgreSQL service'::TEXT,
            'sudo systemctl stop postgresql'::TEXT,
            jsonb_build_object(
                'downtime', true,
                'mode', 'disaster',
                'backup_id', v_backup.backup_id
            );

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'backup_current'::TEXT,
            '💾 Backup current data directory (safety)'::TEXT,
            'sudo mv /var/lib/postgresql/data /var/lib/postgresql/data.backup.'
                || to_char(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MISS'),
            jsonb_build_object('reversible', true);

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'restore'::TEXT,
            format('📦 Restore from %s backup %s', v_backup.backup_tool, v_backup.backup_name),
            CASE v_backup.backup_tool
                WHEN 'pgbackrest' THEN 'pgbackrest --stanza=main --delta restore'
                WHEN 'barman' THEN format('barman recover main %s /var/lib/postgresql/data', v_backup.backup_name)
                WHEN 'pg_dump' THEN format('createdb recovered && pg_restore -d recovered %s', v_backup.location)
                ELSE 'Manual restore required - consult backup tool documentation'
            END,
            jsonb_build_object(
                'backup_id', v_backup.backup_id,
                'location', v_backup.location,
                'tool', v_backup.backup_tool
            );

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'start'::TEXT,
            '▶️  Start PostgreSQL service'::TEXT,
            'sudo systemctl start postgresql'::TEXT,
            jsonb_build_object('wait_for_startup', true);

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'verify'::TEXT,
            '✅ Verify database integrity'::TEXT,
            'psql -c "SELECT COUNT(*) FROM pggit.commits"'::TEXT,
            jsonb_build_object('requires_running_db', true);

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'info'::TEXT,
            format('ℹ️  Recovery complete to commit %s', p_target_commit),
            format('Database restored from backup %s', v_backup.backup_name),
            jsonb_build_object(
                'final_step', true,
                'target_commit', p_target_commit,
                'backup_used', v_backup.backup_name
            );

    ELSIF p_recovery_mode = 'clone' THEN
        -- LIVE CLONE MODE (zero downtime, parallel restore)

        IF p_clone_target IS NULL THEN
            RAISE EXCEPTION 'Clone mode requires p_clone_target parameter (e.g., new cluster path or database name)';
        END IF;

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'prepare'::TEXT,
            '📁 Prepare clone target directory'::TEXT,
            format('sudo mkdir -p %s && sudo chown postgres:postgres %s', p_clone_target, p_clone_target),
            jsonb_build_object(
                'downtime', false,
                'mode', 'clone',
                'target', p_clone_target
            );

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'restore'::TEXT,
            format('📦 Restore backup to clone target: %s', p_clone_target),
            CASE v_backup.backup_tool
                WHEN 'pgbackrest' THEN format('pgbackrest --stanza=main --delta --pg1-path=%s restore', p_clone_target)
                WHEN 'barman' THEN format('barman recover main %s %s', v_backup.backup_name, p_clone_target)
                WHEN 'pg_dump' THEN format('createdb %s && pg_restore -d %s %s', p_clone_target, p_clone_target, v_backup.location)
                ELSE 'Manual restore to clone target required'
            END,
            jsonb_build_object(
                'backup_id', v_backup.backup_id,
                'target', p_clone_target
            );

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'configure'::TEXT,
            '⚙️  Configure clone cluster (different port, etc.)'::TEXT,
            format('Edit %s/postgresql.conf: set port = 5433', p_clone_target),
            jsonb_build_object('manual_step', true);

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'start_clone'::TEXT,
            '▶️  Start clone cluster'::TEXT,
            format('pg_ctl -D %s start', p_clone_target),
            jsonb_build_object('wait_for_startup', true);

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'verify'::TEXT,
            '✅ Verify clone integrity'::TEXT,
            'psql -p 5433 -c "SELECT COUNT(*) FROM pggit.commits"',
            jsonb_build_object('clone_operation', true);

        v_step := v_step + 1;
        RETURN QUERY SELECT
            v_step,
            'info'::TEXT,
            'ℹ️  Clone ready for testing/switchover'::TEXT,
            format('Clone running on port 5433. Test, then optionally switch production traffic.'),
            jsonb_build_object(
                'final_step', true,
                'clone_location', p_clone_target,
                'target_commit', p_target_commit
            );
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.generate_recovery_plan IS
'Generate step-by-step recovery plan for disaster recovery or live clone';

-- Execute recovery (dry-run by default)
CREATE OR REPLACE FUNCTION pggit.restore_from_commit(
    p_target_commit TEXT,
    p_dry_run BOOLEAN DEFAULT TRUE,
    p_recovery_mode TEXT DEFAULT 'disaster'
)
RETURNS TABLE (
    step_number INTEGER,
    status TEXT,
    output TEXT
) AS $$
BEGIN
    IF p_dry_run THEN
        -- Just show the plan
        RETURN QUERY
        SELECT
            s.step_number,
            'planned'::TEXT AS status,
            s.description AS output
        FROM pggit.generate_recovery_plan(p_target_commit, p_recovery_mode) s;
    ELSE
        -- Actual execution requires external orchestration
        RAISE NOTICE 'Actual recovery execution requires external orchestration service';
        RAISE NOTICE 'Run: pggit-recovery-orchestrator restore-to-commit %', p_target_commit;

        RETURN QUERY
        SELECT 1, 'info'::TEXT, 'Recovery plan generated - manual execution required'::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.restore_from_commit IS
'Execute recovery to specific commit (dry-run shows plan only)';

-- =====================================================
-- Backup Verification
-- =====================================================

-- Verify backup integrity
CREATE OR REPLACE FUNCTION pggit.verify_backup(
    p_backup_id UUID,
    p_verification_type TEXT DEFAULT 'checksum'
)
RETURNS UUID AS $$
DECLARE
    v_verification_id UUID := gen_random_uuid();
    v_backup RECORD;
BEGIN
    -- ✅ INPUT VALIDATION: NULL check and existence validation for backup
    IF p_backup_id IS NULL THEN
        RAISE EXCEPTION 'Backup ID cannot be NULL'
            USING ERRCODE = '22004';
    END IF;

    -- Verify backup exists
    SELECT * INTO v_backup
    FROM pggit.backups
    WHERE backup_id = p_backup_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Backup not found: %', p_backup_id
            USING ERRCODE = '02000',  -- no_data_found
                  HINT = 'Check backup_id is correct';
    END IF;

    -- ✅ IDEMPOTENT: Check for existing verification of same type
    SELECT verification_id INTO v_verification_id
    FROM pggit.backup_verifications
    WHERE backup_id = p_backup_id
      AND verification_type = p_verification_type
      AND status IN ('in_progress', 'completed')
      AND verified_at > CURRENT_TIMESTAMP - INTERVAL '1 hour'  -- Recent verifications only
    ORDER BY verified_at DESC
    LIMIT 1;

    -- If found, return existing verification ID (idempotent)
    IF FOUND THEN
        RETURN v_verification_id;
    END IF;

    -- Generate new ID for new verification
    v_verification_id := gen_random_uuid();

    -- Record verification attempt

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Backup % not found', p_backup_id;
    END IF;

    -- Record verification attempt
    INSERT INTO pggit.backup_verifications (
        verification_id,
        backup_id,
        verification_type,
        status,
        details
    ) VALUES (
        v_verification_id,
        p_backup_id,
        p_verification_type,
        'in_progress',
        jsonb_build_object(
            'started_at', CURRENT_TIMESTAMP,
            'tool', v_backup.backup_tool,
            'location', v_backup.location
        )
    );

    -- Trigger verification via notification
    PERFORM pg_notify('pggit_verify_backup',
                     jsonb_build_object(
                         'verification_id', v_verification_id,
                         'backup_id', p_backup_id,
                         'type', p_verification_type,
                         'tool', v_backup.backup_tool,
                         'location', v_backup.location
                     )::text);

    RAISE NOTICE 'Verification job created: %. Listener will process verification.', v_verification_id;

    RETURN v_verification_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.verify_backup IS
'Trigger backup integrity verification (async via listener)';

-- Update verification result
CREATE OR REPLACE FUNCTION pggit.update_verification_result(
    p_verification_id UUID,
    p_status TEXT,
    p_details JSONB DEFAULT '{}'
)
RETURNS BOOLEAN AS $$
BEGIN
    -- ✅ ROW-LEVEL LOCKING: Acquire exclusive lock on verification record
    -- Prevent concurrent updates to the same verification
    PERFORM 1
    FROM pggit.backup_verifications v
    WHERE v.verification_id = p_verification_id
    FOR UPDATE NOWAIT;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Verification % not found or locked by another transaction', p_verification_id
            USING ERRCODE = '55P03';  -- lock_not_available
    END IF;

    UPDATE pggit.backup_verifications v
    SET status = p_status,
        details = v.details || p_details || jsonb_build_object('completed_at', CURRENT_TIMESTAMP)
    WHERE v.verification_id = p_verification_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.update_verification_result IS
'Update verification status and details';

-- List backup verifications
CREATE OR REPLACE FUNCTION pggit.list_backup_verifications(
    p_backup_id UUID DEFAULT NULL,
    p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
    verification_id UUID,
    backup_id UUID,
    backup_name TEXT,
    verification_type TEXT,
    status TEXT,
    created_at TIMESTAMPTZ,
    details JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        v.verification_id,
        v.backup_id,
        b.backup_name,
        v.verification_type,
        v.status,
        v.verified_at AS created_at,
        v.details
    FROM pggit.backup_verifications v
    JOIN pggit.backups b ON v.backup_id = b.backup_id
    WHERE p_backup_id IS NULL OR v.backup_id = p_backup_id
    ORDER BY v.verified_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.list_backup_verifications IS
'List backup verifications with optional filtering';

-- =====================================================
-- Retention Policy Management
-- =====================================================

-- Apply retention policy
CREATE OR REPLACE FUNCTION pggit.apply_retention_policy(
    p_policy JSONB DEFAULT '{"full_days": 30, "incremental_days": 7}'
)
RETURNS TABLE (
    action TEXT,
    backup_id UUID,
    backup_name TEXT,
    reason TEXT
) AS $$
DECLARE
    v_full_retention INTERVAL;
    v_incr_retention INTERVAL;
    v_full_days INTEGER;
    v_incr_days INTEGER;
BEGIN
    -- ✅ INPUT VALIDATION: JSONB policy validation using helper function
    SELECT full_days, incremental_days
    INTO v_full_days, v_incr_days
    FROM pggit.validate_retention_policy(p_policy);

    v_full_retention := (v_full_days || ' days')::INTERVAL;
    v_incr_retention := (v_incr_days || ' days')::INTERVAL;

    -- ✅ ADVISORY LOCK: Prevent concurrent retention policy execution
    -- Use transaction-scoped advisory lock to prevent race conditions
    IF NOT pg_try_advisory_xact_lock(hashtext('apply_retention_policy')) THEN
        RAISE NOTICE 'Retention policy already running, skipping to prevent conflicts';
        RETURN;  -- Exit early, let other transaction finish
    END IF;

    -- ✅ IDEMPOTENT: Mark expired full backups (only once per backup)
    RETURN QUERY
    WITH expired AS (
        UPDATE pggit.backups b
        SET expires_at = COALESCE(b.expires_at, CURRENT_TIMESTAMP),  -- Only set if NULL
            status = CASE WHEN b.expires_at IS NULL THEN 'expired' ELSE b.status END  -- Only change status once
        WHERE b.backup_type = 'full'
          AND b.status = 'completed'
          AND b.completed_at < (CURRENT_TIMESTAMP - v_full_retention)
          AND b.expires_at IS NULL  -- Only process backups not yet marked
        RETURNING b.backup_id, b.backup_name, 'full_retention_exceeded' AS reason
    )
    SELECT 'expire'::TEXT, e.backup_id, e.backup_name, e.reason FROM expired e;

    -- ✅ IDEMPOTENT: Mark expired incremental backups (only once per backup)
    RETURN QUERY
    WITH expired AS (
        UPDATE pggit.backups b
        SET expires_at = COALESCE(b.expires_at, CURRENT_TIMESTAMP),  -- Only set if NULL
            status = CASE WHEN b.expires_at IS NULL THEN 'expired' ELSE b.status END  -- Only change status once
        WHERE b.backup_type IN ('incremental', 'differential')
          AND b.status = 'completed'
          AND b.completed_at < (CURRENT_TIMESTAMP - v_incr_retention)
          AND b.expires_at IS NULL  -- Only process backups not yet marked
        RETURNING b.backup_id, b.backup_name, 'incremental_retention_exceeded' AS reason
    )
    SELECT 'expire'::TEXT, e.backup_id, e.backup_name, e.reason FROM expired e;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.apply_retention_policy IS
'Mark backups as expired based on retention policy';

-- Delete expired backups
CREATE OR REPLACE FUNCTION pggit.cleanup_expired_backups(
    p_dry_run BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
    action TEXT,
    backup_id UUID,
    backup_name TEXT,
    location TEXT
) AS $$
DECLARE
    v_audit_id BIGINT;
    v_start_time TIMESTAMPTZ := clock_timestamp();
    v_rows_affected INTEGER := 0;
BEGIN
    -- ✅ INPUT VALIDATION: Safe default for dry-run operations
    IF p_dry_run IS NULL THEN
        p_dry_run := TRUE;  -- Safe default for destructive operations
    END IF;

    -- ✅ AUDIT LOGGING: Start operation audit
    v_audit_id := pggit.audit_operation(
        'cleanup_expired_backups',
        CASE WHEN p_dry_run THEN 'read' ELSE 'delete' END,
        jsonb_build_object('dry_run', p_dry_run)
    );

    BEGIN
        -- ✅ ADVISORY LOCK: Prevent concurrent cleanup operations
        -- Use transaction-scoped advisory lock to prevent race conditions during deletion
        IF NOT pg_try_advisory_xact_lock(hashtext('cleanup_expired_backups')) THEN
            -- Complete audit with notice (not an error)
            PERFORM pggit.complete_audit(v_audit_id, true, 'PGGIT_CONCURRENT',
                                       'Cleanup already running, skipped to prevent conflicts', 0);
            RETURN;  -- Exit early, let other transaction finish
        END IF;

        -- ✅ TRANSACTION REQUIREMENT: Destructive operations must be in explicit transaction
        IF NOT p_dry_run AND pg_current_xact_id_if_assigned() IS NULL THEN
            RAISE EXCEPTION 'cleanup_expired_backups must be called within a transaction when not in dry-run mode'
                USING ERRCODE = '25P01',  -- no_active_sql_transaction
                      HINT = 'Wrap call in BEGIN...COMMIT block to ensure atomicity';
        END IF;

    IF p_dry_run THEN
        -- Just list what would be deleted
        RETURN QUERY
        SELECT
            'would_delete'::TEXT,
            b.backup_id,
            b.backup_name,
            b.location
        FROM pggit.backups b
        WHERE b.status = 'expired'
          AND b.expires_at < CURRENT_TIMESTAMP;
    ELSE
        -- ✅ DEPENDENCY CHECK: Prevent deletion of full backups with active incremental dependents
        -- Check for incremental backups depending on full backups we're about to delete
        PERFORM 1
        FROM pggit.backups full_backup
        WHERE full_backup.status = 'expired'
          AND full_backup.backup_type = 'full'
          AND EXISTS (
              SELECT 1
              FROM pggit.backups incr_backup
              WHERE incr_backup.backup_type IN ('incremental', 'differential')
                AND incr_backup.status != 'expired'
                AND incr_backup.metadata->>'base_backup_id' = full_backup.backup_id::TEXT
          );

        IF FOUND THEN
            RAISE EXCEPTION 'Cannot delete full backups with active incremental dependents'
                USING ERRCODE = '23503',  -- foreign_key_violation
                      HINT = 'Expire dependent incrementals first, or implement force deletion flag';
        END IF;

        -- Actually delete (just update status, don't remove from DB)
        RETURN QUERY
        WITH deleted AS (
            UPDATE pggit.backups b
            SET status = 'deleted'
            WHERE b.status = 'expired'
              AND b.expires_at < CURRENT_TIMESTAMP
            RETURNING b.backup_id, b.backup_name, b.location
        )
        SELECT 'deleted'::TEXT, backup_id, backup_name, location FROM deleted;

        -- Get rows affected for audit
        GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    END IF;

    -- ✅ AUDIT LOGGING: Complete operation audit successfully
    PERFORM pggit.complete_audit(v_audit_id, true, NULL, NULL, v_rows_affected);

    EXCEPTION WHEN OTHERS THEN
        -- ✅ AUDIT LOGGING: Complete operation audit with failure
        PERFORM pggit.complete_audit(v_audit_id, false, SQLSTATE, SQLERRM, NULL);

        -- Re-raise the exception
        RAISE;
    END;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.cleanup_expired_backups IS
'Delete expired backups (dry-run shows what would be deleted)';

-- Get retention policy recommendations
CREATE OR REPLACE FUNCTION pggit.get_retention_recommendations()
RETURNS TABLE (
    recommendation TEXT,
    current_count BIGINT,
    recommended_action TEXT,
    details JSONB
) AS $$
BEGIN
    -- Check for old backups
    RETURN QUERY
    SELECT
        'old_full_backups'::TEXT,
        COUNT(*)::BIGINT,
        CASE
            WHEN COUNT(*) > 10 THEN 'Consider reducing retention or cleaning up'
            ELSE 'OK'
        END::TEXT,
        jsonb_build_object(
            'oldest_backup', MIN(b.started_at),
            'recommended_retention_days', 30
        )
    FROM pggit.backups b
    WHERE b.backup_type = 'full'
      AND b.status = 'completed'
      AND b.started_at < CURRENT_TIMESTAMP - INTERVAL '30 days';

    -- Check for orphaned incremental backups
    RETURN QUERY
    SELECT
        'orphaned_incrementals'::TEXT,
        COUNT(*)::BIGINT,
        CASE
            WHEN COUNT(*) > 0 THEN 'Clean up incrementals without full backup base'
            ELSE 'OK'
        END::TEXT,
        jsonb_build_object(
            'count', COUNT(*),
            'action', 'Review backup dependencies'
        )
    FROM pggit.backups b
    WHERE b.backup_type IN ('incremental', 'differential')
      AND b.status = 'completed'
      AND NOT EXISTS (
          SELECT 1 FROM pggit.backup_dependencies d
          WHERE d.backup_id = b.backup_id
      );

    -- Check for large backups
    RETURN QUERY
    SELECT
        'large_backups'::TEXT,
        COUNT(*)::BIGINT,
        CASE
            WHEN SUM(b.backup_size) > 1099511627776 THEN 'Monitor storage usage - over 1TB'  -- 1TB
            ELSE 'OK'
        END::TEXT,
        jsonb_build_object(
            'total_size_gb', ROUND((SUM(b.backup_size) / 1073741824)::NUMERIC, 2),
            'largest_backup_gb', ROUND((MAX(b.backup_size) / 1073741824)::NUMERIC, 2)
        )
    FROM pggit.backups b
    WHERE b.status = 'completed';
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.get_retention_recommendations IS
'Get recommendations for backup retention policy optimization';

-- =====================================================
-- Recovery Testing
-- =====================================================

-- Test backup restore (validation)
CREATE OR REPLACE FUNCTION pggit.test_backup_restore(
    p_backup_id UUID,
    p_test_type TEXT DEFAULT 'validate'  -- 'validate', 'sample_restore', 'full_test'
)
RETURNS JSONB AS $$
DECLARE
    v_backup RECORD;
    v_result JSONB;
BEGIN
    -- ✅ INPUT VALIDATION: NULL check and existence validation for backup
    IF p_backup_id IS NULL THEN
        RAISE EXCEPTION 'Backup ID cannot be NULL'
            USING ERRCODE = '22004';
    END IF;

    -- Verify backup exists
    SELECT * INTO v_backup
    FROM pggit.backups b
    WHERE b.backup_id = p_backup_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Backup not found: %', p_backup_id
            USING ERRCODE = '02000',  -- no_data_found
                  HINT = 'Check backup_id is correct';
    END IF;
    -- END VALIDATION BLOCK

    -- Create test record
    SELECT * INTO v_backup
    FROM pggit.backups b
    WHERE b.backup_id = p_backup_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Backup % not found', p_backup_id;
    END IF;

    -- Create test record
    INSERT INTO pggit.backup_verifications (
        verification_id,
        backup_id,
        verification_type,
        status,
        details
    ) VALUES (
        gen_random_uuid(),
        p_backup_id,
        'restore_test',
        'queued',
        jsonb_build_object(
            'test_type', p_test_type,
            'queued_at', CURRENT_TIMESTAMP
        )
    );

    v_result := jsonb_build_object(
        'backup_id', p_backup_id,
        'test_type', p_test_type,
        'status', 'queued',
        'message', 'Restore test queued - will be processed by listener'
    );

    RAISE NOTICE 'Restore test queued for backup %', v_backup.backup_name;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.test_backup_restore IS
'Queue a backup restore test for validation';
