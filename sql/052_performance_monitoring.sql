-- pgGit Real-Time Performance Monitoring
-- Sub-millisecond operation tracking and optimization
-- Enterprise performance insights

-- =====================================================
-- Performance Monitoring Tables
-- =====================================================

CREATE TABLE IF NOT EXISTS pggit.performance_metrics (
    metric_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    operation_type TEXT NOT NULL, -- 'branch_create', 'merge', 'migration', 'ai_analysis', etc.
    operation_name TEXT NOT NULL,
    started_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP(6),
    duration_ms DECIMAL(10,3),
    cpu_time_ms DECIMAL(10,3),
    io_time_ms DECIMAL(10,3),
    rows_affected BIGINT,
    memory_used_mb DECIMAL(10,2),
    cache_hits INT,
    cache_misses INT,
    query_plan JSONB,
    context JSONB DEFAULT '{}'::JSONB
);

CREATE TABLE IF NOT EXISTS pggit.operation_traces (
    trace_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    parent_trace_id UUID,
    operation_type TEXT NOT NULL,
    operation_name TEXT NOT NULL,
    started_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP,
    duration_us BIGINT, -- microseconds for sub-millisecond precision
    span_attributes JSONB DEFAULT '{}'::JSONB
);

CREATE TABLE IF NOT EXISTS pggit.performance_baselines (
    baseline_id SERIAL PRIMARY KEY,
    operation_type TEXT NOT NULL,
    percentile_50 DECIMAL(10,3),
    percentile_75 DECIMAL(10,3),
    percentile_90 DECIMAL(10,3),
    percentile_95 DECIMAL(10,3),
    percentile_99 DECIMAL(10,3),
    sample_count INT,
    calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(operation_type, calculated_at)
);

CREATE TABLE IF NOT EXISTS pggit.performance_alerts (
    alert_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    metric_id UUID REFERENCES pggit.performance_metrics(metric_id),
    alert_type TEXT NOT NULL, -- 'slow_operation', 'high_memory', 'cache_miss_rate', etc.
    severity TEXT NOT NULL, -- 'info', 'warning', 'critical'
    threshold_value DECIMAL(10,3),
    actual_value DECIMAL(10,3),
    alert_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    acknowledged BOOLEAN DEFAULT false,
    acknowledged_by TEXT,
    acknowledged_at TIMESTAMP
);

-- =====================================================
-- Performance Monitoring Functions
-- =====================================================

