-- Performance Benchmark Suite for pgGit
-- Test File: 003_benchmark_history_queries.sql
-- Purpose: Measure query performance on history table with time-based filtering

\timing on

DO $$
DECLARE
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_duration_ms NUMERIC;
    v_row_count INTEGER;
    v_test_iterations INTEGER := 5;
    v_i INTEGER;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'History Query Performance Benchmark';
    RAISE NOTICE '========================================';

    -- Get history table statistics
    SELECT count(*) INTO v_row_count FROM pggit.history;
    RAISE NOTICE 'History table contains % rows', v_row_count;

    -- Benchmark 1: Query last 30 days
    RAISE NOTICE '';
    RAISE NOTICE 'Test 1: Query last 30 days';
    RAISE NOTICE '---------------------------';
    
    FOR v_i IN 1..v_test_iterations LOOP
        v_start_time := clock_timestamp();
        PERFORM count(*) FROM pggit.history 
        WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '30 days';
        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(MILLISECOND FROM (v_end_time - v_start_time));
        RAISE NOTICE 'Iteration %: % ms', v_i, ROUND(v_duration_ms, 2);
    END LOOP;
    
    RAISE NOTICE 'Target: < 100 ms';

    -- Benchmark 2: Query last 90 days
    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: Query last 90 days';
    RAISE NOTICE '---------------------------';
    
    FOR v_i IN 1..v_test_iterations LOOP
        v_start_time := clock_timestamp();
        PERFORM count(*) FROM pggit.history 
        WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '90 days';
        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(MILLISECOND FROM (v_end_time - v_start_time));
        RAISE NOTICE 'Iteration %: % ms', v_i, ROUND(v_duration_ms, 2);
    END LOOP;
    
    RAISE NOTICE 'Target: < 250 ms';

    -- Benchmark 3: Query with object type filter
    RAISE NOTICE '';
    RAISE NOTICE 'Test 3: Query by object type (TABLE)';
    RAISE NOTICE '-------------------------------------';
    
    FOR v_i IN 1..v_test_iterations LOOP
        v_start_time := clock_timestamp();
        PERFORM count(*) FROM pggit.history h
        JOIN pggit.objects o ON h.object_id = o.id
        WHERE o.object_type = 'TABLE'
        AND h.created_at > CURRENT_TIMESTAMP - INTERVAL '30 days';
        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(MILLISECOND FROM (v_end_time - v_start_time));
        RAISE NOTICE 'Iteration %: % ms', v_i, ROUND(v_duration_ms, 2);
    END LOOP;
    
    RAISE NOTICE 'Target: < 150 ms';

    -- Benchmark 4: Query by branch
    RAISE NOTICE '';
    RAISE NOTICE 'Test 4: Query by branch (main)';
    RAISE NOTICE '-------------------------------';
    
    FOR v_i IN 1..v_test_iterations LOOP
        v_start_time := clock_timestamp();
        PERFORM count(*) FROM pggit.history h
        JOIN pggit.objects o ON h.object_id = o.id
        WHERE o.branch_name = 'main'
        AND h.created_at > CURRENT_TIMESTAMP - INTERVAL '30 days';
        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(MILLISECOND FROM (v_end_time - v_start_time));
        RAISE NOTICE 'Iteration %: % ms', v_i, ROUND(v_duration_ms, 2);
    END LOOP;
    
    RAISE NOTICE 'Target: < 150 ms';

    -- Benchmark 5: Full text search on DDL (if applicable)
    RAISE NOTICE '';
    RAISE NOTICE 'Test 5: DDL text search';
    RAISE NOTICE '------------------------';
    
    FOR v_i IN 1..v_test_iterations LOOP
        v_start_time := clock_timestamp();
        PERFORM count(*) FROM pggit.history 
        WHERE ddl_normalized LIKE '%CREATE TABLE%'
        AND created_at > CURRENT_TIMESTAMP - INTERVAL '30 days';
        v_end_time := clock_timestamp();
        v_duration_ms := EXTRACT(MILLISECOND FROM (v_end_time - v_start_time));
        RAISE NOTICE 'Iteration %: % ms', v_i, ROUND(v_duration_ms, 2);
    END LOOP;
    
    RAISE NOTICE 'Target: < 500 ms (text search is inherently slower)';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Benchmark complete';
    RAISE NOTICE '========================================';
END $$;

\timing off
