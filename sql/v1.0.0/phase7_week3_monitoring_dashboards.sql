-- ============================================================================
-- Phase 7: Week 3 Monitoring Dashboards
-- ============================================================================
-- Description: Meta-monitoring views for the monitoring system itself
-- Recommended implementation from specialist review
-- Version: 1.0.0
-- Date: 2025-12-27
-- ============================================================================

-- ============================================================================
-- 1. MONITORING SYSTEM HEALTH DASHBOARD
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_monitoring_system_health AS
WITH alert_stats AS (
    SELECT
        'alerts' as metric,
        COUNT(*) as total,
        COUNT(CASE WHEN is_acknowledged = FALSE THEN 1 END) as active,
        COUNT(CASE WHEN severity = 'CRITICAL' THEN 1 END) as critical,
        COUNT(CASE WHEN severity = 'WARNING' THEN 1 END) as warning,
        COUNT(CASE WHEN created_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour' THEN 1 END) as last_hour,
        COUNT(CASE WHEN created_at >= CURRENT_TIMESTAMP - INTERVAL '1 day' THEN 1 END) as last_day
    FROM pggit.performance_alerts
),
baseline_stats AS (
    SELECT
        'baselines' as metric,
        COUNT(*) as total,
        COUNT(CASE WHEN is_active = TRUE THEN 1 END) as active,
        NULL::INTEGER as critical,
        NULL::INTEGER as warning,
        COUNT(CASE WHEN calculation_timestamp >= CURRENT_TIMESTAMP - INTERVAL '1 hour' THEN 1 END) as last_hour,
        COUNT(CASE WHEN calculation_timestamp >= CURRENT_TIMESTAMP - INTERVAL '1 day' THEN 1 END) as last_day
    FROM pggit.performance_baselines
),
notification_stats AS (
    SELECT
        'notifications' as metric,
        COUNT(*) as total,
        COUNT(CASE WHEN status IN ('pending', 'retrying') THEN 1 END) as active,
        COUNT(CASE WHEN status = 'failed' THEN 1 END) as critical,
        COUNT(CASE WHEN status = 'pending' THEN 1 END) as warning,
        COUNT(CASE WHEN created_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour' THEN 1 END) as last_hour,
        COUNT(CASE WHEN created_at >= CURRENT_TIMESTAMP - INTERVAL '1 day' THEN 1 END) as last_day
    FROM pggit.alert_notification_queue
),
webhook_stats AS (
    SELECT
        'webhooks' as metric,
        COUNT(*) as total,
        COUNT(CASE WHEN enabled = TRUE THEN 1 END) as active,
        COUNT(CASE WHEN test_status = 'failed' THEN 1 END) as critical,
        COUNT(CASE WHEN test_status = 'untested' THEN 1 END) as warning,
        COUNT(CASE WHEN last_tested_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour' THEN 1 END) as last_hour,
        COUNT(CASE WHEN last_tested_at >= CURRENT_TIMESTAMP - INTERVAL '1 day' THEN 1 END) as last_day
    FROM pggit.alert_notification_webhooks
)
SELECT * FROM alert_stats
UNION ALL
SELECT * FROM baseline_stats
UNION ALL
SELECT * FROM notification_stats
UNION ALL
SELECT * FROM webhook_stats;

COMMENT ON VIEW pggit.v_monitoring_system_health IS
'High-level health dashboard showing counts of alerts, baselines, notifications, and webhooks';

-- ============================================================================
-- 2. BASELINE RECALCULATION HEALTH
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_baseline_recalc_health AS
SELECT
    DATE_TRUNC('day', calculated_at) as recalc_date,
    COUNT(*) as total_changes,
    COUNT(CASE WHEN percent_change > 0 THEN 1 END) as degraded,
    COUNT(CASE WHEN percent_change < 0 THEN 1 END) as improved,
    COUNT(CASE WHEN ABS(percent_change) > 10 THEN 1 END) as significant_changes,
    ROUND(AVG(ABS(percent_change))::NUMERIC, 2) as avg_abs_change_pct,
    ROUND(MAX(ABS(percent_change))::NUMERIC, 2) as max_abs_change_pct,
    AVG(sample_count) as avg_sample_count,
    MIN(sample_count) as min_sample_count,
    MAX(sample_count) as max_sample_count,
    STRING_AGG(DISTINCT reason, ', ') as recalc_reasons
FROM pggit.performance_baseline_history
GROUP BY DATE_TRUNC('day', calculated_at)
ORDER BY recalc_date DESC;

COMMENT ON VIEW pggit.v_baseline_recalc_health IS
'Daily baseline recalculation health showing changes, significance, and sample counts';

-- ============================================================================
-- 3. ALERT DELIVERY SUCCESS RATE
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_alert_delivery_success_rate AS
WITH delivery_stats AS (
    SELECT
        webhook_type,
        status,
        COUNT(*) as delivery_count,
        ROUND(AVG(delivery_time_ms)::NUMERIC, 2) as avg_delivery_time_ms,
        MAX(delivery_time_ms) as max_delivery_time_ms,
        STRING_AGG(DISTINCT error_message, '; ' ORDER BY error_message) FILTER (WHERE error_message IS NOT NULL) as error_messages
    FROM pggit.alert_notification_log
    WHERE sent_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
    GROUP BY webhook_type, status
)
SELECT
    webhook_type,
    SUM(CASE WHEN status = 'success' THEN delivery_count ELSE 0 END) as success_count,
    SUM(CASE WHEN status = 'failed' THEN delivery_count ELSE 0 END) as failed_count,
    ROUND(
        100.0 * SUM(CASE WHEN status = 'success' THEN delivery_count ELSE 0 END) /
        SUM(delivery_count),
        2
    ) as success_rate_pct,
    ROUND(
        (SELECT AVG(avg_delivery_time_ms) FROM delivery_stats WHERE status = 'success' AND delivery_stats.webhook_type = ds.webhook_type)::NUMERIC,
        2
    ) as avg_success_delivery_ms
FROM delivery_stats ds
GROUP BY webhook_type
ORDER BY success_rate_pct DESC;

COMMENT ON VIEW pggit.v_alert_delivery_success_rate IS
'Last 7 days alert delivery success rate by notification channel (webhook type)';

-- ============================================================================
-- 4. ALERT RESPONSE TIME SLA
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_alert_response_sla AS
WITH alert_response_times AS (
    SELECT
        a.alert_id,
        a.operation_type,
        a.severity,
        a.created_at as alert_time,
        COALESCE(
            (SELECT MIN(created_at) FROM pggit.alert_snooze
             WHERE operation_type = a.operation_type
               AND created_at > a.created_at
             LIMIT 1),
            CURRENT_TIMESTAMP
        ) as acknowledged_time,
        EXTRACT(EPOCH FROM (
            COALESCE(
                (SELECT MIN(created_at) FROM pggit.alert_snooze
                 WHERE operation_type = a.operation_type
                   AND created_at > a.created_at
                 LIMIT 1),
                CURRENT_TIMESTAMP
            ) - a.created_at
        )) / 60 as response_minutes
    FROM pggit.performance_alerts a
    WHERE a.created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
)
SELECT
    severity,
    COUNT(*) as total_alerts,
    COUNT(CASE WHEN response_minutes <= 5 THEN 1 END) as met_sla_5min,
    COUNT(CASE WHEN response_minutes > 5 AND response_minutes <= 15 THEN 1 END) as met_sla_15min,
    COUNT(CASE WHEN response_minutes > 15 THEN 1 END) as missed_sla,
    ROUND(
        100.0 * COUNT(CASE WHEN response_minutes <= 5 THEN 1 END) / COUNT(*),
        2
    ) as sla_5min_pct,
    ROUND(
        100.0 * COUNT(CASE WHEN response_minutes <= 15 THEN 1 END) / COUNT(*),
        2
    ) as sla_15min_pct,
    ROUND(AVG(response_minutes)::NUMERIC, 2) as avg_response_minutes,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY response_minutes)::NUMERIC, 2) as p95_response_minutes
FROM alert_response_times
GROUP BY severity
ORDER BY CASE WHEN severity = 'CRITICAL' THEN 1 WHEN severity = 'WARNING' THEN 2 ELSE 3 END;

COMMENT ON VIEW pggit.v_alert_response_sla IS
'Alert response SLA tracking: target 5min for CRITICAL, 15min for WARNING';

-- ============================================================================
-- 5. OPERATION TYPE PERFORMANCE TREND
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_operation_performance_trend AS
WITH hourly_stats AS (
    SELECT
        operation_type,
        DATE_TRUNC('hour', recorded_at) as hour,
        COUNT(*) as metric_count,
        ROUND(AVG(duration_microseconds / 1000.0)::NUMERIC, 2) as avg_ms,
        ROUND(MAX(duration_microseconds / 1000.0)::NUMERIC, 2) as max_ms,
        ROUND((PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_microseconds) / 1000.0)::NUMERIC, 2) as p99_ms
    FROM pggit.performance_metrics
    WHERE recorded_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
    GROUP BY operation_type, DATE_TRUNC('hour', recorded_at)
)
SELECT
    hs.operation_type,
    hs.hour,
    hs.metric_count,
    hs.avg_ms,
    hs.max_ms,
    hs.p99_ms,
    b.p99_microseconds / 1000.0 as baseline_p99_ms,
    ROUND((hs.p99_ms / (b.p99_microseconds / 1000.0))::NUMERIC, 2) as baseline_ratio,
    CASE
        WHEN (hs.p99_ms / (b.p99_microseconds / 1000.0)) > (b.alert_threshold_multiplier * 1.5) THEN 'CRITICAL'
        WHEN (hs.p99_ms / (b.p99_microseconds / 1000.0)) > b.alert_threshold_multiplier THEN 'WARNING'
        ELSE 'NORMAL'
    END as status
