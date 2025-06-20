-- Performance Optimizations and Bounded Growth for pg_gitversion
-- Ensures the system scales properly and doesn't grow unbounded

-- ============================================
-- PART 1: History Table Partitioning
-- ============================================

-- Convert history table to partitioned by time
DO $$
BEGIN
    -- Check if history table is already partitioned
    IF NOT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'pggit' 
        AND c.relname = 'history'
        AND c.relkind = 'p'  -- partitioned table
    ) THEN
        -- Create new partitioned table without any constraints
        CREATE TABLE pggit.history_new (
            id INTEGER NOT NULL,
            object_id INTEGER NOT NULL,
            change_type pggit.change_type NOT NULL,
            change_severity pggit.change_severity NOT NULL,
            commit_hash TEXT,
            branch_id INTEGER,
            merge_base_hash TEXT,
            merge_resolution pggit.merge_resolution,
            old_version INTEGER,
            new_version INTEGER,
            old_metadata JSONB,
            new_metadata JSONB,
            change_description TEXT,
            sql_executed TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            created_by TEXT DEFAULT CURRENT_USER,
            PRIMARY KEY (id, created_at)
        ) PARTITION BY RANGE (created_at);
        
        -- Add foreign key constraints
        ALTER TABLE pggit.history_new ADD CONSTRAINT fk_history_object 
            FOREIGN KEY (object_id) REFERENCES pggit.objects(id) ON DELETE CASCADE;
        ALTER TABLE pggit.history_new ADD CONSTRAINT fk_history_branch 
            FOREIGN KEY (branch_id) REFERENCES pggit.branches(id);
        
        -- Create sequence for id column
        CREATE SEQUENCE pggit.history_new_id_seq;
        ALTER TABLE pggit.history_new ALTER COLUMN id SET DEFAULT nextval('pggit.history_new_id_seq');
        
        -- Copy data from old table (explicitly list columns to avoid mismatch)
        INSERT INTO pggit.history_new (
            id, object_id, change_type, change_severity, commit_hash, branch_id,
            merge_base_hash, merge_resolution, old_version, new_version,
            old_metadata, new_metadata, change_description, sql_executed,
            created_at, created_by
        )
        SELECT 
            id, object_id, change_type, change_severity, commit_hash, branch_id,
            merge_base_hash, merge_resolution, old_version, new_version,
            old_metadata, new_metadata, change_description, sql_executed,
            created_at, created_by
        FROM pggit.history;
        
        -- Update sequence to continue from last value
        PERFORM setval('pggit.history_new_id_seq', COALESCE(MAX(id), 1)) FROM pggit.history_new;
        
        -- Swap tables
        ALTER TABLE pggit.history RENAME TO history_old;
        ALTER TABLE pggit.history_new RENAME TO history;
        ALTER SEQUENCE pggit.history_new_id_seq RENAME TO history_id_seq;
        
        -- Update foreign key constraints
        ALTER TABLE pggit.history 
            ADD CONSTRAINT history_object_id_fkey 
            FOREIGN KEY (object_id) REFERENCES pggit.objects(id);
            
        -- Drop old table
        DROP TABLE pggit.history_old;
    END IF;
END $$;

-- Function to create monthly partitions
CREATE OR REPLACE FUNCTION pggit.create_history_partitions(
    p_months_ahead INTEGER DEFAULT 3
) RETURNS INTEGER AS $$
DECLARE
    v_partition_name TEXT;
    v_start_date DATE;
    v_end_date DATE;
    v_created INTEGER := 0;
BEGIN
    -- Create partitions for the specified number of months
    FOR i IN 0..p_months_ahead LOOP
        v_start_date := date_trunc('month', CURRENT_DATE + (i || ' months')::INTERVAL);
        v_end_date := v_start_date + INTERVAL '1 month';
        v_partition_name := 'history_' || to_char(v_start_date, 'YYYY_MM');
        
        -- Check if partition exists
        IF NOT EXISTS (
            SELECT 1 FROM pg_class 
            WHERE relname = v_partition_name 
            AND relnamespace = 'pggit'::regnamespace
        ) THEN
            EXECUTE format(
                'CREATE TABLE pggit.%I PARTITION OF pggit.history
                FOR VALUES FROM (%L) TO (%L)',
                v_partition_name, v_start_date, v_end_date
            );
            
            -- Create indexes on partition
            EXECUTE format(
                'CREATE INDEX %I ON pggit.%I (object_id, version)',
                'idx_' || v_partition_name || '_object_version',
                v_partition_name
            );
            
            EXECUTE format(
                'CREATE INDEX %I ON pggit.%I (created_at)',
                'idx_' || v_partition_name || '_created_at',
                v_partition_name
            );
            
            v_created := v_created + 1;
        END IF;
    END LOOP;
    
    RETURN v_created;
