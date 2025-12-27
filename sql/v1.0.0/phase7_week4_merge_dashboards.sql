-- ============================================================================
-- Phase 7: Week 4 - Merge-Specific Performance Dashboards
-- ============================================================================
-- Purpose: Specialized views for analyzing merge operation performance bottlenecks
-- Date: 2025-12-27
-- Status: Production-ready implementation
-- ============================================================================

-- ============================================================================
-- TABLE DEFINITIONS: Supporting tables for merge analysis
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.merge_performance_analysis (
    analysis_id BIGSERIAL PRIMARY KEY,
    merge_id INTEGER NOT NULL,
    branch_from TEXT NOT NULL,
    branch_into TEXT NOT NULL,

    -- Phase timings (milliseconds)
    lca_find_ms NUMERIC,
    conflict_detect_ms NUMERIC,
    auto_resolve_ms NUMERIC,
    total_merge_ms NUMERIC,

    -- Bottleneck identification
    primary_bottleneck TEXT,          -- Which phase is slowest
    lca_percentage NUMERIC,
    conflict_detect_percentage NUMERIC,
    resolution_percentage NUMERIC,

    -- Success metrics
    resolution_strategy TEXT,         -- 'auto', 'manual', 'rejected'
    conflict_count INTEGER,
    auto_resolved_count INTEGER,

    -- SLA compliance
    sla_status TEXT,                  -- 'OK', 'DEGRADED', 'CRITICAL'
    baseline_p99_ms NUMERIC,
    deviation_percent NUMERIC,

    -- Metadata
    analyzed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT bottleneck_check CHECK (
        primary_bottleneck IN ('LCA_FINDING', 'CONFLICT_DETECTION', 'CONFLICT_RESOLUTION', 'UNKNOWN')
    ),
    CONSTRAINT sla_status_check CHECK (
        sla_status IN ('OK', 'DEGRADED', 'CRITICAL')
    )
);

CREATE INDEX idx_merge_perf_analysis_branch_pair
    ON pggit.merge_performance_analysis(branch_from, branch_into, analyzed_at DESC);
CREATE INDEX idx_merge_perf_analysis_bottleneck
    ON pggit.merge_performance_analysis(primary_bottleneck, analyzed_at DESC);
CREATE INDEX idx_merge_perf_analysis_sla
    ON pggit.merge_performance_analysis(sla_status, analyzed_at DESC);

-- ============================================================================
-- VIEW 1: v_merge_bottleneck_analysis
-- ============================================================================
-- Purpose: Identify which phase is the bottleneck for each merge
-- Shows: Merge phases with durations and percentage breakdown
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_merge_bottleneck_analysis AS
WITH merge_phases AS (
    SELECT
        mr.merge_id,
        mr.branch_from,
        mr.branch_into,
        mr.created_at as merge_start,

        -- Extract phase timings from performance metrics
        (SELECT MAX(duration_ms)
         FROM pggit.performance_metrics
         WHERE operation_type = 'merge_base_find'
           AND distributed_trace_parent_id = mr.merge_id) as lca_find_ms,

        (SELECT MAX(duration_ms)
         FROM pggit.performance_metrics
         WHERE operation_type = 'merge_conflict_detect'
           AND distributed_trace_parent_id = mr.merge_id) as conflict_detect_ms,

        (SELECT MAX(duration_ms)
         FROM pggit.performance_metrics
         WHERE operation_type = 'merge_auto_resolve'
           AND distributed_trace_parent_id = mr.merge_id) as auto_resolve_ms,

        -- Total merge time
        (SELECT MAX(duration_ms)
         FROM pggit.performance_metrics
         WHERE operation_type = 'merge_branches'
           AND distributed_trace_id = mr.merge_id) as total_merge_ms,

        -- Baseline for SLA comparison
        (SELECT p99_microseconds / 1000.0
         FROM pggit.performance_baselines
         WHERE operation_type = 'merge_branches'
           AND is_active = TRUE
         LIMIT 1) as baseline_p99_ms
    FROM pggit.merge_relationships mr
    WHERE mr.created_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
)
SELECT
    merge_id,
    branch_from,
    branch_into,
    merge_start,

    -- Phase timings
    ROUND(lca_find_ms::NUMERIC, 1) as lca_find_ms,
    ROUND(conflict_detect_ms::NUMERIC, 1) as conflict_detect_ms,
    ROUND(auto_resolve_ms::NUMERIC, 1) as auto_resolve_ms,
    ROUND(total_merge_ms::NUMERIC, 1) as total_merge_ms,

    -- Identify bottleneck
    CASE
        WHEN lca_find_ms > conflict_detect_ms AND lca_find_ms > auto_resolve_ms
        THEN 'LCA_FINDING'
        WHEN conflict_detect_ms > lca_find_ms AND conflict_detect_ms > auto_resolve_ms
        THEN 'CONFLICT_DETECTION'
        WHEN auto_resolve_ms > lca_find_ms AND auto_resolve_ms > conflict_detect_ms
        THEN 'CONFLICT_RESOLUTION'
        ELSE 'UNKNOWN'
    END as primary_bottleneck,

    -- Percentage breakdown
    ROUND(100.0 * lca_find_ms / NULLIF(total_merge_ms, 0), 1) as lca_percent,
    ROUND(100.0 * conflict_detect_ms / NULLIF(total_merge_ms, 0), 1) as conflict_detect_percent,
    ROUND(100.0 * auto_resolve_ms / NULLIF(total_merge_ms, 0), 1) as resolution_percent,

    -- SLA compliance
    baseline_p99_ms,
    ROUND(100.0 * (total_merge_ms - baseline_p99_ms) / NULLIF(baseline_p99_ms, 0), 1) as deviation_percent,
    CASE
        WHEN total_merge_ms <= baseline_p99_ms THEN 'OK'
        WHEN total_merge_ms <= baseline_p99_ms * 1.5 THEN 'DEGRADED'
        ELSE 'CRITICAL'
    END as sla_status

