# Week 8: Schema Versioning Refactor

**Date**: December 21, 2025 (Planned)
**Status**: Planned Task
**Duration**: 1 week (20-25 hours)
**Focus**: Rename all schemas from pggit_v0 → pggit_v0 for long-term compatibility
**Dependency**: Weeks 1-7 must complete first

---

## Overview

Implement schema versioning using semantic versioning. All `pggit_v0` references will be renamed to `pggit_v0` to establish a clean versioning scheme that supports future major versions (v1, v2, etc.) without API breakage.

**Why Now?**
- Weeks 1-7 focus on functionality & UAT
- Week 8 focuses on production readiness & naming conventions
- Better to do this before general team adoption
- Easier now than retrofitting after widespread use

---

## Objectives

### Primary: Systematic Schema Rename
Convert all pggit_v0 → pggit_v0 references across codebase

### Secondary: Documentation Update
Update all examples, guides, and comments to reflect new naming

### Tertiary: Validation
Verify all renamed objects work correctly post-rename

---

## Week 8 Plan (5 days × 4-5 hours = 20-25 hours)

### Day 1: SQL File Refactoring (4 hours)
**Goal**: Rename all schema references in SQL files

**Files to Update**:
- [ ] `sql/pggit_migration_core.sql` - Replace `pggit_v0` with `pggit_v0`
- [ ] `sql/pggit_migration_execution.sql` - Replace references
- [ ] `sql/pggit_migration_integration.sql` - Replace references
- [ ] `sql/pggit_audit_schema.sql` - Replace `pggit_audit` with `pggit_audit_v0`
- [ ] `sql/pggit_audit_functions.sql` - Replace all references
- [ ] `sql/pggit_audit_extended.sql` - Replace all references
- [ ] `sql/pggit_v0_developers.sql` - Rename file to `pggit_v0_developers.sql`, update internals
- [ ] `sql/pggit_v0_views.sql` - Rename file to `pggit_v0_views.sql`, update internals
- [ ] `sql/pggit_v0_analytics.sql` - Rename file to `pggit_v0_analytics.sql`, update internals
- [ ] `sql/pggit_v0_branching.sql` - Rename file to `pggit_v0_branching.sql`, update internals
- [ ] `sql/pggit_v0_monitoring.sql` - Rename file to `pggit_v0_monitoring.sql`, update internals

**Approach**:
```bash
# Pattern matching approach
# Replace: CREATE FUNCTION pggit_v0. → CREATE FUNCTION pggit_v0.
# Replace: FROM pggit_v0. → FROM pggit_v0.
# Replace: JOIN pggit_v0. → JOIN pggit_v0.
# Replace: WHERE ... pggit_v0. → WHERE ... pggit_v0.
# Replace: pggit_audit. → pggit_audit_v0.
# Replace: pggit_migration. → pggit_migration_v0.
```

**Validation**:
- [ ] All files parse without syntax errors
- [ ] No broken references
- [ ] All function definitions reference correct schema

### Day 2: Documentation Update (4 hours)
**Goal**: Update all user-facing documentation

**Files to Update**:
- [ ] `docs/pggit_v0_integration_guide.md` - All examples use pggit_v0
- [ ] `WEEK_4_5_COMPLETION_REPORT.md` - Update schema references
- [ ] `WEEK_6_UAT_PREPARATION.md` - Update all test queries to use pggit_v0
- [ ] `WEEK_3_COMPLETION_SUMMARY.md` - Update references
- [ ] `WEEK_2_COMPLETION_SUMMARY.md` - Update references
- [ ] All inline SQL comments - Schema names updated

**Approach**:
- Global search for `pggit_v0` → `pggit_v0`
- Global search for `pggit_audit.` → `pggit_audit_v0.`
- Global search for `pggit_migration.` → `pggit_migration_v0.`
- Review all examples to ensure they're correct

**Validation**:
- [ ] All examples use correct schema names
- [ ] No stale references remain
- [ ] Documentation is consistent

### Day 3: Actual Schema Rename (3 hours)
**Goal**: Execute the schema renames in database

**Steps**:
1. Create migration script: `sql/000_rename_schemas_to_v0.sql`

