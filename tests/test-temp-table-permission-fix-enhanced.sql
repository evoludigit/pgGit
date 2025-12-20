-- Enhanced Test: Verify temp table permission fix
-- Tests the specific permission error scenario from pggit-temp-table-permission-fix.md

\echo 'Testing enhanced temp table permission fix'
\echo '=========================================='

-- Enable detailed error reporting
\set VERBOSITY verbose

-- Create test user with minimal privileges
DO $$
BEGIN
    -- Drop if exists
    DROP ROLE IF EXISTS pggit_restricted_user;
    
    -- Create new role
    CREATE ROLE pggit_restricted_user LOGIN PASSWORD 'test123';
    
    -- Grant minimal permissions
    GRANT USAGE ON SCHEMA public TO pggit_restricted_user;
    GRANT CREATE ON SCHEMA public TO pggit_restricted_user;
    
    -- Explicitly REVOKE all permissions on pggit schema
    REVOKE ALL ON SCHEMA pggit FROM pggit_restricted_user;
    REVOKE ALL ON ALL TABLES IN SCHEMA pggit FROM pggit_restricted_user;
    REVOKE ALL ON ALL SEQUENCES IN SCHEMA pggit FROM pggit_restricted_user;
    REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pggit FROM pggit_restricted_user;
    
    -- Specifically ensure NO INSERT on pggit.objects
    REVOKE INSERT, UPDATE, DELETE, SELECT ON pggit.objects FROM pggit_restricted_user;
    REVOKE INSERT, UPDATE, DELETE, SELECT ON pggit.history FROM pggit_restricted_user;
END$$;

\echo ''
\echo 'Test 1: Direct temp table creation by restricted user'
\echo '-----------------------------------------------------'

-- Save current role
SELECT current_user AS original_user \gset

-- Switch to restricted user
SET ROLE pggit_restricted_user;
SELECT current_user AS test_user;

-- This should succeed without permission errors
\echo 'Creating temp table with ON COMMIT DROP...'
CREATE TEMP TABLE test_temp_drop (
    id UUID DEFAULT gen_random_uuid(),
    data TEXT
) ON COMMIT DROP;

\echo 'Creating temp table with PRESERVE ROWS...'
CREATE TEMP TABLE test_temp_preserve (
    id INTEGER PRIMARY KEY,
    value NUMERIC(10,2)
) ON COMMIT PRESERVE ROWS;

-- Test operations on temp table
\echo 'Testing operations on temp table...'
INSERT INTO test_temp_preserve VALUES (1, 100.50), (2, 200.75);
SELECT COUNT(*) AS temp_table_rows FROM test_temp_preserve;

-- Create index on temp table (should also not be tracked)
\echo 'Creating index on temp table...'
CREATE INDEX idx_temp_preserve_value ON test_temp_preserve(value);

-- Drop temp table explicitly
\echo 'Dropping temp table...'
DROP TABLE test_temp_preserve;

-- Reset to original user
RESET ROLE;

\echo ''
\echo 'Test 2: Function with temp table called by restricted user'
\echo '----------------------------------------------------------'

-- Create a function that uses temp tables (as superuser)
CREATE OR REPLACE FUNCTION public.calculate_with_temp_table(
    input_values numeric[]
) RETURNS TABLE(
    calculation_id UUID,
    input_value NUMERIC,
    squared_value NUMERIC,
    sqrt_value NUMERIC
) AS $$
BEGIN
    -- Create temp table for calculations
    CREATE TEMP TABLE temp_calculations (
        id UUID DEFAULT gen_random_uuid(),
        val NUMERIC,
        squared NUMERIC,
        square_root NUMERIC
    ) ON COMMIT DROP;
    
    -- Populate temp table
    INSERT INTO temp_calculations (val, squared, square_root)
    SELECT 
        unnest(input_values),
        unnest(input_values) ^ 2,
        sqrt(abs(unnest(input_values)))
    FROM generate_series(1, array_length(input_values, 1));
    
    -- Return results
    RETURN QUERY 
    SELECT id, val, squared, square_root 
    FROM temp_calculations
    ORDER BY val;
END;
$$ LANGUAGE plpgsql;

-- Grant execute to restricted user
GRANT EXECUTE ON FUNCTION public.calculate_with_temp_table(numeric[]) TO pggit_restricted_user;

-- Test as restricted user
SET ROLE pggit_restricted_user;

\echo 'Calling function that creates temp table...'
SELECT * FROM public.calculate_with_temp_table(ARRAY[1.5, 2.5, 3.5, 4.5]);

-- Reset role
RESET ROLE;

\echo ''
\echo 'Test 3: Complex scenario with nested temp table operations'
\echo '---------------------------------------------------------'

-- Create a more complex function with multiple temp tables
CREATE OR REPLACE FUNCTION public.complex_temp_operations()
RETURNS TEXT AS $$
DECLARE
    result_text TEXT;
BEGIN
    -- First temp table
    CREATE TEMP TABLE temp_stage1 (
        id SERIAL,
        data TEXT
    ) ON COMMIT DROP;
    
    -- Insert some data
    INSERT INTO temp_stage1 (data) 
    VALUES ('test1'), ('test2'), ('test3');
    
    -- Second temp table based on first
    CREATE TEMP TABLE temp_stage2 AS
    SELECT id, data, length(data) as data_length
    FROM temp_stage1;
    
    -- Create temp view
    CREATE TEMP VIEW temp_view_summary AS
    SELECT COUNT(*) as total_rows, SUM(data_length) as total_length
    FROM temp_stage2;
    
    -- Get result
    SELECT format('Processed %s rows with total length %s', total_rows, total_length)
    INTO result_text
    FROM temp_view_summary;
    
    RETURN result_text;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.complex_temp_operations() TO pggit_restricted_user;

-- Test as restricted user
SET ROLE pggit_restricted_user;

\echo 'Calling complex function with multiple temp objects...'
SELECT public.complex_temp_operations() AS complex_result;

-- Reset role
RESET ROLE;

\echo ''
\echo 'Verification: Check that NO temp objects were tracked'
\echo '----------------------------------------------------'

-- Check pggit.objects for any temp entries
SELECT COUNT(*) AS temp_objects_in_pggit
FROM pggit.objects
WHERE schema_name LIKE 'pg_temp%'
   OR object_name LIKE '%temp%'
   OR object_name LIKE '%tmp%';

-- Check history for any temp-related entries
SELECT COUNT(*) AS temp_history_in_pggit
FROM pggit.history h
JOIN pggit.objects o ON h.object_id = o.id
WHERE o.schema_name LIKE 'pg_temp%'
   OR o.object_name LIKE '%temp%'
   OR o.object_name LIKE '%tmp%';

-- Show any objects created in the last minute (should be none)
\echo 'Objects created in last minute (should be empty):'
SELECT object_type, schema_name, object_name, created_at
FROM pggit.objects
WHERE created_at > NOW() - INTERVAL '1 minute'
ORDER BY created_at DESC;

\echo ''
\echo 'Cleanup'
\echo '-------'

-- Clean up
DROP FUNCTION IF EXISTS public.calculate_with_temp_table(numeric[]);
DROP FUNCTION IF EXISTS public.complex_temp_operations();
DROP ROLE IF EXISTS pggit_restricted_user;

\echo ''
\echo 'Enhanced permission test completed successfully!'
\echo 'No permission errors should have occurred.'