FROM hourly_stats hs
LEFT JOIN pggit.performance_baselines b
    ON hs.operation_type = b.operation_type AND b.is_active = TRUE
ORDER BY hs.hour DESC, hs.operation_type;

COMMENT ON VIEW pggit.v_operation_performance_trend IS
'Hourly performance trend for all operation types over last 24 hours';

-- ============================================================================
-- 6. ALERT FREQUENCY BY OPERATION
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_alert_frequency_by_operation AS
WITH date_range AS (
    SELECT CURRENT_TIMESTAMP - INTERVAL '30 days' as start_date
)
SELECT
    a.operation_type,
    COUNT(*) as total_alerts_30d,
    COUNT(CASE WHEN a.severity = 'CRITICAL' THEN 1 END) as critical_30d,
    COUNT(CASE WHEN a.severity = 'WARNING' THEN 1 END) as warning_30d,
    COUNT(CASE WHEN a.created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days' THEN 1 END) as total_alerts_7d,
    COUNT(CASE WHEN a.created_at >= CURRENT_TIMESTAMP - INTERVAL '1 day' THEN 1 END) as total_alerts_1d,
    ROUND((COUNT(*) / 30.0)::NUMERIC, 1) as avg_alerts_per_day,
    b.p99_microseconds / 1000.0 as current_baseline_p99_ms,
    COUNT(CASE WHEN a.is_acknowledged = FALSE THEN 1 END) as currently_unacknowledged
FROM pggit.performance_alerts a
LEFT JOIN pggit.performance_baselines b
    ON a.operation_type = b.operation_type AND b.is_active = TRUE
WHERE a.created_at >= (SELECT start_date FROM date_range)
GROUP BY a.operation_type, b.p99_microseconds, b.alert_threshold_multiplier
ORDER BY total_alerts_30d DESC;

COMMENT ON VIEW pggit.v_alert_frequency_by_operation IS
'Alert frequency analysis by operation type over 30 days, 7 days, and 1 day windows';

-- ============================================================================
-- 7. SNOOZED ALERTS AUDIT
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_snoozed_alerts_audit AS
SELECT
    snooze_id,
    operation_type,
    alert_type,
    created_by,
    created_at,
    snooze_until,
    EXTRACT(EPOCH FROM (snooze_until - CURRENT_TIMESTAMP)) / 3600 as hours_remaining,
    snooze_reason,
    is_active,
    CASE
        WHEN is_active = TRUE AND snooze_until > CURRENT_TIMESTAMP THEN 'ACTIVE'
        WHEN is_active = TRUE AND snooze_until <= CURRENT_TIMESTAMP THEN 'EXPIRED'
        ELSE 'INACTIVE'
    END as status
FROM pggit.alert_snooze
ORDER BY snooze_until DESC;

COMMENT ON VIEW pggit.v_snoozed_alerts_audit IS
'Audit view of all snoozed alerts showing duration, reason, and status';

-- ============================================================================
-- 8. BASELINE CHANGE IMPACT ANALYSIS
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_baseline_change_impact AS
SELECT
    bh.operation_type,
    COUNT(*) as total_baseline_changes,
    ROUND(AVG(ABS(bh.percent_change))::NUMERIC, 2) as avg_change_pct,
    MAX(ABS(bh.percent_change)) as max_change_pct,
    COUNT(CASE WHEN ABS(bh.percent_change) > 20 THEN 1 END) as major_changes,
    COUNT(CASE WHEN bh.percent_change < 0 THEN 1 END) as improvements,
    COUNT(CASE WHEN bh.percent_change > 0 THEN 1 END) as degradations,
    b.p99_microseconds / 1000.0 as current_p99_ms,
    b.sample_count as current_sample_count,
    MAX(bh.calculated_at) as last_recalc
FROM pggit.performance_baseline_history bh
LEFT JOIN pggit.performance_baselines b
    ON bh.operation_type = b.operation_type AND b.is_active = TRUE
WHERE bh.calculated_at >= CURRENT_TIMESTAMP - INTERVAL '90 days'
GROUP BY bh.operation_type, b.p99_microseconds, b.sample_count
ORDER BY total_baseline_changes DESC;

COMMENT ON VIEW pggit.v_baseline_change_impact IS
'Baseline stability analysis showing change frequency and magnitude over 90 days';

-- ============================================================================
-- 9. NOTIFICATION QUEUE HEALTH
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_notification_queue_health AS
WITH queue_age AS (
    SELECT
        nw.webhook_type,
        anq.status,
        COUNT(*) as count,
        ROUND(AVG(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - anq.created_at)) / 60)::NUMERIC, 2) as avg_age_minutes,
        MAX(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - anq.created_at)) / 60) as max_age_minutes,
        ROUND(
            (SUM(CASE WHEN anq.retry_count > 0 THEN 1 ELSE 0 END)::NUMERIC / COUNT(*)) * 100,
            2
        ) as retry_percent
    FROM pggit.alert_notification_queue anq
    LEFT JOIN pggit.alert_notification_webhooks nw ON anq.webhook_id = nw.webhook_id
    WHERE anq.created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
    GROUP BY nw.webhook_type, anq.status
)
SELECT
    COALESCE(nw.webhook_type, qa.webhook_type) as webhook_type,
    COALESCE(qa.status, 'no_queue') as status,
    COALESCE(qa.count, 0) as queue_count,
    COALESCE(qa.avg_age_minutes, 0) as avg_age_minutes,
    COALESCE(qa.max_age_minutes, 0) as max_age_minutes,
    COALESCE(qa.retry_percent, 0) as retry_percent,
    COALESCE(nw.enabled, FALSE) as webhook_enabled,
    COALESCE(nw.test_status, 'unknown') as webhook_test_status
