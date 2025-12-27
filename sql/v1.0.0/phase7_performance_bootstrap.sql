-- ============================================================================
-- Phase 7: Performance Monitoring - Bootstrap Data
-- ============================================================================
-- Description: Initial setup with baseline data from Phase 4/5/6 operations
-- Version: 1.0.0
-- Created: 2025-12-27
-- Purpose: Week 2 integration with existing phases
-- ============================================================================

-- ============================================================================
-- 1. INITIALIZE OPERATION TYPES FROM EXISTING PHASES
-- ============================================================================

-- Phase 1-3: Basic Operations (already bootstrap in schema)
-- Verify they exist
INSERT INTO pggit.performance_operation_types
    (operation_type, description, category, is_tracked)
SELECT
    operation_type, description, category, is_tracked
FROM (
    VALUES
    ('commit', 'Create new commit on branch', 'WRITE', TRUE),
    ('branch_create', 'Create new branch', 'WRITE', TRUE),
    ('branch_delete', 'Delete branch', 'WRITE', TRUE),
    ('branch_checkout', 'Checkout/switch branch', 'WRITE', TRUE),
    ('get_branches', 'List branches', 'READ', TRUE),
    ('get_commits', 'List commits on branch', 'READ', TRUE),
    ('get_objects', 'Query schema objects', 'READ', TRUE)
) t(operation_type, description, category, is_tracked)
ON CONFLICT (operation_type) DO NOTHING;

-- Phase 4: Object History & Audit (History tracking functions)
INSERT INTO pggit.performance_operation_types
    (operation_type, description, category, is_tracked)
SELECT * FROM (
    VALUES
    ('get_history', 'Query object change history', 'READ', TRUE),
    ('get_object_timeline', 'Get timeline of object changes', 'READ', TRUE),
    ('get_object_at_time', 'Retrieve object state at specific time', 'READ', TRUE),
    ('ensure_object', 'Ensure object exists with history', 'WRITE', TRUE),
    ('create_history_partition', 'Create temporal history partition', 'ADMIN', TRUE),
    ('query_temporal_snapshots', 'Query point-in-time snapshots', 'READ', TRUE)
) t(operation_type, description, category, is_tracked)
ON CONFLICT (operation_type) DO NOTHING;

-- Phase 2: Three-Way Merge (will be implemented in next phase)
INSERT INTO pggit.performance_operation_types
    (operation_type, description, category, is_tracked)
SELECT * FROM (
    VALUES
    ('merge_base_find', 'Find lowest common ancestor', 'READ', TRUE),
    ('merge_conflict_detect', 'Detect merge conflicts (6 types)', 'READ', TRUE),
    ('merge_auto_resolve', 'Automatically resolve conflicts', 'WRITE', TRUE)
) t(operation_type, description, category, is_tracked)
ON CONFLICT (operation_type) DO NOTHING;

-- Phase 6: Rollback Operations
INSERT INTO pggit.performance_operation_types
    (operation_type, description, category, is_tracked)
SELECT * FROM (
    VALUES
    ('rollback_commit', 'Rollback single commit', 'WRITE', TRUE),
    ('rollback_cascade', 'Cascade rollback through merges', 'WRITE', TRUE),
    ('rollback_dry_run', 'Simulate rollback without applying', 'READ', TRUE),
    ('rollback_validate', 'Validate rollback safety', 'READ', TRUE),
    ('rollback_recovery', 'Recover from failed rollback', 'WRITE', TRUE)
) t(operation_type, description, category, is_tracked)
ON CONFLICT (operation_type) DO NOTHING;

-- Phase 5: Merge Operations (advanced)
INSERT INTO pggit.performance_operation_types
    (operation_type, description, category, is_tracked)
SELECT * FROM (
    VALUES
    ('merge_branches', 'Execute merge between branches', 'WRITE', TRUE),
    ('merge_data_branches', 'Merge with data branching (COW)', 'WRITE', TRUE),
    ('merge_execute', 'Execute approved merge', 'WRITE', TRUE),
    ('merge_cleanup', 'Cleanup merged branches', 'WRITE', TRUE)
) t(operation_type, description, category, is_tracked)
ON CONFLICT (operation_type) DO NOTHING;

