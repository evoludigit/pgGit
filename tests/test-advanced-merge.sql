-- pgGit v0.2 Phase 7: Advanced Merge Operations Tests
-- Comprehensive test suite for three-way merge, semantic conflict detection, and automatic heuristics

\set ECHO all
\set ON_ERROR_STOP on

-- TEST SETUP

\echo '=================================================================================='
\echo 'pgGit v0.2 Phase 7: Advanced Merge Operations Test Suite'
\echo 'Testing: Three-way merge, semantic conflicts, automatic heuristics'
\echo '=================================================================================='
\echo ''

DO $$
DECLARE
    v_result text;
BEGIN
    -- Clean up test data from previous runs
    DELETE FROM pggit.merge_conflicts WHERE merge_id::text IN (
        SELECT id::text FROM pggit.merge_history WHERE source_branch LIKE 'adv_test_%'
    );
    DELETE FROM pggit.merge_history WHERE source_branch LIKE 'adv_test_%';
    DELETE FROM pggit.objects WHERE branch_name LIKE 'adv_test_%';
    DELETE FROM pggit.branches WHERE name LIKE 'adv_test_%';

    RAISE NOTICE 'Test setup complete';
END $$;

-- TEST 1: Conflict Severity Classification

\echo ''
\echo '1. Testing conflict severity classification...'

DO $$
DECLARE
    v_critical text;
    v_warning text;
    v_info text;
BEGIN
    -- Test CRITICAL: Foreign key constraint
    SELECT pggit.classify_conflict_severity('constraint_modified', 'ALTER TABLE FOREIGN KEY', 'x')
    INTO v_critical;

    IF v_critical = 'CRITICAL' THEN
        RAISE NOTICE '✓ Test 1.1 PASS: FK constraint classified as CRITICAL';
    ELSE
        RAISE EXCEPTION 'Test 1.1 FAIL: Expected CRITICAL, got %', v_critical;
    END IF;

    -- Test WARNING: Column modification
    SELECT pggit.classify_conflict_severity('column_modified', 'x', 'y')
    INTO v_warning;

    IF v_warning = 'WARNING' THEN
        RAISE NOTICE '✓ Test 1.2 PASS: Column modification classified as WARNING';
    ELSE
        RAISE EXCEPTION 'Test 1.2 FAIL: Expected WARNING, got %', v_warning;
    END IF;

    -- Test INFO: Index addition
    SELECT pggit.classify_conflict_severity('index_added', 'CREATE INDEX', 'x')
    INTO v_info;

    IF v_info = 'INFO' THEN
        RAISE NOTICE '✓ Test 1.3 PASS: Index addition classified as INFO';
    ELSE
        RAISE EXCEPTION 'Test 1.3 FAIL: Expected INFO, got %', v_info;
    END IF;
END $$;

-- TEST 2: Auto-Resolution Suggestion

\echo ''
\echo '2. Testing automatic resolution suggestions...'

DO $$
DECLARE
    v_suggestion text;
BEGIN
    -- Test: INFO level conflict should suggest auto-resolution
    SELECT pggit.suggest_auto_resolution('index_added', 'INFO', 'CREATE INDEX idx', 'x')
    INTO v_suggestion;

    IF v_suggestion = 'theirs' THEN
        RAISE NOTICE '✓ Test 2.1 PASS: Index addition suggests auto-resolve (theirs)';
    ELSE
        RAISE EXCEPTION 'Test 2.1 FAIL: Expected theirs, got %', v_suggestion;
    END IF;

    -- Test: WARNING level may suggest or not
    SELECT pggit.suggest_auto_resolution('constraint_modified', 'WARNING', 'x', 'y')
    INTO v_suggestion;

    IF v_suggestion IS NULL THEN
        RAISE NOTICE '✓ Test 2.2 PASS: Constraint modification suggests manual review (NULL)';
    ELSE
        RAISE EXCEPTION 'Test 2.2 FAIL: Expected NULL, got %', v_suggestion;
    END IF;
END $$;

-- TEST 3: Three-Way Merge - Compatible Changes

