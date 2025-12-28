-- ============================================================================
-- Phase 7: Performance Monitoring - Dashboard Views
-- ============================================================================
-- Description: Pre-built views for real-time performance dashboards
-- Version: 1.0.0
-- Created: 2025-12-27
-- ============================================================================

-- ============================================================================
-- 1. REAL-TIME DASHBOARDS
-- ============================================================================

-- v_performance_dashboard_summary: Real-time performance overview
CREATE OR REPLACE VIEW pggit.v_performance_dashboard_summary AS
SELECT
    'Performance Summary' as dashboard_name,
    (SELECT COUNT(*) FROM pggit.performance_metrics) as total_metrics_recorded,
    (SELECT COUNT(*) FROM pggit.operation_traces) as total_traces,
    (SELECT COUNT(*) FROM pggit.performance_baselines WHERE is_active = TRUE) as active_baselines,
    (SELECT COUNT(*) FROM pggit.performance_alerts WHERE is_acknowledged = FALSE) as unacknowledged_alerts,
    (SELECT COUNT(*) FROM pggit.performance_alerts WHERE is_acknowledged = FALSE AND severity = 'CRITICAL') as critical_alerts,
    (SELECT CURRENT_TIMESTAMP) as dashboard_updated_at;

-- v_operation_performance_summary: Performance by operation type
CREATE OR REPLACE VIEW pggit.v_operation_performance_summary AS
SELECT
    pm.operation_type,
    COUNT(*)::INTEGER as execution_count,
    (AVG(pm.duration_microseconds) / 1000)::NUMERIC(10,3) as avg_ms,
    (PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY pm.duration_microseconds) / 1000)::NUMERIC(10,3) as p50_ms,
    (PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY pm.duration_microseconds) / 1000)::NUMERIC(10,3) as p99_ms,
    (MIN(pm.duration_microseconds) / 1000)::NUMERIC(10,3) as min_ms,
    (MAX(pm.duration_microseconds) / 1000)::NUMERIC(10,3) as max_ms,
    MAX(pm.recorded_at) as last_execution,
    pb.p99_microseconds / 1000 as baseline_p99_ms,
    CASE
        WHEN MAX(pm.duration_microseconds) > pb.p99_microseconds * pb.alert_threshold_multiplier
        THEN 'VIOLATION'
        ELSE 'OK'
    END as status
FROM pggit.performance_metrics pm
LEFT JOIN pggit.performance_baselines pb
    ON pm.operation_type = pb.operation_type
    AND pb.is_active = TRUE
GROUP BY pm.operation_type, pb.p99_microseconds, pb.alert_threshold_multiplier
ORDER BY execution_count DESC;

-- v_branch_performance_summary: Performance metrics by branch
CREATE OR REPLACE VIEW pggit.v_branch_performance_summary AS
SELECT
    b.branch_id as branch_id,
    b.branch_name as branch_name,
    COUNT(pm.metric_id)::INTEGER as operation_count,
    COUNT(DISTINCT pm.operation_type)::INTEGER as operation_types,
    (AVG(pm.duration_microseconds) / 1000)::NUMERIC(10,3) as avg_duration_ms,
    (PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY pm.duration_microseconds) / 1000)::NUMERIC(10,3) as p99_ms,
    MAX(pm.recorded_at) as last_operation
FROM pggit.branches b
LEFT JOIN pggit.performance_metrics pm ON b.branch_id = pm.branch_id
GROUP BY b.branch_id, b.branch_name
ORDER BY operation_count DESC;

-- ============================================================================
-- 2. ALERT DASHBOARDS
-- ============================================================================

-- v_performance_alerts_recent: Recent performance alerts
CREATE OR REPLACE VIEW pggit.v_performance_alerts_recent AS
SELECT
    pa.alert_id,
    pa.operation_type,
    pa.severity,
    pa.alert_type,
    (pa.actual_duration_microseconds / 1000)::NUMERIC(10,3) as actual_duration_ms,
    (pa.baseline_p99_microseconds / 1000)::NUMERIC(10,3) as baseline_p99_ms,
    pa.violation_multiplier as multiplier_over_baseline,
    pa.user_name,
    pa.created_at,
    pa.is_acknowledged,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - pa.created_at)) / 60 as minutes_ago
FROM pggit.performance_alerts pa
ORDER BY pa.created_at DESC
LIMIT 100;

