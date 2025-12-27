-- ============================================================================
-- PHASE 8 ENHANCEMENT 3: Real-Time Analytics Dashboard Backend
-- ============================================================================
--
-- Purpose:
--   Provide comprehensive analytics infrastructure for real-time dashboard
--   with time-series aggregation, live data retrieval, and performance
--   optimization through materialized views and caching layers.
--
-- Architecture:
--   1. Time-Series Aggregation Tables (1min, 5min, 1hour buckets)
--   2. Materialized Views for Dashboard Queries
--   3. Real-Time Data Functions (for live updates)
--   4. Cache Management System
--   5. Dashboard API Data Aggregation
--
-- Performance Targets:
--   - Materialized view refresh: < 5 seconds
--   - Dashboard query latency: < 100ms
--   - Real-time data fetch: < 200ms
--   - Cache hit rate: > 85%
--
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS pggit_analytics;

-- ============================================================================
-- 1. TIME-SERIES AGGREGATION TABLES
-- ============================================================================

-- 1min bucket aggregations (kept for 7 days)
CREATE TABLE IF NOT EXISTS pggit_analytics.metrics_1min (
    metric_id BIGSERIAL PRIMARY KEY,
    bucket_time TIMESTAMP NOT NULL,
    webhook_id BIGINT,
    operation_type VARCHAR(100),
    metric_type VARCHAR(50) NOT NULL, -- 'delivery', 'latency', 'queue_depth', 'error_rate'

    -- Aggregated values
    count_total BIGINT DEFAULT 0,
    count_success BIGINT DEFAULT 0,
    count_failure BIGINT DEFAULT 0,
    count_timeout BIGINT DEFAULT 0,
    sum_latency_ms NUMERIC DEFAULT 0,
    min_latency_ms NUMERIC,
    max_latency_ms NUMERIC,
    avg_latency_ms NUMERIC,
    p50_latency_ms NUMERIC,
    p95_latency_ms NUMERIC,
    p99_latency_ms NUMERIC,

    -- Queue metrics
    queue_depth_min INT,
    queue_depth_max INT,
    queue_depth_avg NUMERIC,

    -- Circuit breaker state
    circuit_breaker_open INT DEFAULT 0, -- seconds open during bucket

    -- Additional metrics
    backpressure_events INT DEFAULT 0,
    rate_limit_hits INT DEFAULT 0,

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(bucket_time, webhook_id, operation_type, metric_type)
);

-- 5min bucket aggregations (kept for 30 days)
CREATE TABLE IF NOT EXISTS pggit_analytics.metrics_5min (
    metric_id BIGSERIAL PRIMARY KEY,
    bucket_time TIMESTAMP NOT NULL,
    webhook_id BIGINT,
    operation_type VARCHAR(100),
    metric_type VARCHAR(50) NOT NULL,

    -- Aggregated values
    count_total BIGINT DEFAULT 0,
    count_success BIGINT DEFAULT 0,
    count_failure BIGINT DEFAULT 0,
    count_timeout BIGINT DEFAULT 0,
    sum_latency_ms NUMERIC DEFAULT 0,
    min_latency_ms NUMERIC,
    max_latency_ms NUMERIC,
    avg_latency_ms NUMERIC,
    p50_latency_ms NUMERIC,
    p95_latency_ms NUMERIC,
    p99_latency_ms NUMERIC,

    -- Queue metrics
    queue_depth_min INT,
    queue_depth_max INT,
    queue_depth_avg NUMERIC,

    -- Circuit breaker state
    circuit_breaker_open INT DEFAULT 0,

    -- Additional metrics
    backpressure_events INT DEFAULT 0,
    rate_limit_hits INT DEFAULT 0,

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(bucket_time, webhook_id, operation_type, metric_type)
);