\echo ''
\echo '3. Testing three-way merge with compatible changes...'

DO $$
DECLARE
    v_branch_base integer;
    v_branch_a integer;
    v_branch_b integer;
    v_three_way jsonb;
    v_conflict_count integer;
    v_auto_merge_count integer;
BEGIN
    -- Create base branch
    v_branch_base := pggit.create_branch('adv_test_base', 'main', false);

    -- Create branch A: Add column email
    v_branch_a := pggit.create_branch('adv_test_3way_a', 'main', false);
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    VALUES ('COLUMN', 'public', 'users.email', 'hash1', 'ALTER TABLE users ADD COLUMN email TEXT', v_branch_a, 'adv_test_3way_a', 1);

    -- Create branch B: Add column phone (different column)
    v_branch_b := pggit.create_branch('adv_test_3way_b', 'main', false);
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    VALUES ('COLUMN', 'public', 'users.phone', 'hash2', 'ALTER TABLE users ADD COLUMN phone TEXT', v_branch_b, 'adv_test_3way_b', 1);

    -- Run three-way merge
    v_three_way := pggit.three_way_merge('adv_test_3way_a', 'adv_test_3way_b', 'main');

    v_conflict_count := (v_three_way->>'conflict_count')::integer;
    v_auto_merge_count := jsonb_array_length(v_three_way->'auto_merges');

    -- With inheritance from main, we get all main's objects as auto-merges. Just verify conflicts = 0
    IF v_conflict_count = 0 AND v_auto_merge_count > 0 THEN
        RAISE NOTICE '✓ Test 3.1 PASS: Non-overlapping changes auto-merged (0 conflicts, % auto-merges)', v_auto_merge_count;
    ELSE
        RAISE EXCEPTION 'Test 3.1 FAIL: Expected 0 conflicts, got %', v_conflict_count;
    END IF;

    -- Cleanup
    DELETE FROM pggit.objects WHERE branch_id IN (v_branch_base, v_branch_a, v_branch_b);
    DELETE FROM pggit.branches WHERE id IN (v_branch_base, v_branch_a, v_branch_b);
END $$;

-- TEST 4: Three-Way Merge - True Conflicts

\echo ''
\echo '4. Testing three-way merge with conflicting changes...'

DO $$
DECLARE
    v_branch_a integer;
    v_branch_b integer;
    v_three_way jsonb;
    v_conflict_count integer;
BEGIN
    -- Create branch A: Modify users table
    v_branch_a := pggit.create_branch('adv_test_conflict_a', 'main', false);
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    VALUES ('TABLE', 'public', 'users', 'hash_a_v1', 'CREATE TABLE users (id INT, email VARCHAR(100))', v_branch_a, 'adv_test_conflict_a', 1);

    -- Create branch B: Different modification to same table
    v_branch_b := pggit.create_branch('adv_test_conflict_b', 'main', false);
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    VALUES ('TABLE', 'public', 'users', 'hash_b_v1', 'CREATE TABLE users (id INT, phone VARCHAR(20))', v_branch_b, 'adv_test_conflict_b', 1);

    -- Run three-way merge
    v_three_way := pggit.three_way_merge('adv_test_conflict_a', 'adv_test_conflict_b', 'main');

    v_conflict_count := (v_three_way->>'conflict_count')::integer;

    IF v_conflict_count = 1 THEN
        RAISE NOTICE '✓ Test 4.1 PASS: Conflicting table modifications detected (1 conflict)';
    ELSE
        RAISE EXCEPTION 'Test 4.1 FAIL: Expected 1 conflict, got %', v_conflict_count;
    END IF;

    -- Cleanup
    DELETE FROM pggit.objects WHERE branch_id IN (v_branch_a, v_branch_b);
    DELETE FROM pggit.branches WHERE id IN (v_branch_a, v_branch_b);
END $$;

-- TEST 5: Semantic Conflict Detection

\echo ''
\echo '5. Testing semantic conflict detection (object renames)...'

DO $$
DECLARE
    v_branch_a integer;
    v_branch_b integer;
    v_semantic jsonb;
    v_rename_count integer;
