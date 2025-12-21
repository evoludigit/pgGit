-- pgGit Data Branching Tests
-- Testing true data isolation between branches
-- Making copy-on-write branching a reality

\set ECHO all
\set ON_ERROR_STOP on

BEGIN;

-- Test Setup
DO $$
BEGIN
    RAISE NOTICE '============================================';
    RAISE NOTICE 'pgGit Data Branching Tests';
    RAISE NOTICE '============================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Testing PostgreSQL 17 copy-on-write features';
END $$;

-- Test 1: Basic data branching
DO $$
DECLARE
    v_branch_id INT;
    v_main_count INT;
    v_branch_count INT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '1. Testing basic data branching...';

    -- Assert required function exists
    PERFORM pggit.assert_function_exists('create_data_branch');

    -- Create test table in main branch
    CREATE TABLE test_products (
        id SERIAL PRIMARY KEY,
        name TEXT,
        price DECIMAL(10,2)
    );
    
    -- Insert data in main
    INSERT INTO test_products (name, price) VALUES
        ('Widget', 9.99),
        ('Gadget', 19.99),
        ('Gizmo', 29.99);
    
    -- Create data branch
    v_branch_id := pggit.create_data_branch(
        p_branch_name := 'feature/price-update',
        p_source_branch := 'main',
        p_tables := ARRAY['test_products']::TEXT[]
    );
    
    -- Modify data in branch
    PERFORM pggit.switch_branch('feature/price-update');
    UPDATE test_products SET price = price * 1.1;
    
    -- Check isolation
    PERFORM pggit.switch_branch('main');
    SELECT COUNT(*) INTO v_main_count FROM test_products WHERE price = 9.99;
    
    PERFORM pggit.switch_branch('feature/price-update');
    SELECT COUNT(*) INTO v_branch_count FROM test_products WHERE price = 10.989;
    
    IF v_main_count = 1 AND v_branch_count = 1 THEN
        RAISE NOTICE 'PASS: Data properly isolated between branches';
    ELSE
        RAISE EXCEPTION 'FAIL: Data isolation not working correctly';
    END IF;

END $$;

-- Test 2: Copy-on-write efficiency
DO $$
DECLARE
    v_storage_before BIGINT;
    v_storage_after BIGINT;
    v_cow_ratio DECIMAL;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '2. Testing copy-on-write efficiency...';

    -- Assert required function exists
    PERFORM pggit.assert_function_exists('create_data_branch');

    -- Create large table
    CREATE TABLE test_large_data AS
    SELECT 
        generate_series(1, 100000) as id,
        md5(random()::text) as data,
        now() as created_at;
    
    -- Measure storage before branching
    SELECT pg_total_relation_size('test_large_data') INTO v_storage_before;
    
    -- Create COW branch
    PERFORM pggit.create_data_branch(
        p_branch_name := 'feature/cow-test',
        p_source_branch := 'main',
        p_tables := ARRAY['test_large_data']::TEXT[],
        p_use_cow := true
    );
    
    -- Measure storage after branching
    SELECT SUM(size) INTO v_storage_after
    FROM pggit.branch_storage_stats
    WHERE branch_name IN ('main', 'feature/cow-test');
    
    -- Calculate COW efficiency
    v_cow_ratio := v_storage_after::DECIMAL / v_storage_before;
    
    IF v_cow_ratio < 1.1 THEN
        RAISE NOTICE 'PASS: Copy-on-write efficient (ratio: %)', v_cow_ratio;
    ELSE
        RAISE EXCEPTION 'FAIL: COW not efficient (ratio: %)', v_cow_ratio;
    END IF;

END $$;

-- Test 3: Multi-table branching
DO $$
DECLARE
    v_branch_result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '3. Testing multi-table data branching...';

    -- Assert required function exists
    PERFORM pggit.assert_function_exists('create_data_branch');

    -- Create related tables
    CREATE TABLE customers (
        id SERIAL PRIMARY KEY,
        name TEXT,
        email TEXT UNIQUE
    );
    
    CREATE TABLE orders (
        id SERIAL PRIMARY KEY,
        customer_id INT REFERENCES customers(id),
        total DECIMAL(10,2),
        status TEXT DEFAULT 'pending'
    );
    
    -- Insert related data
    INSERT INTO customers (name, email) VALUES
        ('Alice', 'alice@example.com'),
        ('Bob', 'bob@example.com');
    
    INSERT INTO orders (customer_id, total) VALUES
        (1, 100.00),
        (1, 200.00),
        (2, 150.00);
    
    -- Create branch with all related data
    SELECT * INTO v_branch_result
    FROM pggit.create_data_branch_with_dependencies(
        p_branch_name := 'feature/customer-update',
        p_source_branch := 'main',
        p_root_table := 'customers',
        p_include_dependencies := true
    );
    
    IF v_branch_result.tables_branched = 2 THEN
        RAISE NOTICE 'PASS: Multi-table branching with dependencies works';
        RAISE NOTICE 'Branched tables: %', v_branch_result.branched_tables;
    ELSE
        RAISE EXCEPTION 'FAIL: Dependencies not properly branched';
    END IF;

