-- Test: Verify that temporary tables are excluded from pgGit tracking
-- This test addresses the issue described in pggit-temp-table-issue.md

\echo 'Testing temporary table exclusion from pgGit tracking'

-- Clean up any existing test data
TRUNCATE pggit.objects, pggit.history CASCADE;

-- Get initial count of tracked objects
SELECT COUNT(*) AS initial_object_count FROM pggit.objects;

-- Create a regular table (should be tracked)
CREATE TABLE test_regular_table (
    id SERIAL PRIMARY KEY,
    data TEXT
);

-- Verify regular table was tracked
SELECT COUNT(*) AS after_regular_table_count FROM pggit.objects;
SELECT object_type, schema_name, object_name 
FROM pggit.objects 
WHERE object_name = 'test_regular_table';

-- Create a temporary table (should NOT be tracked)
CREATE TEMP TABLE test_temp_table (
    id UUID,
    data TEXT
) ON COMMIT DROP;

-- Verify temp table was NOT tracked
SELECT COUNT(*) AS after_temp_table_count FROM pggit.objects;
SELECT object_type, schema_name, object_name 
FROM pggit.objects 
WHERE object_name LIKE '%temp%';

-- Create another temp table with different syntax
CREATE TEMPORARY TABLE test_temp_table2 (
    id INTEGER,
    value NUMERIC
);

-- Verify second temp table was also NOT tracked
SELECT COUNT(*) AS after_temp_table2_count FROM pggit.objects;

-- Test that we can still perform operations on temp tables without errors
INSERT INTO test_temp_table2 (id, value) VALUES (1, 100.0);
SELECT * FROM test_temp_table2;

-- Create an index on the temp table (should also not be tracked)
CREATE INDEX idx_temp_table2_id ON test_temp_table2(id);

-- Verify temp index was NOT tracked
SELECT COUNT(*) AS after_temp_index_count FROM pggit.objects;
SELECT object_type, schema_name, object_name 
FROM pggit.objects 
WHERE object_type = 'INDEX' AND created_at > NOW() - INTERVAL '1 minute';

-- Clean up
DROP TABLE test_regular_table;
DROP TABLE test_temp_table2;

-- Final verification - only the regular table and its drop should be in history
SELECT 
    h.change_type,
    o.object_type,
    o.schema_name,
    o.object_name
FROM pggit.history h
JOIN pggit.objects o ON h.object_id = o.id
ORDER BY h.created_at;

\echo 'Temporary table exclusion test completed'