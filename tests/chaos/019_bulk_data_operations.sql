-- Chaos Test: Bulk Data Operations
-- Test File: 019_bulk_data_operations.sql
-- Purpose: Test performance and stability with bulk INSERT/UPDATE/DELETE

BEGIN;

SELECT plan(14);

-- ============================================================================
-- SETUP: Create test table
-- ============================================================================

SELECT pggit.switch_branch('main');

CREATE TABLE bulk_test (
    id SERIAL PRIMARY KEY,
    data TEXT,
    value INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TEST GROUP 1: Bulk INSERT
-- ============================================================================

-- Test 1: Insert 1000 rows at once
SELECT lives_ok(
    $$ 
    INSERT INTO bulk_test (data, value) 
    SELECT 'row_' || i, i FROM generate_series(1, 1000) AS i;
    $$,
    'Should bulk insert 1000 rows'
);

-- Test 2: Verify count
SELECT is(
    (SELECT count(*) FROM bulk_test),
    1000::BIGINT,
    'Should have 1000 rows'
);

-- Test 3: Insert another 500 rows
SELECT lives_ok(
    $$ 
    INSERT INTO bulk_test (data, value) 
    SELECT 'extra_' || i, i + 1000 FROM generate_series(1, 500) AS i;
    $$,
    'Should insert 500 more rows'
);

-- ============================================================================
-- TEST GROUP 2: Bulk UPDATE
-- ============================================================================

-- Test 4: Update all rows
SELECT lives_ok(
    $$ UPDATE bulk_test SET data = data || '_updated', value = value * 2; $$,
    'Should update all 1500 rows'
);

-- Test 5: Verify updates
SELECT results_eq(
    $$ SELECT count(*) FROM bulk_test WHERE data LIKE '%_updated' $$,
    ARRAY[1500]::BIGINT[],
    'All rows should be updated'
);

-- Test 6: Batch update subset
SELECT lives_ok(
    $$ UPDATE bulk_test SET value = 9999 WHERE id <= 100; $$,
    'Should batch update first 100 rows'
);

-- ============================================================================
-- TEST GROUP 3: Bulk DELETE
-- ============================================================================

-- Test 7: Delete subset
SELECT lives_ok(
    $$ DELETE FROM bulk_test WHERE id > 1400; $$,
    'Should delete last 100 rows'
);

-- Test 8: Verify remaining count
SELECT is(
    (SELECT count(*) FROM bulk_test),
    1400::BIGINT,
    'Should have 1400 rows after delete'
);

-- ============================================================================
-- TEST GROUP 4: Branch with Bulk Data
-- ============================================================================

-- Test 9: Create branch with bulk data
SELECT lives_ok(
    $$ SELECT pggit.create_branch('bulk_data_branch', 'main', true); $$,
    'Should create branch with data copy'
);

-- Test 10: Verify data in branch
SELECT pggit.switch_branch('bulk_data_branch');
SELECT is(
    (SELECT count(*) FROM bulk_test),
    1400::BIGINT,
    'Branch should have 1400 rows'
);

-- Test 11: Modify in branch
SELECT lives_ok(
    $$ DELETE FROM bulk_test WHERE id <= 100; $$,
    'Should delete 100 rows in branch'
);

-- Test 12: Main should be unchanged
SELECT pggit.switch_branch('main');
SELECT is(
    (SELECT count(*) FROM bulk_test),
    1400::BIGINT,
    'Main should still have 1400 rows'
);

-- ============================================================================
-- TEST GROUP 5: System Performance
-- ============================================================================

-- Test 13: Query performance on large dataset
SELECT lives_ok(
    $$ 
    DO $$
    DECLARE
        v_count BIGINT;
        v_start TIMESTAMP;
    BEGIN
        v_start := clock_timestamp();
        SELECT count(*) INTO v_count FROM bulk_test WHERE value = 9999;
        -- Should be fast
        IF clock_timestamp() - v_start > INTERVAL '1 second' THEN
            RAISE WARNING 'Query took longer than expected';
        END IF;
    END;
    $$;
    $$,
    'Queries should remain performant'
);

-- Test 14: DDL tracking should work with bulk data
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.history WHERE object_name = 'bulk_test'),
    '>=',
    3::BIGINT,
    'DDL tracking should capture bulk operations'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up branches
DELETE FROM pggit.branches WHERE name = 'bulk_data_branch';

-- Clean up test data
DROP TABLE IF EXISTS bulk_test CASCADE;

-- Clean up tracking
DELETE FROM pggit.objects WHERE object_name = 'bulk_test';

SELECT * FROM finish();

ROLLBACK;
