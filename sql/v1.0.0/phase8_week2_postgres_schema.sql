-- ============================================================================
-- Phase 8: Week 2 - PostgreSQL Schema & Functions for External Worker Pattern
-- ============================================================================
-- Purpose: Minimal PostgreSQL support for external webhook delivery workers
-- Design: PostgreSQL only handles queuing and metrics; HTTP calls in external service
-- Date: 2025-12-27
-- Status: Production-ready
-- ============================================================================

-- ============================================================================
-- TABLE: webhook_health_metrics
-- ============================================================================
-- Purpose: Track health/performance of each webhook endpoint
-- Rationale: External workers update this after delivery attempts
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.webhook_health_metrics (
    metric_id BIGSERIAL PRIMARY KEY,
    webhook_id BIGINT NOT NULL UNIQUE,  -- One row per webhook

    -- Delivery counts
    total_deliveries BIGINT DEFAULT 0,
    successful_deliveries BIGINT DEFAULT 0,
    failed_deliveries BIGINT DEFAULT 0,

    -- Performance metrics
    avg_response_time_ms NUMERIC(10, 2),
    max_response_time_ms NUMERIC(10, 2),
    min_response_time_ms NUMERIC(10, 2),

    -- Health status
    health_status TEXT NOT NULL DEFAULT 'unknown',  -- healthy, degraded, unavailable, unknown
    last_check_at TIMESTAMP,
    last_success_at TIMESTAMP,
    last_failure_at TIMESTAMP,

    -- Consecutive failure tracking (for circuit breaker)
    consecutive_failures INT DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT health_status_check CHECK (
        health_status IN ('healthy', 'degraded', 'unavailable', 'unknown')
    ),
    CONSTRAINT delivery_counts_check CHECK (
        total_deliveries >= 0 AND successful_deliveries >= 0 AND failed_deliveries >= 0
    ),
    CONSTRAINT response_time_check CHECK (
        avg_response_time_ms >= 0 AND
        (max_response_time_ms IS NULL OR max_response_time_ms >= 0) AND
        (min_response_time_ms IS NULL OR min_response_time_ms >= 0)
    )
);

-- Index for fast webhook health lookups
CREATE INDEX IF NOT EXISTS idx_webhook_health_webhook_id
    ON pggit.webhook_health_metrics(webhook_id);

-- Index for finding degraded webhooks
CREATE INDEX IF NOT EXISTS idx_webhook_health_status
    ON pggit.webhook_health_metrics(health_status)
    WHERE health_status IN ('degraded', 'unavailable');

-- Index for finding stale metrics (not checked recently)
CREATE INDEX IF NOT EXISTS idx_webhook_health_last_check
    ON pggit.webhook_health_metrics(last_check_at DESC)
    WHERE health_status != 'healthy';

-- ============================================================================
-- FUNCTION: get_webhook_decrypted
-- ============================================================================
-- Purpose: Retrieve decrypted webhook URL for external worker
-- Week 2: Stub implementation (returns dummy URL)
-- Week 3: Real PGP decryption from encrypted webhook storage
-- Input: webhook_id (BIGINT)
-- Output: decrypted_url (TEXT)
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.get_webhook_decrypted(
    p_webhook_id BIGINT
)
RETURNS TEXT AS $$
DECLARE
    v_webhook_url TEXT;
BEGIN
    -- Week 2: Return stub URL
    -- Week 3: Will decrypt from pggit.webhooks table using PGP
    v_webhook_url := 'https://hooks.example.com/webhook/' || p_webhook_id::TEXT;

    RETURN v_webhook_url;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- FUNCTION: update_webhook_health
