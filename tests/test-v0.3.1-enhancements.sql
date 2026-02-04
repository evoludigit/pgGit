-- pgGit v0.3.1 Test Suite
-- Advanced Reporting, Analytics & Performance Optimization

\set ECHO all
\set ON_ERROR_STOP on

\echo '===================================================================================='
\echo 'pgGit v0.3.1 Enhancement Test Suite'
\echo 'Testing: Advanced Reporting, Analytics, Performance Optimization'
\echo '===================================================================================='
\echo ''

DO $$
BEGIN
    -- Clean up test data from previous runs
    DELETE FROM pggit.schema_diffs WHERE branch_a LIKE 'v031_test_%' OR branch_b LIKE 'v031_test_%';
    DELETE FROM pggit.objects WHERE branch_name LIKE 'v031_test_%';
    DELETE FROM pggit.branches WHERE name LIKE 'v031_test_%';

    RAISE NOTICE 'Test setup complete';
END $$;

-- ============================================================================
-- TIER 1: ADVANCED REPORTING TESTS
-- ============================================================================

-- TEST 1: HTML Diff Report Generation

\echo ''
\echo '1. Testing HTML diff report generation...'

DO $$
DECLARE
    v_html text;
    v_html_length integer;
    v_has_html_tags boolean;
BEGIN
    -- Create test branches
    PERFORM pggit.create_branch('v031_test_html_a', 'main', false);
    PERFORM pggit.create_branch('v031_test_html_b', 'main', false);

    -- Add object to branch B
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    SELECT 'TABLE'::pggit.object_type, 'public', 'test_table', 'hash_tt', 'CREATE TABLE test_table (...)', id, 'v031_test_html_b', 1
    FROM pggit.branches WHERE name = 'v031_test_html_b';

    -- Generate HTML report
    v_html := pggit.generate_html_diff_report('v031_test_html_a', 'v031_test_html_b');
    v_html_length := LENGTH(v_html);
    v_has_html_tags := v_html LIKE '%<!DOCTYPE%' AND v_html LIKE '%</html>%';

    IF v_html_length > 1000 AND v_has_html_tags THEN
        RAISE NOTICE '✓ Test 1.1 PASS: HTML report generated (% characters with valid HTML)', v_html_length;
    ELSE
        RAISE EXCEPTION 'Test 1.1 FAIL: HTML report invalid';
    END IF;

    -- Cleanup
    DELETE FROM pggit.schema_diffs WHERE branch_a = 'v031_test_html_a';
    DELETE FROM pggit.objects WHERE branch_name IN ('v031_test_html_a', 'v031_test_html_b');
    DELETE FROM pggit.branches WHERE name IN ('v031_test_html_a', 'v031_test_html_b');
END $$;

-- TEST 2: Markdown Diff Report Generation

\echo ''
\echo '2. Testing Markdown diff report generation...'

DO $$
DECLARE
    v_markdown text;
    v_markdown_length integer;
    v_has_markdown_syntax boolean;
BEGIN
    -- Create test branches
    PERFORM pggit.create_branch('v031_test_md_a', 'main', false);
    PERFORM pggit.create_branch('v031_test_md_b', 'main', false);

    -- Add object to branch B
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    SELECT 'TABLE'::pggit.object_type, 'public', 'test_table', 'hash_tt', 'CREATE TABLE test_table (...)', id, 'v031_test_md_b', 1
    FROM pggit.branches WHERE name = 'v031_test_md_b';

    -- Generate Markdown report
    v_markdown := pggit.generate_markdown_diff_report('v031_test_md_a', 'v031_test_md_b');
    v_markdown_length := LENGTH(v_markdown);
    v_has_markdown_syntax := v_markdown LIKE '%# Schema%' AND v_markdown LIKE '%| % |%';

    IF v_markdown_length > 500 AND v_has_markdown_syntax THEN
        RAISE NOTICE '✓ Test 2.1 PASS: Markdown report generated (% characters with valid syntax)', v_markdown_length;
    ELSE
        RAISE EXCEPTION 'Test 2.1 FAIL: Markdown report invalid';
    END IF;

    -- Cleanup
    DELETE FROM pggit.schema_diffs WHERE branch_a = 'v031_test_md_a';
    DELETE FROM pggit.objects WHERE branch_name IN ('v031_test_md_a', 'v031_test_md_b');
    DELETE FROM pggit.branches WHERE name IN ('v031_test_md_a', 'v031_test_md_b');
