-- Test suite for pgGit Migration Tool Integration
-- Tests integration with Flyway, Liquibase, and generic migration tools

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
CREATE SCHEMA test_migrations;

\echo 'Testing Migration Integration...'

-- Test 1: Basic migration tracking
\echo '  Test 1: Basic migration tracking'

-- Assert migration integration is available
DO $$
BEGIN
    PERFORM pggit.assert_function_exists('begin_migration');
    RAISE NOTICE 'PASS: Migration integration is loaded';
END $$;


ROLLBACK;
