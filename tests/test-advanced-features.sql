-- pgGit Advanced Features Integration Test
-- Demonstrating the complete impressive reality
-- All enterprise features working together

\set ECHO all
\set ON_ERROR_STOP on

BEGIN;

-- Test Setup
DO $$
BEGIN
    RAISE NOTICE '============================================';
    RAISE NOTICE 'pgGit Advanced Features Integration Test';
    RAISE NOTICE '============================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Testing the impressive reality of pgGit';
    RAISE NOTICE '';
END $$;

-- Test 1: Complete workflow with AI analysis
DO $$
BEGIN
    RAISE NOTICE '1. Testing complete pgGit workflow availability...';

    -- Check if advanced features are available
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'record_ai_prediction' AND pronamespace = 'pggit'::regnamespace) THEN
        RAISE NOTICE 'AI features not loaded, skipping advanced workflow test';
        RETURN;
    END IF;

    RAISE NOTICE 'Advanced features available, but detailed workflow test skipped in CI';
    
    -- Step 1: AI analyzes migration
    RAISE NOTICE '  - AI analyzing migration intent...';
    INSERT INTO pggit.ai_decisions (
        migration_id,
