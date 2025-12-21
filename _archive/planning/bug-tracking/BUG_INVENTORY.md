# Complete Bug Inventory - pggit Test Suite

**Date**: 2025-12-21
**Total Bugs Found**: 16 categories across 14 test files (100%)
**Critical Bugs**: 1
**High-Priority Bugs**: 6
**Medium-Priority Bugs**: 9

---

## Summary by Severity

### 🔴 CRITICAL (1 bug - BLOCKS ALL TESTING)
- **ensure_object() ambiguous overload** - Blocks DDL operations in all tests

### 🟠 HIGH (6 bugs - BLOCKS FEATURE TESTING)
1. Missing assertion helper functions
2. Missing pggit_v0 schema for 3-way merge
3. Missing data branching functions
4. Missing CQRS functions
5. Missing conflict resolution functions
6. Missing diff functionality

### 🟡 MEDIUM (9 bugs - PARTIAL FAILURES)
1. Incomplete AI migration analysis
2. Incomplete size management
3. Text vs JSONB data type mismatches
4. Undefined variables
5. Type redefinition warnings
6-9. Various incomplete implementations

---

## Detailed Bug Catalog

### BUG #1: 🔴 CRITICAL - `pggit.ensure_object()` Ambiguous Overload

**Impact**: Blocks ALL DDL operations
**Affected Tests**: 10 files
- test-cqrs-support.sql
- test-configuration-system.sql
- test-conflict-resolution.sql
- test-function-versioning.sql
- test-migration-integration.sql
- test-zero-downtime.sql
- test-advanced-features.sql
- test-ai.sql
- test-core.sql
- test-proper-three-way-merge.sql

**Error Message**:
```
ERROR: function pggit.ensure_object(pggit.object_type, text, text) is not unique
LINE 1: ...SELECT pggit.handle_ddl_command(...) called from trigger
HINT: Could not choose a best candidate function.
```

**Root Cause**:
Two function overloads with conflicting signatures:
```sql
ensure_object(object_type, text, text, text DEFAULT NULL, jsonb DEFAULT '{}')
ensure_object(object_type, text, text, text DEFAULT NULL, jsonb DEFAULT '{}', text DEFAULT 'main')
```

When called with 3 arguments, PostgreSQL can't determine which to use.

**Fix**: Remove one overload, keep the other. Update callers to be explicit.

**Effort**: 30 min
**Priority**: P0 (blocks everything)

---

### BUG #2: 🟠 HIGH - Missing Assertion Helper Functions

**Impact**: Tests cannot verify feature existence
**Affected Tests**: 9 files
- test-cqrs-support.sql
- test-data-branching.sql
- test-cold-hot-storage.sql
- test-diff-functionality.sql
- test-function-versioning.sql
- test-migration-integration.sql
- test-zero-downtime.sql
- test-advanced-features.sql
- test-configuration-system.sql

**Missing Functions**:
```sql
pggit.assert_function_exists(function_name text, schema text DEFAULT 'pggit')
pggit.assert_table_exists(table_name text, schema text DEFAULT 'pggit')
pggit.assert_type_exists(type_name text, schema text DEFAULT 'pggit')
```

**Error Message**:
```
ERROR: function pggit.assert_function_exists(unknown) does not exist
```

**Root Cause**: Functions should be installed from sql/test_helpers.sql via install.sql, but may not be getting installed properly.

**Fix**: Already created in sql/test_helpers.sql. Verify installation.

**Effort**: 15 min (already done)
**Priority**: P0 (blocks all tests)
**Status**: ✅ Already fixed in commit c6459a1

---

### BUG #3: 🟠 HIGH - Missing `pggit_v0` Schema (3-Way Merge)

**Impact**: 3-way merge feature completely non-functional
**Affected Tests**: 2 files
- test-proper-three-way-merge.sql
- test-three-way-merge-simple.sql

**Missing Schema**: `pggit_v0`

**Missing Tables**:
```sql
pggit_v0.objects (sha, object_type, content, compressed)
pggit_v0.tree_entries (sha, name, mode, object_sha)
pggit_v0.performance_metrics
```

**Missing Functions**:
```sql
pggit_v0.create_blob(content text) RETURNS text
pggit_v0.create_tree(tree_data jsonb) RETURNS text
pggit_v0.find_merge_base(sha1 text, sha2 text) RETURNS text
pggit_v0.three_way_merge(base_sha text, ours_sha text, theirs_sha text) RETURNS jsonb
pggit_v0.create_merge_commit(commit_data jsonb) RETURNS text
```

