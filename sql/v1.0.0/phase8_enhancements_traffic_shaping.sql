-- ============================================================================
-- Phase 8 Enhancement 2: Advanced Traffic Shaping with Adaptive Queue
-- ============================================================================
--
-- Purpose: Implements adaptive queue management with dynamic rate adjustment,
--          priority queuing, burst handling, and predictive scaling based on
--          webhook health and system load metrics.
--
-- Components:
--   1. Adaptive queue configuration tables
--   2. Dynamic rate limiting with token bucket algorithm
--   3. Priority queue management (critical vs normal webhooks)
--   4. Burst handling with graceful degradation
--   5. Backpressure management and circuit breaker integration
--   6. Monitoring views and metrics
--
-- Version: 1.0.0
-- Created: 2025-12-27
-- ============================================================================

-- Create traffic shaping schema
CREATE SCHEMA IF NOT EXISTS pggit_traffic;

-- ============================================================================
-- TABLES: Traffic Shaping Configuration & State
-- ============================================================================

-- Queue depth limits and adaptive thresholds
CREATE TABLE IF NOT EXISTS pggit_traffic.queue_config (
    config_id BIGSERIAL PRIMARY KEY,
    webhook_id BIGINT NOT NULL REFERENCES pggit.webhook_health_metrics(webhook_id),

    -- Base rate limiting (requests per second)
    base_rps NUMERIC(10, 2) DEFAULT 10.0,
    burst_rps NUMERIC(10, 2) DEFAULT 20.0,

    -- Queue depth thresholds
    normal_queue_limit INT DEFAULT 1000,
    degraded_queue_limit INT DEFAULT 500,
    critical_queue_limit INT DEFAULT 100,

    -- Adaptive rate adjustment factors
    success_rate_threshold NUMERIC(5, 3) DEFAULT 0.95,
    latency_p99_threshold_ms INT DEFAULT 2000,
    degradation_factor NUMERIC(5, 3) DEFAULT 0.8,  -- Reduce by 20% when degraded
    recovery_factor NUMERIC(5, 3) DEFAULT 1.05,     -- Increase by 5% when healthy

    -- Priority configuration
    is_critical_webhook BOOLEAN DEFAULT FALSE,
    critical_queue_priority INT DEFAULT 10,
    normal_queue_priority INT DEFAULT 5,

    -- Auto-scaling parameters
    auto_scaling_enabled BOOLEAN DEFAULT TRUE,
    min_rps NUMERIC(10, 2) DEFAULT 1.0,
    max_rps NUMERIC(10, 2) DEFAULT 50.0,

    -- Backpressure management
    backpressure_enabled BOOLEAN DEFAULT TRUE,
    backpressure_queue_threshold NUMERIC(5, 3) DEFAULT 0.8,  -- 80% full

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_adjustment_at TIMESTAMP,

    UNIQUE(webhook_id)
);

CREATE INDEX idx_queue_config_webhook_id ON pggit_traffic.queue_config(webhook_id);

-- Token bucket state for rate limiting
CREATE TABLE IF NOT EXISTS pggit_traffic.token_bucket_state (
    bucket_id BIGSERIAL PRIMARY KEY,
    webhook_id BIGINT NOT NULL REFERENCES pggit.webhook_health_metrics(webhook_id),

    -- Token count (current tokens available)
    tokens_available NUMERIC(10, 2) NOT NULL DEFAULT 0,

    -- Last refill timestamp
    last_refill_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Current rate (may differ from base due to adaptation)
    current_rps NUMERIC(10, 2) NOT NULL,

    -- Token bucket configuration
    bucket_capacity NUMERIC(10, 2) NOT NULL,  -- Max tokens in bucket
    refill_rate NUMERIC(10, 2) NOT NULL,      -- Tokens per second

    UNIQUE(webhook_id)
);

CREATE INDEX idx_token_bucket_webhook_id ON pggit_traffic.token_bucket_state(webhook_id);