FROM merge_phases
WHERE total_merge_ms IS NOT NULL
ORDER BY total_merge_ms DESC;

-- ============================================================================
-- VIEW 2: v_merge_success_rate_analysis
-- ============================================================================
-- Purpose: Track merge success rates (auto-resolved vs manual vs rejected)
-- Shows: Hourly breakdown of merge outcomes and performance
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_merge_success_rate_analysis AS
WITH merge_attempts AS (
    SELECT
        DATE_TRUNC('hour', mr.created_at) as hour,
        COUNT(*) as total_attempts,
        SUM(CASE WHEN mr.resolution_strategy = 'auto' THEN 1 ELSE 0 END) as auto_resolved,
        SUM(CASE WHEN mr.resolution_strategy = 'manual' THEN 1 ELSE 0 END) as manual_resolved,
        SUM(CASE WHEN mr.resolution_strategy = 'rejected' THEN 1 ELSE 0 END) as rejected,

        -- Performance metrics
        AVG((SELECT MAX(duration_ms)
             FROM pggit.performance_metrics pm
             WHERE pm.operation_type = 'merge_branches'
               AND pm.distributed_trace_id = mr.merge_id)) as avg_merge_time_ms,

        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY (
            SELECT MAX(duration_ms)
            FROM pggit.performance_metrics pm
            WHERE pm.operation_type = 'merge_branches'
              AND pm.distributed_trace_id = mr.merge_id
        )) as p99_merge_time_ms,

        -- Conflict analysis
        COUNT(CASE WHEN mr.status = 'CONFLICT' THEN 1 END) as conflict_count
    FROM pggit.merge_relationships mr
    WHERE mr.created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
    GROUP BY DATE_TRUNC('hour', mr.created_at)
)
SELECT
    hour,
    total_attempts,
    auto_resolved,
    manual_resolved,
    rejected,

    -- Success rates
    ROUND(100.0 * auto_resolved / NULLIF(total_attempts, 0), 1) as auto_resolve_rate_percent,
    ROUND(100.0 * manual_resolved / NULLIF(total_attempts, 0), 1) as manual_resolve_rate_percent,
    ROUND(100.0 * rejected / NULLIF(total_attempts, 0), 1) as rejection_rate_percent,

    -- Performance metrics
    ROUND(avg_merge_time_ms::NUMERIC, 1) as avg_merge_ms,
    ROUND(p99_merge_time_ms::NUMERIC, 1) as p99_merge_ms,

    -- Conflict metrics
    conflict_count,
    ROUND(100.0 * conflict_count / NULLIF(total_attempts, 0), 1) as conflict_rate_percent

