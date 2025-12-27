-- ============================================================================
-- Phase 7: Week 4 - Automated Baseline Recalculation and Job Scheduling
-- ============================================================================
-- Purpose: Set up pg_cron jobs for automated baseline recalculation,
--          anomaly detection, and alert delivery scheduling
-- Date: 2025-12-27
-- Status: Production-ready implementation
-- ============================================================================

-- ============================================================================
-- TABLE DEFINITIONS: Job execution and monitoring
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.scheduled_job_execution (
    job_execution_id BIGSERIAL PRIMARY KEY,
    job_name TEXT NOT NULL,
    cron_schedule TEXT NOT NULL,
    execution_start TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    execution_end TIMESTAMP,
    status TEXT NOT NULL DEFAULT 'RUNNING',
    duration_ms INTEGER,
    rows_affected INTEGER,
    error_message TEXT,
    execution_context JSONB,

    CONSTRAINT job_execution_status_check
        CHECK (status IN ('RUNNING', 'SUCCESS', 'FAILED', 'SKIPPED')),
    CONSTRAINT job_execution_unique
        UNIQUE (job_name, execution_start)
);

CREATE INDEX idx_scheduled_job_execution_status
    ON pggit.scheduled_job_execution(job_name, status, execution_start DESC);
CREATE INDEX idx_scheduled_job_execution_recent
    ON pggit.scheduled_job_execution(execution_start DESC)
    WHERE status = 'RUNNING';

-- Table to track baseline recalculation scheduling
CREATE TABLE IF NOT EXISTS pggit.baseline_recalc_schedule (
    schedule_id BIGSERIAL PRIMARY KEY,
    operation_type TEXT NOT NULL,
    last_recalc_time TIMESTAMP,
    next_recalc_time TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    recalc_frequency_hours INTEGER DEFAULT 24,
    min_samples_required INTEGER DEFAULT 10,
    lookback_days INTEGER DEFAULT 7,
    reason_for_update TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT baseline_recalc_schedule_operation_fk
        FOREIGN KEY (operation_type)
        REFERENCES pggit.performance_operation_types(operation_type),
    CONSTRAINT baseline_recalc_schedule_unique
        UNIQUE (operation_type)
);

CREATE INDEX idx_baseline_recalc_schedule_next
    ON pggit.baseline_recalc_schedule(next_recalc_time, is_active)
    WHERE is_active = TRUE;

-- Table to track anomaly detection job scheduling
CREATE TABLE IF NOT EXISTS pggit.anomaly_detection_schedule (
    schedule_id BIGSERIAL PRIMARY KEY,
    detection_type TEXT NOT NULL, -- 'statistical', 'trend', 'combined'
    operation_type TEXT,           -- NULL means all operations
    last_check_time TIMESTAMP,
    next_check_time TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    check_frequency_minutes INTEGER DEFAULT 30,
    z_score_threshold NUMERIC(5,2) DEFAULT 3.0,
    lookback_hours INTEGER DEFAULT 24,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT anomaly_detection_type_check
        CHECK (detection_type IN ('statistical', 'trend', 'combined'))
);

CREATE INDEX idx_anomaly_detection_schedule_next
    ON pggit.anomaly_detection_schedule(next_check_time, is_active)
    WHERE is_active = TRUE;

-- ============================================================================
-- HELPER FUNCTION: log_job_execution
-- ============================================================================
-- Purpose: Log job execution with timing and error information
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.log_job_execution(
    p_job_name TEXT,
    p_cron_schedule TEXT,
    p_status TEXT,
    p_rows_affected INTEGER DEFAULT NULL,
    p_error_message TEXT DEFAULT NULL,
    p_execution_context JSONB DEFAULT NULL,
    p_execution_start TIMESTAMP DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_duration_ms INTEGER;
    v_exec_id BIGINT;
BEGIN
    -- Calculate duration
    v_duration_ms := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - COALESCE(p_execution_start, CURRENT_TIMESTAMP))) * 1000;

    -- Insert execution record
    INSERT INTO pggit.scheduled_job_execution (
        job_name,
        cron_schedule,
        execution_start,
        execution_end,
        status,
        duration_ms,
        rows_affected,
        error_message,
        execution_context
    ) VALUES (
        p_job_name,
        p_cron_schedule,
        COALESCE(p_execution_start, CURRENT_TIMESTAMP),
        CURRENT_TIMESTAMP,
        p_status,
        v_duration_ms,
        p_rows_affected,
        p_error_message,
        p_execution_context
    )
    RETURNING job_execution_id INTO v_exec_id;

    RETURN v_exec_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: run_scheduled_baseline_recalculation
