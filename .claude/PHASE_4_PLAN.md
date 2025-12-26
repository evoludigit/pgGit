# Phase 4: Merge Operations Implementation Plan

**Status**: Ready for Planning & Approval
**Phase**: 4 of 7
**Complexity**: High - Core feature with conflict detection & resolution
**Estimated Scope**: 3-4 days implementation + testing
**Goal**: Enable merging branches with conflict detection and resolution strategies

---

## Executive Summary

Phase 4 implements the **Merge Operations API** - three critical functions that enable users to merge branches with sophisticated conflict detection and multiple resolution strategies. This phase bridges Phases 1-3 (foundation & visibility) with Phases 5-7 (advanced features).

### Key Deliverables

1. **pggit.merge_branches()** - Execute merge with conflict detection & strategy-based resolution
2. **pggit.detect_merge_conflicts()** - Identify conflicts before merge with 3-way merge support
3. **pggit.resolve_conflict()** - Manually resolve conflicts in multi-conflict merges

### Success Criteria

- [ ] All 3 functions implemented with exact API spec
- [ ] 24-28 comprehensive unit tests (8-10 per function)
- [ ] 100% test pass rate
- [ ] Support all 5 merge strategies (TARGET_WINS, SOURCE_WINS, UNION, MANUAL_REVIEW, ABORT_ON_CONFLICT)
- [ ] Conflict detection works for all object types
- [ ] Dependency validation integrated
- [ ] Full audit trail in merge_operations table
- [ ] Clear git commits with [GREEN] tags

---

## Architecture Overview

### Design Principles

1. **Two-Phase Merge Pattern**
   - Phase A: Detect conflicts (read-only, uses Phase 3 diff_branches)
   - Phase B: Resolve conflicts and create result commit
   - Enables safe preview before actual merge

2. **Strategy-Based Resolution**
   - Different strategies for different conflict scenarios
   - Manual override for complex cases
   - Audit trail of decisions made

3. **Conflict Classification**
   - MODIFIED on both branches = Definite conflict
   - ADDED/REMOVED on one branch = Auto-resolvable
   - Breaking changes flagged via dependency graph

4. **Content-Hash Driven**
   - Uses Phase 1 compute_hash() for reproducibility
   - Leverages Phase 3 diff_branches() for efficient comparison
   - Immutable audit trail via merge_operations table

5. **Dependency-Aware**
   - Uses pggit.object_dependencies for impact analysis
   - Detects cascading failures from dropping required objects
   - Warns about breaking changes

### Dependencies on Previous Phases

**Phase 1 (Schema Foundation):**
- `pggit.branches` table for branch metadata
- `pggit.commits` table for commit creation
- `pggit.schema_objects` for object definitions
- `pggit.object_history` for change tracking
- `pggit.object_dependencies` for dependency graph
- `pggit.merge_operations` table for merge tracking
- Utility functions: `compute_hash()`, `get_branch_by_name()`, `validate_identifier()`

**Phase 2 (Branch Management):**
- `pggit.checkout_branch()` to switch context
- Session variable `pggit.current_branch` for context awareness
- `pggit.set_current_branch()` to update merge base

**Phase 3 (Object Tracking & Visibility):**
- `pggit.diff_branches()` for conflict detection
- `pggit.get_branch_objects()` to query merged state
- `pggit.get_object_history()` for change tracking

---

## Implementation Details

### Function 1: pggit.merge_branches()

**Purpose**: Execute merge with automatic conflict detection and strategy-based resolution

**Signature**:
```sql
CREATE OR REPLACE FUNCTION pggit.merge_branches(
    p_source_branch TEXT,
    p_target_branch TEXT,
    p_merge_strategy TEXT DEFAULT 'ABORT_ON_CONFLICT',
    p_merge_message TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT NULL
) RETURNS TABLE (
    merge_id UUID,
    status TEXT,
    conflicts_detected INTEGER,
    conflicts_resolved INTEGER,
    objects_merged INTEGER,
    result_commit_hash CHAR(64),
    description TEXT
) AS $$
```

**Implementation Steps**:

1. **Validation** (20 lines)
   - Validate branch names exist and are ACTIVE
   - Validate merge_strategy is in allowed list
   - Prevent merging with deleted branches
   - Prevent self-merge (source != target)

2. **Conflict Detection** (40 lines)
   - Call `pggit.diff_branches(p_source_branch, p_target_branch)`
   - Classify differences:
     - UNCHANGED = skip
     - ADDED = auto-merge (add to target)
     - REMOVED = auto-merge (remove from target)
     - MODIFIED = potential conflict
   - Count conflicts by type