-- v_performance_alerts_critical: Critical unacknowledged alerts
CREATE OR REPLACE VIEW pggit.v_performance_alerts_critical AS
SELECT
    pa.alert_id,
    pa.operation_type,
    (pa.actual_duration_microseconds / 1000)::NUMERIC(10,3) as actual_duration_ms,
    (pa.baseline_p99_microseconds / 1000)::NUMERIC(10,3) as baseline_p99_ms,
    ROUND((pa.violation_multiplier - 1) * 100, 1) as percent_over_baseline,
    pa.user_name,
    pa.created_at,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - pa.created_at)) / 60 as minutes_unacknowledged
FROM pggit.performance_alerts pa
WHERE pa.severity = 'CRITICAL'
  AND pa.is_acknowledged = FALSE
ORDER BY pa.created_at DESC;

-- ============================================================================
-- 3. TRACE ANALYSIS VIEWS
-- ============================================================================

-- v_trace_hierarchy: View trace parent-child relationships
CREATE OR REPLACE VIEW pggit.v_trace_hierarchy AS
WITH RECURSIVE trace_tree AS (
    -- Anchor: root spans (no parent)
    SELECT
        trace_id, span_id, parent_span_id, span_name, operation_type, span_status,
        (EXTRACT(EPOCH FROM (end_time - start_time)) * 1000000)::BIGINT as duration_us,
        1 as depth,
        CONCAT(span_name) as trace_path
    FROM pggit.operation_traces
    WHERE parent_span_id IS NULL

    UNION ALL

    -- Recursive: child spans
    SELECT
        ot.trace_id, ot.span_id, ot.parent_span_id, ot.span_name, ot.operation_type, ot.span_status,
        (EXTRACT(EPOCH FROM (ot.end_time - ot.start_time)) * 1000000)::BIGINT as duration_us,
        tt.depth + 1,
        CONCAT(tt.trace_path, ' → ', ot.span_name)
    FROM pggit.operation_traces ot
    JOIN trace_tree tt ON ot.parent_span_id = tt.span_id
    WHERE ot.parent_span_id IS NOT NULL
)
SELECT
    trace_id, span_id, parent_span_id, span_name, operation_type, span_status,
    (duration_us / 1000)::NUMERIC(10,3) as duration_ms,
    depth, trace_path
FROM trace_tree
ORDER BY trace_id, depth, span_id;

-- ============================================================================
-- 4. MERGE PERFORMANCE VIEWS
-- ============================================================================

-- v_merge_performance_summary: Merge operation performance analysis
CREATE OR REPLACE VIEW pggit.v_merge_performance_summary AS
SELECT
    mpm.merge_metric_id,
    sb.branch_name as source_branch,
    tb.branch_name as target_branch,
    (mpm.total_merge_us / 1000)::NUMERIC(10,3) as total_duration_ms,
    (mpm.merge_base_calculation_us / 1000)::NUMERIC(10,3) as merge_base_calc_ms,
    (mpm.conflict_detection_us / 1000)::NUMERIC(10,3) as conflict_detect_ms,
    mpm.conflict_count,
    (mpm.auto_resolution_us / 1000)::NUMERIC(10,3) as auto_resolution_ms,
    mpm.auto_resolution_success_count + mpm.auto_resolution_failure_count as total_conflicts_resolved,
    ROUND(100.0 * mpm.auto_resolution_success_count / NULLIF(mpm.auto_resolution_success_count + mpm.auto_resolution_failure_count, 0), 1) as auto_resolution_success_rate,
    mpm.merge_status,
    mpm.user_name,
    mpm.started_at,
    mpm.completed_at
FROM pggit.merge_performance_metrics mpm
JOIN pggit.branches sb ON mpm.source_branch_id = sb.branch_id
JOIN pggit.branches tb ON mpm.target_branch_id = tb.branch_id
ORDER BY mpm.started_at DESC;

-- v_merge_statistics: Aggregate merge statistics
CREATE OR REPLACE VIEW pggit.v_merge_statistics AS
SELECT
    sb.branch_name as source_branch,
    tb.branch_name as target_branch,
    COUNT(*) as merge_count,
    (AVG(mpm.total_merge_us) / 1000)::NUMERIC(10,3) as avg_duration_ms,
    (MAX(mpm.total_merge_us) / 1000)::NUMERIC(10,3) as max_duration_ms,
    (MIN(mpm.total_merge_us) / 1000)::NUMERIC(10,3) as min_duration_ms,
    AVG(mpm.conflict_count)::NUMERIC(4,1) as avg_conflicts,
    MAX(mpm.conflict_count) as max_conflicts,
    SUM(CASE WHEN mpm.merge_status = 'SUCCESS' THEN 1 ELSE 0 END) as successful_merges,
    SUM(CASE WHEN mpm.merge_status = 'FAILED' THEN 1 ELSE 0 END) as failed_merges,
    MAX(mpm.completed_at) as last_merge
