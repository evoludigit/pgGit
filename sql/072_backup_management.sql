-- =====================================================
-- pgGit Backup Management & Monitoring
-- Phase 2 Stabilization
-- =====================================================
--
-- This module provides health monitoring, worker management,
-- and operational utilities for the backup automation system.
--

-- =====================================================
-- Health Monitoring
-- =====================================================

-- Get backup system health status
CREATE OR REPLACE FUNCTION pggit.get_backup_health()
RETURNS TABLE (
    metric TEXT,
    value BIGINT,
    status TEXT,
    threshold BIGINT,
    description TEXT
) AS $$
BEGIN
    -- Jobs in queue waiting to be processed
    RETURN QUERY
    SELECT
        'queued_jobs'::TEXT,
        COUNT(*)::BIGINT,
        CASE
            WHEN COUNT(*) > 100 THEN 'critical'
            WHEN COUNT(*) > 50 THEN 'warning'
            ELSE 'ok'
        END::TEXT,
        50::BIGINT,
        'Number of jobs waiting in queue'::TEXT
    FROM pggit.backup_jobs j
    WHERE j.status = 'queued';

    -- Jobs currently running
    RETURN QUERY
    SELECT
        'running_jobs'::TEXT,
        COUNT(*)::BIGINT,
        CASE
            WHEN COUNT(*) > 20 THEN 'warning'
            ELSE 'ok'
        END::TEXT,
        20::BIGINT,
        'Number of jobs currently executing'::TEXT
    FROM pggit.backup_jobs j
    WHERE j.status = 'running';

    -- Failed jobs requiring attention
    RETURN QUERY
    SELECT
        'failed_jobs'::TEXT,
        COUNT(*)::BIGINT,
        CASE
            WHEN COUNT(*) > 10 THEN 'critical'
            WHEN COUNT(*) > 5 THEN 'warning'
            ELSE 'ok'
        END::TEXT,
        5::BIGINT,
        'Jobs failed after max retries'::TEXT
    FROM pggit.backup_jobs j
    WHERE j.status = 'failed'
      AND j.attempts >= j.max_attempts;

    -- Oldest queued job (minutes)
    RETURN QUERY
    SELECT
        'oldest_queued_minutes'::TEXT,
        COALESCE(
            EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MIN(j.created_at)))::BIGINT / 60,
            0
        ),
        CASE
            WHEN EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MIN(j.created_at))) / 60 > 60 THEN 'critical'
            WHEN EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MIN(j.created_at))) / 60 > 30 THEN 'warning'
            ELSE 'ok'
        END::TEXT,
        30::BIGINT,
        'Age of oldest queued job in minutes'::TEXT
    FROM pggit.backup_jobs j
    WHERE j.status = 'queued';

    -- Active workers (last 5 minutes)
    RETURN QUERY
    SELECT
        'active_workers'::TEXT,
        COUNT(DISTINCT j.metadata->>'worker_id')::BIGINT,
        CASE
            WHEN COUNT(DISTINCT j.metadata->>'worker_id') = 0 THEN 'critical'
            WHEN COUNT(DISTINCT j.metadata->>'worker_id') < 2 THEN 'warning'
            ELSE 'ok'
        END::TEXT,
        2::BIGINT,
        'Number of workers active in last 5 minutes'::TEXT
    FROM pggit.backup_jobs j
    WHERE j.started_at > CURRENT_TIMESTAMP - INTERVAL '5 minutes';

    -- Backups completed today
    RETURN QUERY
    SELECT
        'backups_completed_today'::TEXT,
        COUNT(*)::BIGINT,
        'info'::TEXT,
        0::BIGINT,
        'Backups completed in last 24 hours'::TEXT
    FROM pggit.backups b
    WHERE b.status = 'completed'
      AND b.completed_at > CURRENT_TIMESTAMP - INTERVAL '24 hours';
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.get_backup_health IS
'Get health metrics for backup system with status thresholds';

-- =====================================================
-- Worker Management
-- =====================================================

