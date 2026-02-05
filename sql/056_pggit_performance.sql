-- File: sql/pggit_performance.sql

-- Performance optimization helpers for pgGit

-- ============================================
-- PART 1: Query Performance Analysis
-- ============================================

CREATE OR REPLACE FUNCTION pggit.analyze_slow_queries(
    threshold_ms NUMERIC DEFAULT 100
)
RETURNS TABLE (
    query_type TEXT,
    avg_duration_ms NUMERIC,
    max_duration_ms NUMERIC,
    call_count BIGINT,
    total_time_ms NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        metric_type,
        AVG(metric_value)::NUMERIC(10,2),
        MAX(metric_value)::NUMERIC(10,2),
        COUNT(*)::BIGINT,
        SUM(metric_value)::NUMERIC(10,2)
    FROM pggit.performance_tracking_metrics
    WHERE metric_value > threshold_ms
        AND recorded_at > NOW() - INTERVAL '1 hour'
    GROUP BY metric_type
    ORDER BY total_time_ms DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.analyze_slow_queries(NUMERIC) IS
'Identify slow query patterns above threshold (default 100ms)';

-- ============================================
-- PART 2: Index Usage Analysis
-- ============================================

CREATE OR REPLACE FUNCTION pggit.check_index_usage()
RETURNS TABLE (
    table_name TEXT,
    index_name TEXT,
    index_scans BIGINT,
    rows_read BIGINT,
    effectiveness NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        schemaname || '.' || tablename,
        indexrelname,
        idx_scan,
        idx_tup_read,
        CASE
            WHEN idx_scan > 0 THEN (idx_tup_read::NUMERIC / idx_scan)::NUMERIC(10,2)
            ELSE 0
        END
    FROM pg_stat_user_indexes
    WHERE schemaname = 'pggit'
    ORDER BY idx_scan DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 3: Automatic Vacuum Monitoring
-- ============================================

CREATE OR REPLACE FUNCTION pggit.vacuum_health()
RETURNS TABLE (
    table_name TEXT,
    last_vacuum TIMESTAMP,
    last_autovacuum TIMESTAMP,
    n_dead_tup BIGINT,
    vacuum_recommended BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        schemaname || '.' || relname,
        last_vacuum,
        last_autovacuum,
        n_dead_tup,
        (n_dead_tup > 1000 AND
         (last_autovacuum IS NULL OR last_autovacuum < NOW() - INTERVAL '1 day'))
    FROM pg_stat_user_tables
    WHERE schemaname = 'pggit'
    ORDER BY n_dead_tup DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 4: Cache Hit Ratio
-- ============================================

CREATE OR REPLACE FUNCTION pggit.cache_hit_ratio()
RETURNS TABLE (
    table_name TEXT,
    heap_read BIGINT,
    heap_hit BIGINT,
    hit_ratio NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        schemaname || '.' || relname,
        heap_blks_read,
        heap_blks_hit,
        CASE
            WHEN (heap_blks_hit + heap_blks_read) > 0
            THEN (heap_blks_hit::NUMERIC * 100 / (heap_blks_hit + heap_blks_read))::NUMERIC(5,2)
            ELSE 0
        END
    FROM pg_statio_user_tables
    WHERE schemaname = 'pggit'
    ORDER BY heap_blks_read DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 5: Connection Pool Monitoring
-- ============================================

CREATE OR REPLACE FUNCTION pggit.connection_stats()
RETURNS TABLE (
    state TEXT,
    count BIGINT,
    avg_duration INTERVAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(state, 'idle'),
        COUNT(*)::BIGINT,
        AVG(NOW() - state_change)
    FROM pg_stat_activity
    WHERE datname = current_database()
    GROUP BY state
    ORDER BY count DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 6: Performance Metrics Collection
-- ============================================

-- NOTE: performance_metrics table defined in 017_performance_monitoring.sql
-- This file extends with additional utility functions

-- Performance tracking metrics table for this module
CREATE TABLE IF NOT EXISTS pggit.performance_tracking_metrics (
    id BIGSERIAL PRIMARY KEY,
    metric_type TEXT NOT NULL,
    metric_value NUMERIC NOT NULL,
    metadata JSONB,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_perf_tracking_metrics_type_time
    ON pggit.performance_tracking_metrics (metric_type, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_perf_tracking_metrics_value
    ON pggit.performance_tracking_metrics (metric_value DESC);

-- Function to record performance metrics
DROP FUNCTION IF EXISTS pggit.record_metric(TEXT, NUMERIC, JSONB) CASCADE;
CREATE OR REPLACE FUNCTION pggit.record_metric(
    metric_type TEXT,
    metric_value NUMERIC,
    metadata JSONB DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO pggit.performance_tracking_metrics (metric_type, metric_value, metadata)
    VALUES (metric_type, metric_value, metadata);

    -- Keep only last 30 days of metrics
    DELETE FROM pggit.performance_tracking_metrics
    WHERE recorded_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 7: Query Execution Time Wrapper
-- ============================================

CREATE OR REPLACE FUNCTION pggit.execute_with_timing(
    query_text TEXT,
    OUT execution_time_ms NUMERIC,
    OUT result_rows BIGINT
)
RETURNS RECORD AS $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    row_count BIGINT;
BEGIN
    start_time := clock_timestamp();

    -- Execute the query and count rows
    EXECUTE 'SELECT COUNT(*) FROM (' || query_text || ') AS subquery' INTO row_count;

    end_time := clock_timestamp();

    execution_time_ms := EXTRACT(epoch FROM (end_time - start_time)) * 1000;
    result_rows := row_count;

    -- Record the metric
    PERFORM pggit.record_metric('custom_query_ms', execution_time_ms,
                               jsonb_build_object('query', left(query_text, 100)));
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 8: Index Recommendations
-- ============================================

CREATE OR REPLACE FUNCTION pggit.recommend_indexes()
RETURNS TABLE (
    table_name TEXT,
    column_name TEXT,
    index_type TEXT,
    reason TEXT,
    estimated_benefit TEXT
) AS $$
BEGIN
    -- Recommend indexes for frequently queried columns
    RETURN QUERY
    SELECT
        'pggit.objects'::TEXT,
        'object_name'::TEXT,
        'btree'::TEXT,
        'High selectivity column frequently used in WHERE clauses'::TEXT,
        '10-50x improvement for name-based lookups'::TEXT
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'pggit' AND tablename = 'objects'
        AND indexdef LIKE '%object_name%'
    );

    RETURN QUERY
    SELECT
        'pggit.history'::TEXT,
        'object_id'::TEXT,
        'btree'::TEXT,
        'Foreign key column used in joins'::TEXT,
        '5-20x improvement for object history queries'::TEXT
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'pggit' AND tablename = 'history'
        AND indexdef LIKE '%object_id%'
    );

    RETURN QUERY
    SELECT
        'pggit.history'::TEXT,
        'created_at'::TEXT,
        'btree'::TEXT,
        'Time-based queries for audit trails'::TEXT,
        '10-30x improvement for temporal queries'::TEXT
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'pggit' AND tablename = 'history'
        AND indexdef LIKE '%created_at%'
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 9: Partitioning Analysis
-- ============================================

CREATE OR REPLACE FUNCTION pggit.partitioning_analysis()
RETURNS TABLE (
    table_name TEXT,
    total_size TEXT,
    row_count BIGINT,
    avg_row_size TEXT,
    partitioning_recommended BOOLEAN,
    recommendation TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        schemaname || '.' || tablename,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)),
        n_tup_ins - n_tup_del,
        pg_size_pretty((pg_total_relation_size(schemaname||'.'||tablename) / GREATEST(n_tup_ins - n_tup_del, 1))::bigint),
        CASE
            WHEN pg_total_relation_size(schemaname||'.'||tablename) > 1073741824 -- 1GB
                 AND n_tup_ins - n_tup_del > 1000000 THEN true
            ELSE false
        END,
        CASE
            WHEN pg_total_relation_size(schemaname||'.'||tablename) > 1073741824
                 AND n_tup_ins - n_tup_del > 1000000
            THEN 'Consider partitioning by date ranges or hash'::TEXT
            ELSE 'Partitioning not currently needed'::TEXT
        END
    FROM pg_stat_user_tables
    WHERE schemaname = 'pggit'
        AND tablename IN ('history', 'objects')
    ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 10: System Resource Monitoring
-- ============================================

CREATE OR REPLACE FUNCTION pggit.system_resources()
RETURNS TABLE (
    resource_type TEXT,
    current_value TEXT,
    recommended_value TEXT,
    status TEXT
) AS $$
DECLARE
    shared_buffers_current TEXT;
    work_mem_current TEXT;
    maintenance_work_mem_current TEXT;
    total_ram_bytes BIGINT;
    recommended_shared_buffers TEXT;
BEGIN
    -- Get current settings
    SELECT setting INTO shared_buffers_current
    FROM pg_settings WHERE name = 'shared_buffers';

    SELECT setting INTO work_mem_current
    FROM pg_settings WHERE name = 'work_mem';

    SELECT setting INTO maintenance_work_mem_current
    FROM pg_settings WHERE name = 'maintenance_work_mem';

    -- Calculate recommendations (rough estimates)
    SELECT (totalram * 1024 * 1024 / 4)::bigint INTO total_ram_bytes
    FROM (SELECT (string_to_array(version(), ' '))[1] as version) v,
         LATERAL (SELECT substring(version from '(\d+)')::bigint as major_version) mv
    CROSS JOIN LATERAL (
        SELECT CASE
            WHEN pg_platform = 'linux' THEN (SELECT (regexp_match(pg_ls_dir('/proc'), '(\d+)'))[1]::bigint * 1024)
            ELSE 8589934592  -- 8GB default assumption
        END as totalram
        FROM (SELECT version() as pg_platform) p
    ) r;

    recommended_shared_buffers := pg_size_pretty(GREATEST(total_ram_bytes / 4, 134217728)); -- max(25% of RAM, 128MB)

    RETURN QUERY
    SELECT
        'shared_buffers'::TEXT,
        shared_buffers_current,
        recommended_shared_buffers,
        CASE
            WHEN shared_buffers_current::bigint < 134217728 THEN 'Increase recommended'::TEXT
            ELSE 'OK'::TEXT
        END;

    RETURN QUERY
    SELECT
        'work_mem'::TEXT,
        work_mem_current,
        '4MB'::TEXT,
        CASE
            WHEN work_mem_current::bigint < 4194304 THEN 'Increase recommended'::TEXT
            ELSE 'OK'::TEXT
        END;

    RETURN QUERY
    SELECT
        'maintenance_work_mem'::TEXT,
        maintenance_work_mem_current,
        '64MB'::TEXT,
        CASE
            WHEN maintenance_work_mem_current::bigint < 67108864 THEN 'Increase recommended'::TEXT
            ELSE 'OK'::TEXT
        END;
END;
$$ LANGUAGE plpgsql;