-- 1hour bucket aggregations (kept for 90 days)
CREATE TABLE IF NOT EXISTS pggit_analytics.metrics_1hour (
    metric_id BIGSERIAL PRIMARY KEY,
    bucket_time TIMESTAMP NOT NULL,
    webhook_id BIGINT,
    operation_type VARCHAR(100),
    metric_type VARCHAR(50) NOT NULL,

    -- Aggregated values
    count_total BIGINT DEFAULT 0,
    count_success BIGINT DEFAULT 0,
    count_failure BIGINT DEFAULT 0,
    count_timeout BIGINT DEFAULT 0,
    sum_latency_ms NUMERIC DEFAULT 0,
    min_latency_ms NUMERIC,
    max_latency_ms NUMERIC,
    avg_latency_ms NUMERIC,
    p50_latency_ms NUMERIC,
    p95_latency_ms NUMERIC,
    p99_latency_ms NUMERIC,

    -- Queue metrics
    queue_depth_min INT,
    queue_depth_max INT,
    queue_depth_avg NUMERIC,

    -- Circuit breaker state
    circuit_breaker_open INT DEFAULT 0,

    -- Additional metrics
    backpressure_events INT DEFAULT 0,
    rate_limit_hits INT DEFAULT 0,

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(bucket_time, webhook_id, operation_type, metric_type)
);

-- Dashboard cache table (very frequently accessed data)
CREATE TABLE IF NOT EXISTS pggit_analytics.dashboard_cache (
    cache_id BIGSERIAL PRIMARY KEY,
    cache_key VARCHAR(500) NOT NULL UNIQUE,
    data JSONB NOT NULL,
    cache_type VARCHAR(50) NOT NULL, -- 'overview', 'webhook_detail', 'performance', 'health'
    webhook_id BIGINT,

    -- Cache management
    hit_count BIGINT DEFAULT 0,
    miss_count BIGINT DEFAULT 0,
    last_hit TIMESTAMP,
    cached_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP + INTERVAL '1 minute',
    is_valid BOOLEAN DEFAULT TRUE,

    INDEX idx_cache_key (cache_key),
    INDEX idx_expires_at (expires_at),
    INDEX idx_webhook_id (webhook_id)
);

-- Analytics event log (for tracking real-time updates)
CREATE TABLE IF NOT EXISTS pggit_analytics.event_log (
    event_id BIGSERIAL PRIMARY KEY,
    event_type VARCHAR(100) NOT NULL, -- 'delivery', 'health_change', 'circuit_break', 'rate_limit'
    webhook_id BIGINT,
    operation_type VARCHAR(100),

    -- Event data
    event_data JSONB,
    severity VARCHAR(20), -- 'info', 'warning', 'critical'

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_webhook_time (webhook_id, created_at DESC),
    INDEX idx_event_type (event_type, created_at DESC),
    INDEX idx_severity (severity, created_at DESC)
);

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_metrics_1min_bucket_time ON pggit_analytics.metrics_1min(bucket_time DESC);
CREATE INDEX IF NOT EXISTS idx_metrics_1min_webhook_time ON pggit_analytics.metrics_1min(webhook_id, bucket_time DESC);
CREATE INDEX IF NOT EXISTS idx_metrics_1min_operation ON pggit_analytics.metrics_1min(operation_type, bucket_time DESC);

CREATE INDEX IF NOT EXISTS idx_metrics_5min_bucket_time ON pggit_analytics.metrics_5min(bucket_time DESC);
CREATE INDEX IF NOT EXISTS idx_metrics_5min_webhook_time ON pggit_analytics.metrics_5min(webhook_id, bucket_time DESC);
CREATE INDEX IF NOT EXISTS idx_metrics_5min_operation ON pggit_analytics.metrics_5min(operation_type, bucket_time DESC);

CREATE INDEX IF NOT EXISTS idx_metrics_1hour_bucket_time ON pggit_analytics.metrics_1hour(bucket_time DESC);
CREATE INDEX IF NOT EXISTS idx_metrics_1hour_webhook_time ON pggit_analytics.metrics_1hour(webhook_id, bucket_time DESC);
CREATE INDEX IF NOT EXISTS idx_metrics_1hour_operation ON pggit_analytics.metrics_1hour(operation_type, bucket_time DESC);

-- ============================================================================
-- 2. TIME-SERIES AGGREGATION FUNCTIONS
-- ============================================================================

-- Aggregate 1min metrics into 5min bucket
CREATE OR REPLACE FUNCTION pggit_analytics.aggregate_1min_to_5min()
RETURNS TABLE (
    rows_aggregated BIGINT,
    webhooks_processed BIGINT
) AS $$
DECLARE
    v_bucket_time TIMESTAMP;
    v_rows_affected BIGINT := 0;
    v_webhooks_affected BIGINT := 0;
