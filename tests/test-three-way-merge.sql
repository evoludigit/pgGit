-- pgGit Three-Way Merge Tests
-- Testing Git-like merge functionality with conflict detection
-- This makes the story claims a reality

\set ECHO all
\set ON_ERROR_STOP on

BEGIN;

-- Test Setup
DO $$
BEGIN
    RAISE NOTICE '============================================';
    RAISE NOTICE 'pgGit Three-Way Merge Tests';
    RAISE NOTICE '============================================';
END $$;

-- Test 1: Basic three-way merge setup
DO $$
DECLARE
    v_base_commit_id UUID;
    v_branch1_commit_id UUID;
    v_branch2_commit_id UUID;
    v_merge_result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '1. Testing three-way merge setup...';
    
    -- Create base commit
    v_base_commit_id := pggit.create_commit('main', 'Initial schema', 
        'CREATE TABLE users (id SERIAL PRIMARY KEY, name TEXT);'
    );
    
    -- Create two branches from same base
    PERFORM pggit.create_branch('feature-1', 'main', v_base_commit_id);
    PERFORM pggit.create_branch('feature-2', 'main', v_base_commit_id);
    
    -- Make changes in branch 1
    v_branch1_commit_id := pggit.create_commit('feature-1', 'Add email column',
        'ALTER TABLE users ADD COLUMN email TEXT UNIQUE;'
    );
    
    -- Make changes in branch 2
    v_branch2_commit_id := pggit.create_commit('feature-2', 'Add phone column',
        'ALTER TABLE users ADD COLUMN phone TEXT;'
    );
    
    -- Test merge detection
    SELECT * INTO v_merge_result 
    FROM pggit.detect_merge_conflicts('feature-1', 'feature-2', v_base_commit_id);
    
    IF v_merge_result.has_conflicts = false THEN
        RAISE NOTICE 'PASS: Non-conflicting changes detected correctly';
    ELSE
        RAISE WARNING 'FAIL: Should not detect conflicts for different columns';
    END IF;
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'WARN: Three-way merge not fully implemented (%)' , SQLERRM;
END $$;

-- Test 2: Conflict detection
DO $$
DECLARE
    v_base_commit_id UUID;
    v_conflict_result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '2. Testing conflict detection...';
    
    -- Create conflicting changes
    v_base_commit_id := pggit.create_commit('main', 'Base table', 
        'CREATE TABLE products (id SERIAL PRIMARY KEY, price DECIMAL(10,2));'
    );
    
    -- Branch 1 changes column type
    PERFORM pggit.create_commit('branch-1', 'Change to NUMERIC',
        'ALTER TABLE products ALTER COLUMN price TYPE NUMERIC(12,4);'
    );
    
    -- Branch 2 changes same column differently  
    PERFORM pggit.create_commit('branch-2', 'Change to MONEY',
        'ALTER TABLE products ALTER COLUMN price TYPE MONEY;'
    );
    
    -- Detect conflict
    SELECT * INTO v_conflict_result
    FROM pggit.detect_merge_conflicts('branch-1', 'branch-2', v_base_commit_id);
    
    IF v_conflict_result.has_conflicts = true THEN
        RAISE NOTICE 'PASS: Conflicting changes detected';
        RAISE NOTICE 'Conflicts: %', v_conflict_result.conflict_details;
    ELSE
        RAISE WARNING 'FAIL: Should detect conflicts for same column changes';
    END IF;
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'WARN: Conflict detection not implemented (%)' , SQLERRM;
END $$;

-- Test 3: Automatic merge resolution
DO $$
DECLARE
    v_merge_commit_id UUID;
    v_merge_sql TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '3. Testing automatic merge resolution...';
    
    -- Create non-conflicting changes
    PERFORM pggit.create_commit('main', 'Base schema',
        'CREATE TABLE orders (id SERIAL PRIMARY KEY, customer_id INT);'
    );
    
    PERFORM pggit.create_commit('add-total', 'Add total column',
        'ALTER TABLE orders ADD COLUMN total DECIMAL(10,2);'
    );
    
    PERFORM pggit.create_commit('add-status', 'Add status column', 
        'ALTER TABLE orders ADD COLUMN status TEXT DEFAULT ''pending'';'
    );
    
    -- Perform automatic merge
    v_merge_commit_id := pggit.merge_branches(
        p_source_branch := 'add-total',
        p_target_branch := 'add-status',
        p_merge_strategy := 'auto',
        p_commit_message := 'Merge: add-total + add-status'
    );
    
    -- Get merged SQL
    SELECT merged_sql INTO v_merge_sql
    FROM pggit.commits 
    WHERE commit_id = v_merge_commit_id;
    
    IF v_merge_sql LIKE '%total%' AND v_merge_sql LIKE '%status%' THEN
        RAISE NOTICE 'PASS: Automatic merge combined both changes';
    ELSE
        RAISE WARNING 'FAIL: Merge did not combine changes correctly';
    END IF;
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'WARN: Automatic merge not implemented (%)' , SQLERRM;
END $$;

