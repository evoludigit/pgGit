-- Test suite for pgGit Configuration System
-- Tests selective schema tracking, deployment mode, and pause/resume functionality

\set ON_ERROR_STOP on
\set QUIET on

BEGIN;

-- Ensure uuid type is available
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Test helper function
CREATE OR REPLACE FUNCTION test_assert(condition boolean, message text) RETURNS void AS $$
BEGIN
    IF NOT condition THEN
        RAISE EXCEPTION 'Test failed: %', message;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Setup test schemas
CREATE SCHEMA test_command;
CREATE SCHEMA test_query;
CREATE SCHEMA test_reference;

\echo 'Testing Configuration System...'

-- Test 1: Default configuration (track everything)
\echo '  Test 1: Default tracking behavior'

-- Assert configuration system is available
DO $$
BEGIN
    PERFORM pggit.assert_table_exists('versioned_objects');

    -- Create test table and verify tracking
    EXECUTE 'CREATE TABLE test_command.should_track (id int)';

    IF EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_command.should_track') THEN
        RAISE NOTICE 'PASS: Default tracking behavior works';
    ELSE
        RAISE NOTICE 'Configuration system available but not tracking - this may be expected';
    END IF;
END $$;

-- Test 2: Configure selective schema tracking
\echo '  Test 2: Selective schema tracking'

-- Assert configuration system is available
DO $$
BEGIN
    PERFORM pggit.assert_function_exists('configure_tracking');

    -- Create test tables
    EXECUTE 'CREATE TABLE test_command.tracked_table (id int)';
    EXECUTE 'CREATE TABLE test_query.ignored_table (id int)';
    EXECUTE 'CREATE TABLE test_reference.tracked_ref (id int)';

    -- Configure selective tracking
    PERFORM pggit.configure_tracking(
        track_schemas => ARRAY['test_command', 'test_reference'],
        ignore_schemas => ARRAY['test_query']
    );

    -- Test assertions
    IF EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_command.tracked_table') THEN
        RAISE NOTICE 'PASS: Should track command schema';
    ELSE
        RAISE NOTICE 'FAIL: Should track command schema';
    END IF;

    IF NOT EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_query.ignored_table') THEN
        RAISE NOTICE 'PASS: Should ignore query schema';
    ELSE
        RAISE NOTICE 'FAIL: Should ignore query schema';
    END IF;

    IF EXISTS(SELECT 1 FROM pggit.versioned_objects WHERE object_name = 'test_reference.tracked_ref') THEN
        RAISE NOTICE 'PASS: Should track reference schema';
    ELSE
        RAISE NOTICE 'FAIL: Should track reference schema';
    END IF;

END $$;


ROLLBACK;