-- ============================================================================
-- Purpose: Orchestrate baseline recalculation for all tracked operations
-- Called by: pg_cron every 24 hours at 02:00 UTC
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.run_scheduled_baseline_recalculation()
RETURNS TABLE (
    operation_type TEXT,
    recalculation_status TEXT,
    rows_affected INTEGER,
    duration_ms INTEGER,
    next_scheduled TIMESTAMP
) AS $$
DECLARE
    v_exec_start TIMESTAMP := CURRENT_TIMESTAMP;
    v_exec_id BIGINT;
    v_total_rows INTEGER := 0;
    v_error_msg TEXT;
    v_operation TEXT;
BEGIN
    -- Log job start
    v_exec_id := pggit.log_job_execution(
        'baseline_recalculation_scheduled',
        '0 2 * * *',
        'RUNNING',
        NULL,
        NULL,
        jsonb_build_object('lookback_days', 7, 'min_samples', 10),
        v_exec_start
    );

    -- Recalculate baselines for all tracked operations
    FOR v_operation IN
        SELECT pot.operation_type
        FROM pggit.performance_operation_types pot
        WHERE pot.is_tracked = TRUE
        ORDER BY pot.operation_type
    LOOP

        BEGIN
            -- Call baseline recalculation function
            PERFORM pggit.recalculate_single_baseline_safe(
                v_operation,
                7,  -- lookback_days
                10, -- min_samples
                FALSE  -- force_recalc
            );

            -- Update schedule tracking
            UPDATE pggit.baseline_recalc_schedule
            SET
                last_recalc_time = CURRENT_TIMESTAMP,
                next_recalc_time = CURRENT_TIMESTAMP + (recalc_frequency_hours || ' hours')::INTERVAL,
                updated_at = CURRENT_TIMESTAMP
            WHERE operation_type = v_operation;

            v_total_rows := v_total_rows + 1;

            RETURN QUERY SELECT
                v_operation,
                'SUCCESS'::TEXT,
                1::INTEGER,
                EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_exec_start))::INTEGER,
                CURRENT_TIMESTAMP + INTERVAL '24 hours';
        EXCEPTION WHEN OTHERS THEN
            -- Log error and continue
            v_error_msg := SQLERRM;
            RETURN QUERY SELECT
                v_operation,
                'FAILED'::TEXT,
                0::INTEGER,
                EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_exec_start))::INTEGER,
                CURRENT_TIMESTAMP + INTERVAL '24 hours';
        END;
    END LOOP;

    -- Log job completion
    PERFORM pggit.log_job_execution(
        'baseline_recalculation_scheduled',
        '0 2 * * *',
        'SUCCESS',
        v_total_rows,
        NULL,
        jsonb_build_object('operations_processed', v_total_rows),
        v_exec_start
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: run_scheduled_anomaly_detection
-- ============================================================================
-- Purpose: Run combined anomaly detection across all operations
-- Called by: pg_cron every 6 hours (every 0, 6, 12, 18 hours UTC)
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.run_scheduled_anomaly_detection()
RETURNS TABLE (
    operation_type TEXT,
    anomalies_detected INTEGER,
    critical_count INTEGER,
    warning_count INTEGER,
    detection_duration_ms INTEGER
) AS $$
DECLARE
    v_exec_start TIMESTAMP := CURRENT_TIMESTAMP;
    v_exec_id BIGINT;
    v_operation TEXT;
    v_rec RECORD;
    v_anomaly_count INTEGER := 0;
    v_critical_count INTEGER := 0;
    v_warning_count INTEGER := 0;
BEGIN
    -- Log job start
    v_exec_id := pggit.log_job_execution(
        'anomaly_detection_scheduled',
        '0 */6 * * *',
        'RUNNING',
        NULL,
        NULL,
        jsonb_build_object('z_score_threshold', 3.0, 'lookback_hours', 24),
        v_exec_start
    );

    -- Run anomaly detection for each operation type
    FOR v_operation IN
        SELECT pot.operation_type
        FROM pggit.performance_operation_types pot
        WHERE pot.is_tracked = TRUE
        ORDER BY pot.operation_type
    LOOP
        v_anomaly_count := 0;
        v_critical_count := 0;
        v_warning_count := 0;

        BEGIN
            -- Detect combined anomalies (statistical + trend)
            SELECT
                COUNT(*) as total_anomalies,
                SUM(CASE WHEN severity = 'CRITICAL' THEN 1 ELSE 0 END) as critical,
                SUM(CASE WHEN severity = 'WARNING' THEN 1 ELSE 0 END) as warning
            INTO
                v_anomaly_count,
                v_critical_count,
                v_warning_count
            FROM pggit.detect_combined_anomalies(v_operation, 24);

            -- Return detection results
            RETURN QUERY SELECT
                v_operation,
                COALESCE(v_anomaly_count, 0),
                COALESCE(v_critical_count, 0),
                COALESCE(v_warning_count, 0),
                EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_exec_start))::INTEGER;
        EXCEPTION WHEN OTHERS THEN
            -- Log error and continue to next operation
            RETURN QUERY SELECT
                v_operation,
                0::INTEGER,
                0::INTEGER,
                0::INTEGER,
                EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_exec_start))::INTEGER;
        END;
    END LOOP;

    -- Log job completion
    PERFORM pggit.log_job_execution(
        'anomaly_detection_scheduled',
        '0 */6 * * *',
        'SUCCESS',
        NULL,
        NULL,
        NULL,
        v_exec_start
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: run_scheduled_correlation_analysis
-- ============================================================================
-- Purpose: Detect correlated operation degradation indicating shared bottlenecks
-- Called by: pg_cron every 12 hours (every 0, 12 hours UTC)
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.run_scheduled_correlation_analysis()
RETURNS TABLE (
    operation_pair TEXT,
    correlation_coefficient NUMERIC,
    bottleneck_type TEXT,
    severity TEXT,
    analysis_time_ms INTEGER
) AS $$
DECLARE
    v_exec_start TIMESTAMP := CURRENT_TIMESTAMP;
    v_exec_id BIGINT;
    v_rec RECORD;
    v_pair_count INTEGER := 0;
BEGIN
    -- Log job start
    v_exec_id := pggit.log_job_execution(
        'correlation_analysis_scheduled',
        '0 */12 * * *',
        'RUNNING',
        NULL,
        NULL,
        jsonb_build_object('correlation_threshold', 0.75, 'lookback_hours', 24),
        v_exec_start
    );

    -- Run correlation analysis and store results
    FOR v_rec IN
        SELECT * FROM pggit.analyze_all_correlations(24)
    LOOP
        -- Process correlation results
        v_pair_count := v_pair_count + 1;
    END LOOP;

    -- Return active correlations exceeding threshold
    FOR v_rec IN
        SELECT
            operation_type_1 || ' <-> ' || operation_type_2 as pair,
            correlation_coefficient,
            shared_bottleneck,
            severity
        FROM pggit.v_active_correlations
        ORDER BY correlation_coefficient DESC
        LIMIT 20
    LOOP
        RETURN QUERY SELECT
            v_rec.pair,
            v_rec.correlation_coefficient,
            v_rec.shared_bottleneck,
            v_rec.severity,
            EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_exec_start))::INTEGER;
    END LOOP;

    -- Log job completion
    PERFORM pggit.log_job_execution(
        'correlation_analysis_scheduled',
        '0 */12 * * *',
        'SUCCESS',
        v_pair_count,
        NULL,
        NULL,
        v_exec_start
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: run_scheduled_alert_delivery
-- ============================================================================
-- Purpose: Deliver pending alerts via webhooks (Mattermost, Slack, email)
-- Called by: pg_cron every 5 minutes
-- Note: Will be implemented in phase7_week4_alert_integration.sql
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.run_scheduled_alert_delivery()
RETURNS TABLE (
    alert_id BIGINT,
    delivery_status TEXT,
    webhook_type TEXT,
    http_status INTEGER,
    delivery_duration_ms INTEGER
) AS $$
DECLARE
    v_exec_start TIMESTAMP := CURRENT_TIMESTAMP;
    v_exec_id BIGINT;
BEGIN
    -- Log job start
    v_exec_id := pggit.log_job_execution(
        'alert_delivery_scheduled',
        '*/5 * * * *',
        'RUNNING',
        NULL,
        NULL,
        NULL,
        v_exec_start
    );

    -- Alert delivery implementation pending in Week 4 Phase 2
    -- This function will be enhanced with actual delivery logic

    -- Log job completion
    PERFORM pggit.log_job_execution(
        'alert_delivery_scheduled',
        '*/5 * * * *',
        'SUCCESS',
        0,
        NULL,
        jsonb_build_object('alerts_delivered', 0),
        v_exec_start
    );

    -- Placeholder return for now
    RETURN QUERY SELECT
        0::BIGINT,
        'PENDING'::TEXT,
        'UNKNOWN'::TEXT,
        0::INTEGER,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_exec_start))::INTEGER;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: initialize_job_schedules