END;
$$ LANGUAGE plpgsql;

-- Create initial partitions
SELECT pggit.create_history_partitions(6);

-- ============================================
-- PART 2: Automated Data Retention
-- ============================================

-- Retention policy configuration
CREATE TABLE IF NOT EXISTS pggit.retention_policies (
    id SERIAL PRIMARY KEY,
    table_name TEXT NOT NULL,
    retention_period INTERVAL NOT NULL,
    archive_enabled BOOLEAN DEFAULT FALSE,
    archive_location TEXT,
    last_cleanup TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Default retention policies
INSERT INTO pggit.retention_policies (table_name, retention_period, archive_enabled)
VALUES 
    ('history', '2 years', true),
    ('trigger_errors', '30 days', false),
    ('metrics', '90 days', false)
ON CONFLICT DO NOTHING;

-- Archive table for old history
CREATE TABLE IF NOT EXISTS pggit.history_archive (
    LIKE pggit.history INCLUDING ALL
);

-- Cleanup function with archiving
CREATE OR REPLACE FUNCTION pggit.cleanup_old_data()
RETURNS TABLE (
    table_name TEXT,
    rows_archived INTEGER,
    rows_deleted INTEGER,
    space_freed TEXT
) AS $$
DECLARE
    v_policy RECORD;
    v_archived INTEGER;
    v_deleted INTEGER;
    v_space_before BIGINT;
    v_space_after BIGINT;
BEGIN
    FOR v_policy IN 
        SELECT * FROM pggit.retention_policies 
        WHERE is_active = TRUE
    LOOP
        v_archived := 0;
        v_deleted := 0;
        
        -- Get space before
        SELECT pg_total_relation_size('pggit.' || v_policy.table_name) 
        INTO v_space_before;
        
        IF v_policy.table_name = 'history' THEN
            -- Archive old history records
            IF v_policy.archive_enabled THEN
                INSERT INTO pggit.history_archive
                SELECT h.* FROM pggit.history h
                WHERE h.created_at < CURRENT_TIMESTAMP - v_policy.retention_period;
                
                GET DIAGNOSTICS v_archived = ROW_COUNT;
            END IF;
            
            -- Delete from main table
            DELETE FROM pggit.history
            WHERE created_at < CURRENT_TIMESTAMP - v_policy.retention_period;
            
            GET DIAGNOSTICS v_deleted = ROW_COUNT;
            
        ELSIF v_policy.table_name = 'trigger_errors' THEN
            DELETE FROM pggit.trigger_errors
            WHERE occurred_at < CURRENT_TIMESTAMP - v_policy.retention_period;
            
            GET DIAGNOSTICS v_deleted = ROW_COUNT;
            
        ELSIF v_policy.table_name = 'metrics' AND 
              EXISTS (SELECT 1 FROM information_schema.tables 
                     WHERE table_schema = 'pggit_enterprise' 
                     AND table_name = 'metrics') THEN
            EXECUTE format(
                'DELETE FROM pggit_enterprise.metrics WHERE collected_at < %L',
                CURRENT_TIMESTAMP - v_policy.retention_period
            );
            
            GET DIAGNOSTICS v_deleted = ROW_COUNT;
        END IF;
        
        -- Update last cleanup time
        UPDATE pggit.retention_policies
        SET last_cleanup = CURRENT_TIMESTAMP
        WHERE id = v_policy.id;
        
        -- Get space after and calculate freed space
        SELECT pg_total_relation_size('pggit.' || v_policy.table_name) 
        INTO v_space_after;
        
        RETURN QUERY
        SELECT 
            v_policy.table_name,
            v_archived,
            v_deleted,
            pg_size_pretty(v_space_before - v_space_after);
    END LOOP;
    
    -- Run VACUUM ANALYZE on cleaned tables
    VACUUM ANALYZE pggit.history;
    
    -- Drop old partitions
    PERFORM pggit.drop_old_partitions();
END;
$$ LANGUAGE plpgsql;

-- Function to drop old partitions
CREATE OR REPLACE FUNCTION pggit.drop_old_partitions()
RETURNS INTEGER AS $$
DECLARE
    v_dropped INTEGER := 0;
    v_partition RECORD;
    v_retention_period INTERVAL;
BEGIN
    -- Get retention period for history
    SELECT retention_period INTO v_retention_period
    FROM pggit.retention_policies
    WHERE table_name = 'history' AND is_active = TRUE;
    
    -- Find and drop old partitions
    FOR v_partition IN
        SELECT 
            schemaname,
            tablename,
            -- Extract date from partition name (history_YYYY_MM)
            to_date(substring(tablename from 'history_(\d{4}_\d{2})'), 'YYYY_MM') as partition_date
        FROM pg_tables
        WHERE schemaname = 'pggit'
        AND tablename LIKE 'history_%'
        AND tablename ~ 'history_\d{4}_\d{2}$'
    LOOP
        IF v_partition.partition_date < CURRENT_DATE - v_retention_period THEN
            EXECUTE format('DROP TABLE %I.%I', 
                v_partition.schemaname, 
                v_partition.tablename
            );
            v_dropped := v_dropped + 1;
        END IF;
    END LOOP;
    
    RETURN v_dropped;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 3: Query Performance Optimizations
-- ============================================

-- Materialized view for frequently accessed object versions
CREATE MATERIALIZED VIEW IF NOT EXISTS pggit.object_versions_cached AS
SELECT 
    o.id,
    o.full_name,
    o.schema_name,
    o.object_name,
    o.object_type,
    o.version,
    o.version_major,
    o.version_minor,
    o.version_patch,
    o.created_at,
    o.updated_at,
    o.ddl_hash,
    h.latest_change_at,
    h.latest_change_type,
    h.change_count
FROM pggit.objects o
LEFT JOIN LATERAL (
    SELECT 
        MAX(created_at) as latest_change_at,
        (array_agg(change_type ORDER BY created_at DESC))[1] as latest_change_type,
        COUNT(*) as change_count
    FROM pggit.history
    WHERE object_id = o.id
) h ON true
WHERE o.is_active = TRUE;

CREATE UNIQUE INDEX idx_object_versions_cached_id ON pggit.object_versions_cached(id);
CREATE INDEX idx_object_versions_cached_name ON pggit.object_versions_cached(full_name);

-- Function to refresh materialized view
CREATE OR REPLACE FUNCTION pggit.refresh_cache()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY pggit.object_versions_cached;
END;
$$ LANGUAGE plpgsql;

-- Optimized version lookup
CREATE OR REPLACE FUNCTION pggit.get_version_fast(
    p_object_name TEXT
) RETURNS TABLE (
    version INTEGER,
    version_string TEXT,
    last_modified TIMESTAMP,
    change_count INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.version,
        o.version_major || '.' || o.version_minor || '.' || o.version_patch as version_string,
        o.latest_change_at as last_modified,
        o.change_count::INTEGER
    FROM pggit.object_versions_cached o
    WHERE o.full_name = p_object_name;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================
-- PART 4: Connection Pooling for Event Triggers
-- ============================================

-- Event trigger performance tracking
CREATE TABLE IF NOT EXISTS pggit.trigger_performance (
    id BIGSERIAL PRIMARY KEY,
    trigger_name TEXT NOT NULL,
    execution_time_ms NUMERIC NOT NULL,
    object_type TEXT,
    object_name TEXT,
    success BOOLEAN DEFAULT TRUE,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_trigger_performance_time ON pggit.trigger_performance(recorded_at DESC);

-- Optimized event trigger with performance tracking
CREATE OR REPLACE FUNCTION pggit.handle_ddl_command_optimized()
RETURNS event_trigger AS $$
DECLARE
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_obj RECORD;
    v_object_id INTEGER;
    v_execution_ms NUMERIC;
BEGIN
    v_start_time := clock_timestamp();
    
    -- Process with minimal overhead
    FOR v_obj IN 
        SELECT * FROM pg_event_trigger_ddl_commands()
        WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    LOOP
        BEGIN
            -- Quick existence check
            SELECT id INTO v_object_id
            FROM pggit.objects
            WHERE schema_name = v_obj.schema_name
            AND object_name = v_obj.object_identity
            AND object_type = v_obj.object_type::pggit.object_type;
            
            IF NOT FOUND THEN
                -- New object - quick insert
                INSERT INTO pggit.objects (
                    schema_name, object_name, full_name, object_type
                ) VALUES (
                    v_obj.schema_name,
                    v_obj.object_identity,
                    v_obj.schema_name || '.' || v_obj.object_identity,
                    v_obj.object_type::pggit.object_type
                ) RETURNING id INTO v_object_id;
            END IF;
            
            -- Quick version bump
            UPDATE pggit.objects
            SET version = version + 1,
                version_minor = version_minor + 1,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = v_object_id;
            
            -- Minimal history entry
            INSERT INTO pggit.history (
                object_id, version, change_type, ddl_command
            ) VALUES (
                v_object_id,
                (SELECT version FROM pggit.objects WHERE id = v_object_id),
                v_obj.command_tag,
                current_query()
            );
            
        EXCEPTION WHEN OTHERS THEN
            -- Log error but don't fail the DDL
            INSERT INTO pggit.trigger_errors (
                error_message, error_detail, trigger_name
            ) VALUES (
                SQLERRM, SQLSTATE, 'handle_ddl_command_optimized'
            );
        END;
    END LOOP;
    
    -- Record performance
    v_end_time := clock_timestamp();
    v_execution_ms := EXTRACT(MILLISECOND FROM (v_end_time - v_start_time));
    
    IF v_execution_ms > 10 THEN  -- Only log slow executions
        INSERT INTO pggit.trigger_performance (
            trigger_name, execution_time_ms
        ) VALUES (
            'handle_ddl_command_optimized', v_execution_ms
        );
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 5: Batch Operations
-- ============================================

-- Batch dependency detection
CREATE OR REPLACE FUNCTION pggit.detect_dependencies_batch()
RETURNS TABLE (
    dependency_type TEXT,
    dependencies_found INTEGER,
    execution_time_ms NUMERIC
) AS $$
DECLARE
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_count INTEGER;
BEGIN
    -- Foreign keys (bulk insert)
    v_start_time := clock_timestamp();
    
    WITH new_deps AS (
        INSERT INTO pggit.dependencies (
            dependent_object_id,
            referenced_object_id,
            dependency_type,
            constraint_name
        )
        SELECT DISTINCT
            child_obj.id,
            parent_obj.id,
            'foreign_key'::pggit.dependency_type,
            con.conname
        FROM pg_constraint con
        JOIN pggit.objects child_obj ON (
            child_obj.schema_name = n1.nspname AND
            child_obj.object_name = c1.relname
        )
        JOIN pggit.objects parent_obj ON (
            parent_obj.schema_name = n2.nspname AND
            parent_obj.object_name = c2.relname
        )
        JOIN pg_class c1 ON c1.oid = con.conrelid
        JOIN pg_namespace n1 ON n1.oid = c1.relnamespace
        JOIN pg_class c2 ON c2.oid = con.confrelid
        JOIN pg_namespace n2 ON n2.oid = c2.relnamespace
        WHERE con.contype = 'f'
        ON CONFLICT (dependent_object_id, referenced_object_id, dependency_type) 
        DO NOTHING
        RETURNING 1
    )
    SELECT COUNT(*) INTO v_count FROM new_deps;
    
    v_end_time := clock_timestamp();
    
    RETURN QUERY
    SELECT 
        'foreign_keys'::TEXT,
        v_count,
        EXTRACT(MILLISECOND FROM (v_end_time - v_start_time))::NUMERIC;
    
    -- Add other dependency types with similar batch approach
    -- Views, Functions, Triggers, etc.
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 6: Background Maintenance Jobs
-- ============================================

-- Job scheduler table
CREATE TABLE IF NOT EXISTS pggit.maintenance_jobs (
    job_name TEXT PRIMARY KEY,
    last_run TIMESTAMP,
    next_run TIMESTAMP,
    run_interval INTERVAL,
    is_active BOOLEAN DEFAULT TRUE,
    last_status TEXT,
    last_duration INTERVAL
);

-- Schedule default jobs
INSERT INTO pggit.maintenance_jobs (job_name, run_interval, next_run)
VALUES 
    ('partition_maintenance', '1 day', CURRENT_TIMESTAMP),
    ('cache_refresh', '1 hour', CURRENT_TIMESTAMP),
    ('cleanup_old_data', '1 week', CURRENT_TIMESTAMP),
    ('dependency_detection', '1 day', CURRENT_TIMESTAMP),
    ('performance_analysis', '1 day', CURRENT_TIMESTAMP)
ON CONFLICT (job_name) DO NOTHING;

-- Master maintenance function
CREATE OR REPLACE FUNCTION pggit.run_maintenance()
RETURNS TABLE (
    job_name TEXT,
    status TEXT,
    duration INTERVAL,
    details TEXT
) AS $$
DECLARE
    v_job RECORD;
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_status TEXT;
    v_details TEXT;
BEGIN
    FOR v_job IN 
        SELECT * FROM pggit.maintenance_jobs
        WHERE is_active = TRUE
        AND next_run <= CURRENT_TIMESTAMP
    LOOP
        v_start_time := clock_timestamp();
        v_status := 'completed';
        v_details := '';
        
        BEGIN
            CASE v_job.job_name
                WHEN 'partition_maintenance' THEN
                    v_details := 'Created ' || pggit.create_history_partitions(3) || ' partitions';
                    
                WHEN 'cache_refresh' THEN
                    PERFORM pggit.refresh_cache();
                    v_details := 'Cache refreshed';
                    
                WHEN 'cleanup_old_data' THEN
                    v_details := 'Cleaned: ' || (
                        SELECT string_agg(
                            t.table_name || ' (' || t.rows_deleted || ' rows)', 
                            ', '
                        )
                        FROM pggit.cleanup_old_data() t
                    );
                    
                WHEN 'dependency_detection' THEN
                    v_details := 'Detected: ' || (
                        SELECT string_agg(
                            d.dependency_type || ' (' || d.dependencies_found || ')',
                            ', '
                        )
                        FROM pggit.detect_dependencies_batch() d
                    );
                    
                WHEN 'performance_analysis' THEN
                    -- Clean up old performance data
                    DELETE FROM pggit.trigger_performance
                    WHERE recorded_at < CURRENT_TIMESTAMP - INTERVAL '7 days';
                    v_details := 'Performance data cleaned';
            END CASE;
            
        EXCEPTION WHEN OTHERS THEN
            v_status := 'failed';
            v_details := SQLERRM;
        END;
        
        v_end_time := clock_timestamp();
        
        -- Update job record
        UPDATE pggit.maintenance_jobs
        SET last_run = v_start_time,
            next_run = v_start_time + run_interval,
            last_status = v_status,
            last_duration = v_end_time - v_start_time
        WHERE job_name = v_job.job_name;
        
        RETURN QUERY
        SELECT 
            v_job.job_name,
            v_status,
            v_end_time - v_start_time,
            v_details;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 7: Performance Monitoring Views
-- ============================================

-- Overall system health
CREATE OR REPLACE VIEW pggit.system_health AS
SELECT 
    'Total Objects' as metric,
    COUNT(*)::text as value,
    'count' as unit
FROM pggit.objects
WHERE is_active = TRUE
UNION ALL
SELECT 
    'History Size',
    pg_size_pretty(pg_total_relation_size('pggit.history'))::text,
    'size'
UNION ALL
SELECT 
    'Average Trigger Time (ms)',
    ROUND(AVG(execution_time_ms)::numeric, 2)::text,
    'milliseconds'
FROM pggit.trigger_performance
WHERE recorded_at > CURRENT_TIMESTAMP - INTERVAL '1 hour'
UNION ALL
SELECT 
    'Cache Age',
    COALESCE(
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - 
            (SELECT MAX(updated_at) FROM pggit.object_versions_cached)
        ))::text || ' seconds',
        'Never refreshed'
    ),
    'age';

COMMENT ON FUNCTION pggit.create_history_partitions IS 'Creates monthly partitions for history table';
COMMENT ON FUNCTION pggit.cleanup_old_data IS 'Archives and removes old data based on retention policies';
COMMENT ON FUNCTION pggit.run_maintenance IS 'Runs all scheduled maintenance jobs';
COMMENT ON VIEW pggit.system_health IS 'Overview of system performance and health metrics';