-- Data Operations
INSERT INTO pggit.performance_operation_types
    (operation_type, description, category, is_tracked)
SELECT * FROM (
    VALUES
    ('create_data_branch', 'Create data-only branch (COW)', 'WRITE', TRUE),
    ('apply_data_merge', 'Apply data merge between branches', 'WRITE', TRUE),
    ('compress_branch', 'Compress branch data (deduplication)', 'ADMIN', TRUE),
    ('calculate_branch_size', 'Calculate total branch size', 'READ', TRUE)
) t(operation_type, description, category, is_tracked)
ON CONFLICT (operation_type) DO NOTHING;

-- ============================================================================
-- 2. VERIFY BOOTSTRAP DATA
-- ============================================================================

SELECT COUNT(*) as operation_type_count
FROM pggit.performance_operation_types
WHERE is_tracked = TRUE;

-- ============================================================================
-- 3. CREATE SAMPLE PERFORMANCE DATA FOR TESTING
-- ============================================================================
-- Note: These are realistic timing estimates based on typical pgGit operations
-- Data is marked with specific session for testing/identification

-- Sample metrics for commit operations (should be fast: 1-10ms)
INSERT INTO pggit.performance_metrics
    (operation_type, operation_name, duration_microseconds, duration_ms,
     start_time, end_time, user_name, session_id, period_start, operation_metadata)
SELECT
    'commit',
    'commit_' || i::TEXT,
    (2000 + (RANDOM() * 5000))::BIGINT,
    ((2000 + (RANDOM() * 5000))::BIGINT)::NUMERIC / 1000,
    CURRENT_TIMESTAMP - INTERVAL '7 days' + (i || ' minutes')::INTERVAL,
    CURRENT_TIMESTAMP - INTERVAL '7 days' + (i || ' minutes')::INTERVAL +
        ((((2000 + (RANDOM() * 5000))::BIGINT) || ' microseconds')::INTERVAL),
    'bootstrap_user',
    'bootstrap_session_commit',
    DATE_TRUNC('day', CURRENT_TIMESTAMP),
    jsonb_build_object('ddl_statements', 5, 'dml_statements', 0)
FROM generate_series(1, 20) AS t(i);

-- Sample metrics for merge operations (slower: 30-100ms)
INSERT INTO pggit.performance_metrics
    (operation_type, operation_name, duration_microseconds, duration_ms,
     start_time, end_time, user_name, session_id, period_start, operation_metadata)
SELECT
    'merge_branches',
    'merge_' || i::TEXT,
    (50000 + (RANDOM() * 50000))::BIGINT,
    ((50000 + (RANDOM() * 50000))::BIGINT)::NUMERIC / 1000,
    CURRENT_TIMESTAMP - INTERVAL '7 days' + (i || ' hours')::INTERVAL,
    CURRENT_TIMESTAMP - INTERVAL '7 days' + (i || ' hours')::INTERVAL +
        ((((50000 + (RANDOM() * 50000))::BIGINT) || ' microseconds')::INTERVAL),
    'bootstrap_user',
    'bootstrap_session_merge',
    DATE_TRUNC('day', CURRENT_TIMESTAMP),
    jsonb_build_object('conflict_count', (RANDOM() * 5)::INT, 'auto_resolved', true)
FROM generate_series(1, 15) AS t(i);

-- Sample metrics for get_history operations (variable: 5-50ms)
INSERT INTO pggit.performance_metrics
    (operation_type, operation_name, duration_microseconds, duration_ms,
     start_time, end_time, user_name, session_id, period_start, operation_metadata)
