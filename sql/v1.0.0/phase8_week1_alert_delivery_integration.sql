-- ============================================================================
-- Phase 8: Week 1 - Alert Delivery Integration with Week 4
-- ============================================================================
-- Purpose: Connect Phase 8 delivery system to Week 4 alerts via triggers
-- Design: Transparent integration, Week 4 code completely untouched
-- Date: 2025-12-27
-- Status: Production-ready implementation
-- ============================================================================

-- ============================================================================
-- PART A: Integration with Week 4 Alert System
-- ============================================================================
-- Week 4 emits: INSERT into alert_notification_queue
-- Phase 8 observes: TRIGGER fires observer_queue_alert()
-- Result: Alerts automatically queued for delivery
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.trigger_queue_alert()
RETURNS TRIGGER AS $$
DECLARE
    v_delivery_id BIGINT;
BEGIN
    -- Week 4 alert received, queue it for delivery via Phase 8
    -- Build delivery message from Week 4 alert format
    v_delivery_id := pggit.observer_queue_alert(
        p_alert_id => NEW.queue_id,
        p_webhook_id => NEW.webhook_id,
        p_message_body => jsonb_build_object(
            'alert_id', NEW.queue_id,
            'webhook_id', NEW.webhook_id,
            'message_format', NEW.message_format,
            'message_body', NEW.message_body,
            'original_status', NEW.status,
            'queued_at', CURRENT_TIMESTAMP
        )
    );

    -- Log integration event
    INSERT INTO pggit.alert_delivery_log (
        delivery_id,
        webhook_id,
        event_type,
        event_details,
        created_at
    ) VALUES (
        v_delivery_id,
        NEW.webhook_id,
        'queued',
        jsonb_build_object(
            'integration_source', 'week4_alert_notification_queue',
            'original_queue_id', NEW.queue_id
        ),
        CURRENT_TIMESTAMP
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TRIGGER: alert_queue trigger on Week 4's alert_notification_queue
-- ============================================================================
-- When: AFTER INSERT on alert_notification_queue
-- Effect: Automatically queue alert for delivery via Phase 8 system
-- ============================================================================

CREATE TRIGGER trigger_alert_queue
AFTER INSERT ON pggit.alert_notification_queue
FOR EACH ROW
EXECUTE FUNCTION pggit.trigger_queue_alert();

-- ============================================================================
-- PART B: Retry Processor for Failed Deliveries
-- ============================================================================
-- Purpose: Process alerts stuck in 'retrying' status with next_retry_at
-- Frequency: Run via scheduled pg_cron job every 1 minute (Week 2+)
-- Week 1: Manual execution for testing
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.process_failed_deliveries()
RETURNS TABLE (
    processed_count INT,
    succeeded_count INT,
    failed_count INT,
    escalated_count INT,
    execution_timestamp TIMESTAMP WITH TIME ZONE
) AS $$
DECLARE
    v_processed_count INT := 0;
    v_succeeded_count INT := 0;
    v_failed_count INT := 0;
    v_escalated_count INT := 0;
    v_delivery_id BIGINT;
    v_delivery_status TEXT;
    v_retry_count INT;
BEGIN
    -- Process alerts ready for retry (next_retry_at <= now)
    FOR v_delivery_id, v_delivery_status, v_retry_count IN
        SELECT delivery_id, delivery_status, retry_count
        FROM pggit.alert_delivery_queue
        WHERE delivery_status = 'retrying'
          AND next_retry_at IS NOT NULL
          AND next_retry_at <= CURRENT_TIMESTAMP
        ORDER BY next_retry_at ASC
        LIMIT 50  -- Process in batches of 50 per execution
    LOOP
        v_processed_count := v_processed_count + 1;

        BEGIN
            -- Attempt delivery via observer
            PERFORM pggit.observer_deliver_alert(v_delivery_id);

            -- Check if delivery succeeded
            SELECT delivery_status INTO v_delivery_status
            FROM pggit.alert_delivery_queue
            WHERE delivery_id = v_delivery_id;

            IF v_delivery_status = 'delivered' THEN
                v_succeeded_count := v_succeeded_count + 1;
            ELSIF v_delivery_status = 'failed' THEN
                v_failed_count := v_failed_count + 1;
            END IF;

        EXCEPTION WHEN OTHERS THEN
            -- Log processing error
            UPDATE pggit.alert_delivery_queue
            SET delivery_status = 'failed'
            WHERE delivery_id = v_delivery_id;

            INSERT INTO pggit.alert_delivery_log (
                delivery_id,
                webhook_id,
                event_type,
                event_details,
                created_at
            ) VALUES (
                v_delivery_id,
                (SELECT webhook_id FROM pggit.alert_delivery_queue WHERE delivery_id = v_delivery_id),
                'failed',
                jsonb_build_object(
                    'processor_error', SQLERRM,
                    'phase', 'retry_processor'
                ),
                CURRENT_TIMESTAMP
            );

            v_failed_count := v_failed_count + 1;
        END;
    END LOOP;

    -- Escalate alerts stuck for >30 minutes (for manual intervention)
    WITH escalation_candidates AS (
        SELECT delivery_id, webhook_id
        FROM pggit.alert_delivery_queue
        WHERE delivery_status IN ('pending', 'retrying')
          AND created_at < CURRENT_TIMESTAMP - INTERVAL '30 minutes'
        LIMIT 50
    )
    UPDATE pggit.alert_delivery_queue
    SET delivery_status = 'failed'  -- Mark as failed to prevent infinite retry loop
    WHERE delivery_id IN (SELECT delivery_id FROM escalation_candidates)
    RETURNING 1 INTO v_escalated_count;

    v_escalated_count := COALESCE(v_escalated_count, 0);

    -- Update observer execution tracking
    UPDATE pggit.alert_observers
    SET execution_count = execution_count + 1,
        last_execution_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE observer_type = 'delivery'
      AND is_active = TRUE;

    RETURN QUERY SELECT
        v_processed_count,
        v_succeeded_count,
        v_failed_count,
        v_escalated_count,
        CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- HELPER: Manual Retry Function
-- ============================================================================
-- Purpose: Manually retry a specific failed delivery
-- Usage: SELECT * FROM pggit.retry_delivery(delivery_id);
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.retry_delivery(
    p_delivery_id BIGINT
)
RETURNS TABLE (
    delivery_id BIGINT,
    status TEXT,
    http_status INT,
    error_message TEXT
) AS $$
BEGIN
    -- Reset retry state for immediate retry
    UPDATE pggit.alert_delivery_queue
    SET delivery_status = 'pending',
        next_retry_at = NULL,
        attempted_at = NULL
    WHERE delivery_id = p_delivery_id
      AND delivery_status IN ('retrying', 'failed');

    -- Attempt delivery
    RETURN QUERY
    SELECT * FROM pggit.observer_deliver_alert(p_delivery_id);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- HELPER: Reset Stuck Deliveries
-- ============================================================================
-- Purpose: Reset deliveries stuck for >1 hour to pending for fresh retry
-- Warning: Use with caution, only for manual intervention
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.reset_stuck_deliveries()
RETURNS TABLE (
    reset_count INT,
    execution_timestamp TIMESTAMP
) AS $$
DECLARE
    v_reset_count INT;
BEGIN
    -- Reset stuck deliveries
    UPDATE pggit.alert_delivery_queue
    SET delivery_status = 'pending',
        retry_count = 0,
        next_retry_at = NULL,
        attempted_at = NULL
    WHERE delivery_status IN ('pending', 'retrying')
      AND created_at < CURRENT_TIMESTAMP - INTERVAL '60 minutes';

    GET DIAGNOSTICS v_reset_count = ROW_COUNT;

    -- Log reset event
    INSERT INTO pggit.alert_delivery_log (
        delivery_id,
        webhook_id,
        event_type,
        event_details,
        created_at
    ) SELECT
        delivery_id,
        webhook_id,
        'escalated',
        jsonb_build_object(
            'action', 'manual_reset_stuck_deliveries',
            'reason', 'stuck_for_>60_minutes'
        ),
        CURRENT_TIMESTAMP
    FROM pggit.alert_delivery_queue
    WHERE delivery_status = 'pending'
      AND created_at < CURRENT_TIMESTAMP - INTERVAL '60 minutes';

    RETURN QUERY SELECT v_reset_count, CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEWS: Operational Monitoring
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_delivery_queue_status AS
SELECT
    'pending' as status,
    COUNT(*) as count,
    MIN(created_at) as oldest,
    MAX(created_at) as newest
FROM pggit.alert_delivery_queue
WHERE delivery_status = 'pending'
UNION ALL
SELECT
    'retrying',
    COUNT(*),
    MIN(created_at),
    MAX(created_at)
FROM pggit.alert_delivery_queue
WHERE delivery_status = 'retrying'
UNION ALL
SELECT
    'delivered',
    COUNT(*),
    MIN(delivered_at),
    MAX(delivered_at)
FROM pggit.alert_delivery_queue
WHERE delivery_status = 'delivered'
  AND delivered_at IS NOT NULL
UNION ALL
SELECT
    'failed',
    COUNT(*),
    MIN(created_at),
    MAX(created_at)
FROM pggit.alert_delivery_queue
WHERE delivery_status = 'failed';

-- ============================================================================
-- VIEW: Delivery Performance Metrics
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_delivery_performance AS
SELECT
    COUNT(*) as total_deliveries,
    COUNT(CASE WHEN delivery_status = 'delivered' THEN 1 END) as successful,
    COUNT(CASE WHEN delivery_status = 'failed' THEN 1 END) as failed,
    COUNT(CASE WHEN delivery_status IN ('pending', 'retrying') THEN 1 END) as in_progress,
    ROUND(
        100.0 * COUNT(CASE WHEN delivery_status = 'delivered' THEN 1 END) /
        NULLIF(COUNT(*), 0),
        1
    ) as success_rate_percent,
    ROUND(
        EXTRACT(EPOCH FROM (
            AVG(CASE WHEN delivered_at IS NOT NULL THEN delivered_at - created_at END)
        ))::NUMERIC,
        2
    ) as avg_delivery_time_seconds,
    MAX(CASE WHEN retry_count > 0 THEN retry_count ELSE 0 END) as max_retries_used,
    CURRENT_TIMESTAMP as calculated_at
FROM pggit.alert_delivery_queue;

-- ============================================================================
-- VIEW: Failed Delivery Details (for investigation)
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_failed_deliveries AS
SELECT
    adq.delivery_id,
    adq.webhook_id,
    adq.alert_id,
    adq.retry_count,
    adq.max_retries,
    adq.created_at,
    adq.attempted_at,
    ROUND(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - adq.created_at)) / 3600.0, 1) as hours_stuck,
    adl.event_details,
    adl.created_at as last_error_at
