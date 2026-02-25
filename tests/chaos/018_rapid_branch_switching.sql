-- Chaos Test: Rapid Branch Switching
-- Test File: 018_rapid_branch_switching.sql
-- Purpose: Test rapid branch switches and context changes

BEGIN;

SELECT plan(14);

-- ============================================================================
-- SETUP: Create multiple branches
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create test branches
SELECT pggit.create_branch('rapid_1');
SELECT pggit.create_branch('rapid_2');
SELECT pggit.create_branch('rapid_3');
SELECT pggit.create_branch('rapid_4');
SELECT pggit.create_branch('rapid_5');

-- Create test table
CREATE TABLE rapid_switch_test (
    id SERIAL PRIMARY KEY,
    branch_marker TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TEST GROUP 1: Rapid Switching
-- ============================================================================

-- Test 1: Rapid switch sequence 1
SELECT lives_ok(
    $$ 
    SELECT pggit.switch_branch('rapid_1');
    SELECT pggit.switch_branch('rapid_2');
    SELECT pggit.switch_branch('rapid_3');
    $$,
    'Should rapid switch through 3 branches'
);

-- Test 2: Insert data in current branch
SELECT pggit.switch_branch('rapid_3');
INSERT INTO rapid_switch_test (branch_marker) VALUES ('in_rapid_3');

-- Test 3: Rapid switch to another branch and insert
SELECT lives_ok(
    $$ 
    SELECT pggit.switch_branch('rapid_1');
    INSERT INTO rapid_switch_test (branch_marker) VALUES ('in_rapid_1');
    $$,
    'Should switch and insert in rapid_1'
);

-- Test 4: Verify data isolation
SELECT results_eq(
    $$ SELECT count(*) FROM rapid_switch_test WHERE branch_marker = 'in_rapid_1' $$,
    ARRAY[1]::BIGINT[],
    'Should see rapid_1 data'
);

-- Test 5: Switch again and verify different data
SELECT lives_ok(
    $$ SELECT pggit.switch_branch('rapid_3'); $$,
    'Should switch to rapid_3'
);

SELECT results_eq(
    $$ SELECT count(*) FROM rapid_switch_test WHERE branch_marker = 'in_rapid_3' $$,
    ARRAY[1]::BIGINT[],
    'Should see rapid_3 data'
);

-- ============================================================================
-- TEST GROUP 2: Many Rapid Switches
-- ============================================================================

-- Test 6: Many switches in sequence
SELECT lives_ok(
    $$ 
    DO $$
    BEGIN
        PERFORM pggit.switch_branch('rapid_2');
        PERFORM pg_sleep(0.01);
        PERFORM pggit.switch_branch('rapid_4');
        PERFORM pg_sleep(0.01);
        PERFORM pggit.switch_branch('rapid_5');
        PERFORM pg_sleep(0.01);
        PERFORM pggit.switch_branch('main');
    END;
    $$;
    $$,
    'Should handle many rapid switches'
);

-- Test 7: Verify final state is main
SELECT results_eq(
    $$ SELECT pggit.get_current_branch() $$,
    ARRAY['main']::TEXT[],
    'Should be on main after switches'
);

-- Test 8: Main should not see branch data
SELECT results_eq(
    $$ SELECT count(*) FROM rapid_switch_test $$,
    ARRAY[0]::BIGINT[],
    'Main should not see branch data'
);

-- ============================================================================
-- TEST GROUP 3: DDL During Rapid Switching
-- ============================================================================

-- Test 9: Create tables in different branches rapidly
SELECT lives_ok(
    $$ 
    SELECT pggit.switch_branch('rapid_2');
    CREATE TABLE rapid_2_table (id INT);
    
    SELECT pggit.switch_branch('rapid_4');
    CREATE TABLE rapid_4_table (id INT);
    $$,
    'Should create tables in different branches'
);

-- Test 10: Verify DDL tracking
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.objects WHERE object_name IN ('rapid_2_table', 'rapid_4_table')),
    '>=',
    2::BIGINT,
    'Should track tables in different branches'
);

-- Test 11: Switch back and verify isolation
SELECT lives_ok(
    $$ 
    SELECT pggit.switch_branch('rapid_2');
    PERFORM count(*) FROM rapid_2_table;
    $$,
    'Should access table in rapid_2'
);

-- ============================================================================
-- TEST GROUP 4: System Stability
-- ============================================================================

-- Test 12: Health check after rapid switching
SELECT results_eq(
    $$ SELECT status FROM pggit.health_check() WHERE check_name = 'branches' $$,
    ARRAY['healthy']::TEXT[],
    'Health check should pass'
);

-- Test 13: DDL tracking should still work
SELECT lives_ok(
    $$ 
    SELECT pggit.switch_branch('main');
    ALTER TABLE rapid_switch_test ADD COLUMN new_col TEXT;
    $$,
    'DDL should work after rapid switching'
);

-- Test 14: Final state consistent
SELECT is(
    (SELECT count(*) FROM pggit.branches WHERE name LIKE 'rapid_%'),
    5::BIGINT,
    'Should have 5 rapid branches'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up branches
DELETE FROM pggit.branches WHERE name LIKE 'rapid_%';

-- Clean up tables
DROP TABLE IF EXISTS rapid_switch_test CASCADE;
DROP TABLE IF EXISTS rapid_2_table CASCADE;
DROP TABLE IF EXISTS rapid_4_table CASCADE;

-- Clean up tracking
DELETE FROM pggit.objects WHERE object_name LIKE 'rapid_%';

SELECT * FROM finish();

ROLLBACK;
