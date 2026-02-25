-- Unit Test Suite for pgGit DDL Tracking
-- Test File: 004_test_ddl_tracking.sql
-- Coverage: Event triggers, DDL capture, history recording

BEGIN;

-- Plan: 30 tests for DDL tracking functionality
SELECT plan(30);

-- ============================================================================
-- SETUP: Create test schema and tables
-- ============================================================================

-- Create a test schema for DDL operations
CREATE SCHEMA IF NOT EXISTS ddl_test_schema;

-- Ensure pggit extension is tracking
SELECT pggit.switch_branch('main');

-- ============================================================================
-- TEST GROUP 1: DDL Event Trigger Activation (Tests 1-6)
-- ============================================================================

-- Test 1: Event trigger should exist
SELECT has_trigger(
    'pggit',
    'objects',
    'ddl_command_end',
    'DDL event trigger should exist'
);

-- Test 2: DDL capture function should exist
SELECT has_function(
    'pggit',
    'handle_ddl_command',
    ARRAY[]::TEXT[],
    'DDL handling function should exist'
);

-- Test 3: Create table should be tracked
SELECT lives_ok(
    $$ CREATE TABLE ddl_test_schema.test_table_1 (id INT PRIMARY KEY, name TEXT) $$,
    'Creating table in test schema should work'
);

-- Test 4: Created table should appear in objects
SELECT results_eq(
    $$ SELECT count(*) FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'test_table_1' $$,
    ARRAY[1]::BIGINT[],
    'Created table should be tracked in pggit.objects'
);

-- Test 5: DDL history should record the CREATE
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.history WHERE object_id IN (SELECT id FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'test_table_1') AND change_type = 'CREATE'),
    '>=',
    1::BIGINT,
    'DDL history should record table creation'
);

-- Test 6: Object should have correct type
SELECT results_eq(
    $$ SELECT object_type FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'test_table_1' $$,
    ARRAY['TABLE']::pggit.object_type[],
    'Tracked object should have correct type'
);

-- ============================================================================
-- TEST GROUP 2: DDL Alter Operations (Tests 7-12)
-- ============================================================================

-- Test 7: Alter table should be tracked
SELECT lives_ok(
    $$ ALTER TABLE ddl_test_schema.test_table_1 ADD COLUMN email TEXT $$,
    'Altering table should work'
);

-- Test 8: Alter operation should be recorded in history
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.history WHERE object_id IN (SELECT id FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'test_table_1') AND change_type = 'ALTER'),
    '>=',
    1::BIGINT,
    'Alter operation should be recorded'
);

-- Test 9: Multiple alters should create multiple history entries
SELECT lives_ok(
    $$ ALTER TABLE ddl_test_schema.test_table_1 ADD COLUMN phone TEXT $$,
    'Second alter should work'
);

SELECT cmp_ok(
    (SELECT count(*) FROM pggit.history WHERE object_id IN (SELECT id FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'test_table_1') AND change_type = 'ALTER'),
    '>=',
    2::BIGINT,
    'Multiple alters should create multiple entries'
);

-- Test 10: Alter column should be tracked
SELECT lives_ok(
    $$ ALTER TABLE ddl_test_schema.test_table_1 ALTER COLUMN name SET NOT NULL $$,
    'Altering column should work'
);

-- Test 11: Create index should be tracked
SELECT lives_ok(
    $$ CREATE INDEX idx_test_name ON ddl_test_schema.test_table_1(name) $$,
    'Creating index should work'
);

SELECT cmp_ok(
    (SELECT count(*) FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'idx_test_name'),
    '>=',
    1::BIGINT,
    'Created index should be tracked'
);

-- Test 12: Index should have correct type
SELECT results_eq(
    $$ SELECT object_type FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'idx_test_name' $$,
    ARRAY['INDEX']::pggit.object_type[],
    'Index should have INDEX type'
);

-- ============================================================================
-- TEST GROUP 3: DDL Drop Operations (Tests 13-17)
-- ============================================================================

-- Test 13: Drop index should be tracked
SELECT lives_ok(
    $$ DROP INDEX ddl_test_schema.idx_test_name $$,
    'Dropping index should work'
);

-- Test 14: Dropped object should be marked inactive
SELECT results_eq(
    $$ SELECT is_active FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'idx_test_name' $$,
    ARRAY[false]::BOOLEAN[],
    'Dropped index should be marked inactive'
);

-- Test 15: Drop should be recorded in history
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.history WHERE object_id IN (SELECT id FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'idx_test_name') AND change_type = 'DROP'),
    '>=',
    1::BIGINT,
    'Drop operation should be recorded'
);

-- Test 16: Drop table should work
SELECT lives_ok(
    $$ DROP TABLE ddl_test_schema.test_table_1 $$,
    'Dropping table should work'
);

-- Test 17: Dropped table should be marked inactive
SELECT results_eq(
    $$ SELECT is_active FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'test_table_1' $$,
    ARRAY[false]::BOOLEAN[],
    'Dropped table should be marked inactive'
);

-- ============================================================================
-- TEST GROUP 4: View and Function Tracking (Tests 18-23)
-- ============================================================================

