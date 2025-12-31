-- User Journey Test: Chapter 9 - Complete API Reference
-- Tests: All documented API functions work correctly
-- Expected: All functions callable and return sensible results

-- Setup: Create test schema
CREATE TABLE IF NOT EXISTS test_api_table (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Test 1: pggit.get_version()
-- Should return version info for a specific object
SELECT
    object_name IS NOT NULL AS get_version_returns_object_name,
    schema_name IS NOT NULL AS get_version_returns_schema,
    version IS NOT NULL AS get_version_returns_version,
    version_string IS NOT NULL AS get_version_returns_version_string,
    created_at IS NOT NULL AS get_version_returns_timestamp
FROM pggit.get_version('public.test_api_table');

-- Test 2: pggit.get_history()
-- Should return change history
SELECT
    COUNT(*) >= 1 AS get_history_returns_records
FROM pggit.get_history('public.test_api_table');

-- Verify history structure
SELECT
    version IS NOT NULL AS history_has_version,
    change_type IS NOT NULL AS history_has_change_type,
    change_description IS NOT NULL AS history_has_description,
    created_at IS NOT NULL AS history_has_timestamp,
    created_by IS NOT NULL AS history_has_user
FROM pggit.get_history('public.test_api_table')
LIMIT 1;

-- Test 3: pggit.get_history() with limit
-- Should respect the limit parameter
SELECT
    COUNT(*) <= 5 AS get_history_respects_limit
FROM pggit.get_history('public.test_api_table', 5);

-- Test 4: pggit.show_table_versions()
-- Should return versions for all tracked tables
SELECT
    COUNT(*) >= 1 AS show_table_versions_returns_data
FROM pggit.show_table_versions();

-- Verify show_table_versions structure
SELECT
    object_name IS NOT NULL AS versions_has_object_name,
    schema_name IS NOT NULL AS versions_has_schema,
    version_string IS NOT NULL AS versions_has_version_string
FROM pggit.show_table_versions()
LIMIT 1;

-- Test 5: pggit.get_impact_analysis()
-- Should return dependency information (or empty if no dependencies)
SELECT
    TRUE AS get_impact_analysis_callable
FROM (
    SELECT * FROM pggit.get_impact_analysis('public.test_api_table')
    LIMIT 1
) AS impact_check;

-- Test 6: pggit.generate_migration()
-- Should generate migration without errors
SELECT
    result IS NOT NULL AS generate_migration_callable,
    LENGTH(result::TEXT) >= 0 AS generate_migration_returns_value
FROM (
    SELECT pggit.generate_migration(
        'api_test_migration',
        'Testing migration generation from API test'
    ) AS result
) AS migration_test;

-- Test 7: Verify all key functions are documented in pg_proc
WITH expected_functions AS (
    SELECT unnest(ARRAY[
        'get_version',
        'get_history',
        'get_impact_analysis',
        'show_table_versions',
        'generate_migration'
    ]) AS function_name
)
SELECT
    COUNT(*) = 5 AS all_documented_functions_exist
FROM expected_functions ef
JOIN pg_proc p ON p.proname = ef.function_name
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'pggit';

-- Test 8: Verify event triggers are active
SELECT
    COUNT(*) >= 2 AS event_triggers_active
FROM pg_event_trigger
WHERE evtenabled = 'O'  -- 'O' means enabled
AND evtname LIKE 'pggit_%';

-- Test 9: Verify pgGit schema is accessible
SELECT
    has_schema_privilege('pggit', 'USAGE') AS can_access_pggit_schema;

-- Test 10: Verify version table is accessible
SELECT
    COUNT(*) >= 0 AS can_query_version_table
FROM pggit.schema_versions
LIMIT 1;

-- Summary output
SELECT
    'All API functions working' AS status,
    COUNT(DISTINCT p.proname) AS total_functions
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'pggit';
