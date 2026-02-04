-- pgGit v0.3 Phase 10: Advanced Workflows Test Suite
-- Test all workflow orchestration, CI/CD integration, and advanced reporting functions

\set ECHO all
\set ON_ERROR_STOP on

\echo '===================================================================================='
\echo 'pgGit v0.3 Phase 10: Advanced Workflows & Polish Test Suite'
\echo 'Testing: Workflow orchestration, CI/CD integration, advanced reporting'
\echo '===================================================================================='
\echo ''

DO $$
BEGIN
    -- Clean up test data from previous runs
    DELETE FROM pggit.schema_compliance_audit WHERE branch_name LIKE 'workflow_test_%';
    DELETE FROM pggit.workflow_state WHERE workflow_id IN (
        SELECT workflow_id FROM pggit.schema_workflows WHERE source_branch LIKE 'workflow_test_%'
    );
    DELETE FROM pggit.schema_workflows WHERE source_branch LIKE 'workflow_test_%' OR target_branch LIKE 'workflow_test_%';
    DELETE FROM pggit.schema_diffs WHERE branch_a LIKE 'workflow_test_%' OR branch_b LIKE 'workflow_test_%';
    DELETE FROM pggit.objects WHERE branch_name LIKE 'workflow_test_%';
    DELETE FROM pggit.branches WHERE name LIKE 'workflow_test_%';

    RAISE NOTICE 'Test setup complete';
END $$;

-- TEST 1: Unified Schema Analysis

\echo ''
\echo '1. Testing unified_schema_analysis() workflow...'

DO $$
DECLARE
    v_analysis jsonb;
    v_status text;
BEGIN
    -- Create test branches
    PERFORM pggit.create_branch('workflow_test_base', 'main', false);
    PERFORM pggit.create_branch('workflow_test_feature', 'main', false);

    -- Add object to feature branch
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    SELECT 'TABLE'::pggit.object_type, 'public', 'new_feature_table', 'hash_nft', 'CREATE TABLE new_feature_table (...)', id, 'workflow_test_feature', 1
    FROM pggit.branches WHERE name = 'workflow_test_feature';

    -- Run unified analysis
    v_analysis := pggit.unified_schema_analysis('workflow_test_base', 'workflow_test_feature');
    v_status := v_analysis->>'status';

    IF v_status = 'completed' THEN
        RAISE NOTICE '✓ Test 1.1 PASS: Unified analysis completed successfully';
    ELSE
        RAISE EXCEPTION 'Test 1.1 FAIL: Analysis status is %', v_status;
    END IF;

    -- Cleanup (delete snapshots before branches due to FK)
    DELETE FROM pggit.schema_snapshots WHERE branch_name IN ('workflow_test_base', 'workflow_test_feature');
    DELETE FROM pggit.schema_diffs WHERE branch_a = 'workflow_test_base';
    DELETE FROM pggit.objects WHERE branch_name IN ('workflow_test_base', 'workflow_test_feature');
    DELETE FROM pggit.branches WHERE name IN ('workflow_test_base', 'workflow_test_feature');
END $$;

-- TEST 2: Check Breaking Changes (CI/CD Gate)

\echo ''
\echo '2. Testing check_breaking_changes() for CI/CD gates...'

DO $$
DECLARE
    v_check jsonb;
    v_ci_approved boolean;
BEGIN
    -- Create test branches
    PERFORM pggit.create_branch('workflow_test_safe_a', 'main', false);
    PERFORM pggit.create_branch('workflow_test_safe_b', 'main', false);

    -- Add non-breaking change (new table)
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    SELECT 'TABLE'::pggit.object_type, 'public', 'new_table', 'hash_nt', 'CREATE TABLE new_table (...)', id, 'workflow_test_safe_b', 1
    FROM pggit.branches WHERE name = 'workflow_test_safe_b';

    -- Check for breaking changes
    v_check := pggit.check_breaking_changes('workflow_test_safe_a', 'workflow_test_safe_b');
    v_ci_approved := (v_check->>'ci_approved')::boolean;

    IF v_ci_approved THEN
        RAISE NOTICE '✓ Test 2.1 PASS: Non-breaking changes approved for CI/CD';
    ELSE
        RAISE EXCEPTION 'Test 2.1 FAIL: Should approve non-breaking changes';
    END IF;

    -- Cleanup
    DELETE FROM pggit.schema_diffs WHERE branch_a = 'workflow_test_safe_a';
    DELETE FROM pggit.objects WHERE branch_name IN ('workflow_test_safe_a', 'workflow_test_safe_b');
    DELETE FROM pggit.branches WHERE name IN ('workflow_test_safe_a', 'workflow_test_safe_b');
