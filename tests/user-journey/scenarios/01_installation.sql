-- User Journey Test: Chapter 2 - Installation
-- Tests: Fresh installation of pgGit extension
-- Expected: Extension installs without errors and is ready to use

-- Install pgGit using the standard installation script
\i sql/install.sql

-- Note: pgGit is installed via SQL files, not as a standard PostgreSQL extension
-- It creates the pggit schema and functions directly

-- Verify core schema exists
SELECT EXISTS (
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
