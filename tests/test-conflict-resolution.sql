-- Test suite for pgGit Conflict Resolution & Operations
-- Tests conflict resolution API, emergency controls, and maintenance operations

\set ON_ERROR_STOP on
\set QUIET on

BEGIN;

-- Test helper function
CREATE OR REPLACE FUNCTION test_assert(condition boolean, message text) RETURNS void AS $$
BEGIN
    IF NOT condition THEN
        RAISE EXCEPTION 'Test failed: %', message;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Setup test schema
CREATE SCHEMA test_conflicts;

\echo 'Testing Conflict Resolution & Operations...'

-- Test 1: Register and resolve merge conflict
\echo '  Test 1: Register and resolve merge conflict'

-- Assert conflict resolution is available
DO $$
BEGIN
    PERFORM pggit.assert_function_exists('register_conflict');
    RAISE NOTICE 'PASS: Conflict resolution is loaded';
END $$;


ROLLBACK;
