-- pggit Demo Script
-- Shows the minimal working version functionality

-- Clean up any existing demo objects
DROP TABLE IF EXISTS demo_users CASCADE;
DROP TABLE IF EXISTS demo_posts CASCADE;

-- Show current tracked objects
\echo 'Current tracked objects:'
SELECT object_type, object_name, version, is_active 
FROM pggit.object_summary 
WHERE schema_name = 'public'
ORDER BY created_at DESC
LIMIT 10;

\echo ''
\echo 'Creating demo_users table...'
-- Create a new table
CREATE TABLE demo_users (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

\echo ''
\echo 'Creating demo_posts table...'
-- Create another table with foreign key
CREATE TABLE demo_posts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES demo_users(id),
    title TEXT NOT NULL,
    content TEXT,
    published_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Check what was tracked
\echo ''
\echo 'Newly tracked objects:'
SELECT object_type, object_name, version 
FROM pggit.object_summary 
WHERE object_name LIKE '%demo_%'
ORDER BY created_at;

-- Make some changes
\echo ''
\echo 'Adding column to demo_users...'
ALTER TABLE demo_users ADD COLUMN is_active BOOLEAN DEFAULT true;

\echo ''
\echo 'Creating an index...'
CREATE INDEX idx_users_email ON demo_users(email);

-- Check version history
\echo ''
\echo 'Version history for demo_users:'
SELECT * FROM pggit.get_history('demo_users');

-- Check all changes
\echo ''
\echo 'All changes made:'
SELECT 
    o.object_type,
    o.object_name,
    h.change_type,
    h.change_severity,
    o.version_major || '.' || o.version_minor || '.' || o.version_patch as version,
    h.created_at
FROM pggit.history h
JOIN pggit.objects o ON h.object_id = o.id
WHERE o.object_name LIKE '%demo_%'
ORDER BY h.created_at;

-- Generate a migration script
\echo ''
\echo 'Generated migration script:'
SELECT pggit.generate_migration(
    (CURRENT_TIMESTAMP - INTERVAL '5 minutes')::TEXT,
    CURRENT_TIMESTAMP::TEXT
);

-- Clean up
\echo ''
\echo 'Dropping demo tables...'
DROP TABLE demo_posts;
DROP TABLE demo_users;

-- Show that drops were tracked
\echo ''
\echo 'Objects after cleanup (showing inactive):'
SELECT object_type, object_name, version, is_active 
FROM pggit.object_summary 
WHERE object_name LIKE '%demo_%'
ORDER BY updated_at DESC;