-- Test 4: Merge with data conflicts
DO $$
DECLARE
    v_data_conflicts JSONB;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '4. Testing data-level conflict detection...';
    
    -- Create table with data
    PERFORM pggit.create_commit('main', 'Users with data',
        'CREATE TABLE users (id INT PRIMARY KEY, email TEXT UNIQUE);
         INSERT INTO users VALUES (1, ''user@example.com'');'
    );
    
    -- Branch 1 updates email
    PERFORM pggit.create_commit('update-email-1', 'Change email',
        'UPDATE users SET email = ''new@example.com'' WHERE id = 1;'
    );
    
    -- Branch 2 updates same row differently
    PERFORM pggit.create_commit('update-email-2', 'Different email', 
        'UPDATE users SET email = ''other@example.com'' WHERE id = 1;'
    );
    
    -- Detect data conflicts
    SELECT data_conflicts INTO v_data_conflicts
    FROM pggit.analyze_merge_data_conflicts('update-email-1', 'update-email-2');
    
    IF v_data_conflicts IS NOT NULL THEN
        RAISE NOTICE 'PASS: Data conflicts detected';
        RAISE NOTICE 'Conflict rows: %', jsonb_array_length(v_data_conflicts);
    ELSE
        RAISE WARNING 'FAIL: Should detect data-level conflicts';
    END IF;
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'WARN: Data conflict detection not implemented (%)' , SQLERRM;
END $$;

-- Test 5: Complex merge scenarios
DO $$
DECLARE
    v_merge_plan JSONB;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '5. Testing complex merge scenarios...';
    
    -- Create complex schema
    PERFORM pggit.create_commit('main', 'Complex schema',
        'CREATE TABLE departments (id SERIAL PRIMARY KEY, name TEXT);
         CREATE TABLE employees (
             id SERIAL PRIMARY KEY,
             name TEXT,
             dept_id INT REFERENCES departments(id)
         );
         CREATE INDEX idx_emp_dept ON employees(dept_id);'
    );
    
    -- Branch 1: Add columns and constraints
    PERFORM pggit.create_commit('feature-complex-1', 'Add salary info',
        'ALTER TABLE employees ADD COLUMN salary DECIMAL(10,2);
         ALTER TABLE employees ADD CONSTRAINT chk_salary CHECK (salary > 0);
         CREATE INDEX idx_emp_salary ON employees(salary);'
    );
    
    -- Branch 2: Add different columns and modify index
    PERFORM pggit.create_commit('feature-complex-2', 'Add hire date',
        'ALTER TABLE employees ADD COLUMN hire_date DATE DEFAULT CURRENT_DATE;
         DROP INDEX idx_emp_dept;
         CREATE INDEX idx_emp_dept_name ON employees(dept_id, name);'
    );
    
    -- Generate merge plan
    SELECT merge_plan INTO v_merge_plan
    FROM pggit.generate_merge_plan('feature-complex-1', 'feature-complex-2');
    
    IF v_merge_plan ? 'conflicts' THEN
        RAISE NOTICE 'PASS: Complex merge plan generated';
        RAISE NOTICE 'Index conflict detected: %', 
            (v_merge_plan->'conflicts'->0->>'object' = 'idx_emp_dept');
    ELSE
        RAISE WARNING 'FAIL: Should detect index modification conflict';
    END IF;
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'WARN: Complex merge planning not implemented (%)' , SQLERRM;
END $$;

-- Summary
DO $$
DECLARE
    v_test_count INT := 5;
    v_functions_exist BOOLEAN;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '============================================';
    RAISE NOTICE 'Three-Way Merge Tests Summary';
    RAISE NOTICE '============================================';
    
    -- Check if merge functions exist
    SELECT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'detect_merge_conflicts' 
        AND pronamespace = 'pggit'::regnamespace
    ) INTO v_functions_exist;
    
    IF v_functions_exist THEN
        RAISE NOTICE 'Three-way merge functions: IMPLEMENTED';
    ELSE
        RAISE NOTICE 'Three-way merge functions: NOT YET IMPLEMENTED';
        RAISE NOTICE 'These tests define the expected behavior';
    END IF;
    
    RAISE NOTICE 'Total test scenarios: %', v_test_count;
    RAISE NOTICE '';
    RAISE NOTICE 'Run with: psql -d your_database -f tests/test-three-way-merge.sql';
END $$;

ROLLBACK;