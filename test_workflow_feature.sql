-- UAT Workflow Testing: Feature Branch Scenario
-- Test the intended workflow even if pggit_v0 functions have issues

\echo '=== Testing Feature Branch Workflow Scenario ==='

-- Step 1: Create a feature branch (simulate with schema changes)
\echo '\n1. Creating feature branch (simulated with schema changes)...'
CREATE SCHEMA feature_new_table;

-- Create a new table in the feature branch
CREATE TABLE feature_new_table.products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(10,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert some test data
INSERT INTO feature_new_table.products (name, price) VALUES
('Feature Product 1', 99.99),
('Feature Product 2', 149.99);

-- Add an index
CREATE INDEX idx_feature_products_name ON feature_new_table.products(name);

\echo 'Feature branch created with new table, data, and index'

-- Step 2: Simulate development work
\echo '\n2. Simulating development work (more schema changes)...'
ALTER TABLE feature_new_table.products ADD COLUMN category VARCHAR(50);
ALTER TABLE feature_new_table.products ADD COLUMN in_stock BOOLEAN DEFAULT true;

-- Add a view
CREATE VIEW feature_new_table.expensive_products AS
SELECT * FROM feature_new_table.products WHERE price > 100;

\echo 'Development work completed - added columns and view'

-- Step 3: Check what pggit tracked
\echo '\n3. Checking what pggit tracked...'
SELECT
    object_type,
    schema_name,
    object_name,
    change_type,
    change_timestamp
FROM pggit.history
WHERE schema_name LIKE 'feature_%'
ORDER BY change_timestamp DESC
LIMIT 10;

-- Step 4: Simulate merge preparation
\echo '\n4. Simulating merge preparation (comparing schemas)...'
-- Check objects in main schema vs feature schema
SELECT 'main schema objects:' as info, COUNT(*) as count
FROM pggit.objects
WHERE schema_name = 'public'
UNION ALL
SELECT 'feature schema objects:', COUNT(*)
FROM pggit.objects
WHERE schema_name LIKE 'feature_%';

-- Step 5: Simulate merge (move feature objects to main)
\echo '\n5. Simulating merge (moving feature to main schema)...'
-- In a real scenario, this would be done by applying the schema changes
-- For this test, we'll just show what would be merged
SELECT
    'Objects to merge:' as status,
    COUNT(*) as count
FROM pggit.history
WHERE schema_name LIKE 'feature_%'
    AND change_timestamp >= (SELECT MAX(change_timestamp) FROM pggit.history WHERE schema_name = 'public');

-- Step 6: Cleanup
\echo '\n6. Cleanup - dropping feature branch...'
DROP VIEW IF EXISTS feature_new_table.expensive_products;
DROP TABLE IF EXISTS feature_new_table.products;
DROP SCHEMA IF EXISTS feature_new_table;

\echo 'Feature branch workflow test completed'

-- Summary
SELECT
    'Total objects tracked:' as summary,
    COUNT(*) as count
FROM pggit.objects
WHERE schema_name LIKE 'feature_%' OR schema_name = 'uat_test';