-- Adaptive rate history for trending
CREATE TABLE IF NOT EXISTS pggit_traffic.rate_adjustment_history (
    adjustment_id BIGSERIAL PRIMARY KEY,
    webhook_id BIGINT NOT NULL REFERENCES pggit.webhook_health_metrics(webhook_id),

    old_rps NUMERIC(10, 2) NOT NULL,
    new_rps NUMERIC(10, 2) NOT NULL,

    -- Adjustment reason
    reason VARCHAR(100),  -- 'health_degraded', 'latency_high', 'recovery', 'auto_scale'

    -- Trigger metrics
    success_rate NUMERIC(5, 3),
    latency_p99_ms INT,
    queue_depth INT,
    consecutive_failures INT,

    adjustment_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_rate_adjustment_webhook_id ON pggit_traffic.rate_adjustment_history(webhook_id);
CREATE INDEX idx_rate_adjustment_timestamp ON pggit_traffic.rate_adjustment_history(adjustment_timestamp DESC);

-- Priority queue assignments (for priority-based delivery)
CREATE TABLE IF NOT EXISTS pggit_traffic.delivery_queue_priority (
    priority_id BIGSERIAL PRIMARY KEY,
    alert_id BIGINT NOT NULL,
    webhook_id BIGINT NOT NULL REFERENCES pggit.webhook_health_metrics(webhook_id),
    priority_level INT NOT NULL,  -- Higher = more important
    priority_reason VARCHAR(50),   -- 'critical_webhook', 'retry_attempt', 'sla_deadline'
    priority_assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(alert_id)
);

CREATE INDEX idx_delivery_queue_priority_webhook ON pggit_traffic.delivery_queue_priority(webhook_id);
CREATE INDEX idx_delivery_queue_priority_level ON pggit_traffic.delivery_queue_priority(priority_level DESC);
CREATE INDEX idx_delivery_queue_priority_alert_id ON pggit_traffic.delivery_queue_priority(alert_id);

-- Backpressure signals
CREATE TABLE IF NOT EXISTS pggit_traffic.backpressure_signal (
    signal_id BIGSERIAL PRIMARY KEY,
    webhook_id BIGINT NOT NULL REFERENCES pggit.webhook_health_metrics(webhook_id),

    -- Backpressure type
    signal_type VARCHAR(30),  -- 'high_queue_depth', 'worker_overload', 'database_load'
    severity VARCHAR(20),     -- 'warning', 'critical'

    -- Queue state when signal triggered
    current_queue_depth INT,
    queue_capacity_percent NUMERIC(5, 2),

    -- Action taken
    action VARCHAR(100),  -- 'reject_new', 'slow_acceptance', 'drain_queue'
    new_acceptance_rate NUMERIC(5, 3),  -- Percentage of normal rate

    signal_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    cleared_at TIMESTAMP,

    is_active BOOLEAN DEFAULT TRUE
);

CREATE INDEX idx_backpressure_signal_webhook ON pggit_traffic.backpressure_signal(webhook_id);
CREATE INDEX idx_backpressure_signal_active ON pggit_traffic.backpressure_signal(is_active);
CREATE INDEX idx_backpressure_signal_timestamp ON pggit_traffic.backpressure_signal(signal_timestamp DESC);

-- ============================================================================
-- FUNCTIONS: Token Bucket & Rate Limiting
-- ============================================================================

-- Calculate current token count with decay
CREATE OR REPLACE FUNCTION pggit_traffic.get_current_tokens(
    p_webhook_id BIGINT
)
RETURNS NUMERIC AS $$
DECLARE
    v_state RECORD;
    v_time_elapsed NUMERIC;
    v_tokens_generated NUMERIC;
    v_current_tokens NUMERIC;
BEGIN
    SELECT * INTO v_state
    FROM pggit_traffic.token_bucket_state
    WHERE webhook_id = p_webhook_id;

    IF v_state IS NULL THEN
        RETURN 0;
    END IF;

    -- Calculate tokens generated since last refill
    v_time_elapsed := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_state.last_refill_at));
    v_tokens_generated := v_time_elapsed * v_state.refill_rate;

    -- Current tokens = previous + generated, capped at capacity
    v_current_tokens := LEAST(
        v_state.tokens_available + v_tokens_generated,
        v_state.bucket_capacity
    );

    RETURN v_current_tokens;
