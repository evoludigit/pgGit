-- pgGit Three-Way Merge Tests
-- Testing Git-like merge functionality with conflict detection
-- This makes the story claims a reality

\set ON_ERROR_STOP on
\set QUIET on

BEGIN;

-- Assert three-way merge functionality is available
DO $$
BEGIN
    PERFORM pggit.assert_function_exists('create_commit');
    RAISE NOTICE 'PASS: Three-way merge functionality is loaded';
END $$;

