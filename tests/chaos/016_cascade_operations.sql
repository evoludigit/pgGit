-- Chaos Test: CASCADE Operations
-- Test File: 016_cascade_operations.sql
-- Purpose: Test DROP CASCADE and dependencies

BEGIN;

SELECT plan(14);

-- ============================================================================
-- SETUP: Create interdependent objects
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Create parent table
CREATE TABLE cascade_parent (
    id SERIAL PRIMARY KEY,
    name TEXT
);

-- Create child table with FK
CREATE TABLE cascade_child (
    id SERIAL PRIMARY KEY,
    parent_id INTEGER REFERENCES cascade_parent(id) ON DELETE CASCADE,
    data TEXT
);

-- Create grandchild table
CREATE TABLE cascade_grandchild (
    id SERIAL PRIMARY KEY,
    child_id INTEGER REFERENCES cascade_child(id) ON DELETE CASCADE,
    info TEXT
);

-- Create views
CREATE VIEW cascade_view AS SELECT * FROM cascade_parent;

-- Create function
CREATE FUNCTION cascade_func() RETURNS INTEGER AS $$ BEGIN RETURN 1; END; $$ LANGUAGE plpgsql;

-- Insert data
INSERT INTO cascade_parent (name) VALUES ('parent1'), ('parent2');
INSERT INTO cascade_child (parent_id, data) 
SELECT id, 'child_of_' || name FROM cascade_parent;
INSERT INTO cascade_grandchild (child_id, info)
SELECT id, 'grandchild' FROM cascade_child;

-- ============================================================================
-- TEST GROUP 1: Verify Objects Created
-- ============================================================================

-- Test 1: Verify parent tracked
SELECT results_eq(
    $$ SELECT count(*) FROM pggit.objects WHERE object_name = 'cascade_parent' $$,
    ARRAY[1]::BIGINT[],
    'Parent table should be tracked'
);

-- Test 2: Verify child tracked
SELECT results_eq(
    $$ SELECT count(*) FROM pggit.objects WHERE object_name = 'cascade_child' $$,
    ARRAY[1]::BIGINT[],
    'Child table should be tracked'
);

-- Test 3: Verify view tracked
SELECT results_eq(
    $$ SELECT count(*) FROM pggit.objects WHERE object_name = 'cascade_view' $$,
    ARRAY[1]::BIGINT[],
    'View should be tracked'
);

-- ============================================================================
-- TEST GROUP 2: CASCADE Delete
-- ============================================================================

-- Test 4: Delete parent should cascade
SELECT lives_ok(
    $$ DELETE FROM cascade_parent WHERE id = 1; $$,
    'Should delete parent with CASCADE'
);

-- Test 5: Verify cascade worked
SELECT results_eq(
    $$ SELECT count(*) FROM cascade_child WHERE parent_id = 1 $$,
    ARRAY[0]::BIGINT[],
    'Child records should be cascade deleted'
);

-- Test 6: Verify grandchild also deleted
SELECT results_eq(
    $$ 
    SELECT count(*) FROM cascade_grandchild g
    JOIN cascade_child c ON g.child_id = c.id
    WHERE c.parent_id = 1
    $$,
    ARRAY[0]::BIGINT[],
    'Grandchild should also be deleted'
);

-- ============================================================================
-- TEST GROUP 3: DROP CASCADE
-- ============================================================================

-- Test 7: Drop parent with CASCADE
SELECT lives_ok(
    $$ DROP TABLE cascade_parent CASCADE; $$,
    'Should DROP CASCADE parent table'
);

-- Test 8: Verify child dropped
SELECT throws_ok(
    $$ SELECT count(*) FROM cascade_child $$,
    '42P01',
    'relation "cascade_child" does not exist',
    'Child table should be cascade dropped'
);

-- Test 9: Verify grandchild dropped
SELECT throws_ok(
    $$ SELECT count(*) FROM cascade_grandchild $$,
    '42P01',
    'relation "cascade_grandchild" does not exist',
    'Grandchild table should be cascade dropped'
);

-- Test 10: Verify view dropped
SELECT throws_ok(
    $$ SELECT count(*) FROM cascade_view $$,
    '42P01',
    'relation "cascade_view" does not exist',
    'View should be cascade dropped'
);

-- ============================================================================
-- TEST GROUP 4: DDL Tracking of CASCADE
-- ============================================================================

-- Test 11: DDL tracking should capture drops
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.history 
     WHERE object_name LIKE 'cascade_%' AND change_type = 'DROP'),
    '>=',
    1::BIGINT,
    'DDL tracking should capture DROP CASCADE'
);

-- Test 12: Objects should be marked inactive
SELECT results_eq(
    $$ SELECT is_active FROM pggit.objects WHERE object_name = 'cascade_parent' $$,
    ARRAY[false]::BOOLEAN[],
    'Parent should be marked inactive'
);

-- ============================================================================
-- TEST GROUP 5: System Stability
-- ============================================================================

-- Test 13: Health check after CASCADE
SELECT results_eq(
    $$ SELECT status FROM pggit.health_check() WHERE check_name = 'tracked_objects' $$,
    ARRAY['healthy']::TEXT[],
    'Health check should pass after CASCADE'
);

-- Test 14: Can still perform DDL after CASCADE
SELECT lives_ok(
    $$ CREATE TABLE post_cascade_test (id INT); $$,
    'Should create table after CASCADE operations'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up function
DROP FUNCTION IF EXISTS cascade_func();

-- Clean up test table
DROP TABLE IF EXISTS post_cascade_test CASCADE;

-- Clean up tracking
DELETE FROM pggit.objects WHERE object_name LIKE 'cascade_%';
DELETE FROM pggit.objects WHERE object_name = 'post_cascade_test';
DELETE FROM pggit.history WHERE object_name LIKE 'cascade_%';

SELECT * FROM finish();

ROLLBACK;