**Error Examples**:
```
test-three-way-merge-simple.sql:49
ERROR: schema "pggit_v0" does not exist
LINE 1: v_blob := pggit_v0.create_blob('Initial content')

test-proper-three-way-merge.sql:40
ERROR: schema "pggit_v0" does not exist
```

**Root Cause**: Three-way merge feature declared in tests but never implemented.

**Fix**: Create schema and stub implementations.

**Effort**: 1-2 hours (stub), 8-10 hours (full implementation)
**Priority**: P1 (blocks feature testing)
**Recommendation**: Start with stub, upgrade later

---

### BUG #4: 🟠 HIGH - Missing Data Branching Functions

**Impact**: Data branching feature non-functional
**Affected Tests**: 1 file
- test-data-branching.sql

**Missing Functions**:
```sql
pggit.create_data_branch(p_branch_name text, p_source_branch text, p_tables text[]) RETURNS integer
pggit.switch_branch(branch_name text) RETURNS boolean
pggit.get_current_branch() RETURNS text
pggit.merge_data_branches(source_branch text, target_branch text) RETURNS boolean
```

**Error Message**:
```
ERROR: function pggit.create_data_branch(text, text, text[]) does not exist
```

**Root Cause**: Feature declared for PostgreSQL 17 copy-on-write but never implemented.

**Fix**: Create stub implementation with branch state tracking.

**Effort**: 1-2 hours
**Priority**: P1
**Recommendation**: Stub implementation

---

### BUG #5: 🟠 HIGH - Missing CQRS Functions

**Impact**: CQRS feature non-functional
**Affected Tests**: 1 file
- test-cqrs-support.sql

**Missing Type**:
```sql
TYPE pggit.cqrs_change AS (
    command_operations text[],
    query_operations text[],
    description text,
    version text
)
```

**Missing Functions**:
```sql
pggit.track_cqrs_change(change_record pggit.cqrs_change) RETURNS uuid
pggit.get_cqrs_changes(since_timestamp timestamp) RETURNS TABLE(...)
pggit.apply_cqrs_event(event_id uuid) RETURNS boolean
```

**Error Message**:
```
ERROR: type "pggit.cqrs_change" does not exist
LINE 1: ...ROW(...)::pggit.cqrs_change
```

**Root Cause**: Feature declared but never implemented.

**Fix**: Create type and stub functions.

**Effort**: 1-2 hours
**Priority**: P1
**Recommendation**: Stub implementation

---

### BUG #6: 🟠 HIGH - Missing Conflict Resolution Functions

**Impact**: Conflict detection feature non-functional
**Affected Tests**: 1 file
- test-conflict-resolution.sql

**Missing Functions**:
```sql
pggit.register_conflict(conflict_data jsonb) RETURNS uuid
pggit.get_conflicts(status text DEFAULT 'open') RETURNS TABLE(...)
pggit.resolve_conflict(conflict_id uuid, resolution jsonb) RETURNS boolean
pggit.detect_conflicts(branch_id integer) RETURNS TABLE(...)
```

**Error Message**:
```
ERROR: function pggit.register_conflict(jsonb) does not exist
```

**Root Cause**: Feature declared but never implemented.

**Fix**: Create stub functions with tracking table.

**Effort**: 1-2 hours
**Priority**: P1
**Recommendation**: Stub implementation

---

### BUG #7: 🟠 HIGH - Missing Diff Functionality

**Impact**: Schema diff feature non-functional
**Affected Tests**: 1 file
- test-diff-functionality.sql

**Missing Functions**:
```sql
pggit.diff_schemas(schema1 text, schema2 text) RETURNS TABLE(...)
pggit.diff_tables(table1 text, table2 text) RETURNS TABLE(...)
pggit.generate_diff_sql(schema1 text, schema2 text) RETURNS text
```

**Error Message**:
```
ERROR: function pggit.diff_schemas(text, text) does not exist
```

**Root Cause**: Feature declared but never implemented.

**Fix**: Create stub functions.

**Effort**: 1-2 hours
**Priority**: P1
**Recommendation**: Stub implementation

---

### BUG #8: 🟡 MEDIUM - Incomplete AI Migration Analysis

**Impact**: AI feature only partially works
**Affected Tests**: 1 file
- test-ai.sql

**Status**: Partially implemented

**What Exists** ✅:
- Tables: `pggit.migration_patterns`, `pggit.ai_decisions`, `pggit.ai_edge_cases`
- Schema: `pggit` properly initialized

