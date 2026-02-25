-- Chaos Test: Event Trigger Edge Cases
-- Test File: 014_event_trigger_edge_cases.sql
-- Purpose: Test event trigger behavior under edge conditions

BEGIN;

SELECT plan(16);

-- ============================================================================
-- SETUP: Create test environment
-- ============================================================================

SELECT pggit.switch_branch('main');

-- ============================================================================
-- TEST GROUP 1: Temp Table Handling
-- ============================================================================

-- Test 1: Temp tables should not be tracked
SELECT lives_ok(
    $$ CREATE TEMP TABLE temp_edge_test (id INT); $$,
    'Should create temp table'
);

-- Test 2: Verify temp table not tracked
SELECT results_eq(
    $$ SELECT count(*) FROM pggit.objects WHERE object_name = 'temp_edge_test' $$,
    ARRAY[0]::BIGINT[],
    'Temp table should not be tracked'
);

-- Test 3: Operations on temp table should work
SELECT lives_ok(
    $$ INSERT INTO temp_edge_test VALUES (1), (2), (3); $$,
    'Should insert into temp table'
);

-- Test 4: Drop temp table
SELECT lives_ok(
    $$ DROP TABLE IF EXISTS temp_edge_test; $$,
    'Should drop temp table'
);

-- ============================================================================
-- TEST GROUP 2: System Object Filtering
-- ============================================================================

-- Test 5: System objects should not be tracked
SELECT results_eq(
    $$ SELECT count(*) FROM pggit.objects 
       WHERE schema_name LIKE 'pg_%' OR schema_name = 'information_schema' $$,
    ARRAY[0]::BIGINT[],
    'System objects should not be tracked'
);

-- Test 6: pg_temp tables should be ignored
SELECT lives_ok(
    $$ 
    CREATE TEMP TABLE pg_temp_edge (id INT);
    DROP TABLE IF EXISTS pg_temp_edge;
    $$,
    'Should handle pg_temp tables'
);

-- ============================================================================
-- TEST GROUP 3: DDL on Untracked Objects
-- ============================================================================

-- Test 7: Create and modify regular table
SELECT lives_ok(
    $$ CREATE TABLE edge_case_regular (id INT PRIMARY KEY); $$,
    'Should create regular table'
);

-- Test 8: Verify tracking
SELECT results_eq(
    $$ SELECT count(*) FROM pggit.objects WHERE object_name = 'edge_case_regular' $$,
    ARRAY[1]::BIGINT[],
    'Regular table should be tracked'
);

-- Test 9: Add column
SELECT lives_ok(
    $$ ALTER TABLE edge_case_regular ADD COLUMN data TEXT; $$,
    'Should add column to tracked table'
);

-- Test 10: Modify column
SELECT lives_ok(
    $$ ALTER TABLE edge_case_regular ALTER COLUMN data SET DEFAULT 'default'; $$,
    'Should modify column'
);

-- ============================================================================
-- TEST GROUP 4: Trigger Function Errors
-- ============================================================================

-- Test 11: DDL should complete even if trigger has issues
SELECT lives_ok(
    $$ 
    CREATE TABLE edge_error_test (
        id INT PRIMARY KEY,
        check_col INTEGER CHECK (check_col > 0)
    );
    $$,
    'Should create table with constraints'
);

-- Test 12: Verify tracking despite complex DDL
SELECT results_eq(
    $$ SELECT count(*) FROM pggit.objects WHERE object_name = 'edge_error_test' $$,
    ARRAY[1]::BIGINT[],
    'Complex DDL should be tracked'
);

-- Test 13: Drop with CASCADE
SELECT lives_ok(
    $$ DROP TABLE IF EXISTS edge_error_test CASCADE; $$,
    'Should drop table with CASCADE'
);

-- ============================================================================
-- TEST GROUP 5: Event Trigger State
-- ============================================================================

-- Test 14: Verify event trigger exists
SELECT results_eq(
    $$ SELECT count(*) > 0 FROM pg_event_trigger WHERE evtname LIKE '%ddl%' $$,
    ARRAY[true]::BOOLEAN[],
    'DDL event trigger should exist'
);

-- Test 15: DDL tracking function should exist
SELECT has_function(
    'pggit',
    'handle_ddl_command',
    ARRAY[]::TEXT[],
    'DDL handler function should exist'
);

-- Test 16: System health should show tracking active
SELECT results_eq(
    $$ SELECT status FROM pggit.health_check() WHERE check_name = 'ddl_tracking' $$,
    ARRAY['healthy']::TEXT[],
    'DDL tracking should be healthy'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up test tables
DROP TABLE IF EXISTS edge_case_regular CASCADE;

-- Clean up any temp tables
DROP TABLE IF EXISTS temp_edge_test;

-- Clean up tracking
DELETE FROM pggit.objects WHERE object_name LIKE 'edge_%';

SELECT * FROM finish();

ROLLBACK;