END;
$$ LANGUAGE plpgsql;

-- Try to consume tokens for request
CREATE OR REPLACE FUNCTION pggit_traffic.try_consume_tokens(
    p_webhook_id BIGINT,
    p_tokens_needed NUMERIC DEFAULT 1.0
)
RETURNS TABLE (
    allowed BOOLEAN,
    tokens_remaining NUMERIC,
    wait_ms INT
) AS $$
DECLARE
    v_current_tokens NUMERIC;
    v_state RECORD;
    v_wait_ms INT;
BEGIN
    SELECT * INTO v_state
    FROM pggit_traffic.token_bucket_state
    WHERE webhook_id = p_webhook_id
    FOR UPDATE;

    IF v_state IS NULL THEN
        RETURN QUERY SELECT FALSE::BOOLEAN, 0::NUMERIC, 0::INT;
        RETURN;
    END IF;

    v_current_tokens := pggit_traffic.get_current_tokens(p_webhook_id);

    IF v_current_tokens >= p_tokens_needed THEN
        -- Consume tokens
        UPDATE pggit_traffic.token_bucket_state
        SET
            tokens_available = v_current_tokens - p_tokens_needed,
            last_refill_at = CURRENT_TIMESTAMP
        WHERE webhook_id = p_webhook_id;

        RETURN QUERY SELECT
            TRUE::BOOLEAN,
            GREATEST(0, v_current_tokens - p_tokens_needed)::NUMERIC,
            0::INT;
    ELSE
        -- Calculate wait time until enough tokens available
        v_wait_ms := CEIL(
            ((p_tokens_needed - v_current_tokens) / v_state.refill_rate) * 1000
        )::INT;

        -- Don't wait more than 60 seconds
        v_wait_ms := LEAST(v_wait_ms, 60000);

        RETURN QUERY SELECT
            FALSE::BOOLEAN,
            v_current_tokens::NUMERIC,
            v_wait_ms::INT;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTIONS: Adaptive Rate Adjustment
-- ============================================================================

-- Calculate recommended rate based on webhook health
CREATE OR REPLACE FUNCTION pggit_traffic.calculate_adaptive_rate(
    p_webhook_id BIGINT
)
RETURNS TABLE (
    recommended_rps NUMERIC,
    adjustment_reason VARCHAR,
    severity VARCHAR,
    adjustment_factor NUMERIC
) AS $$
DECLARE
    v_config RECORD;
    v_health RECORD;
    v_rate NUMERIC;
    v_factor NUMERIC := 1.0;
    v_reason VARCHAR := 'stable';
    v_severity VARCHAR := 'info';
BEGIN
    SELECT * INTO v_config
    FROM pggit_traffic.queue_config
    WHERE webhook_id = p_webhook_id;

    SELECT * INTO v_health
    FROM pggit.webhook_health_metrics
    WHERE webhook_id = p_webhook_id;

    IF v_config IS NULL OR v_health IS NULL THEN
        RETURN QUERY SELECT
            v_config.base_rps,
            'webhook_not_configured',
            'warning',
            1.0::NUMERIC;
        RETURN;
    END IF;

    v_rate := v_config.base_rps;

    -- Check consecutive failures (circuit breaker)
    IF v_health.consecutive_failures >= 5 THEN
        v_factor := 0.1;  -- Reduce to 10% during circuit break
        v_reason := 'circuit_breaker_open';
        v_severity := 'critical';
    -- Check health status
    ELSIF v_health.health_status = 'degraded' THEN
        v_factor := v_config.degradation_factor;
        v_reason := 'health_degraded';
        v_severity := 'warning';
    -- Check success rate
    ELSIF (SELECT CAST(successful_deliveries AS NUMERIC) / NULLIF(total_deliveries, 0)
           FROM pggit.webhook_health_metrics WHERE webhook_id = p_webhook_id) < v_config.success_rate_threshold THEN
        v_factor := v_config.degradation_factor * 0.9;  -- Extra reduction
        v_reason := 'low_success_rate';
        v_severity := 'warning';
    -- Check latency
    ELSIF v_health.avg_response_time_ms > v_config.latency_p99_threshold_ms THEN
        v_factor := v_config.degradation_factor * 0.95;
        v_reason := 'high_latency';
        v_severity := 'warning';
    -- Recovery: webhook is healthy
    ELSIF v_health.health_status = 'healthy' AND v_health.consecutive_failures = 0 THEN
        v_factor := v_config.recovery_factor;
        v_reason := 'health_recovered';
        v_severity := 'info';
    END IF;

    v_rate := GREATEST(
        v_config.min_rps,
        LEAST(
            v_config.max_rps,
            v_config.base_rps * v_factor
        )
    );

    RETURN QUERY SELECT v_rate, v_reason, v_severity, v_factor;