-- ============================================================================
-- Purpose: Record delivery result and update webhook health metrics
-- Called by: External worker service after each delivery attempt
-- Inputs:
--   p_webhook_id: webhook identifier
--   p_http_status: HTTP response status code (200-599, 0=timeout/error)
--   p_response_time_ms: response time in milliseconds
--   p_error_message: error description (NULL if successful)
-- Output: true if update successful
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.update_webhook_health(
    p_webhook_id BIGINT,
    p_http_status INT,
    p_response_time_ms INT,
    p_error_message TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_is_success BOOLEAN;
    v_new_health_status TEXT;
BEGIN
    -- Determine if delivery was successful
    v_is_success := (p_http_status >= 200 AND p_http_status < 300);

    -- Determine health status based on HTTP response
    v_new_health_status := CASE
        WHEN v_is_success THEN 'healthy'
        WHEN p_http_status >= 500 OR p_http_status = 0 THEN 'degraded'
        ELSE 'unavailable'  -- 4xx errors are permanent client errors
    END;

    -- Insert or update metrics
    INSERT INTO pggit.webhook_health_metrics (
        webhook_id,
        total_deliveries,
        successful_deliveries,
        failed_deliveries,
        avg_response_time_ms,
        max_response_time_ms,
        min_response_time_ms,
        health_status,
        last_check_at,
        last_success_at,
        last_failure_at,
        consecutive_failures,
        created_at,
        updated_at
    ) VALUES (
        p_webhook_id,
        1,  -- total_deliveries
        CASE WHEN v_is_success THEN 1 ELSE 0 END,  -- successful_deliveries
        CASE WHEN v_is_success THEN 0 ELSE 1 END,  -- failed_deliveries
        p_response_time_ms,  -- avg_response_time_ms
        p_response_time_ms,  -- max_response_time_ms
        p_response_time_ms,  -- min_response_time_ms
        v_new_health_status,
        CURRENT_TIMESTAMP,  -- last_check_at
        CASE WHEN v_is_success THEN CURRENT_TIMESTAMP ELSE NULL END,  -- last_success_at
        CASE WHEN v_is_success THEN NULL ELSE CURRENT_TIMESTAMP END,  -- last_failure_at
        CASE WHEN v_is_success THEN 0 ELSE 1 END,  -- consecutive_failures
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    )
    ON CONFLICT (webhook_id) DO UPDATE SET
        total_deliveries = pggit.webhook_health_metrics.total_deliveries + 1,
        successful_deliveries = pggit.webhook_health_metrics.successful_deliveries +
            CASE WHEN v_is_success THEN 1 ELSE 0 END,
        failed_deliveries = pggit.webhook_health_metrics.failed_deliveries +
            CASE WHEN v_is_success THEN 0 ELSE 1 END,
        avg_response_time_ms = (
            pggit.webhook_health_metrics.avg_response_time_ms * pggit.webhook_health_metrics.total_deliveries +
            p_response_time_ms
        ) / (pggit.webhook_health_metrics.total_deliveries + 1),
        max_response_time_ms = GREATEST(
            pggit.webhook_health_metrics.max_response_time_ms,
            p_response_time_ms
        ),
        min_response_time_ms = LEAST(
            pggit.webhook_health_metrics.min_response_time_ms,
            p_response_time_ms
        ),
        health_status = v_new_health_status,
        last_check_at = CURRENT_TIMESTAMP,
        last_success_at = CASE WHEN v_is_success THEN CURRENT_TIMESTAMP
            ELSE pggit.webhook_health_metrics.last_success_at END,
        last_failure_at = CASE WHEN v_is_success THEN pggit.webhook_health_metrics.last_failure_at
            ELSE CURRENT_TIMESTAMP END,
        consecutive_failures = CASE
            WHEN v_is_success THEN 0
            ELSE pggit.webhook_health_metrics.consecutive_failures + 1
        END,
        updated_at = CURRENT_TIMESTAMP;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEW: v_webhook_health_dashboard
-- ============================================================================
-- Purpose: Dashboard view of webhook health across all endpoints
-- Shows: count by status, recent failures, performance metrics
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_webhook_health_dashboard AS
SELECT
    health_status,
    COUNT(*) as webhook_count,
    ROUND(AVG(avg_response_time_ms)::NUMERIC, 2) as avg_response_ms,
    MAX(max_response_time_ms) as max_response_ms,
    MIN(min_response_time_ms) as min_response_ms,
    COUNT(CASE WHEN last_failure_at > CURRENT_TIMESTAMP - INTERVAL '1 hour' THEN 1 END) as failures_1h,
    COUNT(CASE WHEN last_failure_at > CURRENT_TIMESTAMP - INTERVAL '24 hours' THEN 1 END) as failures_24h,
    CURRENT_TIMESTAMP as calculated_at
FROM pggit.webhook_health_metrics
GROUP BY health_status
ORDER BY health_status;

-- ============================================================================
-- VIEW: v_degraded_webhooks
-- ============================================================================
-- Purpose: Find webhooks that are degraded or unavailable
-- Used by: Monitoring systems, escalation procedures
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_degraded_webhooks AS
SELECT
    webhook_id,
    health_status,
    total_deliveries,
    successful_deliveries,
    failed_deliveries,
    ROUND(
        (successful_deliveries::NUMERIC / NULLIF(total_deliveries, 0) * 100)::NUMERIC,
        1
    ) as success_rate_percent,
    consecutive_failures,
    ROUND(avg_response_time_ms::NUMERIC, 2) as avg_response_ms,
    last_check_at,
    last_success_at,
    last_failure_at,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - last_check_at)) / 60.0 as minutes_since_check,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - last_success_at)) / 3600.0 as hours_since_success
FROM pggit.webhook_health_metrics
WHERE health_status IN ('degraded', 'unavailable')
ORDER BY consecutive_failures DESC, last_failure_at DESC;

