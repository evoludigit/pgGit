-- Chaos Test: Memory Pressure with Large Objects
-- Test File: 008_memory_pressure.sql
-- Purpose: Test behavior under memory-intensive operations

BEGIN;

SELECT plan(14);

-- ============================================================================
-- SETUP: Create test environment
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create table for large objects
CREATE TABLE memory_test_objects (
    id SERIAL PRIMARY KEY,
    name TEXT,
    large_text TEXT,
    large_json JSONB,
    binary_data BYTEA
);

-- ============================================================================
-- TEST GROUP 1: Large Text Handling
-- ============================================================================

-- Test 1: Insert moderately large text (100KB)
SELECT lives_ok(
    $$ 
    INSERT INTO memory_test_objects (name, large_text) 
    VALUES ('100kb_text', repeat('x', 100000));
    $$,
    'Should handle 100KB text insert'
);

-- Test 2: Insert large text (1MB)
SELECT lives_ok(
    $$ 
    INSERT INTO memory_test_objects (name, large_text) 
    VALUES ('1mb_text', repeat('y', 1000000));
    $$,
    'Should handle 1MB text insert'
);

-- Test 3: Query large text should work
SELECT lives_ok(
    $$ SELECT length(large_text) FROM memory_test_objects WHERE name = '1mb_text'; $$,
    'Should query large text'
);

-- Test 4: Verify text size
SELECT results_eq(
    $$ SELECT length(large_text) FROM memory_test_objects WHERE name = '1mb_text' $$,
    ARRAY[1000000]::INTEGER[],
    'Text size should be 1MB'
);

-- ============================================================================
-- TEST GROUP 2: Large JSONB Handling
-- ============================================================================

-- Test 5: Insert large JSONB structure
SELECT lives_ok(
    $$ 
    INSERT INTO memory_test_objects (name, large_json) 
    VALUES ('large_json', (
        SELECT jsonb_object_agg('key_' || i, repeat('v', 1000))
        FROM generate_series(1, 100) AS i
    ));
    $$,
    'Should handle large JSONB structure'
);

-- Test 6: Query JSONB should work
SELECT lives_ok(
    $$ SELECT jsonb_object_keys(large_json) FROM memory_test_objects WHERE name = 'large_json' LIMIT 5; $$,
    'Should query large JSONB'
);

-- ============================================================================
-- TEST GROUP 3: Multiple Large Objects
-- ============================================================================

-- Test 7: Insert multiple large objects
SELECT lives_ok(
    $$ 
    INSERT INTO memory_test_objects (name, large_text) 
    SELECT 'batch_' || i, repeat('z', 50000)
    FROM generate_series(1, 20) AS i;
    $$,
    'Should handle batch of large objects'
);

-- Test 8: Verify all inserts succeeded
SELECT is(
    (SELECT count(*) FROM memory_test_objects WHERE name LIKE 'batch_%'),
    20::BIGINT,
    'Should have 20 batch objects'
);

-- Test 9: DDL tracking should handle large data
SELECT lives_ok(
    $$ ALTER TABLE memory_test_objects ADD COLUMN extra TEXT; $$,
    'DDL should work with large data present'
);

-- ============================================================================
-- TEST GROUP 4: Memory-Intensive Operations
-- ============================================================================

-- Test 10: Aggregation on large data
SELECT lives_ok(
    $$ SELECT sum(length(large_text)) FROM memory_test_objects WHERE large_text IS NOT NULL; $$,
    'Aggregation should work on large data'
);

-- Test 11: Branch operations should work
SELECT lives_ok(
    $$ SELECT pggit.create_branch('memory_pressure_branch'); $$,
    'Should create branch with large data'
);

-- Test 12: Switch branch with large data
SELECT lives_ok(
    $$ SELECT pggit.switch_branch('memory_pressure_branch'); $$,
    'Should switch branch with large data'
);

-- Test 13: Make changes in branch
SELECT pggit.switch_branch('memory_pressure_branch');
SELECT lives_ok(
    $$ INSERT INTO memory_test_objects (name) VALUES ('branch_data'); $$,
    'Should insert in branch'
);

-- ============================================================================
-- TEST GROUP 5: Health Check
-- ============================================================================

-- Test 14: System should report healthy
SELECT pggit.switch_branch('main');
SELECT results_eq(
    $$ SELECT status FROM pggit.health_check() WHERE check_name = 'database_connection' $$,
    ARRAY['healthy']::TEXT[],
    'Health check should pass after memory pressure'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up branches
DELETE FROM pggit.branches WHERE name = 'memory_pressure_branch';

-- Clean up test data
DROP TABLE IF EXISTS memory_test_objects CASCADE;

-- Clean up tracking
DELETE FROM pggit.objects WHERE object_name = 'memory_test_objects';

SELECT * FROM finish();

ROLLBACK;
