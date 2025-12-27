-- ============================================================================
-- Phase 7: Performance Monitoring - Core Functions
-- ============================================================================
-- Description: Functions for recording, analyzing, and alerting on performance
-- Version: 1.0.0
-- Created: 2025-12-27
-- ============================================================================

-- ============================================================================
-- 1. TRACE MANAGEMENT FUNCTIONS
-- ============================================================================

-- start_performance_trace: Begin a distributed trace span
CREATE OR REPLACE FUNCTION pggit.start_performance_trace(
    p_trace_id TEXT DEFAULT NULL,
    p_span_id TEXT DEFAULT NULL,
    p_parent_span_id TEXT DEFAULT NULL,
    p_operation_type TEXT DEFAULT 'UNKNOWN',
    p_span_name TEXT DEFAULT 'unnamed',
    p_branch_id INTEGER DEFAULT NULL,
    p_user_name TEXT DEFAULT CURRENT_USER,
    p_session_id TEXT DEFAULT NULL,
    p_attributes JSONB DEFAULT NULL
)
RETURNS TEXT AS $$
DECLARE
    v_trace_id TEXT;
    v_span_id TEXT;
BEGIN
    -- Generate IDs if not provided
    v_trace_id := COALESCE(p_trace_id, gen_random_uuid()::TEXT);
    v_span_id := COALESCE(p_span_id, gen_random_uuid()::TEXT);

    -- Insert trace record
    INSERT INTO pggit.operation_traces (
        trace_id, span_id, parent_span_id,
        operation_type, span_name, span_status,
        start_time,
        branch_id, user_name, session_id,
        attributes
    ) VALUES (
        v_trace_id, v_span_id, p_parent_span_id,
        p_operation_type, p_span_name, 'RUNNING',
        CURRENT_TIMESTAMP,
        p_branch_id, p_user_name, p_session_id,
        p_attributes
    );

    RETURN v_span_id;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- end_performance_trace: End a distributed trace span
CREATE OR REPLACE FUNCTION pggit.end_performance_trace(
    p_span_id TEXT,
    p_span_status TEXT DEFAULT 'SUCCESS',
    p_error_message TEXT DEFAULT NULL,
    p_error_code TEXT DEFAULT NULL,
    p_error_details JSONB DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_duration_us BIGINT;
BEGIN
    -- Calculate duration
    SELECT EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - start_time)) * 1000000
    INTO v_duration_us
    FROM pggit.operation_traces
    WHERE span_id = p_span_id;

    -- Update trace record
    UPDATE pggit.operation_traces
    SET
        end_time = CURRENT_TIMESTAMP,
        duration_microseconds = v_duration_us,
        span_status = p_span_status,
        error_message = p_error_message,
        error_code = p_error_code,
        error_details = p_error_details
    WHERE span_id = p_span_id;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- ============================================================================
-- 2. METRIC RECORDING FUNCTIONS
-- ============================================================================