-- List active workers
CREATE OR REPLACE FUNCTION pggit.list_active_workers(
    p_since_minutes INTEGER DEFAULT 10
)
RETURNS TABLE (
    worker_id TEXT,
    jobs_processed BIGINT,
    jobs_successful BIGINT,
    jobs_failed BIGINT,
    last_activity TIMESTAMPTZ,
    status TEXT
) AS $$
BEGIN
    -- ✅ INPUT VALIDATION: NULL and range checks
    IF p_since_minutes IS NULL THEN
        RAISE EXCEPTION 'Parameter p_since_minutes cannot be NULL'
            USING ERRCODE = '22004',  -- null_value_not_allowed
                  HINT = 'Provide a positive integer for minutes';
    END IF;

    IF p_since_minutes < 1 THEN
        RAISE EXCEPTION 'Since minutes must be positive, got: %', p_since_minutes
            USING ERRCODE = '22003',  -- numeric_value_out_of_range
                  HINT = 'Use a value between 1 and 1440 (1 day)';
    END IF;

    IF p_since_minutes > 1440 THEN  -- 1 day max
        RAISE WARNING 'Unusually long lookback (% minutes), are you sure?', p_since_minutes;
    END IF;

    RETURN QUERY
    SELECT
        j.metadata->>'worker_id' AS worker_id,
        COUNT(*)::BIGINT AS jobs_processed,
        COUNT(*) FILTER (WHERE j.status = 'completed')::BIGINT AS jobs_successful,
        COUNT(*) FILTER (WHERE j.status = 'failed')::BIGINT AS jobs_failed,
        MAX(j.started_at) AS last_activity,
        CASE
            WHEN MAX(j.started_at) > CURRENT_TIMESTAMP - INTERVAL '2 minutes' THEN 'active'
            WHEN MAX(j.started_at) > CURRENT_TIMESTAMP - INTERVAL '10 minutes' THEN 'idle'
            ELSE 'inactive'
        END::TEXT AS status
    FROM pggit.backup_jobs j
    WHERE j.metadata ? 'worker_id'
      AND j.started_at > CURRENT_TIMESTAMP - (p_since_minutes || ' minutes')::INTERVAL
    GROUP BY j.metadata->>'worker_id'
    ORDER BY last_activity DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.list_active_workers IS
'List all workers and their activity in the specified time window';

-- Get worker statistics
CREATE OR REPLACE FUNCTION pggit.get_worker_stats(
    p_worker_id TEXT,
    p_since_hours INTEGER DEFAULT 24
)
RETURNS TABLE (
    total_jobs BIGINT,
    completed BIGINT,
    failed BIGINT,
    avg_duration_seconds NUMERIC,
    success_rate NUMERIC
) AS $$
BEGIN
    -- ✅ INPUT VALIDATION: NULL and range checks for worker stats
    IF p_worker_id IS NULL THEN
        RAISE EXCEPTION 'Parameter p_worker_id cannot be NULL'
            USING ERRCODE = '22004',  -- null_value_not_allowed
                  HINT = 'Provide a worker ID string';
    END IF;

    IF p_since_hours IS NULL THEN
        RAISE EXCEPTION 'Parameter p_since_hours cannot be NULL'
            USING ERRCODE = '22004',  -- null_value_not_allowed
                  HINT = 'Provide a positive integer for hours';
    END IF;

    IF p_since_hours < 1 THEN
        RAISE EXCEPTION 'Since hours must be positive, got: %', p_since_hours
            USING ERRCODE = '22003',  -- numeric_value_out_of_range
                  HINT = 'Use a value between 1 and 720 (30 days)';
    END IF;

    IF p_since_hours > 720 THEN  -- 30 days max
        RAISE WARNING 'Unusually long lookback (% hours), are you sure?', p_since_hours;
    END IF;
    RETURN QUERY
    SELECT
        COUNT(*)::BIGINT,
        COUNT(*) FILTER (WHERE j.status = 'completed')::BIGINT,
        COUNT(*) FILTER (WHERE j.status = 'failed')::BIGINT,
        AVG(EXTRACT(EPOCH FROM (COALESCE(j.completed_at, CURRENT_TIMESTAMP) - j.started_at)))::NUMERIC,
        (COUNT(*) FILTER (WHERE j.status = 'completed')::NUMERIC / NULLIF(COUNT(*), 0) * 100)::NUMERIC
    FROM pggit.backup_jobs j
    WHERE j.metadata->>'worker_id' = p_worker_id
      AND j.started_at > CURRENT_TIMESTAMP - (p_since_hours || ' hours')::INTERVAL;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.get_worker_stats IS
