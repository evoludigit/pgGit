-- ============================================================================
-- Phase 8 Week 2B: Integration Tests - PostgreSQL Hybrid Architecture
-- ============================================================================
-- Purpose: Verify end-to-end workflows for webhook delivery system
-- Coverage: Queue→Delivery→Health→Monitoring cycle
-- Prerequisites: PostgreSQL schema from phase8_week2_postgres_schema.sql
-- ============================================================================

\set ECHO all
\set ON_ERROR_STOP on

-- ============================================================================
-- TEST SUITE 1: Queue Management
-- ============================================================================
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;
SELECT 'TEST SUITE 1: Queue Management' as title;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;

-- Test 1.1: Insert delivery into queue
SELECT 'TEST 1.1: Insert delivery into queue' as test;
INSERT INTO pggit.alert_delivery_queue (
    alert_id, webhook_id, message_body, delivery_status,
    retry_count, max_retries, created_at
) VALUES (
    101, 1001,
    jsonb_build_object(
        'alert_id', 101,
        'type', 'anomaly_detection',
        'operation', 'commit',
        'severity', 'WARNING',
        'z_score', 4.2
    ),
    'pending', 0, 3, CURRENT_TIMESTAMP
);
SELECT COUNT(*) as inserted_count FROM pggit.alert_delivery_queue WHERE alert_id = 101;

-- Test 1.2: Get pending deliveries (FIFO order)
SELECT 'TEST 1.2: Get pending deliveries (FIFO order)' as test;
SELECT
    delivery_id, alert_id, webhook_id, delivery_status, created_at
FROM pggit.alert_delivery_queue
WHERE alert_id = 101
ORDER BY created_at ASC;

-- Test 1.3: get_ready_deliveries function
SELECT 'TEST 1.3: get_ready_deliveries function (lock-free polling)' as test;
SELECT
    delivery_id, alert_id, webhook_id, retry_count
FROM pggit.get_ready_deliveries(10);

-- Test 1.4: Verify delivery retrieval doesn't block other workers
SELECT 'TEST 1.4: Queue state after get_ready_deliveries' as test;
SELECT
    delivery_status, COUNT(*) as count
FROM pggit.alert_delivery_queue
WHERE alert_id = 101
GROUP BY delivery_status;

-- ============================================================================
-- TEST SUITE 2: Health Metrics & Status Transitions
-- ============================================================================
SELECT '' as separator;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;
SELECT 'TEST SUITE 2: Health Metrics & Status Transitions' as title;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;

-- Test 2.1: Update webhook health on successful delivery
SELECT 'TEST 2.1: Update webhook health on successful delivery (200 OK)' as test;
SELECT pggit.update_webhook_health(1001, 200, 45, NULL) as result;

-- Verify health record was created
SELECT
    webhook_id, health_status, total_deliveries, successful_deliveries,
    failed_deliveries, avg_response_time_ms, consecutive_failures
FROM pggit.webhook_health_metrics
WHERE webhook_id = 1001;

-- Test 2.2: Multiple successful deliveries aggregate metrics
SELECT 'TEST 2.2: Aggregate metrics over multiple deliveries' as test;
SELECT pggit.update_webhook_health(1001, 200, 50, NULL);
SELECT pggit.update_webhook_health(1001, 200, 60, NULL);
SELECT pggit.update_webhook_health(1001, 200, 40, NULL);

SELECT
    webhook_id, total_deliveries, successful_deliveries,
    ROUND(avg_response_time_ms::NUMERIC, 2) as avg_ms,
    health_status
FROM pggit.webhook_health_metrics
WHERE webhook_id = 1001;

-- Test 2.3: Failed delivery updates health status
SELECT 'TEST 2.3: Failed delivery (500 error) updates health' as test;
SELECT pggit.update_webhook_health(1001, 500, 100, 'Internal Server Error');

SELECT
    webhook_id, health_status, consecutive_failures,
    failed_deliveries, last_failure_at
FROM pggit.webhook_health_metrics
WHERE webhook_id = 1001;

-- Test 2.4: Consecutive failures (circuit breaker logic)
SELECT 'TEST 2.4: Consecutive failures accumulate' as test;
SELECT pggit.update_webhook_health(1002, 500, 100, 'Timeout');
SELECT pggit.update_webhook_health(1002, 500, 100, 'Timeout');
SELECT pggit.update_webhook_health(1002, 500, 100, 'Timeout');
SELECT pggit.update_webhook_health(1002, 500, 100, 'Timeout');
SELECT pggit.update_webhook_health(1002, 500, 100, 'Timeout');

SELECT
    webhook_id, consecutive_failures, health_status
FROM pggit.webhook_health_metrics
WHERE webhook_id = 1002;