END $$;

-- TEST 3: Validate Schema Changes

\echo ''
\echo '3. Testing validate_schema_changes() pre-deployment check...'

DO $$
DECLARE
    v_validation jsonb;
    v_validation_status text;
BEGIN
    -- Create test branch
    PERFORM pggit.create_branch('workflow_test_validate', 'main', false);

    -- Validate schema
    v_validation := pggit.validate_schema_changes('workflow_test_validate');
    v_validation_status := v_validation->>'validation_status';

    IF v_validation_status IN ('passed', 'warning') THEN
        RAISE NOTICE '✓ Test 3.1 PASS: Schema validation completed with status: %', v_validation_status;
    ELSE
        RAISE EXCEPTION 'Test 3.1 FAIL: Invalid validation status: %', v_validation_status;
    END IF;

    -- Cleanup
    DELETE FROM pggit.objects WHERE branch_name = 'workflow_test_validate';
    DELETE FROM pggit.branches WHERE name = 'workflow_test_validate';
END $$;

-- TEST 4: Migration Readiness Scorecard

\echo ''
\echo '4. Testing get_migration_readiness_scorecard()...'

DO $$
DECLARE
    v_scorecard jsonb;
    v_score integer;
    v_category text;
BEGIN
    -- Create test branches
    PERFORM pggit.create_branch('workflow_test_score_src', 'main', false);
    PERFORM pggit.create_branch('workflow_test_score_tgt', 'main', false);

    -- Add object to source
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    SELECT 'TABLE'::pggit.object_type, 'public', 'users', 'hash_users', 'CREATE TABLE users (...)', id, 'workflow_test_score_src', 1
    FROM pggit.branches WHERE name = 'workflow_test_score_src';

    -- Get readiness scorecard
    v_scorecard := pggit.get_migration_readiness_scorecard('workflow_test_score_src', 'workflow_test_score_tgt');
    v_score := (v_scorecard->>'readiness_score')::integer;
    v_category := v_scorecard->>'readiness_category';

    IF v_score >= 0 AND v_score <= 100 AND v_category IN ('READY', 'PROCEED_WITH_CAUTION', 'REQUIRES_REVIEW') THEN
        RAISE NOTICE '✓ Test 4.1 PASS: Readiness scorecard generated (score: %, category: %)', v_score, v_category;
    ELSE
        RAISE EXCEPTION 'Test 4.1 FAIL: Invalid scorecard data';
    END IF;

    -- Cleanup
    DELETE FROM pggit.migration_plans WHERE source_branch = 'workflow_test_score_src';
    DELETE FROM pggit.schema_diffs WHERE branch_a = 'workflow_test_score_src';
    DELETE FROM pggit.objects WHERE branch_name IN ('workflow_test_score_src', 'workflow_test_score_tgt');
    DELETE FROM pggit.branches WHERE name IN ('workflow_test_score_src', 'workflow_test_score_tgt');
END $$;

-- TEST 5: Schema Complexity Score

\echo ''
\echo '5. Testing get_schema_complexity_score()...'

DO $$
DECLARE
    v_complexity jsonb;
    v_score integer;
    v_category text;