SELECT
    'get_history',
    'get_history_' || i::TEXT,
    (5000 + (RANDOM() * 45000))::BIGINT,
    ((5000 + (RANDOM() * 45000))::BIGINT)::NUMERIC / 1000,
    CURRENT_TIMESTAMP - INTERVAL '7 days' + (i || ' hours')::INTERVAL,
    CURRENT_TIMESTAMP - INTERVAL '7 days' + (i || ' hours')::INTERVAL +
        ((((5000 + (RANDOM() * 45000))::BIGINT) || ' microseconds')::INTERVAL),
    'bootstrap_user',
    'bootstrap_session_history',
    DATE_TRUNC('day', CURRENT_TIMESTAMP),
    jsonb_build_object('rows_returned', (RANDOM() * 1000)::INT)
FROM generate_series(1, 25) AS t(i);

-- Sample metrics for branch operations (fast: 1-5ms)
INSERT INTO pggit.performance_metrics
    (operation_type, operation_name, duration_microseconds, duration_ms,
     start_time, end_time, user_name, session_id, period_start, operation_metadata)
SELECT
    'branch_create',
    'branch_create_' || i::TEXT,
    (1000 + (RANDOM() * 3000))::BIGINT,
    ((1000 + (RANDOM() * 3000))::BIGINT)::NUMERIC / 1000,
    CURRENT_TIMESTAMP - INTERVAL '7 days' + (i || ' hours')::INTERVAL,
    CURRENT_TIMESTAMP - INTERVAL '7 days' + (i || ' hours')::INTERVAL +
        ((((1000 + (RANDOM() * 3000))::BIGINT) || ' microseconds')::INTERVAL),
    'bootstrap_user',
    'bootstrap_session_branches',
    DATE_TRUNC('day', CURRENT_TIMESTAMP),
    jsonb_build_object('parent_branch', 'main')
FROM generate_series(1, 12) AS t(i);

-- Sample metrics for rollback operations (variable: 10-200ms)
INSERT INTO pggit.performance_metrics
    (operation_type, operation_name, duration_microseconds, duration_ms,
     start_time, end_time, user_name, session_id, period_start, operation_metadata)
SELECT
    'rollback_commit',
    'rollback_' || i::TEXT,
    (20000 + (RANDOM() * 180000))::BIGINT,
    ((20000 + (RANDOM() * 180000))::BIGINT)::NUMERIC / 1000,
    CURRENT_TIMESTAMP - INTERVAL '7 days' + (i || ' hours')::INTERVAL,
    CURRENT_TIMESTAMP - INTERVAL '7 days' + (i || ' hours')::INTERVAL +
        ((((20000 + (RANDOM() * 180000))::BIGINT) || ' microseconds')::INTERVAL),
    'bootstrap_user',
    'bootstrap_session_rollback',
    DATE_TRUNC('day', CURRENT_TIMESTAMP),
    jsonb_build_object('affected_objects', (RANDOM() * 50)::INT, 'cascade_depth', (RANDOM() * 3)::INT)
FROM generate_series(1, 10) AS t(i);

-- ============================================================================
-- 4. CALCULATE INITIAL BASELINES FROM BOOTSTRAP DATA
-- ============================================================================
-- These will serve as the first SLA thresholds

-- Commit baseline (should be ~4ms)
SELECT pggit.calculate_performance_baseline(
    p_operation_type := 'commit',
    p_branch_id := NULL,
    p_lookback_days := 7,
    p_alert_threshold_multiplier := 2.5
);

-- Merge baseline (should be ~75ms)
SELECT pggit.calculate_performance_baseline(
    p_operation_type := 'merge_branches',
    p_branch_id := NULL,
    p_lookback_days := 7,
    p_alert_threshold_multiplier := 2.0
);

-- Get history baseline (should be ~25ms)
SELECT pggit.calculate_performance_baseline(
    p_operation_type := 'get_history',
    p_branch_id := NULL,
    p_lookback_days := 7,
    p_alert_threshold_multiplier := 2.0
);

-- Branch create baseline (should be ~2.5ms)
SELECT pggit.calculate_performance_baseline(
    p_operation_type := 'branch_create',
    p_branch_id := NULL,
    p_lookback_days := 7,
    p_alert_threshold_multiplier := 3.0
);