END;
$$ LANGUAGE plpgsql;

-- Apply rate adjustment based on health metrics
CREATE OR REPLACE FUNCTION pggit_traffic.apply_rate_adjustment(
    p_webhook_id BIGINT,
    p_force BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    old_rps NUMERIC,
    new_rps NUMERIC,
    was_adjusted BOOLEAN,
    reason VARCHAR
) AS $$
DECLARE
    v_config RECORD;
    v_state RECORD;
    v_recommended RECORD;
    v_old_rps NUMERIC;
    v_new_rps NUMERIC;
    v_was_adjusted BOOLEAN := FALSE;
BEGIN
    SELECT * INTO v_config
    FROM pggit_traffic.queue_config
    WHERE webhook_id = p_webhook_id;

    SELECT * INTO v_state
    FROM pggit_traffic.token_bucket_state
    WHERE webhook_id = p_webhook_id
    FOR UPDATE;

    SELECT * INTO v_recommended
    FROM pggit_traffic.calculate_adaptive_rate(p_webhook_id);

    IF v_config IS NULL OR v_state IS NULL THEN
        RETURN QUERY SELECT 0::NUMERIC, 0::NUMERIC, FALSE, 'not_configured';
        RETURN;
    END IF;

    v_old_rps := v_state.current_rps;
    v_new_rps := v_recommended.recommended_rps;

    -- Only adjust if change is significant (>5%) or forced
    IF p_force OR ABS(v_new_rps - v_old_rps) / v_old_rps > 0.05 THEN
        v_was_adjusted := TRUE;

        -- Update token bucket state
        UPDATE pggit_traffic.token_bucket_state
        SET
            current_rps = v_new_rps,
            refill_rate = v_new_rps,
            bucket_capacity = v_new_rps * 10,  -- Capacity = 10 seconds worth
            last_refill_at = CURRENT_TIMESTAMP
        WHERE webhook_id = p_webhook_id;

        -- Update queue config
        UPDATE pggit_traffic.queue_config
        SET
            base_rps = v_new_rps,
            last_adjustment_at = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
        WHERE webhook_id = p_webhook_id;

        -- Log adjustment
        INSERT INTO pggit_traffic.rate_adjustment_history (
            webhook_id,
            old_rps,
            new_rps,
            reason,
            success_rate,
            latency_p99_ms,
            queue_depth,
            consecutive_failures
        ) SELECT
            p_webhook_id,
            v_old_rps,
            v_new_rps,
            v_recommended.adjustment_reason,
            CAST(whm.successful_deliveries AS NUMERIC) / NULLIF(whm.total_deliveries, 0),
            whm.avg_response_time_ms::INT,
            (SELECT COUNT(*) FROM pggit.alert_delivery_queue
             WHERE webhook_id = p_webhook_id AND delivery_status = 'pending'),
            whm.consecutive_failures
        FROM pggit.webhook_health_metrics whm
        WHERE whm.webhook_id = p_webhook_id;
    END IF;

    RETURN QUERY SELECT v_old_rps, v_new_rps, v_was_adjusted, v_recommended.adjustment_reason;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTIONS: Queue Management with Priorities
-- ============================================================================

