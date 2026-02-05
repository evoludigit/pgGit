-- pgGit v0.2 Phase 8: Batch Operations & Production Monitoring
-- Performance optimization, batch merges, health checks, observability
-- Author: stephengibson12
-- Phase: v0.2 Extended (Week 8 - Performance & Production Hardening)

-- ============================================================================
-- PERFORMANCE OPTIMIZATION: ADDITIONAL INDEXES
-- ============================================================================

-- Index for fast merge status lookups
CREATE INDEX IF NOT EXISTS idx_merge_history_status_initiated
    ON pggit.merge_history(status, initiated_at DESC)
    WHERE status IN ('completed', 'failed', 'in_progress');

-- Index for finding merges by date range
CREATE INDEX IF NOT EXISTS idx_merge_history_date_range
    ON pggit.merge_history(initiated_at DESC, status)
    INCLUDE (source_branch, target_branch);

-- Index for conflict queries by created_at
CREATE INDEX IF NOT EXISTS idx_merge_conflicts_created
    ON pggit.merge_conflicts(created_at DESC)
    WHERE resolution_strategy IS NULL;

-- Index for fast resolution lookups
CREATE INDEX IF NOT EXISTS idx_merge_conflicts_resolution
    ON pggit.merge_conflicts(resolution_strategy)
    WHERE resolution_strategy IS NOT NULL;

-- Composite index for merge operation queries
CREATE INDEX IF NOT EXISTS idx_merge_history_composite
    ON pggit.merge_history(initiated_at DESC, status)
    INCLUDE (source_branch, target_branch);

-- ============================================================================
-- FUNCTION: pggit.batch_merge()
-- ============================================================================
-- Merge multiple branches in sequence with conflict tracking
-- Useful for merging feature branches into main in controlled order

CREATE OR REPLACE FUNCTION pggit.batch_merge(
    p_source_branches text[],
    p_target_branch text DEFAULT 'main',
    p_stop_on_conflict boolean DEFAULT false
)
RETURNS jsonb AS $$
DECLARE
    v_result jsonb := '{"merges": [], "total": 0, "succeeded": 0, "failed": 0, "stopped": false}'::jsonb;
    v_branch text;
    v_merge_result jsonb;
    v_merge_id uuid;
    v_merge_status text;
    v_conflict_count integer;
BEGIN
    -- Validate target branch exists
    IF NOT EXISTS (SELECT 1 FROM pggit.branches WHERE name = p_target_branch) THEN
        RAISE EXCEPTION 'Target branch % not found', p_target_branch;
    END IF;

    -- Process each source branch in order
    FOREACH v_branch IN ARRAY p_source_branches LOOP
        BEGIN
            -- Validate source branch exists
            IF NOT EXISTS (SELECT 1 FROM pggit.branches WHERE name = v_branch) THEN
                v_result := jsonb_set(
                    v_result,
                    '{merges}',
                    v_result->'merges' || jsonb_build_object(
                        'branch', v_branch,
                        'status', 'skipped',
                        'reason', 'Branch not found'
                    )
                );
                CONTINUE;
            END IF;

            -- Attempt merge
            v_merge_result := pggit.merge_with_heuristics(v_branch, p_target_branch);
            v_merge_id := (v_merge_result->>'merge_id')::uuid;
            v_merge_status := v_merge_result->>'status';
            v_conflict_count := (v_merge_result->>'conflict_count')::integer;

            -- Record merge attempt
            IF v_merge_status = 'completed' THEN
                v_result := jsonb_set(v_result, '{succeeded}', to_jsonb((v_result->>'succeeded')::integer + 1));
            ELSIF v_merge_status = 'failed' THEN
                v_result := jsonb_set(v_result, '{failed}', to_jsonb((v_result->>'failed')::integer + 1));
            END IF;

            v_result := jsonb_set(
                v_result,
                '{merges}',
                v_result->'merges' || jsonb_build_object(
                    'branch', v_branch,
                    'merge_id', v_merge_id::text,
                    'status', v_merge_status,
                    'conflicts', v_conflict_count
                )
            );

            -- Stop on conflict if requested
            IF p_stop_on_conflict AND v_conflict_count > 0 THEN
                v_result := jsonb_set(v_result, '{stopped}', to_jsonb(true));
                EXIT;
            END IF;

        EXCEPTION WHEN OTHERS THEN
            v_result := jsonb_set(v_result, '{failed}', to_jsonb((v_result->>'failed')::integer + 1));
            v_result := jsonb_set(
                v_result,
                '{merges}',
                v_result->'merges' || jsonb_build_object(
                    'branch', v_branch,
                    'status', 'error',
                    'error', SQLERRM
                )
            );
        END;
    END LOOP;

    -- Update totals
    v_result := jsonb_set(v_result, '{total}', to_jsonb(array_length(p_source_branches, 1)));

    RAISE NOTICE 'batch_merge: Processed % branches, % succeeded, % failed',
        array_length(p_source_branches, 1),
        v_result->>'succeeded',
        v_result->>'failed';

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.parallel_conflict_detection()
-- ============================================================================
-- Pre-compute conflicts for multiple merges efficiently

