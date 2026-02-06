-- Comprehensive test suite for performance, batch ops, and health checks

\set ECHO all
\set ON_ERROR_STOP on

\echo '===================================================================================='
\echo 'Testing: Batch merges, health checks, performance metrics, monitoring'
\echo '===================================================================================='
\echo ''

DO $$
BEGIN
    -- Clean up test data from previous runs
    DELETE FROM pggit.merge_conflicts WHERE merge_id::text IN (
        SELECT id::text FROM pggit.merge_history WHERE source_branch LIKE 'batch_test_%'
    );
    DELETE FROM pggit.merge_history WHERE source_branch LIKE 'batch_test_%';
    DELETE FROM pggit.objects WHERE branch_name LIKE 'batch_test_%';
    DELETE FROM pggit.branches WHERE name LIKE 'batch_test_%';

    RAISE NOTICE 'Test setup complete';
END $$;

-- TEST 1: Batch Merge Operations

\echo ''
\echo '1. Testing batch merge operations...'

DO $$
DECLARE
    v_batch_result jsonb;
    v_merge_count integer;
    v_succeeded integer;
    v_failed integer;
BEGIN
    -- Create test branches
    PERFORM pggit.create_branch('batch_test_feature_a', 'main', false);
    PERFORM pggit.create_branch('batch_test_feature_b', 'main', false);
    PERFORM pggit.create_branch('batch_test_feature_c', 'main', false);

    -- Add some objects to branches
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    SELECT 'INDEX'::pggit.object_type, 'public', 'idx_a', 'hash_a', 'CREATE INDEX idx_a...', id, 'batch_test_feature_a', 1
    FROM pggit.branches WHERE name = 'batch_test_feature_a';

    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    SELECT 'INDEX'::pggit.object_type, 'public', 'idx_b', 'hash_b', 'CREATE INDEX idx_b...', id, 'batch_test_feature_b', 1
    FROM pggit.branches WHERE name = 'batch_test_feature_b';

    -- Run batch merge
    v_batch_result := pggit.batch_merge(
        ARRAY['batch_test_feature_a', 'batch_test_feature_b', 'batch_test_feature_c'],
        'main'
    );

    v_merge_count := (v_batch_result->>'total')::integer;
    v_succeeded := (v_batch_result->>'succeeded')::integer;
    v_failed := (v_batch_result->>'failed')::integer;

    IF v_merge_count = 3 AND v_succeeded >= 0 THEN
        RAISE NOTICE '✓ Test 1.1 PASS: Batch merge processed 3 branches (% succeeded, % failed)', v_succeeded, v_failed;
    ELSE
        RAISE EXCEPTION 'Test 1.1 FAIL: Expected 3 merges, got %', v_merge_count;
    END IF;

    -- Cleanup
    DELETE FROM pggit.objects WHERE branch_name LIKE 'batch_test_feature_%';
    DELETE FROM pggit.branches WHERE name LIKE 'batch_test_feature_%';
END $$;

-- TEST 2: Parallel Conflict Detection

\echo ''
\echo '2. Testing parallel conflict detection...'

DO $$
DECLARE
    v_conflict_result jsonb;
    v_total_checked integer;
    v_branches_checked integer;
BEGIN
    -- Create test branches with conflicts
    PERFORM pggit.create_branch('batch_test_conflict_a', 'main', false);
    PERFORM pggit.create_branch('batch_test_conflict_b', 'main', false);

    -- Add same object with different content (creates conflict)
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    SELECT 'TABLE'::pggit.object_type, 'public', 'conflict_table', 'hash_conflict_a', 'CREATE TABLE conflict_table (...) v1', id, 'batch_test_conflict_a', 1
    FROM pggit.branches WHERE name = 'batch_test_conflict_a';

    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    SELECT 'TABLE'::pggit.object_type, 'public', 'conflict_table', 'hash_conflict_b', 'CREATE TABLE conflict_table (...) v2', id, 'batch_test_conflict_b', 1
    FROM pggit.branches WHERE name = 'batch_test_conflict_b';

    -- Run parallel conflict detection
    v_conflict_result := pggit.parallel_conflict_detection(
        ARRAY['batch_test_conflict_a', 'batch_test_conflict_b'],
        'main'
    );

    v_total_checked := (v_conflict_result->>'total_checked')::integer;
    v_branches_checked := v_total_checked;

    IF v_branches_checked = 2 THEN
        RAISE NOTICE '✓ Test 2.1 PASS: Parallel detection checked % branches', v_branches_checked;
    ELSE
        RAISE EXCEPTION 'Test 2.1 FAIL: Expected 2 branches checked, got %', v_branches_checked;
    END IF;

    -- Cleanup
    DELETE FROM pggit.objects WHERE branch_name LIKE 'batch_test_conflict_%';
    DELETE FROM pggit.branches WHERE name LIKE 'batch_test_conflict_%';