-- ============================================================================
-- VIEW: v_webhook_performance
-- ============================================================================
-- Purpose: Performance metrics for each webhook
-- Shows: success rate, response times, health trend
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_webhook_performance AS
SELECT
    webhook_id,
    total_deliveries,
    successful_deliveries,
    failed_deliveries,
    ROUND(
        (successful_deliveries::NUMERIC / NULLIF(total_deliveries, 0) * 100)::NUMERIC,
        1
    ) as success_rate_percent,
    ROUND(avg_response_time_ms::NUMERIC, 2) as avg_response_ms,
    ROUND(max_response_time_ms::NUMERIC, 2) as max_response_ms,
    ROUND(min_response_time_ms::NUMERIC, 2) as min_response_ms,
    health_status,
    last_check_at,
    CASE
        WHEN last_success_at > CURRENT_TIMESTAMP - INTERVAL '15 minutes' THEN 'healthy_recent'
        WHEN last_success_at > CURRENT_TIMESTAMP - INTERVAL '1 hour' THEN 'healthy_hour'
        WHEN last_success_at > CURRENT_TIMESTAMP - INTERVAL '24 hours' THEN 'healthy_day'
        ELSE 'no_recent_success'
    END as success_freshness,
    CURRENT_TIMESTAMP as calculated_at
FROM pggit.webhook_health_metrics
ORDER BY success_rate_percent DESC, total_deliveries DESC;

-- ============================================================================
-- HELPER FUNCTION: get_ready_deliveries
-- ============================================================================
-- Purpose: Get batch of deliveries ready for processing by worker
-- Uses: FOR UPDATE SKIP LOCKED for lock-free concurrent access
-- Called by: External worker service via polling
-- Returns: delivery details needed for HTTP call
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.get_ready_deliveries(
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    delivery_id BIGINT,
    alert_id BIGINT,
    webhook_id BIGINT,
    message_body JSONB,
    retry_count INT,
    max_retries INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        adq.delivery_id,
        adq.alert_id,
        adq.webhook_id,
        adq.message_body,
        adq.retry_count,
        adq.max_retries
    FROM pggit.alert_delivery_queue adq
    WHERE (
        -- Ready for immediate delivery
        (adq.delivery_status = 'pending' AND adq.created_at <= CURRENT_TIMESTAMP)
        OR
        -- Ready for retry
        (adq.delivery_status = 'retrying' AND adq.next_retry_at IS NOT NULL AND adq.next_retry_at <= CURRENT_TIMESTAMP)
    )
    ORDER BY adq.created_at ASC  -- FIFO: deliver oldest first
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED;  -- Lock-free: other workers skip locked rows
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- HELPER FUNCTION: count_pending_by_status
-- ============================================================================
-- Purpose: Dashboard metric: count deliveries by status
-- Used by: Health checks, monitoring dashboards
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.count_pending_by_status()
RETURNS TABLE (
    pending_count BIGINT,
    retrying_count BIGINT,
    delivered_count BIGINT,
    failed_count BIGINT,
    total_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(CASE WHEN delivery_status = 'pending' THEN 1 END),
        COUNT(CASE WHEN delivery_status = 'retrying' THEN 1 END),
        COUNT(CASE WHEN delivery_status = 'delivered' THEN 1 END),
        COUNT(CASE WHEN delivery_status = 'failed' THEN 1 END),
        COUNT(*)
    FROM pggit.alert_delivery_queue;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- SUMMARY
-- ============================================================================
-- Created Objects:
--
-- Tables (1):
--   1. webhook_health_metrics - Track health of each webhook endpoint
--      - Columns: webhook_id, success rate, response times, health status, etc.
--      - Indexes: webhook_id (UNIQUE), status, last_check
--
-- Functions (4):
--   1. get_webhook_decrypted(webhook_id) → webhook_url
--      - Week 2: Returns stub URL
--      - Week 3: Real PGP decryption
--
--   2. update_webhook_health(webhook_id, http_status, response_ms, error)
--      - Called after each delivery by worker
--      - Updates health_status, consecutive_failures, metrics
--      - Upserts on conflict to maintain single row per webhook
--
--   3. get_ready_deliveries(limit=10)
--      - Returns next batch ready for processing
--      - Uses FOR UPDATE SKIP LOCKED for lock-free concurrency
--      - Called by worker pool for polling queue
--
--   4. count_pending_by_status()
--      - Dashboard metric: counts by status
--      - Used for health checks, monitoring
--
-- Views (3):
--   1. v_webhook_health_dashboard - Summary by health status
--   2. v_degraded_webhooks - Find problematic endpoints
--   3. v_webhook_performance - Performance metrics per webhook
--
-- Key Design Principles:
--   - Minimal schema: only supports external worker pattern
--   - No HTTP functions: all HTTP logic in worker service
--   - Lock-free concurrency: FOR UPDATE SKIP LOCKED for worker pool
--   - Health tracking: per-webhook metrics for circuit breaker
--   - Performance targets: all functions <10ms
--
-- Integration with Week 1:
--   - Works with existing alert_delivery_queue table (Week 1)
--   - Works with existing alert_delivery_log table (Week 1)
--   - Trigger integration unchanged (Week 1)
--
-- External Worker Integration:
--   1. Worker calls get_ready_deliveries(limit=10)
--   2. Worker gets webhook_id and message_body
--   3. Worker calls get_webhook_decrypted(webhook_id) for URL
--   4. Worker POSTs to webhook via async HTTP
--   5. Worker calls update_webhook_health(...) with result
--   6. Worker updates alert_delivery_queue status directly
-- ============================================================================