'Get detailed statistics for a specific worker';

-- =====================================================
-- Job Cleanup
-- =====================================================

-- Clean up old completed jobs
CREATE OR REPLACE FUNCTION pggit.cleanup_old_jobs(
    p_retention_days INTEGER DEFAULT 7,
    p_dry_run BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
    action TEXT,
    job_count BIGINT,
    details JSONB
) AS $$
DECLARE
    v_deleted_count BIGINT;
BEGIN
    -- ✅ INPUT VALIDATION: NULL checks and range validation for cleanup
    IF p_retention_days IS NULL THEN
        RAISE EXCEPTION 'Parameter p_retention_days cannot be NULL'
            USING ERRCODE = '22004',  -- null_value_not_allowed
                  HINT = 'Provide a positive integer for retention days';
    END IF;

    IF p_dry_run IS NULL THEN
        p_dry_run := TRUE;  -- Safe default for destructive operations
    END IF;

    IF p_retention_days < 1 THEN
        RAISE EXCEPTION 'Retention days must be positive, got: %', p_retention_days
            USING ERRCODE = '22003',  -- numeric_value_out_of_range
                  HINT = 'Use a value between 1 and 3650';
    END IF;

    IF p_retention_days > 3650 THEN  -- 10 years max
        RAISE WARNING 'Unusually long retention (% days), are you sure?', p_retention_days;
    END IF;

    IF p_dry_run THEN
        -- Show what would be deleted
        RETURN QUERY
        SELECT
            'would_delete'::TEXT,
            COUNT(*)::BIGINT,
            jsonb_build_object(
                'retention_days', p_retention_days,
                'cutoff_date', CURRENT_TIMESTAMP - (p_retention_days || ' days')::INTERVAL
            )
        FROM pggit.backup_jobs j
        WHERE j.status IN ('completed', 'cancelled')
          AND j.completed_at < CURRENT_TIMESTAMP - (p_retention_days || ' days')::INTERVAL;
    ELSE
        -- Actually delete
        WITH deleted AS (
            DELETE FROM pggit.backup_jobs j
            WHERE j.status IN ('completed', 'cancelled')
              AND j.completed_at < CURRENT_TIMESTAMP - (p_retention_days || ' days')::INTERVAL
            RETURNING j.job_id
        )
        SELECT COUNT(*)::BIGINT INTO v_deleted_count FROM deleted;

        RETURN QUERY
        SELECT
            'deleted'::TEXT,
            v_deleted_count,
            jsonb_build_object(
                'retention_days', p_retention_days,
                'deleted_count', v_deleted_count
            );
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.cleanup_old_jobs IS
'Delete old completed and cancelled jobs to prevent table bloat';

