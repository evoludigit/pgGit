-- ============================================
-- Schema Versioning Migration
-- Rename all pggit_v2 schemas to pggit_v0
-- ============================================
-- Date: December 21, 2025 (Week 8 - Post-Production)
-- Purpose: Establish semantic versioning (v0.x.y = stable API)
-- Status: Production deployment
-- Backward Compatible: NO (one-time migration)
--
-- This script implements semantic versioning by renaming schemas
-- from pggit_v2 (confusing numbering) to pggit_v0 (clear versioning):
-- - pggit_v0.x: Stable, backward-compatible releases
-- - pggit_v1+: Future major versions if breaking changes needed
--
-- This allows multiple major versions to coexist in production.
-- ============================================

-- ============================================
-- PRE-MIGRATION CHECKS
-- ============================================

-- Check 1: Verify schemas exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_v2') THEN
        RAISE EXCEPTION 'Schema pggit_v2 does not exist. Migration may have already occurred.';
    END IF;
    RAISE NOTICE 'Pre-migration check: pggit_v2 schema found ✓';
END $$;

-- Check 2: Verify target schemas don't already exist
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_v0') THEN
        RAISE EXCEPTION 'Target schema pggit_v0 already exists. Please remove it before running migration.';
    END IF;
    RAISE NOTICE 'Pre-migration check: pggit_v0 schema does not exist ✓';
END $$;

-- ============================================
-- SCHEMA RENAMES
-- ============================================

-- Rename main schema
ALTER SCHEMA pggit_v2 RENAME TO pggit_v0;
RAISE NOTICE 'Renamed schema: pggit_v2 → pggit_v0';

-- Rename audit schema
ALTER SCHEMA pggit_audit RENAME TO pggit_audit_v0;
RAISE NOTICE 'Renamed schema: pggit_audit → pggit_audit_v0';

-- Rename migration schema
ALTER SCHEMA pggit_migration RENAME TO pggit_migration_v0;
RAISE NOTICE 'Renamed schema: pggit_migration → pggit_migration_v0';

-- ============================================
-- UPDATE SCHEMA COMMENTS
-- ============================================

COMMENT ON SCHEMA pggit_v0 IS 'pgGit v0: Content-addressable schema versioning (stable API, semantic versioning)';
COMMENT ON SCHEMA pggit_audit_v0 IS 'pgGit v0 Audit: Immutable DDL change tracking and compliance (stable API)';
COMMENT ON SCHEMA pggit_migration_v0 IS 'pgGit v0 Migration: Tools for v1→v2 data migration (stable API)';

RAISE NOTICE 'Updated schema comments for clarity';

-- ============================================
-- POST-MIGRATION VERIFICATION
-- ============================================

-- Verify all schemas renamed
DO $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM information_schema.schemata
    WHERE schema_name IN ('pggit_v0', 'pggit_audit_v0', 'pggit_migration_v0');

    IF v_count = 3 THEN
        RAISE NOTICE 'Post-migration verification: All 3 schemas renamed successfully ✓';
    ELSE
        RAISE EXCEPTION 'Post-migration verification failed: Expected 3 schemas, found %', v_count;
    END IF;
END $$;

-- Verify no old schemas exist
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_v2') THEN
        RAISE EXCEPTION 'Post-migration error: pggit_v2 schema still exists!';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_audit' AND schema_name != 'pggit_audit_v0') THEN
        RAISE EXCEPTION 'Post-migration error: pggit_audit schema still exists!';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_migration' AND schema_name != 'pggit_migration_v0') THEN
        RAISE EXCEPTION 'Post-migration error: pggit_migration schema still exists!';
    END IF;
    RAISE NOTICE 'Post-migration verification: No old schemas remain ✓';
END $$;

-- Verify functions are accessible
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema = 'pggit_v0') THEN
        RAISE NOTICE 'Post-migration verification: Functions accessible in pggit_v0 schema ✓';
    ELSE
        RAISE EXCEPTION 'Post-migration error: No functions found in pggit_v0 schema!';
    END IF;
END $$;

-- ============================================
-- MIGRATION SUMMARY
-- ============================================

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