-- Start performance trace
CREATE OR REPLACE FUNCTION pggit.start_performance_trace(
    p_operation_type TEXT,
    p_operation_name TEXT,
    p_parent_trace_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_trace_id UUID;
BEGIN
    INSERT INTO pggit.operation_traces (
        parent_trace_id,
        operation_type,
        operation_name,
        started_at
    ) VALUES (
        p_parent_trace_id,
        p_operation_type,
        p_operation_name,
        clock_timestamp()
    ) RETURNING trace_id INTO v_trace_id;
    
    -- Store in session variable for nested traces
    PERFORM set_config('pggit.current_trace_id', v_trace_id::TEXT, true);
    
    RETURN v_trace_id;
END;
$$ LANGUAGE plpgsql;

-- End performance trace
CREATE OR REPLACE FUNCTION pggit.end_performance_trace(
    p_trace_id UUID,
    p_attributes JSONB DEFAULT '{}'::JSONB
) RETURNS VOID AS $$
DECLARE
    v_start_time TIMESTAMP(6);
    v_duration_us BIGINT;
BEGIN
    -- Get start time
    SELECT started_at INTO v_start_time
    FROM pggit.operation_traces
    WHERE trace_id = p_trace_id;
    
    -- Calculate duration in microseconds
    v_duration_us := EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000000;
    
    -- Update trace
    UPDATE pggit.operation_traces
    SET duration_us = v_duration_us,
        span_attributes = span_attributes || p_attributes
    WHERE trace_id = p_trace_id;
END;
$$ LANGUAGE plpgsql;

-- Record performance metric
CREATE OR REPLACE FUNCTION pggit.record_performance_metric(
    p_operation_type TEXT,
    p_operation_name TEXT,
    p_start_time TIMESTAMP(6),
    p_rows_affected BIGINT DEFAULT NULL,
    p_context JSONB DEFAULT '{}'::JSONB
) RETURNS UUID AS $$
DECLARE
    v_metric_id UUID;
    v_duration_ms DECIMAL(10,3);
    v_cpu_time_ms DECIMAL(10,3);
    v_memory_mb DECIMAL(10,2);
BEGIN
    -- Calculate duration
    v_duration_ms := EXTRACT(EPOCH FROM (clock_timestamp() - p_start_time)) * 1000;
    
    -- Get CPU time (simplified - would use pg_stat_statements in production)
    v_cpu_time_ms := v_duration_ms * 0.8; -- Assume 80% CPU
    
    -- Estimate memory usage
    v_memory_mb := (pg_backend_memory_contexts()).total_bytes / 1024.0 / 1024.0;
    
    -- Insert metric
    INSERT INTO pggit.performance_metrics (
        operation_type,
        operation_name,
        started_at,
        completed_at,
        duration_ms,
        cpu_time_ms,
        rows_affected,
        memory_used_mb,
        context
    ) VALUES (
        p_operation_type,
        p_operation_name,
        p_start_time,
        clock_timestamp(),
        v_duration_ms,
        v_cpu_time_ms,
        p_rows_affected,
        v_memory_mb,
        p_context
    ) RETURNING metric_id INTO v_metric_id;
    
    -- Check for performance alerts
    PERFORM pggit.check_performance_alerts(v_metric_id);
    
    RETURN v_metric_id;
END;
$$ LANGUAGE plpgsql;

-- Check for performance alerts
CREATE OR REPLACE FUNCTION pggit.check_performance_alerts(
    p_metric_id UUID
) RETURNS VOID AS $$
DECLARE
    v_metric RECORD;
    v_baseline RECORD;
BEGIN
    -- Get metric
    SELECT * INTO v_metric
    FROM pggit.performance_metrics
    WHERE metric_id = p_metric_id;
    
    -- Get baseline for comparison
    SELECT * INTO v_baseline
    FROM pggit.performance_baselines
    WHERE operation_type = v_metric.operation_type
    ORDER BY calculated_at DESC
    LIMIT 1;
    
    -- Check for slow operation
    IF v_baseline.baseline_id IS NOT NULL AND 
       v_metric.duration_ms > v_baseline.percentile_95 * 2 THEN
        INSERT INTO pggit.performance_alerts (
            metric_id,
            alert_type,
            severity,
            threshold_value,
            actual_value,
            alert_message
        ) VALUES (
            p_metric_id,
            'slow_operation',
            CASE 
                WHEN v_metric.duration_ms > v_baseline.percentile_99 * 3 THEN 'critical'
                WHEN v_metric.duration_ms > v_baseline.percentile_99 * 2 THEN 'warning'
                ELSE 'info'
            END,
            v_baseline.percentile_95,
            v_metric.duration_ms,
            format('Operation %s took %sms (baseline p95: %sms)',
                v_metric.operation_name,
                v_metric.duration_ms,
                v_baseline.percentile_95)
        );
    END IF;
    
    -- Check for high memory usage
    IF v_metric.memory_used_mb > 100 THEN
        INSERT INTO pggit.performance_alerts (
            metric_id,
            alert_type,
            severity,
            threshold_value,
            actual_value,
            alert_message
        ) VALUES (
            p_metric_id,
            'high_memory',
            CASE 
                WHEN v_metric.memory_used_mb > 500 THEN 'critical'
                WHEN v_metric.memory_used_mb > 200 THEN 'warning'
                ELSE 'info'
            END,
            100,
            v_metric.memory_used_mb,
            format('High memory usage: %sMB', v_metric.memory_used_mb)
        );
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Calculate performance baselines
CREATE OR REPLACE FUNCTION pggit.calculate_performance_baselines(
    p_lookback_hours INT DEFAULT 24
) RETURNS VOID AS $$
DECLARE
    v_operation_type TEXT;
BEGIN
    -- Calculate baselines for each operation type
    FOR v_operation_type IN
        SELECT DISTINCT operation_type
        FROM pggit.performance_metrics
        WHERE started_at >= now() - (p_lookback_hours || ' hours')::INTERVAL
    LOOP
        INSERT INTO pggit.performance_baselines (
            operation_type,
            percentile_50,
            percentile_75,
            percentile_90,
            percentile_95,
            percentile_99,
            sample_count
        )
        SELECT 
            v_operation_type,
            percentile_cont(0.50) WITHIN GROUP (ORDER BY duration_ms),
            percentile_cont(0.75) WITHIN GROUP (ORDER BY duration_ms),
            percentile_cont(0.90) WITHIN GROUP (ORDER BY duration_ms),
            percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_ms),
            percentile_cont(0.99) WITHIN GROUP (ORDER BY duration_ms),
            COUNT(*)::INT
        FROM pggit.performance_metrics
        WHERE operation_type = v_operation_type
        AND started_at >= now() - (p_lookback_hours || ' hours')::INTERVAL
        ON CONFLICT (operation_type, calculated_at) DO UPDATE
        SET percentile_50 = EXCLUDED.percentile_50,
            percentile_75 = EXCLUDED.percentile_75,
            percentile_90 = EXCLUDED.percentile_90,
            percentile_95 = EXCLUDED.percentile_95,
            percentile_99 = EXCLUDED.percentile_99,
            sample_count = EXCLUDED.sample_count;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Get performance dashboard
