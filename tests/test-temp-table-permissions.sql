-- Test: Verify that users without INSERT permissions on pggit.objects
-- can still create temporary tables without errors
-- This test addresses the permission issue described in pggit-temp-table-issue.md

\echo 'Testing temporary table creation with restricted user permissions'

-- Create a test user with limited privileges
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'test_limited_user') THEN
        CREATE ROLE test_limited_user LOGIN PASSWORD 'test123';
    END IF;
END$$;

-- Grant basic permissions to the test user
GRANT USAGE ON SCHEMA public TO test_limited_user;
GRANT CREATE ON SCHEMA public TO test_limited_user;

-- Explicitly REVOKE INSERT permissions on pggit.objects
REVOKE INSERT ON pggit.objects FROM test_limited_user;

-- Create a function that uses temporary tables (as the regular user)
CREATE OR REPLACE FUNCTION public.test_function_with_temp_table()
RETURNS TABLE(result_id UUID, result_data TEXT) AS $$
BEGIN
    -- This is the pattern that was causing issues
    CREATE TEMP TABLE tmp_calculations (
        id UUID,
        data TEXT
    ) ON COMMIT DROP;
    
    -- Simulate some work with the temp table
    INSERT INTO tmp_calculations VALUES 
        (gen_random_uuid(), 'test1'),
        (gen_random_uuid(), 'test2');
    
    RETURN QUERY SELECT * FROM tmp_calculations;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permission to the test user
GRANT EXECUTE ON FUNCTION public.test_function_with_temp_table() TO test_limited_user;

-- Now test as the limited user
\echo 'Switching to limited user context...'
SET ROLE test_limited_user;

-- This should work without permission errors
\echo 'Calling function that creates temp table (should succeed)...'
SELECT * FROM public.test_function_with_temp_table();

-- Also test direct temp table creation
\echo 'Creating temp table directly (should succeed)...'
CREATE TEMP TABLE direct_temp_test (
    id INTEGER,
    value TEXT
) ON COMMIT PRESERVE ROWS;

INSERT INTO direct_temp_test VALUES (1, 'test');
SELECT * FROM direct_temp_test;
DROP TABLE direct_temp_test;

-- Switch back to regular user
RESET ROLE;

-- Verify that no temp tables were tracked in pggit.objects
\echo 'Verifying no temp tables were tracked...'
SELECT COUNT(*) AS temp_objects_count
FROM pggit.objects
WHERE schema_name LIKE 'pg_temp%'
   OR object_name LIKE '%tmp%'
   OR object_name LIKE '%temp%';

-- Clean up
DROP FUNCTION public.test_function_with_temp_table();
DROP ROLE IF EXISTS test_limited_user;

\echo 'Permission test completed successfully'