CREATE OR REPLACE FUNCTION pggit.parallel_conflict_detection(
    p_source_branches text[],
    p_target_branch text DEFAULT 'main'
)
RETURNS jsonb AS $$
DECLARE
    v_result jsonb := '{"conflicts": {}, "total_checked": 0, "conflicts_found": 0}'::jsonb;
    v_branch text;
    v_conflicts jsonb;
    v_conflict_count integer;
BEGIN
    FOREACH v_branch IN ARRAY p_source_branches LOOP
        BEGIN
            -- Detect conflicts without performing merge
            v_conflicts := pggit.detect_conflicts(v_branch, p_target_branch);
            v_conflict_count := jsonb_array_length(v_conflicts->'conflicts');

            IF v_conflict_count > 0 THEN
                v_result := jsonb_set(
                    v_result,
                    '{conflicts, ' || v_branch || '}',
                    v_conflicts
                );
                v_result := jsonb_set(
                    v_result,
                    '{conflicts_found}',
                    to_jsonb((v_result->>'conflicts_found')::integer + v_conflict_count)
                );
            END IF;

            v_result := jsonb_set(
                v_result,
                '{total_checked}',
                to_jsonb((v_result->>'total_checked')::integer + 1)
            );

        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Error detecting conflicts for %: %', v_branch, SQLERRM;
        END;
    END LOOP;

    RAISE NOTICE 'parallel_conflict_detection: Checked % branches, found % conflicts',
        v_result->>'total_checked',
        v_result->>'conflicts_found';

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.bulk_resolve_conflicts()
-- ============================================================================
-- Bulk resolve multiple conflicts with same strategy

CREATE OR REPLACE FUNCTION pggit.bulk_resolve_conflicts(
    p_merge_id uuid,
    p_strategy text,
    p_conflict_type text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
    v_result jsonb := '{"resolved": 0, "failed": 0, "errors": []}'::jsonb;
    v_conflict record;
    v_resolved integer := 0;
    v_failed integer := 0;
BEGIN
    -- Bulk update conflicts with matching type
    FOR v_conflict IN
        SELECT id FROM pggit.merge_conflicts
        WHERE merge_id = p_merge_id::text
          AND resolution_strategy IS NULL
          AND (p_conflict_type IS NULL OR conflict_type = p_conflict_type)
    LOOP
        BEGIN
            UPDATE pggit.merge_conflicts
            SET resolution_strategy = p_strategy,
                resolved_at = NOW(),
                resolved_by = 'bulk_resolve'
            WHERE id = v_conflict.id;

            v_resolved := v_resolved + 1;
        EXCEPTION WHEN OTHERS THEN
            v_failed := v_failed + 1;
            v_result := jsonb_set(
                v_result,
                '{errors}',
                v_result->'errors' || to_jsonb(SQLERRM)
            );
        END;
    END LOOP;

    v_result := jsonb_set(v_result, '{resolved}', to_jsonb(v_resolved));
    v_result := jsonb_set(v_result, '{failed}', to_jsonb(v_failed));

    RAISE NOTICE 'bulk_resolve_conflicts: Resolved %, Failed %', v_resolved, v_failed;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.health_check_merge_integrity()
-- ============================================================================
-- Validate merge operation integrity

CREATE OR REPLACE FUNCTION pggit.health_check_merge_integrity()
RETURNS jsonb AS $$
DECLARE
    v_result jsonb := '{
        "status": "healthy",
        "checks": {},
        "issues": [],
        "timestamp": ""
    }'::jsonb;
    v_orphaned_count integer;
    v_unresolved_count integer;
    v_long_running_count integer;