CREATE OR REPLACE FUNCTION pggit.get_performance_dashboard(
    p_time_range INTERVAL DEFAULT INTERVAL '1 hour'
) RETURNS TABLE (
    metric_type TEXT,
    metric_value JSONB
) AS $$
BEGIN
    -- Operations per minute
    RETURN QUERY
    SELECT 
        'operations_per_minute',
        jsonb_build_object(
            'value', COUNT(*) / EXTRACT(EPOCH FROM p_time_range) * 60,
            'unit', 'ops/min'
        )
    FROM pggit.performance_metrics
    WHERE started_at >= now() - p_time_range;
    
    -- Average response time
    RETURN QUERY
    SELECT 
        'average_response_time',
        jsonb_build_object(
            'value', ROUND(AVG(duration_ms), 2),
            'unit', 'ms'
        )
    FROM pggit.performance_metrics
    WHERE started_at >= now() - p_time_range;
    
    -- Slowest operations
    RETURN QUERY
    SELECT 
        'slowest_operations',
        jsonb_agg(jsonb_build_object(
            'operation', operation_name,
            'duration_ms', duration_ms,
            'time', started_at
        ) ORDER BY duration_ms DESC)
    FROM (
        SELECT operation_name, duration_ms, started_at
        FROM pggit.performance_metrics
        WHERE started_at >= now() - p_time_range
        ORDER BY duration_ms DESC
        LIMIT 10
    ) slow_ops;
    
    -- Active alerts
    RETURN QUERY
    SELECT 
        'active_alerts',
        jsonb_agg(jsonb_build_object(
            'type', alert_type,
            'severity', severity,
            'message', alert_message,
            'time', created_at
        ) ORDER BY created_at DESC)
    FROM pggit.performance_alerts
    WHERE created_at >= now() - p_time_range
    AND NOT acknowledged;
    
    -- Operation breakdown
    RETURN QUERY
    SELECT 
        'operation_breakdown',
        jsonb_object_agg(
            operation_type,
            jsonb_build_object(
                'count', op_count,
                'avg_duration_ms', avg_duration,
                'total_time_ms', total_duration
            )
        )
    FROM (
        SELECT 
            operation_type,
            COUNT(*) as op_count,
            ROUND(AVG(duration_ms), 2) as avg_duration,
            ROUND(SUM(duration_ms), 2) as total_duration
        FROM pggit.performance_metrics
        WHERE started_at >= now() - p_time_range
        GROUP BY operation_type
    ) op_stats;
END;
$$ LANGUAGE plpgsql;

-- Analyze query performance
CREATE OR REPLACE FUNCTION pggit.analyze_query_performance(
    p_query TEXT,
    p_params TEXT[] DEFAULT NULL
) RETURNS TABLE (
    execution_time_ms DECIMAL(10,3),
    planning_time_ms DECIMAL(10,3),
    rows_returned BIGINT,
    query_plan JSONB
) AS $$
DECLARE
    v_start_time TIMESTAMP(6);
    v_end_time TIMESTAMP(6);
    v_plan JSONB;
    v_exec_time DECIMAL(10,3);
    v_plan_time DECIMAL(10,3);
    v_rows BIGINT;
BEGIN
    -- Get query plan
    EXECUTE format('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) %s', p_query)
    INTO v_plan;
    
    -- Extract metrics from plan
    v_exec_time := (v_plan->0->>'Execution Time')::DECIMAL;
    v_plan_time := (v_plan->0->>'Planning Time')::DECIMAL;
    v_rows := (v_plan->0->'Plan'->>'Actual Rows')::BIGINT;
    
    -- Record metric
    PERFORM pggit.record_performance_metric(
        'query_analysis',
        p_query,
        now() - (v_exec_time || ' milliseconds')::INTERVAL,
        v_rows,
        jsonb_build_object('query_plan', v_plan)
    );
    
    RETURN QUERY
    SELECT v_exec_time, v_plan_time, v_rows, v_plan;