-- record_performance_metric: Record a single operation's performance
CREATE OR REPLACE FUNCTION pggit.record_performance_metric(
    p_operation_type TEXT,
    p_duration_microseconds BIGINT,
    p_operation_name TEXT DEFAULT NULL,
    p_branch_id INTEGER DEFAULT NULL,
    p_user_name TEXT DEFAULT CURRENT_USER,
    p_session_id TEXT DEFAULT NULL,
    p_rows_affected INTEGER DEFAULT NULL,
    p_memory_bytes BIGINT DEFAULT NULL,
    p_cpu_microseconds BIGINT DEFAULT NULL,
    p_operation_metadata JSONB DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_metric_id BIGINT;
    v_duration_ms NUMERIC(10,3);
    v_period_start TIMESTAMP;
BEGIN
    -- Validate duration
    IF p_duration_microseconds <= 0 THEN
        RAISE EXCEPTION 'Duration must be positive: %', p_duration_microseconds;
    END IF;

    -- Calculate milliseconds
    v_duration_ms := (p_duration_microseconds::NUMERIC / 1000);

    -- Period start is midnight of the current day
    v_period_start := DATE_TRUNC('day', CURRENT_TIMESTAMP);

    -- Insert metric record
    INSERT INTO pggit.performance_metrics (
        operation_type, operation_name,
        duration_microseconds, duration_ms,
        start_time, end_time,
        branch_id, user_name, session_id,
        rows_affected, memory_bytes, cpu_microseconds,
        operation_metadata,
        period_start
    ) VALUES (
        p_operation_type, p_operation_name,
        p_duration_microseconds, v_duration_ms,
        CURRENT_TIMESTAMP - (p_duration_microseconds || ' microseconds')::INTERVAL,
        CURRENT_TIMESTAMP,
        p_branch_id, p_user_name, p_session_id,
        p_rows_affected, p_memory_bytes, p_cpu_microseconds,
        p_operation_metadata,
        v_period_start
    )
    RETURNING metric_id INTO v_metric_id;

    -- Check baseline and create alert if exceeded
    PERFORM pggit.check_performance_baseline(v_metric_id);

    RETURN v_metric_id;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- ============================================================================
-- 3. BASELINE MANAGEMENT FUNCTIONS
-- ============================================================================

-- calculate_performance_baseline: Calculate percentile baselines from recent data
CREATE OR REPLACE FUNCTION pggit.calculate_performance_baseline(
    p_operation_type TEXT,
    p_branch_id INTEGER DEFAULT NULL,
    p_lookback_days INTEGER DEFAULT 7,
    p_alert_threshold_multiplier NUMERIC DEFAULT 2.0
)
RETURNS BIGINT AS $$
DECLARE
    v_baseline_id BIGINT;
    v_sample_count INTEGER;
    v_min_us BIGINT;
    v_max_us BIGINT;
    v_mean_us NUMERIC(12,2);
    v_stddev_us NUMERIC(12,2);
    v_p50_us BIGINT;
    v_p75_us BIGINT;
    v_p90_us BIGINT;
    v_p95_us BIGINT;
    v_p99_us BIGINT;
    v_baseline_date DATE;
BEGIN
    v_baseline_date := CURRENT_DATE;

    -- Calculate percentiles using aggregate functions
    WITH metrics AS (
        SELECT duration_microseconds
        FROM pggit.performance_metrics
        WHERE operation_type = p_operation_type
          AND (p_branch_id IS NULL OR branch_id = p_branch_id)
          AND period_start >= CURRENT_DATE - (p_lookback_days || ' days')::INTERVAL
        ORDER BY duration_microseconds
    ),
    stats AS (
        SELECT
            COUNT(*) as sample_count,
            MIN(duration_microseconds) as min_us,
            MAX(duration_microseconds) as max_us,
            AVG(duration_microseconds)::NUMERIC(12,2) as mean_us,
            STDDEV(duration_microseconds)::NUMERIC(12,2) as stddev_us,
            PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY duration_microseconds) as p50_us,
            PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY duration_microseconds) as p75_us,
            PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY duration_microseconds) as p90_us,
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_microseconds) as p95_us,
            PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_microseconds) as p99_us
        FROM metrics
    )
    SELECT
        sample_count, min_us, max_us, mean_us, stddev_us,
        p50_us::BIGINT, p75_us::BIGINT, p90_us::BIGINT, p95_us::BIGINT, p99_us::BIGINT
    INTO
        v_sample_count, v_min_us, v_max_us, v_mean_us, v_stddev_us,
        v_p50_us, v_p75_us, v_p90_us, v_p95_us, v_p99_us
    FROM stats;

    -- Skip if insufficient data
    IF v_sample_count < 10 THEN
        RAISE WARNING 'Insufficient data for baseline (% samples)', v_sample_count;
        RETURN NULL;
    END IF;

    -- Mark old baselines as inactive
    UPDATE pggit.performance_baselines
    SET is_active = FALSE
    WHERE operation_type = p_operation_type
      AND (p_branch_id IS NULL OR branch_id = p_branch_id)
      AND is_active = TRUE;

    -- Insert new baseline
    INSERT INTO pggit.performance_baselines (
        operation_type, branch_id,
        baseline_date, calculation_timestamp,
        sample_count, min_microseconds, max_microseconds,
        p50_microseconds, p75_microseconds, p90_microseconds, p95_microseconds, p99_microseconds,
        mean_microseconds, stddev_microseconds,
        alert_threshold_multiplier,
        calculated_from_days
    ) VALUES (
        p_operation_type, p_branch_id,
        v_baseline_date, CURRENT_TIMESTAMP,
        v_sample_count, v_min_us, v_max_us,
        v_p50_us, v_p75_us, v_p90_us, v_p95_us, v_p99_us,
        v_mean_us, v_stddev_us,
        p_alert_threshold_multiplier,
        p_lookback_days
    )
    RETURNING baseline_id INTO v_baseline_id;

    RETURN v_baseline_id;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- check_performance_baseline: Check if metric exceeds baseline and alert if needed
