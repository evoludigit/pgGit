-- User Journey Test: Chapter 4 - Watching Changes Evolve
-- Tests: ALTER TABLE tracking and version incrementing
-- Expected: ALTER is tracked, version increments to 1.1.0 or higher

-- Prerequisite: users table should exist from scenario 02
-- If not, create it
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Get the current version before ALTER
CREATE TEMP TABLE version_before AS
SELECT version, version_string
FROM pggit.get_version('public.users');

-- ALTER TABLE: Add name and bio columns (from the guide)
ALTER TABLE users
ADD COLUMN name VARCHAR(100),
ADD COLUMN bio TEXT;

-- Verify columns were added
SELECT
    COUNT(*) >= 5 AS has_all_columns
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name = 'users'
AND column_name IN ('id', 'email', 'created_at', 'name', 'bio');

-- Get the new version after ALTER
CREATE TEMP TABLE version_after AS
SELECT version, version_string
FROM pggit.get_version('public.users');

-- Verify version incremented
SELECT
    va.version > vb.version AS version_incremented,
    va.version_string != vb.version_string AS version_string_changed
FROM version_before vb
CROSS JOIN version_after va;

-- Check history now shows 2 changes
SELECT
    COUNT(*) >= 2 AS has_multiple_history_entries,
    MAX(CASE WHEN change_type = 'CREATE' THEN 1 ELSE 0 END) = 1 AS has_create,
    MAX(CASE WHEN change_type = 'ALTER' THEN 1 ELSE 0 END) = 1 AS has_alter
FROM pggit.get_history('public.users');

-- Verify ALTER description contains column information
SELECT
    change_description ILIKE '%name%' OR
    change_description ILIKE '%bio%' OR
    change_description ILIKE '%column%' AS alter_description_has_details
FROM pggit.get_history('public.users')
WHERE change_type = 'ALTER'
ORDER BY created_at DESC
LIMIT 1;

-- Verify change order (CREATE should be first, ALTER second)
WITH numbered_history AS (
    SELECT
        change_type,
        ROW_NUMBER() OVER (ORDER BY created_at) AS change_order
    FROM pggit.get_history('public.users')
)
SELECT
    MAX(CASE WHEN change_order = 1 AND change_type = 'CREATE' THEN 1 ELSE 0 END) = 1 AS create_is_first,
    MAX(CASE WHEN change_order = 2 AND change_type = 'ALTER' THEN 1 ELSE 0 END) = 1 AS alter_is_second
FROM numbered_history;

-- Test output
SELECT 'Schema evolution tracked successfully' AS status,
       version_string AS current_version,
       (SELECT COUNT(*) FROM pggit.get_history('public.users')) AS total_changes
FROM pggit.get_version('public.users');

-- Cleanup temp tables
DROP TABLE IF EXISTS version_before;
DROP TABLE IF EXISTS version_after;
