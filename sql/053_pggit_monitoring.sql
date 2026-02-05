-- pgGit Monitoring and Metrics
-- Production observability for pgGit installations

-- ============================================
-- PART 1: Performance Metrics Collection
-- ============================================

-- NOTE: performance_metrics table defined in 017_performance_monitoring.sql
-- This file extends with additional functions and monitoring capabilities

-- Monitoring metrics table for this module
CREATE TABLE IF NOT EXISTS pggit.monitoring_metrics (
    metric_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    metric_type TEXT NOT NULL,
    metric_value NUMERIC NOT NULL,
    tags JSONB DEFAULT '{}'::jsonb,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_monitoring_metrics_type_time
    ON pggit.monitoring_metrics(metric_type, recorded_at DESC);

-- Record performance metrics
DROP FUNCTION IF EXISTS pggit.record_metric(TEXT, NUMERIC, JSONB) CASCADE;
CREATE OR REPLACE FUNCTION pggit.record_metric(
    p_type TEXT,
    p_value NUMERIC,
    p_tags JSONB DEFAULT '{}'
) RETURNS VOID AS $$
BEGIN
    INSERT INTO pggit.monitoring_metrics (metric_type, metric_value, tags)
    VALUES (p_type, p_value, p_tags);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.record_metric(TEXT, NUMERIC, JSONB) IS
'Record a performance metric for monitoring and alerting.';

-- ============================================
-- PART 2: Health Check System
-- ============================================

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

    -- Check 2: Recent activity (last hour)
    RETURN QUERY
    SELECT
        'recent_activity'::TEXT,
        CASE WHEN COUNT(*) > 0 THEN 'healthy' ELSE 'warning' END::TEXT,
        format('%s changes in last hour', COUNT(*))::TEXT,
        jsonb_build_object('change_count', COUNT(*))
    FROM pggit.history
    WHERE created_at > NOW() - INTERVAL '1 hour';

    -- Check 3: Storage size health
    RETURN QUERY
    SELECT
        'storage_size'::TEXT,
        CASE
            WHEN size_mb < 1000 THEN 'healthy'
            WHEN size_mb < 5000 THEN 'warning'
            ELSE 'critical'
        END::TEXT,
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

    -- Check 5: Performance metrics collection
    RETURN QUERY
    SELECT
        'metrics_collection'::TEXT,
        CASE WHEN COUNT(*) > 0 THEN 'healthy' ELSE 'warning' END::TEXT,
        format('%s metrics collected in last hour', COUNT(*))::TEXT,
        jsonb_build_object('metrics_count', COUNT(*))
    FROM pggit.monitoring_metrics
    WHERE recorded_at > NOW() - INTERVAL '1 hour';

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.health_check() IS
'Comprehensive health check for pgGit installation. Returns status for all critical components.';

-- ============================================
-- PART 3: Metrics Summary Views
-- ============================================

-- Metrics summary view
CREATE OR REPLACE VIEW pggit.metrics_summary AS
SELECT
    metric_type,
    COUNT(*) as sample_count,
    AVG(metric_value) as avg_value,
    MIN(metric_value) as min_value,
    MAX(metric_value) as max_value,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY metric_value) as p95_value,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY metric_value) as p99_value
FROM pggit.monitoring_metrics
WHERE recorded_at > NOW() - INTERVAL '1 hour'
GROUP BY metric_type;

COMMENT ON VIEW pggit.metrics_summary IS
'Performance metrics summary for the last hour. Use for dashboards and alerting.';

-- System overview view
CREATE OR REPLACE VIEW pggit.system_overview AS
SELECT
    'total_objects' as metric,
    COUNT(*)::TEXT as value,
    'Total tracked database objects' as description
FROM pggit.objects
WHERE is_active = true

UNION ALL

SELECT
    'total_changes' as metric,
    COUNT(*)::TEXT as value,
    'Total recorded schema changes' as description
FROM pggit.history

UNION ALL

SELECT
    'active_branches' as metric,
    COUNT(DISTINCT branch_id)::TEXT as value,
    'Number of active branches' as description
FROM pggit.history h
JOIN pggit.objects o ON h.object_id = o.id
WHERE o.is_active = true

UNION ALL

SELECT
    'storage_size_mb' as metric,
    (pg_total_relation_size('pggit.history') / 1024 / 1024)::TEXT as value,
    'Storage used by history table in MB' as description
;

COMMENT ON VIEW pggit.system_overview IS
'High-level system metrics for monitoring dashboards.';

-- ============================================
-- PART 4: Prometheus Metrics Export
-- ============================================

-- Prometheus metrics exporter
CREATE OR REPLACE FUNCTION pggit.prometheus_metrics()
RETURNS TEXT AS $$
DECLARE
    v_output TEXT := '';
    v_metric RECORD;