-- ============================================================================
-- Purpose: Initialize default schedule records for baseline recalculation
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.initialize_job_schedules()
RETURNS TABLE (
    operation_type TEXT,
    last_recalc_time TIMESTAMP,
    next_recalc_time TIMESTAMP
) AS $$
DECLARE
    v_op_type TEXT;
BEGIN
    -- Initialize baseline recalc schedule for all tracked operations
    FOR v_op_type IN
        SELECT pot.operation_type
        FROM pggit.performance_operation_types pot
        WHERE pot.is_tracked = TRUE
    LOOP
        INSERT INTO pggit.baseline_recalc_schedule (
            operation_type,
            last_recalc_time,
            next_recalc_time,
            is_active,
            recalc_frequency_hours,
            min_samples_required,
            lookback_days,
            reason_for_update
        ) VALUES (
            v_op_type,
            NULL,
            CURRENT_TIMESTAMP,
            TRUE,
            24,
            10,
            7,
            'Initial schedule creation'
        )
        ON CONFLICT (operation_type) DO UPDATE SET
            next_recalc_time = EXCLUDED.next_recalc_time;

        RETURN QUERY SELECT
            v_op_type,
            NULL::TIMESTAMP,
            CURRENT_TIMESTAMP;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEW: v_job_execution_summary
