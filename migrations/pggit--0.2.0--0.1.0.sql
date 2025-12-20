-- pgGit Downgrade Script: 0.2.0 → 0.1.0
-- This script safely downgrades pgGit from version 0.2.0 to 0.1.0
-- Run with: psql -f migrations/pggit--0.2.0--0.1.0.sql

BEGIN;

-- Record downgrade start
DO $$
BEGIN
    INSERT INTO pggit.upgrade_log (from_version, to_version, status)
    VALUES ('0.2.0', '0.1.0', 'in_progress');

    RAISE NOTICE 'Starting pgGit downgrade from 0.2.0 to 0.1.0';
END $$;

-- Remove 0.2.0 features (safe rollback)
DO $$
DECLARE
    v_error TEXT;
BEGIN
    RAISE NOTICE 'Removing 0.2.0 features...';

    -- Drop new table (with CASCADE to remove indexes)
    DROP TABLE IF EXISTS pggit.performance_metrics CASCADE;

    -- Remove new columns (safe - they have defaults)
    ALTER TABLE pggit.objects DROP COLUMN IF EXISTS tags;
    ALTER TABLE pggit.objects DROP COLUMN IF EXISTS description;
    ALTER TABLE pggit.history DROP COLUMN IF EXISTS performance_impact;
    ALTER TABLE pggit.history DROP COLUMN IF EXISTS operation_metadata;

    -- Drop new indexes
    DROP INDEX IF EXISTS pggit.idx_history_created_at;
    DROP INDEX IF EXISTS pggit.idx_objects_schema_name;

    -- Restore version function
    CREATE OR REPLACE FUNCTION pggit.version() RETURNS TEXT AS $$
        SELECT '0.1.0'::TEXT;
    $$ LANGUAGE sql IMMUTABLE;

    RAISE NOTICE 'Features removed successfully';

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    RAISE EXCEPTION 'Feature removal failed: %', v_error;
END $$;

-- Mark downgrade as completed
DO $$
BEGIN
    UPDATE pggit.upgrade_log
    SET status = 'completed', completed_at = CURRENT_TIMESTAMP
    WHERE from_version = '0.2.0' AND to_version = '0.1.0' AND status = 'in_progress';

    RAISE NOTICE 'pgGit successfully downgraded to version 0.1.0';
    RAISE NOTICE '⚠️  Some 0.2.0 features have been removed. Backup data is preserved in backup schemas.';
END $$;

COMMIT;

-- Verification
DO $$
DECLARE
    v_version TEXT;
BEGIN
    SELECT pggit.version() INTO v_version;
    IF v_version != '0.1.0' THEN
        RAISE EXCEPTION 'Downgrade verification failed: expected 0.1.0, got %', v_version;
    END IF;

    RAISE NOTICE '✅ Downgrade verification successful!';
    RAISE NOTICE '   Version: %', v_version;
END $$;