-- Rollback baseline (should be ~100ms)
SELECT pggit.calculate_performance_baseline(
    p_operation_type := 'rollback_commit',
    p_branch_id := NULL,
    p_lookback_days := 7,
    p_alert_threshold_multiplier := 2.0
);

-- ============================================================================
-- 5. CREATE SAMPLE DISTRIBUTED TRACES
-- ============================================================================
-- Demonstrate trace hierarchy for a complex merge workflow

-- Create parent trace for merge workflow
INSERT INTO pggit.operation_traces
    (trace_id, span_id, parent_span_id, operation_type, span_name, span_status,
     start_time, end_time, duration_microseconds, user_name, session_id)
VALUES
    (
        'trace_merge_001',
        'span_merge_workflow_001',
        NULL,
        'merge_workflow',
        'merge_feature_to_main_workflow',
        'SUCCESS',
        CURRENT_TIMESTAMP - INTERVAL '2 hours',
        CURRENT_TIMESTAMP - INTERVAL '2 hours' + INTERVAL '100ms',
        100000,
        'bootstrap_user',
        'bootstrap_trace_merge_1'
    );

-- Phase 1: Find merge base (LCA)
INSERT INTO pggit.operation_traces
    (trace_id, span_id, parent_span_id, operation_type, span_name, span_status,
     start_time, end_time, duration_microseconds, user_name, session_id, attributes)
VALUES
    (
        'trace_merge_001',
        'span_merge_phase1_lca',
        'span_merge_workflow_001',
        'merge_workflow',
        'find_merge_base_lca',
        'SUCCESS',
        CURRENT_TIMESTAMP - INTERVAL '2 hours',
        CURRENT_TIMESTAMP - INTERVAL '2 hours' + INTERVAL '5ms',
        5000,
        'bootstrap_user',
        'bootstrap_trace_merge_1',
        jsonb_build_object('algorithm', 'lowest_common_ancestor', 'branches', 2)
    );

-- Phase 2: Detect conflicts
INSERT INTO pggit.operation_traces
    (trace_id, span_id, parent_span_id, operation_type, span_name, span_status,
     start_time, end_time, duration_microseconds, user_name, session_id, attributes)
VALUES
    (
        'trace_merge_001',
        'span_merge_phase2_conflict',
        'span_merge_workflow_001',
        'merge_workflow',
        'conflict_detection_6_types',
        'SUCCESS',
        CURRENT_TIMESTAMP - INTERVAL '2 hours' + INTERVAL '5ms',
        CURRENT_TIMESTAMP - INTERVAL '2 hours' + INTERVAL '45ms',
        40000,
        'bootstrap_user',
        'bootstrap_trace_merge_1',
        jsonb_build_object('conflict_count', 3, 'types', array['structural', 'semantic', 'data'])
    );

-- Phase 3: Auto resolution attempt
INSERT INTO pggit.operation_traces
    (trace_id, span_id, parent_span_id, operation_type, span_name, span_status,
     start_time, end_time, duration_microseconds, user_name, session_id, attributes)
VALUES
    (
        'trace_merge_001',
        'span_merge_phase3_resolve',
        'span_merge_workflow_001',
        'merge_workflow',
        'auto_resolution_attempt',
        'SUCCESS',
        CURRENT_TIMESTAMP - INTERVAL '2 hours' + INTERVAL '45ms',
        CURRENT_TIMESTAMP - INTERVAL '2 hours' + INTERVAL '100ms',
        55000,
        'bootstrap_user',
        'bootstrap_trace_merge_1',
        jsonb_build_object('resolved_automatically', 2, 'required_manual', 1)
    );

-- ============================================================================
-- 6. CREATE SAMPLE ALERTS FROM ANOMALIES
-- ============================================================================
-- Insert a few sample alerts to show alert workflow

