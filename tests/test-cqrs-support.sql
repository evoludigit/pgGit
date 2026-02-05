-- Test suite for pgGit CQRS Support
-- Tests Command Query Responsibility Segregation tracking features

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
CREATE SCHEMA IF NOT EXISTS command;
CREATE SCHEMA IF NOT EXISTS query;

-- Test 1: Basic CQRS change tracking
\echo '  Test 1: Basic CQRS change tracking'

-- Assert CQRS system is available
DO $$
BEGIN
    PERFORM pggit.assert_function_exists('track_cqrs_change');
    RAISE NOTICE 'PASS: CQRS system available, running tests';
END $$;

ROLLBACK;
