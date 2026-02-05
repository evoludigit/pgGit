-- pgGit v0.3.1 Phase 11: Analytics & Insights
-- Change frequency analysis, trend tracking, effort estimation

-- ============================================================================
-- FUNCTION: pggit.analyze_schema_change_frequency()
-- ============================================================================
-- Analyze schema change patterns and frequency

CREATE OR REPLACE FUNCTION pggit.analyze_schema_change_frequency(
    p_branch_name text,
    p_days integer DEFAULT 30
)
RETURNS jsonb AS $$
DECLARE
    v_analysis jsonb;
    v_total_changes integer;
    v_daily_average numeric;
    v_peak_day text;
    v_total_added integer;
    v_total_removed integer;
    v_total_modified integer;
BEGIN
    -- Calculate totals
    SELECT
        COUNT(*),
        SUM(added_count),
        SUM(removed_count),
        SUM(modified_count)
    INTO v_total_changes, v_total_added, v_total_removed, v_total_modified
    FROM pggit.schema_diffs
    WHERE (branch_a = p_branch_name OR branch_b = p_branch_name)
      AND created_at > NOW() - (p_days || ' days')::interval;

    v_total_added := COALESCE(v_total_added, 0);
    v_total_removed := COALESCE(v_total_removed, 0);
    v_total_modified := COALESCE(v_total_modified, 0);
    v_total_changes := COALESCE(v_total_changes, 0);

    -- Calculate daily average
    v_daily_average := CASE
        WHEN v_total_changes > 0 THEN ROUND(v_total_changes::numeric / p_days, 2)
        ELSE 0
    END;

    -- Find peak day
    SELECT DATE(created_at)::text
    INTO v_peak_day
    FROM pggit.schema_diffs
    WHERE (branch_a = p_branch_name OR branch_b = p_branch_name)
      AND created_at > NOW() - (p_days || ' days')::interval
    GROUP BY DATE(created_at)
    ORDER BY COUNT(*) DESC
    LIMIT 1;

    v_analysis := jsonb_build_object(
        'branch_name', p_branch_name,
        'period_days', p_days,
        'total_changes', v_total_changes,
        'daily_average', v_daily_average,
        'peak_day', v_peak_day,
        'total_added', v_total_added,
        'total_removed', v_total_removed,
        'total_modified', v_total_modified,
        'change_intensity', CASE
            WHEN v_daily_average > 2 THEN 'HIGH'
            WHEN v_daily_average > 0.5 THEN 'MEDIUM'
            ELSE 'LOW'
        END,
        'analysis_timestamp', NOW()::text
    );

    RAISE NOTICE 'analyze_schema_change_frequency: % changes for % in % days', v_total_changes, p_branch_name, p_days;

    RETURN v_analysis;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.get_breaking_change_trends()
-- ============================================================================
-- Analyze breaking change patterns over time

CREATE OR REPLACE FUNCTION pggit.get_breaking_change_trends(
    p_branch_name text,
    p_days integer DEFAULT 30
)
RETURNS jsonb AS $$
DECLARE
    v_trends jsonb := '{"data": []}'::jsonb;
    v_day_record RECORD;
    v_day integer;
    v_daily_count integer;
    v_period_breaking integer;
BEGIN
    -- Calculate total breaking changes
    SELECT COUNT(*)
    INTO v_period_breaking
    FROM pggit.schema_diffs sd
    JOIN pggit.schema_changes sc ON sd.id = sc.diff_id
    WHERE (sd.branch_a = p_branch_name OR sd.branch_b = p_branch_name)
      AND sc.category = 'BREAKING'
      AND sd.created_at > NOW() - (p_days || ' days')::interval;

    v_period_breaking := COALESCE(v_period_breaking, 0);

    -- Build day-by-day trend
    FOR v_day IN 0..(p_days-1)
    LOOP
        SELECT COUNT(*)
        INTO v_daily_count
        FROM pggit.schema_diffs sd
        JOIN pggit.schema_changes sc ON sd.id = sc.diff_id
        WHERE (sd.branch_a = p_branch_name OR sd.branch_b = p_branch_name)
          AND sc.category = 'BREAKING'
          AND DATE(sd.created_at) = DATE(NOW() - (v_day || ' days')::interval);

        v_daily_count := COALESCE(v_daily_count, 0);

        v_trends := jsonb_set(
            v_trends,
            '{data}',
            v_trends->'data' || jsonb_build_object(
                'day', v_day,
                'date', DATE(NOW() - (v_day || ' days')::interval)::text,
                'breaking_changes', v_daily_count
            )
        );
    END LOOP;

    v_trends := jsonb_set(v_trends, '{branch}', to_jsonb(p_branch_name));
    v_trends := jsonb_set(v_trends, '{period_days}', to_jsonb(p_days));
    v_trends := jsonb_set(v_trends, '{total_breaking_changes}', to_jsonb(v_period_breaking));
    v_trends := jsonb_set(v_trends, '{trend}', to_jsonb(CASE
        WHEN v_period_breaking > 10 THEN 'INCREASING'
        WHEN v_period_breaking > 5 THEN 'MODERATE'
        ELSE 'LOW'
    END));

    RAISE NOTICE 'get_breaking_change_trends: % breaking changes for % over % days', v_period_breaking, p_branch_name, p_days;

    RETURN v_trends;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.estimate_migration_effort()
