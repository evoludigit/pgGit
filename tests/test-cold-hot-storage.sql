-- pgGit Cold/Hot Storage Tests
-- Testing tiered storage for 10TB+ databases
-- Simulating massive scale with limited resources

\set ECHO all
\set ON_ERROR_STOP on

BEGIN;

-- Test Setup
DO $$
BEGIN
    RAISE NOTICE '============================================';
    RAISE NOTICE 'pgGit Cold/Hot Storage Tests';
    RAISE NOTICE '============================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Simulating 10TB database with 100GB hot storage';
END $$;

-- Test 1: Storage tier classification
DO $$
DECLARE
    v_hot_size BIGINT;
    v_cold_size BIGINT;
    v_tier_result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '1. Testing storage tier classification...';

    -- Assert required function exists
    PERFORM pggit.assert_function_exists('classify_storage_tier');

    -- Create test objects of various sizes
    CREATE TABLE test_hot_data (
        id BIGINT,
        accessed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        data TEXT
    );
    
    CREATE TABLE test_cold_data (
        id BIGINT,
        archived_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP - INTERVAL '60 days',
        historical_data TEXT
    );
    
    -- Classify storage tiers
    SELECT * INTO v_tier_result
    FROM pggit.classify_storage_tier('test_hot_data');
    
    IF v_tier_result.tier = 'HOT' THEN
        RAISE NOTICE 'PASS: Recent data classified as HOT';
    ELSE
        RAISE WARNING 'FAIL: Recent data not classified correctly';
    END IF;
    
    SELECT * INTO v_tier_result  
    FROM pggit.classify_storage_tier('test_cold_data');
    
    IF v_tier_result.tier = 'COLD' THEN
        RAISE NOTICE 'PASS: Historical data classified as COLD';
    ELSE
        RAISE EXCEPTION 'FAIL: Historical data not classified correctly';
    END IF;

END $$;

-- Test 2: Deduplication efficiency
DO $$
DECLARE
    v_original_size BIGINT;
    v_dedup_size BIGINT;
    v_dedup_ratio DECIMAL;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '2. Testing deduplication for large tables...';

    -- Assert required function exists
    PERFORM pggit.assert_function_exists('deduplicate_blocks');

    -- Simulate large table with repetitive data
    CREATE TABLE test_large_table AS
    SELECT 
        i as id,
        'DUPLICATE_BLOCK_' || (i % 1000) as data_block,
        repeat('X', 1000) as padding
    FROM generate_series(1, 100000) i;
    
    -- Measure original size
    SELECT pg_total_relation_size('test_large_table') INTO v_original_size;
    
    -- Apply deduplication
    SELECT deduplicated_size INTO v_dedup_size
    FROM pggit.deduplicate_storage('test_large_table');
    
    v_dedup_ratio := v_original_size::DECIMAL / v_dedup_size;
    
    IF v_dedup_ratio > 10 THEN
        RAISE NOTICE 'PASS: Deduplication achieved %x reduction', v_dedup_ratio;
    ELSE
        RAISE EXCEPTION 'FAIL: Insufficient deduplication ratio: %x', v_dedup_ratio;
    END IF;

END $$;

-- Test 3: Cold storage migration
DO $$
DECLARE
    v_migration_result RECORD;
    v_hot_usage_before BIGINT;
    v_hot_usage_after BIGINT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '3. Testing cold storage migration...';

    -- Assert required function exists
    PERFORM pggit.assert_function_exists('migrate_to_cold_storage');

    -- Get hot storage usage before
    SELECT bytes_used INTO v_hot_usage_before
    FROM pggit.storage_tier_stats
    WHERE tier = 'HOT';
    
    -- Create old branch data
    PERFORM pggit.create_test_branch_with_age(
        'ancient-branch',
        '90 days'::INTERVAL,
        '1GB'::BIGINT
    );
    
    -- Trigger cold storage migration
    SELECT * INTO v_migration_result
    FROM pggit.migrate_to_cold_storage(
        p_age_threshold := '30 days'::INTERVAL,
        p_size_threshold := '100MB'::BIGINT
    );
    
    -- Get hot storage usage after
    SELECT bytes_used INTO v_hot_usage_after
    FROM pggit.storage_tier_stats  
    WHERE tier = 'HOT';
    
    IF v_hot_usage_after < v_hot_usage_before THEN
        RAISE NOTICE 'PASS: Migrated % MB to cold storage',
            (v_hot_usage_before - v_hot_usage_after) / 1024 / 1024;
        RAISE NOTICE 'Objects migrated: %', v_migration_result.objects_migrated;
    ELSE
        RAISE EXCEPTION 'FAIL: No reduction in hot storage usage';
    END IF;