CREATE OR REPLACE FUNCTION pggit.check_performance_baseline(
    p_metric_id BIGINT
)
RETURNS BIGINT AS $$
DECLARE
    v_alert_id BIGINT;
    v_operation_type TEXT;
    v_branch_id INTEGER;
    v_duration_us BIGINT;
    v_baseline_id BIGINT;
    v_p99_us BIGINT;
    v_threshold_us BIGINT;
    v_multiplier NUMERIC(6,2);
    v_user_name TEXT;
BEGIN
    -- Get metric details
    SELECT pm.operation_type, pm.branch_id, pm.duration_microseconds, pm.user_name
    INTO v_operation_type, v_branch_id, v_duration_us, v_user_name
    FROM pggit.performance_metrics pm
    WHERE metric_id = p_metric_id;

    -- Find active baseline
    SELECT baseline_id, p99_microseconds, alert_threshold_multiplier
    INTO v_baseline_id, v_p99_us, v_multiplier
    FROM pggit.performance_baselines
    WHERE operation_type = v_operation_type
      AND (branch_id IS NULL OR branch_id = v_branch_id)
      AND is_active = TRUE
    ORDER BY calculation_timestamp DESC
    LIMIT 1;

    -- If no baseline, skip alerting
    IF v_baseline_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Calculate threshold
    v_threshold_us := (v_p99_us * v_multiplier)::BIGINT;

    -- Create alert if exceeded
    IF v_duration_us > v_threshold_us THEN
        INSERT INTO pggit.performance_alerts (
            metric_id, baseline_id,
            operation_type, alert_type, severity,
            baseline_p99_microseconds, actual_duration_microseconds,
            violation_multiplier,
            branch_id, user_name
        ) VALUES (
            p_metric_id, v_baseline_id,
            v_operation_type, 'THRESHOLD_EXCEEDED', 'WARNING',
            v_p99_us, v_duration_us,
            (v_duration_us::NUMERIC / v_p99_us),
            v_branch_id, v_user_name
        )
        RETURNING alert_id INTO v_alert_id;

        RETURN v_alert_id;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- ============================================================================
-- 4. ANALYSIS & REPORTING FUNCTIONS
-- ============================================================================

-- get_performance_trend: Get performance trend for an operation over time
CREATE OR REPLACE FUNCTION pggit.get_performance_trend(
    p_operation_type TEXT,
    p_branch_id INTEGER DEFAULT NULL,
    p_days INTEGER DEFAULT 7
)
RETURNS TABLE (
    trend_date DATE,
    sample_count INTEGER,
    avg_duration_ms NUMERIC,
    min_duration_ms NUMERIC,
    max_duration_ms NUMERIC,
    p50_ms NUMERIC,
    p99_ms NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        DATE(pm.period_start)::DATE as trend_date,
        COUNT(*)::INTEGER as sample_count,
        (AVG(pm.duration_microseconds) / 1000)::NUMERIC(10,3) as avg_duration_ms,
        (MIN(pm.duration_microseconds) / 1000)::NUMERIC(10,3) as min_duration_ms,
        (MAX(pm.duration_microseconds) / 1000)::NUMERIC(10,3) as max_duration_ms,
        (PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY pm.duration_microseconds) / 1000)::NUMERIC(10,3) as p50_ms,
        (PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY pm.duration_microseconds) / 1000)::NUMERIC(10,3) as p99_ms
    FROM pggit.performance_metrics pm
    WHERE pm.operation_type = p_operation_type
      AND (p_branch_id IS NULL OR pm.branch_id = p_branch_id)
      AND pm.period_start >= CURRENT_DATE - (p_days || ' days')::INTERVAL
    GROUP BY DATE(pm.period_start)
    ORDER BY trend_date DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- get_slowest_operations: Find the slowest operations (for optimization)