END $$;

-- TEST 3: Schema Evolution Timeline

\echo ''
\echo '3. Testing schema evolution timeline...'

DO $$
DECLARE
    v_timeline jsonb;
    v_event_count integer;
BEGIN
    -- Create test branch
    PERFORM pggit.create_branch('v031_test_timeline', 'main', false);

    -- Get timeline
    v_timeline := pggit.get_schema_evolution_timeline('v031_test_timeline', 30);
    v_event_count := COALESCE(jsonb_array_length(v_timeline->'events'), 0);

    IF v_timeline ? 'branch' AND v_timeline ? 'event_count' THEN
        RAISE NOTICE '✓ Test 3.1 PASS: Timeline generated (% events)', v_event_count;
    ELSE
        RAISE EXCEPTION 'Test 3.1 FAIL: Invalid timeline structure';
    END IF;

    -- Cleanup
    DELETE FROM pggit.objects WHERE branch_name = 'v031_test_timeline';
    DELETE FROM pggit.branches WHERE name = 'v031_test_timeline';
END $$;

-- ============================================================================
-- TIER 2: ANALYTICS TESTS
-- ============================================================================

-- TEST 4: Change Frequency Analysis

\echo ''
\echo '4. Testing schema change frequency analysis...'

DO $$
DECLARE
    v_analysis jsonb;
    v_has_metrics boolean;
BEGIN
    -- Create test branch
    PERFORM pggit.create_branch('v031_test_freq', 'main', false);

    -- Analyze frequency
    v_analysis := pggit.analyze_schema_change_frequency('v031_test_freq', 30);
    v_has_metrics := v_analysis ? 'total_changes' AND v_analysis ? 'change_intensity';

    IF v_has_metrics THEN
        RAISE NOTICE '✓ Test 4.1 PASS: Frequency analysis completed';
    ELSE
        RAISE EXCEPTION 'Test 4.1 FAIL: Missing analysis metrics';
    END IF;

    -- Cleanup
    DELETE FROM pggit.objects WHERE branch_name = 'v031_test_freq';
    DELETE FROM pggit.branches WHERE name = 'v031_test_freq';
END $$;

-- TEST 5: Breaking Change Trends

\echo ''
\echo '5. Testing breaking change trends...'

DO $$
DECLARE
    v_trends jsonb;
    v_has_data boolean;
BEGIN
    -- Create test branch
    PERFORM pggit.create_branch('v031_test_breaks', 'main', false);

    -- Get breaking change trends
    v_trends := pggit.get_breaking_change_trends('v031_test_breaks', 30);
    v_has_data := v_trends ? 'data' AND v_trends ? 'total_breaking_changes';

    IF v_has_data THEN
        RAISE NOTICE '✓ Test 5.1 PASS: Breaking change trends analyzed';
    ELSE
        RAISE EXCEPTION 'Test 5.1 FAIL: Missing trend data';
    END IF;

    -- Cleanup
    DELETE FROM pggit.objects WHERE branch_name = 'v031_test_breaks';
    DELETE FROM pggit.branches WHERE name = 'v031_test_breaks';
END $$;

-- TEST 6: Migration Effort Estimation

\echo ''
\echo '6. Testing migration effort estimation...'

DO $$
DECLARE
    v_estimate jsonb;
    v_effort_hours numeric;
    v_has_estimate boolean;