BEGIN
    -- Get the 5min bucket for the current time (rounded down)
    v_bucket_time := DATE_TRUNC('5 minutes', CURRENT_TIMESTAMP);

    -- Aggregate 1min metrics from the past 5 minutes
    INSERT INTO pggit_analytics.metrics_5min (
        bucket_time, webhook_id, operation_type, metric_type,
        count_total, count_success, count_failure, count_timeout,
        sum_latency_ms, min_latency_ms, max_latency_ms, avg_latency_ms,
        p50_latency_ms, p95_latency_ms, p99_latency_ms,
        queue_depth_min, queue_depth_max, queue_depth_avg,
        circuit_breaker_open, backpressure_events, rate_limit_hits
    )
    SELECT
        v_bucket_time,
        webhook_id,
        operation_type,
        metric_type,
        SUM(count_total),
        SUM(count_success),
        SUM(count_failure),
        SUM(count_timeout),
        SUM(sum_latency_ms),
        MIN(min_latency_ms),
        MAX(max_latency_ms),
        AVG(avg_latency_ms),
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p50_latency_ms),
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY p95_latency_ms),
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY p99_latency_ms),
        MIN(queue_depth_min),
        MAX(queue_depth_max),
        AVG(queue_depth_avg),
        SUM(circuit_breaker_open),
        SUM(backpressure_events),
        SUM(rate_limit_hits)
    FROM pggit_analytics.metrics_1min
    WHERE bucket_time >= (v_bucket_time - INTERVAL '5 minutes')
      AND bucket_time < v_bucket_time
    GROUP BY webhook_id, operation_type, metric_type
    ON CONFLICT (bucket_time, webhook_id, operation_type, metric_type) DO UPDATE SET
        count_total = EXCLUDED.count_total,
        count_success = EXCLUDED.count_success,
        count_failure = EXCLUDED.count_failure,
        count_timeout = EXCLUDED.count_timeout,
        sum_latency_ms = EXCLUDED.sum_latency_ms,
        min_latency_ms = EXCLUDED.min_latency_ms,
        max_latency_ms = EXCLUDED.max_latency_ms,
        avg_latency_ms = EXCLUDED.avg_latency_ms,
        p50_latency_ms = EXCLUDED.p50_latency_ms,
        p95_latency_ms = EXCLUDED.p95_latency_ms,
        p99_latency_ms = EXCLUDED.p99_latency_ms,
        queue_depth_min = EXCLUDED.queue_depth_min,
        queue_depth_max = EXCLUDED.queue_depth_max,
        queue_depth_avg = EXCLUDED.queue_depth_avg,
        circuit_breaker_open = EXCLUDED.circuit_breaker_open,
        backpressure_events = EXCLUDED.backpressure_events,
        rate_limit_hits = EXCLUDED.rate_limit_hits;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    -- Count unique webhooks processed
    SELECT COUNT(DISTINCT webhook_id) INTO v_webhooks_affected
    FROM pggit_analytics.metrics_5min
    WHERE bucket_time = v_bucket_time;

    RETURN QUERY SELECT v_rows_affected, v_webhooks_affected;
END;
$$ LANGUAGE plpgsql;

-- Aggregate 5min metrics into 1hour bucket
CREATE OR REPLACE FUNCTION pggit_analytics.aggregate_5min_to_1hour()
RETURNS TABLE (
    rows_aggregated BIGINT,
    webhooks_processed BIGINT
) AS $$
DECLARE
    v_bucket_time TIMESTAMP;
    v_rows_affected BIGINT := 0;
    v_webhooks_affected BIGINT := 0;