BEGIN
    v_result := jsonb_set(v_result, '{timestamp}', to_jsonb(NOW()::text));

    -- Check 1: Orphaned merge_conflicts (merge_id references non-existent merge)
    SELECT COUNT(*) INTO v_orphaned_count
    FROM pggit.merge_conflicts mc
    WHERE NOT EXISTS (
        SELECT 1 FROM pggit.merge_history mh WHERE mh.id = mc.merge_id::uuid
    );

    v_result := jsonb_set(
        v_result,
        '{checks, orphaned_conflicts}',
        jsonb_build_object('count', v_orphaned_count, 'status', CASE WHEN v_orphaned_count > 0 THEN 'warning' ELSE 'ok' END)
    );

    IF v_orphaned_count > 0 THEN
        v_result := jsonb_set(
            v_result,
            '{issues}',
            v_result->'issues' || to_jsonb('Found ' || v_orphaned_count || ' orphaned conflicts')
        );
    END IF;

    -- Check 2: Unresolved conflicts in completed merges
    SELECT COUNT(*) INTO v_unresolved_count
    FROM pggit.merge_conflicts mc
    JOIN pggit.merge_history mh ON mh.id = mc.merge_id::uuid
    WHERE mh.status = 'completed'
      AND mc.resolution_strategy IS NULL;

    v_result := jsonb_set(
        v_result,
        '{checks, unresolved_in_completed}',
        jsonb_build_object('count', v_unresolved_count, 'status', CASE WHEN v_unresolved_count > 0 THEN 'warning' ELSE 'ok' END)
    );

    IF v_unresolved_count > 0 THEN
        v_result := jsonb_set(
            v_result,
            '{issues}',
            v_result->'issues' || to_jsonb('Found ' || v_unresolved_count || ' unresolved conflicts in completed merges')
        );
    END IF;

    -- Check 3: Long-running merges (in progress for > 1 hour)
    SELECT COUNT(*) INTO v_long_running_count
    FROM pggit.merge_history
    WHERE status = 'in_progress'
      AND initiated_at < NOW() - INTERVAL '1 hour';

    v_result := jsonb_set(
        v_result,
        '{checks, long_running_merges}',
        jsonb_build_object('count', v_long_running_count, 'status', CASE WHEN v_long_running_count > 0 THEN 'warning' ELSE 'ok' END)
    );

    IF v_long_running_count > 0 THEN
        v_result := jsonb_set(
            v_result,
            '{issues}',
            v_result->'issues' || to_jsonb('Found ' || v_long_running_count || ' long-running merges')
        );
    END IF;

    -- Overall status
    IF jsonb_array_length(v_result->'issues') > 0 THEN
        v_result := jsonb_set(v_result, '{status}', to_jsonb('warning'));
    END IF;

    RAISE NOTICE 'health_check_merge_integrity: % issues found', jsonb_array_length(v_result->'issues');

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.health_check_performance_baseline()
-- ============================================================================
-- Check merge performance against baseline

CREATE OR REPLACE FUNCTION pggit.health_check_performance_baseline()
RETURNS jsonb AS $$
DECLARE
    v_result jsonb := '{
        "status": "ok",
        "metrics": {},
        "warnings": [],
        "timestamp": ""
    }'::jsonb;
    v_avg_merge_time_ms integer;
    v_avg_conflicts_per_merge numeric;
    v_success_rate numeric;
