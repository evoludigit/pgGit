-- pgGit v0.3 Phase 9: Schema Diffing Foundation Tests
-- Comprehensive test suite for schema comparison, diff detection, and migration planning

\set ECHO all
\set ON_ERROR_STOP on

\echo '===================================================================================='
\echo 'pgGit v0.3 Phase 9: Schema Diffing Foundation Test Suite'
\echo 'Testing: Schema comparison, diff detection, impact assessment, migration planning'
\echo '===================================================================================='
\echo ''

DO $$
BEGIN
    -- Clean up test data from previous runs
    DELETE FROM pggit.migration_plans WHERE source_branch LIKE 'schema_test_%';
    DELETE FROM pggit.schema_changes WHERE diff_id IN (
        SELECT id FROM pggit.schema_diffs WHERE branch_a LIKE 'schema_test_%'
    );
    DELETE FROM pggit.schema_diffs WHERE branch_a LIKE 'schema_test_%' OR branch_b LIKE 'schema_test_%';
    DELETE FROM pggit.schema_snapshots WHERE branch_name LIKE 'schema_test_%';
    DELETE FROM pggit.objects WHERE branch_name LIKE 'schema_test_%';
    DELETE FROM pggit.branches WHERE name LIKE 'schema_test_%';

    RAISE NOTICE 'Test setup complete';
END $$;

-- TEST 1: Schema Snapshot Generation

\echo ''
\echo '1. Testing schema snapshot generation...'

DO $$
DECLARE
    v_snapshot jsonb;
    v_object_count integer;
BEGIN
    -- Create test branch
    PERFORM pggit.create_branch('schema_test_main', 'main', false);

    -- Get schema snapshot
    v_snapshot := pggit.get_schema_snapshot('schema_test_main');

    -- Verify snapshot structure
    v_object_count := COALESCE((v_snapshot->'summary'->>'object_count')::integer, -1);

    IF v_object_count > 0 THEN
        RAISE NOTICE '✓ Test 1.1 PASS: Schema snapshot generated with % objects', v_object_count;
    ELSE
        RAISE EXCEPTION 'Test 1.1 FAIL: Expected positive object count, got %', v_object_count;
    END IF;

    -- Cleanup
    DELETE FROM pggit.schema_snapshots WHERE branch_name = 'schema_test_main';
    DELETE FROM pggit.objects WHERE branch_name = 'schema_test_main';
    DELETE FROM pggit.branches WHERE name = 'schema_test_main';
END $$;

-- TEST 2: Schema Comparison - Added Objects

\echo ''
\echo '2. Testing schema comparison with added objects...'

DO $$
DECLARE
    v_diff jsonb;
    v_added_count integer;
BEGIN
    -- Create branches
    PERFORM pggit.create_branch('schema_test_base', 'main', false);
    PERFORM pggit.create_branch('schema_test_feature', 'main', false);

    -- Add object to feature branch
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    SELECT 'TABLE'::pggit.object_type, 'public', 'new_table', 'hash_new', 'CREATE TABLE new_table (...)', id, 'schema_test_feature', 1
    FROM pggit.branches WHERE name = 'schema_test_feature';

    -- Compare schemas
    v_diff := pggit.compare_schemas('schema_test_base', 'schema_test_feature');

    v_added_count := (v_diff->'summary'->>'added')::integer;

    IF v_added_count >= 1 THEN
        RAISE NOTICE '✓ Test 2.1 PASS: Schema comparison detected % added objects', v_added_count;
    ELSE
        RAISE EXCEPTION 'Test 2.1 FAIL: Expected added objects, got %', v_added_count;
    END IF;

    -- Cleanup
    DELETE FROM pggit.schema_diffs WHERE branch_a = 'schema_test_base';
    DELETE FROM pggit.objects WHERE branch_name IN ('schema_test_base', 'schema_test_feature');
    DELETE FROM pggit.branches WHERE name IN ('schema_test_base', 'schema_test_feature');
END $$;

-- TEST 3: Schema Comparison - Removed Objects

\echo ''
\echo '3. Testing schema comparison with removed objects...'