END;
$$ LANGUAGE plpgsql;

-- Monitor long-running operations
CREATE OR REPLACE FUNCTION pggit.monitor_long_running_operations()
RETURNS TABLE (
    pid INT,
    duration INTERVAL,
    query TEXT,
    state TEXT,
    wait_event TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        pg_stat_activity.pid,
        now() - pg_stat_activity.query_start as duration,
        pg_stat_activity.query,
        pg_stat_activity.state,
        pg_stat_activity.wait_event
    FROM pg_stat_activity
    WHERE pg_stat_activity.query_start < now() - interval '1 minute'
    AND pg_stat_activity.state != 'idle'
    AND pg_stat_activity.query NOT LIKE '%pg_stat_activity%'
    ORDER BY duration DESC;
END;
$$ LANGUAGE plpgsql;

-- Create performance views
CREATE OR REPLACE VIEW pggit.performance_summary AS
SELECT 
    operation_type,
    COUNT(*) as total_operations,
    ROUND(AVG(duration_ms), 2) as avg_duration_ms,
    ROUND(MIN(duration_ms), 2) as min_duration_ms,
    ROUND(MAX(duration_ms), 2) as max_duration_ms,
    ROUND(STDDEV(duration_ms), 2) as stddev_duration_ms,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY duration_ms)::numeric, 2) as median_duration_ms,
    ROUND(percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_ms)::numeric, 2) as p95_duration_ms,
    ROUND(percentile_cont(0.99) WITHIN GROUP (ORDER BY duration_ms)::numeric, 2) as p99_duration_ms
FROM pggit.performance_metrics
WHERE started_at >= now() - interval '24 hours'
GROUP BY operation_type;

CREATE OR REPLACE VIEW pggit.recent_alerts AS
SELECT 
    a.*,
    m.operation_type,
    m.operation_name,
    m.duration_ms
FROM pggit.performance_alerts a
JOIN pggit.performance_metrics m ON a.metric_id = m.metric_id
WHERE a.created_at >= now() - interval '24 hours'
ORDER BY a.created_at DESC;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_perf_metrics_started 
ON pggit.performance_metrics(started_at DESC);

CREATE INDEX IF NOT EXISTS idx_perf_metrics_operation 
ON pggit.performance_metrics(operation_type, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_perf_metrics_duration 
ON pggit.performance_metrics(duration_ms DESC) 
WHERE duration_ms > 100;

CREATE INDEX IF NOT EXISTS idx_traces_parent 
ON pggit.operation_traces(parent_trace_id);

CREATE INDEX IF NOT EXISTS idx_alerts_created 
ON pggit.performance_alerts(created_at DESC) 
WHERE NOT acknowledged;

-- Performance monitoring triggers
CREATE OR REPLACE FUNCTION pggit.auto_monitor_performance()
RETURNS event_trigger AS $$
DECLARE
    v_start_time TIMESTAMP(6);
    v_event_text TEXT;
    v_command_tag TEXT;
    v_schema TEXT;
    v_object TEXT;
BEGIN
    -- Record performance monitoring start
    v_start_time := clock_timestamp();
    v_command_tag := TG_TAG;

    -- Extract event details from tg_ddl_command_start
    BEGIN
        -- Try to parse command details
        v_event_text := (SELECT current_query FROM pg_stat_statements
                        WHERE userid = current_user_id LIMIT 1);
    EXCEPTION WHEN OTHERS THEN
        v_event_text := NULL;
    END;

    -- Record DDL operation performance
    INSERT INTO pggit.ddl_operation_history (
        operation_type,
        schema_name,
        object_name,
        command_tag,
        started_at,
        duration_ms,
        query_text,
        completed
    ) VALUES (
        'DDL',
        'pggit',
        TG_EVENT,
        v_command_tag,
        v_start_time,
        EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time))::INT,
        v_event_text,
        true
    ) ON CONFLICT DO NOTHING;

    -- Update performance baseline
    PERFORM pggit.calculate_performance_baselines();

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Schedule baseline calculation
CREATE OR REPLACE FUNCTION pggit.schedule_baseline_calculation()
RETURNS VOID AS $$
BEGIN
    -- This would be called by pg_cron or similar
    PERFORM pggit.calculate_performance_baselines();
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA pggit TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pggit TO PUBLIC;