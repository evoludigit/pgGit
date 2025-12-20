-- pgGit Migration: 0.1.0 → 0.2.0
-- Upgrade script from version 0.1.0 to 0.2.0

BEGIN;

-- Record upgrade start
CREATE TABLE IF NOT EXISTS pggit.upgrade_log (
    upgrade_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_version TEXT NOT NULL,
    to_version TEXT NOT NULL,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    status TEXT CHECK (status IN ('in_progress', 'completed', 'failed', 'rolled_back')),
    error_message TEXT
);

INSERT INTO pggit.upgrade_log (from_version, to_version, status)
VALUES ('0.1.0', '0.2.0', 'in_progress')
RETURNING upgrade_id AS current_upgrade_id \gset

-- Backup existing data
CREATE SCHEMA IF NOT EXISTS pggit_backup_:current_upgrade_id;
CREATE TABLE pggit_backup_:current_upgrade_id.objects AS SELECT * FROM pggit.objects;
CREATE TABLE pggit_backup_:current_upgrade_id.history AS SELECT * FROM pggit.history;

-- Schema changes
DO $upgrade$
DECLARE
    v_error TEXT;
BEGIN
    -- Add new columns
    ALTER TABLE pggit.objects ADD COLUMN IF NOT EXISTS tags JSONB DEFAULT '[]'::jsonb;
    ALTER TABLE pggit.history ADD COLUMN IF NOT EXISTS performance_impact TEXT;

    -- Create new tables
    CREATE TABLE IF NOT EXISTS pggit.performance_metrics (
        metric_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        metric_type TEXT NOT NULL,
        metric_value NUMERIC NOT NULL,
        tags JSONB DEFAULT '{}'::jsonb,
        recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    -- Add new indexes
    CREATE INDEX IF NOT EXISTS idx_history_performance
        ON pggit.history(change_type, created_at DESC);

    -- Update existing data
    UPDATE pggit.objects SET tags = '[]'::jsonb WHERE tags IS NULL;

    -- Version update
    CREATE OR REPLACE FUNCTION pggit.version() RETURNS TEXT AS $$
        SELECT '0.2.0'::TEXT;
    $$ LANGUAGE sql IMMUTABLE;

    -- Mark upgrade as completed
    UPDATE pggit.upgrade_log
    SET status = 'completed', completed_at = CURRENT_TIMESTAMP
    WHERE upgrade_id = :current_upgrade_id;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;

    -- Mark upgrade as failed
    UPDATE pggit.upgrade_log
    SET status = 'failed', error_message = v_error, completed_at = CURRENT_TIMESTAMP
    WHERE upgrade_id = :current_upgrade_id;

    RAISE EXCEPTION 'Upgrade failed: %', v_error;
END $upgrade$;

COMMIT;

-- Verification
DO $verify$
DECLARE
    v_version TEXT;
BEGIN
    SELECT pggit.version() INTO v_version;
    IF v_version != '0.2.0' THEN
        RAISE EXCEPTION 'Upgrade verification failed: expected 0.2.0, got %', v_version;
    END IF;

    RAISE NOTICE '✅ Successfully upgraded to version %', v_version;
END $verify$;