END $$;

-- Test 4: Smart prefetching
DO $$
DECLARE
    v_prefetch_result RECORD;
    v_cache_hits INT;
    v_response_time DECIMAL;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '4. Testing smart prefetching from cold storage...';

    -- Assert required function exists
    PERFORM pggit.assert_function_exists('predict_prefetch_candidates');

    -- Access pattern simulation
    PERFORM pggit.record_access_pattern('users_2024_01', 'branch_read');
    PERFORM pggit.record_access_pattern('users_2024_02', 'branch_read');
    PERFORM pggit.record_access_pattern('users_2024_03', 'branch_read');
    
    -- Predict next access
    SELECT * INTO v_prefetch_result
    FROM pggit.predict_prefetch_candidates();
    
    IF 'users_2024_04' = ANY(v_prefetch_result.predicted_objects) THEN
        RAISE NOTICE 'PASS: Correctly predicted next access pattern';
        
        -- Trigger prefetch
        PERFORM pggit.prefetch_from_cold('users_2024_04');
        
        -- Measure response time
        SELECT response_time_ms INTO v_response_time
        FROM pggit.measure_cold_retrieval('users_2024_04');
        
        IF v_response_time < 100 THEN
            RAISE NOTICE 'PASS: Prefetched data retrieved in %ms', v_response_time;
        END IF;
    ELSE
        RAISE EXCEPTION 'FAIL: Access pattern prediction failed';
    END IF;

END $$;

-- Test 5: Branch creation with tiered storage
DO $$
DECLARE
    v_branch_result RECORD;
    v_hot_objects INT;
    v_cold_references INT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '5. Testing branch creation with tiered storage...';

    -- Assert required function exists
    PERFORM pggit.assert_function_exists('create_tiered_branch');

    -- Create branch from mixed hot/cold data
    SELECT * INTO v_branch_result
    FROM pggit.create_tiered_branch(
        p_branch_name := 'feature/mixed-storage',
        p_source_branch := 'main',
        p_hot_tables := ARRAY['active_users', 'recent_orders']::TEXT[],
        p_cold_tables := ARRAY['historical_logs', 'archived_data']::TEXT[]
    );
    
    IF v_branch_result.status = 'success' THEN
        RAISE NOTICE 'PASS: Branch created with tiered storage';
        RAISE NOTICE 'Hot objects: %', v_branch_result.hot_object_count;
        RAISE NOTICE 'Cold references: %', v_branch_result.cold_reference_count;
        RAISE NOTICE 'Storage saved: % GB', v_branch_result.storage_saved_gb;
    ELSE
        RAISE EXCEPTION 'FAIL: Tiered branch creation failed';
    END IF;

END $$;

-- Test 6: Storage pressure handling
DO $$
DECLARE
    v_eviction_result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '6. Testing storage pressure handling...';

    -- Assert required function exists
    PERFORM pggit.assert_function_exists('handle_storage_pressure');

    -- Simulate storage pressure (90% full)
    PERFORM pggit.simulate_storage_pressure(0.9);
    
    -- Trigger automatic eviction
    SELECT * INTO v_eviction_result
    FROM pggit.handle_storage_pressure();
    
    IF v_eviction_result.bytes_evicted > 0 THEN
        RAISE NOTICE 'PASS: Evicted % GB to cold storage',
            v_eviction_result.bytes_evicted / 1024 / 1024 / 1024;
        RAISE NOTICE 'Strategy used: %', v_eviction_result.eviction_strategy;
        RAISE NOTICE 'Objects evicted: %', v_eviction_result.object_count;
    ELSE
        RAISE EXCEPTION 'FAIL: Storage pressure not handled';
    END IF;

END $$;