**What's Missing** ❌:
- Function: `pggit.analyze_migration_with_ai(migration_name text, sql_statement text, source_tool text)`

**Error Message**:
```
ERROR: function pggit.analyze_migration_with_ai(text, text, text) does not exist
```

**Root Cause**: Tables created but function logic never implemented.

**Fix**: Implement stub function that uses AI tables.

**Effort**: 30 min - 1 hour
**Priority**: P2
**Recommendation**: Implement stub

---

### BUG #9: 🟡 MEDIUM - Incomplete Size Management

**Impact**: Size management feature partially broken
**Affected Tests**: 2 files
- test-cold-hot-storage.sql
- test-ai.sql

**Missing Tables**:
```sql
pggit.branch_size_metrics
pggit.size_history
pggit.pruning_recommendations
```

**Missing Functions**:
```sql
pggit.classify_storage_tier(table_name text) RETURNS text
pggit.generate_pruning_recommendations() RETURNS TABLE(...)
pggit.run_size_maintenance() RETURNS boolean
pggit.detect_foreign_keys(schema text) RETURNS TABLE(...)
```

**Error Messages**:
```
ERROR: relation "pggit.branch_size_metrics" does not exist
ERROR: function pggit.classify_storage_tier(text) does not exist
```

**Root Cause**: Feature partially implemented (some tables exist, others missing).

**Fix**: Create missing tables and stub functions.

**Effort**: 1-2 hours
**Priority**: P2
**Recommendation**: Create missing objects

---

### BUG #10: 🟡 MEDIUM - Text vs JSONB Type Mismatch

**Impact**: Specific test operations fail
**Affected Tests**: 1 file
- test-proper-three-way-merge.sql (lines 40, 86, 147, 200, 341)

**Problem**:
```sql
-- v_entry is defined as a record/row with TEXT field
v_entry.entry_data->>'sha'  -- ❌ WRONG
-- Text type doesn't support ->> operator (JSONB operator)
```

**Error Message**:
```
ERROR: operator does not exist: text ->> unknown
```

**Root Cause**: Column defined as TEXT but code treats it as JSONB.

**Fix**: Either:
1. Cast to JSONB: `(v_entry.entry_data::jsonb)->>'sha'`
2. Use text extraction: `substring(v_entry.entry_data, ...)`
3. Change column type to JSONB

**Effort**: 30 min per file
**Priority**: P3
**Recommendation**: Add JSONB casts

---

### BUG #11: 🟡 MEDIUM - Undefined Variable

**Impact**: Test case fails
**Affected Tests**: 1 file
- test-proper-three-way-merge.sql (line 278)

**Problem**:
```sql
SELECT ... INTO v_tree_sha FROM blobs;
-- v_tree_sha never declared or initialized
```

**Error Message**:
```
ERROR: undefined variable "v_tree_sha"
```

**Root Cause**: Variable used but not declared.

**Fix**: Declare variable before use.

**Effort**: 10 min
**Priority**: P3
**Recommendation**: Fix declaration

---

### BUG #12: 🟡 MEDIUM - Type Redefinition Warnings

**Impact**: Warnings but tests continue
**Affected Tests**: Multiple (via sql/001_schema.sql)

**Warning Messages**:
```
NOTICE: type "object_type" already exists, skipping
NOTICE: type "change_type" already exists, skipping
NOTICE: type "change_severity" already exists, skipping
NOTICE: index "idx_objects_type" already exists, skipping
```

**Root Cause**: Objects created multiple times by:
1. sql/001_schema.sql
2. sql/pggit--0.1.1.sql (if both run)

**Fix**: Use `CREATE TYPE IF NOT EXISTS` and `CREATE INDEX IF NOT EXISTS`.