-- Cancel stuck jobs
CREATE OR REPLACE FUNCTION pggit.cancel_stuck_jobs(
    p_timeout_minutes INTEGER DEFAULT 60,
    p_dry_run BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
    action TEXT,
    job_id UUID,
    backup_name TEXT,
    running_since TIMESTAMPTZ,
    stuck_minutes BIGINT
) AS $$
BEGIN
    -- ✅ INPUT VALIDATION: NULL checks and range validation for stuck job cancellation
    IF p_timeout_minutes IS NULL THEN
        RAISE EXCEPTION 'Parameter p_timeout_minutes cannot be NULL'
            USING ERRCODE = '22004',  -- null_value_not_allowed
                  HINT = 'Provide a positive integer for timeout minutes';
    END IF;

    IF p_dry_run IS NULL THEN
        p_dry_run := TRUE;  -- Safe default for destructive operations
    END IF;

    IF p_timeout_minutes < 1 THEN
        RAISE EXCEPTION 'Timeout minutes must be positive, got: %', p_timeout_minutes
            USING ERRCODE = '22003',  -- numeric_value_out_of_range
                  HINT = 'Use a value between 1 and 10080 (1 week)';
    END IF;

    IF p_timeout_minutes > 10080 THEN  -- 1 week max
        RAISE WARNING 'Unusually long timeout (% minutes), are you sure?', p_timeout_minutes;
    END IF;

    IF p_dry_run THEN
        -- Show what would be cancelled
        RETURN QUERY
        SELECT
            'would_cancel'::TEXT,
            j.job_id,
            b.backup_name,
            j.started_at,
            EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - j.started_at))::BIGINT / 60
        FROM pggit.backup_jobs j
        JOIN pggit.backups b ON j.backup_id = b.backup_id
        WHERE j.status = 'running'
          AND j.started_at < CURRENT_TIMESTAMP - (p_timeout_minutes || ' minutes')::INTERVAL
        ORDER BY j.started_at ASC;
    ELSE
        -- Actually cancel
        RETURN QUERY
        WITH cancelled AS (
            UPDATE pggit.backup_jobs j
            SET status = 'cancelled',
                completed_at = CURRENT_TIMESTAMP,
                last_error = format('Cancelled after %s minutes timeout', p_timeout_minutes)
            WHERE j.status = 'running'
              AND j.started_at < CURRENT_TIMESTAMP - (p_timeout_minutes || ' minutes')::INTERVAL
            RETURNING j.job_id, j.backup_id, j.started_at
        )
        SELECT
            'cancelled'::TEXT,
            c.job_id,
            b.backup_name,
            c.started_at,
            EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - c.started_at))::BIGINT / 60
        FROM cancelled c
        JOIN pggit.backups b ON c.backup_id = b.backup_id
        ORDER BY c.started_at ASC;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.cancel_stuck_jobs IS
'Cancel jobs that have been running longer than the timeout threshold';

-- =====================================================
-- Metrics and Analytics
-- =====================================================