BEGIN
    v_result := jsonb_set(v_result, '{timestamp}', to_jsonb(NOW()::text));

    -- Calculate average merge time (last 30 days)
    SELECT COALESCE(AVG(EXTRACT(EPOCH FROM (completed_at - initiated_at)) * 1000)::integer, 0)
    INTO v_avg_merge_time_ms
    FROM pggit.merge_history
    WHERE status = 'completed'
      AND initiated_at > NOW() - INTERVAL '30 days';

    v_result := jsonb_set(
        v_result,
        '{metrics, avg_merge_time_ms}',
        to_jsonb(v_avg_merge_time_ms)
    );

    -- Check if exceeds baseline (50ms target for 1000-object merges)
    IF v_avg_merge_time_ms > 50 THEN
        v_result := jsonb_set(
            v_result,
            '{warnings}',
            v_result->'warnings' || to_jsonb('Average merge time (' || v_avg_merge_time_ms || 'ms) exceeds baseline (50ms)')
        );
        v_result := jsonb_set(v_result, '{status}', to_jsonb('warning'));
    END IF;

    -- Calculate average conflicts per merge
    SELECT COALESCE(AVG(conflict_count), 0)
    INTO v_avg_conflicts_per_merge
    FROM (
        SELECT COUNT(*) as conflict_count
        FROM pggit.merge_conflicts mc
        JOIN pggit.merge_history mh ON mh.id = mc.merge_id::uuid
        WHERE mh.initiated_at > NOW() - INTERVAL '30 days'
        GROUP BY mc.merge_id
    ) subq;

    v_result := jsonb_set(
        v_result,
        '{metrics, avg_conflicts_per_merge}',
        to_jsonb(v_avg_conflicts_per_merge)
    );

    -- Calculate success rate
    SELECT COALESCE(
        100.0 * COUNT(CASE WHEN status = 'completed' THEN 1 END) / NULLIF(COUNT(*), 0),
        0
    )::numeric(5,2)
    INTO v_success_rate
    FROM pggit.merge_history
    WHERE initiated_at > NOW() - INTERVAL '30 days';

    v_result := jsonb_set(
        v_result,
        '{metrics, success_rate_percent}',
        to_jsonb(v_success_rate)
    );

    -- Warn if success rate below 95%
    IF v_success_rate < 95 THEN
        v_result := jsonb_set(
            v_result,
            '{warnings}',
            v_result->'warnings' || to_jsonb('Success rate (' || v_success_rate || '%) below target (95%)')
        );
        v_result := jsonb_set(v_result, '{status}', to_jsonb('warning'));
    END IF;

    RAISE NOTICE 'health_check_performance_baseline: Avg time %ms, Success rate %, Avg conflicts %',
        v_avg_merge_time_ms, v_success_rate, v_avg_conflicts_per_merge;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEW: v_merge_operations_summary
-- ============================================================================
-- Real-time summary of all merge operations

CREATE OR REPLACE VIEW pggit.v_merge_operations_summary AS
SELECT
    mh.id,
    mh.source_branch,
    mh.target_branch,
    mh.status,
    mh.initiated_at,
    mh.completed_at,
    EXTRACT(EPOCH FROM (COALESCE(mh.completed_at, NOW()) - mh.initiated_at)) as duration_seconds,
    COALESCE(mc_counts.conflict_count, 0) as total_conflicts,
    COALESCE(mc_counts.unresolved_count, 0) as unresolved_conflicts,
    COALESCE(mc_counts.critical_count, 0) as critical_conflicts,
    COALESCE(mc_counts.warning_count, 0) as warning_conflicts,
    mh.merge_strategy,
    mh.initiated_by
FROM pggit.merge_history mh
LEFT JOIN (
    SELECT
        merge_id,
        COUNT(*) as conflict_count,
        COUNT(CASE WHEN resolution_strategy IS NULL THEN 1 END) as unresolved_count,
        COUNT(CASE WHEN conflict_severity = 'CRITICAL' THEN 1 END) as critical_count,
        COUNT(CASE WHEN conflict_severity = 'WARNING' THEN 1 END) as warning_count
    FROM pggit.merge_conflicts
    GROUP BY merge_id
) mc_counts ON mc_counts.merge_id = mh.id::text
ORDER BY mh.initiated_at DESC;

-- ============================================================================
-- VIEW: v_performance_metrics
-- ============================================================================
-- Performance tracking over time

CREATE OR REPLACE VIEW pggit.v_performance_metrics AS
SELECT
    DATE_TRUNC('day', mh.initiated_at)::date as date,
    COUNT(*) as total_merges,
    COUNT(CASE WHEN mh.status = 'completed' THEN 1 END) as completed_merges,
    COUNT(CASE WHEN mh.status = 'failed' THEN 1 END) as failed_merges,
    ROUND(AVG(EXTRACT(EPOCH FROM (COALESCE(mh.completed_at, NOW()) - mh.initiated_at)) * 1000)::numeric, 2) as avg_merge_time_ms,
    ROUND(MIN(EXTRACT(EPOCH FROM (COALESCE(mh.completed_at, NOW()) - mh.initiated_at)) * 1000)::numeric, 2) as min_merge_time_ms,
    ROUND(MAX(EXTRACT(EPOCH FROM (COALESCE(mh.completed_at, NOW()) - mh.initiated_at)) * 1000)::numeric, 2) as max_merge_time_ms,
    ROUND(
        100.0 * COUNT(CASE WHEN mh.status = 'completed' THEN 1 END) / NULLIF(COUNT(*), 0),
        2
    )::numeric(5,2) as success_rate_percent
FROM pggit.merge_history mh
GROUP BY DATE_TRUNC('day', mh.initiated_at)
ORDER BY date DESC;

