-- ============================================
-- pgGit Diff Functionality Test Suite
-- ============================================
-- Tests for schema and data diffing capabilities
-- Following TDD approach: write tests first, then implement

\echo 'Starting pgGit diff functionality tests...'

-- Test setup - using separate transactions to avoid cascading failures

-- Create test schemas
CREATE SCHEMA IF NOT EXISTS test_diff_source;
CREATE SCHEMA IF NOT EXISTS test_diff_target;

-- ============================================
-- SCHEMA DIFF TESTS
-- ============================================

\echo 'Testing schema diff functionality...'

-- Test 1: Detect new table addition
BEGIN;
DO $$
DECLARE
    v_diff_result RECORD;
    v_found_add BOOLEAN := FALSE;
BEGIN
    -- Setup: Create table only in target schema
    CREATE TABLE test_diff_target.new_users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) NOT NULL,
        email VARCHAR(100) UNIQUE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    -- Test: Run schema diff
    FOR v_diff_result IN 
        SELECT * FROM pggit.diff_schemas('test_diff_source', 'test_diff_target')
    LOOP
        IF v_diff_result.object_name = 'new_users' 
           AND v_diff_result.change_type = 'ADD' THEN
            v_found_add := TRUE;
        END IF;
    END LOOP;
    
    -- Assert
    IF NOT v_found_add THEN
        RAISE EXCEPTION 'Test 1 FAILED: Did not detect new table addition';
    END IF;
    
    RAISE NOTICE 'Test 1 PASSED: New table addition detected';
END $$;
ROLLBACK;

-- Test 2: Detect table removal
DO $$
DECLARE
    v_diff_result RECORD;
    v_found_drop BOOLEAN := FALSE;
BEGIN
    -- Setup: Create table only in source schema
    CREATE TABLE test_diff_source.old_users (
        id INTEGER PRIMARY KEY,
        name VARCHAR(100)
    );
    
    -- Test: Run schema diff
    FOR v_diff_result IN 
        SELECT * FROM pggit.diff_schemas('test_diff_source', 'test_diff_target')
    LOOP
        IF v_diff_result.object_name = 'old_users' 
           AND v_diff_result.change_type = 'DROP' THEN
            v_found_drop := TRUE;
        END IF;
    END LOOP;
    
    -- Assert
    IF NOT v_found_drop THEN
        RAISE EXCEPTION 'Test 2 FAILED: Did not detect table removal';
    END IF;
    
    RAISE NOTICE 'Test 2 PASSED: Table removal detected';
END $$;

-- Test 3: Detect column modifications
DO $$
DECLARE
    v_diff_result RECORD;
    v_column_changes INTEGER := 0;
BEGIN
    -- Setup: Create tables with different columns
    CREATE TABLE test_diff_source.products (
        id INTEGER PRIMARY KEY,
        name VARCHAR(100),
        price DECIMAL(10,2)
    );
    
    CREATE TABLE test_diff_target.products (
        id INTEGER PRIMARY KEY,
        name VARCHAR(200),  -- Changed length
        price DECIMAL(12,2), -- Changed precision
        description TEXT,    -- New column
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP -- New column
    );
    
    -- Test: Run schema diff
    FOR v_diff_result IN 
        SELECT * FROM pggit.diff_schemas('test_diff_source', 'test_diff_target')
    LOOP
        IF v_diff_result.object_name = 'products' 
           AND v_diff_result.change_type IN ('MODIFY', 'ALTER_COLUMN', 'ADD_COLUMN') THEN
            v_column_changes := v_column_changes + 1;
        END IF;
    END LOOP;
    
    -- Assert: Should detect at least one modification
    IF v_column_changes = 0 THEN
        RAISE EXCEPTION 'Test 3 FAILED: Did not detect column modifications';
    END IF;
    
    RAISE NOTICE 'Test 3 PASSED: Column modifications detected (% changes)', v_column_changes;
END $$;

-- Test 4: Detect constraint changes
DO $$
DECLARE
    v_diff_result RECORD;
    v_constraint_changes INTEGER := 0;