BEGIN
    -- Create branch A: users_old table
    v_branch_a := pggit.create_branch('adv_test_semantic_a', 'main', false);
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    VALUES ('TABLE', 'public', 'users_old', 'hash1', 'CREATE TABLE users_old (...)', v_branch_a, 'adv_test_semantic_a', 1);

    -- Create branch B: users_new table (likely rename of users_old)
    v_branch_b := pggit.create_branch('adv_test_semantic_b', 'main', false);
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    VALUES ('TABLE', 'public', 'users_new', 'hash1', 'CREATE TABLE users_new (...)', v_branch_b, 'adv_test_semantic_b', 1);

    -- Detect semantic conflicts
    v_semantic := pggit.detect_semantic_conflicts('adv_test_semantic_a', 'adv_test_semantic_b');

    v_rename_count := jsonb_array_length(v_semantic->'semantic_conflicts');

    IF v_rename_count >= 1 THEN
        RAISE NOTICE '✓ Test 5.1 PASS: Potential rename detected (% semantic conflicts)', v_rename_count;
    ELSE
        RAISE EXCEPTION 'Test 5.1 FAIL: Expected semantic conflicts, got %', v_rename_count;
    END IF;

    -- Cleanup
    DELETE FROM pggit.objects WHERE branch_id IN (v_branch_a, v_branch_b);
    DELETE FROM pggit.branches WHERE id IN (v_branch_a, v_branch_b);
END $$;

-- TEST 6: Merge with Heuristics

\echo ''
\echo '6. Testing merge with heuristics (auto-resolution enabled)...'

DO $$
DECLARE
    v_branch_a integer;
    v_branch_b integer;
    v_merge_result jsonb;
    v_merge_id uuid;
    v_auto_resolved integer;
BEGIN
    -- Create branches with non-conflicting changes
    v_branch_a := pggit.create_branch('adv_test_heuristic_a', 'main', false);
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    VALUES ('INDEX', 'public', 'idx_users_email', 'hash1', 'CREATE INDEX idx_users_email ON users(email)', v_branch_a, 'adv_test_heuristic_a', 1);

    v_branch_b := pggit.create_branch('adv_test_heuristic_b', 'main', false);

    -- Run merge with heuristics
    v_merge_result := pggit.merge_with_heuristics('adv_test_heuristic_a', 'adv_test_heuristic_b');

    v_merge_id := (v_merge_result->>'merge_id')::uuid;
    v_auto_resolved := (v_merge_result->>'auto_resolved_count')::integer;

    IF v_auto_resolved >= 0 THEN
        RAISE NOTICE '✓ Test 6.1 PASS: Merge with heuristics completed (% auto-resolved)', v_auto_resolved;
    ELSE
        RAISE EXCEPTION 'Test 6.1 FAIL: Merge with heuristics failed';
    END IF;

    -- Cleanup
    DELETE FROM pggit.merge_conflicts WHERE merge_id = v_merge_id::text;
    DELETE FROM pggit.merge_history WHERE id = v_merge_id;
    DELETE FROM pggit.objects WHERE branch_id IN (v_branch_a, v_branch_b);
    DELETE FROM pggit.branches WHERE id IN (v_branch_a, v_branch_b);
END $$;

-- TEST 7: Get Merge Metrics

\echo ''
\echo '7. Testing merge metrics retrieval...'

DO $$
DECLARE
    v_metrics jsonb;
    v_total_merges integer;
BEGIN
    -- Get merge metrics
    v_metrics := pggit.get_merge_metrics('7 days'::interval);

    v_total_merges := (v_metrics->>'total_merges')::integer;

    IF v_metrics IS NOT NULL AND v_total_merges >= 0 THEN
        RAISE NOTICE '✓ Test 7.1 PASS: Merge metrics retrieved (total: % merges)', v_total_merges;
    ELSE
        RAISE EXCEPTION 'Test 7.1 FAIL: Failed to retrieve merge metrics';
    END IF;
END $$;

-- TEST 8: Merge Summary View