-- Test 18: Create view should be tracked
SELECT lives_ok(
    $$ CREATE VIEW ddl_test_schema.test_view AS SELECT 1 as col $$,
    'Creating view should work'
);

SELECT results_eq(
    $$ SELECT object_type FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'test_view' $$,
    ARRAY['VIEW']::pggit.object_type[],
    'View should be tracked with correct type'
);

-- Test 19: Create function should be tracked
SELECT lives_ok(
    $$ CREATE FUNCTION ddl_test_schema.test_func() RETURNS INT AS $$ BEGIN RETURN 1; END; $$ LANGUAGE plpgsql $$,
    'Creating function should work'
);

SELECT cmp_ok(
    (SELECT count(*) FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'test_func'),
    '>=',
    1::BIGINT,
    'Function should be tracked'
);

-- Test 20: Replace function should be tracked as alter
SELECT lives_ok(
    $$ CREATE OR REPLACE FUNCTION ddl_test_schema.test_func() RETURNS INT AS $$ BEGIN RETURN 2; END; $$ LANGUAGE plpgsql $$,
    'Replacing function should work'
);

-- Test 21: Create trigger should be tracked
SELECT lives_ok(
    $$ 
    CREATE TABLE ddl_test_schema.trigger_test (id INT);
    CREATE FUNCTION ddl_test_schema.trigger_func() RETURNS trigger AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;
    CREATE TRIGGER test_trigger BEFORE INSERT ON ddl_test_schema.trigger_test 
    FOR EACH ROW EXECUTE FUNCTION ddl_test_schema.trigger_func();
    $$,
    'Creating trigger should work'
);

SELECT cmp_ok(
    (SELECT count(*) FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'test_trigger'),
    '>=',
    1::BIGINT,
    'Trigger should be tracked'
);

-- Test 22: Create sequence should be tracked
SELECT lives_ok(
    $$ CREATE SEQUENCE ddl_test_schema.test_seq START 1 $$,
    'Creating sequence should work'
);

SELECT results_eq(
    $$ SELECT object_type FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'test_seq' $$,
    ARRAY['SEQUENCE']::pggit.object_type[],
    'Sequence should be tracked with correct type'
);

-- Test 23: Create type should be tracked
SELECT lives_ok(
    $$ CREATE TYPE ddl_test_schema.test_type AS (x INT, y INT) $$,
    'Creating type should work'
);

SELECT results_eq(
    $$ SELECT object_type FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'test_type' $$,
    ARRAY['TYPE']::pggit.object_type[],
    'Type should be tracked with correct type'
);

-- ============================================================================
-- TEST GROUP 5: DDL in Different Branches (Tests 24-27)
-- ============================================================================

-- Test 24: DDL in branch should be isolated
SELECT pggit.create_branch('ddl_test_branch');
SELECT pggit.switch_branch('ddl_test_branch');

CREATE TABLE ddl_test_schema.branch_table (id INT);

SELECT results_eq(
    $$ SELECT count(*) FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'branch_table' AND branch_name = 'ddl_test_branch' $$,
    ARRAY[1]::BIGINT[],
    'DDL in branch should track for that branch'
);

-- Test 25: DDL should not appear in other branches
SELECT pggit.switch_branch('main');
SELECT results_eq(
    $$ SELECT count(*) FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND object_name = 'branch_table' AND branch_name = 'main' $$,
    ARRAY[0]::BIGINT[],
    'DDL should not appear in other branches'
);

-- Test 26: Switch branch and verify
SELECT pggit.switch_branch('ddl_test_branch');
SELECT has_table(
    'ddl_test_schema',
    'branch_table',
    'Table should exist when in correct branch'
);

-- Test 27: Verify table not in main
SELECT pggit.switch_branch('main');
SELECT hasnt_table(
    'ddl_test_schema',
    'branch_table',
    'Table should not exist in main branch'
);

-- ============================================================================
-- TEST GROUP 6: Temporary Objects and Edge Cases (Tests 28-30)
-- ============================================================================

-- Test 28: Temporary tables should not be tracked
SELECT lives_ok(
    $$ CREATE TEMP TABLE temp_test_table (id INT) $$,
    'Creating temp table should work'
);

SELECT results_eq(
    $$ SELECT count(*) FROM pggit.objects WHERE object_name = 'temp_test_table' $$,
    ARRAY[0]::BIGINT[],
    'Temporary tables should not be tracked'
);

-- Test 29: System objects should not be tracked
SELECT results_eq(
    $$ SELECT count(*) FROM pggit.objects WHERE schema_name LIKE 'pg_%' OR schema_name = 'information_schema' $$,
    ARRAY[0]::BIGINT[],
    'System objects should not be tracked'
);

-- Test 30: Content hash should be generated
SELECT cmp_ok(
    (SELECT count(*) FROM pggit.objects WHERE schema_name = 'ddl_test_schema' AND content_hash IS NOT NULL AND length(content_hash) > 0),
    '>',
    0::BIGINT,
    'Content hashes should be generated for tracked objects'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT pggit.switch_branch('main');

-- Clean up test branches
DELETE FROM pggit.branches WHERE name = 'ddl_test_branch';

-- Drop test schema and all objects
DROP SCHEMA IF EXISTS ddl_test_schema CASCADE;

SELECT * FROM finish();

ROLLBACK;
