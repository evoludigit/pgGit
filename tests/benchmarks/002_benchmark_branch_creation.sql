-- Performance Benchmark Suite for pgGit
-- Test File: 002_benchmark_branch_creation.sql
-- Purpose: Measure branch creation performance (especially with data copy)

\timing on

DO $$
DECLARE
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_duration_ms NUMERIC;
    v_branch_id INTEGER;
    v_test_table_name TEXT := 'benchmark_products';
    v_row_count INTEGER := 10000;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Branch Creation Benchmark';
    RAISE NOTICE '========================================';

    -- Setup: Create test table with data
    RAISE NOTICE 'Creating test table with % rows...', v_row_count;
    
    EXECUTE format('
        CREATE TABLE IF NOT EXISTS %I (
            id SERIAL PRIMARY KEY,
            name TEXT NOT NULL,
            price DECIMAL(10,2),
            category TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            data TEXT
        )', v_test_table_name);
    
    -- Insert test data
    INSERT INTO benchmark_products (name, price, category, data)
    SELECT 
        'Product ' || i,
        (random() * 1000)::DECIMAL(10,2),
        CASE (i % 5) 
            WHEN 0 THEN 'Electronics'
            WHEN 1 THEN 'Clothing'
            WHEN 2 THEN 'Books'
            WHEN 3 THEN 'Home'
            ELSE 'Sports'
        END,
        repeat('x', 100)  -- 100 bytes of data per row
    FROM generate_series(1, v_row_count) AS i;
    
    RAISE NOTICE 'Inserted % rows', v_row_count;
    
    -- Benchmark 1: Branch creation without data copy
    RAISE NOTICE '';
    RAISE NOTICE 'Test 1: Branch creation WITHOUT data copy';
    RAISE NOTICE '-------------------------------------------';
    
    v_start_time := clock_timestamp();
    SELECT pggit.create_branch('benchmark_branch_no_data', 'main', false) INTO v_branch_id;
    v_end_time := clock_timestamp();
    v_duration_ms := EXTRACT(MILLISECOND FROM (v_end_time - v_start_time));
    
    RAISE NOTICE 'Duration: % ms', ROUND(v_duration_ms, 2);
    RAISE NOTICE 'Target: < 100 ms';
    
    IF v_duration_ms > 100 THEN
        RAISE WARNING 'PERFORMANCE REGRESSION: Branch creation without data (%) exceeds 100ms!', 
            ROUND(v_duration_ms, 2);
    ELSE
        RAISE NOTICE 'PASS: Branch creation is within target';
    END IF;
    
    -- Benchmark 2: Branch creation with data copy
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: Branch creation WITH data copy (%,000 rows)', v_row_count / 1000;
    RAISE NOTICE '-----------------------------------------------------------';
    
    v_start_time := clock_timestamp();
    SELECT pggit.create_branch('benchmark_branch_with_data', 'main', true) INTO v_branch_id;
    v_end_time := clock_timestamp();
    v_duration_ms := EXTRACT(MILLISECOND FROM (v_end_time - v_start_time));
    
    RAISE NOTICE 'Duration: % ms', ROUND(v_duration_ms, 2);
    RAISE NOTICE 'Target: < 500 ms for % rows', v_row_count;
    
    IF v_duration_ms > 500 THEN
        RAISE WARNING 'PERFORMANCE REGRESSION: Branch creation with data (%) exceeds 500ms!', 
            ROUND(v_duration_ms, 2);
    ELSE
        RAISE NOTICE 'PASS: Branch creation with data is within target';
    END IF;
    
    -- Verify data was copied
    SELECT pggit.switch_branch('benchmark_branch_with_data');
    
    RAISE NOTICE '';
    RAISE NOTICE 'Verifying data copy...';
    
    SELECT count(*) INTO v_row_count FROM benchmark_products;
    RAISE NOTICE 'Row count in new branch: %', v_row_count;
    
    IF v_row_count = 10000 THEN
        RAISE NOTICE 'PASS: All rows copied correctly';
    ELSE
        RAISE WARNING 'DATA INCONSISTENCY: Expected 10000 rows, got %', v_row_count;
    END IF;
    
    -- Cleanup
    SELECT pggit.switch_branch('main');
    DELETE FROM pggit.branches WHERE name LIKE 'benchmark_branch_%';
    DROP TABLE IF EXISTS benchmark_products;
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Benchmark complete';
    RAISE NOTICE '========================================';
END $$;

\timing off