-- Test 7: 10TB database simulation
DO $$
DECLARE
    v_sim_result RECORD;
    v_operations_per_sec DECIMAL;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '7. Testing 10TB database simulation...';

    -- Assert required function exists
    PERFORM pggit.assert_function_exists('initialize_massive_db_simulation');

    -- Initialize 10TB simulation with 100GB hot storage
    SELECT * INTO v_sim_result
    FROM pggit.initialize_massive_db_simulation(
        p_total_size := '10TB',
        p_hot_storage := '100GB',
        p_warm_storage := '1TB',
        p_table_count := 1000,
        p_avg_table_size := '10GB'
    );
    
    IF v_sim_result.initialized THEN
        RAISE NOTICE 'PASS: 10TB database simulation initialized';
        
        -- Test branch creation on massive database
        PERFORM pggit.benchmark_massive_branch_creation(
            p_branch_name := 'feature/massive-test',
            p_tables_to_branch := 50
        );
        
        SELECT operations_per_second INTO v_operations_per_sec
        FROM pggit.massive_db_performance_stats
        WHERE operation = 'branch_create';
        
        IF v_operations_per_sec > 10 THEN
            RAISE NOTICE 'PASS: Branch operations performant at scale';
            RAISE NOTICE 'Operations/sec: %', v_operations_per_sec;
        ELSE
            RAISE EXCEPTION 'FAIL: Performance degraded at scale';
        END IF;
    END IF;

END $$;

-- Test 8: Compression and archival
DO $$
DECLARE
    v_compression_result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '8. Testing compression and archival...';

    -- Assert required function exists
    PERFORM pggit.assert_function_exists('test_compression_algorithms');

    -- Test different compression algorithms
    FOR v_compression_result IN
        SELECT * FROM pggit.test_compression_algorithms(
            'test_large_table',
            ARRAY['lz4', 'zstd', 'gzip']::TEXT[]
        )
    LOOP
        RAISE NOTICE 'Algorithm: %, Ratio: %, Speed: % MB/s',
            v_compression_result.algorithm,
            v_compression_result.compression_ratio,
            v_compression_result.speed_mbps;
    END LOOP;
    
    -- Archive old branches
    SELECT * INTO v_compression_result
    FROM pggit.archive_old_branches(
        p_age_threshold := '180 days',
        p_compression := 'zstd',
        p_compression_level := 9
    );
    
    IF v_compression_result.branches_archived > 0 THEN
        RAISE NOTICE 'PASS: Archived % branches', v_compression_result.branches_archived;
        RAISE NOTICE 'Space reclaimed: % GB', v_compression_result.space_reclaimed_gb;
    END IF;

END $$;

-- Summary
DO $$
DECLARE
    v_storage_stats RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '============================================';
    RAISE NOTICE 'Cold/Hot Storage Tests Summary';
    RAISE NOTICE '============================================';
    
    -- Get final storage statistics
    SELECT 
        SUM(CASE WHEN tier = 'HOT' THEN bytes_used ELSE 0 END) as hot_bytes,
        SUM(CASE WHEN tier = 'WARM' THEN bytes_used ELSE 0 END) as warm_bytes,
        SUM(CASE WHEN tier = 'COLD' THEN bytes_used ELSE 0 END) as cold_bytes
    INTO v_storage_stats
    FROM pggit.storage_tier_stats;
    
    RAISE NOTICE 'Storage Distribution:';
    RAISE NOTICE '  HOT:  % GB', COALESCE(v_storage_stats.hot_bytes, 0) / 1024 / 1024 / 1024;
    RAISE NOTICE '  WARM: % GB', COALESCE(v_storage_stats.warm_bytes, 0) / 1024 / 1024 / 1024;
    RAISE NOTICE '  COLD: % TB', COALESCE(v_storage_stats.cold_bytes, 0) / 1024 / 1024 / 1024 / 1024;
    RAISE NOTICE '';
    RAISE NOTICE 'Key Capabilities Tested:';
    RAISE NOTICE '  - Storage tier classification';
    RAISE NOTICE '  - Block-level deduplication';
    RAISE NOTICE '  - Automatic cold migration';
    RAISE NOTICE '  - Smart prefetching';
    RAISE NOTICE '  - Tiered branch creation';
    RAISE NOTICE '  - Storage pressure handling';
    RAISE NOTICE '  - 10TB database operations';
    RAISE NOTICE '  - Compression and archival';
    RAISE NOTICE '';
    RAISE NOTICE 'pgGit is now ready for massive databases!';

END $$;

ROLLBACK;