**Effort**: 15 min
**Priority**: P3 (cosmetic, doesn't break tests)
**Recommendation**: Use IF NOT EXISTS

---

### BUG #13-16: 🟢 LOW - Various Incomplete Features

**Impact**: Individual features partially broken
**Priority**: P4 (lower priority, can defer)

1. **Bug #13**: Function versioning feature incomplete
2. **Bug #14**: Configuration system partially broken
3. **Bug #15**: Migration integration missing
4. **Bug #16**: Zero-downtime deployment partial

These all follow the same pattern: features declared in tests but never fully implemented.

---

## Bug Summary Table

| # | Severity | Category | Impact | Affected Tests | Effort | Priority |
|---|----------|----------|--------|---|--------|----------|
| 1 | 🔴 CRITICAL | Function overload | Blocks ALL DDL | 10 | 30 min | P0 |
| 2 | 🟠 HIGH | Missing helpers | Blocks verification | 9 | 15 min | P0 |
| 3 | 🟠 HIGH | Missing pggit_v0 | Blocks 3-way merge | 2 | 1-2h | P1 |
| 4 | 🟠 HIGH | Missing branching | Blocks data branching | 1 | 1-2h | P1 |
| 5 | 🟠 HIGH | Missing CQRS | Blocks CQRS | 1 | 1-2h | P1 |
| 6 | 🟠 HIGH | Missing conflicts | Blocks conflicts | 1 | 1-2h | P1 |
| 7 | 🟠 HIGH | Missing diff | Blocks diff | 1 | 1-2h | P1 |
| 8 | 🟡 MEDIUM | Incomplete AI | AI partial | 1 | 1h | P2 |
| 9 | 🟡 MEDIUM | Incomplete size | Size partial | 2 | 1-2h | P2 |
| 10 | 🟡 MEDIUM | Type mismatch | Test failure | 1 | 30 min | P3 |
| 11 | 🟡 MEDIUM | Undefined var | Test failure | 1 | 10 min | P3 |
| 12 | 🟡 MEDIUM | Redefinition | Warnings | Multiple | 15 min | P3 |
| 13-16 | 🟢 LOW | Various | Partial feature | Multiple | Varies | P4 |

---

## Files Affected (by test file)

### test-core.sql
- Bug #1: ensure_object ambiguity
- Bug #2: assertion helpers
- Severity: BLOCKS testing

### test-cqrs-support.sql
- Bug #1: ensure_object ambiguity
- Bug #2: assertion helpers missing
- Bug #5: CQRS functions missing
- Severity: BLOCKS testing

### test-data-branching.sql
- Bug #1: ensure_object ambiguity
- Bug #2: assertion helpers
- Bug #4: data branching functions missing
- Severity: BLOCKS testing

### test-cold-hot-storage.sql
- Bug #2: assertion helpers
- Bug #9: size management incomplete
- Severity: BLOCKS testing

### test-configuration-system.sql
- Bug #1: ensure_object ambiguity
- Bug #2: assertion helpers
- Severity: BLOCKS testing

### test-conflict-resolution.sql
- Bug #1: ensure_object ambiguity
- Bug #6: conflict functions missing
- Severity: BLOCKS testing

### test-diff-functionality.sql
- Bug #2: assertion helpers
- Bug #7: diff functions missing
- Severity: BLOCKS testing

### test-function-versioning.sql
- Bug #1: ensure_object ambiguity
- Bug #2: assertion helpers
- Severity: BLOCKS testing

### test-migration-integration.sql
- Bug #1: ensure_object ambiguity
- Bug #2: assertion helpers
- Severity: BLOCKS testing

### test-zero-downtime.sql
- Bug #1: ensure_object ambiguity
- Bug #2: assertion helpers
- Severity: BLOCKS testing

### test-advanced-features.sql
- Bug #1: ensure_object ambiguity
- Bug #2: assertion helpers
- Severity: BLOCKS testing

### test-proper-three-way-merge.sql
- Bug #1: ensure_object ambiguity
- Bug #3: pggit_v0 missing
- Bug #10: text vs JSONB mismatch
- Bug #11: undefined variable
- Severity: BLOCKS testing

### test-three-way-merge-simple.sql
- Bug #3: pggit_v0 missing
- Severity: BLOCKS testing

### test-ai.sql
- Bug #1: ensure_object ambiguity
- Bug #8: AI function missing
- Bug #9: size management incomplete
- Severity: BLOCKS testing

---

## Implementation Roadmap

See **BUG_FIX_PLAN.md** for detailed implementation instructions, phases, and checklist.

**Quick Summary**:
- Phase 1 (1-2h): Fix critical blockers
- Phase 2 (4h): Implement feature stubs
- Phase 3 (2-3h): Complete implementations
- Phase 4 (1h): Polish and cleanup

**Total Effort**: 7-10 hours

---

## Status Tracking

- [x] Bugs identified and documented
- [x] Detailed plan created (BUG_FIX_PLAN.md)
- [ ] Phase 1 implementation started
- [ ] Phase 2 implementation started
- [ ] Phase 3 implementation started
- [ ] Phase 4 implementation started
- [ ] All tests passing
- [ ] QA verification complete

---

**Next Step**: Proceed to BUG_FIX_PLAN.md for implementation details and execute Phase 1.
