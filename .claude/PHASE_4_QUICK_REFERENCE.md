# Phase 4 Plan - Quick Reference Guide

**Updated**: 2025-12-26 | **Status**: Ready for Implementation ✅

---

## Function Signatures (Updated)

### 1. merge_branches()
```sql
pggit.merge_branches(
    p_source_branch TEXT,
    p_target_branch TEXT,
    p_merge_strategy TEXT DEFAULT 'ABORT_ON_CONFLICT',
    p_merge_message TEXT DEFAULT NULL,
    p_merge_base_branch TEXT DEFAULT NULL,  -- ✅ NEW
    p_metadata JSONB DEFAULT NULL
)
```

**Change**: Added `p_merge_base_branch` parameter for three-way merge support

---

### 2. detect_merge_conflicts()
```sql
pggit.detect_merge_conflicts(
    p_source_branch TEXT,
    p_target_branch TEXT,
    p_merge_base_branch TEXT DEFAULT NULL
)
```

**Returns**: Conflicts classified as: NO_CONFLICT, SOURCE_MODIFIED, TARGET_MODIFIED, BOTH_MODIFIED, DELETED_SOURCE, DELETED_TARGET

---

### 3. resolve_conflict()
```sql
pggit.resolve_conflict(
    p_merge_id UUID,
    p_object_id BIGINT,
    p_resolution_choice TEXT,
    p_custom_definition TEXT DEFAULT NULL
)
```

**Change**: Validates custom definitions via EXPLAIN parsing ✅

---

## Conflict Classification Matrix

| Base State | Source | Target | Classification | Auto-Resolvable | Action |
|-----------|--------|--------|---|---|---|
| EXISTS | MODIFIED | UNCHANGED | SOURCE_MODIFIED | ✅ | Apply source |
| EXISTS | UNCHANGED | MODIFIED | TARGET_MODIFIED | ✅ | Keep target |
| EXISTS | DELETED | UNCHANGED | DELETED_SOURCE | ✅ | Delete |
| EXISTS | UNCHANGED | DELETED | DELETED_TARGET | ✅ | No-op |
| EXISTS | MODIFIED | MODIFIED | BOTH_MODIFIED | ❌ | Manual review |
| NOT EXISTS | ADDED | NOT ADDED | ADDED | ✅ | Apply |
| NOT EXISTS | NOT ADDED | ADDED | ADDED | ✅ | Keep |
| NOT EXISTS | ADDED (same) | ADDED (same) | NO_CONFLICT | ✅ | Skip |
| NOT EXISTS | ADDED (diff) | ADDED (diff) | BOTH_MODIFIED | ❌ | Manual review |

---

## UNION Strategy Rules

| Object Type | Supported | Example |
|-------------|---|---|
| TABLE | ✅ Limited | Merge ADD COLUMN from both |
| TRIGGER | ✅ Limited | Merge non-overlapping ON clauses |
| INDEX | ✅ Limited | Merge ADD INDEX from both |
| FUNCTION | ❌ | Requires MANUAL_REVIEW |
| VIEW | ❌ | Requires MANUAL_REVIEW |

**Key Rule**: UNION only for independent, non-overlapping changes

---

## Breaking Change Detection

### Detected as Breaking
✅ DROP TABLE/FUNCTION/VIEW with dependents → MAJOR
✅ Any DROP with dependents in object_dependencies → MAJOR
✅ TRIGGER/INDEX DROP → MINOR

### NOT Detected (Require Manual Review)
❌ Column renames
❌ Parameter additions
❌ Constraint modifications
❌ Schema restructuring

---

## Merge Base Discovery

**If `p_merge_base_branch` is NULL:**
1. Find LCA (Lowest Common Ancestor) of source and target
2. Traverse parent_branch_id for both branches
3. Find first common ancestor in branch tree
4. If no LCA found, default to 'main'

**If `p_merge_base_branch` is provided:**
- Use explicit base branch for three-way merge

**Example**:
```
main (branch 1)
├── feature-a (branch 2)
└── feature-b (branch 3)

Merge feature-a → feature-b:
- LCA = main
- Three-way: main → feature-a vs main → feature-b
```

---

## Custom Definition Validation

**Process**:
```sql
BEGIN
  EXECUTE 'EXPLAIN (FORMAT JSON) ' || p_custom_definition LIMIT 0;
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Custom definition has syntax errors: %', SQLERRM;
END;
```

**Effect**:
- Uses PostgreSQL's SQL parser
- Validates syntax without execution
- Rejects invalid definitions with clear errors
- Works for all SQL object types

---

## Test Coverage