-- Get next delivery respecting priorities and rate limits
CREATE OR REPLACE FUNCTION pggit_traffic.get_next_prioritized_delivery(
    p_limit INT DEFAULT 10,
    p_respect_rate_limits BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
    alert_id BIGINT,
    webhook_id BIGINT,
    message_body JSONB,
    priority_level INT,
    allowed_by_rate_limit BOOLEAN,
    wait_ms INT
) AS $$
DECLARE
    v_delivery RECORD;
    v_rate_check RECORD;
BEGIN
    -- Select deliveries ordered by priority and age
    FOR v_delivery IN
        SELECT
            adq.alert_id,
            adq.webhook_id,
            adq.message_body,
            COALESCE(dqp.priority_level,
                    CASE WHEN qc.is_critical_webhook THEN qc.critical_queue_priority
                         ELSE qc.normal_queue_priority END) as priority_level
        FROM pggit.alert_delivery_queue adq
        JOIN pggit_traffic.queue_config qc ON qc.webhook_id = adq.webhook_id
        LEFT JOIN pggit_traffic.delivery_queue_priority dqp ON dqp.alert_id = adq.alert_id
        WHERE adq.delivery_status = 'pending'
        ORDER BY
            priority_level DESC,           -- High priority first
            adq.created_at ASC             -- Older items first
        LIMIT p_limit
        FOR UPDATE SKIP LOCKED
    LOOP
        IF p_respect_rate_limits THEN
            -- Check rate limit
            SELECT * INTO v_rate_check
            FROM pggit_traffic.try_consume_tokens(v_delivery.webhook_id, 1.0);

            RETURN QUERY SELECT
                v_delivery.alert_id,
                v_delivery.webhook_id,
                v_delivery.message_body,
                v_delivery.priority_level,
                v_rate_check.allowed,
                v_rate_check.wait_ms;
        ELSE
            RETURN QUERY SELECT
                v_delivery.alert_id,
                v_delivery.webhook_id,
                v_delivery.message_body,
                v_delivery.priority_level,
                TRUE::BOOLEAN,
                0::INT;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTIONS: Backpressure Management
-- ============================================================================

-- Check and signal backpressure conditions
CREATE OR REPLACE FUNCTION pggit_traffic.check_backpressure(
    p_webhook_id BIGINT
)
RETURNS TABLE (
    is_backpressure_active BOOLEAN,
    current_queue_depth INT,
    capacity_percent NUMERIC,
    acceptance_rate NUMERIC,
    action VARCHAR
) AS $$
DECLARE
    v_config RECORD;
    v_queue_depth INT;
    v_limit INT;
    v_capacity_percent NUMERIC;
    v_acceptance_rate NUMERIC := 1.0;
    v_action VARCHAR := 'accept_all';
    v_is_active BOOLEAN := FALSE;