CREATE OR REPLACE FUNCTION pggit.get_slowest_operations(
    p_operation_type TEXT DEFAULT NULL,
    p_branch_id INTEGER DEFAULT NULL,
    p_days INTEGER DEFAULT 7,
    p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
    metric_id BIGINT,
    operation_type TEXT,
    duration_ms NUMERIC,
    user_name TEXT,
    recorded_at TIMESTAMP,
    operation_name TEXT,
    branch_id INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        pm.metric_id,
        pm.operation_type,
        (pm.duration_microseconds / 1000)::NUMERIC(10,3) as duration_ms,
        pm.user_name,
        pm.recorded_at,
        pm.operation_name,
        pm.branch_id
    FROM pggit.performance_metrics pm
    WHERE (p_operation_type IS NULL OR pm.operation_type = p_operation_type)
      AND (p_branch_id IS NULL OR pm.branch_id = p_branch_id)
      AND pm.period_start >= CURRENT_DATE - (p_days || ' days')::INTERVAL
    ORDER BY pm.duration_microseconds DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

-- get_operation_statistics: Get overall statistics for an operation
CREATE OR REPLACE FUNCTION pggit.get_operation_statistics(
    p_operation_type TEXT,
    p_branch_id INTEGER DEFAULT NULL
)
RETURNS TABLE (
    operation_type TEXT,
    total_executions BIGINT,
    total_time_hours NUMERIC,
    avg_duration_ms NUMERIC,
    min_duration_ms NUMERIC,
    max_duration_ms NUMERIC,
    p50_ms NUMERIC,
    p95_ms NUMERIC,
    p99_ms NUMERIC,
    last_execution TIMESTAMP,
    last_baseline_date DATE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        pm.operation_type,
        COUNT(*)::BIGINT as total_executions,
        (SUM(pm.duration_microseconds) / 1000000.0 / 3600)::NUMERIC(10,2) as total_time_hours,
        (AVG(pm.duration_microseconds) / 1000)::NUMERIC(10,3) as avg_duration_ms,
        (MIN(pm.duration_microseconds) / 1000)::NUMERIC(10,3) as min_duration_ms,
        (MAX(pm.duration_microseconds) / 1000)::NUMERIC(10,3) as max_duration_ms,
        (PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY pm.duration_microseconds) / 1000)::NUMERIC(10,3) as p50_ms,
        (PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY pm.duration_microseconds) / 1000)::NUMERIC(10,3) as p95_ms,
        (PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY pm.duration_microseconds) / 1000)::NUMERIC(10,3) as p99_ms,
        MAX(pm.recorded_at)::TIMESTAMP as last_execution,
        pb.baseline_date as last_baseline_date
    FROM pggit.performance_metrics pm
    LEFT JOIN pggit.performance_baselines pb
        ON pm.operation_type = pb.operation_type
        AND (p_branch_id IS NULL OR pm.branch_id = pb.branch_id)
        AND pb.is_active = TRUE
    WHERE pm.operation_type = p_operation_type
      AND (p_branch_id IS NULL OR pm.branch_id = p_branch_id)
    GROUP BY pm.operation_type, pb.baseline_date;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- 5. ALERT MANAGEMENT FUNCTIONS
-- ============================================================================

