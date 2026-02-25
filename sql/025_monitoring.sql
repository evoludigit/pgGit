-- pgGit Monitoring and Metrics Collection
-- File: 025_monitoring.sql
-- Purpose: Comprehensive metrics collection and observability

-- ============================================================================
-- Core Metrics Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.metrics (
    metric_id BIGSERIAL PRIMARY KEY,
    metric_name TEXT NOT NULL,
    metric_value NUMERIC,
    metric_type TEXT NOT NULL CHECK (metric_type IN ('counter', 'gauge', 'histogram', 'summary')),
    labels JSONB DEFAULT '{}',
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_metrics_name_time 
ON pggit.metrics(metric_name, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_metrics_time 
ON pggit.metrics(recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_metrics_labels 
ON pggit.metrics USING GIN(labels);

COMMENT ON TABLE pggit.metrics IS 
    'Time-series metrics storage for pgGit performance and operational monitoring.
     Supports counter, gauge, histogram, and summary metric types.';

-- ============================================================================
-- Metric Recording Functions
-- ============================================================================

-- Function: Record a metric value
CREATE OR REPLACE FUNCTION pggit.record_metric(
    p_metric_name TEXT,
    p_metric_value NUMERIC,
    p_metric_type TEXT DEFAULT 'gauge',
    p_labels JSONB DEFAULT '{}'
) RETURNS BIGINT AS $$
DECLARE
    v_metric_id BIGINT;
BEGIN
    INSERT INTO pggit.metrics (metric_name, metric_value, metric_type, labels)
    VALUES (p_metric_name, p_metric_value, p_metric_type, p_labels)
    RETURNING metric_id INTO v_metric_id;
    
    RETURN v_metric_id;
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE;

COMMENT ON FUNCTION pggit.record_metric IS 
    'Record a single metric value.
     Example: SELECT pggit.record_metric(''ddl_operations'', 1, ''counter'', ''{"type": "create"}'');';

-- Function: Record DDL operation metric
CREATE OR REPLACE FUNCTION pggit.record_ddl_metric(
    p_operation_type TEXT,
    p_duration_ms NUMERIC,
    p_object_type TEXT,
    p_success BOOLEAN
) RETURNS BIGINT AS $$
BEGIN
    RETURN pggit.record_metric(
        'ddl_operation_duration_ms',
        p_duration_ms,
        'histogram',
        jsonb_build_object(
            'operation', p_operation_type,
            'object_type', p_object_type,
            'success', p_success
        )
    );
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE;

COMMENT ON FUNCTION pggit.record_ddl_metric IS 
    'Record DDL operation timing and metadata.
     Automatically called by event triggers to track DDL performance.';

-- Function: Record branch operation metric
CREATE OR REPLACE FUNCTION pggit.record_branch_metric(
    p_operation TEXT,  -- create, switch, merge, delete
    p_duration_ms NUMERIC,
    p_branch_name TEXT,
    p_success BOOLEAN,
    p_details JSONB DEFAULT '{}'
) RETURNS BIGINT AS $$
BEGIN
    RETURN pggit.record_metric(
        'branch_operation_duration_ms',
        p_duration_ms,
        'histogram',
        jsonb_build_object(
            'operation', p_operation,
            'branch', p_branch_name,
            'success', p_success
        ) || p_details
    );
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE;

-- ============================================================================
-- Prometheus Metrics Export
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.prometheus_metrics()
RETURNS TABLE (
    metric_line TEXT
) AS $$
BEGIN
    RETURN QUERY
    
    -- DDL Operation Counter
    SELECT format(
        'pggit_ddl_operations_total{operation="%s",object_type="%s",status="%s"} %s',
        labels->>'operation',
        labels->>'object_type',
        CASE WHEN (labels->>'success')::BOOLEAN THEN 'success' ELSE 'failure' END,
        count::TEXT
    )
    FROM (
        SELECT 
            labels,
            count(*) as count
        FROM pggit.metrics
        WHERE metric_name = 'ddl_operation_duration_ms'
        AND recorded_at > CURRENT_TIMESTAMP - INTERVAL '5 minutes'
        GROUP BY labels
    ) sub;
    
    -- DDL Operation Duration Histogram (simplified)
    RETURN QUERY
    SELECT format(
        'pggit_ddl_operation_duration_ms{operation="%s",object_type="%s"} %s',
        labels->>'operation',
        labels->>'object_type',
        round(avg(metric_value), 3)::TEXT
    )
    FROM pggit.metrics
    WHERE metric_name = 'ddl_operation_duration_ms'
    AND recorded_at > CURRENT_TIMESTAMP - INTERVAL '5 minutes'
    GROUP BY labels;
    
    -- Active Branches Gauge
    RETURN QUERY
    SELECT format(
        'pggit_active_branches %s',
        (SELECT count(*)::TEXT FROM pggit.branches WHERE status = 'ACTIVE')
    );
    
    -- Total Objects Gauge
    RETURN QUERY
    SELECT format(
        'pggit_tracked_objects %s',
        (SELECT count(*)::TEXT FROM pggit.objects WHERE is_active = true)
    );
    
    -- History Table Size
    RETURN QUERY
    SELECT format(
        'pggit_history_rows %s',
        (SELECT count(*)::TEXT FROM pggit.history)
    );
    
    -- Merge Operation Metrics
    RETURN QUERY
    SELECT format(
        'pggit_merge_operations_total{status="%s"} %s',
        status,
        count::TEXT
    )
    FROM (
        SELECT status, count(*) as count
        FROM pggit.merge_history
        WHERE completed_at > CURRENT_TIMESTAMP - INTERVAL '1 hour'
        GROUP BY status
    ) sub;
    
    -- Tracking Pause Status
    RETURN QUERY
    SELECT format(
        'pggit_tracking_paused %s',
        CASE WHEN EXISTS (SELECT 1 FROM pggit.tracking_config WHERE config_key = 'ddl_tracking_paused') 
             THEN '1' ELSE '0' END
    );
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
STABLE;

COMMENT ON FUNCTION pggit.prometheus_metrics IS 
    'Export metrics in Prometheus exposition format.
     Use with Prometheus scrape configuration or pushgateway.
     Example: curl http://postgres:8080/metrics (via appropriate endpoint)';

-- ============================================================================
-- System Health Check
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.health_check()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    message TEXT,
    details JSONB
) AS $$
DECLARE
    v_branch_count INTEGER;
    v_object_count INTEGER;
    v_history_count INTEGER;
    v_tracking_paused BOOLEAN;
    v_oldest_uncompleted_merge TIMESTAMP;
BEGIN
    -- Check 1: Database connectivity (implicit - if we can run, we're connected)
    RETURN QUERY SELECT 
        'database_connection'::TEXT,
        'healthy'::TEXT,
        'Database connection active'::TEXT,
        '{}'::JSONB;
    
    -- Check 2: Branch count
    SELECT count(*) INTO v_branch_count FROM pggit.branches;
    RETURN QUERY SELECT 
        'branches'::TEXT,
        CASE WHEN v_branch_count > 0 THEN 'healthy' ELSE 'warning' END::TEXT,
        format('Found %s branches', v_branch_count)::TEXT,
        jsonb_build_object('count', v_branch_count);
    
    -- Check 3: Object tracking
    SELECT count(*) INTO v_object_count FROM pggit.objects WHERE is_active = true;
    RETURN QUERY SELECT 
        'tracked_objects'::TEXT,
        'healthy'::TEXT,
        format('Tracking %s active objects', v_object_count)::TEXT,
        jsonb_build_object('count', v_object_count);
    
    -- Check 4: History table size
    SELECT count(*) INTO v_history_count FROM pggit.history;
    RETURN QUERY SELECT 
        'history_size'::TEXT,
        CASE 
            WHEN v_history_count < 100000 THEN 'healthy'
            WHEN v_history_count < 1000000 THEN 'warning'
            ELSE 'critical'
        END::TEXT,
        format('History table contains %s records', v_history_count)::TEXT,
        jsonb_build_object('count', v_history_count);
    
    -- Check 5: DDL tracking status
    SELECT EXISTS (
        SELECT 1 FROM pggit.tracking_config WHERE config_key = 'ddl_tracking_paused'
    ) INTO v_tracking_paused;
    RETURN QUERY SELECT 
        'ddl_tracking'::TEXT,
        CASE WHEN v_tracking_paused THEN 'warning' ELSE 'healthy' END::TEXT,
        CASE 
            WHEN v_tracking_paused THEN 'DDL tracking is currently paused'
            ELSE 'DDL tracking is active'
        END::TEXT,
        jsonb_build_object('paused', v_tracking_paused);
    
    -- Check 6: Merge operations
    SELECT max(initiated_at) INTO v_oldest_uncompleted_merge
    FROM pggit.merge_history
    WHERE status = 'in_progress' OR status = 'awaiting_resolution';
    
    RETURN QUERY SELECT 
        'merge_operations'::TEXT,
        CASE 
            WHEN v_oldest_uncompleted_merge IS NULL THEN 'healthy'
            WHEN v_oldest_uncompleted_merge < CURRENT_TIMESTAMP - INTERVAL '1 hour' THEN 'warning'
            ELSE 'healthy'
        END::TEXT,
        CASE 
            WHEN v_oldest_uncompleted_merge IS NULL THEN 'No incomplete merges'
            ELSE format('Oldest incomplete merge started at %s', v_oldest_uncompleted_merge)
        END::TEXT,
        jsonb_build_object('oldest_uncompleted', v_oldest_uncompleted_merge);
    
    -- Check 7: Disk space (simplified check)
    RETURN QUERY SELECT 
        'disk_space'::TEXT,
        'healthy'::TEXT,
        'Disk space check requires external monitoring'::TEXT,
        '{}'::JSONB;
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
STABLE;

COMMENT ON FUNCTION pggit.health_check IS 
    'Perform comprehensive health check of pgGit system.
     Returns status for each component (database, branches, objects, history, tracking, merges, disk).
     Example: SELECT * FROM pggit.health_check();';

-- ============================================================================
-- Metrics Aggregation Functions
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.get_metric_stats(
    p_metric_name TEXT,
    p_time_window INTERVAL DEFAULT INTERVAL '1 hour'
)
RETURNS TABLE (
    metric_name TEXT,
    count BIGINT,
    avg_value NUMERIC,
    min_value NUMERIC,
    max_value NUMERIC,
    p50_value NUMERIC,
    p95_value NUMERIC,
    p99_value NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p_metric_name::TEXT,
        count(*)::BIGINT,
        avg(metric_value)::NUMERIC,
        min(metric_value)::NUMERIC,
        max(metric_value)::NUMERIC,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY metric_value)::NUMERIC as p50_value,
        percentile_cont(0.95) WITHIN GROUP (ORDER BY metric_value)::NUMERIC as p95_value,
        percentile_cont(0.99) WITHIN GROUP (ORDER BY metric_value)::NUMERIC as p99_value
    FROM pggit.metrics
    WHERE metric_name = p_metric_name
    AND recorded_at > CURRENT_TIMESTAMP - p_time_window;
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
STABLE;

COMMENT ON FUNCTION pggit.get_metric_stats IS 
    'Get statistical summary of a metric over a time window.
     Example: SELECT * FROM pggit.get_metric_stats(''ddl_operation_duration_ms'', ''1 hour'');';

-- ============================================================================
-- Metrics Cleanup
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.cleanup_old_metrics(
    p_retention INTERVAL DEFAULT INTERVAL '7 days'
)
RETURNS BIGINT AS $$
DECLARE
    v_deleted_count BIGINT;
BEGIN
    DELETE FROM pggit.metrics
    WHERE recorded_at < CURRENT_TIMESTAMP - p_retention;
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    
    RAISE NOTICE 'Cleaned up % old metric records (older than %)', 
        v_deleted_count, p_retention;
    
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE;

COMMENT ON FUNCTION pggit.cleanup_old_metrics IS 
    'Clean up metric records older than the specified retention period.
     Default retention is 7 days for operational metrics.
     Example: SELECT pggit.cleanup_old_metrics(''7 days'');';

-- ============================================================================
-- Alert Conditions and Notifications
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.check_alert_conditions()
RETURNS TABLE (
    alert_name TEXT,
    severity TEXT,
    message TEXT,
    details JSONB
) AS $$
DECLARE
    v_history_count BIGINT;
    v_incomplete_merges BIGINT;
    v_tracking_paused BOOLEAN;
    v_avg_ddl_duration NUMERIC;
BEGIN
    -- Alert 1: History table too large
    SELECT count(*) INTO v_history_count FROM pggit.history;
    IF v_history_count > 1000000 THEN
        RETURN QUERY SELECT 
            'history_table_size'::TEXT,
            'warning'::TEXT,
            format('History table has %s records. Consider running retention policy.', v_history_count)::TEXT,
            jsonb_build_object('count', v_history_count, 'threshold', 1000000);
    END IF;
    
    -- Alert 2: Incomplete merges too old
    SELECT count(*) INTO v_incomplete_merges
    FROM pggit.merge_history
    WHERE status IN ('in_progress', 'awaiting_resolution')
    AND initiated_at < CURRENT_TIMESTAMP - INTERVAL '1 hour';
    
    IF v_incomplete_merges > 0 THEN
        RETURN QUERY SELECT 
            'stale_merges'::TEXT,
            'warning'::TEXT,
            format('%s merge operations have been incomplete for over 1 hour', v_incomplete_merges)::TEXT,
            jsonb_build_object('count', v_incomplete_merges);
    END IF;
    
    -- Alert 3: DDL tracking paused
    SELECT EXISTS (
        SELECT 1 FROM pggit.tracking_config WHERE config_key = 'ddl_tracking_paused'
    ) INTO v_tracking_paused;
    
    IF v_tracking_paused THEN
        RETURN QUERY SELECT 
            'tracking_paused'::TEXT,
            'info'::TEXT,
            'DDL tracking is currently paused'::TEXT,
            jsonb_build_object('paused', true);
    END IF;
    
    -- Alert 4: DDL operations taking too long
    SELECT avg(metric_value) INTO v_avg_ddl_duration
    FROM pggit.metrics
    WHERE metric_name = 'ddl_operation_duration_ms'
    AND recorded_at > CURRENT_TIMESTAMP - INTERVAL '5 minutes';
    
    IF v_avg_ddl_duration > 100 THEN  -- 100ms threshold
        RETURN QUERY SELECT 
            'slow_ddl_operations'::TEXT,
            'warning'::TEXT,
            format('Average DDL operation time is %s ms (threshold: 100ms)', round(v_avg_ddl_duration, 2))::TEXT,
            jsonb_build_object('avg_duration_ms', v_avg_ddl_duration, 'threshold_ms', 100);
    END IF;
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
STABLE;

COMMENT ON FUNCTION pggit.check_alert_conditions IS 
    'Check for alert conditions and return any active alerts.
     Monitors: history size, stale merges, tracking status, DDL performance.
     Example: SELECT * FROM pggit.check_alert_conditions();';

-- ============================================================================
-- Grant Permissions
-- ============================================================================

GRANT SELECT ON pggit.metrics TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.prometheus_metrics() TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.health_check() TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.get_metric_stats(TEXT, INTERVAL) TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.check_alert_conditions() TO PUBLIC;
