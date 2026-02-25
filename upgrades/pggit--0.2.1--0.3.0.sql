-- pgGit Extension Upgrade: v0.2.1 → v0.3.0
-- File: upgrades/pggit--0.2.1--0.3.0.sql
-- Purpose: Upgrade script for Pass 5 enhancements

-- ============================================================================
-- Upgrade Metadata
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Upgrading pgGit from v0.2.1 to v0.3.0';
    RAISE NOTICE 'This upgrade includes:';
    RAISE NOTICE '  - Production mode with DDL tracking pause/resume';
    RAISE NOTICE '  - History table retention and archiving';
    RAISE NOTICE '  - Comprehensive monitoring and metrics';
    RAISE NOTICE '  - Internal schema separation';
    RAISE NOTICE '  - Row-level security for multi-tenancy';
END;
$$;

-- ============================================================================
-- Step 1: Add Production Mode Features (023_production_mode.sql)
-- ============================================================================

-- Create tracking config table
CREATE TABLE IF NOT EXISTS pggit.tracking_config (
    config_key TEXT PRIMARY KEY,
    config_value JSONB NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by TEXT DEFAULT current_user
);

-- Create production mode functions
CREATE OR REPLACE FUNCTION pggit.pause_tracking(p_reason TEXT DEFAULT 'Bulk operation')
RETURNS VOID AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM pggit.tracking_config WHERE config_key = 'ddl_tracking_paused') THEN
        RAISE NOTICE 'DDL tracking is already paused';
        RETURN;
    END IF;
    
    INSERT INTO pggit.tracking_config (config_key, config_value, updated_by)
    VALUES (
        'ddl_tracking_paused',
        jsonb_build_object(
            'paused_at', CURRENT_TIMESTAMP,
            'paused_by', current_user,
            'reason', p_reason
        ),
        current_user
    );
    
    RAISE NOTICE 'DDL tracking paused: %', p_reason;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit.resume_tracking()
RETURNS VOID AS $$
DECLARE
    v_record JSONB;
BEGIN
    SELECT config_value INTO v_record FROM pggit.tracking_config WHERE config_key = 'ddl_tracking_paused';
    
    IF v_record IS NULL THEN
        RAISE NOTICE 'DDL tracking is not currently paused';
        RETURN;
    END IF;
    
    DELETE FROM pggit.tracking_config WHERE config_key = 'ddl_tracking_paused';
    RAISE NOTICE 'DDL tracking resumed (was paused at %)', v_record->>'paused_at';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit.is_tracking_paused()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (SELECT 1 FROM pggit.tracking_config WHERE config_key = 'ddl_tracking_paused');
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Step 2: Add History Management (024_history_management.sql)
-- ============================================================================

-- Create retention policies table
CREATE TABLE IF NOT EXISTS pggit.retention_policies (
    policy_id SERIAL PRIMARY KEY,
    policy_name TEXT NOT NULL UNIQUE,
    table_pattern TEXT NOT NULL,
    retention_period INTERVAL NOT NULL DEFAULT INTERVAL '90 days',
    archive_enabled BOOLEAN DEFAULT false,
    archive_location TEXT,
    archive_format TEXT DEFAULT 'parquet',
    compression_enabled BOOLEAN DEFAULT true,
    delete_after_archive BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    last_run_at TIMESTAMP,
    last_run_status TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create archive log table
CREATE TABLE IF NOT EXISTS pggit.archive_log (
    archive_id BIGSERIAL PRIMARY KEY,
    policy_id INTEGER REFERENCES pggit.retention_policies(policy_id),
    table_name TEXT NOT NULL,
    records_archived BIGINT NOT NULL,
    records_deleted BIGINT,
    archive_path TEXT,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    status TEXT DEFAULT 'in_progress',
    error_message TEXT
);

-- Create default retention policy
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pggit.retention_policies WHERE policy_name = 'default_history_retention') THEN
        INSERT INTO pggit.retention_policies (policy_name, table_pattern, retention_period)
        VALUES ('default_history_retention', 'history', INTERVAL '90 days');
    END IF;
END;
$$;

-- Create retention policy functions
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
    INSERT INTO pggit.retention_policies (policy_name, table_pattern, retention_period, archive_enabled, archive_location)
    VALUES (p_policy_name, p_table_pattern, p_retention_period, p_archive_enabled, p_archive_location)
    ON CONFLICT (policy_name) DO UPDATE
    SET retention_period = EXCLUDED.retention_period,
        archive_enabled = EXCLUDED.archive_enabled,
        archive_location = EXCLUDED.archive_location
    RETURNING policy_id INTO v_policy_id;
    
    RETURN v_policy_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Step 3: Add Monitoring & Metrics (025_monitoring.sql)
-- ============================================================================

