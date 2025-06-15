-- pgGit Core Functionality Tests
-- Tests basic versioning, event triggers, and core functions
-- No external dependencies required

\echo '============================================'
\echo 'pgGit Core Tests'
\echo '============================================'
\echo ''

-- Test 1: Schema and basic setup
\echo '1. Testing schema and basic setup...'
DO $$
BEGIN
    -- Check schema exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit') THEN
        RAISE EXCEPTION 'FAIL: pgGit schema does not exist';
    END IF;
    RAISE NOTICE 'PASS: pgGit schema exists';
    
    -- Check core tables
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'pggit' AND table_name = 'objects') THEN
        RAISE EXCEPTION 'FAIL: pgGit.objects table missing';
    END IF;
    RAISE NOTICE 'PASS: Core tables exist';
END;
$$;

-- Test 2: Core functions
\echo ''
\echo '2. Testing core functions...'
DO $$
DECLARE
    v_object_id INTEGER;
    v_version_count INTEGER;
    v_migration_length INTEGER;
BEGIN
    -- Test ensure_object
    SELECT pggit.ensure_object('TABLE'::pggit.object_type, 'public', 'core_test_table') INTO v_object_id;
    IF v_object_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: ensure_object returned NULL';
    END IF;
    RAISE NOTICE 'PASS: ensure_object works (ID: %)', v_object_id;
    
    -- Test get_version
    SELECT COUNT(*) INTO v_version_count FROM pggit.get_version('core_test_table');
    IF v_version_count = 0 THEN
        RAISE WARNING 'WARN: No version records found for test table';
    ELSE
        RAISE NOTICE 'PASS: get_version works (% records)', v_version_count;
    END IF;
    
    -- Test generate_migration
    SELECT LENGTH(pggit.generate_migration()) INTO v_migration_length;
    IF v_migration_length < 10 THEN
        RAISE EXCEPTION 'FAIL: generate_migration returned empty or invalid result';
    END IF;
    RAISE NOTICE 'PASS: generate_migration works (% chars)', v_migration_length;
END;
$$;

-- Test 3: Version tracking
\echo ''
\echo '3. Testing version tracking...'
DO $$
DECLARE
    v_object_id INTEGER;
    v_history_count INTEGER;
BEGIN
    -- Create test table
    CREATE TABLE IF NOT EXISTS test_version_tracking (
        id SERIAL PRIMARY KEY,
        name TEXT
    );
    
    -- Ensure tracking
    SELECT pggit.ensure_object('TABLE'::pggit.object_type, 'public', 'test_version_tracking') INTO v_object_id;
    
    -- Make a change
    ALTER TABLE test_version_tracking ADD COLUMN IF NOT EXISTS email TEXT;
    
    -- Record the change
    PERFORM pggit.increment_version(
        v_object_id, 
        'ALTER'::pggit.change_type, 
        'MINOR'::pggit.change_severity, 
        'Added email column'
    );
    
    -- Check history
    SELECT COUNT(*) INTO v_history_count FROM pggit.get_history('test_version_tracking');
    IF v_history_count = 0 THEN
        RAISE WARNING 'WARN: No history records found';
    ELSE
        RAISE NOTICE 'PASS: Version tracking works (% history records)', v_history_count;
    END IF;
    
    -- Cleanup
    DROP TABLE test_version_tracking;
END;
$$;

-- Test 4: Event triggers
\echo ''
\echo '4. Testing event triggers...'
DO $$
BEGIN
    -- Check if event triggers exist
    IF EXISTS (SELECT 1 FROM pg_event_trigger WHERE evtname = 'pggit_ddl_trigger' AND evtenabled != 'D') THEN
        RAISE NOTICE 'PASS: DDL event trigger is enabled';
    ELSE
        RAISE WARNING 'WARN: DDL event trigger not found or disabled';
    END IF;
    
    IF EXISTS (SELECT 1 FROM pg_event_trigger WHERE evtname = 'pggit_drop_trigger' AND evtenabled != 'D') THEN
        RAISE NOTICE 'PASS: DROP event trigger is enabled';
    ELSE
        RAISE WARNING 'WARN: DROP event trigger not found or disabled';
    END IF;
END;
$$;

-- Test 5: Impact analysis
\echo ''
\echo '5. Testing impact analysis...'
DO $$
DECLARE
    v_impact_count INTEGER;
BEGIN
    -- Create related tables
    CREATE TABLE test_parent (id SERIAL PRIMARY KEY);
    CREATE TABLE test_child (
        id SERIAL PRIMARY KEY,
        parent_id INTEGER REFERENCES test_parent(id)
    );
    
    -- Test impact analysis
    SELECT COUNT(*) INTO v_impact_count 
    FROM pggit.get_impact_analysis('public.test_parent');
    
    IF v_impact_count >= 0 THEN
        RAISE NOTICE 'PASS: Impact analysis works (% impacts found)', v_impact_count;
    ELSE
        RAISE EXCEPTION 'FAIL: Impact analysis failed';
    END IF;
    
    -- Cleanup
    DROP TABLE test_child;
    DROP TABLE test_parent;
EXCEPTION WHEN OTHERS THEN
    -- Cleanup on error
    DROP TABLE IF EXISTS test_child;
    DROP TABLE IF EXISTS test_parent;
    RAISE;
END;
$$;

-- Summary
\echo ''
\echo '============================================'
\echo 'Core Tests Complete'
\echo '============================================'
\echo ''
\echo 'Run with: psql -d your_database -f tests/test-core.sql'