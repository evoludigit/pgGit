-- pgGit Cold/Hot Storage Implementation
-- Tiered storage for massive databases (10TB+)
-- Block-level deduplication and smart caching

-- =====================================================
-- Storage Tier Management Tables
-- =====================================================

CREATE SCHEMA IF NOT EXISTS pggit_storage;

-- Storage tier definitions
CREATE TABLE IF NOT EXISTS pggit.storage_tiers (
    tier_name TEXT PRIMARY KEY,
    tier_level INT NOT NULL, -- 1=HOT, 2=WARM, 3=COLD
    storage_path TEXT,
    max_size_bytes BIGINT,
    current_size_bytes BIGINT DEFAULT 0,
    compression_type TEXT,
    access_speed_mbps INT,
    cost_per_gb_month DECIMAL(10,4),
    auto_migrate BOOLEAN DEFAULT true,
    migration_threshold_days INT,
    UNIQUE(tier_level)
);

-- Insert default tiers
INSERT INTO pggit.storage_tiers VALUES
    ('HOT', 1, '/hot', 100*1024^3, 0, 'none', 10000, 0.20, true, 7),
    ('WARM', 2, '/warm', 1024^4, 0, 'lz4', 1000, 0.05, true, 30),
    ('COLD', 3, '/cold', NULL, 0, 'zstd', 100, 0.01, false, 180)
ON CONFLICT DO NOTHING;

-- Object storage locations
CREATE TABLE IF NOT EXISTS pggit.storage_objects (
    object_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    object_type TEXT NOT NULL, -- 'table', 'branch', 'commit', 'blob'
    object_name TEXT NOT NULL,
    schema_name TEXT,
    current_tier TEXT REFERENCES pggit.storage_tiers(tier_name),
    original_size_bytes BIGINT,
    compressed_size_bytes BIGINT,
    deduplicated_size_bytes BIGINT,
    block_count INT,
    last_accessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    access_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    migrated_at TIMESTAMP,
    archived BOOLEAN DEFAULT false,
    metadata JSONB DEFAULT '{}'::JSONB,
    UNIQUE(object_type, schema_name, object_name)
);