BEGIN
    -- Setup: Create tables with different constraints
    CREATE TABLE test_diff_source.orders (
        id INTEGER PRIMARY KEY,
        customer_id INTEGER,
        total DECIMAL(10,2)
    );
    
    CREATE TABLE test_diff_target.orders (
        id INTEGER PRIMARY KEY,
        customer_id INTEGER NOT NULL,  -- Added NOT NULL
        total DECIMAL(10,2) CHECK (total > 0),  -- Added CHECK
        order_date DATE DEFAULT CURRENT_DATE,  -- Added DEFAULT
        UNIQUE(customer_id, order_date)  -- Added UNIQUE constraint
    );
    
    -- Test: Run schema diff
    FOR v_diff_result IN 
        SELECT * FROM pggit.diff_schemas('test_diff_source', 'test_diff_target')
    LOOP
        IF v_diff_result.object_name = 'orders' 
           AND v_diff_result.change_type LIKE '%CONSTRAINT%' THEN
            v_constraint_changes := v_constraint_changes + 1;
        END IF;
    END LOOP;
    
    -- Assert
    IF v_constraint_changes = 0 THEN
        RAISE EXCEPTION 'Test 4 FAILED: Did not detect constraint changes';
    END IF;
    
    RAISE NOTICE 'Test 4 PASSED: Constraint changes detected (% changes)', v_constraint_changes;
END $$;

-- ============================================
-- DATA DIFF TESTS
-- ============================================

\echo 'Testing data diff functionality...'

-- Test 5: Detect row insertions
DO $$
DECLARE
    v_diff_result RECORD;
    v_inserts_found INTEGER := 0;
BEGIN
    -- Setup: Create identical tables
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
    
    -- Insert data in source
    INSERT INTO test_diff_source.customers VALUES 
        (1, 'Alice', 'alice@example.com'),
        (2, 'Bob', 'bob@example.com');
    
    -- Insert additional data in target
    INSERT INTO test_diff_target.customers VALUES 
        (1, 'Alice', 'alice@example.com'),
        (2, 'Bob', 'bob@example.com'),
        (3, 'Charlie', 'charlie@example.com'),
        (4, 'David', 'david@example.com');
    
    -- Test: Run data diff
    FOR v_diff_result IN 
        SELECT * FROM pggit.diff_table_data('test_diff_source', 'test_diff_target', 'customers')
    LOOP
        IF v_diff_result.change_type = 'INSERT' THEN
            v_inserts_found := v_inserts_found + 1;
        END IF;
    END LOOP;
    
    -- Assert: Should find 2 inserts
    IF v_inserts_found != 2 THEN
        RAISE EXCEPTION 'Test 5 FAILED: Expected 2 inserts, found %', v_inserts_found;
    END IF;
    
    RAISE NOTICE 'Test 5 PASSED: Row insertions detected (% rows)', v_inserts_found;
END $$;

-- Test 6: Detect row deletions
DO $$
DECLARE
    v_diff_result RECORD;
    v_deletes_found INTEGER := 0;
BEGIN
    -- Setup: Create identical tables
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
    
    -- Insert more data in source
    INSERT INTO test_diff_source.inventory VALUES 
        (1, 'Widget', 100),
        (2, 'Gadget', 50),
        (3, 'Doohickey', 75),
        (4, 'Thingamajig', 25);
    
    -- Insert less data in target (simulating deletions)
    INSERT INTO test_diff_target.inventory VALUES 
        (1, 'Widget', 100),
        (3, 'Doohickey', 75);
    
    -- Test: Run data diff
    FOR v_diff_result IN 
        SELECT * FROM pggit.diff_table_data('test_diff_source', 'test_diff_target', 'inventory')
    LOOP
        IF v_diff_result.change_type = 'DELETE' THEN
            v_deletes_found := v_deletes_found + 1;
        END IF;
    END LOOP;
    
    -- Assert: Should find 2 deletions
    IF v_deletes_found != 2 THEN
        RAISE EXCEPTION 'Test 6 FAILED: Expected 2 deletions, found %', v_deletes_found;
    END IF;
    
    RAISE NOTICE 'Test 6 PASSED: Row deletions detected (% rows)', v_deletes_found;
END $$;

-- Test 7: Detect row updates
DO $$
DECLARE
    v_diff_result RECORD;
    v_updates_found INTEGER := 0;