```sql
-- 000_rename_schemas_to_v0.sql
-- Migration: Rename all schemas from pggit_v0 to pggit_v0
-- Date: Week 8
-- Backward compatible: NO (must be done before production if not already there)

-- Rename main schemas
ALTER SCHEMA pggit_v0 RENAME TO pggit_v0;
ALTER SCHEMA pggit_audit RENAME TO pggit_audit_v0;
ALTER SCHEMA pggit_migration RENAME TO pggit_migration_v0;

-- Update schema comments for clarity
COMMENT ON SCHEMA pggit_v0 IS 'pgGit v0: Content-addressable schema versioning (stable API)';
COMMENT ON SCHEMA pggit_audit_v0 IS 'pgGit v0 Audit Layer: Compliance and change tracking (stable API)';
COMMENT ON SCHEMA pggit_migration_v0 IS 'pgGit v0 Migration Tools: v1 to v2 conversion utilities (stable API)';
```

2. Test migration script
3. Apply to test database
4. Validate all objects still work

### Day 4: Comprehensive Testing (5 hours)
**Goal**: Verify all renamed functions and views work

**Test Categories**:

**Developer Functions** (12):
- [ ] `pggit_v0.get_current_schema()`
- [ ] `pggit_v0.list_objects()`
- [ ] `pggit_v0.create_branch()`
- [ ] `pggit_v0.list_branches()`
- [ ] `pggit_v0.delete_branch()`
- [ ] `pggit_v0.get_commit_history()`
- [ ] `pggit_v0.get_object_history()`
- [ ] `pggit_v0.diff_commits()`
- [ ] `pggit_v0.diff_branches()`
- [ ] `pggit_v0.get_object_definition()`
- [ ] `pggit_v0.get_object_metadata()`
- [ ] `pggit_v0.get_head_sha()`

**Views** (12):
- [ ] All 12 views query from correct `pggit_v0` schema
- [ ] `pggit_v0.recent_commits_by_author`
- [ ] `pggit_v0.most_changed_objects`
- [ ] `pggit_v0.branch_comparison`
- [ ] `pggit_v0.daily_change_summary`
- [ ] `pggit_v0.schema_growth_history`
- [ ] `pggit_v0.author_activity`
- [ ] `pggit_v0.commits_without_message`
- [ ] `pggit_v0.orphaned_objects`
- [ ] `pggit_v0.large_commits`
- [ ] `pggit_v0.current_head_info`
- [ ] `pggit_v0.branch_status_summary`
- [ ] `pggit_v0.recent_activity_summary`

**Analytics Functions** (7):
- [ ] `pggit_v0.analyze_storage_usage()`
- [ ] `pggit_v0.get_object_size_distribution()`
- [ ] `pggit_v0.analyze_query_performance()`
- [ ] `pggit_v0.benchmark_extraction_functions()`
- [ ] `pggit_v0.validate_data_integrity()`
- [ ] `pggit_v0.detect_anomalies()`
- [ ] `pggit_v0.estimate_storage_growth()`

**Branching Functions** (8):
- [ ] `pggit_v0.create_feature_branch()`
- [ ] `pggit_v0.merge_branch()`
- [ ] `pggit_v0.rebase_branch()`
- [ ] `pggit_v0.detect_merge_conflicts()`
- [ ] `pggit_v0.resolve_conflict()`
- [ ] `pggit_v0.create_merge_request()`
- [ ] `pggit_v0.approve_merge_request()`
- [ ] `pggit_v0.get_merge_request_status()`

**Monitoring Functions** (5+):
- [ ] `pggit_v0.check_for_alerts()`
- [ ] `pggit_v0.get_recommendations()`
- [ ] `pggit_v0.get_dashboard_summary()`
- [ ] `pggit_v0.generate_monitoring_report()`
- [ ] All monitoring views work

**Audit Functions**:
- [ ] All functions in `pggit_audit_v0` work correctly
- [ ] All changes tracked properly

### Day 5: Git Commit & Documentation (3 hours)
**Goal**: Commit all changes with clear history

**Tasks**:
1. [ ] Commit SQL file renames and content updates
2. [ ] Commit documentation updates
3. [ ] Commit migration script
4. [ ] Create WEEK_8_COMPLETION_REPORT.md
5. [ ] Update main README with new schema names
6. [ ] Tag as v0.1.1-ready or similar

---

## Success Criteria

**All must pass**:

1. ✅ **SQL Files**
   - [ ] All 11 SQL files updated with new schema names
   - [ ] All files parse without syntax errors
   - [ ] No broken references remain
   - [ ] File names reflect new structure