BEGIN
    -- Get the 1hour bucket for the current time (rounded down)
    v_bucket_time := DATE_TRUNC('hour', CURRENT_TIMESTAMP);

    -- Aggregate 5min metrics from the past hour
    INSERT INTO pggit_analytics.metrics_1hour (
        bucket_time, webhook_id, operation_type, metric_type,
        count_total, count_success, count_failure, count_timeout,
        sum_latency_ms, min_latency_ms, max_latency_ms, avg_latency_ms,
        p50_latency_ms, p95_latency_ms, p99_latency_ms,
        queue_depth_min, queue_depth_max, queue_depth_avg,
        circuit_breaker_open, backpressure_events, rate_limit_hits
    )
    SELECT
        v_bucket_time,
        webhook_id,
        operation_type,
        metric_type,
        SUM(count_total),
        SUM(count_success),
        SUM(count_failure),
        SUM(count_timeout),
        SUM(sum_latency_ms),
        MIN(min_latency_ms),
        MAX(max_latency_ms),
        AVG(avg_latency_ms),
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p50_latency_ms),
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY p95_latency_ms),
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY p99_latency_ms),
        MIN(queue_depth_min),
        MAX(queue_depth_max),
        AVG(queue_depth_avg),
        SUM(circuit_breaker_open),
        SUM(backpressure_events),
        SUM(rate_limit_hits)
    FROM pggit_analytics.metrics_5min
    WHERE bucket_time >= (v_bucket_time - INTERVAL '1 hour')
      AND bucket_time < v_bucket_time
    GROUP BY webhook_id, operation_type, metric_type
    ON CONFLICT (bucket_time, webhook_id, operation_type, metric_type) DO UPDATE SET
        count_total = EXCLUDED.count_total,
        count_success = EXCLUDED.count_success,
        count_failure = EXCLUDED.count_failure,
        count_timeout = EXCLUDED.count_timeout,
        sum_latency_ms = EXCLUDED.sum_latency_ms,
        min_latency_ms = EXCLUDED.min_latency_ms,
        max_latency_ms = EXCLUDED.max_latency_ms,
        avg_latency_ms = EXCLUDED.avg_latency_ms,
        p50_latency_ms = EXCLUDED.p50_latency_ms,
        p95_latency_ms = EXCLUDED.p95_latency_ms,
        p99_latency_ms = EXCLUDED.p99_latency_ms,
        queue_depth_min = EXCLUDED.queue_depth_min,
        queue_depth_max = EXCLUDED.queue_depth_max,
        queue_depth_avg = EXCLUDED.queue_depth_avg,
        circuit_breaker_open = EXCLUDED.circuit_breaker_open,
        backpressure_events = EXCLUDED.backpressure_events,
        rate_limit_hits = EXCLUDED.rate_limit_hits;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    -- Count unique webhooks processed
    SELECT COUNT(DISTINCT webhook_id) INTO v_webhooks_affected
    FROM pggit_analytics.metrics_1hour
    WHERE bucket_time = v_bucket_time;

    RETURN QUERY SELECT v_rows_affected, v_webhooks_affected;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 3. CACHE MANAGEMENT FUNCTIONS
-- ============================================================================

-- Get cached dashboard data or return null if expired
CREATE OR REPLACE FUNCTION pggit_analytics.get_cached_data(
    p_cache_key VARCHAR
)
RETURNS TABLE (
    data JSONB,
    is_valid BOOLEAN,
    age_seconds INT
) AS $$
DECLARE
    v_cache RECORD;
BEGIN
    SELECT * INTO v_cache FROM pggit_analytics.dashboard_cache
    WHERE cache_key = p_cache_key AND is_valid = TRUE;

    IF v_cache IS NOT NULL THEN
        -- Check if expired
        IF v_cache.expires_at < CURRENT_TIMESTAMP THEN
            UPDATE pggit_analytics.dashboard_cache
            SET is_valid = FALSE, miss_count = miss_count + 1
            WHERE cache_id = v_cache.cache_id;

            RETURN QUERY SELECT NULL::JSONB, FALSE::BOOLEAN, NULL::INT;
        ELSE
            -- Update hit count
            UPDATE pggit_analytics.dashboard_cache
            SET hit_count = hit_count + 1, last_hit = CURRENT_TIMESTAMP
            WHERE cache_id = v_cache.cache_id;

            RETURN QUERY SELECT
                v_cache.data,
                TRUE::BOOLEAN,
                EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_cache.cached_at))::INT;
        END IF;
    ELSE
        RETURN QUERY SELECT NULL::JSONB, FALSE::BOOLEAN, NULL::INT;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Set cached data with TTL
CREATE OR REPLACE FUNCTION pggit_analytics.set_cached_data(
    p_cache_key VARCHAR,
    p_data JSONB,
    p_cache_type VARCHAR,
    p_webhook_id BIGINT DEFAULT NULL,
    p_ttl_seconds INT DEFAULT 60
)
RETURNS TABLE (
    cache_id BIGINT,
    is_new BOOLEAN
) AS $$
DECLARE
    v_cache_id BIGINT;
    v_is_new BOOLEAN := FALSE;