**Total: 40 tests** (34 unit + 6 integration)

### Unit Tests (34)
- TestMergeBranches: 10 tests
- TestDetectMergeConflicts: 10 tests (expanded)
- TestResolveConflict: 8 tests
- TestIntegration: 6 tests (NEW)

### Key Test Scenarios
- ✅ Three-way merge with auto-discovered base
- ✅ All 6 conflict types
- ✅ All 5 merge strategies
- ✅ UNION strategy with compatible/incompatible objects
- ✅ Custom definition validation (valid & invalid)
- ✅ Breaking change detection
- ✅ Full workflow: detect → review → resolve

---

## Timeline

**Estimate: 5-6 days** (revised from 3-4)

**Breakdown**:
- merge_branches(): 1.5 days (merge_base discovery)
- detect_merge_conflicts(): 1.5 days (three-way merge)
- resolve_conflict(): 1 day (validation)
- Unit Testing: 1.5 days (34 tests)
- Integration Testing: 1 day (6 tests)
- Documentation & QA: 0.5 days

**Key Milestones**:
- Day 1-1.5: merge_branches()
- Day 2: detect_merge_conflicts()
- Day 2-2.5: resolve_conflict()
- Day 3: All unit tests passing
- Day 4: All integration tests passing
- Day 5: QA + [GREEN] commit

---

## Key Differences from Original Plan

| Aspect | Original | Updated | Reason |
|--------|----------|---------|--------|
| Conflict Types | 3 (vague) | 6 (explicit) | Three-way merge semantics |
| UNION Rules | Not specified | Per-type rules | Complexity varies by object |
| Breaking Changes | "via dependency graph" | Conservative rules | Avoid false positives |
| Merge Base | Auto only | Auto + explicit | Flexibility for advanced scenarios |
| Custom Validation | "compute_hash()" | SQL parsing | Catch syntax errors early |
| Tests | 26 unit | 34 unit + 6 integration | Better coverage |
| Timeline | 3-4 days | 5-6 days | Realistic complexity |

---

## Architecture Principles

1. **Three-Way Merge Semantics** ✅
   - Base branch enables true conflict detection
   - Auto-discovery for convenience, explicit option for control

2. **Strategy-Based Resolution** ✅
   - ABORT_ON_CONFLICT (safe default)
   - TARGET_WINS, SOURCE_WINS (automatic)
   - UNION (smart for compatible changes)
   - MANUAL_REVIEW (for complex cases)

3. **Conservative Approach** ✅
   - Break change detection flags only certain scenarios
   - UNION only for known-safe object types
   - Custom definitions validated before applying

4. **Immutable Audit Trail** ✅
   - All merges recorded in merge_operations
   - Result commits preserve merged state
   - Enables future rollback functionality

5. **Dependency-Aware** ✅
   - Checks for breaking changes via object_dependencies
   - Counts dependent objects for impact analysis

---

## Success Criteria Checklist

Before marking Phase 4 complete:

- [ ] All 3 functions implemented per spec
- [ ] All 6 conflict types correctly detected
- [ ] UNION strategy per-type rules implemented
- [ ] Custom definitions validated via EXPLAIN
- [ ] Merge base auto-discovered correctly
- [ ] All 40 tests passing (100%)
- [ ] Breaking change detection working
- [ ] No regression in Phase 1-3 tests
- [ ] [GREEN] commit ready

---

## Files to Modify/Create

### SQL Implementation
- **Create**: `sql/032_pggit_merge_operations.sql`
  - pggit.merge_branches() ~220-250 lines
  - pggit.detect_merge_conflicts() ~180-200 lines
  - pggit.resolve_conflict() ~130-150 lines
  - Total: ~500-600 lines SQL

### Python Tests
- **Create**: `tests/unit/test_phase4_merge_operations.py`
  - 34 unit tests + 6 integration tests
  - ~800-1000 lines Python

### Documentation
- **Update**: PHASE_4_PLAN.md (✅ done)
- **Create**: PHASE_4_CLARIFICATIONS_SUMMARY.md (✅ done)
- **Create**: PHASE_4_QUICK_REFERENCE.md (this file)

---

## References

- Backup implementation: `/home/lionel/code/pggit.v0.1.1.bk/sql/04_merge_operations.sql`
- Review document: `.claude/PHASE_4_REVIEW.md`
- Full plan: `.claude/PHASE_4_PLAN.md`
- Clarifications: `.claude/PHASE_4_CLARIFICATIONS_SUMMARY.md`

---

**Status**: ✅ Ready for Implementation

All clarifications addressed. Phase 4 is architecturally sound and ready to code.