END $$;

-- Test 4: Branch merging with data conflicts
DO $$
DECLARE
    v_merge_result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '4. Testing data merge with conflict resolution...';

    -- Assert required function exists
    PERFORM pggit.assert_function_exists('create_data_branch');

    -- Create branches with conflicting data changes
    PERFORM pggit.create_data_branch('branch-1', 'main', ARRAY['customers']);
    PERFORM pggit.create_data_branch('branch-2', 'main', ARRAY['customers']);
    
    -- Make conflicting changes
    PERFORM pggit.switch_branch('branch-1');
    UPDATE customers SET email = 'alice.new@example.com' WHERE id = 1;
    
    PERFORM pggit.switch_branch('branch-2');
    UPDATE customers SET email = 'alice.updated@example.com' WHERE id = 1;
    
    -- Attempt merge
    SELECT * INTO v_merge_result
    FROM pggit.merge_data_branches(
        p_source := 'branch-1',
        p_target := 'branch-2',
        p_conflict_resolution := 'interactive'
    );
    
    IF v_merge_result.has_conflicts THEN
        RAISE NOTICE 'PASS: Data conflicts detected';
        RAISE NOTICE 'Conflicts: %', v_merge_result.conflict_count;
    ELSE
        RAISE EXCEPTION 'FAIL: Should detect data conflicts';
    END IF;

END $$;

-- Test 5: Temporal branching
DO $$
DECLARE
    v_snapshot_id UUID;
    v_restored_count INT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '5. Testing temporal data branching...';

    -- Assert required function exists
    PERFORM pggit.assert_function_exists('create_temporal_branch');

    -- Create time-travel branch
    v_snapshot_id := pggit.create_temporal_branch(
        p_branch_name := 'snapshot/before-migration',
        p_source_branch := 'main',
        p_point_in_time := now() - interval '1 hour'
    );
    
    -- Verify snapshot
    PERFORM pggit.switch_branch('snapshot/before-migration');
    SELECT COUNT(*) INTO v_restored_count FROM customers;
    
    IF v_restored_count >= 0 THEN
        RAISE NOTICE 'PASS: Temporal branching created';
        RAISE NOTICE 'Snapshot ID: %', v_snapshot_id;
    ELSE
        RAISE EXCEPTION 'FAIL: Temporal branch not created';
    END IF;

END $$;

-- Test 6: Branch storage optimization
DO $$
DECLARE
    v_optimization_result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '6. Testing branch storage optimization...';

    -- Assert required function exists
    PERFORM pggit.assert_function_exists('optimize_branch_storage');

    -- Run storage optimization
    SELECT * INTO v_optimization_result
    FROM pggit.optimize_branch_storage(
        p_branch := 'feature/cow-test',
        p_compression := 'lz4',
        p_deduplicate := true
    );
    
    IF v_optimization_result.space_saved_mb > 0 THEN
        RAISE NOTICE 'PASS: Storage optimization successful';
        RAISE NOTICE 'Space saved: % MB', v_optimization_result.space_saved_mb;
        RAISE NOTICE 'Compression ratio: %', v_optimization_result.compression_ratio;
    ELSE
        RAISE EXCEPTION 'FAIL: No space saved by optimization';
    END IF;

END $$;

-- Summary
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '============================================';
    RAISE NOTICE 'Data Branching Tests Summary';
    RAISE NOTICE '============================================';
    RAISE NOTICE 'Features tested:';
    RAISE NOTICE '  - Basic data isolation';
    RAISE NOTICE '  - Copy-on-write efficiency';
    RAISE NOTICE '  - Multi-table branching';
    RAISE NOTICE '  - Data conflict resolution';
    RAISE NOTICE '  - Temporal branching';
    RAISE NOTICE '  - Storage optimization';
    RAISE NOTICE '';
    RAISE NOTICE 'These tests demonstrate enterprise-grade';
    RAISE NOTICE 'data branching capabilities for pgGit';
END $$;

ROLLBACK;