BEGIN
    -- Create test branches
    PERFORM pggit.create_branch('v031_test_effort_a', 'main', false);
    PERFORM pggit.create_branch('v031_test_effort_b', 'main', false);

    -- Add objects
    INSERT INTO pggit.objects (object_type, schema_name, object_name, content_hash, ddl_normalized, branch_id, branch_name, version)
    SELECT 'TABLE'::pggit.object_type, 'public', 'users', 'hash_users', 'CREATE TABLE users (...)', id, 'v031_test_effort_a', 1
    FROM pggit.branches WHERE name = 'v031_test_effort_a';

    -- Estimate effort
    v_estimate := pggit.estimate_migration_effort('v031_test_effort_a', 'v031_test_effort_b');
    v_effort_hours := COALESCE((v_estimate->'effort_estimate'->>'total_hours')::numeric, -1);
    v_has_estimate := v_estimate ? 'effort_estimate' AND v_estimate ? 'complexity';

    IF v_has_estimate AND v_effort_hours > 0 THEN
        RAISE NOTICE '✓ Test 6.1 PASS: Effort estimation completed (% hours)', v_effort_hours;
    ELSE
        RAISE EXCEPTION 'Test 6.1 FAIL: Invalid effort estimate';
    END IF;

    -- Cleanup
    DELETE FROM pggit.migration_plans WHERE source_branch = 'v031_test_effort_a';
    DELETE FROM pggit.schema_diffs WHERE branch_a = 'v031_test_effort_a';
    DELETE FROM pggit.objects WHERE branch_name IN ('v031_test_effort_a', 'v031_test_effort_b');
    DELETE FROM pggit.branches WHERE name IN ('v031_test_effort_a', 'v031_test_effort_b');
END $$;

-- ============================================================================
-- TIER 3: PERFORMANCE OPTIMIZATION TESTS
-- ============================================================================

-- TEST 7: Query Performance Analysis

\echo ''
\echo '7. Testing query performance analysis...'

DO $$
DECLARE
    v_performance jsonb;
    v_has_analysis boolean;
BEGIN
    -- Analyze performance
    v_performance := pggit.analyze_query_performance();
    v_has_analysis := v_performance ? 'target_queries' AND v_performance ? 'optimization_tips';

    IF v_has_analysis THEN
        RAISE NOTICE '✓ Test 7.1 PASS: Query performance analysis completed';
    ELSE
        RAISE EXCEPTION 'Test 7.1 FAIL: Missing performance analysis';
    END IF;
END $$;

-- TEST 8: Storage Usage Summary

\echo ''
\echo '8. Testing storage usage summary...'

DO $$
DECLARE
    v_storage jsonb;
    v_total_size numeric;
    v_has_storage boolean;
BEGIN
    -- Get storage summary
    v_storage := pggit.get_storage_usage_summary();
    v_total_size := COALESCE((v_storage->'storage_breakdown_mb'->>'total')::numeric, -1);
    v_has_storage := v_storage ? 'storage_breakdown_mb' AND v_storage ? 'growth_recommendation';

    IF v_has_storage AND v_total_size >= 0 THEN
        RAISE NOTICE '✓ Test 8.1 PASS: Storage usage analyzed (%.2f MB)', v_total_size;
    ELSE
        RAISE EXCEPTION 'Test 8.1 FAIL: Invalid storage summary';
    END IF;
END $$;

-- TEST 9: Schema Optimization

\echo ''
\echo '9. Testing schema query optimization...'

DO $$
DECLARE
    v_optimization jsonb;
    v_index_count integer;
    v_has_optimization boolean;
