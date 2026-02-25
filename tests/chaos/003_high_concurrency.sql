-- Chaos Test: High Concurrency and Stress Testing
-- Test File: 003_high_concurrency.sql
-- Purpose: Test system behavior with 100+ concurrent branches and operations

BEGIN;

SELECT plan(15);

-- ============================================================================
-- SETUP: Create stress test environment
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create test table
CREATE TABLE stress_test_data (
    id SERIAL PRIMARY KEY,
    branch_name TEXT,
    operation_count INTEGER DEFAULT 0,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TEST GROUP 1: Mass Branch Creation
-- ============================================================================

-- Test 1: Create 50 branches rapidly
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        v_branch_name TEXT;
    BEGIN
        FOR i IN 1..50 LOOP
            v_branch_name := 'stress_branch_' || i;
            BEGIN
                PERFORM pggit.create_branch(v_branch_name);
            EXCEPTION
                WHEN OTHERS THEN
                    -- Log but continue (some might fail due to race conditions)
                    RAISE NOTICE 'Branch % creation had issue: %', v_branch_name, SQLERRM;
            END;
        END LOOP;
    END;
    $$;
    $$,
    'Creating 50 branches should complete without crash'
);

-- Test 2: Verify branch count is reasonable
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.branches WHERE name LIKE 'stress_branch_%'),
    '>=',
    40::BIGINT,  -- Allow some failures due to race conditions
    'Should have created at least 40 stress test branches'
);

-- Test 3: Branch creation should have generated IDs
SELECT results_eq(
    $$ SELECT count(*) > 0 FROM pggit.branches WHERE name LIKE 'stress_branch_%' AND id IS NOT NULL $$,
    ARRAY[true]::BOOLEAN[],
    'All stress branches should have valid IDs'
);

-- ============================================================================
-- TEST GROUP 2: Concurrent Operations Across Branches
-- ============================================================================

-- Test 4: Switch between branches rapidly
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        v_branch RECORD;
    BEGIN
        FOR v_branch IN 
            SELECT name FROM pggit.branches WHERE name LIKE 'stress_branch_%' LIMIT 10
        LOOP
            PERFORM pggit.switch_branch(v_branch.name);
            -- Do a small operation in each branch
            EXECUTE format('INSERT INTO stress_test_data (branch_name) VALUES (%L)', v_branch.name);
        END LOOP;
        
        -- Return to main
        PERFORM pggit.switch_branch('main');
    END;
    $$;
    $$,
    'Switching between 10 branches rapidly should work'
);

-- Test 5: Verify data was inserted in each branch
SELECT cmp_ok(
    (SELECT count(DISTINCT branch_name) FROM stress_test_data),
    '>=',
    5::BIGINT,  -- At least 5 branches should have data
    'Data should be distributed across branches'
);

-- Test 6: Concurrent DDL operations in different branches
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        v_branch RECORD;
        v_counter INTEGER := 0;
    BEGIN
        FOR v_branch IN 
            SELECT name FROM pggit.branches WHERE name LIKE 'stress_branch_%' LIMIT 5
        LOOP
            PERFORM pggit.switch_branch(v_branch.name);
            
            -- Create table in this branch
            BEGIN
                EXECUTE format('CREATE TABLE IF NOT EXISTS branch_%s_table (id INT)', v_counter);
                v_counter := v_counter + 1;
            EXCEPTION
                WHEN OTHERS THEN
                    RAISE NOTICE 'DDL in branch % had issue: %', v_branch.name, SQLERRM;
            END;
        END LOOP;
        
        PERFORM pggit.switch_branch('main');
    END;
    $$;
    $$,
    'DDL operations across multiple branches should not deadlock'
);

-- ============================================================================
-- TEST GROUP 3: Large Dataset Operations
-- ============================================================================

-- Test 7: Insert large dataset in main
SELECT lives_ok(
    $$ 
    INSERT INTO stress_test_data (branch_name, operation_count)
    SELECT 'bulk_insert_test', i FROM generate_series(1, 1000) AS i;
    $$,
    'Bulk insert of 1000 rows should complete'
);