3. **Strategy Application** (50 lines)
   - Check merge_strategy against conflicts_detected
   - ABORT_ON_CONFLICT: Return ABORTED if conflicts_detected > 0
   - TARGET_WINS: Use target branch definitions for all conflicts
   - SOURCE_WINS: Use source branch definitions for all conflicts
   - UNION: Merge compatible objects (trigger combinations, etc.)
   - MANUAL_REVIEW: Flag for manual resolution via resolve_conflict()

4. **Merge Execution** (40 lines)
   - For each changed object:
     - Update schema_objects with merged definition
     - Create object_history record documenting merge
     - Calculate new content_hash via compute_hash()
   - Create result commit with merge message
   - Update all object_history records to point to result_commit

5. **Finalization** (30 lines)
   - Update target branch status to MERGED
   - Record merge in merge_operations table:
     - merge_id, source_branch_id, target_branch_id
     - merge_strategy, status (SUCCESS/CONFLICT/ABORTED)
     - conflicts_detected, objects_merged
     - result_commit_hash, merged_by, merged_at
   - Return merge result

**Complexity**: High - 180+ lines
**Dependencies**: Phase 3 diff_branches(), Phase 1 utilities

**Test Cases** (10):
1. Happy path - merge two branches with no conflicts
2. ABORT_ON_CONFLICT with conflicts - returns ABORTED
3. TARGET_WINS strategy - target definitions preserved
4. SOURCE_WINS strategy - source definitions override
5. UNION strategy - compatible changes merged
6. MANUAL_REVIEW strategy - returns CONFLICT status
7. Self-merge rejected (source = target)
8. Deleted branch merge rejected
9. Invalid strategy rejected
10. Merge creates result commit in commits table

---

### Function 2: pggit.detect_merge_conflicts()

**Purpose**: Preview merge conflicts before execution (read-only analysis)

**Signature**:
```sql
CREATE OR REPLACE FUNCTION pggit.detect_merge_conflicts(
    p_source_branch TEXT,
    p_target_branch TEXT,
    p_merge_base_branch TEXT DEFAULT NULL
) RETURNS TABLE (
    object_type TEXT,
    schema_name TEXT,
    object_name TEXT,
    full_name TEXT,
    change_type TEXT,
    is_breaking_change BOOLEAN,
    dependency_impact_count INTEGER,
    source_hash CHAR(64),
    target_hash CHAR(64),
    base_hash CHAR(64),
    conflict_reason TEXT,
    suggested_resolution TEXT
) AS $$
```

**Implementation Steps**:

1. **Base Diff** (30 lines)
   - Call `pggit.diff_branches(p_source_branch, p_target_branch)`
   - Filter to only MODIFIED changes (true conflicts)
   - Store results in CTE for analysis

2. **Three-Way Merge Analysis** (40 lines)
   - If merge_base provided:
     - Call `pggit.diff_branches(p_merge_base_branch, p_source_branch)`
     - Call `pggit.diff_branches(p_merge_base_branch, p_target_branch)`
     - Compare change patterns:
       - Base→Source differs, Base→Target same = Apply source change
       - Base→Source same, Base→Target differs = Apply target change
       - Base differs in both branches = CONFLICT
   - Classify conflicts:
     - "Divergent changes" = both modified differently
     - "Breaking change" = dropped required object
     - "Dependent object modified" = object that's referenced by others

3. **Dependency Analysis** (40 lines)
   - For each conflicting object:
     - Query `pggit.object_dependencies` table
     - Find objects that depend on this one
     - Count dependents: `dependency_impact_count`
     - Flag as breaking change if:
       - Object is being DROPPED AND has dependents
       - Object signature changed AND dependents may break
   - Suggest resolution based on impact:
     - No impact: "Can use either version"
     - Minor impact: "Check dependent objects"
     - Major impact: "Breaking change - manual review required"

4. **Suggest Resolutions** (30 lines)
   - Analyze change patterns to suggest resolution:
     - If source added feature, target didn't change: "Apply source"
     - If target made critical fix, source didn't change: "Apply target"
     - If both changed incompatibly: "Manual review required"
     - If union-mergeable: "Can combine changes"

**Complexity**: Medium-High - 140+ lines
**Dependencies**: Phase 3 diff_branches(), object_dependencies table

**Test Cases** (8):
1. No conflicts - empty result
2. Single MODIFIED conflict - returned with details
3. Multiple conflicts - all returned
4. Three-way merge - base→source vs base→target analysis
5. Breaking change detection - dropping referenced object
6. Dependency impact count - counts dependents
7. Suggest resolution analysis - provides suggestions
8. Complex scenario - multiple objects with cross-dependencies

---

### Function 3: pggit.resolve_conflict()

**Purpose**: Manually resolve conflicts in multi-conflict merges (MANUAL_REVIEW status)