-- ============================================================================
-- VIEW: v_branch_merge_activity
-- ============================================================================
-- Merge activity by branch

CREATE OR REPLACE VIEW pggit.v_branch_merge_activity AS
SELECT
    COALESCE(source_branch, 'N/A') as branch_name,
    'source' as branch_role,
    COUNT(*) as merge_count,
    COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed,
    COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed,
    COUNT(CASE WHEN status = 'in_progress' THEN 1 END) as in_progress
FROM pggit.merge_history
WHERE source_branch IS NOT NULL
GROUP BY source_branch

UNION ALL

SELECT
    COALESCE(target_branch, 'N/A') as branch_name,
    'target' as branch_role,
    COUNT(*) as merge_count,
    COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed,
    COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed,
    COUNT(CASE WHEN status = 'in_progress' THEN 1 END) as in_progress
FROM pggit.merge_history
WHERE target_branch IS NOT NULL
GROUP BY target_branch
ORDER BY merge_count DESC;

-- ============================================================================
-- FUNCTION: pggit.cleanup_orphaned_data()
-- ============================================================================
-- Clean up orphaned records and optimize performance

CREATE OR REPLACE FUNCTION pggit.cleanup_orphaned_data(
    p_dry_run boolean DEFAULT true
)
RETURNS jsonb AS $$
DECLARE
    v_result jsonb := '{
        "orphaned_conflicts": 0,
        "orphaned_branches": 0,
        "total_cleaned": 0,
        "dry_run": true
    }'::jsonb;
    v_orphaned_conflicts integer := 0;
    v_orphaned_branches integer := 0;
BEGIN
    v_result := jsonb_set(v_result, '{dry_run}', to_jsonb(p_dry_run));

    -- Count orphaned conflicts (merge_id references non-existent merge)
    SELECT COUNT(*) INTO v_orphaned_conflicts
    FROM pggit.merge_conflicts mc
    WHERE NOT EXISTS (
        SELECT 1 FROM pggit.merge_history mh WHERE mh.id = mc.merge_id::uuid
    );

    v_result := jsonb_set(v_result, '{orphaned_conflicts}', to_jsonb(v_orphaned_conflicts));

    -- Only delete if not dry run
    IF NOT p_dry_run AND v_orphaned_conflicts > 0 THEN
        DELETE FROM pggit.merge_conflicts mc
        WHERE NOT EXISTS (
            SELECT 1 FROM pggit.merge_history mh WHERE mh.id = mc.merge_id::uuid
        );

        RAISE NOTICE 'Cleaned up % orphaned conflicts', v_orphaned_conflicts;
    END IF;

    -- Count orphaned branches (merged branches that reference non-existent parents)
    SELECT COUNT(*) INTO v_orphaned_branches
    FROM pggit.branches b
    WHERE parent_branch_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM pggit.branches parent WHERE parent.id = b.parent_branch_id
      );

    v_result := jsonb_set(v_result, '{orphaned_branches}', to_jsonb(v_orphaned_branches));

    -- Only update if not dry run
    IF NOT p_dry_run AND v_orphaned_branches > 0 THEN
        UPDATE pggit.branches
        SET parent_branch_id = NULL
        WHERE parent_branch_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM pggit.branches parent WHERE parent.id = parent_branch_id
          );

        RAISE NOTICE 'Cleaned up % orphaned branch references', v_orphaned_branches;
    END IF;

    v_result := jsonb_set(
        v_result,
        '{total_cleaned}',
        to_jsonb(v_orphaned_conflicts + v_orphaned_branches)
    );

    RAISE NOTICE 'cleanup_orphaned_data: Dry run: %, Orphaned conflicts: %, Orphaned branches: %',
        p_dry_run, v_orphaned_conflicts, v_orphaned_branches;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.get_merge_performance_report()
-- ============================================================================
-- Generate comprehensive performance report

CREATE OR REPLACE FUNCTION pggit.get_merge_performance_report(
    p_days integer DEFAULT 30
)
RETURNS jsonb AS $$
DECLARE
    v_result jsonb := '{"period_days": 0, "report": {}}'::jsonb;
    v_total_merges integer;
    v_completed integer;
    v_failed integer;
    v_avg_time_ms integer;
    v_max_time_ms integer;
    v_avg_conflicts numeric;