FROM queue_age qa
FULL OUTER JOIN (
    SELECT DISTINCT webhook_type, enabled, test_status
    FROM pggit.alert_notification_webhooks
) nw ON qa.webhook_type = nw.webhook_type
ORDER BY COALESCE(qa.count, 0) DESC;

COMMENT ON VIEW pggit.v_notification_queue_health IS
'Notification queue health showing pending items, age, retry rate, and webhook status';

-- ============================================================================
-- 10. EXECUTION ERROR TRACKING
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_baseline_recalc_execution_health AS
WITH recent_executions AS (
    SELECT
        operation_type,
        status,
        COUNT(*) as count,
        ROUND(AVG(duration_ms)::NUMERIC, 2) as avg_duration_ms,
        MAX(duration_ms) as max_duration_ms,
        MAX(start_time) as latest_execution,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MAX(start_time))) / 3600 as hours_since_last
    FROM pggit.baseline_recalc_execution
    WHERE start_time >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    GROUP BY operation_type, status
)
SELECT
    COALESCE(re.operation_type, 'ALL') as operation_type,
    COALESCE(re.status, 'UNKNOWN') as status,
    COALESCE(re.count, 0) as execution_count_30d,
    COALESCE(re.avg_duration_ms, 0) as avg_duration_ms,
    COALESCE(re.max_duration_ms, 0) as max_duration_ms,
    COALESCE(re.latest_execution::TEXT, 'NEVER') as latest_execution,
    COALESCE(re.hours_since_last, NULL) as hours_since_last,
    CASE
        WHEN re.status = 'FAILED' THEN 'CRITICAL'
        WHEN re.hours_since_last > 25 THEN 'WARNING'
        WHEN re.status = 'RUNNING' THEN 'IN_PROGRESS'
        ELSE 'OK'
    END as health_status