BEGIN
    -- Setup: Create identical tables
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
    
    -- Insert data in source
    INSERT INTO test_diff_source.employees VALUES 
        (1, 'John Doe', 'Engineering', 75000),
        (2, 'Jane Smith', 'Marketing', 65000),
        (3, 'Bob Johnson', 'Sales', 60000);
    
    -- Insert modified data in target
    INSERT INTO test_diff_target.employees VALUES 
        (1, 'John Doe', 'Engineering', 80000),  -- Salary changed
        (2, 'Jane Smith', 'HR', 65000),         -- Department changed
        (3, 'Robert Johnson', 'Sales', 62000);  -- Name and salary changed
    
    -- Test: Run data diff
    FOR v_diff_result IN 
        SELECT * FROM pggit.diff_table_data('test_diff_source', 'test_diff_target', 'employees')
    LOOP
        IF v_diff_result.change_type = 'UPDATE' THEN
            v_updates_found := v_updates_found + 1;
        END IF;
    END LOOP;
    
    -- Assert: Should find 3 updates
    IF v_updates_found != 3 THEN
        RAISE EXCEPTION 'Test 7 FAILED: Expected 3 updates, found %', v_updates_found;
    END IF;
    
    RAISE NOTICE 'Test 7 PASSED: Row updates detected (% rows)', v_updates_found;
END $$;

-- ============================================
-- INTEGRATED DIFF TESTS (Using pggit.diff)
-- ============================================

\echo 'Testing integrated diff functionality...'

-- Test 8: Test pggit.diff() with schema changes
DO $$
DECLARE
    v_diff_count INTEGER;
    v_commit_id UUID;
BEGIN
    -- Setup: Initialize pggit and create initial commit
    PERFORM pggit.init();
    PERFORM pggit.commit('Initial commit');
    
    -- Make schema changes
    CREATE TABLE test_table_1 (id INTEGER PRIMARY KEY, name TEXT);
    CREATE TABLE test_table_2 (id INTEGER PRIMARY KEY, value INTEGER);
    
    -- Test: Run diff against HEAD
    SELECT COUNT(*) INTO v_diff_count
    FROM pggit.diff();
    
    -- Assert: Should detect the new tables
    IF v_diff_count < 2 THEN
        RAISE EXCEPTION 'Test 8 FAILED: Expected at least 2 changes, found %', v_diff_count;
    END IF;
    
    RAISE NOTICE 'Test 8 PASSED: pggit.diff() detected % schema changes', v_diff_count;
END $$;

-- Test 9: Test pggit.diff() between commits
DO $$
DECLARE
    v_commit1 UUID;
    v_commit2 UUID;
    v_diff_count INTEGER;
BEGIN
    -- Setup: Create first commit
    CREATE TABLE test_diff_v1 (id INTEGER PRIMARY KEY);
    SELECT pggit.commit('First version') INTO v_commit1;
    
    -- Make changes and create second commit
    ALTER TABLE test_diff_v1 ADD COLUMN name TEXT;
    CREATE INDEX idx_test_diff_v1_name ON test_diff_v1(name);
    SELECT pggit.commit('Added name column and index') INTO v_commit2;
    
    -- Test: Run diff between commits
    SELECT COUNT(*) INTO v_diff_count
    FROM pggit.diff(v_commit1, v_commit2);
    
    -- Assert: Should detect the changes
    IF v_diff_count = 0 THEN
        RAISE EXCEPTION 'Test 9 FAILED: No differences detected between commits';
    END IF;
    
    RAISE NOTICE 'Test 9 PASSED: Detected % differences between commits', v_diff_count;
END $$;

-- Test 10: Test diff output format
DO $$
DECLARE
    v_diff_record RECORD;
    v_has_proper_format BOOLEAN := TRUE;
BEGIN
    -- Setup: Make a change
    CREATE TABLE test_diff_format (id INTEGER);
    
    -- Test: Check diff output format
    FOR v_diff_record IN SELECT * FROM pggit.diff() LOOP
        -- Verify required fields exist and are not null
        IF v_diff_record.object_name IS NULL OR 
           v_diff_record.change_type IS NULL OR
           v_diff_record.diff_text IS NULL THEN
            v_has_proper_format := FALSE;
        END IF;
        
        -- Verify change_type is one of expected values
        IF v_diff_record.change_type NOT IN ('ADD', 'DELETE', 'MODIFY', 'INSERT', 'UPDATE') THEN
            v_has_proper_format := FALSE;
        END IF;
    END LOOP;
    
    -- Assert
    IF NOT v_has_proper_format THEN
        RAISE EXCEPTION 'Test 10 FAILED: Diff output format is incorrect';
    END IF;
    
    RAISE NOTICE 'Test 10 PASSED: Diff output format is correct';
END $$;

-- Cleanup
ROLLBACK;

\echo 'All diff functionality tests completed!'
\echo 'Note: These tests are expected to fail initially (TDD approach)'
\echo 'Implementation needed for:'
\echo '  - pggit.diff_schemas()'
\echo '  - pggit.diff_table_data()'
\echo '  - Enhanced pggit.diff() with proper schema/data comparison'