BEGIN
    INSERT INTO pggit_analytics.dashboard_cache (
        cache_key, data, cache_type, webhook_id,
        cached_at, expires_at, is_valid
    ) VALUES (
        p_cache_key,
        p_data,
        p_cache_type,
        p_webhook_id,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP + (p_ttl_seconds || ' seconds')::INTERVAL,
        TRUE
    )
    ON CONFLICT (cache_key) DO UPDATE SET
        data = EXCLUDED.data,
        cached_at = CURRENT_TIMESTAMP,
        expires_at = CURRENT_TIMESTAMP + (p_ttl_seconds || ' seconds')::INTERVAL,
        is_valid = TRUE
    RETURNING dashboard_cache.cache_id INTO v_cache_id;

    -- Check if this was a new insert
    SELECT NOT EXISTS (
        SELECT 1 FROM pggit_analytics.dashboard_cache
        WHERE cache_id = v_cache_id AND cached_at < CURRENT_TIMESTAMP - INTERVAL '1 second'
    ) INTO v_is_new;

    RETURN QUERY SELECT v_cache_id, v_is_new;
END;
$$ LANGUAGE plpgsql;

-- Invalidate cache entries matching a pattern
CREATE OR REPLACE FUNCTION pggit_analytics.invalidate_cache(
    p_cache_key_pattern VARCHAR
)
RETURNS TABLE (
    invalidated_count BIGINT
) AS $$
DECLARE
    v_count BIGINT;
BEGIN
    UPDATE pggit_analytics.dashboard_cache
    SET is_valid = FALSE
    WHERE cache_key LIKE p_cache_key_pattern;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN QUERY SELECT v_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 4. REAL-TIME DATA AGGREGATION FUNCTIONS
-- ============================================================================

-- Get current system overview (for dashboard top-level view)
CREATE OR REPLACE FUNCTION pggit_analytics.get_overview_metrics(
    p_lookback_minutes INT DEFAULT 5
)
RETURNS TABLE (
    total_deliveries BIGINT,
    successful_deliveries BIGINT,
    failed_deliveries BIGINT,
    success_rate_percent NUMERIC,
    current_queue_depth BIGINT,
    active_webhooks BIGINT,
    avg_p99_latency_ms NUMERIC,
    webhooks_unhealthy INT,
    circuit_breakers_open INT
) AS $$
BEGIN
    RETURN QUERY
    WITH recent_metrics AS (
        SELECT
            SUM(count_total) as total,
            SUM(count_success) as success,
            SUM(count_failure) as failure,
            AVG(p99_latency_ms) as p99_avg
        FROM pggit_analytics.metrics_1min
        WHERE bucket_time > CURRENT_TIMESTAMP - (p_lookback_minutes || ' minutes')::INTERVAL
          AND metric_type = 'delivery'
    ),
    queue_state AS (
        SELECT COUNT(*) as depth FROM pggit.alert_delivery_queue
        WHERE delivery_status = 'pending'
    ),
    health_state AS (
        SELECT
            COUNT(*) as total_webhooks,
            SUM(CASE WHEN health_status != 'healthy' THEN 1 ELSE 0 END) as unhealthy,
            SUM(CASE WHEN consecutive_failures >= 5 THEN 1 ELSE 0 END) as circuit_open
        FROM pggit.webhook_health_metrics
    )
    SELECT
        COALESCE(rm.total, 0)::BIGINT,
        COALESCE(rm.success, 0)::BIGINT,
        COALESCE(rm.failure, 0)::BIGINT,
        CASE WHEN COALESCE(rm.total, 0) > 0
            THEN ROUND((rm.success::NUMERIC / rm.total) * 100, 2)
            ELSE 100.0 END::NUMERIC,
        qs.depth,
        hs.total_webhooks,
        ROUND(COALESCE(rm.p99_avg, 0), 2)::NUMERIC,
        COALESCE(hs.unhealthy, 0)::INT,
        COALESCE(hs.circuit_open, 0)::INT
    FROM recent_metrics rm, queue_state qs, health_state hs;
END;
$$ LANGUAGE plpgsql;

