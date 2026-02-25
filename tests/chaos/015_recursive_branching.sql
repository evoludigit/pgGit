-- Chaos Test: Recursive Branching Deep Nesting
-- Test File: 015_recursive_branching.sql
-- Purpose: Test deep branch hierarchies (branch of branch of branch)

BEGIN;

SELECT plan(18);

-- ============================================================================
-- SETUP: Create base state
-- ============================================================================

SELECT pggit.switch_branch('main');

-- ============================================================================
-- TEST GROUP 1: Create Deep Branch Hierarchy
-- ============================================================================

-- Test 1: Create level 1 branch from main
SELECT lives_ok(
    $$ SELECT pggit.create_branch('level_1'); $$,
    'Should create level 1 branch'
);

-- Test 2: Create level 2 from level 1
SELECT lives_ok(
    $$ SELECT pggit.create_branch('level_2', 'level_1'); $$,
    'Should create level 2 branch'
);

-- Test 3: Create level 3 from level 2
SELECT lives_ok(
    $$ SELECT pggit.create_branch('level_3', 'level_2'); $$,
    'Should create level 3 branch'
);

-- Test 4: Create level 4 from level 3
SELECT lives_ok(
    $$ SELECT pggit.create_branch('level_4', 'level_3'); $$,
    'Should create level 4 branch'
);

-- Test 5: Create level 5 from level 4
SELECT lives_ok(
    $$ SELECT pggit.create_branch('level_5', 'level_4'); $$,
    'Should create level 5 branch'
);

-- Test 6: Verify all branches exist
SELECT is(
    (SELECT count(*) FROM pggit.branches WHERE name LIKE 'level_%'),
    5::BIGINT,
    'Should have 5 levels of branches'
);

-- ============================================================================
-- TEST GROUP 2: Verify Ancestry Chain
-- ============================================================================

-- Test 7: Check level 5 parent is level 4
SELECT results_eq(
    $$ 
    SELECT b5.parent_branch_id = b4.id 
    FROM pggit.branches b5, pggit.branches b4 
    WHERE b5.name = 'level_5' AND b4.name = 'level_4'
    $$,
    ARRAY[true]::BOOLEAN[],
    'Level 5 should have level 4 as parent'
);

-- Test 8: Check level 2 parent is level 1
SELECT results_eq(
    $$ 
    SELECT b2.parent_branch_id = b1.id 
    FROM pggit.branches b2, pggit.branches b1 
    WHERE b2.name = 'level_2' AND b1.name = 'level_1'
    $$,
    ARRAY[true]::BOOLEAN[],
    'Level 2 should have level 1 as parent'
);

-- ============================================================================
-- TEST GROUP 3: Data Isolation Across Hierarchy
-- ============================================================================

-- Test 9: Create table in level 1
SELECT pggit.switch_branch('level_1');
CREATE TABLE recursive_test_table (id INT);
INSERT INTO recursive_test_table VALUES (1);

-- Test 10: Verify data in level 1
SELECT results_eq(
    $$ SELECT count(*) FROM recursive_test_table $$,
    ARRAY[1]::BIGINT[],
    'Level 1 should have data'
);

-- Test 11: Check if data propagates to level 2
SELECT pggit.switch_branch('level_2');
SELECT results_eq(
    $$ SELECT count(*) FROM recursive_test_table $$,
    ARRAY[1]::BIGINT[],
    'Level 2 should inherit level 1 data'
);

-- Test 12: Add data in level 3
SELECT pggit.switch_branch('level_3');
INSERT INTO recursive_test_table VALUES (2);

-- Test 13: Verify level 3 has both rows
SELECT results_eq(
    $$ SELECT count(*) FROM recursive_test_table $$,
    ARRAY[2]::BIGINT[],
    'Level 3 should have 2 rows'
);

-- Test 14: Main should not see any data
SELECT pggit.switch_branch('main');
SELECT throws_ok(
    $$ SELECT count(*) FROM recursive_test_table $$,
    '42P01',  -- undefined_table
    'relation "recursive_test_table" does not exist',
    'Main should not see branch table'
);

-- ============================================================================
-- TEST GROUP 4: Merge from Deep Branch
-- ============================================================================

-- Test 15: Merge level 3 into main
SELECT lives_ok(
    $$ SELECT pggit.merge('level_3', 'main', 'auto'); $$,
    'Should merge deep branch'
);

-- Test 16: Verify merge completed
SELECT results_eq(
    $$ SELECT status FROM pggit.merge_history WHERE source_branch = 'level_3' ORDER BY initiated_at DESC LIMIT 1 $$,
    ARRAY['completed']::TEXT[],
    'Deep branch merge should complete'
);

-- Test 17: Main should now see data
SELECT results_eq(
    $$ SELECT count(*) FROM recursive_test_table $$,
    ARRAY[2]::BIGINT[],
    'Main should have merged data'
);

-- Test 18: System health after deep branching
SELECT results_eq(
    $$ SELECT status FROM pggit.health_check() WHERE check_name = 'branches' $$,
    ARRAY['healthy']::TEXT[],
    'Health check should pass after deep branching'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up branches (in reverse order to avoid FK issues)
DELETE FROM pggit.branches WHERE name = 'level_5';
DELETE FROM pggit.branches WHERE name = 'level_4';
DELETE FROM pggit.branches WHERE name = 'level_3';
DELETE FROM pggit.branches WHERE name = 'level_2';
DELETE FROM pggit.branches WHERE name = 'level_1';

-- Clean up test table
DROP TABLE IF EXISTS recursive_test_table CASCADE;

-- Clean up tracking
DELETE FROM pggit.objects WHERE object_name = 'recursive_test_table';

SELECT * FROM finish();

ROLLBACK;