FROM merge_attempts
ORDER BY hour DESC;

-- ============================================================================
-- VIEW 3: v_merge_conflict_hotspots
-- ============================================================================
-- Purpose: Identify branch pairs with high conflict rates
-- Shows: Which branch combinations frequently conflict
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_merge_conflict_hotspots AS
SELECT
    mr.branch_from,
    mr.branch_into,
    COUNT(*) as merge_attempts,
    SUM(CASE WHEN mr.status = 'CONFLICT' THEN 1 ELSE 0 END) as conflict_count,

    -- Conflict rate
    ROUND(100.0 * SUM(CASE WHEN mr.status = 'CONFLICT' THEN 1 ELSE 0 END) /
          NULLIF(COUNT(*), 0), 1) as conflict_rate_percent,

    -- Performance impact of conflicts
    AVG(CASE WHEN mr.status = 'CONFLICT'
        THEN (SELECT MAX(duration_ms)
              FROM pggit.performance_metrics
              WHERE operation_type = 'merge_branches'
                AND distributed_trace_id = mr.merge_id)
    END) as avg_conflict_resolve_ms,

    MAX(CASE WHEN mr.status = 'CONFLICT'
        THEN (SELECT MAX(duration_ms)
              FROM pggit.performance_metrics
              WHERE operation_type = 'merge_branches'
                AND distributed_trace_id = mr.merge_id)
    END) as max_conflict_resolve_ms,

    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY
        CASE WHEN mr.status = 'CONFLICT'
        THEN (SELECT MAX(duration_ms)
              FROM pggit.performance_metrics
              WHERE operation_type = 'merge_branches'
                AND distributed_trace_id = mr.merge_id)
        END
    ) as p99_conflict_resolve_ms,

    -- Auto-resolution rate for conflicts
    SUM(CASE WHEN mr.status = 'CONFLICT' AND mr.resolution_strategy = 'auto' THEN 1 ELSE 0 END) as auto_resolved_conflicts,
    SUM(CASE WHEN mr.status = 'CONFLICT' AND mr.resolution_strategy = 'manual' THEN 1 ELSE 0 END) as manual_resolved_conflicts

FROM pggit.merge_relationships mr
WHERE mr.created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
GROUP BY mr.branch_from, mr.branch_into
HAVING SUM(CASE WHEN mr.status = 'CONFLICT' THEN 1 ELSE 0 END) > 0
ORDER BY conflict_rate_percent DESC, merge_attempts DESC;

-- ============================================================================
-- VIEW 4: v_merge_phase_timeline
-- ============================================================================
-- Purpose: Time-series view of merge phases for trend analysis
-- Shows: How each phase performs over time
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_merge_phase_timeline AS
WITH phase_metrics AS (
    SELECT
        DATE_TRUNC('hour', pm.recorded_at) as hour_window,
        pm.operation_type,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY pm.duration_ms) as p50_ms,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY pm.duration_ms) as p75_ms,
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY pm.duration_ms) as p90_ms,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY pm.duration_ms) as p99_ms,
        COUNT(*) as sample_count
    FROM pggit.performance_metrics pm
    WHERE pm.operation_type LIKE 'merge_%'
      AND pm.recorded_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
    GROUP BY DATE_TRUNC('hour', pm.recorded_at), pm.operation_type
)
SELECT
    hour_window,
    'LCA Finding' as phase,
    p50_ms, p75_ms, p90_ms, p99_ms, sample_count
FROM phase_metrics
WHERE operation_type = 'merge_base_find'

UNION ALL

SELECT
    hour_window,
    'Conflict Detection' as phase,
    p50_ms, p75_ms, p90_ms, p99_ms, sample_count
FROM phase_metrics
WHERE operation_type = 'merge_conflict_detect'

UNION ALL

SELECT
    hour_window,
    'Resolution' as phase,
    p50_ms, p75_ms, p90_ms, p99_ms, sample_count
FROM phase_metrics
WHERE operation_type = 'merge_auto_resolve'

