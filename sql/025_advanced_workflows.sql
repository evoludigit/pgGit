-- pgGit v0.3 Phase 10: Advanced Workflows & Polish
-- Workflow orchestration, CI/CD integration, advanced reporting

-- ============================================================================
-- STORAGE TABLES: WORKFLOW MANAGEMENT
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.schema_workflows (
    id SERIAL PRIMARY KEY,
    workflow_id UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
    operation_type TEXT NOT NULL CHECK (operation_type IN ('analysis', 'migration', 'validation', 'comparison')),
    source_branch TEXT NOT NULL,
    target_branch TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
    started_at TIMESTAMP DEFAULT NOW(),
    completed_at TIMESTAMP,
    result_json JSONB,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS pggit.workflow_state (
    workflow_id UUID NOT NULL REFERENCES pggit.schema_workflows(workflow_id),
    step_number INTEGER NOT NULL,
    step_name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed', 'skipped')),
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    context_json JSONB,
    result_json JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (workflow_id, step_number)
);

CREATE TABLE IF NOT EXISTS pggit.schema_compliance_audit (
    id SERIAL PRIMARY KEY,
    audit_id UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
    branch_name TEXT NOT NULL,
    check_date TIMESTAMP DEFAULT NOW(),
    compliance_status TEXT NOT NULL CHECK (compliance_status IN ('compliant', 'warning', 'failed')),
    breaking_changes_count INTEGER DEFAULT 0,
    risky_changes_count INTEGER DEFAULT 0,
    audit_result JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_schema_workflows_status_started ON pggit.schema_workflows(status, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_schema_workflows_operation ON pggit.schema_workflows(operation_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflow_state_status ON pggit.workflow_state(workflow_id, status);
CREATE INDEX IF NOT EXISTS idx_schema_compliance_audit_check_date ON pggit.schema_compliance_audit(check_date DESC);

-- ============================================================================
-- FUNCTION: pggit.unified_schema_analysis()
-- ============================================================================
-- Complete analysis: snapshot → diff → impact → plan all in one call

CREATE OR REPLACE FUNCTION pggit.unified_schema_analysis(
    p_branch_a text,
    p_branch_b text
)
RETURNS jsonb AS $$
DECLARE
    v_workflow_id UUID;
    v_snapshot_a jsonb;
    v_snapshot_b jsonb;
    v_diff jsonb;
    v_impact jsonb;
    v_plan jsonb;
    v_result jsonb;
BEGIN
    v_workflow_id := gen_random_uuid();

    BEGIN
        -- Step 1: Create snapshots
        v_snapshot_a := pggit.get_schema_snapshot(p_branch_a);
        v_snapshot_b := pggit.get_schema_snapshot(p_branch_b);

        -- Step 2: Compare schemas
        v_diff := pggit.compare_schemas(p_branch_a, p_branch_b);

        -- Step 3: Assess impact
        v_impact := pggit.assess_migration_impact(v_diff);

        -- Step 4: Plan migration
        v_plan := pggit.plan_migration(p_branch_a, p_branch_b);

        -- Aggregate results
        v_result := jsonb_build_object(
            'workflow_id', v_workflow_id::text,
            'status', 'completed',
            'branch_a', p_branch_a,
            'branch_b', p_branch_b,
            'timestamp', NOW()::text,
            'analysis', jsonb_build_object(
                'snapshot_a_objects', v_snapshot_a->'summary'->>'object_count',
                'snapshot_b_objects', v_snapshot_b->'summary'->>'object_count',
                'diff_summary', v_diff->'summary',
                'impact_assessment', v_impact,
                'migration_plan', jsonb_build_object(
                    'feasibility', v_plan->>'feasibility',
                    'step_count', v_plan->>'step_count'
                )
            )
        );

        RAISE NOTICE 'unified_schema_analysis: Completed analysis for % → % (workflow: %)',
            p_branch_a, p_branch_b, v_workflow_id;

        RETURN v_result;
    EXCEPTION WHEN OTHERS THEN
        v_result := jsonb_build_object(
            'workflow_id', v_workflow_id::text,
            'status', 'failed',
            'error', SQLERRM
        );
        RAISE NOTICE 'unified_schema_analysis: FAILED - %', SQLERRM;
        RETURN v_result;
    END;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.check_breaking_changes()
-- ============================================================================
-- CI/CD gate function: Detect breaking changes for automated decisions

CREATE OR REPLACE FUNCTION pggit.check_breaking_changes(
    p_branch_a text,
    p_branch_b text
)
RETURNS jsonb AS $$
DECLARE
    v_diff jsonb;
    v_impact jsonb;
    v_breaking_count integer := 0;
    v_has_breaking boolean := false;
    v_changes RECORD;
    v_result jsonb;
BEGIN
    -- Get diff
    v_diff := pggit.compare_schemas(p_branch_a, p_branch_b);

    -- Get impact assessment
    v_impact := pggit.assess_migration_impact(v_diff);

    -- Count breaking changes
    FOR v_changes IN
        SELECT jsonb_array_elements(v_diff->'changes') as change
    LOOP
        IF v_changes.change->>'type' = 'removed' THEN
            v_breaking_count := v_breaking_count + 1;
            v_has_breaking := true;
        END IF;
    END LOOP;

    v_result := jsonb_build_object(
        'branch_a', p_branch_a,
        'branch_b', p_branch_b,
        'has_breaking_changes', v_has_breaking,
        'breaking_change_count', v_breaking_count,
        'feasibility', v_impact->>'feasibility',
        'risk_level', v_impact->>'risk_level',
        'ci_approved', CASE WHEN v_has_breaking THEN false ELSE true END,
        'timestamp', NOW()::text
    );

    RAISE NOTICE 'check_breaking_changes: Found % breaking changes (approved: %)',
        v_breaking_count, NOT v_has_breaking;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.validate_schema_changes()
-- ============================================================================
-- Pre-deployment validation for schema changes

CREATE OR REPLACE FUNCTION pggit.validate_schema_changes(
    p_branch_name text
)
RETURNS jsonb AS $$
DECLARE
    v_result jsonb;
    v_object_count integer;
    v_issues jsonb := '[]'::jsonb;
    v_warnings jsonb := '[]'::jsonb;
    v_validation_status text := 'passed';
BEGIN
    -- Check if branch exists
    IF NOT EXISTS (SELECT 1 FROM pggit.branches WHERE name = p_branch_name) THEN
        v_result := jsonb_build_object(
            'branch_name', p_branch_name,
            'validation_status', 'failed',
            'error', 'Branch not found'
        );
        RETURN v_result;
    END IF;

    -- Get object count
    SELECT COUNT(*) INTO v_object_count FROM pggit.objects WHERE branch_name = p_branch_name;

    -- Add validation warnings for potential issues
    IF v_object_count = 0 THEN
        v_warnings := v_warnings || jsonb_build_array('No objects in schema');
    END IF;

    -- Check for orphaned objects
    IF EXISTS (
        SELECT 1 FROM pggit.objects
        WHERE branch_name = p_branch_name AND content_hash IS NULL
    ) THEN
        v_warnings := v_warnings || jsonb_build_array('Orphaned objects detected');
        v_validation_status := 'warning';
    END IF;

    v_result := jsonb_build_object(
        'branch_name', p_branch_name,
        'validation_status', v_validation_status,
        'object_count', v_object_count,
        'issues', CASE WHEN jsonb_array_length(v_issues) = 0 THEN jsonb_build_array() ELSE v_issues END,
        'warnings', CASE WHEN jsonb_array_length(v_warnings) = 0 THEN jsonb_build_array() ELSE v_warnings END,
        'timestamp', NOW()::text
    );

    RAISE NOTICE 'validate_schema_changes: Validated % (% objects, status: %)',
        p_branch_name, v_object_count, v_validation_status;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.get_migration_readiness_scorecard()
-- ============================================================================
-- Scorecard with readiness metrics and recommendations

CREATE OR REPLACE FUNCTION pggit.get_migration_readiness_scorecard(
    p_source_branch text,
    p_target_branch text
)
RETURNS jsonb AS $$
DECLARE
    v_diff jsonb;
    v_impact jsonb;
    v_readiness_score integer := 100;
    v_recommendations jsonb := '[]'::jsonb;
    v_metrics jsonb;
    v_result jsonb;
BEGIN
    -- Get analysis
    v_diff := pggit.compare_schemas(p_source_branch, p_target_branch);
    v_impact := pggit.assess_migration_impact(v_diff);

    -- Calculate readiness score
    v_readiness_score := 100;

    -- Deduct for breaking changes
    IF (v_impact->>'feasibility')::text = 'review_required' THEN
        v_readiness_score := v_readiness_score - 40;
        v_recommendations := v_recommendations || jsonb_build_array('Review breaking changes before migration');
    END IF;

    -- Deduct for risky changes
    IF (v_impact->>'feasibility')::text = 'proceed_with_caution' THEN
        v_readiness_score := v_readiness_score - 20;
        v_recommendations := v_recommendations || jsonb_build_array('Plan mitigation for risky changes');
    END IF;

    -- Assess effort
    IF (v_impact->>'estimated_effort')::text = 'high' THEN
        v_recommendations := v_recommendations || jsonb_build_array('Allocate sufficient time for high-effort migration');
    END IF;

    v_metrics := jsonb_build_object(
        'breaking_changes', v_impact->>'breaking_changes',
        'risky_changes', v_impact->>'risky_changes',
        'compatible_changes', v_impact->>'compatible_changes',
        'risk_level', v_impact->>'risk_level'
    );

    v_result := jsonb_build_object(
        'source_branch', p_source_branch,
        'target_branch', p_target_branch,
        'readiness_score', v_readiness_score,
        'readiness_category', CASE
            WHEN v_readiness_score >= 80 THEN 'READY'
            WHEN v_readiness_score >= 60 THEN 'PROCEED_WITH_CAUTION'
            ELSE 'REQUIRES_REVIEW'
        END,
        'metrics', v_metrics,
        'recommendations', v_recommendations,
        'timestamp', NOW()::text
    );

    RAISE NOTICE 'get_migration_readiness_scorecard: Score % for % → %',
        v_readiness_score, p_source_branch, p_target_branch;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.get_schema_complexity_score()
-- ============================================================================
-- Complexity metrics for schema health assessment

CREATE OR REPLACE FUNCTION pggit.get_schema_complexity_score(
    p_branch_name text
)
RETURNS jsonb AS $$
DECLARE
    v_total_objects integer;
    v_table_count integer;
    v_view_count integer;
    v_function_count integer;
    v_index_count integer;
    v_complexity_score integer := 0;
    v_result jsonb;
BEGIN
    -- Count objects by type
    SELECT
        COUNT(*) FILTER (WHERE object_type = 'TABLE') ,
        COUNT(*) FILTER (WHERE object_type = 'VIEW') ,
        COUNT(*) FILTER (WHERE object_type = 'FUNCTION') ,
        COUNT(*) FILTER (WHERE object_type = 'INDEX') ,
        COUNT(*)
    INTO v_table_count, v_view_count, v_function_count, v_index_count, v_total_objects
    FROM pggit.objects
    WHERE branch_name = p_branch_name;

    -- Calculate complexity score (simple heuristic)
    v_complexity_score := (
        (COALESCE(v_table_count, 0) * 10) +
        (COALESCE(v_view_count, 0) * 15) +
        (COALESCE(v_function_count, 0) * 20) +
        (COALESCE(v_index_count, 0) * 5)
    );

    v_result := jsonb_build_object(
        'branch_name', p_branch_name,
        'total_objects', COALESCE(v_total_objects, 0),
        'table_count', COALESCE(v_table_count, 0),
        'view_count', COALESCE(v_view_count, 0),
        'function_count', COALESCE(v_function_count, 0),
        'index_count', COALESCE(v_index_count, 0),
        'complexity_score', v_complexity_score,
        'complexity_category', CASE
            WHEN v_complexity_score < 100 THEN 'LOW'
            WHEN v_complexity_score < 300 THEN 'MEDIUM'
            ELSE 'HIGH'
        END,
        'timestamp', NOW()::text
    );

    RAISE NOTICE 'get_schema_complexity_score: Score % for % (% objects)',
        v_complexity_score, p_branch_name, COALESCE(v_total_objects, 0);

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: pggit.generate_compliance_report()
-- ============================================================================
-- Compliance-focused report for audit/regulatory requirements

CREATE OR REPLACE FUNCTION pggit.generate_compliance_report(
    p_branch_a text,
    p_branch_b text
)
RETURNS text AS $$
DECLARE
    v_diff jsonb;
    v_impact jsonb;
    v_report text;
    v_breaking_count integer;
    v_risky_count integer;
    v_change RECORD;
BEGIN
    -- Get analysis
    v_diff := pggit.compare_schemas(p_branch_a, p_branch_b);
    v_impact := pggit.assess_migration_impact(v_diff);

    -- Count breaking and risky
    v_breaking_count := COALESCE((v_impact->>'breaking_changes')::integer, 0);
    v_risky_count := COALESCE((v_impact->>'risky_changes')::integer, 0);

    -- Generate report
    v_report := format(
        E'SCHEMA CHANGE COMPLIANCE REPORT\n' ||
        E'================================\n' ||
        E'Generated: %s\n' ||
        E'Source Branch: %s\n' ||
        E'Target Branch: %s\n' ||
        E'\n' ||
        E'COMPLIANCE ASSESSMENT\n' ||
        E'---------------------\n' ||
        E'Breaking Changes: %s (requires approval)\n' ||
        E'Risky Changes: %s (requires mitigation planning)\n' ||
        E'Compatible Changes: %s\n' ||
        E'Overall Risk Level: %s\n' ||
        E'\n' ||
        E'MIGRATION FEASIBILITY: %s\n' ||
        E'ESTIMATED EFFORT: %s\n' ||
        E'\n' ||
        E'COMPLIANCE STATUS: %s\n',
        NOW()::text,
        p_branch_a,
        p_branch_b,
        v_breaking_count,
        v_risky_count,
        COALESCE((v_impact->>'compatible_changes')::integer, 0),
        v_impact->>'risk_level',
        v_impact->>'feasibility',
        v_impact->>'estimated_effort',
        CASE
            WHEN v_breaking_count = 0 AND v_risky_count = 0 THEN 'COMPLIANT'
            WHEN v_breaking_count = 0 THEN 'WARNING'
            ELSE 'REQUIRES_APPROVAL'
        END
    );

    RAISE NOTICE 'generate_compliance_report: Generated report for % → %', p_branch_a, p_branch_b;

    RETURN v_report;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEWS: WORKFLOW MONITORING & READINESS
-- ============================================================================

CREATE OR REPLACE VIEW pggit.v_schema_workflow_summary AS
SELECT
    workflow_id,
    operation_type,
    source_branch,
    target_branch,
    status,
    started_at,
    completed_at,
    EXTRACT(EPOCH FROM (COALESCE(completed_at, NOW()) - started_at))::integer as duration_seconds
FROM pggit.schema_workflows
ORDER BY created_at DESC;

CREATE OR REPLACE VIEW pggit.v_ci_ready_changes AS
SELECT
    sd.branch_a,
    sd.branch_b,
    sd.added_count,
    sd.removed_count,
    sd.modified_count,
    CASE
        WHEN sd.removed_count = 0 THEN 'SAFE'
        ELSE 'REVIEW_REQUIRED'
    END as ci_approval,
    sd.created_at
FROM pggit.schema_diffs sd
WHERE sd.removed_count = 0
ORDER BY sd.created_at DESC;

CREATE OR REPLACE VIEW pggit.v_migration_readiness_summary AS
SELECT
    branch_a as source_branch,
    branch_b as target_branch,
    added_count,
    removed_count,
    modified_count,
    CASE
        WHEN removed_count = 0 AND modified_count <= 5 THEN 'READY'
        WHEN removed_count = 0 THEN 'PROCEED_WITH_CAUTION'
        ELSE 'REQUIRES_REVIEW'
    END as readiness_status,
    created_at
FROM pggit.schema_diffs
ORDER BY created_at DESC;

-- ============================================================================
-- END OF PHASE 10 ADVANCED WORKFLOWS
-- ============================================================================

