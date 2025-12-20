-- pgGit Monitoring Module
-- Performance metrics, health checks, and observability

-- Performance metrics table
CREATE TABLE IF NOT EXISTS pggit.performance_metrics (
    metric_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    metric_type TEXT NOT NULL,
    metric_value NUMERIC NOT NULL,
    tags JSONB DEFAULT '{}'::jsonb,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_perf_metrics_type_time
    ON pggit.performance_metrics(metric_type, recorded_at DESC);

-- Record DDL operation metrics
CREATE OR REPLACE FUNCTION pggit.record_metric(
    p_type TEXT,
    p_value NUMERIC,
    p_tags JSONB DEFAULT '{}'
) RETURNS VOID AS $$
BEGIN
    INSERT INTO pggit.performance_metrics (metric_type, metric_value, tags)
    VALUES (p_type, p_value, p_tags);
END;
$$ LANGUAGE plpgsql;

-- Monitoring views
CREATE OR REPLACE VIEW pggit.metrics_summary AS
SELECT
    metric_type,
    COUNT(*) as sample_count,
    AVG(metric_value) as avg_value,
    MIN(metric_value) as min_value,
    MAX(metric_value) as max_value,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY metric_value) as p95_value,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY metric_value) as p99_value
FROM pggit.performance_metrics
WHERE recorded_at > NOW() - INTERVAL '1 hour'
GROUP BY metric_type;

COMMENT ON VIEW pggit.metrics_summary IS
'Performance metrics summary for the last hour.
Use for monitoring dashboards and alerting.';

-- Health check function
CREATE OR REPLACE FUNCTION pggit.health_check()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    message TEXT,
    details JSONB
) AS $$
BEGIN
    -- Check 1: Event triggers enabled
    RETURN QUERY
    SELECT
        'event_triggers'::TEXT,
        CASE WHEN COUNT(*) >= 2 THEN 'healthy' ELSE 'unhealthy' END::TEXT,
        format('%s event triggers active', COUNT(*))::TEXT,
        jsonb_build_object('count', COUNT(*), 'expected', 2)
    FROM pg_event_trigger
    WHERE evtname LIKE 'pggit%' AND evtenabled = 'O';

    -- Check 2: Recent activity
    RETURN QUERY
    SELECT
        'recent_activity'::TEXT,
        CASE WHEN COUNT(*) > 0 THEN 'healthy' ELSE 'warning' END::TEXT,
        format('%s changes in last hour', COUNT(*))::TEXT,
        jsonb_build_object('change_count', COUNT(*))
    FROM pggit.history
    WHERE created_at > NOW() - INTERVAL '1 hour';

    -- Check 3: Storage size
    RETURN QUERY
    SELECT
        'storage_size'::TEXT,
        CASE WHEN size_mb < 1000 THEN 'healthy'
             WHEN size_mb < 5000 THEN 'warning'
             ELSE 'critical' END::TEXT,
        format('%.2f MB used', size_mb)::TEXT,
        jsonb_build_object('size_mb', size_mb, 'threshold_mb', 5000)
    FROM (
        SELECT pg_total_relation_size('pggit.history')::NUMERIC / 1024 / 1024 as size_mb
    ) sizes;

    -- Check 4: Object count
    RETURN QUERY
    SELECT
        'object_count'::TEXT,
        'healthy'::TEXT,
        format('%s tracked objects', COUNT(*))::TEXT,
        jsonb_build_object('count', COUNT(*))
    FROM pggit.objects
    WHERE is_active = true;

END;
$$ LANGUAGE plpgsql;

-- Prometheus exporter function
CREATE OR REPLACE FUNCTION pggit.prometheus_metrics()
RETURNS TEXT AS $$
DECLARE
    v_output TEXT := '';
    v_metric RECORD;
BEGIN
    -- Metric: Total tracked objects
    v_output := v_output || format(E'# HELP pggit_objects_total Total number of tracked objects\n');
    v_output := v_output || format(E'# TYPE pggit_objects_total gauge\n');
    v_output := v_output || format(E'pggit_objects_total %s\n',
        (SELECT COUNT(*) FROM pggit.objects WHERE is_active = true)
    );

    -- Metric: Changes per hour
    v_output := v_output || format(E'# HELP pggit_changes_per_hour Changes in the last hour\n');
    v_output := v_output || format(E'# TYPE pggit_changes_per_hour gauge\n');
    v_output := v_output || format(E'pggit_changes_per_hour %s\n',
        (SELECT COUNT(*) FROM pggit.history WHERE created_at > NOW() - INTERVAL '1 hour')
    );

    -- Metric: Storage size
    v_output := v_output || format(E'# HELP pggit_storage_bytes Total storage used by pgGit\n');
    v_output := v_output || format(E'# TYPE pggit_storage_bytes gauge\n');
    v_output := v_output || format(E'pggit_storage_bytes %s\n',
        pg_total_relation_size('pggit.history') + pg_total_relation_size('pggit.objects')
    );

    -- Metric: Performance metrics by type
    FOR v_metric IN
        SELECT metric_type, AVG(metric_value) as avg_val
        FROM pggit.performance_metrics
        WHERE recorded_at > NOW() - INTERVAL '5 minutes'
        GROUP BY metric_type
    LOOP
        v_output := v_output || format(E'# HELP pggit_%s_avg Average %s\n',
            v_metric.metric_type, v_metric.metric_type);
        v_output := v_output || format(E'# TYPE pggit_%s_avg gauge\n', v_metric.metric_type);
        v_output := v_output || format(E'pggit_%s_avg %s\n',
            v_metric.metric_type, v_metric.avg_val);
    END LOOP;

    RETURN v_output;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.prometheus_metrics() IS
'Export metrics in Prometheus format.
Expose via pg_exporter or custom HTTP endpoint.';

-- Create metrics collection trigger
CREATE OR REPLACE FUNCTION pggit.collect_ddl_metrics()
RETURNS event_trigger AS $$
DECLARE
    v_start TIMESTAMP;
    v_duration NUMERIC;
BEGIN
    v_start := clock_timestamp();

    -- Track DDL execution time
    v_duration := EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) * 1000;

    PERFORM pggit.record_metric(
        'ddl_execution_ms',
        v_duration,
        jsonb_build_object('command', TG_TAG)
    );
END;
$$ LANGUAGE plpgsql;