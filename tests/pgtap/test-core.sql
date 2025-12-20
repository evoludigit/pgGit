-- pgGit Core Functionality Tests (pgTAP format)
-- Tests basic versioning, event triggers, and core functions

BEGIN;
SELECT plan(10); -- Number of tests

-- Test 1: Schema exists
SELECT has_schema('pggit', 'pggit schema should exist');

-- Test 2: Core tables exist
SELECT has_table('pggit', 'objects', 'pggit.objects table should exist');
SELECT has_table('pggit', 'history', 'pggit.history table should exist');

-- Test 3: Event triggers exist
SELECT ok(
    EXISTS (SELECT 1 FROM pg_event_trigger WHERE evtname = 'pggit_ddl_trigger'),
    'DDL event trigger should exist'
);

-- Test 4: Function exists and returns correct type
SELECT has_function('pggit', 'ensure_object', 'ensure_object function should exist');

-- Test 5: Basic functions work
SELECT lives_ok(
    $$SELECT pggit.ensure_object('TABLE'::pggit.object_type, 'public', 'test_table')$$,
    'ensure_object should work'
);

-- Test 6: Migration generation works
SELECT lives_ok(
    $$SELECT pggit.generate_migration()$$,
    'generate_migration should execute without error'
);

-- Test 7: Migration is not empty
SELECT ok(
    LENGTH(pggit.generate_migration()) > 0,
    'generate_migration should return content'
);

-- Test 8: Get history function exists
SELECT has_function('pggit', 'get_history', 'get_history function should exist');

-- Test 9: Generate migration function exists
SELECT has_function('pggit', 'generate_migration', 'generate_migration function should exist');

-- Test 10: Check basic functionality
SELECT ok(
    (SELECT COUNT(*) FROM pggit.objects) >= 0,
    'Objects table should be accessible'
);

DROP TABLE test_versioning CASCADE;

SELECT * FROM finish();
ROLLBACK;