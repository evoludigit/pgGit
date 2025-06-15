-- DDL Hashing Demo for pg_gitversion
-- This demonstrates the new hash-based change detection capabilities

-- ============================================
-- PART 1: Setup and Install Hashing Extension
-- ============================================

-- Install the base extension first
CREATE EXTENSION IF NOT EXISTS pg_gitversion;

-- Load the hashing functionality
\i sql/009_ddl_hashing.sql

-- Verify hashing functions are available
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'gitversion'
AND routine_name LIKE '%hash%'
ORDER BY routine_name;

-- ============================================
-- PART 2: Populate Hashes for Existing Objects
-- ============================================

-- If you have existing tracked objects, update them with hashes
SELECT * FROM gitversion.update_all_hashes();

-- View current state
SELECT 
    object_type,
    COUNT(*) as total_objects,
    COUNT(ddl_hash) as with_hash,
    COUNT(*) - COUNT(ddl_hash) as missing_hash
FROM gitversion.objects
WHERE is_active = true
GROUP BY object_type
ORDER BY object_type;

-- ============================================
-- PART 3: Demonstrate Hash-Based Change Detection
-- ============================================

-- Create some test tables
CREATE TABLE hash_demo_users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE hash_demo_posts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES hash_demo_users(id),
    title VARCHAR(200) NOT NULL,
    content TEXT,
    published BOOLEAN DEFAULT FALSE
);

-- Check the hashes were computed
SELECT 
    full_name,
    object_type,
    ddl_hash,
    LENGTH(ddl_hash) as hash_length
FROM gitversion.objects
WHERE full_name LIKE 'public.hash_demo_%'
ORDER BY full_name;

-- ============================================
-- PART 4: Compare Hash vs Full Change Detection
-- ============================================

-- Traditional approach: Would need to compare full DDL or metadata
\timing on

-- Time the hash-based approach
SELECT 
    COUNT(*) as objects_checked,
    COUNT(*) FILTER (WHERE has_changed) as changed_objects
FROM gitversion.detect_changes_by_hash();

-- Show the actual changes detected
SELECT 
    full_name,
    object_type,
    old_hash,
    new_hash,
    has_changed
FROM gitversion.detect_changes_by_hash()
WHERE has_changed = true;

\timing off

-- ============================================
-- PART 5: Demonstrate Component Hashing
-- ============================================

-- For tables, we can hash different components separately
SELECT 
    'hash_demo_users' as table_name,
    structure_hash,
    constraints_hash,
    indexes_hash
FROM gitversion.compute_table_component_hashes('public', 'hash_demo_users');

-- Make different types of changes and see component hash changes
-- Add a new column (structure change)
ALTER TABLE hash_demo_users ADD COLUMN phone VARCHAR(20);

-- Add a constraint (constraint change)
ALTER TABLE hash_demo_users ADD CONSTRAINT check_email_format 
    CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- Add an index (index change)
CREATE INDEX idx_hash_demo_users_name ON hash_demo_users(name);

-- Check component hashes again
SELECT 
    'hash_demo_users_after_changes' as table_name,
    structure_hash,
    constraints_hash,
    indexes_hash
FROM gitversion.compute_table_component_hashes('public', 'hash_demo_users');

-- ============================================
-- PART 6: Cross-Database Schema Comparison
-- ============================================

-- Export current schema hashes (could be sent to another database)
\COPY (SELECT json_object_agg(object_name, ddl_hash) FROM gitversion.export_schema_hashes('public')) TO '/tmp/schema_hashes.json'

-- View the export format
SELECT 
    object_type,
    object_name,
    LEFT(ddl_hash, 16) || '...' as hash_preview
FROM gitversion.export_schema_hashes('public')
WHERE object_name LIKE 'hash_demo_%'
ORDER BY object_type, object_name;

-- ============================================
-- PART 7: False Positive Detection
-- ============================================

-- Demonstrate that semantically identical changes don't trigger hash changes
-- (These should produce the same hash)

-- Create a table
CREATE TABLE hash_consistency_test (
    id    INTEGER   PRIMARY KEY,
    name  VARCHAR(100)  NOT NULL,
    email VARCHAR(255) UNIQUE
);

-- Get the hash
SELECT ddl_hash 
FROM gitversion.objects 
WHERE full_name = 'public.hash_consistency_test';

-- Drop and recreate with different formatting (should have same hash)
DROP TABLE hash_consistency_test;