**Signature**:
```sql
CREATE OR REPLACE FUNCTION pggit.resolve_conflict(
    p_merge_id UUID,
    p_object_id BIGINT,
    p_resolution_choice TEXT,  -- 'SOURCE' | 'TARGET' | 'CUSTOM'
    p_custom_definition TEXT DEFAULT NULL
) RETURNS TABLE (
    merge_id UUID,
    status TEXT,
    conflicts_detected INTEGER,
    conflicts_resolved INTEGER,
    objects_merged INTEGER,
    all_conflicts_resolved BOOLEAN,
    description TEXT
) AS $$
```

**Implementation Steps**:

1. **Validation** (25 lines)
   - Verify merge_id exists and is MANUAL_REVIEW status
   - Verify object_id is involved in this merge
   - Verify object is in conflict state
   - Validate resolution_choice in ('SOURCE', 'TARGET', 'CUSTOM')
   - If CUSTOM: validate p_custom_definition is not null

2. **Record Resolution** (20 lines)
   - Get current conflict_details from merge_operations
   - Find the object in conflict_details
   - Mark as resolved with user's choice
   - If CUSTOM: validate custom definition with compute_hash()
   - Update merge_operations.conflict_details

3. **Apply Resolution** (30 lines)
   - If SOURCE: use source branch's object definition
   - If TARGET: use target branch's object definition
   - If CUSTOM: use provided custom definition
   - Update schema_objects with chosen definition
   - Create object_history record: change_type='MERGE', severity='MAJOR'
   - Update result_commit with new object state

4. **Update Counters** (20 lines)
   - Increment conflicts_resolved counter
   - Check if all conflicts now resolved:
     - If `conflicts_resolved == conflicts_detected`:
       - Set status = 'SUCCESS'
       - Mark merge as complete
   - Update resolution_summary with resolution details

5. **Finalization** (15 lines)
   - If all conflicts resolved:
     - Create final result commit with all merged objects
     - Return status='SUCCESS'
   - Else:
     - Return status='CONFLICT' with progress info
   - Return updated merge record

**Complexity**: Medium - 110+ lines
**Dependencies**: Phase 1 compute_hash(), Phase 3 diff_branches()

**Test Cases** (8):
1. Resolve conflict with SOURCE choice
2. Resolve conflict with TARGET choice
3. Resolve conflict with CUSTOM definition
4. Invalid merge_id rejected
5. Non-conflicting object rejected
6. Single conflict resolution completes merge
7. Multiple conflicts require multiple resolutions
8. Partial resolution shows progress (conflicts_resolved < conflicts_detected)

---

## Database Changes

### New SQL File

**Location**: `/home/lionel/code/pggit/sql/032_pggit_merge_operations.sql`

**Structure**:
```sql
-- Phase 4: Merge Operations (3 functions, ~450 lines total)
-- 1. pggit.merge_branches()           ~180 lines
-- 2. pggit.detect_merge_conflicts()   ~140 lines
-- 3. pggit.resolve_conflict()         ~110 lines
```

### No Schema Changes Required

The merge_operations table already exists from Phase 1 schema. Phase 4 only adds functions.

---

## Testing Strategy

### Unit Test File

**Location**: `/home/lionel/code/pggit/tests/unit/test_phase4_merge_operations.py`

**Test Structure**:
```python
class TestMergeBranches:          # 10 tests
    - test_merge_no_conflicts
    - test_merge_abort_on_conflict
    - test_merge_target_wins
    - test_merge_source_wins
    - test_merge_union_strategy
    - test_merge_manual_review
    - test_merge_self_rejected
    - test_merge_deleted_branch_rejected
    - test_merge_invalid_strategy
    - test_merge_creates_result_commit

class TestDetectMergeConflicts:  # 8 tests
    - test_detect_no_conflicts
    - test_detect_single_conflict
    - test_detect_multiple_conflicts
    - test_detect_three_way_merge
    - test_detect_breaking_change
    - test_detect_dependency_impact
    - test_detect_suggests_resolution
    - test_detect_complex_scenario

class TestResolveConflict:       # 8 tests
    - test_resolve_with_source_choice
    - test_resolve_with_target_choice
    - test_resolve_with_custom_definition
    - test_resolve_invalid_merge_id
    - test_resolve_non_conflicting_object
    - test_resolve_single_conflict_completes
    - test_resolve_multiple_conflicts_partial
    - test_resolve_shows_progress
```

**Total**: 26 unit tests

### Test Data Setup

Fixture creates:
- **Branch 1 (main)**: Base state with 4 objects (users, orders, views, functions)
- **Branch 2 (feature-a)**: Modified users table + added products table
- **Branch 3 (feature-b)**: Modified users table differently + dropped view
- **Merge scenarios**:
  - main→feature-a: Users conflict (both modified)
  - main→feature-b: Users conflict + view removed
  - feature-a→feature-b: Complex 3-way scenario

---

## Quality Checklist

