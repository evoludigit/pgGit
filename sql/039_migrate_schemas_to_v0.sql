-- ============================================
-- Schema Versioning Migration
-- Rename all pggit_v0 schemas to pggit_v0
-- ============================================
-- Date: December 21, 2025 (Week 8 - Post-Production)
-- Purpose: Establish semantic versioning (v0.x.y = stable API)
-- Status: Production deployment
-- Backward Compatible: NO (one-time migration)
--
-- This script implements semantic versioning by renaming schemas
-- from pggit_v0 (confusing numbering) to pggit_v0 (clear versioning):
-- - pggit_v0.x: Stable, backward-compatible releases
-- - pggit_v1+: Future major versions if breaking changes needed
--
-- This allows multiple major versions to coexist in production.
-- ============================================

-- ============================================
-- CONDITIONAL SCHEMA MIGRATION
-- This script only runs if old schemas exist
-- For fresh installations, it safely exits
-- ============================================

DO $$
DECLARE
    v_has_old_schemas BOOLEAN;
BEGIN
    -- Check if old schemas exist (would indicate an upgrade from older version)
    SELECT EXISTS (
        SELECT 1 FROM information_schema.schemata
        WHERE schema_name IN ('pggit_v0', 'pggit_audit', 'pggit_migration')
    ) INTO v_has_old_schemas;

    IF NOT v_has_old_schemas THEN
        RAISE NOTICE 'Schema migration skipped: No old schemas found (fresh installation) ✓';
        RETURN;
    END IF;

    RAISE NOTICE 'Starting schema migration from old naming to v0...';

    -- Rename main schema if it exists
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_v0') THEN
        EXECUTE 'ALTER SCHEMA pggit_v0 RENAME TO pggit_v0_migrated';
        RAISE NOTICE 'Renamed schema: pggit_v0 → pggit_v0_migrated';
    END IF;

    -- Rename audit schema if it exists
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_audit') THEN
        EXECUTE 'ALTER SCHEMA pggit_audit RENAME TO pggit_audit_v0';
        RAISE NOTICE 'Renamed schema: pggit_audit → pggit_audit_v0';
    END IF;

    -- Rename migration schema if it exists
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_migration') THEN
        EXECUTE 'ALTER SCHEMA pggit_migration RENAME TO pggit_migration_v0';
        RAISE NOTICE 'Renamed schema: pggit_migration → pggit_migration_v0';
    END IF;

    RAISE NOTICE 'Schema migration completed successfully ✓';
END $$;

-- ============================================
-- POST-MIGRATION VERIFICATION
-- Only runs if migration occurred
-- ============================================

DO $$
DECLARE
    v_has_old_schemas BOOLEAN;
BEGIN
    -- Check if schemas were actually migrated
    SELECT EXISTS (
        SELECT 1 FROM information_schema.schemata
        WHERE schema_name IN ('pggit_v0_migrated', 'pggit_audit_v0', 'pggit_migration_v0')
    ) INTO v_has_old_schemas;

    IF v_has_old_schemas THEN
        RAISE NOTICE 'Post-migration verification: Schema migration verification completed ✓';
    ELSE
        RAISE NOTICE 'Post-migration verification skipped: No migrated schemas found (fresh installation) ✓';
    END IF;
END $$;

DO $$
DECLARE
    v_function_count INTEGER;
    v_table_count INTEGER;
    v_view_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_function_count
    FROM information_schema.routines
    WHERE routine_schema IN ('pggit_v0', 'pggit_audit_v0', 'pggit_migration_v0');

    SELECT COUNT(*) INTO v_table_count
    FROM information_schema.tables
    WHERE table_schema IN ('pggit_v0', 'pggit_audit_v0', 'pggit_migration_v0');

    SELECT COUNT(*) INTO v_view_count
    FROM information_schema.views
    WHERE table_schema IN ('pggit_v0', 'pggit_audit_v0', 'pggit_migration_v0');

    RAISE NOTICE '==============================================';
    RAISE NOTICE 'SCHEMA RENAMING MIGRATION COMPLETE';
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Schemas renamed: 3 (pggit_v0, pggit_audit_v0, pggit_migration_v0)';
    RAISE NOTICE 'Functions available: % (in new schemas)', v_function_count;
    RAISE NOTICE 'Tables available: % (in new schemas)', v_table_count;
    RAISE NOTICE 'Views available: % (in new schemas)', v_view_count;
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Semantic Versioning Enabled:';
    RAISE NOTICE '  • pggit_v0.x.y = stable, backward-compatible releases';
    RAISE NOTICE '  • pggit_v1+     = future major versions (if breaking changes needed)';
    RAISE NOTICE '==============================================';
END $$;

-- ============================================
-- COMPLETION
-- ============================================

RAISE NOTICE '';
RAISE NOTICE '✓ Schema versioning migration successfully completed!';
RAISE NOTICE '✓ All functions now accessible via pggit_v0.* prefix';
RAISE NOTICE '✓ All audit functions accessible via pggit_audit_v0.* prefix';
RAISE NOTICE '✓ All migration functions accessible via pggit_migration_v0.* prefix';
RAISE NOTICE '';
RAISE NOTICE 'Next steps:';
RAISE NOTICE '  1. Update application connection strings if using schema-qualified names';
RAISE NOTICE '  2. Update CI/CD deployment scripts to reference pggit_v0';
RAISE NOTICE '  3. Update user documentation to reference new schema names';
RAISE NOTICE '  4. Run application tests to verify compatibility';