BEGIN
    -- Help and type definitions
    v_output := v_output || E'# HELP pggit_objects_total Total number of tracked objects\n';
    v_output := v_output || E'# TYPE pggit_objects_total gauge\n';
    v_output := v_output || format(E'pggit_objects_total %s\n',
        (SELECT COUNT(*) FROM pggit.objects WHERE is_active = true));

    v_output := v_output || E'# HELP pggit_changes_total Total number of recorded changes\n';
    v_output := v_output || E'# TYPE pggit_changes_total counter\n';
    v_output := v_output || format(E'pggit_changes_total %s\n',
        (SELECT COUNT(*) FROM pggit.history));

    v_output := v_output || E'# HELP pggit_storage_bytes Total storage used by pgGit\n';
    v_output := v_output || E'# TYPE pggit_storage_bytes gauge\n';
    v_output := v_output || format(E'pggit_storage_bytes %s\n',
        pg_total_relation_size('pggit.history') + pg_total_relation_size('pggit.objects'));

    -- Performance metrics by type
    FOR v_metric IN
        SELECT metric_type, AVG(metric_value) as avg_val, COUNT(*) as sample_count
        FROM pggit.monitoring_metrics
        WHERE recorded_at > NOW() - INTERVAL '5 minutes'
        GROUP BY metric_type
    LOOP
        v_output := v_output || format(E'# HELP pggit_%s_avg Average %s time\n',
            v_metric.metric_type, v_metric.metric_type);
        v_output := v_output || format(E'# TYPE pggit_%s_avg gauge\n', v_metric.metric_type);
        v_output := v_output || format(E'pggit_%s_avg %s\n',
            v_metric.metric_type, v_metric.avg_val);

        v_output := v_output || format(E'# HELP pggit_%s_samples Number of %s samples\n',
            v_metric.metric_type, v_metric.metric_type);
        v_output := v_output || format(E'# TYPE pggit_%s_samples gauge\n', v_metric.metric_type);
        v_output := v_output || format(E'pggit_%s_samples %s\n',
            v_metric.metric_type, v_metric.sample_count);
    END LOOP;

    RETURN v_output;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.prometheus_metrics() IS
'Export metrics in Prometheus format for monitoring systems.';

-- ============================================
-- PART 5: Automated Metrics Collection
-- ============================================

-- DDL performance monitoring trigger
CREATE OR REPLACE FUNCTION pggit.collect_ddl_metrics()
RETURNS event_trigger AS $$
DECLARE
    v_start TIMESTAMP;
    v_duration NUMERIC;
BEGIN
    v_start := clock_timestamp();

    -- This trigger fires after DDL commands
    -- Record the time it took to process the DDL
    v_duration := EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) * 1000;

    PERFORM pggit.record_metric(
        'ddl_processing_ms',
        v_duration,
        jsonb_build_object('command', TG_TAG)
    );
END;
$$ LANGUAGE plpgsql;

-- Create the event trigger for metrics collection
DO $$
BEGIN
    -- Drop existing trigger if it exists
    DROP EVENT TRIGGER IF EXISTS pggit_metrics_trigger;

    -- Create new trigger
    CREATE EVENT TRIGGER pggit_metrics_trigger
        ON ddl_command_end
        EXECUTE FUNCTION pggit.collect_ddl_metrics();
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Could not create metrics trigger: %', SQLERRM;
END $$;

COMMENT ON FUNCTION pggit.collect_ddl_metrics() IS
'Automatically collect performance metrics for DDL operations.';

-- ============================================
-- PART 6: Maintenance Functions
-- ============================================

-- Clean old metrics
CREATE OR REPLACE FUNCTION pggit.cleanup_old_metrics(
    p_retention_days INTEGER DEFAULT 30
) RETURNS INTEGER AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    DELETE FROM pggit.monitoring_metrics
    WHERE recorded_at < NOW() - (p_retention_days || ' days')::INTERVAL;

    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.cleanup_old_metrics(INTEGER) IS
'Clean up old performance metrics to prevent table bloat. Returns number of records deleted.';

-- Maintenance view
CREATE OR REPLACE VIEW pggit.maintenance_status AS
SELECT
    'metrics_table_size' as check_name,
    pg_size_pretty(pg_total_relation_size('pggit.monitoring_metrics')) as value,
    CASE
        WHEN pg_total_relation_size('pggit.monitoring_metrics') > 100*1024*1024 THEN 'warning'
        ELSE 'healthy'
    END as status
UNION ALL
SELECT
    'oldest_metric' as check_name,
    MIN(recorded_at)::TEXT as value,
    CASE
        WHEN MIN(recorded_at) < NOW() - INTERVAL '90 days' THEN 'warning'
        ELSE 'healthy'
    END as status
FROM pggit.monitoring_metrics
UNION ALL
SELECT
    'metrics_retention_days' as check_name,
    EXTRACT(EPOCH FROM (NOW() - MIN(recorded_at)))/86400 || ' days' as value,
    'info' as status
FROM pggit.monitoring_metrics;

COMMENT ON VIEW pggit.maintenance_status IS
'Maintenance status for monitoring and alerting.';

-- Grant permissions for monitoring
GRANT SELECT ON pggit.monitoring_metrics TO PUBLIC;
GRANT SELECT ON pggit.metrics_summary TO PUBLIC;
GRANT SELECT ON pggit.system_overview TO PUBLIC;
GRANT SELECT ON pggit.maintenance_status TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.health_check() TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.prometheus_metrics() TO PUBLIC;

-- Final setup message
DO $$
BEGIN
    RAISE NOTICE 'pgGit monitoring system installed successfully!';
    RAISE NOTICE 'Available functions:';
    RAISE NOTICE '  - pggit.health_check() - System health status';
    RAISE NOTICE '  - pggit.prometheus_metrics() - Prometheus format metrics';
    RAISE NOTICE 'Available views:';
    RAISE NOTICE '  - pggit.metrics_summary - Performance metrics';
    RAISE NOTICE '  - pggit.system_overview - System status';
    RAISE NOTICE '  - pggit.maintenance_status - Maintenance info';
END $$;