### Code Quality
- [ ] Consistent with Phase 1-3 patterns
- [ ] Qualified table aliases (so., oh., etc.) to prevent ambiguity
- [ ] Comprehensive parameter validation
- [ ] Clear error messages with context
- [ ] Proper NULL handling and graceful degradation

### Documentation
- [ ] Inline comments explaining complex logic
- [ ] Parameter descriptions
- [ ] Return value documentation
- [ ] Examples for each merge strategy

### Error Handling
- [ ] Invalid branch names → descriptive error
- [ ] Deleted/inactive branches → descriptive error
- [ ] Self-merge prevention → descriptive error
- [ ] Invalid merge strategies → list valid options
- [ ] Missing custom definition → descriptive error
- [ ] Merge conflicts → proper CONFLICT status, not exception

### Performance
- [ ] Efficient use of diff_branches() (avoid redundant calls)
- [ ] Proper index usage on branch_id, object_type
- [ ] Minimal transaction overhead
- [ ] Batch updates when possible

---

## Implementation Workflow

### Step 1: Develop pggit.merge_branches()
- Implement core merge logic
- Support all 5 strategies
- Create 10 comprehensive tests
- Ensure 100% test pass rate

### Step 2: Develop pggit.detect_merge_conflicts()
- Implement conflict detection
- Add three-way merge support
- Implement dependency analysis
- Create 8 comprehensive tests
- Ensure 100% test pass rate

### Step 3: Develop pggit.resolve_conflict()
- Implement manual resolution
- Support custom definitions
- Update merge status tracking
- Create 8 comprehensive tests
- Ensure 100% test pass rate

### Step 4: Integration Testing
- Verify all 3 functions work together
- Test complex multi-branch scenarios
- Validate audit trail in merge_operations
- Confirm dependency analysis works

### Step 5: Commit & QA
- Commit with [GREEN] tag
- Run comprehensive QA report
- Verify no regression in Phases 1-3
- Document findings

---

## Success Metrics

### Code Coverage
- 26 unit tests with 100% pass rate
- All 3 functions tested thoroughly
- All merge strategies tested
- All error conditions tested

### Functionality
- Merge conflicts correctly detected
- All 5 merge strategies work properly
- Manual conflict resolution works
- Result commits created correctly
- Merge audit trail is complete

### Quality
- No performance issues
- Clear error messages
- Consistent with project patterns
- Well-documented code

---

## Risk Mitigation

### High-Risk Areas

1. **Conflict Detection Accuracy**
   - Risk: False positives/negatives in diff detection
   - Mitigation: Extensive test cases covering all object types
   - Validation: Cross-check with Phase 3 diff_branches()

2. **Complex Merge Scenarios**
   - Risk: Three-way merge logic errors
   - Mitigation: Detailed test cases with base branch
   - Validation: Manual review of complex scenarios

3. **Dependency Analysis**
   - Risk: Missing breaking change detection
   - Mitigation: Test dependency graph traversal
   - Validation: Test breaking changes across object types

4. **Transaction Safety**
   - Risk: Partial merge on error
   - Mitigation: Proper rollback on all error paths
   - Validation: Test error conditions mid-merge

---

## Dependencies & Blockers

### No External Blockers
- All required Phase 1-3 functions exist
- merge_operations table already created
- object_dependencies table available
- Tests can run independently

### Internal Dependencies
- Requires Phase 1 utilities (compute_hash, validate_identifier)
- Requires Phase 3 diff_branches() function
- Requires Phase 2 session variable support

---

## Timeline & Effort

**Estimated Breakdown**:
- pggit.merge_branches(): 1 day
- pggit.detect_merge_conflicts(): 1 day
- pggit.resolve_conflict(): 0.5 days
- Testing & QA: 1-1.5 days
- **Total: 3-4 days**

**Key Milestones**:
- Day 1: merge_branches() complete + 10 tests passing
- Day 2: detect_merge_conflicts() complete + 8 tests passing
- Day 3: resolve_conflict() complete + 8 tests passing + integration testing
- Day 4: QA report + commit

---

## Sign-Off Criteria

Before considering Phase 4 complete:

- [ ] All 3 functions implemented per spec
- [ ] All 26 unit tests passing (100%)
- [ ] All 5 merge strategies working
- [ ] Manual conflict resolution tested
- [ ] Dependency analysis validated
- [ ] No regression in Phase 1-3 tests
- [ ] Comprehensive inline documentation
- [ ] Git commit with [GREEN] tag
- [ ] QA report generated

---

## Next Phase (Phase 5)

Phase 5 will implement **Conflict Resolution & Advanced Merging**:
- Intelligent conflict resolution (beyond simple strategies)
- Semantic merge detection (understand code structure)
- Custom merge rules per object type
- Merge rollback/undo capability

---

**Plan Created**: December 26, 2025
**Status**: Ready for Review & Approval
**Questions/Changes**: Please review and provide feedback before implementation starts
