-- pgGit Upgrade Script: 0.1.0 → 0.2.0
-- This script safely upgrades pgGit from version 0.1.0 to 0.2.0
-- Run with: psql -f migrations/pggit--0.1.0--0.2.0.sql

BEGIN;

-- Record upgrade start
DO $$
DECLARE
    current_upgrade_id UUID;
BEGIN
    -- Create upgrade log table if it doesn't exist
    CREATE TABLE IF NOT EXISTS pggit.upgrade_log (
        upgrade_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        from_version TEXT NOT NULL,
        to_version TEXT NOT NULL,
        started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        completed_at TIMESTAMP,
        status TEXT CHECK (status IN ('in_progress', 'completed', 'failed', 'rolled_back')),
        error_message TEXT
    );

    -- Record upgrade start
    INSERT INTO pggit.upgrade_log (from_version, to_version, status)
    VALUES ('0.1.0', '0.2.0', 'in_progress')
    RETURNING upgrade_id INTO current_upgrade_id;

    -- Store upgrade ID for later use
    PERFORM set_config('pggit.upgrade_id', current_upgrade_id::TEXT, FALSE);

    RAISE NOTICE 'Starting pgGit upgrade from 0.1.0 to 0.2.0 (ID: %)', current_upgrade_id;
END $$;

-- Backup existing data
DO $$
DECLARE
    backup_schema_name TEXT;
    upgrade_id TEXT;
BEGIN
    upgrade_id := current_setting('pggit.upgrade_id');
    backup_schema_name := 'pggit_backup_' || upgrade_id;

    RAISE NOTICE 'Creating backup schema: %', backup_schema_name;

    -- Create backup schema
    EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', backup_schema_name);

    -- Backup all existing tables
    EXECUTE format('CREATE TABLE %I.objects AS SELECT * FROM pggit.objects', backup_schema_name);
    EXECUTE format('CREATE TABLE %I.history AS SELECT * FROM pggit.history', backup_schema_name);

    RAISE NOTICE 'Backup completed successfully';
END $$;

-- Schema changes
DO $$
DECLARE
    v_error TEXT;
BEGIN
    RAISE NOTICE 'Applying schema changes...';

    -- Add new columns to objects table
    ALTER TABLE pggit.objects ADD COLUMN IF NOT EXISTS tags JSONB DEFAULT '[]'::jsonb;
    ALTER TABLE pggit.objects ADD COLUMN IF NOT EXISTS description TEXT;

    -- Add new columns to history table
    ALTER TABLE pggit.history ADD COLUMN IF NOT EXISTS performance_impact TEXT;
    ALTER TABLE pggit.history ADD COLUMN IF NOT EXISTS operation_metadata JSONB;

    -- Create new performance metrics table
    CREATE TABLE IF NOT EXISTS pggit.performance_metrics (
        metric_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        metric_type TEXT NOT NULL,
        metric_value NUMERIC NOT NULL,
        tags JSONB DEFAULT '{}'::jsonb,
        recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_perf_metrics_type_time
        ON pggit.performance_metrics(metric_type, recorded_at DESC);

    -- Add new indexes for performance
    CREATE INDEX IF NOT EXISTS idx_history_created_at
        ON pggit.history(created_at DESC);

    CREATE INDEX IF NOT EXISTS idx_objects_schema_name
        ON pggit.objects(schema_name);

    -- Update existing data with safe defaults
    UPDATE pggit.objects SET tags = '[]'::jsonb WHERE tags IS NULL;

    -- Create new version function
    CREATE OR REPLACE FUNCTION pggit.version() RETURNS TEXT AS $$
        SELECT '0.2.0'::TEXT;
    $$ LANGUAGE sql IMMUTABLE;

    RAISE NOTICE 'Schema changes applied successfully';

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    RAISE EXCEPTION 'Schema upgrade failed: %', v_error;
END $$;

-- Mark upgrade as completed
DO $$
DECLARE
    upgrade_id TEXT;
BEGIN
    upgrade_id := current_setting('pggit.upgrade_id');

    UPDATE pggit.upgrade_log
    SET status = 'completed', completed_at = CURRENT_TIMESTAMP
    WHERE upgrade_id = upgrade_id::UUID;

    RAISE NOTICE 'pgGit successfully upgraded to version 0.2.0';
END $$;

COMMIT;

-- Verification
DO $$
DECLARE
    v_version TEXT;
    v_object_count INTEGER;
    v_history_count INTEGER;
BEGIN
    SELECT pggit.version() INTO v_version;
    IF v_version != '0.2.0' THEN
        RAISE EXCEPTION 'Upgrade verification failed: expected 0.2.0, got %', v_version;
    END IF;

    SELECT COUNT(*) INTO v_object_count FROM pggit.objects;
    SELECT COUNT(*) INTO v_history_count FROM pggit.history;

    RAISE NOTICE '✅ Upgrade verification successful!';
    RAISE NOTICE '   Version: %', v_version;
    RAISE NOTICE '   Objects: %', v_object_count;
    RAISE NOTICE '   History records: %', v_history_count;
END $$;