-- ============================================
-- pgGit Diff Functionality Test Suite (Isolated Tests)
-- ============================================
-- Each test runs in its own transaction to prevent cascading failures

\echo 'Starting isolated pgGit diff functionality tests...'

-- Setup test schemas
DROP SCHEMA IF EXISTS test_diff_source CASCADE;
DROP SCHEMA IF EXISTS test_diff_target CASCADE;
CREATE SCHEMA test_diff_source;
CREATE SCHEMA test_diff_target;

-- ============================================
-- Test 1: Schema diff - table addition
-- ============================================
\echo 'Test 1: Detecting new table addition...'
BEGIN;

CREATE TABLE test_diff_target.new_users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DO $$
DECLARE
    v_found_add BOOLEAN := FALSE;
    v_diff_result RECORD;
BEGIN
    FOR v_diff_result IN 
        SELECT * FROM pggit.diff_schemas('test_diff_source', 'test_diff_target')
    LOOP
        IF v_diff_result.object_name = 'new_users' 
           AND v_diff_result.change_type = 'ADD' THEN
            v_found_add := TRUE;
            EXIT;
        END IF;
    END LOOP;
    
    IF v_found_add THEN
        RAISE NOTICE 'Test 1 PASSED: Table addition detected';
    ELSE
        RAISE EXCEPTION 'Test 1 FAILED: Table addition not detected';
    END IF;
END $$;

ROLLBACK;

-- ============================================
-- Test 2: Schema diff - table removal
-- ============================================
\echo 'Test 2: Detecting table removal...'
BEGIN;

CREATE TABLE test_diff_source.old_users (
    id INTEGER PRIMARY KEY,
    name VARCHAR(100)
);

DO $$
DECLARE
    v_found_drop BOOLEAN := FALSE;
    v_diff_result RECORD;
BEGIN
    FOR v_diff_result IN 
        SELECT * FROM pggit.diff_schemas('test_diff_source', 'test_diff_target')
    LOOP
        IF v_diff_result.object_name = 'old_users' 
           AND v_diff_result.change_type = 'DROP' THEN
            v_found_drop := TRUE;
            EXIT;
        END IF;
    END LOOP;
    
    IF v_found_drop THEN
        RAISE NOTICE 'Test 2 PASSED: Table removal detected';
    ELSE
        RAISE EXCEPTION 'Test 2 FAILED: Table removal not detected';
    END IF;
END $$;

ROLLBACK;

-- ============================================
-- Test 3: Data diff - row insertions
-- ============================================
\echo 'Test 3: Detecting row insertions...'
BEGIN;

CREATE TABLE test_diff_source.customers (
    id INTEGER PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100)
);

CREATE TABLE test_diff_target.customers (
    id INTEGER PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100)
);

INSERT INTO test_diff_source.customers VALUES 
    (1, 'Alice', 'alice@example.com'),
    (2, 'Bob', 'bob@example.com');

INSERT INTO test_diff_target.customers VALUES 
    (1, 'Alice', 'alice@example.com'),
    (2, 'Bob', 'bob@example.com'),
    (3, 'Charlie', 'charlie@example.com'),
    (4, 'David', 'david@example.com');

DO $$
DECLARE
    v_inserts_found INTEGER := 0;
    v_diff_result RECORD;
BEGIN
    FOR v_diff_result IN 
        SELECT * FROM pggit.diff_table_data('test_diff_source', 'test_diff_target', 'customers')
    LOOP
        IF v_diff_result.change_type = 'INSERT' THEN
            v_inserts_found := v_inserts_found + 1;
        END IF;
    END LOOP;
    
    IF v_inserts_found = 2 THEN
        RAISE NOTICE 'Test 3 PASSED: Row insertions detected (% rows)', v_inserts_found;
    ELSE
        RAISE EXCEPTION 'Test 3 FAILED: Expected 2 inserts, found %', v_inserts_found;
    END IF;
END $$;

ROLLBACK;

-- ============================================
-- Test 4: Data diff - row deletions  
-- ============================================
\echo 'Test 4: Detecting row deletions...'
BEGIN;

CREATE TABLE test_diff_source.inventory (
    id INTEGER PRIMARY KEY,
    product_name VARCHAR(100),
    quantity INTEGER
);

CREATE TABLE test_diff_target.inventory (
    id INTEGER PRIMARY KEY,
    product_name VARCHAR(100),
    quantity INTEGER
);

