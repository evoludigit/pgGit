-- Performance Optimizations for Large Schema Operations
-- Addresses Viktor's concern about "Performance Will Be Garbage"

-- ============================================
-- PART 1: Copy-on-Write Storage with Deduplication
-- ============================================

-- Deduplicated blob storage
CREATE TABLE IF NOT EXISTS pggit.blob_storage (
    content_hash TEXT PRIMARY KEY,
    content_data TEXT NOT NULL,
    compressed_data BYTEA, -- Compressed version for large content
    original_size INTEGER NOT NULL,
    compressed_size INTEGER,
    compression_ratio NUMERIC,
    reference_count INTEGER DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_accessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Reference tracking for garbage collection
CREATE TABLE IF NOT EXISTS pggit.blob_references (
    content_hash TEXT REFERENCES pggit.blob_storage(content_hash) ON DELETE CASCADE,
    commit_id UUID REFERENCES pggit.commits(id) ON DELETE CASCADE,
    object_path TEXT NOT NULL, -- e.g., 'schema.table'
    PRIMARY KEY (content_hash, commit_id, object_path)
);

-- Optimized indexes for performance
CREATE INDEX IF NOT EXISTS idx_blob_storage_size ON pggit.blob_storage(original_size);
CREATE INDEX IF NOT EXISTS idx_blob_storage_refs ON pggit.blob_storage(reference_count);
CREATE INDEX IF NOT EXISTS idx_blob_storage_accessed ON pggit.blob_storage(last_accessed);
CREATE INDEX IF NOT EXISTS idx_blob_refs_commit ON pggit.blob_references(commit_id);

-- ============================================
-- PART 2: Intelligent Blob Storage
-- ============================================

-- Store content with automatic deduplication and compression
CREATE OR REPLACE FUNCTION pggit.store_blob_optimized(
    p_content TEXT,
    p_commit_id UUID,
    p_object_path TEXT
) RETURNS TEXT AS $$
DECLARE
    v_content_hash TEXT;
    v_compressed BYTEA;
    v_compressed_size INTEGER;
    v_original_size INTEGER;
    v_compression_ratio NUMERIC;
    v_should_compress BOOLEAN := false;
BEGIN
    -- Calculate hash and size
    v_content_hash := encode(digest(p_content, 'sha256'), 'hex');
    v_original_size := length(p_content);
    
    -- Decide whether to compress (for content > 1KB)
    v_should_compress := v_original_size > 1024;
    
    -- Try to insert blob (will fail if exists)
    BEGIN
        IF v_should_compress THEN
            -- Compress using PostgreSQL's built-in compression
            v_compressed := compress(p_content::bytea);
            v_compressed_size := length(v_compressed);
            v_compression_ratio := ROUND((v_compressed_size::NUMERIC / v_original_size::NUMERIC) * 100, 2);
            
            INSERT INTO pggit.blob_storage (
                content_hash, content_data, compressed_data, 
                original_size, compressed_size, compression_ratio
            ) VALUES (
                v_content_hash, p_content, v_compressed,
                v_original_size, v_compressed_size, v_compression_ratio
            );
        ELSE
            INSERT INTO pggit.blob_storage (
                content_hash, content_data, original_size
            ) VALUES (
                v_content_hash, p_content, v_original_size
            );
        END IF;
    EXCEPTION WHEN unique_violation THEN
        -- Blob already exists, just increment reference count
        UPDATE pggit.blob_storage 
        SET reference_count = reference_count + 1,
            last_accessed = CURRENT_TIMESTAMP
        WHERE content_hash = v_content_hash;
    END;
    
    -- Add reference
    INSERT INTO pggit.blob_references (content_hash, commit_id, object_path)
    VALUES (v_content_hash, p_commit_id, p_object_path)
    ON CONFLICT DO NOTHING;
    
    RETURN v_content_hash;
END;
$$ LANGUAGE plpgsql;

-- Retrieve blob content with automatic decompression
CREATE OR REPLACE FUNCTION pggit.get_blob_content(
    p_content_hash TEXT
) RETURNS TEXT AS $$
DECLARE
    v_record RECORD;
BEGIN
    SELECT * INTO v_record 
    FROM pggit.blob_storage 
    WHERE content_hash = p_content_hash;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Blob % not found', p_content_hash;
    END IF;
    
    -- Update access time
    UPDATE pggit.blob_storage 
    SET last_accessed = CURRENT_TIMESTAMP 
    WHERE content_hash = p_content_hash;
    
    -- Return decompressed content if needed
    IF v_record.compressed_data IS NOT NULL THEN
        RETURN convert_from(decompress(v_record.compressed_data), 'UTF8');
    ELSE
        RETURN v_record.content_data;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 3: Incremental Tree Building
-- ============================================

-- Build tree incrementally with only changed objects
CREATE OR REPLACE FUNCTION pggit.create_incremental_tree_snapshot(
    p_parent_commit_id UUID DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_changed_objects RECORD;
    v_tree_data JSONB := '{"blobs": [], "metadata": {}}'::jsonb;
    v_blob_hashes TEXT[] := ARRAY[]::TEXT[];
    v_unchanged_hashes TEXT[] := ARRAY[]::TEXT[];
    v_tree_hash TEXT;
    v_object_count INTEGER := 0;
    v_new_object_count INTEGER := 0;
    v_current_schema TEXT;
BEGIN
    -- Get current working schema
    SELECT working_schema INTO v_current_schema FROM pggit.HEAD;
    
    -- If no parent commit, do full snapshot
    IF p_parent_commit_id IS NULL THEN
        RETURN pggit.create_tree_snapshot();
    END IF;
    
    -- Get changed objects since parent commit
    FOR v_changed_objects IN
        WITH current_state AS (
            SELECT 
                c.relkind::text as object_kind,
                n.nspname as schema_name,
                c.relname as object_name,
                pggit.get_current_object_definition(
                    CASE c.relkind 
                        WHEN 'r' THEN 'TABLE'::pggit.object_type
                        WHEN 'v' THEN 'VIEW'::pggit.object_type
                        ELSE 'TABLE'::pggit.object_type
                    END,
                    n.nspname,
                    c.relname
                ) as current_definition
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = v_current_schema
            AND c.relkind IN ('r', 'v', 'f', 'p')
        ),
        parent_state AS (
            SELECT 
                b.object_schema || '.' || b.object_name as full_name,
                b.blob_hash,
                b.object_definition
            FROM pggit.commits pc
            JOIN pggit.trees pt ON pt.tree_hash = pc.tree_hash
            JOIN pggit.blobs b ON b.blob_hash = ANY(
                SELECT jsonb_array_elements_text(pt.schema_snapshot->'blobs')
            )
            WHERE pc.id = p_parent_commit_id
        )
        SELECT 
            cs.schema_name || '.' || cs.object_name as full_name,
            cs.current_definition,
            ps.blob_hash as parent_hash,
            ps.object_definition as parent_definition,
            CASE 
                WHEN ps.full_name IS NULL THEN 'ADDED'
                WHEN cs.current_definition IS DISTINCT FROM ps.object_definition THEN 'MODIFIED'
                ELSE 'UNCHANGED'
            END as change_type
        FROM current_state cs
        FULL OUTER JOIN parent_state ps ON cs.schema_name || '.' || cs.object_name = ps.full_name
        WHERE cs.schema_name || '.' || cs.object_name IS NOT NULL
    LOOP
        v_object_count := v_object_count + 1;
        
        IF v_changed_objects.change_type IN ('ADDED', 'MODIFIED') THEN
            -- Create new blob for changed object
            v_blob_hashes := v_blob_hashes || pggit.store_blob_optimized(
                v_changed_objects.current_definition,
                (SELECT current_commit_id FROM pggit.HEAD),
                v_changed_objects.full_name
            );
            v_new_object_count := v_new_object_count + 1;
        ELSE
            -- Reuse existing blob hash
            v_unchanged_hashes := v_unchanged_hashes || v_changed_objects.parent_hash;
        END IF;
    END LOOP;
    
    -- Combine all blob hashes
    v_blob_hashes := v_blob_hashes || v_unchanged_hashes;
    
    -- Create tree metadata
    v_tree_data := jsonb_set(v_tree_data, '{blobs}', to_jsonb(v_blob_hashes));
    v_tree_data := jsonb_set(v_tree_data, '{metadata}', jsonb_build_object(
        'total_objects', v_object_count,
        'new_objects', v_new_object_count,
        'reused_objects', v_object_count - v_new_object_count,
        'parent_commit', p_parent_commit_id,
        'incremental', true,
        'timestamp', CURRENT_TIMESTAMP
    ));
    
    -- Generate tree hash
    v_tree_hash := encode(digest(v_tree_data::text, 'sha256'), 'hex');
    
    -- Store tree
    INSERT INTO pggit.trees (tree_hash, schema_snapshot, object_count)
    VALUES (v_tree_hash, v_tree_data, v_object_count)
    ON CONFLICT (tree_hash) DO NOTHING;
    
    RETURN v_tree_hash;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 4: Parallel Processing for Large Operations
-- ============================================

-- Process large schemas in parallel batches
CREATE OR REPLACE FUNCTION pggit.process_schema_parallel(
    p_schema_name TEXT,
    p_operation TEXT, -- 'clone', 'snapshot', 'compare'
    p_batch_size INTEGER DEFAULT 50
) RETURNS TABLE (
    batch_id INTEGER,
    objects_processed INTEGER,
    processing_time_ms NUMERIC,
    status TEXT
) AS $$
DECLARE
    v_total_objects INTEGER;
    v_batch_count INTEGER;
    v_current_batch INTEGER := 1;
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_batch_objects INTEGER;
BEGIN
    -- Count total objects
    SELECT COUNT(*) INTO v_total_objects
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = p_schema_name
    AND c.relkind IN ('r', 'v', 'f', 'p');
    
    v_batch_count := CEIL(v_total_objects::NUMERIC / p_batch_size::NUMERIC);
    
    -- Process in batches
    FOR v_current_batch IN 1..v_batch_count LOOP
        v_start_time := clock_timestamp();
        
        -- Process batch based on operation type
        CASE p_operation
            WHEN 'snapshot' THEN
                PERFORM pggit.process_snapshot_batch(
                    p_schema_name, 
                    v_current_batch, 
                    p_batch_size
                );
            WHEN 'clone' THEN
                PERFORM pggit.process_clone_batch(
                    p_schema_name, 
                    v_current_batch, 
                    p_batch_size
                );
            ELSE
                RAISE EXCEPTION 'Unknown operation: %', p_operation;
        END CASE;
        
        v_end_time := clock_timestamp();
        v_batch_objects := LEAST(p_batch_size, v_total_objects - (v_current_batch - 1) * p_batch_size);
        
        RETURN QUERY SELECT 
            v_current_batch,
            v_batch_objects,
            EXTRACT(milliseconds FROM (v_end_time - v_start_time)),
            'completed'::TEXT;
    END LOOP;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- Process snapshot batch
CREATE OR REPLACE FUNCTION pggit.process_snapshot_batch(
    p_schema_name TEXT,
    p_batch_number INTEGER,
    p_batch_size INTEGER
) RETURNS void AS $$
DECLARE
    v_object RECORD;
    v_offset INTEGER;
BEGIN
    v_offset := (p_batch_number - 1) * p_batch_size;
    
    FOR v_object IN
        SELECT 
            c.relname as object_name,
            c.relkind as object_kind,
            n.nspname as schema_name
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = p_schema_name
        AND c.relkind IN ('r', 'v', 'f', 'p')
        ORDER BY c.relname
        LIMIT p_batch_size OFFSET v_offset
    LOOP
        -- Process individual object
        PERFORM pggit.create_blob_for_object(
            v_object.object_kind,
            v_object.schema_name,
            v_object.object_name
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 5: Performance Monitoring and Metrics
-- ============================================

-- Performance metrics tracking
CREATE TABLE IF NOT EXISTS pggit.performance_metrics (
    id SERIAL PRIMARY KEY,
    operation_type TEXT NOT NULL,
    operation_context JSONB,
    duration_ms NUMERIC NOT NULL,
    objects_processed INTEGER,
    memory_usage_mb NUMERIC,
    blob_cache_hits INTEGER DEFAULT 0,
    blob_cache_misses INTEGER DEFAULT 0,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_perf_metrics_operation ON pggit.performance_metrics(operation_type);
CREATE INDEX idx_perf_metrics_time ON pggit.performance_metrics(recorded_at);

-- Track operation performance
CREATE OR REPLACE FUNCTION pggit.track_operation_performance(
    p_operation_type TEXT,
    p_operation_context JSONB,
    p_duration_ms NUMERIC,
    p_objects_processed INTEGER DEFAULT NULL
) RETURNS void AS $$
BEGIN
    INSERT INTO pggit.performance_metrics (
        operation_type,
        operation_context,
        duration_ms,
        objects_processed
    ) VALUES (
        p_operation_type,
        p_operation_context,
        p_duration_ms,
        p_objects_processed
    );
END;
$$ LANGUAGE plpgsql;

-- Performance dashboard view
CREATE OR REPLACE VIEW pggit.performance_dashboard AS
WITH recent_metrics AS (
    SELECT 
        operation_type,
        AVG(duration_ms) as avg_duration_ms,
        MAX(duration_ms) as max_duration_ms,
        MIN(duration_ms) as min_duration_ms,
        COUNT(*) as operation_count,
        SUM(objects_processed) as total_objects_processed,
        AVG(objects_processed) as avg_objects_per_operation
    FROM pggit.performance_metrics
    WHERE recorded_at > CURRENT_TIMESTAMP - INTERVAL '24 hours'
    GROUP BY operation_type
)
SELECT 
    operation_type,
    ROUND(avg_duration_ms::NUMERIC, 2) as avg_duration_ms,
    ROUND(max_duration_ms::NUMERIC, 2) as max_duration_ms,
    operation_count,
    total_objects_processed,
    ROUND(avg_objects_per_operation::NUMERIC, 1) as avg_objects_per_op,
    CASE 
        WHEN avg_duration_ms > 5000 THEN 'SLOW'
        WHEN avg_duration_ms > 1000 THEN 'MODERATE'
        ELSE 'FAST'
    END as performance_rating,
    ROUND((total_objects_processed::NUMERIC / GREATEST(avg_duration_ms, 1)) * 1000, 2) as objects_per_second
FROM recent_metrics
ORDER BY avg_duration_ms DESC;

-- ============================================
-- PART 6: Garbage Collection
-- ============================================

-- Clean up unreferenced blobs
CREATE OR REPLACE FUNCTION pggit.cleanup_unreferenced_blobs(
    p_older_than_days INTEGER DEFAULT 7
) RETURNS TABLE (
    cleaned_blobs INTEGER,
    space_freed_mb NUMERIC
) AS $$
DECLARE
    v_deleted_count INTEGER;
    v_space_freed NUMERIC;
BEGIN
    -- Delete blobs with no references and older than threshold
    WITH unreferenced_blobs AS (
        SELECT bs.content_hash, bs.original_size
        FROM pggit.blob_storage bs
        LEFT JOIN pggit.blob_references br ON bs.content_hash = br.content_hash
        WHERE br.content_hash IS NULL
        AND bs.last_accessed < CURRENT_TIMESTAMP - (p_older_than_days || ' days')::INTERVAL
    ),
    deleted_blobs AS (
        DELETE FROM pggit.blob_storage
        WHERE content_hash IN (SELECT content_hash FROM unreferenced_blobs)
        RETURNING content_hash, original_size
    )
    SELECT 
        COUNT(*)::INTEGER,
        ROUND(SUM(original_size)::NUMERIC / 1024.0 / 1024.0, 2)
    INTO v_deleted_count, v_space_freed
    FROM deleted_blobs;
    
    RETURN QUERY SELECT v_deleted_count, v_space_freed;
END;
$$ LANGUAGE plpgsql;

-- Storage statistics
CREATE OR REPLACE VIEW pggit.storage_statistics AS
SELECT 
    COUNT(*) as total_blobs,
    SUM(original_size) / 1024.0 / 1024.0 as total_size_mb,
    SUM(COALESCE(compressed_size, original_size)) / 1024.0 / 1024.0 as actual_size_mb,
    ROUND(AVG(COALESCE(compression_ratio, 100)), 2) as avg_compression_ratio,
    SUM(reference_count) as total_references,
    COUNT(*) FILTER (WHERE reference_count = 1) as unique_blobs,
    COUNT(*) FILTER (WHERE reference_count > 1) as shared_blobs,
    ROUND(
        (COUNT(*) FILTER (WHERE reference_count > 1)::NUMERIC / COUNT(*)::NUMERIC) * 100, 
        2
    ) as deduplication_rate_percent
FROM pggit.blob_storage;

COMMENT ON FUNCTION pggit.store_blob_optimized IS 'Store content with deduplication and compression';
COMMENT ON FUNCTION pggit.create_incremental_tree_snapshot IS 'Create tree snapshot with only changed objects';
COMMENT ON FUNCTION pggit.process_schema_parallel IS 'Process large schemas in parallel batches';
COMMENT ON VIEW pggit.performance_dashboard IS 'Performance metrics for operations';