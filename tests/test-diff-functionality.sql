-- ============================================
-- pgGit Diff Functionality Test Suite
-- ============================================
-- Tests for schema and data diffing capabilities
-- Following TDD approach: write tests first, then implement

\echo 'Starting pgGit diff functionality tests...'

-- Assert diff functionality is available
DO $$
BEGIN
    PERFORM pggit.assert_function_exists('diff_schemas');
    RAISE NOTICE 'PASS: Diff functionality is loaded';
END $$;

-- Test setup - using separate transactions to avoid cascading failures