FROM recent_executions re
ORDER BY COALESCE(re.count, 0) DESC, COALESCE(re.hours_since_last, 0) DESC;

COMMENT ON VIEW pggit.v_baseline_recalc_execution_health IS
'Baseline recalculation execution health tracking success, failures, and timing';

-- ============================================================================
-- GRANTS FOR MONITORING VIEWS
-- ============================================================================

GRANT SELECT ON pggit.v_monitoring_system_health TO PUBLIC;
GRANT SELECT ON pggit.v_baseline_recalc_health TO PUBLIC;
GRANT SELECT ON pggit.v_alert_delivery_success_rate TO PUBLIC;
GRANT SELECT ON pggit.v_alert_response_sla TO PUBLIC;
GRANT SELECT ON pggit.v_operation_performance_trend TO PUBLIC;
GRANT SELECT ON pggit.v_alert_frequency_by_operation TO PUBLIC;
GRANT SELECT ON pggit.v_snoozed_alerts_audit TO PUBLIC;
GRANT SELECT ON pggit.v_baseline_change_impact TO PUBLIC;
GRANT SELECT ON pggit.v_notification_queue_health TO PUBLIC;
GRANT SELECT ON pggit.v_baseline_recalc_execution_health TO PUBLIC;

-- ============================================================================
-- SAMPLE QUERIES FOR MONITORING DASHBOARD
-- ============================================================================

