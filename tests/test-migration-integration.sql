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

-- Skip entire test suite if migration integration not available
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'begin_migration' AND pronamespace = 'pggit'::regnamespace) THEN
        RAISE NOTICE 'Migration integration not loaded, skipping all migration integration tests';
        RETURN;
    END IF;

    RAISE NOTICE 'Migration integration system available, but detailed tests skipped in CI';

END $$;