ORDER BY hour_window DESC, phase;

-- ============================================================================
-- VIEW 5: v_merge_performance_by_branch
-- ============================================================================
-- Purpose: Per-branch merge performance statistics
-- Shows: How branches perform as source vs target
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_merge_performance_by_branch AS
WITH branch_stats AS (
    SELECT
        'source' as role,
        mr.branch_from as branch,
        COUNT(*) as merge_count,
        AVG((SELECT MAX(duration_ms)
             FROM pggit.performance_metrics
             WHERE operation_type = 'merge_branches'
               AND distributed_trace_id = mr.merge_id)) as avg_time_ms,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY (
            SELECT MAX(duration_ms)
            FROM pggit.performance_metrics
            WHERE operation_type = 'merge_branches'
              AND distributed_trace_id = mr.merge_id
        )) as p99_time_ms,
        SUM(CASE WHEN mr.status = 'CONFLICT' THEN 1 ELSE 0 END) as conflict_count
    FROM pggit.merge_relationships mr
    WHERE mr.created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    GROUP BY mr.branch_from

    UNION ALL

    SELECT
        'target' as role,
        mr.branch_into as branch,
        COUNT(*) as merge_count,
        AVG((SELECT MAX(duration_ms)
             FROM pggit.performance_metrics
             WHERE operation_type = 'merge_branches'
               AND distributed_trace_id = mr.merge_id)) as avg_time_ms,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY (
            SELECT MAX(duration_ms)
            FROM pggit.performance_metrics
            WHERE operation_type = 'merge_branches'
              AND distributed_trace_id = mr.merge_id
        )) as p99_time_ms,
        SUM(CASE WHEN mr.status = 'CONFLICT' THEN 1 ELSE 0 END) as conflict_count
    FROM pggit.merge_relationships mr
    WHERE mr.created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    GROUP BY mr.branch_into
)
SELECT
    role,
    branch,
    merge_count,
    ROUND(avg_time_ms::NUMERIC, 1) as avg_merge_ms,
    ROUND(p99_time_ms::NUMERIC, 1) as p99_merge_ms,
    conflict_count,
    ROUND(100.0 * conflict_count / NULLIF(merge_count, 0), 1) as conflict_rate_percent
FROM branch_stats
ORDER BY merge_count DESC, p99_time_ms DESC;

-- ============================================================================
-- VIEW 6: v_merge_resolution_effectiveness
-- ============================================================================
-- Purpose: Track auto-resolution effectiveness and improvement opportunities
-- Shows: How effective automated conflict resolution is
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_merge_resolution_effectiveness AS
WITH resolution_attempts AS (
    SELECT
        DATE_TRUNC('day', mr.created_at) as day,
        COUNT(*) as total_merges,
        SUM(CASE WHEN mr.status = 'CONFLICT' THEN 1 ELSE 0 END) as conflicts,
        SUM(CASE WHEN mr.status = 'CONFLICT' AND mr.resolution_strategy = 'auto' THEN 1 ELSE 0 END) as auto_resolved,
        SUM(CASE WHEN mr.status = 'CONFLICT' AND mr.resolution_strategy = 'manual' THEN 1 ELSE 0 END) as manual_resolved,
        SUM(CASE WHEN mr.status = 'CONFLICT' AND mr.resolution_strategy = 'rejected' THEN 1 ELSE 0 END) as rejected,
        AVG(CASE WHEN mr.status = 'CONFLICT'
            THEN (SELECT MAX(duration_ms)
                  FROM pggit.performance_metrics
                  WHERE operation_type = 'merge_branches'
                    AND distributed_trace_id = mr.merge_id)
        END) as avg_conflict_time_ms
    FROM pggit.merge_relationships mr
    WHERE mr.created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    GROUP BY DATE_TRUNC('day', mr.created_at)
)
SELECT
    day,
    total_merges,
    conflicts,
    auto_resolved,
    manual_resolved,
    rejected,

    -- Success rates
    ROUND(100.0 * conflicts / NULLIF(total_merges, 0), 1) as conflict_rate_percent,
    ROUND(100.0 * auto_resolved / NULLIF(conflicts, 0), 1) as auto_resolution_rate_percent,
    ROUND(100.0 * manual_resolved / NULLIF(conflicts, 0), 1) as manual_resolution_rate_percent,
    ROUND(100.0 * rejected / NULLIF(conflicts, 0), 1) as rejection_rate_percent,

    -- Performance impact
    ROUND(avg_conflict_time_ms::NUMERIC, 1) as avg_conflict_resolution_ms,

    -- Trend indicator
    CASE
        WHEN auto_resolved > 0 AND manual_resolved = 0 AND rejected = 0 THEN 'EXCELLENT'
        WHEN auto_resolved >= COALESCE(manual_resolved, 0) THEN 'GOOD'
        WHEN auto_resolved > 0 THEN 'FAIR'
        ELSE 'NEEDS_IMPROVEMENT'
    END as effectiveness_rating

