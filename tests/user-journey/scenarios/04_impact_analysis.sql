-- User Journey Test: Chapter 5 - Impact Analysis (Safety Net)
-- Tests: Dependency detection before dropping/altering
-- Expected: Impact analysis shows foreign keys and views

-- Ensure users table exists
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create a dependent table (foreign key reference)
DROP TABLE IF EXISTS user_reports CASCADE;
CREATE TABLE user_reports (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id),
    report_text TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create a dependent view
DROP VIEW IF EXISTS user_summary CASCADE;
CREATE VIEW user_summary AS
SELECT
    u.id,
    u.email,
    COUNT(r.id) AS report_count
FROM users u
LEFT JOIN user_reports r ON u.id = r.user_id
GROUP BY u.id, u.email;

-- Verify dependencies were created
SELECT
    EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'user_reports') AS dependent_table_exists,
    EXISTS (SELECT 1 FROM pg_views WHERE viewname = 'user_summary') AS dependent_view_exists;

-- Test impact analysis function
SELECT
    COUNT(*) >= 1 AS impact_analysis_returns_results
FROM pggit.get_impact_analysis('public.users');

-- Verify impact analysis detects foreign key dependency
SELECT
    COUNT(*) >= 1 AS detects_foreign_key
FROM pggit.get_impact_analysis('public.users')
WHERE dependency_type ILIKE '%foreign%'
   OR dependent_object ILIKE '%user_reports%'
   OR dependency_type ILIKE '%table%';

-- Verify impact analysis detects view dependency
SELECT
    COUNT(*) >= 1 AS detects_view
FROM pggit.get_impact_analysis('public.users')
WHERE dependency_type ILIKE '%view%'
   OR dependent_object ILIKE '%user_summary%';

-- Verify impact analysis shows dependency details
SELECT
    dependent_object IS NOT NULL AS has_dependent_object,
    dependency_type IS NOT NULL AS has_dependency_type
FROM pggit.get_impact_analysis('public.users')
LIMIT 1;

-- Test that we can see all dependencies
SELECT
    COUNT(DISTINCT dependent_object) >= 2 AS has_multiple_dependencies
FROM pggit.get_impact_analysis('public.users');

-- Test output
SELECT
    'Impact analysis working' AS status,
    COUNT(*) AS total_dependencies,
    STRING_AGG(DISTINCT dependent_object, ', ' ORDER BY dependent_object) AS dependent_objects
FROM pggit.get_impact_analysis('public.users');
