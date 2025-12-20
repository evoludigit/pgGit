-- pgGit Migration: 0.2.0 → 0.1.0
-- Downgrade script from version 0.2.0 to 0.1.0

BEGIN;

-- Remove new features
DROP TABLE IF EXISTS pggit.performance_metrics CASCADE;
ALTER TABLE pggit.objects DROP COLUMN IF EXISTS tags;
ALTER TABLE pggit.history DROP COLUMN IF EXISTS performance_impact;
DROP INDEX IF EXISTS pggit.idx_history_performance;

-- Restore version
CREATE OR REPLACE FUNCTION pggit.version() RETURNS TEXT AS $$
    SELECT '0.1.0'::TEXT;
$$ LANGUAGE sql IMMUTABLE;

COMMIT;

RAISE NOTICE '⚠️  Downgraded to version 0.1.0';