INSERT INTO test_diff_source.inventory VALUES 
    (1, 'Widget', 100),
    (2, 'Gadget', 50),
    (3, 'Doohickey', 75),
    (4, 'Thingamajig', 25);

INSERT INTO test_diff_target.inventory VALUES 
    (1, 'Widget', 100),
    (3, 'Doohickey', 75);

DO $$
DECLARE
    v_deletes_found INTEGER := 0;
    v_diff_result RECORD;
BEGIN
    FOR v_diff_result IN 
        SELECT * FROM pggit.diff_table_data('test_diff_source', 'test_diff_target', 'inventory')
    LOOP
        IF v_diff_result.change_type = 'DELETE' THEN
            v_deletes_found := v_deletes_found + 1;
        END IF;
    END LOOP;
    
    IF v_deletes_found = 2 THEN
        RAISE NOTICE 'Test 4 PASSED: Row deletions detected (% rows)', v_deletes_found;
    ELSE
        RAISE EXCEPTION 'Test 4 FAILED: Expected 2 deletions, found %', v_deletes_found;
    END IF;
END $$;

ROLLBACK;

-- ============================================
-- Test 5: Data diff - row updates
-- ============================================
\echo 'Test 5: Detecting row updates...'
BEGIN;

CREATE TABLE test_diff_source.employees (
    id INTEGER PRIMARY KEY,
    name VARCHAR(100),
    department VARCHAR(50),
    salary DECIMAL(10,2)
);

CREATE TABLE test_diff_target.employees (
    id INTEGER PRIMARY KEY,
    name VARCHAR(100),
    department VARCHAR(50),
    salary DECIMAL(10,2)
);

INSERT INTO test_diff_source.employees VALUES 
    (1, 'John Doe', 'Engineering', 75000),
    (2, 'Jane Smith', 'Marketing', 65000),
    (3, 'Bob Johnson', 'Sales', 60000);

INSERT INTO test_diff_target.employees VALUES 
    (1, 'John Doe', 'Engineering', 80000),  -- Salary changed
    (2, 'Jane Smith', 'HR', 65000),         -- Department changed
    (3, 'Robert Johnson', 'Sales', 62000);  -- Name and salary changed

DO $$
DECLARE
    v_updates_found INTEGER := 0;
    v_diff_result RECORD;
BEGIN
    FOR v_diff_result IN 
        SELECT * FROM pggit.diff_table_data('test_diff_source', 'test_diff_target', 'employees')
    LOOP
        IF v_diff_result.change_type = 'UPDATE' THEN
            v_updates_found := v_updates_found + 1;
        END IF;
    END LOOP;
    
    IF v_updates_found = 3 THEN
        RAISE NOTICE 'Test 5 PASSED: Row updates detected (% rows)', v_updates_found;
    ELSE
        RAISE EXCEPTION 'Test 5 FAILED: Expected 3 updates, found %', v_updates_found;
    END IF;
END $$;

ROLLBACK;

-- ============================================
-- Test 6: Integrated diff (pggit.diff)
-- ============================================
\echo 'Test 6: Testing integrated diff functionality...'
BEGIN;

-- Ensure pggit schema exists (should be already installed)
-- Just check that our diff function works with any table

CREATE TABLE test_integrated_diff (id INTEGER PRIMARY KEY, name TEXT);

DO $$
DECLARE
    v_diff_count INTEGER;
    v_test_passed BOOLEAN := FALSE;
BEGIN
    -- Test the diff function signature exists and works
    BEGIN
        -- Try calling diff function (may return empty results but shouldn't error)
        SELECT COUNT(*) INTO v_diff_count
        FROM pggit.diff(NULL, NULL, FALSE);
        
        -- If we got here without error, the function exists and works
        v_test_passed := TRUE;
        
    EXCEPTION WHEN OTHERS THEN
        -- Function doesn't work as expected
        v_test_passed := FALSE;
    END;
    
    IF v_test_passed THEN
        RAISE NOTICE 'Test 6 PASSED: Integrated diff function exists and works';
    ELSE
        RAISE EXCEPTION 'Test 6 FAILED: Integrated diff function has issues';
    END IF;
END $$;

ROLLBACK;

-- Cleanup
DROP SCHEMA IF EXISTS test_diff_source CASCADE;
DROP SCHEMA IF EXISTS test_diff_target CASCADE;

\echo 'All isolated diff functionality tests completed!'
\echo 'Summary: Tests for built-in diff algorithms covering both schema and data changes';