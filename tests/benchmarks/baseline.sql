-- pgGit Performance Baseline Benchmark
-- Measures current performance metrics for tracking regressions

-- Enable timing
\timing on

-- Create benchmark schema to avoid conflicts
CREATE SCHEMA IF NOT EXISTS benchmark;
SET search_path TO benchmark, public;

-- Benchmark 1: DDL Tracking Overhead
DO $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    total_time INTERVAL;
BEGIN
    RAISE NOTICE '=== Benchmark: DDL Tracking Overhead ===';

    start_time := clock_timestamp();

    -- Create 100 tables to measure tracking overhead
    FOR i IN 1..100 LOOP
        EXECUTE format('CREATE TABLE bench_table_%s (id SERIAL PRIMARY KEY, data TEXT)', i);
    END LOOP;

    end_time := clock_timestamp();
    total_time := end_time - start_time;

    RAISE NOTICE 'Created 100 tables in: %', total_time;

    -- Check how many were tracked
    SELECT COUNT(*) as tracked_objects FROM pggit.objects WHERE schema_name = 'benchmark'
    INTO total_time; -- Reuse variable

    RAISE NOTICE 'Objects tracked: %', total_time;
END $$;

-- Benchmark 2: Version Retrieval Performance
DO $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    total_time INTERVAL;
BEGIN
    RAISE NOTICE '=== Benchmark: Version Retrieval ===';

    start_time := clock_timestamp();

    -- Query versions for all benchmark tables
    FOR i IN 1..100 LOOP
        PERFORM pggit.get_version(format('bench_table_%s', i));
    END LOOP;

    end_time := clock_timestamp();
    total_time := end_time - start_time;

    RAISE NOTICE 'Retrieved 100 versions in: %', total_time;
END $$;

-- Benchmark 3: History Query Performance
DO $$
DECLARE
    history_count INTEGER;
    query_time INTERVAL;
    start_time TIMESTAMP;
BEGIN
    RAISE NOTICE '=== Benchmark: History Query ===';

    start_time := clock_timestamp();

    SELECT COUNT(*) INTO history_count
    FROM pggit.history
    WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour';

    query_time := clock_timestamp() - start_time;

    RAISE NOTICE 'Found % history records in: %', history_count, query_time;
END $$;

-- Benchmark 4: Migration Generation
DO $$
DECLARE
    start_time TIMESTAMP;
    migration_text TEXT;
    gen_time INTERVAL;
BEGIN
    RAISE NOTICE '=== Benchmark: Migration Generation ===';

    start_time := clock_timestamp();

    SELECT pggit.generate_migration('benchmark', 'Performance test') INTO migration_text;

    gen_time := clock_timestamp() - start_time;

    RAISE NOTICE 'Generated migration (%s chars) in: %', length(migration_text), gen_time;
END $$;

-- Report results
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== Performance Baseline Summary ===';
    RAISE NOTICE 'Date: %', CURRENT_TIMESTAMP;
    RAISE NOTICE 'pgGit Version: 0.1.1';
    RAISE NOTICE 'PostgreSQL Version: %', version();
    RAISE NOTICE '';
    RAISE NOTICE 'Run this benchmark periodically to detect performance regressions.';
    RAISE NOTICE 'All times are wall-clock measurements.';
END $$;

-- Cleanup
DROP SCHEMA benchmark CASCADE;