BEGIN
    v_result := jsonb_set(v_result, '{period_days}', to_jsonb(p_days));

    -- Overall statistics
    SELECT
        COUNT(*),
        COUNT(CASE WHEN status = 'completed' THEN 1 END),
        COUNT(CASE WHEN status = 'failed' THEN 1 END),
        COALESCE(AVG(EXTRACT(EPOCH FROM (completed_at - initiated_at)) * 1000)::integer, 0),
        COALESCE(MAX(EXTRACT(EPOCH FROM (completed_at - initiated_at)) * 1000)::integer, 0)
    INTO v_total_merges, v_completed, v_failed, v_avg_time_ms, v_max_time_ms
    FROM pggit.merge_history
    WHERE initiated_at > NOW() - (p_days || ' days')::interval;

    v_result := jsonb_set(v_result, '{report, total_merges}', to_jsonb(v_total_merges));
    v_result := jsonb_set(v_result, '{report, completed}', to_jsonb(v_completed));
    v_result := jsonb_set(v_result, '{report, failed}', to_jsonb(v_failed));
    v_result := jsonb_set(v_result, '{report, avg_merge_time_ms}', to_jsonb(v_avg_time_ms));
    v_result := jsonb_set(v_result, '{report, max_merge_time_ms}', to_jsonb(v_max_time_ms));

    -- Average conflicts per merge
    SELECT COALESCE(AVG(conflict_count), 0)
    INTO v_avg_conflicts
    FROM (
        SELECT COUNT(*) as conflict_count
        FROM pggit.merge_conflicts mc
        JOIN pggit.merge_history mh ON mh.id = mc.merge_id::uuid
        WHERE mh.created_at > NOW() - (p_days || ' days')::interval
        GROUP BY mc.merge_id
    ) subq;

    v_result := jsonb_set(v_result, '{report, avg_conflicts_per_merge}', to_jsonb(v_avg_conflicts));

    RAISE NOTICE 'get_merge_performance_report: Generated report for % days', p_days;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.estimate_merge_duration()
-- ============================================================================
-- Estimate merge duration based on historical data

CREATE OR REPLACE FUNCTION pggit.estimate_merge_duration(
    p_source_branch text,
    p_target_branch text
)
RETURNS jsonb AS $$
DECLARE
    v_result jsonb := '{
        "source_branch": "",
        "target_branch": "",
        "estimated_ms": 0,
        "confidence": "low",
        "historical_merges": 0
    }'::jsonb;
    v_source_avg_ms integer;
    v_target_avg_ms integer;
    v_combined_avg_ms integer;
    v_source_count integer;
    v_target_count integer;
BEGIN
    v_result := jsonb_set(v_result, '{source_branch}', to_jsonb(p_source_branch));
    v_result := jsonb_set(v_result, '{target_branch}', to_jsonb(p_target_branch));

    -- Get average merge time for source branch
    SELECT
        COALESCE(AVG(EXTRACT(EPOCH FROM (completed_at - initiated_at)) * 1000)::integer, 0),
        COUNT(*)
    INTO v_source_avg_ms, v_source_count
    FROM pggit.merge_history
    WHERE (source_branch = p_source_branch OR source_branch LIKE '%' || p_source_branch || '%')
      AND status = 'completed'
      AND initiated_at > NOW() - INTERVAL '30 days';

    -- Get average merge time for target branch
    SELECT
        COALESCE(AVG(EXTRACT(EPOCH FROM (completed_at - initiated_at)) * 1000)::integer, 0),
        COUNT(*)
    INTO v_target_avg_ms, v_target_count
    FROM pggit.merge_history
    WHERE (target_branch = p_target_branch OR target_branch LIKE '%' || p_target_branch || '%')
      AND status = 'completed'
      AND initiated_at > NOW() - INTERVAL '30 days';

    -- Calculate combined estimate
    v_combined_avg_ms := GREATEST(
        COALESCE((v_source_avg_ms + v_target_avg_ms) / 2, 0),
        10
    );

    v_result := jsonb_set(v_result, '{estimated_ms}', to_jsonb(v_combined_avg_ms));
    v_result := jsonb_set(v_result, '{historical_merges}', to_jsonb(v_source_count + v_target_count));

    -- Set confidence level
    IF v_source_count + v_target_count > 10 THEN
        v_result := jsonb_set(v_result, '{confidence}', to_jsonb('high'));
    ELSIF v_source_count + v_target_count > 3 THEN
        v_result := jsonb_set(v_result, '{confidence}', to_jsonb('medium'));
    ELSE
        v_result := jsonb_set(v_result, '{confidence}', to_jsonb('low'));
    END IF;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;
