-- User Journey Test: Chapter 2 - Installation
-- Tests: Fresh installation of pgGit extension
-- Expected: Extension installs without errors and is ready to use

-- Ensure pgcrypto extension is installed (required dependency)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Install pgGit using the consolidated extension SQL
-- Note: In production use CREATE EXTENSION pggit (after running make install)
-- For testing we load the consolidated SQL directly
-- Path is relative to workspace root (../../../ from scenarios/)
\i ../../../pggit--1.0.0.sql

-- NOTE: The above \i directive loads a large SQL file (300KB+) which is executed via psql
-- The queries below will be executed separately via psycopg to collect results

-- Verify pgGit was installed successfully
-- Note: In test mode we check for schema existence instead of pg_extension entry
-- since we load SQL directly rather than via CREATE EXTENSION
SELECT EXISTS (
    SELECT 1 FROM pg_namespace WHERE nspname = 'pggit'
) AS extension_installed, -- Using same column name for test compatibility
EXISTS (
    SELECT 1 FROM pg_namespace WHERE nspname = 'pggit'
) AS schema_exists;

-- Verify event triggers are installed
SELECT COUNT(*) >= 2 AS event_triggers_installed
FROM pg_event_trigger
WHERE evtname LIKE 'pggit_%';

-- Verify key functions exist
SELECT
    COUNT(*) >= 5 AS core_functions_exist
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'pggit'
AND p.proname IN (
    'get_version',
    'get_history',
    'get_impact_analysis',
    'show_table_versions',
    'generate_migration'
);

-- Verify core tables exist
SELECT
    COUNT(*) >= 1 AS version_table_exists
FROM pg_tables
WHERE schemaname = 'pggit'
AND tablename LIKE '%version%';

-- Test output message
SELECT 'pgGit extension installed successfully' AS status;
