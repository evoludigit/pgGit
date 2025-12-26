# Phase 4 Plan - Clarifications Summary

**Date**: 2025-12-26
**Status**: All 5 Clarifications Addressed ✅

This document summarizes the clarifications made to the Phase 4 implementation plan based on the comprehensive review.

---

## Clarification #1: Conflict Classification Logic ✅

### Original Issue
Plan was ambiguous about which conflicts are auto-resolvable vs require manual review. The distinction between MODIFIED, ADDED, REMOVED was unclear in edge cases.

### Solution Implemented
Added **Conflict Classification Matrix** showing all 10 scenarios with three-way merge semantics:

```
TRUE THREE-WAY MERGE LOGIC:
- If base → source differs but base → target same: SOURCE_MODIFIED (auto-resolvable)
- If base → source same but base → target differs: TARGET_MODIFIED (auto-resolvable)
- If base → source differs AND base → target differs: BOTH_MODIFIED (manual review)
- If deleted on one side but modified on other: BOTH_MODIFIED (conflict)
```

**Key Insight**: Prevents the "lost deletion" problem where one branch deletes while other modifies.

**Conflict Types Defined**:
- ✅ NO_CONFLICT - No changes needed
- ✅ SOURCE_MODIFIED - Safe to apply source's change
- ✅ TARGET_MODIFIED - Safe to keep target's change
- ✅ DELETED_SOURCE - Safe to delete from target
- ✅ DELETED_TARGET - Already deleted, no action
- ❌ BOTH_MODIFIED - Requires MANUAL_REVIEW

**Location in Plan**: New "Clarified Implementation Details" section with full matrix

---

## Clarification #2: UNION Strategy Details ✅

### Original Issue
Plan only showed simple trigger merging example. Real UNION strategy is much more complex with many object types having different merge rules.

### Solution Implemented
Created **per-object-type UNION rules**:

| Object Type | UNION Support | Notes |
|-------------|---|---|
| TABLE | ✅ Limited | Merge ADD COLUMN from both branches (error if same column) |
| TRIGGER | ✅ Limited | Merge non-overlapping ON clauses (error if same event) |
| INDEX | ✅ Limited | Merge ADD INDEX from both (error if same name) |
| FUNCTION/PROCEDURE | ❌ Not Supported | Requires code understanding |
| VIEW | ❌ Not Supported | Too complex to merge safely |
| SEQUENCE/DOMAIN | ❌ Not Supported | Too risky to auto-merge |

**Practical Examples**:
- ✅ Both add different columns to table → merge both
- ✅ One adds INSERT trigger, other adds UPDATE trigger → merge both
- ❌ Both modify function body → requires MANUAL_REVIEW
- ❌ Both add INSERT trigger on same table → conflict

**Implementation Strategy**:
1. Detect UNION strategy attempt
2. For each BOTH_MODIFIED conflict:
   - If object_type supports UNION, attempt smart merge
   - If merge succeeds, apply result
   - If merge fails, fall back to MANUAL_REVIEW
   - If object_type doesn't support UNION, always MANUAL_REVIEW

**Location in Plan**: "UNION Strategy Details" section with tables and examples

---

## Clarification #3: Breaking Change Detection Rules ✅

### Original Issue
Plan said "flag via dependency graph" but wasn't specific about which changes are actually breaking.

### Solution Implemented
Defined **conservative breaking change detection**:

**Detected as Breaking**:
1. ✅ DROP operations on objects with dependents
   - Query object_dependencies table
   - If other objects reference this, flag as MAJOR severity
   - Example: DROP TABLE used by foreign keys

2. ✅ DROP operations on critical types
   - TABLE, FUNCTION, VIEW drops → MAJOR
   - TRIGGER/INDEX drops → MINOR

**NOT Detected** (require manual review):
- Column renames (syntax change, semantic unknown)
- Parameter additions (requires SQL parsing)
- Constraint modifications (needs understanding)
- Schema restructuring

**Implementation SQL**:
```sql
-- Check if object being dropped has dependents
SELECT COUNT(*) FROM pggit.object_dependencies
WHERE depends_on_object_id = current_object_id
  AND is_active = true;

-- If count > 0 and DROP detected, flag severity as MAJOR
```

**Location in Plan**: "Breaking Change Detection Rules" section

---

## Clarification #4: Merge Base Parameter ✅

### Original Issue
Plan showed detect_merge_conflicts() with merge_base parameter, but merge_branches() had no such parameter. How would actual merge use three-way logic?

### Solution Implemented
**Added p_merge_base_branch parameter to merge_branches()**:

```sql
CREATE OR REPLACE FUNCTION pggit.merge_branches(
    p_source_branch TEXT,
    p_target_branch TEXT,
    p_merge_strategy TEXT DEFAULT 'ABORT_ON_CONFLICT',
    p_merge_message TEXT DEFAULT NULL,
    p_merge_base_branch TEXT DEFAULT NULL,  -- NEW
    p_metadata JSONB DEFAULT NULL
)
```

