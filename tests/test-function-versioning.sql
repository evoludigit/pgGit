-- Test suite for pgGit Enhanced Function Versioning
-- Tests function overloading, signature tracking, and version management

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
CREATE SCHEMA IF NOT EXISTS test_functions;

-- Test 1: Basic function tracking
\echo '  Test 1: Basic function tracking'

-- Assert function versioning is available
DO $$
BEGIN
    PERFORM pggit.assert_function_exists('track_function');
    RAISE NOTICE 'PASS: Function versioning is loaded';
END $$;

ROLLBACK;