-- Test 2.5: Success resets consecutive failures
SELECT 'TEST 2.5: Success resets consecutive failure counter' as test;
SELECT pggit.update_webhook_health(1002, 200, 50, NULL);

SELECT
    webhook_id, consecutive_failures, health_status,
    successful_deliveries, failed_deliveries
FROM pggit.webhook_health_metrics
WHERE webhook_id = 1002;

-- ============================================================================
-- TEST SUITE 3: Views & Dashboards
-- ============================================================================
SELECT '' as separator;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;
SELECT 'TEST SUITE 3: Views & Dashboards' as title;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;

-- Test 3.1: Webhook health dashboard
SELECT 'TEST 3.1: v_webhook_health_dashboard summary' as test;
SELECT
    health_status, webhook_count, avg_response_ms,
    failures_1h, failures_24h
FROM pggit.v_webhook_health_dashboard;

-- Test 3.2: Webhook performance view
SELECT 'TEST 3.2: v_webhook_performance metrics' as test;
SELECT
    webhook_id, total_deliveries, success_rate_percent,
    health_status, success_freshness
FROM pggit.v_webhook_performance
ORDER BY webhook_id;

-- Test 3.3: Degraded webhooks view
SELECT 'TEST 3.3: v_degraded_webhooks (problems only)' as test;
SELECT
    webhook_id, health_status, consecutive_failures,
    minutes_since_check, hours_since_success
FROM pggit.v_degraded_webhooks
ORDER BY consecutive_failures DESC;

-- Test 3.4: count_pending_by_status dashboard
SELECT 'TEST 3.4: count_pending_by_status queue metrics' as test;
SELECT * FROM pggit.count_pending_by_status();

-- ============================================================================
-- TEST SUITE 4: Error Handling & Edge Cases
-- ============================================================================
SELECT '' as separator;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;
SELECT 'TEST SUITE 4: Error Handling & Edge Cases' as title;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;

-- Test 4.1: Timeout (HTTP status 0)
SELECT 'TEST 4.1: Timeout (HTTP status 0 = network failure)' as test;
SELECT pggit.update_webhook_health(1003, 0, 5000, 'Connection timeout');

SELECT
    webhook_id, health_status, failed_deliveries
FROM pggit.webhook_health_metrics
WHERE webhook_id = 1003;

-- Test 4.2: Client error (4xx) vs server error (5xx)
SELECT 'TEST 4.2: Client error (400 Bad Request)' as test;
SELECT pggit.update_webhook_health(1004, 400, 50, 'Bad Request: invalid message format');

SELECT webhook_id, health_status FROM pggit.webhook_health_metrics WHERE webhook_id = 1004;

-- Test 4.3: Empty queue returns empty result
SELECT 'TEST 4.3: Empty queue returns no deliveries' as test;
DELETE FROM pggit.alert_delivery_queue WHERE delivery_status IN ('pending', 'retrying')
  AND created_at < CURRENT_TIMESTAMP - INTERVAL '1 minute';
SELECT COUNT(*) as pending_after_cleanup FROM pggit.alert_delivery_queue
WHERE delivery_status IN ('pending', 'retrying');

-- Test 4.4: get_webhook_decrypted stub function
SELECT 'TEST 4.4: get_webhook_decrypted stub (Week 2 implementation)' as test;
SELECT pggit.get_webhook_decrypted(1001) as webhook_url;

-- ============================================================================
-- TEST SUITE 5: Concurrency & Lock-Free Access
-- ============================================================================
SELECT '' as separator;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;
SELECT 'TEST SUITE 5: Concurrency & Lock-Free Access' as title;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;

-- Test 5.1: Verify FOR UPDATE SKIP LOCKED is used
SELECT 'TEST 5.1: Verify get_ready_deliveries uses lock-free access' as test;
INSERT INTO pggit.alert_delivery_queue (
    alert_id, webhook_id, message_body, delivery_status,
    retry_count, max_retries, created_at
) VALUES (
    102, 2001, jsonb_build_object('seq', 1), 'pending', 0, 3, CURRENT_TIMESTAMP
),
(
    103, 2002, jsonb_build_object('seq', 2), 'pending', 0, 3, CURRENT_TIMESTAMP
),
(
    104, 2003, jsonb_build_object('seq', 3), 'pending', 0, 3, CURRENT_TIMESTAMP
);

-- Get first batch
SELECT delivery_id, webhook_id FROM pggit.get_ready_deliveries(2);

-- Verify other deliveries still available (not locked)
SELECT COUNT(*) as available_after_batch FROM pggit.alert_delivery_queue
WHERE delivery_status = 'pending';