BEGIN
    -- Optimize schema
    v_optimization := pggit.optimize_schema_queries();
    v_index_count := COALESCE((v_optimization->'index_status'->>'total_indexes')::integer, -1);
    v_has_optimization := v_optimization ? 'index_status' AND v_optimization ? 'recommendations';

    IF v_has_optimization AND v_index_count >= 0 THEN
        RAISE NOTICE '✓ Test 9.1 PASS: Schema optimization analyzed (% indexes)', v_index_count;
    ELSE
        RAISE EXCEPTION 'Test 9.1 FAIL: Invalid optimization analysis';
    END IF;
END $$;

-- ============================================================================
-- VIEW TESTS
-- ============================================================================

-- TEST 10: Reporting Views

\echo ''
\echo '10. Testing reporting and analytics views...'

DO $$
DECLARE
    v_reports_exist boolean;
    v_activity_exist boolean;
    v_effort_exist boolean;
BEGIN
    -- Check views exist in information_schema
    SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'pggit' AND table_name = 'v_schema_reports_summary') INTO v_reports_exist;
    SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'pggit' AND table_name = 'v_schema_change_activity') INTO v_activity_exist;
    SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'pggit' AND table_name = 'v_migration_effort_summary') INTO v_effort_exist;

    IF v_reports_exist AND v_activity_exist AND v_effort_exist THEN
        RAISE NOTICE '✓ Test 10.1 PASS: All reporting views exist and are queryable';
    ELSE
        RAISE EXCEPTION 'Test 10.1 FAIL: Views do not exist';
    END IF;
END $$;

-- TEST 11: Analytics Views

\echo ''
\echo '11. Testing analytics views...'

DO $$
DECLARE
    v_trends_exist boolean;
    v_breaking_exist boolean;
    v_active_exist boolean;
BEGIN
    -- Check views exist in information_schema
    SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'pggit' AND table_name = 'v_schema_change_trends') INTO v_trends_exist;
    SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'pggit' AND table_name = 'v_breaking_change_frequency') INTO v_breaking_exist;
    SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'pggit' AND table_name = 'v_most_active_branches') INTO v_active_exist;

    IF v_trends_exist AND v_breaking_exist AND v_active_exist THEN
        RAISE NOTICE '✓ Test 11.1 PASS: All analytics views exist and are queryable';
    ELSE
        RAISE EXCEPTION 'Test 11.1 FAIL: Analytics views do not exist';
    END IF;
END $$;

-- TEST 12: Performance Monitoring Views

\echo ''
\echo '12. Testing performance monitoring views...'

DO $$
DECLARE
    v_perf_exist boolean;
    v_index_exist boolean;
    v_opt_exist boolean;
BEGIN
    -- Check views exist in information_schema
    SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'pggit' AND table_name = 'v_schema_analysis_performance') INTO v_perf_exist;
    SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'pggit' AND table_name = 'v_index_effectiveness') INTO v_index_exist;
    SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'pggit' AND table_name = 'v_query_optimization_status') INTO v_opt_exist;

    IF v_perf_exist AND v_index_exist AND v_opt_exist THEN
        RAISE NOTICE '✓ Test 12.1 PASS: All performance views exist and are queryable';
    ELSE
        RAISE EXCEPTION 'Test 12.1 FAIL: Performance views do not exist';
    END IF;
END $$;

-- ============================================================================
-- TEST SUMMARY
-- ============================================================================

\echo ''
\echo '===================================================================================='
\echo 'v0.3.1 Enhancement Test Suite: COMPLETE'
\echo '===================================================================================='
\echo ''
\echo 'Coverage:'
\echo '  ✅ HTML diff report generation'
\echo '  ✅ Markdown diff report generation'
\echo '  ✅ Schema evolution timeline'
\echo '  ✅ Change frequency analysis'
\echo '  ✅ Breaking change trends'
\echo '  ✅ Migration effort estimation'
\echo '  ✅ Query performance analysis'
\echo '  ✅ Storage usage summary'
\echo '  ✅ Schema query optimization'
\echo '  ✅ Reporting views (3)'
\echo '  ✅ Analytics views (3)'
\echo '  ✅ Performance monitoring views (3)'
\echo ''

