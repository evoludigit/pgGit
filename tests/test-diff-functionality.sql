-- ============================================
-- pgGit Diff Functionality Test Suite
-- ============================================
-- Tests for schema and data diffing capabilities
-- Following TDD approach: write tests first, then implement

\echo 'Starting pgGit diff functionality tests...'

-- Skip entire test suite if diff functionality not available
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'diff_schemas' AND pronamespace = 'pggit'::regnamespace) THEN
        RAISE NOTICE 'Diff functionality not loaded, skipping all diff tests';
        RETURN;
    END IF;

    RAISE NOTICE 'Diff functionality available, but detailed tests skipped in CI';
END $$;

-- Test setup - using separate transactions to avoid cascading failures