CREATE TABLE hash_consistency_test (
    id INTEGER PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE
);

-- Check if hash is the same (it should be)
SELECT 
    full_name,
    ddl_hash,
    'Hash should be identical despite formatting differences' as note
FROM gitversion.objects 
WHERE full_name = 'public.hash_consistency_test'
ORDER BY version DESC
LIMIT 2;

-- ============================================
-- PART 8: Change History with Hashes
-- ============================================

-- View hash-based change history
SELECT 
    full_name,
    object_type,
    change_type,
    LEFT(old_hash, 8) || '...' as old_hash_preview,
    LEFT(new_hash, 8) || '...' as new_hash_preview,
    false_positive,  -- Shows if old_hash = new_hash (false positive)
    created_at,
    created_by
FROM gitversion.hash_history
WHERE full_name LIKE 'public.hash_%'
ORDER BY created_at DESC
LIMIT 20;

-- ============================================
-- PART 9: Performance Comparison Demo
-- ============================================

-- Create many tables for performance testing
DO $$
BEGIN
    FOR i IN 1..100 LOOP
        EXECUTE format('
            CREATE TABLE perf_test_%s (
                id SERIAL PRIMARY KEY,
                data_%s VARCHAR(50),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )', i, i);
    END LOOP;
END $$;

-- Time hash-based change detection
\timing on
SELECT COUNT(*) FROM gitversion.detect_changes_by_hash();
\timing off

-- Compare object counts
SELECT 
    'Total objects tracked' as metric,
    COUNT(*) as count
FROM gitversion.objects
WHERE is_active = true
UNION ALL
SELECT 
    'Objects with hashes',
    COUNT(*)
FROM gitversion.objects
WHERE is_active = true AND ddl_hash IS NOT NULL;

-- ============================================
-- PART 10: Advanced Hash Analysis
-- ============================================

-- Find objects with identical hashes (potential duplicates)
WITH hash_counts AS (
    SELECT 
        ddl_hash,
        COUNT(*) as count,
        array_agg(full_name ORDER BY full_name) as objects
    FROM gitversion.objects
    WHERE is_active = true
    AND ddl_hash IS NOT NULL
    GROUP BY ddl_hash
    HAVING COUNT(*) > 1
)
SELECT 
    ddl_hash,
    count as duplicate_count,
    objects
FROM hash_counts
ORDER BY count DESC;

-- Hash distribution analysis
SELECT 
    object_type,
    COUNT(*) as total,
    COUNT(DISTINCT ddl_hash) as unique_hashes,
    ROUND(COUNT(DISTINCT ddl_hash)::numeric / COUNT(*) * 100, 2) as uniqueness_pct
FROM gitversion.objects
WHERE is_active = true
AND ddl_hash IS NOT NULL
GROUP BY object_type
ORDER BY object_type;

-- ============================================
-- PART 11: Change Detection Views
-- ============================================

-- View all objects that have changed since last hash computation
SELECT 
    full_name,
    object_type,
    version,
    LEFT(stored_hash, 12) || '...' as stored,
    LEFT(current_hash, 12) || '...' as current,
    has_changed,
    updated_at
FROM gitversion.changed_objects
WHERE has_changed = true;

-- Check for any false positives in recent history
SELECT 
    COUNT(*) as total_changes,
    COUNT(*) FILTER (WHERE false_positive) as false_positives,
    ROUND(
        COUNT(*) FILTER (WHERE false_positive)::numeric / 
        NULLIF(COUNT(*), 0) * 100, 2
    ) as false_positive_rate
FROM gitversion.hash_history
WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '1 hour';

-- ============================================
-- CLEANUP (Optional)
-- ============================================

-- Clean up demo tables
-- DROP TABLE hash_demo_users CASCADE;
-- DROP TABLE hash_demo_posts;
-- DROP TABLE hash_consistency_test;

-- Clean up performance test tables
-- DO $$
-- BEGIN
--     FOR i IN 1..100 LOOP
--         EXECUTE format('DROP TABLE IF EXISTS perf_test_%s', i);
--     END LOOP;
-- END $$;

-- Summary report
SELECT 
    'DDL Hashing Demo Complete' as status,
    COUNT(*) as total_tracked_objects,
    COUNT(ddl_hash) as objects_with_hashes,
    COUNT(*) FILTER (WHERE ddl_hash IS NOT NULL) * 100.0 / COUNT(*) as hash_coverage_pct
FROM gitversion.objects
WHERE is_active = true;