**Behavior**:
- If p_merge_base_branch IS NULL:
  - Auto-discover via LCA (Lowest Common Ancestor) algorithm
  - Traverse parent_branch_id for both branches
  - Find first common ancestor
  - If no LCA, default to 'main'
- If p_merge_base_branch provided:
  - Validate branch exists
  - Use explicit base for three-way merge

**Benefits**:
- Auto-discovery enables natural Git-like behavior
- Explicit base allows advanced merge scenarios
- Three-way merge prevents lost deletions
- Matches backup implementation's find_merge_base() approach

**Location in Plan**: Updated Function 1 signature with parameter details

---

## Clarification #5: Custom Definition Validation ✅

### Original Issue
Plan said "validate with compute_hash()" but that only computes hash. How to validate SQL syntax before applying?

### Solution Implemented
**SQL syntax validation in resolve_conflict()**:

```sql
-- Validate custom definition has valid SQL syntax
BEGIN
  EXECUTE 'EXPLAIN (FORMAT JSON) ' || p_custom_definition LIMIT 0;
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Custom definition has syntax errors: %', SQLERRM;
END;
```

**Why this approach?**
- Uses PostgreSQL's built-in SQL parser
- Catches syntax errors immediately
- Provides clear error messages
- Works for all SQL object types
- No external dependencies

**Process**:
1. User provides custom definition
2. Attempt EXPLAIN parse (no execution)
3. If EXPLAIN succeeds: SQL is valid
4. If EXPLAIN fails: Return error message
5. If valid, compute hash and proceed with resolution

**Location in Plan**: Updated resolve_conflict() Function 3 implementation steps

---

## Additional Improvements

### Test Coverage Expanded
- Unit tests increased from 26 → 34 (new test cases)
- Integration tests added (6 new tests) - was missing entirely
- Now tests all conflict types, merge scenarios, and full workflows
- Tests for merge_base auto-discovery
- Tests for UNION strategy behavior
- Tests for custom definition validation

**Location**: Updated "Testing Strategy" section

### Effort Estimate Revised
- Original estimate: 3-4 days
- Revised estimate: 5-6 days
- Reasons: merge_base discovery, three-way merge complexity, UNION rules, custom validation, integration testing

**Location**: Updated "Timeline & Effort" section

### Conflict Type Definitions Added
Added explicit list of 6 conflict types instead of vague language:
- NO_CONFLICT
- SOURCE_MODIFIED
- TARGET_MODIFIED
- BOTH_MODIFIED
- DELETED_SOURCE
- DELETED_TARGET

**Location**: Architecture Overview section

---

## Reference Implementation

The clarifications were informed by the backup implementation in `/home/lionel/code/pggit.v0.1.1.bk/sql/04_merge_operations.sql` which includes:

- ✅ `find_merge_base()` - LCA algorithm for merge base discovery
- ✅ Conflict classification with 6 types (not 3)
- ✅ Three-way merge analysis (base → source vs base → target)
- ✅ Auto-resolvable vs manual review distinction
- ✅ Breaking change detection via object_dependencies
- ✅ `can_merge_safely()` - Risk assessment function

This gave us confidence that the clarifications are architecturally sound.

---

## Files Updated

1. **`/home/lionel/code/pggit/.claude/PHASE_4_PLAN.md`**
   - Added "Clarified Implementation Details" section
   - Updated Architecture Overview with three-way merge
   - Updated Function 1 signature with merge_base parameter
   - Updated Function 3 with validation logic
   - Expanded test coverage section
   - Revised timeline from 3-4 to 5-6 days
   - Added detailed conflict classification matrix
   - Added UNION strategy rules per object type
   - Added breaking change detection rules

2. **`/home/lionel/code/pggit/.claude/PHASE_4_REVIEW.md`** (existing)
   - Documents the original 5 concerns and analysis

3. **`/home/lionel/code/pggit/.claude/PHASE_4_CLARIFICATIONS_SUMMARY.md`** (this file)
   - Summarizes what was addressed

---

## Ready for Implementation

All 5 clarifications have been addressed:

- ✅ Clarification #1: Conflict classification matrix with clear examples
- ✅ Clarification #2: UNION strategy rules per object type
- ✅ Clarification #3: Breaking change detection simplified rules
- ✅ Clarification #4: Merge_base parameter added to merge_branches()
- ✅ Clarification #5: Custom definition validation approach documented

**Phase 4 is now ready for implementation with complete technical clarity.**

---

## Next Steps

1. ✅ Review the updated PHASE_4_PLAN.md
2. ✅ Confirm all clarifications address your concerns
3. ⏭️ Approve Phase 4 implementation
4. ⏭️ Begin implementation with 5-6 day timeline

**Recommendation**: Phase 4 can now proceed with confidence that:
- All merge scenarios are clearly classified
- UNION strategy has explicit per-type rules
- Breaking changes are conservatively detected
- Three-way merge uses proper LCA algorithm
- Custom definitions are validated before applying
- Test coverage is comprehensive (40 tests)

---

**Review Completed**: 2025-12-26
**Status**: READY FOR IMPLEMENTATION ✅