-- Health dashboard query (execute every 5 minutes)
/*
SELECT * FROM pggit.v_monitoring_system_health;
*/

-- Alert response SLA (execute every 1 hour)
/*
SELECT * FROM pggit.v_alert_response_sla;
*/

-- Critical issues check (execute every 1 minute)
/*
SELECT * FROM pggit.v_notification_queue_health
WHERE status IN ('pending', 'failed')
  AND queue_count > 0;
*/

-- Baseline stability check (execute every 6 hours)
/*
SELECT * FROM pggit.v_baseline_change_impact
WHERE major_changes > 5
   OR max_change_pct > 50;
*/

-- ============================================================================
-- VERSION AND METADATA
-- ============================================================================

COMMENT ON SCHEMA pggit IS 'pgGit performance monitoring system with critical enhancements';

-- Create a meta-view that shows when these dashboards were last updated
CREATE OR REPLACE VIEW pggit.v_monitoring_dashboard_freshness AS
SELECT
    'v_monitoring_system_health' as dashboard,
    (SELECT MAX(created_at) FROM pggit.performance_alerts) as last_data_update,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - (SELECT MAX(created_at) FROM pggit.performance_alerts))) / 60 as minutes_since_update
UNION ALL
SELECT
    'v_alert_response_sla',
    (SELECT MAX(created_at) FROM pggit.alert_snooze),
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - (SELECT MAX(created_at) FROM pggit.alert_snooze))) / 60
UNION ALL
SELECT
    'v_notification_queue_health',
    (SELECT MAX(created_at) FROM pggit.alert_notification_queue),
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - (SELECT MAX(created_at) FROM pggit.alert_notification_queue))) / 60;

GRANT SELECT ON pggit.v_monitoring_dashboard_freshness TO PUBLIC;

-- ============================================================================
-- INTEGRATION WITH EXISTING DASHBOARDS
-- ============================================================================

-- Add meta-metrics to the performance dashboard
CREATE OR REPLACE VIEW pggit.v_complete_system_overview AS
SELECT
    'Operation Performance' as metric_category,
    operation_type as metric_name,
    COUNT(*) as value,
    'metrics' as unit
FROM pggit.performance_metrics
WHERE recorded_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour'
GROUP BY operation_type
UNION ALL
SELECT
    'Monitoring System' as metric_category,
    metric as metric_name,
    COALESCE(critical, warning, active, 0) as value,
    'count' as unit
FROM pggit.v_monitoring_system_health;

GRANT SELECT ON pggit.v_complete_system_overview TO PUBLIC;

COMMENT ON VIEW pggit.v_complete_system_overview IS
'Complete system overview combining operation performance and monitoring system health';