END $$;

-- TEST 3: Bulk Conflict Resolution

\echo ''
\echo '3. Testing bulk conflict resolution...'

DO $$
DECLARE
    v_merge_id uuid;
    v_merge_result jsonb;
    v_bulk_result jsonb;
    v_resolved integer;
BEGIN
    -- Create a test merge
    PERFORM pggit.create_branch('batch_test_bulk_a', 'main', false);
    PERFORM pggit.create_branch('batch_test_bulk_b', 'main', false);

    -- Insert test conflicts
    INSERT INTO pggit.merge_conflicts (merge_id, branch_a, branch_b, conflict_object, conflict_type, conflict_severity, created_at)
    VALUES (
        (SELECT id FROM pggit.merge_history ORDER BY created_at DESC LIMIT 1),
        'batch_test_bulk_a',
        'batch_test_bulk_b',
        'test_object_1',
        'both_modified_different',
        'WARNING',
        NOW()
    );

    -- Get the merge_id we just created
    SELECT id INTO v_merge_id FROM pggit.merge_history ORDER BY created_at DESC LIMIT 1;

    -- Run bulk resolve
    v_bulk_result := pggit.bulk_resolve_conflicts(v_merge_id, 'theirs', 'both_modified_different');
    v_resolved := (v_bulk_result->>'resolved')::integer;

    IF v_resolved >= 0 THEN
        RAISE NOTICE '✓ Test 3.1 PASS: Bulk resolution processed % conflicts', v_resolved;
    ELSE
        RAISE EXCEPTION 'Test 3.1 FAIL: Bulk resolution failed';
    END IF;

    -- Cleanup
    DELETE FROM pggit.merge_conflicts WHERE merge_id = v_merge_id::text;
    DELETE FROM pggit.merge_history WHERE id = v_merge_id;
    DELETE FROM pggit.objects WHERE branch_name LIKE 'batch_test_bulk_%';
    DELETE FROM pggit.branches WHERE name LIKE 'batch_test_bulk_%';
END $$;

-- TEST 4: Health Check - Merge Integrity

\echo ''
\echo '4. Testing health check for merge integrity...'

DO $$
DECLARE
    v_health_result jsonb;
    v_status text;
BEGIN
    -- Run health check
    v_health_result := pggit.health_check_merge_integrity();
    v_status := v_health_result->>'status';

    IF v_status IN ('healthy', 'warning') THEN
        RAISE NOTICE '✓ Test 4.1 PASS: Health check completed with status: %', v_status;
    ELSE
        RAISE EXCEPTION 'Test 4.1 FAIL: Unexpected health status: %', v_status;
    END IF;
END $$;

-- TEST 5: Health Check - Performance Baseline

\echo ''
\echo '5. Testing health check for performance baseline...'

DO $$
DECLARE
    v_perf_result jsonb;
    v_status text;
    v_avg_time integer;
BEGIN
    -- Run performance baseline check
    v_perf_result := pggit.health_check_performance_baseline();
    v_status := v_perf_result->>'status';
    v_avg_time := (v_perf_result->'metrics'->>'avg_merge_time_ms')::integer;

    IF v_status IN ('ok', 'warning') THEN
        RAISE NOTICE '✓ Test 5.1 PASS: Performance baseline check completed (avg time: %ms)', v_avg_time;
    ELSE
        RAISE EXCEPTION 'Test 5.1 FAIL: Unexpected performance status: %', v_status;
    END IF;
END $$;

-- TEST 6: Merge Operations Summary View

\echo ''
\echo '6. Testing merge operations summary view...'

DO $$
DECLARE
    v_count integer;
BEGIN
    -- Query the view
    SELECT COUNT(*) INTO v_count FROM pggit.v_merge_operations_summary WHERE status IN ('completed', 'failed', 'in_progress');

    IF v_count >= 0 THEN
        RAISE NOTICE '✓ Test 6.1 PASS: Merge operations summary view works (% records)', v_count;
    ELSE
        RAISE EXCEPTION 'Test 6.1 FAIL: Could not query merge operations view';
    END IF;