-- Get detailed metrics for a specific webhook
CREATE OR REPLACE FUNCTION pggit_analytics.get_webhook_metrics(
    p_webhook_id BIGINT,
    p_lookback_hours INT DEFAULT 24
)
RETURNS TABLE (
    webhook_id BIGINT,
    health_status VARCHAR,
    total_deliveries BIGINT,
    success_rate_percent NUMERIC,
    p50_latency_ms NUMERIC,
    p95_latency_ms NUMERIC,
    p99_latency_ms NUMERIC,
    failure_count BIGINT,
    timeout_count BIGINT,
    circuit_breaker_open BOOLEAN,
    consecutive_failures INT,
    last_failure_time TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    WITH metrics AS (
        SELECT
            SUM(count_total) as total,
            SUM(count_success) as success,
            SUM(count_failure) as failure,
            SUM(count_timeout) as timeout,
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p50_latency_ms) as p50,
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY p95_latency_ms) as p95,
            PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY p99_latency_ms) as p99
        FROM pggit_analytics.metrics_1hour
        WHERE webhook_id = p_webhook_id
          AND bucket_time > CURRENT_TIMESTAMP - (p_lookback_hours || ' hours')::INTERVAL
    ),
    health AS (
        SELECT
            health_status,
            consecutive_failures,
            last_failure_time
        FROM pggit.webhook_health_metrics
        WHERE webhook_id = p_webhook_id
    )
    SELECT
        p_webhook_id,
        h.health_status,
        COALESCE(m.total, 0),
        CASE WHEN COALESCE(m.total, 0) > 0
            THEN ROUND((m.success::NUMERIC / m.total) * 100, 2)
            ELSE 100.0 END,
        ROUND(COALESCE(m.p50, 0), 2),
        ROUND(COALESCE(m.p95, 0), 2),
        ROUND(COALESCE(m.p99, 0), 2),
        COALESCE(m.failure, 0),
        COALESCE(m.timeout, 0),
        COALESCE(h.consecutive_failures, 0) >= 5,
        COALESCE(h.consecutive_failures, 0),
        h.last_failure_time
    FROM metrics m, health h;
END;
$$ LANGUAGE plpgsql;

-- Get time-series data for charting
CREATE OR REPLACE FUNCTION pggit_analytics.get_timeseries_data(
    p_webhook_id BIGINT DEFAULT NULL,
    p_metric_type VARCHAR DEFAULT 'delivery',
    p_lookback_hours INT DEFAULT 24,
    p_bucket_size VARCHAR DEFAULT '5min' -- '1min', '5min', '1hour'
)
RETURNS TABLE (
    bucket_time TIMESTAMP,
    webhook_id BIGINT,
    count_total BIGINT,
    count_success BIGINT,
    count_failure BIGINT,
    avg_latency_ms NUMERIC,
    p99_latency_ms NUMERIC
) AS $$
DECLARE
    v_table_name VARCHAR;
BEGIN
    -- Select appropriate table based on bucket size
    v_table_name := CASE
        WHEN p_bucket_size = '1min' THEN 'pggit_analytics.metrics_1min'
        WHEN p_bucket_size = '5min' THEN 'pggit_analytics.metrics_5min'
        WHEN p_bucket_size = '1hour' THEN 'pggit_analytics.metrics_1hour'
        ELSE 'pggit_analytics.metrics_5min'
    END;

    RETURN QUERY EXECUTE format(
        'SELECT
            bucket_time,
            webhook_id,
            count_total,
            count_success,
            count_failure,
            ROUND(avg_latency_ms::NUMERIC, 2),
            ROUND(p99_latency_ms::NUMERIC, 2)
        FROM %s
        WHERE metric_type = $1
          AND bucket_time > CURRENT_TIMESTAMP - ($2 || '' hours'')::INTERVAL
          AND ($3::BIGINT IS NULL OR webhook_id = $3)
        ORDER BY bucket_time DESC',
        v_table_name
    ) USING p_metric_type, p_lookback_hours, p_webhook_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 5. MATERIALIZED VIEWS FOR DASHBOARD
-- ============================================================================

-- Overall system health summary
CREATE OR REPLACE VIEW pggit_analytics.v_system_health AS
SELECT
    COUNT(*) as total_webhooks,
    SUM(CASE WHEN health_status = 'healthy' THEN 1 ELSE 0 END) as healthy_count,
    SUM(CASE WHEN health_status = 'degraded' THEN 1 ELSE 0 END) as degraded_count,
    SUM(CASE WHEN health_status = 'unavailable' THEN 1 ELSE 0 END) as unavailable_count,
    ROUND(100.0 * SUM(CASE WHEN health_status = 'healthy' THEN 1 ELSE 0 END) /
        NULLIF(COUNT(*), 0), 2) as health_percentage,
    SUM(consecutive_failures) as total_consecutive_failures,
    MAX(consecutive_failures) as max_consecutive_failures,
    COUNT(CASE WHEN total_deliveries > 0 THEN 1 END) as webhooks_with_activity
