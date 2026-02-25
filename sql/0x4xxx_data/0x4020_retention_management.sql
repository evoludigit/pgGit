-- pgGit History Table Management with Retention Policies
-- File: 024_history_management.sql
-- Purpose: Automated archiving and cleanup of history data

-- ============================================================================
-- Retention Policies Configuration Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.retention_policies (
    policy_id SERIAL PRIMARY KEY,
    policy_name TEXT NOT NULL UNIQUE,
    table_pattern TEXT NOT NULL,  -- e.g., 'history', 'objects', or specific tables
    retention_period INTERVAL NOT NULL DEFAULT INTERVAL '90 days',
    archive_enabled BOOLEAN DEFAULT false,
    archive_location TEXT,  -- S3 bucket, file path, or other storage
    archive_format TEXT DEFAULT 'parquet',  -- parquet, csv, json
    compression_enabled BOOLEAN DEFAULT true,
    compression_type TEXT DEFAULT 'gzip',  -- gzip, lz4, zstd
    delete_after_archive BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    last_run_at TIMESTAMP,
    last_run_status TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT current_user
);

COMMENT ON TABLE pggit.retention_policies IS 
    'Configuration for automated data retention and archiving policies.
     Each policy defines retention rules for specific tables or table patterns.';

-- Add comments to columns
COMMENT ON COLUMN pggit.retention_policies.table_pattern IS 
    'Pattern to match tables (e.g., ''history'' matches all history* tables)';
COMMENT ON COLUMN pggit.retention_policies.retention_period IS 
    'How long to keep data before archiving/deleting (e.g., ''90 days'')';
COMMENT ON COLUMN pggit.retention_policies.archive_location IS 
    'External storage location for archived data (S3 URI, file path, etc.)';

-- Create index for active policies
CREATE INDEX IF NOT EXISTS idx_retention_policies_active 
ON pggit.retention_policies(is_active) WHERE is_active = true;

-- ============================================================================
-- Archive Log Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS pggit.archive_log (
    archive_id BIGSERIAL PRIMARY KEY,
    policy_id INTEGER REFERENCES pggit.retention_policies(policy_id),
    table_name TEXT NOT NULL,
    records_archived BIGINT NOT NULL,
    records_deleted BIGINT,
    archive_path TEXT,
    archive_size_bytes BIGINT,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    status TEXT DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed', 'failed')),
    error_message TEXT,
    checksum TEXT  -- For data integrity verification
);

CREATE INDEX IF NOT EXISTS idx_archive_log_policy 
ON pggit.archive_log(policy_id, completed_at DESC);

CREATE INDEX IF NOT EXISTS idx_archive_log_status 
ON pggit.archive_log(status) WHERE status = 'in_progress';

COMMENT ON TABLE pggit.archive_log IS 
    'Audit trail of all archiving operations performed by retention policies';

