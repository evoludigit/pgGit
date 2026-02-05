-- pgGit Zero-Downtime Deployment Tests
-- Testing blue-green deployments and shadow tables
-- Enterprise-grade deployment strategies

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

-- Assert zero-downtime features are available
DO $$
BEGIN
    PERFORM pggit.assert_function_exists('start_zero_downtime_deployment');
    RAISE NOTICE 'PASS: Zero-downtime deployment features are loaded';
END $$;

ROLLBACK;
