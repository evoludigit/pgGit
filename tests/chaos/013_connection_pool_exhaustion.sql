-- Chaos Test: Connection Pool Exhaustion
-- Test File: 013_connection_pool_exhaustion.sql
-- Purpose: Test behavior under connection pool pressure

BEGIN;

SELECT plan(14);

-- ============================================================================
-- SETUP: Create test environment
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create test table
CREATE TABLE conn_pool_test (
    id SERIAL PRIMARY KEY,
    session_id TEXT,
    operation_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TEST GROUP 1: Rapid Connection Simulation
-- ============================================================================

-- Test 1: Simulate rapid session creation
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        -- Simulate multiple operations in rapid succession
        FOR i IN 1..30 LOOP
            INSERT INTO conn_pool_test (session_id, operation_count) 
            VALUES ('session_' || i, i);
        END LOOP;
    END;
    $$;
    $$,
    'Should handle rapid inserts'
);

-- Test 2: Verify all data inserted
SELECT is(
    (SELECT count(*) FROM conn_pool_test),
    30::BIGINT,
    'Should have 30 rows from rapid inserts'
);

-- ============================================================================
-- TEST GROUP 2: DDL Under Connection Pressure
-- ============================================================================

-- Test 3: Create table while connections active
SELECT lives_ok(
    $$ CREATE TABLE conn_pool_temp_1 (id INT PRIMARY KEY, data TEXT); $$,
    'Should create table under load'
);

-- Test 4: Create index under pressure
SELECT lives_ok(
    $$ CREATE INDEX idx_conn_pool ON conn_pool_test(operation_count); $$,
    'Should create index under load'
);

-- Test 5: DDL tracking should work
SELECT results_eq(
    $$ SELECT count(*) > 0 FROM pggit.objects WHERE object_name = 'conn_pool_temp_1' $$,
    ARRAY[true]::BOOLEAN[],
    'DDL tracking should capture new table'
);

-- ============================================================================
-- TEST GROUP 3: Branch Operations Under Pressure
-- ============================================================================

-- Test 6: Create multiple branches rapidly
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        FOR i IN 1..5 LOOP
            PERFORM pggit.create_branch('conn_pool_branch_' || i);
        END LOOP;
    END;
    $$;
    $$,
    'Should create 5 branches rapidly'
);

-- Test 7: Verify branches created
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.branches WHERE name LIKE 'conn_pool_branch_%'),
    '>=',
    5::BIGINT,
    'Should have 5 connection pool test branches'
);

-- Test 8: Switch between branches rapidly
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        PERFORM pggit.switch_branch('conn_pool_branch_1');
        PERFORM pg_sleep(0.05);
        PERFORM pggit.switch_branch('conn_pool_branch_2');
        PERFORM pg_sleep(0.05);
        PERFORM pggit.switch_branch('main');
    END;
    $$;
    $$,
    'Should switch branches rapidly'
);

-- ============================================================================
-- TEST GROUP 4: Concurrent Operations
-- ============================================================================

-- Test 9: Multiple DDL operations in sequence
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        FOR i IN 2..5 LOOP
            EXECUTE format('CREATE TABLE conn_pool_temp_%s (id INT)', i);
        END LOOP;
    END;
    $$;
    $$,
    'Should create multiple temp tables'
);

-- Test 10: Verify DDL tracking captured all
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.objects WHERE object_name LIKE 'conn_pool_temp_%'),
    '>=',
    4::BIGINT,
    'Should track multiple temp tables'
);

-- Test 11: Query performance under load
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        FOR i IN 1..10 LOOP
            PERFORM count(*) FROM conn_pool_test;
        END LOOP;
    END;
    $$;
    $$,
    'Should handle repeated queries'
);

-- ============================================================================
-- TEST GROUP 5: Cleanup and Recovery
-- ============================================================================

-- Test 12: Health check should pass
SELECT results_eq(
    $$ SELECT status FROM pggit.health_check() WHERE check_name = 'database_connection' $$,
    ARRAY['healthy']::TEXT[],
    'Health check should pass'
);

-- Test 13: DDL tracking continues after pressure
SELECT lives_ok(
    $$ ALTER TABLE conn_pool_test ADD COLUMN final_col TEXT; $$,
    'DDL should work after connection pressure'
);

-- Test 14: Final state consistent
SELECT is(
    (SELECT count(*) FROM conn_pool_test),
    30::BIGINT,
    'Final row count should be consistent'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up branches
DELETE FROM pggit.branches WHERE name LIKE 'conn_pool_branch_%';

-- Clean up temp tables
DROP TABLE IF EXISTS conn_pool_temp_1 CASCADE;
DROP TABLE IF EXISTS conn_pool_temp_2 CASCADE;
DROP TABLE IF EXISTS conn_pool_temp_3 CASCADE;
DROP TABLE IF EXISTS conn_pool_temp_4 CASCADE;
DROP TABLE IF EXISTS conn_pool_temp_5 CASCADE;

-- Clean up main test table
DROP TABLE IF EXISTS conn_pool_test CASCADE;

-- Clean up tracking
DELETE FROM pggit.objects WHERE object_name LIKE 'conn_pool%';

SELECT * FROM finish();

ROLLBACK;