FROM pggit.webhook_health_metrics;

-- Dashboard performance summary (last 24 hours)
CREATE OR REPLACE VIEW pggit_analytics.v_performance_summary_24h AS
SELECT
    COUNT(DISTINCT webhook_id) as active_webhooks,
    SUM(count_total) as total_deliveries,
    SUM(count_success) as successful_deliveries,
    SUM(count_failure) as failed_deliveries,
    ROUND(100.0 * SUM(count_success) / NULLIF(SUM(count_total), 0), 2) as success_rate_percent,
    ROUND(AVG(p99_latency_ms), 2) as avg_p99_latency_ms,
    ROUND(MIN(p50_latency_ms), 2) as min_p50_latency_ms,
    ROUND(MAX(p99_latency_ms), 2) as max_p99_latency_ms,
    SUM(backpressure_events) as total_backpressure_events,
    SUM(rate_limit_hits) as total_rate_limit_hits
FROM pggit_analytics.metrics_1hour
WHERE bucket_time > CURRENT_TIMESTAMP - INTERVAL '24 hours';

-- Real-time anomalies (current issues)
CREATE OR REPLACE VIEW pggit_analytics.v_active_anomalies AS
SELECT
    wh.webhook_id,
    wh.health_status,
    wh.consecutive_failures,
    ROUND(100.0 * wh.successful_deliveries / NULLIF(wh.total_deliveries, 0), 2) as success_rate_percent,
    wh.avg_response_time_ms,
    CASE
        WHEN wh.consecutive_failures >= 5 THEN 'CRITICAL - Circuit Breaker Open'
        WHEN wh.health_status = 'unavailable' THEN 'CRITICAL - Webhook Unavailable'
        WHEN wh.health_status = 'degraded' THEN 'WARNING - Degraded Performance'
        ELSE 'INFO - Healthy'
    END as status_message,
    wh.last_check_at,
    wh.last_failure_at
FROM pggit.webhook_health_metrics wh
WHERE wh.health_status != 'healthy' OR wh.consecutive_failures > 0
ORDER BY wh.consecutive_failures DESC, wh.last_failure_at DESC;

-- Top performing webhooks
CREATE OR REPLACE VIEW pggit_analytics.v_top_webhooks AS
SELECT
    webhook_id,
    health_status,
    total_deliveries,
    successful_deliveries,
    ROUND(100.0 * successful_deliveries / NULLIF(total_deliveries, 0), 2) as success_rate_percent,
    ROUND(avg_response_time_ms, 2) as avg_response_ms,
    consecutive_failures,
    last_failure_at
FROM pggit.webhook_health_metrics
WHERE total_deliveries > 0
ORDER BY total_deliveries DESC, avg_response_time_ms ASC
LIMIT 10;

-- Queue depth trend (last 1 hour)
CREATE OR REPLACE VIEW pggit_analytics.v_queue_trend_1h AS
SELECT
    bucket_time,
    SUM(queue_depth_max) as max_queue_depth,
    SUM(queue_depth_avg) as avg_queue_depth,
    SUM(queue_depth_min) as min_queue_depth,
    COUNT(DISTINCT webhook_id) as webhooks_in_queue
FROM pggit_analytics.metrics_1min
WHERE bucket_time > CURRENT_TIMESTAMP - INTERVAL '1 hour'
GROUP BY bucket_time
ORDER BY bucket_time DESC;

-- ============================================================================
-- 6. DASHBOARD DATA AGGREGATION FUNCTION
-- ============================================================================

-- Main dashboard data compilation (used for initial page load)
CREATE OR REPLACE FUNCTION pggit_analytics.get_full_dashboard_data()
RETURNS TABLE (
    overview JSONB,
    performance JSONB,
    webhooks JSONB,
    anomalies JSONB,
    queue_trend JSONB,
    generated_at TIMESTAMP
) AS $$
DECLARE
    v_overview JSONB;
    v_performance JSONB;
    v_webhooks JSONB;
    v_anomalies JSONB;
    v_queue_trend JSONB;