-- Get backup statistics
CREATE OR REPLACE FUNCTION pggit.get_backup_stats(
    p_since_days INTEGER DEFAULT 30
)
RETURNS TABLE (
    metric TEXT,
    value NUMERIC,
    unit TEXT
) AS $$
BEGIN
    -- ✅ INPUT VALIDATION: NULL and range checks for backup stats
    IF p_since_days IS NULL THEN
        RAISE EXCEPTION 'Parameter p_since_days cannot be NULL'
            USING ERRCODE = '22004',  -- null_value_not_allowed
                  HINT = 'Provide a positive integer for days';
    END IF;

    IF p_since_days < 1 THEN
        RAISE EXCEPTION 'Since days must be positive, got: %', p_since_days
            USING ERRCODE = '22003',  -- numeric_value_out_of_range
                  HINT = 'Use a value between 1 and 365';
    END IF;

    IF p_since_days > 365 THEN  -- 1 year max
        RAISE WARNING 'Unusually long lookback (% days), are you sure?', p_since_days;
    END IF;

    -- Total backups created
    RETURN QUERY
    SELECT
        'total_backups'::TEXT,
        COUNT(*)::NUMERIC,
        'backups'::TEXT
    FROM pggit.backups b
    WHERE b.started_at > CURRENT_TIMESTAMP - (p_since_days || ' days')::INTERVAL;

    -- Successful backups
    RETURN QUERY
    SELECT
        'successful_backups'::TEXT,
        COUNT(*)::NUMERIC,
        'backups'::TEXT
    FROM pggit.backups b
    WHERE b.status = 'completed'
      AND b.started_at > CURRENT_TIMESTAMP - (p_since_days || ' days')::INTERVAL;

    -- Success rate
    RETURN QUERY
    SELECT
        'success_rate'::TEXT,
        (COUNT(*) FILTER (WHERE b.status = 'completed')::NUMERIC /
         NULLIF(COUNT(*), 0) * 100)::NUMERIC,
        'percent'::TEXT
    FROM pggit.backups b
    WHERE b.started_at > CURRENT_TIMESTAMP - (p_since_days || ' days')::INTERVAL;

    -- Total backup size
    RETURN QUERY
    SELECT
        'total_size'::TEXT,
        COALESCE(SUM(b.backup_size), 0)::NUMERIC,
        'bytes'::TEXT
    FROM pggit.backups b
    WHERE b.status = 'completed'
      AND b.started_at > CURRENT_TIMESTAMP - (p_since_days || ' days')::INTERVAL;

    -- Average backup duration
    RETURN QUERY
    SELECT
        'avg_duration'::TEXT,
        AVG(EXTRACT(EPOCH FROM (b.completed_at - b.started_at)))::NUMERIC,
        'seconds'::TEXT
    FROM pggit.backups b
    WHERE b.status = 'completed'
      AND b.started_at > CURRENT_TIMESTAMP - (p_since_days || ' days')::INTERVAL;

    -- Average job retry rate
    RETURN QUERY
    SELECT
        'avg_retry_rate'::TEXT,
        AVG(j.attempts - 1)::NUMERIC,
        'retries'::TEXT
    FROM pggit.backup_jobs j
    WHERE j.status = 'completed'
      AND j.created_at > CURRENT_TIMESTAMP - (p_since_days || ' days')::INTERVAL;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.get_backup_stats IS
'Get statistical summary of backup operations';

-- Get tool usage breakdown
CREATE OR REPLACE FUNCTION pggit.get_tool_usage_stats(
    p_since_days INTEGER DEFAULT 30
)
RETURNS TABLE (
    tool TEXT,
    total_backups BIGINT,
    successful BIGINT,
    failed BIGINT,
    success_rate NUMERIC,
    total_size BIGINT,
    avg_duration_seconds NUMERIC
) AS $$
BEGIN
    -- ✅ INPUT VALIDATION: NULL and range checks for tool usage stats
    IF p_since_days IS NULL THEN
        RAISE EXCEPTION 'Parameter p_since_days cannot be NULL'
            USING ERRCODE = '22004',  -- null_value_not_allowed
                  HINT = 'Provide a positive integer for days';
    END IF;

    IF p_since_days < 1 THEN
        RAISE EXCEPTION 'Since days must be positive, got: %', p_since_days
            USING ERRCODE = '22003',  -- numeric_value_out_of_range
                  HINT = 'Use a value between 1 and 365';
    END IF;

    IF p_since_days > 365 THEN  -- 1 year max
        RAISE WARNING 'Unusually long lookback (% days), are you sure?', p_since_days;
    END IF;

    RETURN QUERY
    SELECT
        b.backup_tool,
        COUNT(*)::BIGINT,
        COUNT(*) FILTER (WHERE b.status = 'completed')::BIGINT,
        COUNT(*) FILTER (WHERE b.status = 'failed')::BIGINT,
        (COUNT(*) FILTER (WHERE b.status = 'completed')::NUMERIC /
         NULLIF(COUNT(*), 0) * 100)::NUMERIC,
        COALESCE(SUM(b.backup_size) FILTER (WHERE b.status = 'completed'), 0)::BIGINT,
        AVG(EXTRACT(EPOCH FROM (b.completed_at - b.started_at)))::NUMERIC
    FROM pggit.backups b
    WHERE b.started_at > CURRENT_TIMESTAMP - (p_since_days || ' days')::INTERVAL
    GROUP BY b.backup_tool
    ORDER BY total_backups DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.get_tool_usage_stats IS
'Get usage statistics broken down by backup tool';