DO $$
DECLARE
    v_diff jsonb;
    v_removed_count integer;
BEGIN
    -- Create branches
    PERFORM pggit.create_branch('schema_test_old', 'main', false);
    PERFORM pggit.create_branch('schema_test_new', 'main', false);

    -- Add object to old branch
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    SELECT 'TABLE'::pggit.object_type, 'public', 'removed_table', 'hash_removed', 'CREATE TABLE removed_table (...)', id, 'schema_test_old', 1
    FROM pggit.branches WHERE name = 'schema_test_old';

    -- Compare (old to new - new is missing the table)
    v_diff := pggit.compare_schemas('schema_test_old', 'schema_test_new');

    v_removed_count := (v_diff->'summary'->>'removed')::integer;

    IF v_removed_count >= 1 THEN
        RAISE NOTICE '✓ Test 3.1 PASS: Schema comparison detected % removed objects', v_removed_count;
    ELSE
        RAISE EXCEPTION 'Test 3.1 FAIL: Expected removed objects, got %', v_removed_count;
    END IF;

    -- Cleanup
    DELETE FROM pggit.schema_diffs WHERE branch_a = 'schema_test_old';
    DELETE FROM pggit.objects WHERE branch_name IN ('schema_test_old', 'schema_test_new');
    DELETE FROM pggit.branches WHERE name IN ('schema_test_old', 'schema_test_new');
END $$;

-- TEST 4: Change Categorization

\echo ''
\echo '4. Testing change categorization...'

DO $$
DECLARE
    v_result jsonb;
    v_category text;
BEGIN
    -- Test categorizing a removed column (BREAKING)
    v_result := pggit.categorize_change('COLUMN', 'removed', 'VARCHAR(100)', NULL);
    v_category := v_result->>'category';

    IF v_category = 'BREAKING' THEN
        RAISE NOTICE '✓ Test 4.1 PASS: Categorized removed column as BREAKING';
    ELSE
        RAISE EXCEPTION 'Test 4.1 FAIL: Expected BREAKING, got %', v_category;
    END IF;

    -- Test categorizing an added index (COMPATIBLE)
    v_result := pggit.categorize_change('INDEX', 'added', NULL, 'CREATE INDEX idx...');
    v_category := v_result->>'category';

    IF v_category = 'COMPATIBLE' THEN
        RAISE NOTICE '✓ Test 4.2 PASS: Categorized added index as COMPATIBLE';
    ELSE
        RAISE EXCEPTION 'Test 4.2 FAIL: Expected COMPATIBLE, got %', v_category;
    END IF;
END $$;

-- TEST 5: Migration Impact Assessment

\echo ''
\echo '5. Testing migration impact assessment...'

DO $$
DECLARE
    v_diff jsonb;
    v_impact jsonb;
    v_feasibility text;
BEGIN
    -- Create test diff with various changes
    v_diff := jsonb_build_object(
        'branch_a', 'test_a',
        'branch_b', 'test_b',
        'changes', jsonb_build_array(
            jsonb_build_object('type', 'added', 'object_type', 'TABLE'),
            jsonb_build_object('type', 'added', 'object_type', 'INDEX')
        )
    );

    -- Assess impact
    v_impact := pggit.assess_migration_impact(v_diff);
    v_feasibility := v_impact->>'feasibility';

    IF v_feasibility IN ('ready', 'proceed_with_caution', 'review_required') THEN
        RAISE NOTICE '✓ Test 5.1 PASS: Migration impact assessed with feasibility: %', v_feasibility;
    ELSE
        RAISE EXCEPTION 'Test 5.1 FAIL: Invalid feasibility value: %', v_feasibility;
    END IF;
END $$;

-- TEST 6: Migration Plan Generation

\echo ''
\echo '6. Testing migration plan generation...'

DO $$
DECLARE
    v_plan jsonb;
    v_step_count integer;