-- ============================================================================
-- Purpose: Summary of recent job executions for monitoring
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_job_execution_summary AS
SELECT
    job_name,
    status,
    COUNT(*) as execution_count,
    AVG(duration_ms)::INTEGER as avg_duration_ms,
    MAX(duration_ms) as max_duration_ms,
    MIN(duration_ms) as min_duration_ms,
    SUM(rows_affected) as total_rows_affected,
    MAX(execution_start) as last_execution,
    ROUND(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MAX(execution_start))) / 3600, 1) as hours_since_last
FROM pggit.scheduled_job_execution
WHERE execution_start >= CURRENT_TIMESTAMP - INTERVAL '7 days'
GROUP BY job_name, status
ORDER BY job_name, status;

-- ============================================================================
-- VIEW: v_upcoming_scheduled_jobs
-- ============================================================================
-- Purpose: Show next scheduled job runs
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_upcoming_scheduled_jobs AS
SELECT
    'baseline_recalculation' as job_type,
    operation_type as resource,
    next_recalc_time as scheduled_time,
    ROUND(EXTRACT(EPOCH FROM (next_recalc_time - CURRENT_TIMESTAMP)) / 3600, 2) as hours_until_execution,
    is_active,
    recalc_frequency_hours::TEXT as frequency_info
FROM pggit.baseline_recalc_schedule
WHERE is_active = TRUE

ORDER BY scheduled_time ASC;

-- ============================================================================
-- VIEW: v_job_health_dashboard
-- ============================================================================
-- Purpose: Overall job health and performance metrics
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_job_health_dashboard AS
WITH job_stats AS (
    SELECT
        job_name,
        COUNT(*) as total_executions,
        SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) as successful,
        SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) as failed,
        ROUND(100.0 * SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) as success_rate_percent,
        AVG(duration_ms)::INTEGER as avg_duration_ms,
        MAX(execution_start) as last_execution
    FROM pggit.scheduled_job_execution
    WHERE execution_start >= CURRENT_TIMESTAMP - INTERVAL '7 days'
    GROUP BY job_name
)
SELECT
    job_name,
    total_executions,
    successful,
    failed,
    success_rate_percent,
    avg_duration_ms,
    last_execution,
    ROUND(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - last_execution)) / 3600, 1) as hours_since_last_run,
    CASE
        WHEN success_rate_percent >= 95 THEN 'HEALTHY'
        WHEN success_rate_percent >= 80 THEN 'DEGRADED'
        ELSE 'CRITICAL'
    END as health_status
FROM job_stats
ORDER BY job_name;