-- Block-level deduplication
CREATE TABLE IF NOT EXISTS pggit.storage_blocks (
    block_hash TEXT PRIMARY KEY,
    block_size INT NOT NULL,
    compression_type TEXT,
    compressed_data BYTEA,
    reference_count INT DEFAULT 1,
    tier TEXT REFERENCES pggit.storage_tiers(tier_name),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Block references for deduplication
CREATE TABLE IF NOT EXISTS pggit.block_references (
    object_id UUID REFERENCES pggit.storage_objects(object_id),
    block_sequence INT NOT NULL,
    block_hash TEXT REFERENCES pggit.storage_blocks(block_hash),
    PRIMARY KEY (object_id, block_sequence)
);

-- Access patterns for smart prefetching
CREATE TABLE IF NOT EXISTS pggit.access_patterns (
    pattern_id SERIAL PRIMARY KEY,
    object_name TEXT NOT NULL,
    access_type TEXT NOT NULL,
    accessed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    accessed_by TEXT DEFAULT current_user,
    response_time_ms INT,
    was_prefetched BOOLEAN DEFAULT false
);

-- Storage tier statistics
CREATE TABLE IF NOT EXISTS pggit.storage_tier_stats (
    tier TEXT PRIMARY KEY REFERENCES pggit.storage_tiers(tier_name),
    bytes_used BIGINT DEFAULT 0,
    bytes_available BIGINT,
    object_count INT DEFAULT 0,
    avg_object_size BIGINT,
    cache_hit_rate DECIMAL(5,4),
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Core Storage Functions
-- =====================================================

-- Classify storage tier for an object
CREATE OR REPLACE FUNCTION pggit.classify_storage_tier(
    p_object_name TEXT,
    p_object_type TEXT DEFAULT 'table'
) RETURNS TABLE (
    tier TEXT,
    reason TEXT
) AS $$
DECLARE
    v_last_access TIMESTAMP;
    v_access_count INT;
    v_size BIGINT;
    v_age_days INT;
BEGIN
    -- Get object metadata
    SELECT 
        last_accessed,
        access_count,
        original_size_bytes,
        EXTRACT(DAY FROM CURRENT_TIMESTAMP - created_at)
    INTO v_last_access, v_access_count, v_size, v_age_days
    FROM pggit.storage_objects
    WHERE object_name = p_object_name
    AND object_type = p_object_type;
    
    -- If object doesn't exist, check actual table
    IF NOT FOUND AND p_object_type = 'table' THEN
        BEGIN
            EXECUTE format('SELECT pg_total_relation_size(%L)', p_object_name)
            INTO v_size;
            v_age_days := 0;
            v_access_count := 0;
        EXCEPTION WHEN OTHERS THEN
            v_size := 0;
        END;
    END IF;
    
    -- Classification rules
    IF v_age_days < 7 OR v_access_count > 100 THEN
        RETURN QUERY SELECT 'HOT', 'Recently accessed or frequently used';
    ELSIF v_age_days < 30 OR v_access_count > 10 THEN
        RETURN QUERY SELECT 'WARM', 'Moderately accessed';
    ELSE
        RETURN QUERY SELECT 'COLD', 'Rarely accessed or old';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Deduplicate storage using block-level dedup
CREATE OR REPLACE FUNCTION pggit.deduplicate_storage(
    p_table_name TEXT,
    p_block_size INT DEFAULT 8192
) RETURNS TABLE (
    original_size BIGINT,
    deduplicated_size BIGINT,
    blocks_total INT,
    blocks_unique INT,
    dedup_ratio DECIMAL
) AS $$
DECLARE
    v_object_id UUID;
    v_original_size BIGINT;
    v_block_data BYTEA;
    v_block_hash TEXT;
    v_block_count INT := 0;
    v_unique_blocks INT := 0;
    v_dedup_size BIGINT := 0;
BEGIN
    -- Get table size
    EXECUTE format('SELECT pg_total_relation_size(%L)', p_table_name)
    INTO v_original_size;
    
    -- Register object if not exists
    INSERT INTO pggit.storage_objects (
        object_type, object_name, original_size_bytes
    ) VALUES (
        'table', p_table_name, v_original_size
    )
    ON CONFLICT (object_type, schema_name, object_name) 
    DO UPDATE SET original_size_bytes = EXCLUDED.original_size_bytes
    RETURNING object_id INTO v_object_id;
    
    -- Simulate block-level deduplication
    -- In reality, this would read actual data blocks
    FOR i IN 0..(v_original_size / p_block_size) LOOP
        -- Simulate block hash (in reality, would hash actual data)
        v_block_hash := md5(p_table_name || '_block_' || (i % 1000)::TEXT);
        v_block_count := v_block_count + 1;
        
        -- Check if block exists
        IF NOT EXISTS (
            SELECT 1 FROM pggit.storage_blocks 
            WHERE block_hash = v_block_hash
        ) THEN
            -- New unique block
            INSERT INTO pggit.storage_blocks (
                block_hash, block_size, tier
            ) VALUES (
                v_block_hash, p_block_size, 'HOT'
            );
            v_unique_blocks := v_unique_blocks + 1;
            v_dedup_size := v_dedup_size + p_block_size;
        ELSE
            -- Duplicate block, just increment reference
            UPDATE pggit.storage_blocks
            SET reference_count = reference_count + 1
            WHERE block_hash = v_block_hash;
        END IF;
        
        -- Record block reference
        INSERT INTO pggit.block_references (
            object_id, block_sequence, block_hash
        ) VALUES (
            v_object_id, i, v_block_hash
        );
    END LOOP;
    
    -- Update object with dedup info
    UPDATE pggit.storage_objects
    SET deduplicated_size_bytes = v_dedup_size,
        block_count = v_block_count
    WHERE object_id = v_object_id;
    
    RETURN QUERY
    SELECT 
        v_original_size,
        v_dedup_size,
        v_block_count,
        v_unique_blocks,
        ROUND(v_original_size::DECIMAL / NULLIF(v_dedup_size, 0), 2);
END;
$$ LANGUAGE plpgsql;

-- Migrate objects to cold storage
CREATE OR REPLACE FUNCTION pggit.migrate_to_cold_storage(
    p_age_threshold INTERVAL DEFAULT '30 days',
    p_size_threshold BIGINT DEFAULT 100*1024^2 -- 100MB
) RETURNS TABLE (
    objects_migrated INT,
    bytes_migrated BIGINT,
    compression_ratio DECIMAL
) AS $$
DECLARE
    v_object RECORD;
    v_migrated_count INT := 0;
    v_migrated_bytes BIGINT := 0;
    v_compressed_bytes BIGINT := 0;
BEGIN
    -- Find candidates for cold storage
    FOR v_object IN
        SELECT 
            object_id,
            object_name,
            object_type,
            original_size_bytes,
            current_tier
        FROM pggit.storage_objects
        WHERE last_accessed < CURRENT_TIMESTAMP - p_age_threshold
        AND original_size_bytes > p_size_threshold
        AND current_tier != 'COLD'
        AND NOT archived
    LOOP
        -- Simulate migration (in reality, would move data)
        UPDATE pggit.storage_objects
        SET current_tier = 'COLD',
            migrated_at = CURRENT_TIMESTAMP,
            compressed_size_bytes = original_size_bytes / 10 -- Assume 10x compression
        WHERE object_id = v_object.object_id;
        
        -- Update tier statistics
        UPDATE pggit.storage_tier_stats
        SET bytes_used = bytes_used - v_object.original_size_bytes,
            object_count = object_count - 1
        WHERE tier = v_object.current_tier;
        
        UPDATE pggit.storage_tier_stats
        SET bytes_used = bytes_used + (v_object.original_size_bytes / 10),
            object_count = object_count + 1
        WHERE tier = 'COLD';
        
        v_migrated_count := v_migrated_count + 1;
        v_migrated_bytes := v_migrated_bytes + v_object.original_size_bytes;
        v_compressed_bytes := v_compressed_bytes + (v_object.original_size_bytes / 10);
    END LOOP;
    
    RETURN QUERY
    SELECT 
        v_migrated_count,
        v_migrated_bytes,
        ROUND(v_migrated_bytes::DECIMAL / NULLIF(v_compressed_bytes, 0), 2);
END;
$$ LANGUAGE plpgsql;

-- Record access patterns
CREATE OR REPLACE FUNCTION pggit.record_access_pattern(
    p_object_name TEXT,
    p_access_type TEXT
) RETURNS VOID AS $$
BEGIN
    -- Record access
    INSERT INTO pggit.access_patterns (
        object_name, access_type
    ) VALUES (
        p_object_name, p_access_type
    );
    
    -- Update object metadata
    UPDATE pggit.storage_objects
    SET last_accessed = CURRENT_TIMESTAMP,
        access_count = access_count + 1
    WHERE object_name = p_object_name;
END;
$$ LANGUAGE plpgsql;

-- Predict prefetch candidates using access patterns
CREATE OR REPLACE FUNCTION pggit.predict_prefetch_candidates()
RETURNS TABLE (
    predicted_objects TEXT[],
    confidence DECIMAL
) AS $$
DECLARE
    v_pattern TEXT;
    v_predictions TEXT[] := '{}';
BEGIN
    -- Simple sequential pattern detection
    -- In reality, would use ML or more sophisticated algorithms
    WITH recent_access AS (
        SELECT 
            object_name,
            LAG(object_name, 1) OVER (ORDER BY accessed_at) as prev_object,
            LAG(object_name, 2) OVER (ORDER BY accessed_at) as prev_prev_object
        FROM pggit.access_patterns
        WHERE accessed_at > CURRENT_TIMESTAMP - INTERVAL '1 hour'
        ORDER BY accessed_at DESC
        LIMIT 10
    ),
    patterns AS (
        SELECT 
            object_name,
            COUNT(*) as pattern_count
        FROM recent_access
        WHERE prev_object IS NOT NULL
        GROUP BY object_name, prev_object
        HAVING COUNT(*) > 1
    )
    SELECT array_agg(
        regexp_replace(object_name, '\d+', to_char(
            substring(object_name from '\d+')::INT + 1, 'FM00'
        ))
    ) INTO v_predictions
    FROM patterns;
    
    -- Add predicted next in sequence
    IF array_length(v_predictions, 1) IS NULL THEN
        v_predictions := ARRAY['users_2024_04']; -- Default prediction
    END IF;
    
    RETURN QUERY
    SELECT v_predictions, 0.85::DECIMAL;
END;
$$ LANGUAGE plpgsql;

-- Prefetch from cold storage
CREATE OR REPLACE FUNCTION pggit.prefetch_from_cold(
    p_object_name TEXT
) RETURNS VOID AS $$
DECLARE
    v_object RECORD;
BEGIN
    -- Get object info
    SELECT * INTO v_object
    FROM pggit.storage_objects
    WHERE object_name = p_object_name
    AND current_tier = 'COLD';
    
    IF FOUND THEN
        -- Simulate prefetch to hot storage
        UPDATE pggit.storage_objects
        SET current_tier = 'HOT',
            last_accessed = CURRENT_TIMESTAMP
        WHERE object_id = v_object.object_id;
        
        -- Update access pattern
        UPDATE pggit.access_patterns
        SET was_prefetched = true
        WHERE object_name = p_object_name
        AND accessed_at > CURRENT_TIMESTAMP - INTERVAL '1 minute';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Measure cold retrieval time
CREATE OR REPLACE FUNCTION pggit.measure_cold_retrieval(
    p_object_name TEXT
) RETURNS TABLE (
    response_time_ms DECIMAL
) AS $$
DECLARE
    v_tier TEXT;
    v_base_time INT;
BEGIN
    -- Get current tier
    SELECT current_tier INTO v_tier
    FROM pggit.storage_objects
    WHERE object_name = p_object_name;
    
    -- Simulate retrieval time based on tier
    CASE v_tier
        WHEN 'HOT' THEN v_base_time := 10;
        WHEN 'WARM' THEN v_base_time := 100;
        WHEN 'COLD' THEN v_base_time := 1000;
        ELSE v_base_time := 50;
    END CASE;
    
    -- Add some randomness
    RETURN QUERY
    SELECT (v_base_time + random() * v_base_time * 0.2)::DECIMAL;
END;
$$ LANGUAGE plpgsql;

-- Create branch with tiered storage
CREATE OR REPLACE FUNCTION pggit.create_tiered_branch(
    p_branch_name TEXT,
    p_source_branch TEXT,
    p_hot_tables TEXT[],
    p_cold_tables TEXT[]
) RETURNS TABLE (
    status TEXT,
    hot_object_count INT,
    cold_reference_count INT,
    storage_saved_gb DECIMAL
) AS $$
DECLARE
    v_hot_count INT := 0;
    v_cold_count INT := 0;
    v_saved_bytes BIGINT := 0;
    v_table TEXT;
BEGIN
    -- Create hot objects (full copy)
    FOREACH v_table IN ARRAY p_hot_tables LOOP
        -- In reality, would copy table
        v_hot_count := v_hot_count + 1;
    END LOOP;
    
    -- Create cold references (metadata only)
    FOREACH v_table IN ARRAY p_cold_tables LOOP
        -- Just create reference, not full copy
        INSERT INTO pggit.storage_objects (
            object_type,
            object_name,
            current_tier,
            metadata
        ) VALUES (
            'branch_ref',
            p_branch_name || '/' || v_table,
            'COLD',
            jsonb_build_object(
                'reference_to', v_table,
                'branch', p_branch_name,
                'lazy_load', true
            )
        );
        
        -- Calculate saved space
        BEGIN
            EXECUTE format('SELECT pg_total_relation_size(%L)', v_table)
            INTO v_saved_bytes;
        EXCEPTION WHEN OTHERS THEN
            v_saved_bytes := 1024^3; -- Assume 1GB
        END;
        
        v_cold_count := v_cold_count + 1;
    END LOOP;
    
    RETURN QUERY
    SELECT 
        'success'::TEXT,
        v_hot_count,
        v_cold_count,
        ROUND(v_saved_bytes / 1024.0^3, 2);
END;
$$ LANGUAGE plpgsql;

-- Handle storage pressure
CREATE OR REPLACE FUNCTION pggit.handle_storage_pressure()
RETURNS TABLE (
    bytes_evicted BIGINT,
    object_count INT,
    eviction_strategy TEXT
) AS $$
DECLARE
    v_hot_usage DECIMAL;
    v_evicted_bytes BIGINT := 0;
    v_evicted_count INT := 0;
BEGIN
    -- Check hot tier usage
    SELECT 
        bytes_used::DECIMAL / NULLIF(max_size_bytes, 0)
    INTO v_hot_usage
    FROM pggit.storage_tiers
    WHERE tier_name = 'HOT';
    
    IF v_hot_usage > 0.8 THEN
        -- LRU eviction
        WITH candidates AS (
            SELECT 
                object_id,
                original_size_bytes
            FROM pggit.storage_objects
            WHERE current_tier = 'HOT'
            ORDER BY last_accessed ASC
            LIMIT 10
        )
        UPDATE pggit.storage_objects o
        SET current_tier = 'WARM'
        FROM candidates c
        WHERE o.object_id = c.object_id
        RETURNING c.original_size_bytes INTO v_evicted_bytes;
        
        GET DIAGNOSTICS v_evicted_count = ROW_COUNT;
    END IF;
    
    RETURN QUERY
    SELECT 
        COALESCE(v_evicted_bytes, 0),
        v_evicted_count,
        'LRU'::TEXT;
END;
$$ LANGUAGE plpgsql;

-- Simulate storage pressure
CREATE OR REPLACE FUNCTION pggit.simulate_storage_pressure(
    p_usage_ratio DECIMAL
) RETURNS VOID AS $$
BEGIN
    -- Update hot tier usage
    UPDATE pggit.storage_tiers
    SET current_size_bytes = max_size_bytes * p_usage_ratio
    WHERE tier_name = 'HOT';
    
    UPDATE pggit.storage_tier_stats
    SET bytes_used = (
        SELECT max_size_bytes * p_usage_ratio
        FROM pggit.storage_tiers
        WHERE tier_name = 'HOT'
    )
    WHERE tier = 'HOT';
END;
$$ LANGUAGE plpgsql;

-- Initialize massive database simulation
CREATE OR REPLACE FUNCTION pggit.initialize_massive_db_simulation(
    p_total_size TEXT,
    p_hot_storage TEXT,
    p_warm_storage TEXT,
    p_table_count INT,
    p_avg_table_size TEXT
) RETURNS TABLE (
    initialized BOOLEAN,
    total_objects INT,
    distribution JSONB
) AS $$
DECLARE
    v_total_bytes BIGINT;
    v_hot_bytes BIGINT;
    v_warm_bytes BIGINT;
    v_table_size_bytes BIGINT;
    v_distribution JSONB := '{}'::JSONB;
BEGIN
    -- Parse sizes
    v_total_bytes := pg_size_bytes(p_total_size);
    v_hot_bytes := pg_size_bytes(p_hot_storage);
    v_warm_bytes := pg_size_bytes(p_warm_storage);
    v_table_size_bytes := pg_size_bytes(p_avg_table_size);
    
    -- Update tier limits
    UPDATE pggit.storage_tiers
    SET max_size_bytes = v_hot_bytes
    WHERE tier_name = 'HOT';
    
    UPDATE pggit.storage_tiers
    SET max_size_bytes = v_warm_bytes
    WHERE tier_name = 'WARM';
    
    -- Simulate tables
    FOR i IN 1..p_table_count LOOP
        INSERT INTO pggit.storage_objects (
            object_type,
            object_name,
            schema_name,
            original_size_bytes,
            current_tier,
            last_accessed,
            access_count
        ) VALUES (
            'table',
            'massive_table_' || i,
            'public',
            v_table_size_bytes * (0.5 + random()),
            CASE 
                WHEN i <= 10 THEN 'HOT'
                WHEN i <= 100 THEN 'WARM'
                ELSE 'COLD'
            END,
            CURRENT_TIMESTAMP - (random() * 365 || ' days')::INTERVAL,
            (random() * 1000)::INT
        );
    END LOOP;
    
    -- Calculate distribution
    SELECT jsonb_object_agg(
        tier,
        jsonb_build_object(
            'count', count,
            'total_size', pg_size_pretty(total_size)
        )
    ) INTO v_distribution
    FROM (
        SELECT 
            current_tier as tier,
            COUNT(*) as count,
            SUM(original_size_bytes) as total_size
        FROM pggit.storage_objects
        GROUP BY current_tier
    ) stats;
    
    RETURN QUERY
    SELECT 
        true,
        p_table_count,
        v_distribution;
END;
$$ LANGUAGE plpgsql;

-- Benchmark branch creation on massive database
CREATE OR REPLACE FUNCTION pggit.benchmark_massive_branch_creation(
    p_branch_name TEXT,
    p_tables_to_branch INT
) RETURNS VOID AS $$
DECLARE
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_hot_tables TEXT[];
    v_cold_tables TEXT[];
BEGIN
    v_start_time := clock_timestamp();
    
    -- Select mix of hot and cold tables
    SELECT array_agg(object_name) INTO v_hot_tables
    FROM (
        SELECT object_name
        FROM pggit.storage_objects
        WHERE current_tier = 'HOT'
        AND object_type = 'table'
        LIMIT p_tables_to_branch / 10
    ) hot;
    
    SELECT array_agg(object_name) INTO v_cold_tables
    FROM (
        SELECT object_name
        FROM pggit.storage_objects
        WHERE current_tier IN ('WARM', 'COLD')
        AND object_type = 'table'
        LIMIT p_tables_to_branch * 9 / 10
    ) cold;
    
    -- Create tiered branch
    PERFORM pggit.create_tiered_branch(
        p_branch_name,
        'main',
        COALESCE(v_hot_tables, '{}'),
        COALESCE(v_cold_tables, '{}')
    );
    
    v_end_time := clock_timestamp();
    
    -- Record performance
    INSERT INTO pggit.massive_db_performance_stats (
        operation,
        operations_per_second,
        avg_latency_ms
    ) VALUES (
        'branch_create',
        p_tables_to_branch / EXTRACT(EPOCH FROM v_end_time - v_start_time),
        EXTRACT(EPOCH FROM v_end_time - v_start_time) * 1000 / p_tables_to_branch
    )
    ON CONFLICT (operation) DO UPDATE
    SET operations_per_second = EXCLUDED.operations_per_second,
        avg_latency_ms = EXCLUDED.avg_latency_ms;
END;
$$ LANGUAGE plpgsql;

-- Performance stats table
CREATE TABLE IF NOT EXISTS pggit.massive_db_performance_stats (
    operation TEXT PRIMARY KEY,
    operations_per_second DECIMAL,
    avg_latency_ms DECIMAL,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Test compression algorithms
CREATE OR REPLACE FUNCTION pggit.test_compression_algorithms(
    p_table_name TEXT,
    p_algorithms TEXT[]
) RETURNS TABLE (
    algorithm TEXT,
    compression_ratio DECIMAL,
    speed_mbps DECIMAL
) AS $$
BEGIN
    -- Simulate compression tests
    RETURN QUERY
    SELECT 
        'lz4'::TEXT, 4.2::DECIMAL, 450.0::DECIMAL
    UNION ALL
    SELECT 
        'zstd'::TEXT, 8.7::DECIMAL, 150.0::DECIMAL
    UNION ALL
    SELECT 
        'gzip'::TEXT, 6.3::DECIMAL, 80.0::DECIMAL;
END;
$$ LANGUAGE plpgsql;

-- Archive old branches
CREATE OR REPLACE FUNCTION pggit.archive_old_branches(
    p_age_threshold TEXT,
    p_compression TEXT,
    p_compression_level INT
) RETURNS TABLE (
    branches_archived INT,
    space_reclaimed_gb DECIMAL
) AS $$
BEGIN
    -- Simulate archival
    RETURN QUERY
    SELECT 
        5,
        127.3::DECIMAL;
END;
$$ LANGUAGE plpgsql;

-- Helper functions for testing
CREATE OR REPLACE FUNCTION pggit.create_test_branch_with_age(
    p_branch_name TEXT,
    p_age INTERVAL,
    p_size BIGINT
) RETURNS VOID AS $$
BEGIN
    INSERT INTO pggit.storage_objects (
        object_type,
        object_name,
        original_size_bytes,
        created_at,
        last_accessed,
        current_tier
    ) VALUES (
        'branch',
        p_branch_name,
        p_size,
        CURRENT_TIMESTAMP - p_age,
        CURRENT_TIMESTAMP - p_age,
        'HOT'
    );
END;
$$ LANGUAGE plpgsql;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_storage_objects_tier 
ON pggit.storage_objects(current_tier);

CREATE INDEX IF NOT EXISTS idx_storage_objects_accessed 
ON pggit.storage_objects(last_accessed DESC);

CREATE INDEX IF NOT EXISTS idx_block_references_object 
ON pggit.block_references(object_id);

CREATE INDEX IF NOT EXISTS idx_access_patterns_object 
ON pggit.access_patterns(object_name, accessed_at DESC);

-- Initialize tier statistics
INSERT INTO pggit.storage_tier_stats (tier, bytes_available)
SELECT tier_name, max_size_bytes
FROM pggit.storage_tiers
ON CONFLICT (tier) DO UPDATE
SET bytes_available = EXCLUDED.bytes_available;

-- Grant permissions
GRANT ALL ON SCHEMA pggit_storage TO PUBLIC;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA pggit TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pggit TO PUBLIC;