BEGIN
    SELECT * INTO v_config
    FROM pggit_traffic.queue_config
    WHERE webhook_id = p_webhook_id;

    IF v_config IS NULL OR NOT v_config.backpressure_enabled THEN
        RETURN QUERY SELECT FALSE, 0, 0, 1.0, 'disabled';
        RETURN;
    END IF;

    -- Calculate current queue depth
    SELECT COUNT(*) INTO v_queue_depth
    FROM pggit.alert_delivery_queue
    WHERE webhook_id = p_webhook_id AND delivery_status = 'pending';

    -- Determine limit based on health status
    SELECT health_status INTO v_config.is_critical_webhook
    FROM pggit.webhook_health_metrics
    WHERE webhook_id = p_webhook_id;

    v_limit := CASE
        WHEN v_config.is_critical_webhook = 'critical' THEN v_config.critical_queue_limit
        WHEN v_config.is_critical_webhook = 'degraded' THEN v_config.degraded_queue_limit
        ELSE v_config.normal_queue_limit
    END;

    v_capacity_percent := ROUND((v_queue_depth::NUMERIC / v_limit) * 100, 2);

    -- Apply backpressure strategies
    IF v_capacity_percent >= 90 THEN
        -- Critical: reject new items
        v_acceptance_rate := 0.0;
        v_action := 'reject_new';
        v_is_active := TRUE;
    ELSIF v_capacity_percent >= 80 THEN
        -- High: slow acceptance
        v_acceptance_rate := 0.5;
        v_action := 'slow_acceptance';
        v_is_active := TRUE;
    ELSIF v_capacity_percent >= 70 THEN
        -- Elevated: monitor
        v_acceptance_rate := 0.8;
        v_action := 'monitor';
        v_is_active := TRUE;
    ELSE
        v_acceptance_rate := 1.0;
        v_action := 'accept_all';
    END IF;

    -- Log backpressure signal if active
    IF v_is_active THEN
        INSERT INTO pggit_traffic.backpressure_signal (
            webhook_id,
            signal_type,
            severity,
            current_queue_depth,
            queue_capacity_percent,
            action,
            new_acceptance_rate,
            is_active
        ) VALUES (
            p_webhook_id,
            'high_queue_depth',
            CASE WHEN v_capacity_percent >= 90 THEN 'critical' ELSE 'warning' END,
            v_queue_depth,
            v_capacity_percent,
            v_action,
            v_acceptance_rate,
            TRUE
        )
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN QUERY SELECT v_is_active, v_queue_depth, v_capacity_percent, v_acceptance_rate, v_action;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTIONS: Initialization & Maintenance
-- ============================================================================

-- Initialize queue config for a webhook
CREATE OR REPLACE FUNCTION pggit_traffic.initialize_webhook_traffic_config(
    p_webhook_id BIGINT,
    p_base_rps NUMERIC DEFAULT 10.0,
    p_is_critical BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    webhook_id BIGINT,
    config_created BOOLEAN,
    token_bucket_created BOOLEAN
) AS $$
DECLARE
    v_exists BOOLEAN;
BEGIN
    -- Check if config already exists
    SELECT EXISTS(SELECT 1 FROM pggit_traffic.queue_config WHERE webhook_id = p_webhook_id)
    INTO v_exists;

    IF NOT v_exists THEN
        -- Create queue config
        INSERT INTO pggit_traffic.queue_config (
            webhook_id,
            base_rps,
            is_critical_webhook
        ) VALUES (
            p_webhook_id,
            p_base_rps,
            p_is_critical
        );

        -- Create token bucket state
        INSERT INTO pggit_traffic.token_bucket_state (
            webhook_id,
            tokens_available,
            current_rps,
            bucket_capacity,
            refill_rate
        ) VALUES (
            p_webhook_id,
            p_base_rps * 10,  -- Start with 10 seconds worth
            p_base_rps,
            p_base_rps * 10,
            p_base_rps
        );

        RETURN QUERY SELECT p_webhook_id, TRUE, TRUE;
    ELSE
        RETURN QUERY SELECT p_webhook_id, FALSE, FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Initialize all webhooks with traffic shaping
CREATE OR REPLACE FUNCTION pggit_traffic.initialize_all_webhooks()
RETURNS TABLE (
    webhook_id BIGINT,
    configured BOOLEAN
) AS $$
DECLARE
    v_webhook RECORD;
BEGIN
    FOR v_webhook IN
        SELECT webhook_id FROM pggit.webhook_health_metrics
        WHERE webhook_id NOT IN (
            SELECT webhook_id FROM pggit_traffic.queue_config
        )
    LOOP
        PERFORM pggit_traffic.initialize_webhook_traffic_config(
            v_webhook.webhook_id,
            10.0,
            FALSE
        );

        RETURN QUERY SELECT v_webhook.webhook_id, TRUE;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEWS: Traffic Shaping Monitoring
-- ============================================================================

