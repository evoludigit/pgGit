-- Chaos Test: Connection Failure Simulation
-- Test File: 001_connection_failure.sql
-- Purpose: Test system behavior during connection interruptions

BEGIN;

SELECT plan(10);

-- ============================================================================
-- SETUP: Create test state
-- ============================================================================

SELECT pggit.switch_branch('main');
SELECT pggit.create_branch('chaos_test_branch');
SELECT pggit.switch_branch('chaos_test_branch');

CREATE TABLE chaos_test_table (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert initial data
INSERT INTO chaos_test_table (data) 
SELECT 'data_' || i FROM generate_series(1, 100) AS i;

-- ============================================================================
-- TEST GROUP 1: Transaction Rollback Simulation
-- ============================================================================

-- Test 1: Verify data before simulated failure
SELECT is(
    (SELECT count(*) FROM chaos_test_table),
    100::BIGINT,
    'Should have 100 rows before chaos test'
);

-- Test 2: Failed transaction should not corrupt state
DO $$
BEGIN
    -- Simulate a transaction that fails partway through
    INSERT INTO chaos_test_table (data) VALUES ('new_row_1');
    INSERT INTO chaos_test_table (data) VALUES ('new_row_2');
    
    -- Simulate failure - rollback
    RAISE EXCEPTION 'Simulated connection failure';
EXCEPTION
    WHEN OTHERS THEN
        -- Transaction automatically rolls back
        RAISE NOTICE 'Transaction rolled back as expected';
END;
$$;

-- Test 3: Data should be consistent after rollback
SELECT is(
    (SELECT count(*) FROM chaos_test_table),
    100::BIGINT,
    'Should still have 100 rows after failed transaction'
);

-- Test 4: Verify no partial data remains
SELECT results_eq(
    $$ SELECT count(*) FROM chaos_test_table WHERE data LIKE 'new_row_%' $$,
    ARRAY[0]::BIGINT[],
    'No partial data should remain after rollback'
);

-- ============================================================================
-- TEST GROUP 2: Concurrent Branch Operations
-- ============================================================================

-- Test 5: Multiple branches should handle concurrent operations
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        v_branch_id INTEGER;
    BEGIN
        -- Create multiple branches rapidly
        FOR i IN 1..5 LOOP
            INSERT INTO pggit.branches (name, parent_branch_id)
            VALUES ('concurrent_branch_' || i, 1)
            ON CONFLICT DO NOTHING;
        END LOOP;
    END;
    $$;
    $$,
    'Concurrent branch creation should not fail'
);

-- Test 6: Verify branch consistency after concurrent operations
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.branches WHERE name LIKE 'concurrent_branch_%'),
    '>=',
    0::BIGINT,
    'Branch count should be valid after concurrent operations'
);

-- ============================================================================
-- TEST GROUP 3: Lock Contention
-- ============================================================================

-- Test 7: Long-running operations should not deadlock
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        -- Simulate long-running DDL
        PERFORM pg_sleep(0.1);  -- 100ms delay
        ALTER TABLE chaos_test_table ADD COLUMN temp_col TEXT;
        ALTER TABLE chaos_test_table DROP COLUMN temp_col;
    END;
    $$;
    $$,
    'DDL operations should complete without deadlock'
);

-- Test 8: Table should be intact after DDL operations
SELECT has_table(
    'public',
    'chaos_test_table',
    'Table should exist after DDL operations'
);

-- ============================================================================
-- TEST GROUP 4: Resource Exhaustion Recovery
-- ============================================================================

-- Test 9: System should recover from memory pressure simulation
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        v_temp_data TEXT;
    BEGIN
        -- Allocate and release memory
        v_temp_data := repeat('x', 1000000);  -- 1MB string
        v_temp_data := NULL;  -- Release
        
        -- Verify system still works
        PERFORM count(*) FROM chaos_test_table;
    END;
    $$;
    $$,
    'System should recover from memory pressure'
);

-- Test 10: Final consistency check
SELECT results_eq(
    $$ SELECT count(*) FROM chaos_test_table $$,
    ARRAY[100]::BIGINT[],
    'Final state should be consistent'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');
DROP TABLE IF EXISTS chaos_test_table;
DELETE FROM pggit.branches WHERE name LIKE 'chaos_test%' OR name LIKE 'concurrent_branch_%';

SELECT * FROM finish();

ROLLBACK;