BEGIN
    -- Create branches
    PERFORM pggit.create_branch('schema_test_src', 'main', false);
    PERFORM pggit.create_branch('schema_test_tgt', 'main', false);

    -- Add objects to source
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    SELECT 'TABLE'::pggit.object_type, 'public', 'users', 'hash_users', 'CREATE TABLE users (...)', id, 'schema_test_src', 1
    FROM pggit.branches WHERE name = 'schema_test_src';

    -- Generate migration plan
    v_plan := pggit.plan_migration('schema_test_src', 'schema_test_tgt');

    v_step_count := COALESCE((v_plan->>'step_count')::integer, -1);

    IF v_step_count > 0 THEN
        RAISE NOTICE '✓ Test 6.1 PASS: Migration plan generated with % steps', v_step_count;
    ELSE
        RAISE EXCEPTION 'Test 6.1 FAIL: Expected migration steps, got %', v_step_count;
    END IF;

    -- Cleanup
    DELETE FROM pggit.migration_plans WHERE source_branch = 'schema_test_src';
    DELETE FROM pggit.schema_diffs WHERE branch_a = 'schema_test_src';
    DELETE FROM pggit.objects WHERE branch_name IN ('schema_test_src', 'schema_test_tgt');
    DELETE FROM pggit.branches WHERE name IN ('schema_test_src', 'schema_test_tgt');
END $$;

-- TEST 7: Schema Dependency Detection

\echo ''
\echo '7. Testing schema dependency detection...'

DO $$
DECLARE
    v_deps jsonb;
    v_dep_count integer;
BEGIN
    -- Create test branch
    PERFORM pggit.create_branch('schema_test_deps', 'main', false);

    -- Detect dependencies
    v_deps := pggit.detect_schema_dependencies('schema_test_deps');

    v_dep_count := COALESCE((v_deps->>'dependency_count')::integer, -1);

    -- Dependencies may be 0 or more, so check for >= 0 and verify structure exists
    IF v_dep_count >= 0 AND v_deps ? 'dependency_count' THEN
        RAISE NOTICE '✓ Test 7.1 PASS: Schema dependency detection completed (% dependencies)', v_dep_count;
    ELSE
        RAISE EXCEPTION 'Test 7.1 FAIL: Invalid dependency structure or missing dependency_count';
    END IF;

    -- Cleanup
    DELETE FROM pggit.objects WHERE branch_name = 'schema_test_deps';
    DELETE FROM pggit.branches WHERE name = 'schema_test_deps';
END $$;

-- TEST 8: Schema Diff Report Generation

\echo ''
\echo '8. Testing schema diff report generation...'

DO $$
DECLARE
    v_report text;
    v_report_length integer;
BEGIN
    -- Create branches
    PERFORM pggit.create_branch('schema_test_report_a', 'main', false);
    PERFORM pggit.create_branch('schema_test_report_b', 'main', false);

    -- Generate report
    v_report := pggit.generate_schema_diff_report('schema_test_report_a', 'schema_test_report_b');

    v_report_length := LENGTH(v_report);

    IF v_report_length > 0 THEN
        RAISE NOTICE '✓ Test 8.1 PASS: Schema diff report generated (% characters)', v_report_length;
    ELSE
        RAISE EXCEPTION 'Test 8.1 FAIL: Empty report';
    END IF;

    -- Cleanup
    DELETE FROM pggit.schema_diffs WHERE branch_a = 'schema_test_report_a';
    DELETE FROM pggit.objects WHERE branch_name LIKE 'schema_test_report_%';
    DELETE FROM pggit.branches WHERE name LIKE 'schema_test_report_%';
END $$;

-- TEST 9: Schema Lineage Tracking

\echo ''
\echo '9. Testing schema lineage tracking...'

DO $$
DECLARE
    v_lineage jsonb;
    v_snapshot_count integer;