2. ✅ **Database Objects**
   - [ ] All 30+ functions in `pggit_v0` schema
   - [ ] All 12 views in `pggit_v0` schema
   - [ ] All audit objects in `pggit_audit_v0` schema
   - [ ] All migration objects in `pggit_migration_v0` schema

3. ✅ **Functionality**
   - [ ] All functions tested and working
   - [ ] All views returning correct data
   - [ ] All workflow scenarios pass
   - [ ] Integration points verified

4. ✅ **Documentation**
   - [ ] All examples updated to use pggit_v0
   - [ ] All references consistent
   - [ ] No stale pggit_v0 references remain
   - [ ] Integration guide accurate

5. ✅ **Git History**
   - [ ] Clean commit messages
   - [ ] Logical commit grouping
   - [ ] Full history preserved

---

## Implementation Notes

### Search & Replace Patterns

**Be careful with these patterns**:
```sql
-- Wrong: This would break things
pggit_v0.commit_graph → pggit_v0.commit_graph ✅

-- Be careful: Check context
v2 → v0 (too generic, might catch version numbers)
pggit_v0 → pggit_v0 (use full string)

-- Also rename:
pggit_audit. → pggit_audit_v0.
pggit_migration. → pggit_migration_v0.
```

### File Rename Strategy

**SQL Files** (optional but recommended):
```bash
sql/pggit_v0_developers.sql → sql/pggit_v0_developers.sql
sql/pggit_v0_views.sql → sql/pggit_v0_views.sql
sql/pggit_v0_analytics.sql → sql/pggit_v0_analytics.sql
sql/pggit_v0_branching.sql → sql/pggit_v0_branching.sql
sql/pggit_v0_monitoring.sql → sql/pggit_v0_monitoring.sql
```

**Or keep as-is** and only update schema names inside files (simpler approach).

### Git Commits

**Recommended sequence**:
1. Commit: "refactor: Rename schemas pggit_v0 → pggit_v0 for semantic versioning"
   - SQL file content updates
   - Schema rename migration script

2. Commit: "docs: Update all references from pggit_v0 to pggit_v0"
   - Documentation updates
   - Example updates
   - Comments updates

3. Commit: "test: Verify pggit_v0 functions and views after schema rename"
   - Test results
   - Validation completeness

---

## Why Week 8 Matters

**This sets up long-term success**:
- ✅ Clean versioning for future releases
- ✅ Supports multiple major versions coexisting
- ✅ Clear naming convention for all features
- ✅ Professional, maintainable codebase
- ✅ Ready for team adoption without confusion

**Without this**:
- ❌ v0.2.0, v0.3.0 still in pggit_v0 schema (confusing)
- ❌ Future v1 can't coexist cleanly
- ❌ Naming doesn't match versioning

---

## Timeline Integration

```
Week 7: Production Launch (Saturday midnight)
  pggit_v0 schemas deployed

Week 8: Schema Versioning Refactor
  Rename pggit_v0 → pggit_v0
  Update all documentation
  Clean versioning established

Week 9: Operations & Training
  Users trained on pggit_v0
  Documentation reflects new naming
  Production stable with proper versioning
```

---

## Success Definition

Week 8 is successful when:
1. ✅ All `pggit_v0` renamed to `pggit_v0`
2. ✅ All `pggit_audit` renamed to `pggit_audit_v0`
3. ✅ All `pggit_migration` renamed to `pggit_migration_v0`
4. ✅ All 30+ functions work in new schema
5. ✅ All 12 views work in new schema
6. ✅ Documentation consistent and accurate
7. ✅ Git history clean and logical
8. ✅ Ready for production with proper versioning

---

## Rollback Plan

If anything goes wrong:
```sql
-- Rollback schemas (reverse the renames)
ALTER SCHEMA pggit_v0 RENAME TO pggit_v0;
ALTER SCHEMA pggit_audit_v0 RENAME TO pggit_audit;
ALTER SCHEMA pggit_migration_v0 RENAME TO pggit_migration;

-- Git: git reset --hard to pre-rename commit
```

---

## Summary

Week 8 implements semantic versioning through schema naming. This positions pggit_v0 as a stable API that can coexist with future major versions without conflict.

**Key Achievement**: Clean, professional versioning scheme that supports long-term project evolution.

**Next Step**: Execute Week 8 plan after production stabilizes (early in week)

**Expected Outcome**: Production system with proper semantic versioning in place

---

*Week 8 Schema Versioning Refactor Plan - December 21, 2025*
*Planned for post-launch cleanup and professionalization*
*Supports long-term project maintainability and user clarity*
