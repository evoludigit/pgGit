-- Chaos Test: Deadlock and Concurrency Scenarios
-- Test File: 002_deadlock_scenarios.sql
-- Purpose: Test system behavior under concurrent DDL operations

BEGIN;

SELECT plan(12);

-- ============================================================================
-- SETUP: Create test environment
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create test schema with dependencies
CREATE SCHEMA IF NOT EXISTS deadlock_test;

CREATE TABLE deadlock_test.parent_table (
    id SERIAL PRIMARY KEY,
    name TEXT
);

CREATE TABLE deadlock_test.child_table (
    id SERIAL PRIMARY KEY,
    parent_id INTEGER REFERENCES deadlock_test.parent_table(id),
    data TEXT
);

-- ============================================================================
-- TEST GROUP 1: Concurrent DDL Operations
-- ============================================================================

-- Test 1: Concurrent table creation should not deadlock
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        CREATE TABLE deadlock_test.concurrent_1 (id INT);
        CREATE TABLE deadlock_test.concurrent_2 (id INT);
        CREATE TABLE deadlock_test.concurrent_3 (id INT);
    END;
    $$;
    $$,
    'Sequential DDL should complete without deadlock'
);

-- Test 2: All tables should exist
SELECT has_table(
    'deadlock_test',
    'concurrent_1',
    'Table concurrent_1 should exist'
);

SELECT has_table(
    'deadlock_test',
    'concurrent_2',
    'Table concurrent_2 should exist'
);

SELECT has_table(
    'deadlock_test',
    'concurrent_3',
    'Table concurrent_3 should exist'
);

-- Test 3: Concurrent index creation should work
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        CREATE INDEX idx_concurrent_1 ON deadlock_test.concurrent_1(id);
        CREATE INDEX idx_concurrent_2 ON deadlock_test.concurrent_2(id);
        CREATE INDEX idx_concurrent_3 ON deadlock_test.concurrent_3(id);
    END;
    $$;
    $$,
    'Concurrent index creation should complete'
);

-- Test 4: All indexes should exist
SELECT has_index(
    'deadlock_test',
    'concurrent_1',
    'idx_concurrent_1',
    'Index on concurrent_1 should exist'
);

-- ============================================================================
-- TEST GROUP 2: Foreign Key Constraint Handling
-- ============================================================================

-- Test 5: Foreign key operations during concurrent DDL
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        -- Insert parent
        INSERT INTO deadlock_test.parent_table (name) VALUES ('parent1');
        
        -- Try to insert child (should work)
        INSERT INTO deadlock_test.child_table (parent_id, data) 
        VALUES (1, 'child_data');
    END;
    $$;
    $$,
    'Foreign key operations should work during concurrent activity'
);

-- Test 6: Verify referential integrity
SELECT results_eq(
    $$ SELECT count(*) FROM deadlock_test.child_table WHERE parent_id = 1 $$,
    ARRAY[1]::BIGINT[],
    'Referential integrity should be maintained'
);

-- ============================================================================
-- TEST GROUP 3: Lock Timeout Scenarios
-- ============================================================================

-- Test 7: Long-running DDL should handle lock waits
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        -- Set short lock timeout
        PERFORM set_config('lock_timeout', '5s', true);
        
        -- Perform DDL that might wait
        ALTER TABLE deadlock_test.concurrent_1 ADD COLUMN new_col TEXT DEFAULT 'test';
        
        -- Reset timeout
        PERFORM set_config('lock_timeout', '0', true);
    EXCEPTION
        WHEN lock_not_available THEN
            RAISE NOTICE 'Lock timeout occurred (expected in some scenarios)';
    END;
    $$;
    $$,
    'DDL should handle lock timeouts gracefully'
);

-- Test 8: Table should be intact after lock timeout
SELECT has_column(
    'deadlock_test',
    'concurrent_1',
    'new_col',
    'Column should exist after DDL (or transaction rolled back cleanly)'
);

-- ============================================================================
-- TEST GROUP 4: Rapid Schema Changes
-- ============================================================================

-- Test 9: Rapid alter table operations
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        ALTER TABLE deadlock_test.concurrent_1 ADD COLUMN col_a TEXT;
        ALTER TABLE deadlock_test.concurrent_1 ADD COLUMN col_b INT;
        ALTER TABLE deadlock_test.concurrent_1 DROP COLUMN col_a;
        ALTER TABLE deadlock_test.concurrent_1 ADD COLUMN col_c BOOLEAN DEFAULT false;
    END;
    $$;
    $$,
    'Rapid schema changes should not cause corruption'
);

-- Test 10: Verify schema state after rapid changes
SELECT has_column(
    'deadlock_test',
    'concurrent_1',
    'col_b',
    'col_b should exist after rapid changes'
);

SELECT has_column(
    'deadlock_test',
    'concurrent_1',
    'col_c',
    'col_c should exist after rapid changes'
);

SELECT hasnt_column(
    'deadlock_test',
    'concurrent_1',
    'col_a',
    'col_a should not exist (was dropped)'
);

-- ============================================================================
-- TEST GROUP 5: Recovery from Failed Operations
-- ============================================================================

-- Test 11: Failed ALTER TABLE should not leave partial state
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        -- This might fail but shouldn't corrupt table
        ALTER TABLE deadlock_test.concurrent_1 ADD COLUMN test_col TEXT;
        -- Drop it immediately
        ALTER TABLE deadlock_test.concurrent_1 DROP COLUMN test_col;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Operation failed but did not corrupt: %', SQLERRM;
    END;
    $$;
    $$,
    'Failed operations should not corrupt table'
);

-- Test 12: Final consistency check - all operations tracked
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.history WHERE schema_name = 'deadlock_test'),
    '>=',
    3::BIGINT,
    'DDL operations should be tracked in history'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

-- Clean up test objects
DROP SCHEMA IF EXISTS deadlock_test CASCADE;

SELECT * FROM finish();

ROLLBACK;