-- Find a slow operation to create an alert for
WITH slow_op AS (
    SELECT metric_id, operation_type, duration_microseconds
    FROM pggit.performance_metrics
    WHERE operation_type = 'rollback_commit'
    ORDER BY duration_microseconds DESC
    LIMIT 1
)
INSERT INTO pggit.performance_alerts
    (metric_id, operation_type, alert_type, severity,
     baseline_p99_microseconds, actual_duration_microseconds,
     violation_multiplier, user_name)
SELECT
    slow_op.metric_id,
    slow_op.operation_type,
    'THRESHOLD_EXCEEDED',
    CASE WHEN slow_op.duration_microseconds > 150000 THEN 'CRITICAL' ELSE 'WARNING' END,
    100000,  -- Baseline p99
    slow_op.duration_microseconds,
    (slow_op.duration_microseconds::NUMERIC / 100000),
    'bootstrap_user'
FROM slow_op
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 7. SUMMARY STATISTICS
-- ============================================================================

-- Show bootstrap data overview
DO $$
DECLARE
    v_metric_count INTEGER;
    v_baseline_count INTEGER;
    v_alert_count INTEGER;
    v_trace_count INTEGER;
    v_operation_type_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_metric_count FROM pggit.performance_metrics;
    SELECT COUNT(*) INTO v_baseline_count FROM pggit.performance_baselines WHERE is_active = TRUE;
    SELECT COUNT(*) INTO v_alert_count FROM pggit.performance_alerts;
    SELECT COUNT(*) INTO v_trace_count FROM pggit.operation_traces;
    SELECT COUNT(*) INTO v_operation_type_count FROM pggit.performance_operation_types WHERE is_tracked = TRUE;

    RAISE NOTICE '
╔════════════════════════════════════════════════════════════╗
║         PHASE 7 BOOTSTRAP DATA - INITIALIZATION COMPLETE   ║
╠════════════════════════════════════════════════════════════╣
║ Operation Types Defined:        % │ (tracked)              ║
║ Performance Metrics Recorded:    % │                        ║
║ Active Performance Baselines:    % │                        ║
║ Sample Alerts Generated:         % │                        ║
║ Distributed Trace Spans:         % │                        ║
╚════════════════════════════════════════════════════════════╝
    ',
    v_operation_type_count,
    v_metric_count,
    v_baseline_count,
    v_alert_count,
    v_trace_count;
END $$;

-- Final verification queries
SELECT
    'Performance Metrics' as metric,
    COUNT(*) as count,
    (MIN(duration_microseconds) / 1000)::NUMERIC(10,1) as min_ms,
    (AVG(duration_microseconds) / 1000)::NUMERIC(10,1) as avg_ms,
    (MAX(duration_microseconds) / 1000)::NUMERIC(10,1) as max_ms
FROM pggit.performance_metrics
GROUP BY 1

UNION ALL

SELECT
    'Active Baselines' as metric,
    COUNT(*) as count,
    NULL as min_ms,
    NULL as avg_ms,
    NULL as max_ms
FROM pggit.performance_baselines
WHERE is_active = TRUE

UNION ALL

SELECT
    'Performance Alerts' as metric,
    COUNT(*) as count,
    NULL as min_ms,
    NULL as avg_ms,
    NULL as max_ms
FROM pggit.performance_alerts

UNION ALL

SELECT
    'Operation Traces' as metric,
    COUNT(*) as count,
    NULL as min_ms,
    NULL as avg_ms,
    NULL as max_ms
FROM pggit.operation_traces;

-- ============================================================================
-- BOOTSTRAP SUMMARY
-- ============================================================================
-- Created:
-- ✅ 21 standard operation types across all phases
-- ✅ 82 sample performance metrics (realistic timings)
-- ✅ 5 performance baselines (p50, p75, p90, p95, p99)
-- ✅ 1+ sample performance alerts
-- ✅ Multi-level distributed trace with parent-child spans
--
-- Ready for:
-- - Week 2: Phase 4 and Phase 6 integration
-- - Week 3: Automated baseline recalculation
-- - Week 4: Dashboard deployment and optimization
-- ============================================================================
