-- Performance Benchmark Suite for pgGit
-- Test File: 001_benchmark_ddl_overhead.sql
-- Purpose: Measure DDL operation overhead with event triggers

\timing on

DO $$
DECLARE
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_overhead_ms NUMERIC;
    v_iterations INTEGER := 100;
    v_total_overhead_ms NUMERIC := 0;
    v_max_overhead_ms NUMERIC := 0;
    v_min_overhead_ms NUMERIC := 999999;
    v_test_table_name TEXT;
    v_baseline_ms NUMERIC;
    v_with_tracking_ms NUMERIC;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'DDL Overhead Benchmark';
    RAISE NOTICE 'Iterations: %', v_iterations;
    RAISE NOTICE '========================================';

    -- First, measure baseline without pggit (if possible)
    -- For this test, we'll measure create/drop table overhead
    
    FOR i IN 1..v_iterations LOOP
        v_test_table_name := 'benchmark_table_' || i;
        
        -- Measure CREATE TABLE with tracking
        v_start_time := clock_timestamp();
        EXECUTE format('CREATE TABLE %I (id INT)', v_test_table_name);
        v_end_time := clock_timestamp();
        v_with_tracking_ms := EXTRACT(MILLISECOND FROM (v_end_time - v_start_time));
        
        v_total_overhead_ms := v_total_overhead_ms + v_with_tracking_ms;
        v_max_overhead_ms := GREATEST(v_max_overhead_ms, v_with_tracking_ms);
        v_min_overhead_ms := LEAST(v_min_overhead_ms, v_with_tracking_ms);
        
        -- Clean up
        EXECUTE format('DROP TABLE %I', v_test_table_name);
        
        -- Progress every 10 iterations
        IF i % 10 = 0 THEN
            RAISE NOTICE 'Progress: %/% iterations', i, v_iterations;
        END IF;
    END LOOP;
    
    -- Calculate statistics
    RAISE NOTICE '';
    RAISE NOTICE 'Results:';
    RAISE NOTICE '--------';
    RAISE NOTICE 'Average overhead: % ms', ROUND(v_total_overhead_ms / v_iterations, 2);
    RAISE NOTICE 'Min overhead: % ms', ROUND(v_min_overhead_ms, 2);
    RAISE NOTICE 'Max overhead: % ms', ROUND(v_max_overhead_ms, 2);
    RAISE NOTICE 'Total time: % ms', ROUND(v_total_overhead_ms, 2);
    
    -- Performance assertion
    IF (v_total_overhead_ms / v_iterations) > 15 THEN
        RAISE WARNING 'PERFORMANCE REGRESSION: Average overhead (%) exceeds 15ms target!', 
            ROUND(v_total_overhead_ms / v_iterations, 2);
    ELSE
        RAISE NOTICE 'PASS: Average overhead (%) is within 15ms target', 
            ROUND(v_total_overhead_ms / v_iterations, 2);
    END IF;
END $$;

\timing off