BEGIN
    -- Create test branch
    PERFORM pggit.create_branch('schema_test_lineage', 'main', false);

    -- Generate snapshot
    PERFORM pggit.get_schema_snapshot('schema_test_lineage');

    -- Track lineage
    v_lineage := pggit.track_schema_lineage('schema_test_lineage');

    v_snapshot_count := COALESCE(jsonb_array_length(v_lineage->'snapshots'), -1);

    IF v_snapshot_count > 0 THEN
        RAISE NOTICE '✓ Test 9.1 PASS: Schema lineage tracked with % snapshots', v_snapshot_count;
    ELSE
        RAISE EXCEPTION 'Test 9.1 FAIL: Expected lineage snapshots, got %', v_snapshot_count;
    END IF;

    -- Cleanup
    DELETE FROM pggit.schema_snapshots WHERE branch_name = 'schema_test_lineage';
    DELETE FROM pggit.objects WHERE branch_name = 'schema_test_lineage';
    DELETE FROM pggit.branches WHERE name = 'schema_test_lineage';
END $$;

-- TEST 10: View - Schema Change Summary

\echo ''
\echo '10. Testing schema change summary view...'

DO $$
DECLARE
    v_count integer;
    v_view_exists boolean;
BEGIN
    -- Check view exists
    SELECT EXISTS (
        SELECT 1 FROM information_schema.views
        WHERE table_schema = 'pggit' AND table_name = 'v_schema_change_summary'
    ) INTO v_view_exists;

    IF v_view_exists THEN
        -- Query the view (should not throw error)
        SELECT COUNT(*) INTO v_count FROM pggit.v_schema_change_summary;
        RAISE NOTICE '✓ Test 10.1 PASS: Schema change summary view works (% records)', v_count;
    ELSE
        RAISE EXCEPTION 'Test 10.1 FAIL: View v_schema_change_summary does not exist';
    END IF;
END $$;

-- TEST 11: View - Schema Impact Analysis

\echo ''
\echo '11. Testing schema impact analysis view...'

DO $$
DECLARE
    v_count integer;
    v_view_exists boolean;
BEGIN
    -- Check view exists
    SELECT EXISTS (
        SELECT 1 FROM information_schema.views
        WHERE table_schema = 'pggit' AND table_name = 'v_schema_impact_analysis'
    ) INTO v_view_exists;

    IF v_view_exists THEN
        -- Query the view (should not throw error)
        SELECT COUNT(*) INTO v_count FROM pggit.v_schema_impact_analysis;
        RAISE NOTICE '✓ Test 11.1 PASS: Schema impact analysis view works (% records)', v_count;
    ELSE
        RAISE EXCEPTION 'Test 11.1 FAIL: View v_schema_impact_analysis does not exist';
    END IF;
END $$;

-- TEST 12: View - Migration Readiness

\echo ''
\echo '12. Testing migration readiness view...'

DO $$
DECLARE
    v_count integer;
    v_view_exists boolean;
BEGIN
    -- Check view exists
    SELECT EXISTS (
        SELECT 1 FROM information_schema.views
        WHERE table_schema = 'pggit' AND table_name = 'v_schema_migration_readiness'
    ) INTO v_view_exists;

    IF v_view_exists THEN
        -- Query the view (should not throw error)
        SELECT COUNT(*) INTO v_count FROM pggit.v_schema_migration_readiness;
        RAISE NOTICE '✓ Test 12.1 PASS: Migration readiness view works (% records)', v_count;
    ELSE
        RAISE EXCEPTION 'Test 12.1 FAIL: View v_schema_migration_readiness does not exist';
    END IF;
END $$;

-- TEST SUMMARY

\echo ''
\echo '===================================================================================='
\echo 'Schema Diffing Foundation Test Suite: COMPLETE'
\echo '===================================================================================='
\echo ''
\echo 'Coverage:'
\echo '  ✅ Schema snapshot generation'
\echo '  ✅ Schema comparison (added objects)'
\echo '  ✅ Schema comparison (removed objects)'
\echo '  ✅ Change categorization'
\echo '  ✅ Migration impact assessment'
\echo '  ✅ Migration plan generation'
\echo '  ✅ Schema dependency detection'
\echo '  ✅ Schema diff report generation'
\echo '  ✅ Schema lineage tracking'
\echo '  ✅ Schema change summary view'
\echo '  ✅ Schema impact analysis view'
\echo '  ✅ Migration readiness view'
\echo ''