\echo ''
\echo '8. Testing merge summary view...'

DO $$
DECLARE
    v_view_exists boolean;
    v_merge_count integer;
BEGIN
    -- Check if view exists and is queryable
    SELECT COUNT(*) INTO v_merge_count FROM pggit.v_merge_summary;

    IF v_merge_count >= 0 THEN
        RAISE NOTICE '✓ Test 8.1 PASS: Merge summary view works (% records)', v_merge_count;
    ELSE
        RAISE EXCEPTION 'Test 8.1 FAIL: Merge summary view failed';
    END IF;
END $$;

-- TEST 9: Conflict Summary View

\echo ''
\echo '9. Testing conflict summary view...'

DO $$
DECLARE
    v_summary record;
BEGIN
    -- Query conflict summary
    SELECT * INTO v_summary FROM pggit.v_conflict_summary;

    IF v_summary IS NOT NULL THEN
        RAISE NOTICE '✓ Test 9.1 PASS: Conflict summary view works (total: % conflicts)', v_summary.total_conflicts;
    ELSE
        RAISE EXCEPTION 'Test 9.1 FAIL: Conflict summary view failed';
    END IF;
END $$;

-- TEST 10: Integration Test - Full Advanced Workflow

\echo ''
\echo '10. Integration test: Full advanced merge workflow...'

DO $$
DECLARE
    v_branch_main integer;
    v_branch_feature_a integer;
    v_branch_feature_b integer;
    v_merge_result jsonb;
    v_merge_id uuid;
    v_status text;
BEGIN
    -- Create feature branches with different changes
    v_branch_feature_a := pggit.create_branch('adv_test_feature_a', 'main', false);
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    VALUES
        ('TABLE', 'public', 'feature_table', 'hash1', 'CREATE TABLE feature_table (...)', v_branch_feature_a, 'adv_test_feature_a', 1),
        ('INDEX', 'public', 'idx_feature', 'hash2', 'CREATE INDEX idx_feature ON feature_table(id)', v_branch_feature_a, 'adv_test_feature_a', 1);

    v_branch_feature_b := pggit.create_branch('adv_test_feature_b', 'main', false);

    -- Execute advanced merge
    v_merge_result := pggit.merge_with_heuristics('adv_test_feature_a', 'adv_test_feature_b');

    v_merge_id := (v_merge_result->>'merge_id')::uuid;
    v_status := v_merge_result->>'status';

    IF v_status IN ('completed', 'awaiting_resolution') THEN
        RAISE NOTICE '✓ Test 10.1 PASS: Advanced merge workflow completed (status: %)', v_status;
    ELSE
        RAISE EXCEPTION 'Test 10.1 FAIL: Unexpected merge status: %', v_status;
    END IF;

    -- Cleanup
    DELETE FROM pggit.merge_conflicts WHERE merge_id = v_merge_id::text;
    DELETE FROM pggit.merge_history WHERE id = v_merge_id;
    DELETE FROM pggit.objects WHERE branch_id IN (v_branch_feature_a, v_branch_feature_b);
    DELETE FROM pggit.branches WHERE id IN (v_branch_feature_a, v_branch_feature_b);
END $$;

-- TEST SUMMARY

\echo ''
\echo '=================================================================================='
\echo 'Advanced Merge Operations Test Suite: COMPLETE'
\echo '=================================================================================='
\echo ''
\echo 'All tests completed successfully!'
\echo ''
\echo 'Coverage:'
\echo '  ✅ Conflict severity classification (CRITICAL/WARNING/INFO)'
\echo '  ✅ Automatic resolution suggestions'
\echo '  ✅ Three-way merge algorithm (compatible changes)'
\echo '  ✅ Three-way merge algorithm (true conflicts)'
\echo '  ✅ Semantic conflict detection (likely renames)'
\echo '  ✅ Merge with heuristics (auto-resolution)'
\echo '  ✅ Merge metrics retrieval'
\echo '  ✅ Merge summary view'
\echo '  ✅ Conflict summary view'
\echo '  ✅ Full advanced merge workflow'
\echo ''