-- ============================================================================
-- Estimate effort required for migration

CREATE OR REPLACE FUNCTION pggit.estimate_migration_effort(
    p_branch_a text,
    p_branch_b text
)
RETURNS jsonb AS $$
DECLARE
    v_diff jsonb;
    v_impact jsonb;
    v_estimate jsonb;
    v_added integer;
    v_removed integer;
    v_modified integer;
    v_breaking integer;
    v_risky integer;
    v_base_effort numeric;
    v_risk_multiplier numeric;
    v_total_effort numeric;
    v_testing_hours numeric;
    v_development_hours numeric;
BEGIN
    -- Get analysis
    v_diff := pggit.compare_schemas(p_branch_a, p_branch_b);
    v_impact := pggit.assess_migration_impact(v_diff);

    -- Extract counts
    v_added := COALESCE((v_diff->'summary'->>'added')::integer, 0);
    v_removed := COALESCE((v_diff->'summary'->>'removed')::integer, 0);
    v_modified := COALESCE((v_diff->'summary'->>'modified')::integer, 0);
    v_breaking := COALESCE((v_impact->>'breaking_changes')::integer, 0);
    v_risky := COALESCE((v_impact->>'risky_changes')::integer, 0);

    -- Calculate base effort (in hours)
    -- Base: 0.25h per object change, plus overhead
    v_base_effort := (v_added + v_removed + v_modified) * 0.25;
    v_base_effort := GREATEST(v_base_effort, 0.5); -- Minimum 30 minutes

    -- Risk multiplier based on breaking changes
    v_risk_multiplier := 1.0;
    IF v_breaking > 0 THEN
        v_risk_multiplier := 1.5 + (v_breaking * 0.25); -- 50% base + 25% per breaking change
    ELSIF v_risky > 0 THEN
        v_risk_multiplier := 1.25; -- 25% increase for risky changes
    END IF;

    -- Development effort
    v_development_hours := ROUND(v_base_effort * v_risk_multiplier, 1);

    -- Testing effort (usually 50-75% of development)
    v_testing_hours := ROUND(v_development_hours * 0.6, 1);

    -- Total effort
    v_total_effort := v_development_hours + v_testing_hours;

    v_estimate := jsonb_build_object(
        'source_branch', p_branch_a,
        'target_branch', p_branch_b,
        'scope', jsonb_build_object(
            'added_objects', v_added,
            'removed_objects', v_removed,
            'modified_objects', v_modified,
            'total_changes', v_added + v_removed + v_modified
        ),
        'risk_factors', jsonb_build_object(
            'breaking_changes', v_breaking,
            'risky_changes', v_risky,
            'risk_multiplier', ROUND(v_risk_multiplier, 2)
        ),
        'effort_estimate', jsonb_build_object(
            'development_hours', v_development_hours,
            'testing_hours', v_testing_hours,
            'total_hours', v_total_effort,
            'development_days', ROUND(v_development_hours / 8, 1),
            'testing_days', ROUND(v_testing_hours / 8, 1),
            'total_days', ROUND(v_total_effort / 8, 1)
        ),
        'complexity', CASE
            WHEN v_total_effort <= 4 THEN 'LOW'
            WHEN v_total_effort <= 16 THEN 'MEDIUM'
            ELSE 'HIGH'
        END,
        'estimated_timestamp', NOW()::text
    );

    RAISE NOTICE 'estimate_migration_effort: % → % estimated at % hours', p_branch_a, p_branch_b, v_total_effort;

    RETURN v_estimate;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEWS: ANALYTICS
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_schema_change_trends AS
SELECT
    DATE(sd.created_at) as change_date,
    branch_a as branch,
    COUNT(*) as comparison_count,
    SUM(added_count) as total_added,
    SUM(removed_count) as total_removed,
    SUM(modified_count) as total_modified,
    ROUND(AVG(added_count + removed_count + modified_count)::numeric, 1) as avg_changes_per_comparison
FROM pggit.schema_diffs sd
GROUP BY branch_a, DATE(sd.created_at)
ORDER BY change_date DESC, branch_a;

CREATE OR REPLACE VIEW pggit.v_breaking_change_frequency AS
SELECT
    branch_a as branch,
    COUNT(DISTINCT sd.id) as total_comparisons,
    COUNT(DISTINCT sc.id) FILTER (WHERE sc.category = 'BREAKING') as breaking_change_count,
    ROUND(
        COUNT(DISTINCT sc.id) FILTER (WHERE sc.category = 'BREAKING')::numeric
        / COUNT(DISTINCT sd.id) * 100,
        1
    ) as breaking_change_percentage
FROM pggit.schema_diffs sd
LEFT JOIN pggit.schema_changes sc ON sd.id = sc.diff_id
GROUP BY branch_a
ORDER BY breaking_change_count DESC;

CREATE OR REPLACE VIEW pggit.v_most_active_branches AS
SELECT
    branch_a as branch,
    COUNT(*) as comparison_count,
    MAX(created_at) as last_compared,
    SUM(added_count) as lifetime_additions,
    SUM(removed_count) as lifetime_removals,
    SUM(modified_count) as lifetime_modifications
FROM pggit.schema_diffs
GROUP BY branch_a
ORDER BY comparison_count DESC
LIMIT 20;

-- ============================================================================
-- END OF PHASE 11 TIER 2 - ANALYTICS & INSIGHTS
-- ============================================================================