FROM pggit.merge_performance_metrics mpm
JOIN pggit.branches sb ON mpm.source_branch_id = sb.branch_id
JOIN pggit.branches tb ON mpm.target_branch_id = tb.branch_id
GROUP BY sb.branch_name, tb.branch_name
ORDER BY merge_count DESC;

-- ============================================================================
-- 5. TREND & ANALYSIS VIEWS
-- ============================================================================

-- v_performance_trend_hourly: Hourly performance trend
CREATE OR REPLACE VIEW pggit.v_performance_trend_hourly AS
SELECT
    pm.operation_type,
    DATE_TRUNC('hour', pm.recorded_at)::TIMESTAMP as hour,
    COUNT(*)::INTEGER as execution_count,
    (AVG(pm.duration_microseconds) / 1000)::NUMERIC(10,3) as avg_ms,
    (PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY pm.duration_microseconds) / 1000)::NUMERIC(10,3) as p99_ms
FROM pggit.performance_metrics pm
WHERE pm.recorded_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
GROUP BY pm.operation_type, DATE_TRUNC('hour', pm.recorded_at)
ORDER BY hour DESC, execution_count DESC;

-- v_slowest_operations_last_24h: Top slowest operations in last 24 hours
CREATE OR REPLACE VIEW pggit.v_slowest_operations_last_24h AS
SELECT
    pm.metric_id,
    pm.operation_type,
    (pm.duration_microseconds / 1000)::NUMERIC(10,3) as duration_ms,
    pm.user_name,
    pm.recorded_at,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - pm.recorded_at)) / 3600 as hours_ago,
    pb.p99_microseconds / 1000 as baseline_p99_ms,
    ROUND((pm.duration_microseconds::NUMERIC / NULLIF(pb.p99_microseconds, 0)) - 1, 2) * 100 as percent_over_baseline
FROM pggit.performance_metrics pm
LEFT JOIN pggit.performance_baselines pb
    ON pm.operation_type = pb.operation_type
    AND pb.is_active = TRUE
WHERE pm.recorded_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
ORDER BY pm.duration_microseconds DESC
LIMIT 50;

-- ============================================================================
-- 6. BASELINE TRACKING VIEWS
-- ============================================================================

-- v_baseline_health: Baseline effectiveness and coverage
CREATE OR REPLACE VIEW pggit.v_baseline_health AS
SELECT
    pb.operation_type,
    pb.baseline_date,
    pb.sample_count,
    (pb.p99_microseconds / 1000)::NUMERIC(10,3) as p99_ms,
    (pb.alert_threshold_multiplier - 1) * 100 as alert_threshold_percent,
    COUNT(DISTINCT pa.alert_id) as alerts_generated,
    pb.is_active,
    EXTRACT(DAYS FROM CURRENT_TIMESTAMP - pb.calculation_timestamp) as days_since_calculation
FROM pggit.performance_baselines pb
LEFT JOIN pggit.performance_alerts pa
    ON pb.baseline_id = pa.baseline_id
    AND pa.created_at >= pb.calculation_timestamp
GROUP BY pb.baseline_id, pb.operation_type, pb.baseline_date, pb.sample_count,
         pb.p99_microseconds, pb.alert_threshold_multiplier, pb.is_active,
         pb.calculation_timestamp
ORDER BY pb.operation_type, pb.calculation_timestamp DESC;

-- ============================================================================
-- 7. USER ACTIVITY VIEWS
-- ============================================================================

-- v_user_performance_activity: Performance metrics by user
CREATE OR REPLACE VIEW pggit.v_user_performance_activity AS
SELECT
    pm.user_name,
    COUNT(*)::INTEGER as operations_performed,
    COUNT(DISTINCT pm.operation_type)::INTEGER as operation_types,
    (AVG(pm.duration_microseconds) / 1000)::NUMERIC(10,3) as avg_operation_ms,
    (SUM(pm.duration_microseconds) / 1000000.0)::NUMERIC(12,2) as total_time_seconds,
    COUNT(pa.alert_id) as alerts_triggered,
    MAX(pm.recorded_at) as last_operation
FROM pggit.performance_metrics pm
LEFT JOIN pggit.performance_alerts pa
    ON pm.metric_id = pa.metric_id
GROUP BY pm.user_name
ORDER BY operations_performed DESC;

-- ============================================================================
-- Summary
-- ============================================================================
-- Total views: 17
-- - Dashboards: 3
-- - Alerts: 2
-- - Tracing: 1
-- - Merge analysis: 2
-- - Trends: 2
-- - Baselines: 1
-- - User activity: 1
-- ============================================================================
