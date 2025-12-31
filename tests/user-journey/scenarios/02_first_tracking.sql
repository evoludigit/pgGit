-- User Journey Test: Chapter 3 - First Automatic Tracking
-- Tests: Creating a table and verifying automatic version tracking
-- Expected: Table creation is tracked automatically with version 1.0.0

-- Clean up any existing test data
DROP TABLE IF EXISTS users CASCADE;

-- Create the users table (from the guide)
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Verify table was created
SELECT EXISTS (
    SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'users'
) AS table_created;

-- Check version information
SELECT
    object_name = 'users' AS correct_object_name,
    schema_name = 'public' AS correct_schema,
    version >= 1 AS has_version,
    version_string IS NOT NULL AS has_version_string,
    created_at IS NOT NULL AS has_timestamp
FROM pggit.get_version('public.users');

-- Verify version string format (should be something like 1.0.0)
SELECT
    version_string ~ '^\d+\.\d+\.\d+$' AS version_format_valid
FROM pggit.get_version('public.users');

-- Check history contains the CREATE event
SELECT
    COUNT(*) >= 1 AS create_event_tracked,
    MAX(CASE WHEN change_type = 'CREATE' THEN 1 ELSE 0 END) = 1 AS has_create_type
FROM pggit.get_history('public.users');

-- Verify column tracking (if implemented)
SELECT
    COUNT(*) >= 3 AS has_expected_columns
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name = 'users'
AND column_name IN ('id', 'email', 'created_at');

-- Test output
SELECT 'First table tracked automatically' AS status,
       version_string AS version
FROM pggit.get_version('public.users');