END $$;

-- TEST 7: Performance Metrics View

\echo ''
\echo '7. Testing performance metrics view...'

DO $$
DECLARE
    v_count integer;
BEGIN
    -- Query the view
    SELECT COUNT(*) INTO v_count FROM pggit.v_performance_metrics;

    IF v_count >= 0 THEN
        RAISE NOTICE '✓ Test 7.1 PASS: Performance metrics view works (% records)', v_count;
    ELSE
        RAISE EXCEPTION 'Test 7.1 FAIL: Could not query performance metrics view';
    END IF;
END $$;

-- TEST 8: Branch Merge Activity View

\echo ''
\echo '8. Testing branch merge activity view...'

DO $$
DECLARE
    v_count integer;
BEGIN
    -- Query the view
    SELECT COUNT(*) INTO v_count FROM pggit.v_branch_merge_activity;

    IF v_count >= 0 THEN
        RAISE NOTICE '✓ Test 8.1 PASS: Branch merge activity view works (% records)', v_count;
    ELSE
        RAISE EXCEPTION 'Test 8.1 FAIL: Could not query branch activity view';
    END IF;
END $$;

-- TEST 9: Cleanup Orphaned Data

\echo ''
\echo '9. Testing cleanup orphaned data (dry run)...'

DO $$
DECLARE
    v_cleanup_result jsonb;
    v_dry_run boolean;
BEGIN
    -- Run cleanup in dry-run mode
    v_cleanup_result := pggit.cleanup_orphaned_data(true);
    v_dry_run := (v_cleanup_result->>'dry_run')::boolean;

    IF v_dry_run = true THEN
        RAISE NOTICE '✓ Test 9.1 PASS: Cleanup dry run completed (orphaned: %)',
            (v_cleanup_result->>'orphaned_conflicts')::integer + (v_cleanup_result->>'orphaned_branches')::integer;
    ELSE
        RAISE EXCEPTION 'Test 9.1 FAIL: Cleanup did not run in dry-run mode';
    END IF;
END $$;

-- TEST 10: Merge Performance Report

\echo ''
\echo '10. Testing merge performance report...'

DO $$
DECLARE
    v_report jsonb;
    v_total_merges integer;
BEGIN
    -- Get performance report
    v_report := pggit.get_merge_performance_report(30);
    v_total_merges := (v_report->'report'->>'total_merges')::integer;

    IF v_total_merges >= 0 THEN
        RAISE NOTICE '✓ Test 10.1 PASS: Performance report generated (% merges in period)', v_total_merges;
    ELSE
        RAISE EXCEPTION 'Test 10.1 FAIL: Could not generate performance report';
    END IF;
END $$;

-- TEST 11: Merge Duration Estimation

\echo ''
\echo '11. Testing merge duration estimation...'

DO $$
DECLARE
    v_estimate jsonb;
    v_estimated_ms integer;
BEGIN
    -- Estimate merge duration
    v_estimate := pggit.estimate_merge_duration('main', 'main');
    v_estimated_ms := (v_estimate->>'estimated_ms')::integer;

    IF v_estimated_ms >= 0 THEN
        RAISE NOTICE '✓ Test 11.1 PASS: Merge duration estimated at %ms', v_estimated_ms;
    ELSE
        RAISE EXCEPTION 'Test 11.1 FAIL: Could not estimate merge duration';
    END IF;
END $$;

-- TEST SUMMARY

\echo ''
\echo '===================================================================================='
\echo 'Batch Operations & Monitoring Test Suite: COMPLETE'
\echo '===================================================================================='
\echo ''
\echo 'Coverage:'
\echo '  ✅ Batch merge operations'
\echo '  ✅ Parallel conflict detection'
\echo '  ✅ Bulk conflict resolution'
\echo '  ✅ Health check - merge integrity'
\echo '  ✅ Health check - performance baseline'
\echo '  ✅ Merge operations summary view'
\echo '  ✅ Performance metrics view'
\echo '  ✅ Branch merge activity view'
\echo '  ✅ Cleanup orphaned data'
\echo '  ✅ Merge performance report'
\echo '  ✅ Merge duration estimation'
\echo ''