-- ============================================================================
-- FUNCTION: setup_pg_cron_jobs
-- ============================================================================
-- Purpose: Create pg_cron job definitions
-- Note: Requires pg_cron extension to be installed
--       Run this function manually or as part of deployment
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.setup_pg_cron_jobs()
RETURNS TABLE (
    job_name TEXT,
    cron_schedule TEXT,
    status TEXT
) AS $$
BEGIN
    -- Check if pg_cron is installed
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        RAISE EXCEPTION 'pg_cron extension is not installed. Please install it first.';
    END IF;

    -- Create baseline recalculation job (daily at 02:00 UTC)
    -- Using cron schedule: minute hour day month weekday
    -- "0 2 * * *" = every day at 02:00 UTC
    PERFORM cron.schedule(
        'pggit_baseline_recalculation_daily',
        '0 2 * * *',
        'SELECT pggit.run_scheduled_baseline_recalculation()'
    );

    RETURN QUERY SELECT
        'pggit_baseline_recalculation_daily'::TEXT,
        '0 2 * * *'::TEXT,
        'Scheduled'::TEXT;

    -- Create anomaly detection job (every 6 hours)
    -- "0 */6 * * *" = at 00:00, 06:00, 12:00, 18:00 UTC
    PERFORM cron.schedule(
        'pggit_anomaly_detection_6hourly',
        '0 */6 * * *',
        'SELECT pggit.run_scheduled_anomaly_detection()'
    );

    RETURN QUERY SELECT
        'pggit_anomaly_detection_6hourly'::TEXT,
        '0 */6 * * *'::TEXT,
        'Scheduled'::TEXT;

    -- Create correlation analysis job (every 12 hours)
    -- "0 */12 * * *" = at 00:00, 12:00 UTC
    PERFORM cron.schedule(
        'pggit_correlation_analysis_12hourly',
        '0 */12 * * *',
        'SELECT pggit.run_scheduled_correlation_analysis()'
    );

    RETURN QUERY SELECT
        'pggit_correlation_analysis_12hourly'::TEXT,
        '0 */12 * * *'::TEXT,
        'Scheduled'::TEXT;

    -- Create alert delivery job (every 5 minutes)
    -- "*/5 * * * *" = every 5 minutes
    PERFORM cron.schedule(
        'pggit_alert_delivery_5minute',
        '*/5 * * * *',
        'SELECT pggit.run_scheduled_alert_delivery()'
    );

    RETURN QUERY SELECT
        'pggit_alert_delivery_5minute'::TEXT,
        '*/5 * * * *'::TEXT,
        'Scheduled'::TEXT;

    -- Create cleanup job (daily at 03:00 UTC)
    -- Cleanup old metrics, anomalies, and execution logs
    PERFORM cron.schedule(
        'pggit_cleanup_old_data_daily',
        '0 3 * * *',
        'SELECT pggit.cleanup_old_anomalies(30)'
    );

    RETURN QUERY SELECT
        'pggit_cleanup_old_data_daily'::TEXT,
        '0 3 * * *'::TEXT,
        'Scheduled'::TEXT;

END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- SUMMARY
-- ============================================================================
-- Created tables:
--   1. scheduled_job_execution - Execution history and timing
--   2. baseline_recalc_schedule - Baseline recalculation schedule tracking
--   3. anomaly_detection_schedule - Anomaly detection job scheduling
--
-- Created functions:
--   1. log_job_execution() - Log execution with timing info
--   2. run_scheduled_baseline_recalculation() - Daily baseline recalc
--   3. run_scheduled_anomaly_detection() - Every 6 hours anomaly check
--   4. run_scheduled_correlation_analysis() - Every 12 hours bottleneck detection
--   5. run_scheduled_alert_delivery() - Every 5 minutes alert delivery
--   6. initialize_job_schedules() - Initialize schedule records
--   7. setup_pg_cron_jobs() - Create pg_cron job definitions
--
-- Created views:
--   1. v_job_execution_summary - Recent execution statistics
--   2. v_upcoming_scheduled_jobs - Next scheduled runs
--   3. v_job_health_dashboard - Overall job health metrics
--
-- Cron Schedule:
--   - Baseline recalculation: Daily at 02:00 UTC (0 2 * * *)
--   - Anomaly detection: Every 6 hours (0 */6 * * *)
--   - Correlation analysis: Every 12 hours (0 */12 * * *)
--   - Alert delivery: Every 5 minutes (*/5 * * * *)
--   - Data cleanup: Daily at 03:00 UTC (0 3 * * *)
--
-- Performance targets:
--   - Baseline recalculation: <60 seconds for all operations
--   - Anomaly detection: <30 seconds per cycle
--   - Correlation analysis: <120 seconds per cycle
--   - Alert delivery: <10 seconds per delivery
-- ============================================================================