-- acknowledge_performance_alert: Mark an alert as acknowledged
CREATE OR REPLACE FUNCTION pggit.acknowledge_performance_alert(
    p_alert_id BIGINT,
    p_acknowledged_by TEXT DEFAULT CURRENT_USER,
    p_resolution_notes TEXT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    UPDATE pggit.performance_alerts
    SET
        is_acknowledged = TRUE,
        acknowledged_at = CURRENT_TIMESTAMP,
        acknowledged_by = p_acknowledged_by,
        resolution_notes = p_resolution_notes
    WHERE alert_id = p_alert_id;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- get_unacknowledged_alerts: Get all unacknowledged performance alerts
CREATE OR REPLACE FUNCTION pggit.get_unacknowledged_alerts(
    p_days INTEGER DEFAULT 7
)
RETURNS TABLE (
    alert_id BIGINT,
    operation_type TEXT,
    severity TEXT,
    violation_multiplier NUMERIC,
    baseline_p99_ms NUMERIC,
    actual_duration_ms NUMERIC,
    user_name TEXT,
    created_at TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        pa.alert_id,
        pa.operation_type,
        pa.severity,
        pa.violation_multiplier,
        (pa.baseline_p99_microseconds / 1000)::NUMERIC(10,3) as baseline_p99_ms,
        (pa.actual_duration_microseconds / 1000)::NUMERIC(10,3) as actual_duration_ms,
        pa.user_name,
        pa.created_at
    FROM pggit.performance_alerts pa
    WHERE pa.is_acknowledged = FALSE
      AND pa.created_at >= CURRENT_TIMESTAMP - (p_days || ' days')::INTERVAL
    ORDER BY pa.created_at DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- 6. MERGE-SPECIFIC PERFORMANCE FUNCTIONS
-- ============================================================================

-- record_merge_performance: Record detailed merge operation metrics
CREATE OR REPLACE FUNCTION pggit.record_merge_performance(
    p_source_branch_id INTEGER,
    p_target_branch_id INTEGER,
    p_total_merge_us BIGINT,
    p_merge_base_hash TEXT DEFAULT NULL,
    p_merge_base_calc_us BIGINT DEFAULT NULL,
    p_conflict_detection_us BIGINT DEFAULT NULL,
    p_conflict_count INTEGER DEFAULT 0,
    p_auto_resolution_us BIGINT DEFAULT NULL,
    p_auto_success_count INTEGER DEFAULT 0,
    p_auto_failure_count INTEGER DEFAULT 0,
    p_merge_status TEXT DEFAULT 'SUCCESS',
    p_merge_outcome JSONB DEFAULT NULL,
    p_user_name TEXT DEFAULT CURRENT_USER
)
RETURNS BIGINT AS $$
DECLARE
    v_merge_metric_id BIGINT;
    v_session_id TEXT;
BEGIN
    v_session_id := gen_random_uuid()::TEXT;

    INSERT INTO pggit.merge_performance_metrics (
        source_branch_id, target_branch_id,
        merge_base_commit_hash,
        merge_base_calculation_us,
        conflict_detection_us,
        conflict_count,
        auto_resolution_us,
        auto_resolution_success_count,
        auto_resolution_failure_count,
        total_merge_us,
        merge_status,
        merge_outcome_details,
        user_name,
        session_id,
        started_at,
        completed_at
    ) VALUES (
        p_source_branch_id, p_target_branch_id,
        p_merge_base_hash,
        p_merge_base_calc_us,
        p_conflict_detection_us,
        p_conflict_count,
        p_auto_resolution_us,
        p_auto_success_count,
        p_auto_failure_count,
        p_total_merge_us,
        p_merge_status,
        p_merge_outcome,
        p_user_name,
        v_session_id,
        CURRENT_TIMESTAMP - (p_total_merge_us || ' microseconds')::INTERVAL,
        CURRENT_TIMESTAMP
    )
    RETURNING merge_metric_id INTO v_merge_metric_id;

    -- Record overall metric in performance_metrics for unified analysis
    PERFORM pggit.record_performance_metric(
        p_operation_type := 'merge',
        p_operation_name := CONCAT('merge_', p_source_branch_id, '_to_', p_target_branch_id),
        p_duration_microseconds := p_total_merge_us,
        p_branch_id := p_target_branch_id,
        p_user_name := p_user_name,
        p_session_id := v_session_id,
        p_operation_metadata := jsonb_build_object(
            'merge_metric_id', v_merge_metric_id,
            'source_branch_id', p_source_branch_id,
            'target_branch_id', p_target_branch_id,
            'conflict_count', p_conflict_count,
            'merge_status', p_merge_status
        )
    );

    RETURN v_merge_metric_id;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- ============================================================================
-- Summary
-- ============================================================================
-- Total functions: 11
-- - Trace management: 2 (start, end)
-- - Metric recording: 1
-- - Baseline management: 3 (calculate, check, helper)
-- - Analysis: 4 (trend, slowest, stats, alerts)
-- - Merge-specific: 1
-- ============================================================================