-- Overview of traffic shaping status
CREATE OR REPLACE VIEW pggit_traffic.v_traffic_status AS
SELECT
    qc.webhook_id,
    whm.health_status,
    tbs.current_rps,
    pggit_traffic.get_current_tokens(qc.webhook_id) as available_tokens,
    tbs.bucket_capacity,
    (SELECT COUNT(*) FROM pggit.alert_delivery_queue
     WHERE webhook_id = qc.webhook_id AND delivery_status = 'pending') as pending_deliveries,
    qc.normal_queue_limit,
    ROUND(
        ((SELECT COUNT(*) FROM pggit.alert_delivery_queue
         WHERE webhook_id = qc.webhook_id AND delivery_status = 'pending')
        :: NUMERIC / qc.normal_queue_limit) * 100, 2
    ) as queue_utilization_percent,
    qc.is_critical_webhook,
    qc.auto_scaling_enabled,
    qc.last_adjustment_at
FROM pggit_traffic.queue_config qc
JOIN pggit.webhook_health_metrics whm ON whm.webhook_id = qc.webhook_id
JOIN pggit_traffic.token_bucket_state tbs ON tbs.webhook_id = qc.webhook_id
ORDER BY whm.health_status DESC, qc.webhook_id;

-- Rate adjustment history
CREATE OR REPLACE VIEW pggit_traffic.v_rate_adjustment_history AS
SELECT
    webhook_id,
    old_rps,
    new_rps,
    ROUND((new_rps - old_rps) / old_rps * 100, 2) as adjustment_percent,
    reason,
    success_rate,
    latency_p99_ms,
    queue_depth,
    consecutive_failures,
    adjustment_timestamp
FROM pggit_traffic.rate_adjustment_history
ORDER BY adjustment_timestamp DESC;

-- Active backpressure signals
CREATE OR REPLACE VIEW pggit_traffic.v_active_backpressure AS
SELECT
    signal_id,
    webhook_id,
    signal_type,
    severity,
    current_queue_depth,
    queue_capacity_percent,
    action,
    new_acceptance_rate,
    signal_timestamp,
    AGE(CURRENT_TIMESTAMP, signal_timestamp) as duration,
    is_active
FROM pggit_traffic.backpressure_signal
WHERE is_active = TRUE
ORDER BY severity DESC, signal_timestamp DESC;

-- Traffic shaping recommendations
CREATE OR REPLACE VIEW pggit_traffic.v_adaptive_rate_recommendations AS
SELECT
    qc.webhook_id,
    whm.health_status,
    tbs.current_rps as current_rate,
    (SELECT recommended_rps FROM pggit_traffic.calculate_adaptive_rate(qc.webhook_id)) as recommended_rate,
    (SELECT adjustment_reason FROM pggit_traffic.calculate_adaptive_rate(qc.webhook_id)) as recommendation_reason,
    (SELECT severity FROM pggit_traffic.calculate_adaptive_rate(qc.webhook_id)) as recommendation_severity,
    whm.consecutive_failures,
    CAST(whm.successful_deliveries AS NUMERIC) / NULLIF(whm.total_deliveries, 0) as success_rate
FROM pggit_traffic.queue_config qc
JOIN pggit.webhook_health_metrics whm ON whm.webhook_id = qc.webhook_id
JOIN pggit_traffic.token_bucket_state tbs ON tbs.webhook_id = qc.webhook_id
WHERE qc.auto_scaling_enabled = TRUE
ORDER BY whm.health_status DESC, qc.webhook_id;

-- Priority queue analysis
CREATE OR REPLACE VIEW pggit_traffic.v_priority_queue_analysis AS
SELECT
    COALESCE(dqp.priority_level,
            CASE WHEN qc.is_critical_webhook THEN qc.critical_queue_priority
                 ELSE qc.normal_queue_priority END) as priority_level,
    COUNT(*) as queue_count,
    AVG(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - adq.created_at))) as avg_wait_seconds,
    MAX(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - adq.created_at))) as max_wait_seconds,
    COUNT(DISTINCT adq.webhook_id) as unique_webhooks
FROM pggit.alert_delivery_queue adq
JOIN pggit_traffic.queue_config qc ON qc.webhook_id = adq.webhook_id
LEFT JOIN pggit_traffic.delivery_queue_priority dqp ON dqp.alert_id = adq.alert_id
WHERE adq.delivery_status = 'pending'
GROUP BY priority_level
ORDER BY priority_level DESC;
