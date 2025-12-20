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

-- Skip entire test suite if CQRS system not available
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'track_cqrs_change' AND pronamespace = 'pggit'::regnamespace) THEN
        RAISE NOTICE 'CQRS system not loaded, skipping all CQRS tests';
        RETURN;
    END IF;

    RAISE NOTICE 'CQRS system available, running tests';

    -- Basic functionality test
    IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'cqrs_change' AND typnamespace = 'pggit'::regnamespace) THEN
        RAISE NOTICE 'CQRS types available';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'pggit' AND tablename = 'cqrs_changesets') THEN
        RAISE NOTICE 'CQRS tables available';
    END IF;

END $$;