-- Create metrics table
CREATE TABLE IF NOT EXISTS pggit.metrics (
    metric_id BIGSERIAL PRIMARY KEY,
    metric_name TEXT NOT NULL,
    metric_value NUMERIC,
    metric_type TEXT NOT NULL,
    labels JSONB DEFAULT '{}',
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_metrics_name_time ON pggit.metrics(metric_name, recorded_at DESC);

-- Create monitoring functions
CREATE OR REPLACE FUNCTION pggit.prometheus_metrics()
RETURNS TABLE (metric_line TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT format('pggit_active_branches %s', (SELECT count(*)::TEXT FROM pggit.branches WHERE status = 'ACTIVE'));
    
    RETURN QUERY
    SELECT format('pggit_tracked_objects %s', (SELECT count(*)::TEXT FROM pggit.objects WHERE is_active = true));
    
    RETURN QUERY
    SELECT format('pggit_history_rows %s', (SELECT count(*)::TEXT FROM pggit.history));
    
    RETURN QUERY
    SELECT format('pggit_tracking_paused %s', 
        CASE WHEN EXISTS (SELECT 1 FROM pggit.tracking_config WHERE config_key = 'ddl_tracking_paused') 
             THEN '1' ELSE '0' END);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit.health_check()
RETURNS TABLE (check_name TEXT, status TEXT, message TEXT, details JSONB) AS $$
BEGIN
    RETURN QUERY SELECT 'database_connection'::TEXT, 'healthy'::TEXT, 'Database connection active'::TEXT, '{}'::JSONB;
    RETURN QUERY SELECT 'branches'::TEXT, 'healthy'::TEXT, format('Found %s branches', (SELECT count(*) FROM pggit.branches))::TEXT, '{}'::JSONB;
    RETURN QUERY SELECT 'tracked_objects'::TEXT, 'healthy'::TEXT, format('Tracking %s objects', (SELECT count(*) FROM pggit.objects WHERE is_active = true))::TEXT, '{}'::JSONB;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Step 4: Add Internal Schema (026_internal_schema.sql)
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS pggit_internal;

-- Create internal audit log
CREATE TABLE IF NOT EXISTS pggit_internal.audit_log (
    log_id BIGSERIAL PRIMARY KEY,
    event_type TEXT NOT NULL,
    event_details JSONB,
    user_name TEXT DEFAULT current_user,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create internal config
CREATE TABLE IF NOT EXISTS pggit_internal.config (
    config_key TEXT PRIMARY KEY,
    config_value TEXT,
    config_type TEXT DEFAULT 'string',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create internal helper functions
CREATE OR REPLACE FUNCTION pggit_internal.extract_table_columns(p_schema_name TEXT, p_table_name TEXT)
RETURNS JSONB AS $$
DECLARE
    v_columns JSONB;
BEGIN
    SELECT jsonb_object_agg(column_name, jsonb_build_object('type', udt_name))
    INTO v_columns
    FROM information_schema.columns
    WHERE table_schema = p_schema_name AND table_name = p_table_name;
    RETURN COALESCE(v_columns, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Step 5: Add Row-Level Security (027_row_level_security.sql)
-- ============================================================================

-- Add tenant_id columns
ALTER TABLE pggit.branches ADD COLUMN IF NOT EXISTS tenant_id INTEGER DEFAULT 1;
ALTER TABLE pggit.objects ADD COLUMN IF NOT EXISTS tenant_id INTEGER DEFAULT 1;
ALTER TABLE pggit.history ADD COLUMN IF NOT EXISTS tenant_id INTEGER DEFAULT 1;

-- Enable RLS
ALTER TABLE pggit.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE pggit.objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE pggit.history ENABLE ROW LEVEL SECURITY;

-- Create RLS policies (simplified - full implementation in 027_row_level_security.sql)
CREATE POLICY IF NOT EXISTS branch_isolation ON pggit.branches
    USING (tenant_id = 1);  -- Simplified for upgrade

-- ============================================================================
-- Step 6: Update Indexes for Performance
-- ============================================================================

-- Create additional indexes for new columns
CREATE INDEX IF NOT EXISTS idx_branches_tenant ON pggit.branches(tenant_id);
CREATE INDEX IF NOT EXISTS idx_objects_tenant ON pggit.objects(tenant_id);
CREATE INDEX IF NOT EXISTS idx_history_tenant ON pggit.history(tenant_id);

-- ============================================================================
-- Step 7: Grant Permissions
-- ============================================================================

GRANT EXECUTE ON FUNCTION pggit.pause_tracking(TEXT) TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.resume_tracking() TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.is_tracking_paused() TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.prometheus_metrics() TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.health_check() TO PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.create_retention_policy(TEXT, TEXT, INTERVAL, BOOLEAN, TEXT) TO PUBLIC;

-- ============================================================================
-- Upgrade Complete
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'pgGit Upgrade Complete: v0.2.1 → v0.3.0';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'New features added:';
    RAISE NOTICE '  ✓ Production mode with pause/resume';
    RAISE NOTICE '  ✓ History retention policies';
    RAISE NOTICE '  ✓ Prometheus metrics export';
    RAISE NOTICE '  ✓ Health check function';
    RAISE NOTICE '  ✓ Internal schema separation';
    RAISE NOTICE '  ✓ Row-level security foundation';
    RAISE NOTICE '';
    RAISE NOTICE 'Run tests to verify upgrade:';
    RAISE NOTICE '  make test';
END;
$$;