BEGIN
    -- Get overview
    SELECT jsonb_build_object(
        'total_deliveries', total_deliveries,
        'successful_deliveries', successful_deliveries,
        'failed_deliveries', failed_deliveries,
        'success_rate_percent', success_rate_percent,
        'current_queue_depth', current_queue_depth,
        'active_webhooks', active_webhooks,
        'avg_p99_latency_ms', avg_p99_latency_ms,
        'webhooks_unhealthy', webhooks_unhealthy,
        'circuit_breakers_open', circuit_breakers_open
    ) INTO v_overview
    FROM pggit_analytics.get_overview_metrics(5);

    -- Get performance summary
    SELECT jsonb_build_object(
        'active_webhooks', active_webhooks,
        'total_deliveries', total_deliveries,
        'successful_deliveries', successful_deliveries,
        'failed_deliveries', failed_deliveries,
        'success_rate_percent', success_rate_percent,
        'avg_p99_latency_ms', avg_p99_latency_ms,
        'total_backpressure_events', total_backpressure_events,
        'total_rate_limit_hits', total_rate_limit_hits
    ) INTO v_performance
    FROM pggit_analytics.v_performance_summary_24h;

    -- Get top webhooks
    SELECT jsonb_agg(
        jsonb_build_object(
            'webhook_id', webhook_id,
            'health_status', health_status,
            'total_deliveries', total_deliveries,
            'success_rate_percent', success_rate_percent,
            'avg_response_ms', avg_response_ms
        )
    ) INTO v_webhooks
    FROM pggit_analytics.v_top_webhooks;

    -- Get active anomalies
    SELECT jsonb_agg(
        jsonb_build_object(
            'webhook_id', webhook_id,
            'health_status', health_status,
            'consecutive_failures', consecutive_failures,
            'status_message', status_message,
            'last_failure_time', last_failure_time
        )
    ) INTO v_anomalies
    FROM pggit_analytics.v_active_anomalies
    LIMIT 10;

    -- Get queue trend
    SELECT jsonb_agg(
        jsonb_build_object(
            'bucket_time', bucket_time,
            'max_queue_depth', max_queue_depth,
            'avg_queue_depth', avg_queue_depth,
            'webhooks_in_queue', webhooks_in_queue
        )
    ) INTO v_queue_trend
    FROM pggit_analytics.v_queue_trend_1h;

    RETURN QUERY SELECT
        v_overview,
        v_performance,
        COALESCE(v_webhooks, '[]'::JSONB),
        COALESCE(v_anomalies, '[]'::JSONB),
        COALESCE(v_queue_trend, '[]'::JSONB),
        CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- INITIALIZATION & SEEDING
-- ============================================================================

-- Initialize analytics schema for tracking
CREATE OR REPLACE FUNCTION pggit_analytics.initialize_analytics()
RETURNS TABLE (
    section TEXT,
    status TEXT
) AS $$
BEGIN
    -- Clean old data from metrics_1min (>7 days)
    DELETE FROM pggit_analytics.metrics_1min
    WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '7 days';

    RETURN QUERY SELECT 'Cleanup', 'Removed metrics older than 7 days'::TEXT;

    -- Clean old data from metrics_5min (>30 days)
    DELETE FROM pggit_analytics.metrics_5min
    WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '30 days';

    RETURN QUERY SELECT 'Cleanup', 'Removed 5min metrics older than 30 days'::TEXT;

    -- Clean old data from metrics_1hour (>90 days)
    DELETE FROM pggit_analytics.metrics_1hour
    WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '90 days';

    RETURN QUERY SELECT 'Cleanup', 'Removed hourly metrics older than 90 days'::TEXT;

    -- Clean expired cache entries
    DELETE FROM pggit_analytics.dashboard_cache
    WHERE expires_at < CURRENT_TIMESTAMP;

    RETURN QUERY SELECT 'Cache', 'Cleaned expired cache entries'::TEXT;

    -- Clean old event log (>30 days)
    DELETE FROM pggit_analytics.event_log
    WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '30 days';

    RETURN QUERY SELECT 'EventLog', 'Cleaned events older than 30 days'::TEXT;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- GRANTS & PERMISSIONS
-- ============================================================================

GRANT USAGE ON SCHEMA pggit_analytics TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA pggit_analytics TO postgres;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pggit_analytics TO postgres;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA pggit_analytics TO postgres;