FROM resolution_attempts
ORDER BY day DESC;

-- ============================================================================
-- HELPER FUNCTION: record_merge_analysis
-- ============================================================================
-- Purpose: Store merge analysis results for historical tracking
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.record_merge_analysis(
    p_merge_id INTEGER,
    p_branch_from TEXT,
    p_branch_into TEXT,
    p_lca_find_ms NUMERIC,
    p_conflict_detect_ms NUMERIC,
    p_auto_resolve_ms NUMERIC,
    p_total_merge_ms NUMERIC,
    p_primary_bottleneck TEXT,
    p_resolution_strategy TEXT,
    p_conflict_count INTEGER,
    p_sla_status TEXT
)
RETURNS BIGINT AS $$
DECLARE
    v_baseline_p99 NUMERIC;
    v_deviation_percent NUMERIC;
    v_analysis_id BIGINT;
BEGIN
    -- Get current baseline
    SELECT p99_microseconds / 1000.0
    INTO v_baseline_p99
    FROM pggit.performance_baselines
    WHERE operation_type = 'merge_branches'
      AND is_active = TRUE
    LIMIT 1;

    -- Calculate deviation
    v_deviation_percent := 100.0 * (p_total_merge_ms - v_baseline_p99) / NULLIF(v_baseline_p99, 0);

    -- Insert analysis record
    INSERT INTO pggit.merge_performance_analysis (
        merge_id, branch_from, branch_into,
        lca_find_ms, conflict_detect_ms, auto_resolve_ms, total_merge_ms,
        primary_bottleneck,
        lca_percentage, conflict_detect_percentage, resolution_percentage,
        resolution_strategy, conflict_count, sla_status,
        baseline_p99_ms, deviation_percent, analyzed_at
    ) VALUES (
        p_merge_id, p_branch_from, p_branch_into,
        p_lca_find_ms, p_conflict_detect_ms, p_auto_resolve_ms, p_total_merge_ms,
        p_primary_bottleneck,
        ROUND(100.0 * p_lca_find_ms / NULLIF(p_total_merge_ms, 0), 1),
        ROUND(100.0 * p_conflict_detect_ms / NULLIF(p_total_merge_ms, 0), 1),
        ROUND(100.0 * p_auto_resolve_ms / NULLIF(p_total_merge_ms, 0), 1),
        p_resolution_strategy, p_conflict_count, p_sla_status,
        v_baseline_p99, v_deviation_percent, CURRENT_TIMESTAMP
    )
    RETURNING analysis_id INTO v_analysis_id;

    RETURN v_analysis_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- SUMMARY
-- ============================================================================
-- Created views:
--   1. v_merge_bottleneck_analysis - Identify slowest merge phase per merge
--   2. v_merge_success_rate_analysis - Hourly merge success rates
--   3. v_merge_conflict_hotspots - Branch pairs with high conflict rates
--   4. v_merge_phase_timeline - Time-series per-phase performance
--   5. v_merge_performance_by_branch - Per-branch statistics
--   6. v_merge_resolution_effectiveness - Auto-resolution success tracking
--
-- Created tables:
--   1. merge_performance_analysis - Historical merge analysis records
--
-- Created functions:
--   1. record_merge_analysis() - Store analysis for historical tracking
--
-- Performance targets:
--   - All views: <5ms per query
--   - Bottleneck identification: Real-time from performance_metrics
--   - Historical analysis: Supports up to 1 year of data
-- ============================================================================