FROM pggit.alert_delivery_queue adq
LEFT JOIN LATERAL (
    SELECT event_details, created_at
    FROM pggit.alert_delivery_log
    WHERE delivery_id = adq.delivery_id
      AND event_type = 'failed'
    ORDER BY created_at DESC
    LIMIT 1
) adl ON true
WHERE adq.delivery_status = 'failed'
ORDER BY adq.created_at ASC;

-- ============================================================================
-- INITIALIZATION: Insert observer registry entries
-- ============================================================================

INSERT INTO pggit.alert_observers (observer_type, is_active)
VALUES
    ('delivery', TRUE),
    ('escalation', TRUE),
    ('health', TRUE)
ON CONFLICT (observer_type) DO NOTHING;

-- ============================================================================
-- SUMMARY
-- ============================================================================
-- Integration Layer Functions (3):
--
--   1. trigger_queue_alert() - Trigger function
--      - Called by: TRIGGER on alert_notification_queue
--      - Effect: Observes Week 4 inserts, queues for Phase 8 delivery
--      - Integration: Transparent, Week 4 code untouched
--
--   2. process_failed_deliveries() - Retry processor
--      - Input: None (queries queue directly)
--      - Output: processed, succeeded, failed, escalated counts
--      - Batch size: 50 per execution
--      - Run frequency: 1-minute intervals (via pg_cron in Week 2)
--      - Escalation: >30 minutes stuck → marked as failed
--
--   3. retry_delivery() - Manual retry helper
--      - Input: delivery_id
--      - Output: Retry result (status, http_status, error)
--      - Usage: For manual intervention on individual deliveries
--
-- Escalation Helper (1):
--   4. reset_stuck_deliveries() - Manual reset for >60 min stuck
--      - WARNING: Use with caution
--      - Purpose: Manual intervention for chronic failures
--      - Resets to 'pending' for fresh retry attempt
--
-- Views (3):
--   1. v_delivery_queue_status - Queue status breakdown
--   2. v_delivery_performance - Metrics (success rate, avg time, etc.)
--   3. v_failed_deliveries - Details of failed deliveries with error context
--
-- TRIGGER (1):
--   1. trigger_alert_queue - AFTER INSERT on alert_notification_queue
--      - Fires observer_queue_alert() for each Week 4 alert
--      - Automatic Phase 8 queuing when Week 4 creates alerts
--
-- Integration Architecture:
--   Week 4 (Alert Creation)
--   └─ INSERT into alert_notification_queue
--      └─ TRIGGER trigger_alert_queue fires
--         └─ pggit.trigger_queue_alert() executes
--            └─ pggit.observer_queue_alert() queues for delivery
--               └─ INSERT into alert_delivery_queue (Phase 8)
--
--   Phase 8 Delivery Pipeline (Automatic):
--   Alert queued
--   └─ observer_deliver_alert() runs (immediate <100ms)
--      └─ Attempts delivery, logs result
--         └─ Success: Mark delivered, log success
--         └─ Failure: Schedule retry with exponential backoff
--
--   Retry Processing (Scheduled):
--   process_failed_deliveries() runs (every 1 minute)
--   └─ Finds retrying alerts ready (next_retry_at <= now)
--      └─ observer_deliver_alert() retries each
--         └─ Success: Mark delivered
--         └─ Failure: Update next_retry_at
--   └─ Escalates >30min stuck alerts (manual intervention)
--
-- Data Flow:
--   Week 4 creates alert
--   └─> Phase 8 queues it
--       └─> Attempts immediate delivery (observer_deliver_alert)
--           ├─> Success: DELIVERED
--           └─> Failure: Schedule retry
--               └─> Next retry window: 5min, 10min, 15min
--                   └─> process_failed_deliveries() retries
--                       ├─> Success: DELIVERED
--                       └─> Failure: Escalate at >30min
--
-- Performance Targets:
--   - Trigger execution: <5ms
--   - Immediate delivery: <100ms
--   - Retry processor: <500ms for batch of 50
--   - Views: <5ms
--   - Escalation threshold: 30 minutes stuck
--   - Escalation batch size: 50 per execution
-- ============================================================================