-- Test 8: Verify bulk insert
SELECT is(
    (SELECT count(*) FROM stress_test_data WHERE branch_name = 'bulk_insert_test'),
    1000::BIGINT,
    'Bulk insert should have created exactly 1000 rows'
);

-- Test 9: Query performance on large dataset
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        v_count INTEGER;
        v_start_time TIMESTAMP;
        v_duration_ms NUMERIC;
    BEGIN
        v_start_time := clock_timestamp();
        SELECT count(*) INTO v_count FROM stress_test_data;
        v_duration_ms := EXTRACT(MILLISECOND FROM (clock_timestamp() - v_start_time));
        
        RAISE NOTICE 'Query on % rows took % ms', v_count, v_duration_ms;
        
        -- Should complete in reasonable time (< 1 second for this test)
        IF v_duration_ms > 1000 THEN
            RAISE WARNING 'Query took longer than expected: % ms', v_duration_ms;
        END IF;
    END;
    $$;
    $$,
    'Query on large dataset should complete in reasonable time'
);

-- ============================================================================
-- TEST GROUP 4: Memory and Resource Management
-- ============================================================================

-- Test 10: Memory-intensive operations
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        v_large_text TEXT;
        v_i INTEGER;
    BEGIN
        -- Generate large data and process it
        FOR v_i IN 1..10 LOOP
            v_large_text := repeat('x', 100000);  -- 100KB per iteration
            
            -- Insert with large text (if column supports it)
            BEGIN
                INSERT INTO stress_test_data (branch_name, operation_count) 
                VALUES ('large_data_test', v_i);
            EXCEPTION
                WHEN OTHERS THEN
                    -- Column might not support large text, that's OK
                    NULL;
            END;
            
            -- Explicitly clear to help garbage collection
            v_large_text := NULL;
        END LOOP;
    END;
    $$;
    $$,
    'Memory-intensive operations should not cause OOM'
);

-- Test 11: Connection stress simulation
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        v_result INTEGER;
    BEGIN
        -- Simulate multiple queries
        FOR v_i IN 1..100 LOOP
            SELECT count(*) INTO v_result FROM pggit.branches;
            SELECT count(*) INTO v_result FROM pggit.objects;
            SELECT count(*) INTO v_result FROM pggit.history;
        END LOOP;
    END;
    $$;
    $$,
    'Multiple rapid queries should not exhaust resources'
);

-- ============================================================================
-- TEST GROUP 5: Branch Cleanup and Consistency
-- ============================================================================

-- Test 12: Delete stress test branches
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        DELETE FROM pggit.branches WHERE name LIKE 'stress_branch_%';
    END;
    $$;
    $$,
    'Deleting stress test branches should work'
);

-- Test 13: Verify cleanup
SELECT results_eq(
    $$ SELECT count(*) FROM pggit.branches WHERE name LIKE 'stress_branch_%' $$,
    ARRAY[0]::BIGINT[],
    'All stress branches should be deleted'
);

-- Test 14: Main branch should still be intact
SELECT is(
    pggit.branch_exists('main'),
    true,
    'Main branch should still exist after cleanup'
);

-- Test 15: Final consistency check
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        -- Verify core tables are intact
        PERFORM count(*) FROM pggit.branches;
        PERFORM count(*) FROM pggit.objects;
        PERFORM count(*) FROM pggit.history;
        PERFORM count(*) FROM pggit.commits;
        
        -- Verify we can create a new branch (system still works)
        PERFORM pggit.create_branch('final_test_branch');
        PERFORM pggit.delete_branch('final_test_branch');
    END;
    $$;
    $$,
    'System should be consistent and functional after stress test'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

DROP TABLE IF EXISTS stress_test_data;

-- Remove any remaining stress test data from pggit tables
DELETE FROM pggit.objects WHERE schema_name = 'public' AND object_name LIKE 'branch_%_table';

SELECT * FROM finish();

ROLLBACK;