-- =====================================================
-- Monitoring Views
-- =====================================================

-- System health dashboard view
CREATE OR REPLACE VIEW pggit.backup_system_health AS
SELECT
    metric,
    value,
    status,
    threshold,
    description,
    CASE status
        WHEN 'critical' THEN '🔴'
        WHEN 'warning' THEN '🟡'
        WHEN 'ok' THEN '🟢'
        ELSE 'ℹ️'
    END AS indicator
FROM pggit.get_backup_health()
ORDER BY
    CASE status
        WHEN 'critical' THEN 1
        WHEN 'warning' THEN 2
        WHEN 'ok' THEN 3
        ELSE 4
    END,
    metric;

COMMENT ON VIEW pggit.backup_system_health IS
'Real-time health dashboard for backup system';

-- Recent failures view
CREATE OR REPLACE VIEW pggit.recent_backup_failures AS
SELECT
    b.backup_id,
    b.backup_name,
    b.backup_tool,
    b.started_at,
    b.error_message,
    j.job_id,
    j.attempts,
    j.last_error AS job_error,
    j.metadata->>'worker_id' AS failed_worker
FROM pggit.backups b
LEFT JOIN pggit.backup_jobs j ON b.backup_id = j.backup_id
WHERE b.status = 'failed'
  AND b.started_at > CURRENT_TIMESTAMP - INTERVAL '7 days'
ORDER BY b.started_at DESC
LIMIT 50;

COMMENT ON VIEW pggit.recent_backup_failures IS
'Recent backup failures for troubleshooting';

-- =====================================================
-- Utility Functions
-- =====================================================

-- Reset failed job for manual retry
CREATE OR REPLACE FUNCTION pggit.reset_job(
    p_job_id UUID
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE pggit.backup_jobs j
    SET status = 'queued',
        attempts = 0,
        next_retry_at = NULL,
        last_error = NULL,
        started_at = NULL,
        completed_at = NULL
    WHERE j.job_id = p_job_id
      AND j.status IN ('failed', 'cancelled');

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.reset_job IS
'Reset a failed or cancelled job for manual retry';

-- Pause all new jobs (maintenance mode)
CREATE OR REPLACE FUNCTION pggit.set_maintenance_mode(
    p_enabled BOOLEAN,
    p_reason TEXT DEFAULT 'Manual maintenance'
)
RETURNS JSONB AS $$
DECLARE
    v_affected_count INTEGER;
BEGIN
    IF p_enabled THEN
        -- Mark queued jobs as paused
        WITH paused AS (
            UPDATE pggit.backup_jobs j
            SET status = 'paused',
                metadata = j.metadata || jsonb_build_object(
                    'paused_at', CURRENT_TIMESTAMP,
                    'pause_reason', p_reason,
                    'original_status', j.status
                )
            WHERE j.status IN ('queued', 'failed')
              AND (j.metadata->>'paused_at' IS NULL)
            RETURNING j.job_id
        )
        SELECT COUNT(*)::INTEGER INTO v_affected_count FROM paused;

        RETURN jsonb_build_object(
            'maintenance_mode', true,
            'paused_jobs', v_affected_count,
            'reason', p_reason,
            'timestamp', CURRENT_TIMESTAMP
        );
    ELSE
        -- Unpause jobs
        WITH unpaused AS (
            UPDATE pggit.backup_jobs j
            SET status = COALESCE(j.metadata->>'original_status', 'queued'),
                metadata = j.metadata - 'paused_at' - 'pause_reason' - 'original_status'
            WHERE j.status = 'paused'
            RETURNING j.job_id
        )
        SELECT COUNT(*)::INTEGER INTO v_affected_count FROM unpaused;

        RETURN jsonb_build_object(
            'maintenance_mode', false,
            'resumed_jobs', v_affected_count,
            'timestamp', CURRENT_TIMESTAMP
        );
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.set_maintenance_mode IS
'Enable or disable maintenance mode (pauses new job processing)';