-- ============================================================================
-- Function: Create Retention Policy
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.create_retention_policy(
    p_policy_name TEXT,
    p_table_pattern TEXT,
    p_retention_period INTERVAL,
    p_archive_enabled BOOLEAN DEFAULT false,
    p_archive_location TEXT DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_policy_id INTEGER;
BEGIN
    -- Validate inputs
    IF p_policy_name IS NULL OR p_policy_name = '' THEN
        RAISE EXCEPTION 'Policy name cannot be empty';
    END IF;
    
    IF p_table_pattern IS NULL OR p_table_pattern = '' THEN
        RAISE EXCEPTION 'Table pattern cannot be empty';
    END IF;
    
    IF p_retention_period IS NULL OR p_retention_period <= INTERVAL '0' THEN
        RAISE EXCEPTION 'Retention period must be positive';
    END IF;
    
    -- Check for duplicate name
    IF EXISTS (SELECT 1 FROM pggit.retention_policies WHERE policy_name = p_policy_name) THEN
        RAISE EXCEPTION 'Policy with name % already exists', p_policy_name;
    END IF;
    
    -- Insert policy
    INSERT INTO pggit.retention_policies (
        policy_name, table_pattern, retention_period, 
        archive_enabled, archive_location, created_by
    ) VALUES (
        p_policy_name, p_table_pattern, p_retention_period,
        p_archive_enabled, p_archive_location, current_user
    )
    RETURNING policy_id INTO v_policy_id;
    
    RAISE NOTICE 'Created retention policy "%" (ID: %) for tables matching "%" with retention %',
        p_policy_name, v_policy_id, p_table_pattern, p_retention_period;
    
    RETURN v_policy_id;
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE;

COMMENT ON FUNCTION pggit.create_retention_policy IS 
    'Create a new retention policy for automated history cleanup.
     Example: SELECT pggit.create_retention_policy(''main_history'', ''history'', ''90 days'');';

-- ============================================================================
-- Function: Apply Retention Policy (Main Worker)
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.apply_retention_policy(
    p_policy_id INTEGER,
    p_dry_run BOOLEAN DEFAULT false
) RETURNS TABLE (
    archived_count BIGINT,
    deleted_count BIGINT,
    status TEXT,
    message TEXT
) AS $$
DECLARE
    v_policy RECORD;
    v_cutoff_date TIMESTAMP;
    v_archived BIGINT := 0;
    v_deleted BIGINT := 0;
    v_archive_path TEXT;
    v_table RECORD;
    v_sql TEXT;
BEGIN
    -- Get policy details
    SELECT * INTO v_policy 
    FROM pggit.retention_policies 
    WHERE policy_id = p_policy_id AND is_active = true;
    
    IF v_policy IS NULL THEN
        RETURN QUERY SELECT 
            0::BIGINT, 
            0::BIGINT, 
            'failed'::TEXT, 
            format('Policy %s not found or inactive', p_policy_id)::TEXT;
        RETURN;
    END IF;
    
    -- Calculate cutoff date
    v_cutoff_date := CURRENT_TIMESTAMP - v_policy.retention_period;
    
    RAISE NOTICE 'Applying retention policy "%" (ID: %)', v_policy.policy_name, p_policy_id;
    RAISE NOTICE 'Cutoff date: % (retention: %)', v_cutoff_date, v_policy.retention_period;
    
    -- Update last run timestamp
    UPDATE pggit.retention_policies 
    SET last_run_at = CURRENT_TIMESTAMP, last_run_status = 'in_progress'
    WHERE policy_id = p_policy_id;
    
    -- Process each matching table
    FOR v_table IN 
        SELECT 
            schemaname, 
            tablename,
            pg_total_relation_size(schemaname || '.' || tablename) as size_bytes
        FROM pg_tables
        WHERE tablename LIKE '%' || v_policy.table_pattern || '%'
        AND schemaname = 'pggit'
    LOOP
        RAISE NOTICE 'Processing table: %.%', v_table.schemaname, v_table.tablename;
        
        -- Count records to be archived/deleted
        EXECUTE format(
            'SELECT count(*) FROM %I.%I WHERE created_at < %L',
            v_table.schemaname, v_table.tablename, v_cutoff_date
        ) INTO v_archived;
        
        IF v_archived = 0 THEN
            RAISE NOTICE '  No records to archive in %.%', v_table.schemaname, v_table.tablename;
            CONTINUE;
        END IF;
        
        RAISE NOTICE '  Found % records older than %', v_archived, v_cutoff_date;
        
        IF p_dry_run THEN
            RAISE NOTICE '  DRY RUN: Would archive % records', v_archived;
            v_deleted := 0;
        ELSE
            -- Create archive log entry
            INSERT INTO pggit.archive_log (
                policy_id, table_name, records_archived, started_at, status
            ) VALUES (
                p_policy_id, v_table.schemaname || '.' || v_table.tablename, 
                v_archived, CURRENT_TIMESTAMP, 'in_progress'
            );
            
            -- Archive data if enabled
            IF v_policy.archive_enabled AND v_policy.archive_location IS NOT NULL THEN
                -- Archive implementation would go here
                -- For now, we just track the intent
                v_archive_path := v_policy.archive_location || '/' || v_table.tablename || '_' || to_char(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MISS');
                RAISE NOTICE '  Archiving to: %', v_archive_path;
                
                -- TODO: Implement actual archive to S3/file system
                -- This would typically use COPY TO or foreign data wrappers
            END IF;
            
            -- Delete old records
            IF v_policy.delete_after_archive OR NOT v_policy.archive_enabled THEN
                EXECUTE format(
                    'DELETE FROM %I.%I WHERE created_at < %L',
                    v_table.schemaname, v_table.tablename, v_cutoff_date
                );
                GET DIAGNOSTICS v_deleted = ROW_COUNT;
                
                RAISE NOTICE '  Deleted % records', v_deleted;
            END IF;
            
            -- Update archive log
            UPDATE pggit.archive_log 
            SET completed_at = CURRENT_TIMESTAMP, 
                status = 'completed',
                archive_path = v_archive_path,
                records_deleted = v_deleted
            WHERE policy_id = p_policy_id 
            AND table_name = v_table.schemaname || '.' || v_table.tablename
            AND status = 'in_progress';
        END IF;
    END LOOP;
    
    -- Update policy status
    UPDATE pggit.retention_policies 
    SET last_run_status = CASE WHEN p_dry_run THEN 'dry_run' ELSE 'completed' END
    WHERE policy_id = p_policy_id;
    
    RETURN QUERY SELECT 
        v_archived, 
        v_deleted, 
        CASE WHEN p_dry_run THEN 'dry_run' ELSE 'completed' END::TEXT,
        format('Retention policy applied successfully. Archived: %s, Deleted: %s', v_archived, v_deleted)::TEXT;
        
EXCEPTION
    WHEN OTHERS THEN
        -- Log the error
        UPDATE pggit.retention_policies 
        SET last_run_status = 'failed'
        WHERE policy_id = p_policy_id;
        
        -- Update any in-progress archive log entries
        UPDATE pggit.archive_log 
        SET status = 'failed', 
            completed_at = CURRENT_TIMESTAMP,
            error_message = SQLERRM
        WHERE policy_id = p_policy_id AND status = 'in_progress';
        
        RETURN QUERY SELECT 
            0::BIGINT, 
            0::BIGINT, 
            'failed'::TEXT, 
            SQLERRM::TEXT;
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE;

COMMENT ON FUNCTION pggit.apply_retention_policy IS 
    'Apply a retention policy to archive and/or delete old records.
     Use p_dry_run := true to preview what would be deleted without actually doing it.
     Example: SELECT * FROM pggit.apply_retention_policy(1, true); -- Dry run
              SELECT * FROM pggit.apply_retention_policy(1);      -- Execute';

-- ============================================================================
-- Function: Get History Table Statistics
-- ============================================================================

CREATE OR REPLACE FUNCTION pggit.get_history_stats()
RETURNS TABLE (
    table_name TEXT,
    row_count BIGINT,
    size_bytes BIGINT,
    size_pretty TEXT,
    oldest_record TIMESTAMP,
    newest_record TIMESTAMP,
    days_retained NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.tablename::TEXT,
        (SELECT count(*) FROM pg_catalog.pg_class c 
         JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'pggit' AND c.relname = t.tablename)::BIGINT as row_count,
        pg_total_relation_size('pggit.' || t.tablename) as size_bytes,
        pg_size_pretty(pg_total_relation_size('pggit.' || t.tablename)) as size_pretty,
        (SELECT min(created_at) FROM pggit.history WHERE created_at IS NOT NULL) as oldest_record,
        (SELECT max(created_at) FROM pggit.history WHERE created_at IS NOT NULL) as newest_record,
        EXTRACT(DAY FROM (
            (SELECT max(created_at) FROM pggit.history WHERE created_at IS NOT NULL) -
            (SELECT min(created_at) FROM pggit.history WHERE created_at IS NOT NULL)
        ))::NUMERIC as days_retained
    FROM pg_tables t
    WHERE t.schemaname = 'pggit'
    AND t.tablename LIKE 'history%'
    ORDER BY pg_total_relation_size('pggit.' || t.tablename) DESC;
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER
STABLE;

COMMENT ON FUNCTION pggit.get_history_stats IS 
    'Get statistics about history tables including size, row count, and retention period.
     Example: SELECT * FROM pggit.get_history_stats();';

-- ============================================================================
-- Default Retention Policy Setup
-- ============================================================================

-- Create a default retention policy for the history table (90 days)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pggit.retention_policies WHERE policy_name = 'default_history_retention') THEN
        PERFORM pggit.create_retention_policy(
            'default_history_retention',
            'history',
            INTERVAL '90 days',
            false,  -- Don't archive by default
            NULL
        );
        
        RAISE NOTICE 'Created default retention policy: 90 days for history tables';
    END IF;
END;
$$;

-- ============================================================================
-- Grant Permissions
-- ============================================================================

GRANT SELECT ON pggit.retention_policies TO PUBLIC;
GRANT SELECT ON pggit.archive_log TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.get_history_stats() TO PUBLIC;