BEGIN
    -- Create test branch
    PERFORM pggit.create_branch('workflow_test_complexity', 'main', false);

    -- Get complexity score
    v_complexity := pggit.get_schema_complexity_score('workflow_test_complexity');
    v_score := (v_complexity->>'complexity_score')::integer;
    v_category := v_complexity->>'complexity_category';

    IF v_category IN ('LOW', 'MEDIUM', 'HIGH') THEN
        RAISE NOTICE '✓ Test 5.1 PASS: Complexity score calculated (score: %, category: %)', v_score, v_category;
    ELSE
        RAISE EXCEPTION 'Test 5.1 FAIL: Invalid complexity category: %', v_category;
    END IF;

    -- Cleanup
    DELETE FROM pggit.objects WHERE branch_name = 'workflow_test_complexity';
    DELETE FROM pggit.branches WHERE name = 'workflow_test_complexity';
END $$;

-- TEST 6: Compliance Report Generation

\echo ''
\echo '6. Testing generate_compliance_report()...'

DO $$
DECLARE
    v_report text;
    v_report_length integer;
BEGIN
    -- Create test branches
    PERFORM pggit.create_branch('workflow_test_comp_a', 'main', false);
    PERFORM pggit.create_branch('workflow_test_comp_b', 'main', false);

    -- Generate compliance report
    v_report := pggit.generate_compliance_report('workflow_test_comp_a', 'workflow_test_comp_b');
    v_report_length := LENGTH(v_report);

    IF v_report_length > 0 AND v_report LIKE '%COMPLIANCE%' THEN
        RAISE NOTICE '✓ Test 6.1 PASS: Compliance report generated (% characters)', v_report_length;
    ELSE
        RAISE EXCEPTION 'Test 6.1 FAIL: Invalid compliance report';
    END IF;

    -- Cleanup
    DELETE FROM pggit.schema_diffs WHERE branch_a = 'workflow_test_comp_a';
    DELETE FROM pggit.objects WHERE branch_name IN ('workflow_test_comp_a', 'workflow_test_comp_b');
    DELETE FROM pggit.branches WHERE name IN ('workflow_test_comp_a', 'workflow_test_comp_b');
END $$;

-- TEST 7: View - Workflow Summary

\echo ''
\echo '7. Testing v_schema_workflow_summary view...'

DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*) INTO v_count FROM pggit.v_schema_workflow_summary;

    IF v_count >= 0 THEN
        RAISE NOTICE '✓ Test 7.1 PASS: Workflow summary view works (% records)', v_count;
    ELSE
        RAISE EXCEPTION 'Test 7.1 FAIL: Could not query view';
    END IF;
END $$;

-- TEST 8: View - CI Ready Changes

\echo ''
\echo '8. Testing v_ci_ready_changes view...'

DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*) INTO v_count FROM pggit.v_ci_ready_changes;

    IF v_count >= 0 THEN
        RAISE NOTICE '✓ Test 8.1 PASS: CI ready changes view works (% records)', v_count;
    ELSE
        RAISE EXCEPTION 'Test 8.1 FAIL: Could not query view';
    END IF;
END $$;

-- TEST 9: View - Migration Readiness Summary

\echo ''
\echo '9. Testing v_migration_readiness_summary view...'

DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*) INTO v_count FROM pggit.v_migration_readiness_summary;

    IF v_count >= 0 THEN
        RAISE NOTICE '✓ Test 9.1 PASS: Migration readiness summary view works (% records)', v_count;
    ELSE
        RAISE EXCEPTION 'Test 9.1 FAIL: Could not query view';
    END IF;
END $$;

-- TEST SUMMARY

\echo ''
\echo '===================================================================================='
\echo 'Advanced Workflows Test Suite: COMPLETE'
\echo '===================================================================================='
\echo ''
\echo 'Coverage:'
\echo '  ✅ Unified schema analysis'
\echo '  ✅ CI/CD breaking change detection'
\echo '  ✅ Pre-deployment schema validation'
\echo '  ✅ Migration readiness scorecard'
\echo '  ✅ Schema complexity scoring'
\echo '  ✅ Compliance report generation'
\echo '  ✅ Workflow summary view'
\echo '  ✅ CI ready changes view'
\echo '  ✅ Migration readiness summary view'
\echo ''

