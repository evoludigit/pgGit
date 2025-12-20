-- pgGit Test Coverage Report
-- This script analyzes which pggit functions are tested by pgTAP tests

-- Count total functions
CREATE TEMP TABLE total_functions AS
SELECT
    routine_schema,
    routine_name,
    COUNT(*) as overload_count
FROM information_schema.routines
WHERE routine_schema = 'pggit'
  AND routine_type = 'FUNCTION'
GROUP BY routine_schema, routine_name;

-- Track tested functions (from pgTAP tests)
-- This is a simplified version - in practice you'd need to parse test files
CREATE TEMP TABLE tested_functions AS
SELECT DISTINCT
    'pggit' as schema_name,
    -- Extract function names from test descriptions or comments
    -- For now, we'll use a manual list based on our test-core.sql
    unnest(ARRAY[
        'ensure_object',
        'get_history',
        'generate_migration'
    ]) as function_name;

-- Coverage report
SELECT
    'Total Functions' as metric,
    COUNT(*)::text as value
FROM total_functions
UNION ALL
SELECT
    'Tested Functions',
    COUNT(*)::text
FROM tested_functions
UNION ALL
SELECT
    'Coverage %',
    ROUND(
        (SELECT COUNT(*)::numeric FROM tested_functions) /
        NULLIF((SELECT COUNT(*) FROM total_functions), 0) * 100,
        2
    )::text || '%'
UNION ALL
SELECT
    'Untested Functions',
    string_agg(routine_name, ', ' ORDER BY routine_name)
FROM total_functions tf
WHERE NOT EXISTS (
    SELECT 1 FROM tested_functions tt
    WHERE tt.function_name = tf.routine_name
);