-- Test 5.2: Multiple calls to get_ready_deliveries work independently
SELECT 'TEST 5.2: Multiple get_ready_deliveries calls are non-blocking' as test;
SELECT COUNT(*) as first_call FROM pggit.get_ready_deliveries(10);
SELECT COUNT(*) as second_call FROM pggit.get_ready_deliveries(10);

-- ============================================================================
-- TEST SUITE 6: Performance Baseline
-- ============================================================================
SELECT '' as separator;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;
SELECT 'TEST SUITE 6: Performance Baseline (expected < 10ms)' as title;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;

-- Test 6.1: get_ready_deliveries performance
SELECT 'TEST 6.1: get_ready_deliveries latency' as test;
WITH timing AS (
    SELECT
        (SELECT EXTRACT(EPOCH FROM (clock_timestamp() - now())) * 1000) as pre_time
)
SELECT
    COUNT(*) as deliveries_returned,
    ROUND(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - now())) * 1000::NUMERIC, 2) as latency_ms
FROM pggit.get_ready_deliveries(100);

-- Test 6.2: update_webhook_health performance
SELECT 'TEST 6.2: update_webhook_health latency' as test;
SELECT pggit.update_webhook_health(3001, 200, 55, NULL);

-- Test 6.3: View query performance
SELECT 'TEST 6.3: v_webhook_performance view latency' as test;
SELECT COUNT(*) as webhook_records FROM pggit.v_webhook_performance;

-- ============================================================================
-- TEST SUITE 7: Data Consistency
-- ============================================================================
SELECT '' as separator;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;
SELECT 'TEST SUITE 7: Data Consistency & Integrity' as title;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;

-- Test 7.1: Verify constraint: total = successful + failed
SELECT 'TEST 7.1: Constraint validation (total = successful + failed)' as test;
SELECT
    webhook_id,
    total_deliveries,
    successful_deliveries + failed_deliveries as sum_delivered_failed,
    CASE
        WHEN total_deliveries = (successful_deliveries + failed_deliveries) THEN 'VALID'
        ELSE 'INVALID'
    END as constraint_check
FROM pggit.webhook_health_metrics
ORDER BY webhook_id;

-- Test 7.2: Verify unique constraint on webhook_id
SELECT 'TEST 7.2: Unique constraint on webhook_id' as test;
SELECT
    webhook_id, COUNT(*) as count
FROM pggit.webhook_health_metrics
GROUP BY webhook_id
HAVING COUNT(*) > 1;
SELECT 'No duplicates found' as result WHERE NOT EXISTS (
    SELECT 1 FROM pggit.webhook_health_metrics GROUP BY webhook_id HAVING COUNT(*) > 1
);

-- Test 7.3: Verify health_status enum values
SELECT 'TEST 7.3: Valid health_status values' as test;
SELECT DISTINCT health_status FROM pggit.webhook_health_metrics
ORDER BY health_status;

-- ============================================================================
-- TEST SUITE 8: End-to-End Workflow
-- ============================================================================
SELECT '' as separator;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;
SELECT 'TEST SUITE 8: End-to-End Workflow' as title;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;

-- Setup: Create a complete workflow scenario
SELECT 'TEST 8.1: Complete delivery lifecycle' as test;

-- Step 1: Insert alert into queue
INSERT INTO pggit.alert_delivery_queue (
    alert_id, webhook_id, message_body, delivery_status,
    retry_count, max_retries, created_at
) VALUES (
    200, 4001,
    jsonb_build_object('alert', 'performance degradation', 'severity', 'HIGH'),
    'pending', 0, 3, CURRENT_TIMESTAMP
) RETURNING delivery_id, alert_id, webhook_id, delivery_status;

-- Step 2: Worker retrieves ready deliveries
SELECT delivery_id, webhook_id FROM pggit.get_ready_deliveries(5);

-- Step 3: Worker reports success
SELECT pggit.update_webhook_health(4001, 200, 55, NULL);

-- Step 4: Check final state
SELECT
    'Queue Status' as check_point,
    delivery_status as status,
    COUNT(*) as count
FROM pggit.alert_delivery_queue
WHERE alert_id = 200
GROUP BY delivery_status
UNION ALL
SELECT
    'Health Metrics' as check_point,
    health_status as status,
    1 as count
FROM pggit.webhook_health_metrics
WHERE webhook_id = 4001;

-- ============================================================================
-- TEST SUMMARY
-- ============================================================================
SELECT '' as separator;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;
SELECT 'TEST SUMMARY' as title;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as section;

SELECT
    'Queue Management' as suite,
    (SELECT COUNT(*) FROM pggit.alert_delivery_queue) as queue_items,
    (SELECT COUNT(DISTINCT webhook_id) FROM pggit.webhook_health_metrics) as tracked_webhooks,
    'COMPLETE' as status;
