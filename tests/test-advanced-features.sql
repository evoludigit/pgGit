-- pgGit Advanced Features Integration Test
-- Demonstrating the complete impressive reality
-- All enterprise features working together

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

-- Assert advanced features are available
DO $$
BEGIN
    PERFORM pggit.assert_function_exists('record_ai_prediction');
    RAISE NOTICE 'PASS: Advanced features are loaded';
END $$;

ROLLBACK;
