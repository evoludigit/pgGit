# Phase 4: Merge Operations Implementation Plan

**Status**: Ready for Implementation (Step 0 Complete)
**Phase**: 4 of 7
**Complexity**: High - Core feature with conflict detection & resolution
**Estimated Scope**: 5-6 days implementation + testing
**Goal**: Enable merging branches with conflict detection and resolution strategies

**Pre-Implementation Documents**:
- ✅ PHASE_4_PLAN.md (this file) - Main specification
- ✅ PHASE_4_REVIEW.md - Technical review & concerns
- ✅ PHASE_4_CLARIFICATIONS_SUMMARY.md - All 5 clarifications addressed
- ✅ PHASE_4_QUICK_REFERENCE.md - One-page lookup guide
- ✅ PHASE_4_STEP_0_FIXTURES.md - **NEW**: Fixture architecture + pseudo code from backup
- ✅ PHASE_4_INDEX.md - Documentation navigation guide

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
   - Supports three-way merge with automatic merge-base discovery

2. **Strategy-Based Resolution**
   - Different strategies for different conflict scenarios
   - Manual override for complex cases
   - Audit trail of decisions made

3. **Conflict Classification (Three-Way Merge)**
   - Uses **base branch** to determine true conflicts from independent changes
   - Classifies conflicts as: NO_CONFLICT, SOURCE_MODIFIED, TARGET_MODIFIED, BOTH_MODIFIED, DELETED_SOURCE, DELETED_TARGET
   - Auto-resolvable conflicts: SOURCE_MODIFIED (target unchanged), TARGET_MODIFIED (source unchanged), DELETED_SOURCE, DELETED_TARGET
   - Manual review required: BOTH_MODIFIED (both branches changed independently)
   - Breaking changes detected via dependency graph (objects with dependents being dropped)

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

## Clarified Implementation Details

### Conflict Classification Matrix (Three-Way Merge)

The conflict classification uses three-way merge logic: comparing base → source → target.

| Base State | Source Change | Target Change | Classification | Auto-Resolvable | Action |
|-----------|---------------|---------------|-----------------|-----------------|--------|
| EXISTS | MODIFIED | UNCHANGED | SOURCE_MODIFIED | ✅ YES | Apply source change to target |
| EXISTS | UNCHANGED | MODIFIED | TARGET_MODIFIED | ✅ YES | Keep target change (source didn't change) |
| EXISTS | DELETED | UNCHANGED | DELETED_SOURCE | ✅ YES | Delete from target |
| EXISTS | UNCHANGED | DELETED | DELETED_TARGET | ✅ YES | Object already deleted, no action |
| EXISTS | MODIFIED | MODIFIED (different) | BOTH_MODIFIED | ❌ NO | Requires manual review |
| EXISTS | DELETED | MODIFIED | BOTH_MODIFIED | ❌ NO | Source deleted but target changed - conflict |
| NOT EXISTS | ADDED | NOT ADDED | ADDED | ✅ YES | Apply source's addition |
| NOT EXISTS | NOT ADDED | ADDED | ADDED | ✅ YES | Keep target's addition |
| NOT EXISTS | ADDED (same) | ADDED (same) | NO_CONFLICT | ✅ YES | Both added identical definition - no conflict |
| NOT EXISTS | ADDED | ADDED (different) | BOTH_MODIFIED | ❌ NO | Both added differently - requires review |

**Key Insight**: This is true three-way merge semantics:
- If only one branch changed something, it's auto-resolvable (safe to apply)
- If both branches changed something independently, it's a conflict requiring manual review
- This prevents the "lost deletion" problem where one branch deletes while other modifies

### UNION Strategy Details

The UNION strategy merges compatible objects without conflicts. Here are the rules per object type:

| Object Type | UNION Behavior | Notes |
|-------------|---|---|
| **TABLE** | Merge ADD COLUMN statements from both branches | Error if same column added differently. Indexes and constraints require MANUAL_REVIEW |
| **TRIGGER** | Merge non-overlapping ON clauses (e.g., one adds INSERT trigger, other adds UPDATE trigger) | Error if both add trigger for same event |
| **INDEX** | Merge ADD INDEX statements (error if same index name) | No UNION support for index modifications |
| **FUNCTION/PROCEDURE** | **NOT SUPPORTED** - use MANUAL_REVIEW | Code merging requires semantic understanding |
| **VIEW** | **NOT SUPPORTED** - use MANUAL_REVIEW | View definitions are complex to merge safely |
| **SEQUENCE/DOMAIN** | **NOT SUPPORTED** - use MANUAL_REVIEW | Too risky to auto-merge |

**Practical UNION Examples**:
```
✅ WORKS: Table A adds column, Table B adds different column → merge both
✅ WORKS: Trigger for INSERT on Table A, Trigger for UPDATE on Table A → merge both
❌ FAILS: Function body modified on both branches → MANUAL_REVIEW required
❌ FAILS: Trigger ON INSERT added on both branches → conflict, even though same event
```

**Implementation**: For UNION strategy in merge_branches():
1. Filter conflicts to only those with BOTH_MODIFIED classification
2. For each BOTH_MODIFIED:
   - If object_type in (TABLE, TRIGGER, INDEX):
     - Attempt smart merge (combine ADD COLUMN, combine non-overlapping triggers)
     - If merge succeeds, apply result
     - If merge fails, fall back to MANUAL_REVIEW behavior
   - Else: Fall back to MANUAL_REVIEW (don't attempt merge)

### Breaking Change Detection Rules

Breaking changes are detected conservatively to avoid false positives:

**Detected as Breaking**:
1. ✅ **DROP operations on objects with dependents**
   - Query object_dependencies table
   - If dependent_object_id references this object, flag as breaking
   - Example: DROP TABLE that's referenced by foreign keys

2. ✅ **DROP operations on critical object types**
   - TABLE, FUNCTION, VIEW drops are always flagged as MAJOR severity
   - TRIGGER/INDEX drops are flagged as MINOR severity

**NOT detected as breaking** (require manual review):
- Column renames (detected as MODIFIED, needs manual inspection)
- Parameter additions to functions (requires SQL parsing)
- Constraint modifications (requires semantic understanding)
- Schema restructuring

**Implementation**: In detect_merge_conflicts():
```sql
-- Check if object being dropped has dependents
SELECT COUNT(*) FROM pggit.object_dependencies
WHERE depends_on_object_id = current_object_id
  AND is_active = true;

-- If count > 0 and object is being DROPPED, flag severity as MAJOR
```

---

## Implementation Pseudo Code (from v0.1.1.bk backup)

**NOTE**: The following pseudo code sections are extracted from the backup implementation at `/home/lionel/code/pggit.v0.1.1.bk/sql/04_merge_operations.sql`. These provide proven patterns and algorithms for implementation.

### Pseudo Code 1: LCA (Lowest Common Ancestor) Algorithm

**Algorithm Overview** (lines 41-157 of backup):

```
find_merge_base(branch1_id, branch2_id) RETURNS base_branch_id, depths:

  1. VALIDATE:
     - Both branch IDs not NULL
     - Both branches exist
     - Return if branches identical

  2. BUILD ANCESTRY PATHS with RECURSIVE CTE:
     ancestry1: Start with branch1, recursively fetch parent_branch_id
     ancestry2: Start with branch2, recursively fetch parent_branch_id

     WITH RECURSIVE ancestry1 AS (
       SELECT id, parent_id, 0 AS depth FROM branches WHERE id = branch1_id
       UNION ALL
       SELECT b.id, b.parent_id, a.depth + 1
       FROM branches b
       JOIN ancestry1 a ON b.id = a.parent_id
       WHERE a.parent_id IS NOT NULL
     )

  3. FIND COMMON ANCESTOR via FULL OUTER JOIN:
     - Join ancestry1 and ancestry2 on ID
     - Find first row where both are NOT NULL
     - Order by depth DESC to get closest common ancestor
     - LIMIT 1

  4. FALLBACK if no common ancestor:
     - Walk ancestry1 to root (parent_id IS NULL)
     - Use that as base
     - Mark distance to branch2 as 999

  5. RETURN base_branch_id, base_branch_name, depth_from_branch1, depth_from_branch2

Key characteristics:
- O(H1 + H2) complexity where H is branch tree height
- Handles unbalanced trees
- Recursion stops at root (parent_id IS NULL)
```

**Implementation notes for pggit.merge_branches():**
- Call find_merge_base(source_branch_id, target_branch_id) to auto-discover base
- If p_merge_base_branch parameter provided, use that instead
- Fall back to main (id=1) if no LCA found
- Store depth metrics for user visibility

---

### Pseudo Code 2: Three-Way Merge Conflict Detection

**Algorithm Overview** (lines 192-345 of backup):

```
detect_merge_conflicts(source_id, target_id, base_id) RETURNS conflicts:

  1. AUTO-DETECT BASE if not provided:
     IF p_base_branch_id IS NULL:
       v_base_id := find_merge_base(source_id, target_id).base_branch_id
       IF NULL: v_base_id := 1  -- default to main

  2. LOAD OBJECTS from each branch:
     source_objs := SELECT * FROM schema_objects WHERE branch_id = source_id
     target_objs := SELECT * FROM schema_objects WHERE branch_id = target_id
     base_objs := SELECT * FROM schema_objects WHERE branch_id = v_base_id

  3. FULL OUTER JOIN all three:
     all_objects := FULL OUTER JOIN on (object_type, schema_name, object_name)

     Result: One row per unique object, with NULLs where object doesn't exist

  4. CLASSIFY each object using THREE-WAY MERGE logic:

     CASE base_hash, source_hash, target_hash:

       -- No changes at all
       WHEN (NULL, NULL, NULL) OR (H, H, H) → 'NO_CONFLICT'

       -- Deletions
       WHEN source IS NULL AND target IS NOT NULL AND base IS NOT NULL
         → 'DELETED_SOURCE' (auto-resolvable: delete)

       WHEN target IS NULL AND source IS NOT NULL AND base IS NOT NULL
         → 'DELETED_TARGET' (auto-resolvable: already gone)

       -- Modifications (one branch changes, other doesn't)
       WHEN base_hash = target_hash AND source_hash != base_hash
         → 'SOURCE_MODIFIED' (auto-resolvable: apply source change)

       WHEN base_hash = source_hash AND target_hash != base_hash
         → 'TARGET_MODIFIED' (auto-resolvable: keep target change)

       -- Additions (both add new)
       WHEN base IS NULL AND source_hash = target_hash
         → 'NO_CONFLICT' (both added identical)

       WHEN base IS NULL AND source_hash != target_hash
         → 'BOTH_MODIFIED' (both added different: conflict)

       -- True conflicts (both modified differently)
       WHEN source_hash != base_hash AND target_hash != base_hash
         → 'BOTH_MODIFIED' (conflict: requires manual review)

       -- Default for edge cases
       ELSE → 'BOTH_MODIFIED'

  5. DETERMINE SEVERITY:
     CASE
       WHEN object_type IN ('TABLE','FUNCTION','VIEW') AND deleted: 'MAJOR'
       WHEN object IS NULL in base: 'MAJOR'  -- new object with conflict
       ELSE: 'MINOR'

  6. CHECK DEPENDENCIES:
     -- Query object_dependencies table
     -- If object being dropped has dependents: severity = 'MAJOR'
     -- Treat as non-auto-resolvable

  7. RETURN only conflicts (WHERE conflict_type != 'NO_CONFLICT'):
     RETURN conflict_id, object_type, schema_name, object_name,
            conflict_type, base_hash, source_hash, target_hash,
            auto_resolvable, severity, dependencies_count
```

**Key insight**: This is TRUE three-way merge (not two-way diff). The base branch is essential for determining whether changes are independent or conflicting.

---

### Pseudo Code 3: Merge Strategy Application

**Algorithm Overview** (lines 706-767 of backup):

```
merge_branches strategy logic:

  After detecting conflicts with count:
    total_conflicts, auto_resolvable_count, manual_count

  APPLY STRATEGY:

    CASE p_merge_strategy:

      WHEN 'ABORT_ON_CONFLICT':
        IF total_conflicts > 0:
          RAISE EXCEPTION 'Merge aborted due to conflicts'
          RETURN status='ABORTED'
        ELSE:
          Proceed with merge

      WHEN 'TARGET_WINS':
        FOR EACH conflict WHERE type IN (SOURCE_MODIFIED, BOTH_MODIFIED):
          source_definition := get_object(source_id, object_id)
          target_definition := get_object(target_id, object_id)
          -- Use TARGET definition, ignore source
          apply(target_id, object_id, target_definition)
        merge_complete := true

      WHEN 'SOURCE_WINS':
        FOR EACH conflict WHERE type IN (TARGET_MODIFIED, BOTH_MODIFIED):
          source_definition := get_object(source_id, object_id)
          target_definition := get_object(target_id, object_id)
          -- Use SOURCE definition, override target
          apply(target_id, object_id, source_definition)
        merge_complete := true

      WHEN 'UNION':
        FOR EACH conflict:
          IF object_type = 'TABLE':
            result := try_merge_table_columns(source, target)
            IF result NOT NULL:
              apply(target_id, object_id, result)
            ELSE:
              mark_for_manual_review(conflict_id)

          ELSE IF object_type = 'TRIGGER':
            result := try_merge_triggers(source, target)
            IF result NOT NULL:
              apply(target_id, object_id, result)
            ELSE:
              mark_for_manual_review(conflict_id)

          ELSE:
            -- FUNCTION, VIEW unsupported
            mark_for_manual_review(conflict_id)

        IF any unresolved:
          merge_complete := false
          status := 'CONFLICT'
        ELSE:
          merge_complete := true
          status := 'SUCCESS'

      WHEN 'MANUAL_REVIEW':
        FOR EACH conflict:
          mark_for_manual_review(conflict_id)
        merge_complete := false
        status := 'CONFLICT'
        RETURN (user must call resolve_conflict() for each)

  CREATE RESULT COMMIT:
    result_commit_hash := compute_hash(merged_objects)
    INSERT INTO commits:
      branch_id = target_id
      commit_message = p_merge_message OR 'Merge source → target'
      objects_hash = result_commit_hash
      created_by = CURRENT_USER

  UPDATE MERGE OPERATIONS RECORD:
    INSERT into merge_operations:
      merge_id = generated_uuid()
      source_branch_id = source_id
      target_branch_id = target_id
      merge_strategy = p_merge_strategy
      status = status
      conflicts_detected = total_conflicts
      result_commit_hash = result_commit_hash
      merged_at = NOW()

  IF merge_complete:
    UPDATE branches SET status='MERGED' WHERE id = source_id

  RETURN merge_id, status, conflicts_detected, auto_resolvable_count,
         manual_count, merge_complete, result_commit_hash
```

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
    p_merge_base_branch TEXT DEFAULT NULL,
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

**Parameters**:
- `p_source_branch`: Branch to merge FROM (required)
- `p_target_branch`: Branch to merge INTO (required)
- `p_merge_strategy`: Strategy for conflict resolution, default ABORT_ON_CONFLICT (safe)
- `p_merge_message`: Commit message for merge (optional)
- `p_merge_base_branch`: Base branch for three-way merge (optional, auto-detected if NULL)
- `p_metadata`: Additional JSONB metadata (optional)

**Implementation Steps**:

1. **Validation & Merge Base Detection** (30 lines)
   - Validate branch names exist and are ACTIVE
   - Validate merge_strategy is in allowed list
   - Prevent merging with deleted branches
   - Prevent self-merge (source != target)
   - **NEW**: If p_merge_base_branch is NULL:
     - Use helper function (or inline logic) to find LCA (Lowest Common Ancestor)
     - LCA logic: traverse parent_branch_id for both branches, find first common ancestor
     - If no LCA found, default to 'main' as merge base
   - If p_merge_base_branch provided, validate it exists

2. **Conflict Detection** (60 lines)
   - Call `pggit.detect_merge_conflicts(p_source_branch, p_target_branch, v_merge_base_branch_id)`
   - This performs three-way merge analysis:
     - Compares base → source vs base → target
     - Classifies as: SOURCE_MODIFIED, TARGET_MODIFIED, BOTH_MODIFIED, DELETED_SOURCE, DELETED_TARGET
   - Count conflicts:
     - auto_resolvable_count = SOURCE_MODIFIED + TARGET_MODIFIED + DELETED_*
     - manual_required_count = BOTH_MODIFIED
   - If auto_resolvable_count > 0 and strategy supports it, these are safe to apply

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

1. **Validation** (35 lines)
   - Verify merge_id exists and is MANUAL_REVIEW status
   - Verify object_id is involved in this merge
   - Verify object is in conflict state
   - Validate resolution_choice in ('SOURCE', 'TARGET', 'CUSTOM')
   - If CUSTOM:
     - Validate p_custom_definition is not null
     - **NEW**: Validate SQL syntax via PostgreSQL parser:
       ```sql
       BEGIN
         EXECUTE 'EXPLAIN (FORMAT JSON) ' || p_custom_definition LIMIT 0;
       EXCEPTION WHEN OTHERS THEN
         RAISE EXCEPTION 'Custom definition has syntax errors: %', SQLERRM;
       END;
       ```
     - If validation fails, reject the resolution with clear error message

2. **Record Resolution** (25 lines)
   - Get current conflict_details from merge_operations
   - Find the object in conflict_details
   - Mark as resolved with user's choice
   - If CUSTOM: compute hash via pggit.compute_hash(p_custom_definition)
   - Update merge_operations.conflict_details with resolution choice and timestamp
   - Store user who performed resolution in resolution_summary

3. **Apply Resolution** (40 lines)
   - If SOURCE: use source branch's object definition
   - If TARGET: use target branch's object definition
   - If CUSTOM: use provided custom definition (already validated)
   - Update schema_objects with chosen definition and new content_hash
   - Create object_history record: change_type='MERGE', severity='MAJOR'
   - Update result_commit with merged objects

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

## Documentation Examples

### Example 1: ABORT_ON_CONFLICT Strategy (Safest)

**Use Case**: Production merge where safety is paramount

```sql
-- Check for conflicts first
SELECT * FROM pggit.detect_merge_conflicts('feature-a', 'main');
-- Result: 0 rows = no conflicts

-- Safe to merge
SELECT * FROM pggit.merge_branches(
    'feature-a',
    'main',
    'ABORT_ON_CONFLICT',
    'Merge feature-a: Add user preferences feature'
);
-- Result: status='SUCCESS', conflicts_detected=0, objects_merged=5

-- Target branch now contains all changes from feature-a
-- Branch feature-a status = MERGED
```

---

### Example 2: TARGET_WINS Strategy (Discard Source)

**Use Case**: Source branch changes were experimental, target has correct version

```sql
-- Preview what would be lost
SELECT * FROM pggit.detect_merge_conflicts('experimental', 'main');
-- Result: users table MODIFIED on both (experimental version would be discarded)

-- Merge with TARGET_WINS
SELECT * FROM pggit.merge_branches(
    'experimental',
    'main',
    'TARGET_WINS',
    'Merge experimental: Discard experimental users table changes'
);
-- Result: status='SUCCESS', conflicts_resolved=1
-- Main branch keeps its users table definition
-- experimental branch marked MERGED
```

---

### Example 3: SOURCE_WINS Strategy (Accept Source)

**Use Case**: Source branch has critical bug fixes that target doesn't have

```sql
-- Preview incoming changes
SELECT * FROM pggit.detect_merge_conflicts('hotfix-critical', 'staging');
-- Result: payment_processor function MODIFIED on both

-- Accept all source changes
SELECT * FROM pggit.merge_branches(
    'hotfix-critical',
    'staging',
    'SOURCE_WINS',
    'Merge hotfix-critical: Apply critical payment processor fixes'
);
-- Result: status='SUCCESS', conflicts_resolved=1
-- Staging branch now has hotfix-critical's payment_processor implementation
```

---

### Example 4: UNION Strategy (Merge Compatible Changes)

**Use Case**: Both branches added non-conflicting features to same object

```sql
-- Analyze conflicts
SELECT * FROM pggit.detect_merge_conflicts('feature-logging', 'feature-metrics');
-- Result: orders table MODIFIED
--   - feature-logging: Added logging trigger
--   - feature-metrics: Added metrics trigger
--   Both triggers target same table but different operations

-- Merge compatible changes
SELECT * FROM pggit.merge_branches(
    'feature-logging',
    'feature-metrics',
    'UNION',
    'Merge feature-logging: Combine logging and metrics for orders table'
);
-- Result: status='SUCCESS', objects_merged=1
-- orders table now has BOTH logging AND metrics triggers
-- Combined definition created via union logic
```

---

### Example 5: MANUAL_REVIEW Strategy (Conditional Merge)

**Use Case**: Complex conflicts requiring human judgment

```sql
-- Identify conflicts
SELECT * FROM pggit.detect_merge_conflicts('refactor-users', 'main');
-- Result: users table MODIFIED on both
--   - refactor-users: Restructured columns, new business logic
--   - main: Added audit columns, different security approach
--   Conflict reason: "Divergent changes - both modified incompatibly"

-- Start merge with manual review
SELECT * FROM pggit.merge_branches(
    'refactor-users',
    'main',
    'MANUAL_REVIEW',
    'Merge refactor-users: Requires manual resolution'
);
-- Result: status='CONFLICT', merge_id='abc-123-def'
-- conflicts_detected=1, conflicts_resolved=0
-- Merge is created but NOT finalized

-- User examines conflict details
SELECT conflict_details FROM pggit.merge_operations
WHERE merge_id = 'abc-123-def';
-- Can see full diff of both versions

-- User decides to use SOURCE_WINS for this specific object
SELECT * FROM pggit.resolve_conflict(
    'abc-123-def',
    object_id_for_users_table,
    'SOURCE',
    NULL
);
-- Result: conflicts_resolved=1 (now equals conflicts_detected)
-- Merge status automatically updates to SUCCESS
-- Result commit finalized with refactor-users version of users table
```

---

### Example 6: CUSTOM Resolution Strategy

**Use Case**: Manually crafted definition combining both versions

```sql
-- Start with MANUAL_REVIEW
-- (merge_id='xyz-456', 1 conflict detected)

-- User creates custom definition by hand-merging both versions
-- Combines refactor-users structure + main's audit columns
SELECT * FROM pggit.resolve_conflict(
    'xyz-456',
    object_id_for_users_table,
    'CUSTOM',
    'CREATE TABLE schema.users (
        id SERIAL PRIMARY KEY,
        email VARCHAR(255) NOT NULL,
        status VARCHAR(50),
        -- refactor-users restructuring
        profile_data JSONB,
        -- main audit columns
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW(),
        updated_by VARCHAR(255)
    )'
);
-- Result: Custom definition validated and applied
-- conflicts_resolved=1
-- Merge status = SUCCESS
-- Result commit contains custom merged version
```

---

## Rollback & Undo Strategy

This section clarifies what happens if a merge causes problems and needs to be undone.

### Current Phase 4 Scope (What's Implemented)

Phase 4 creates merge records in `merge_operations` table with full audit trail:
- Which branches merged
- What merge strategy was used
- Which objects changed
- Result commit hash
- Timestamp and user who performed merge

**This enables future rollback capability** by:
1. Knowing exactly what the previous state was (via commits & object_history)
2. Having a permanent record of the merge decision
3. Allowing Phase 5-6 to implement rollback functions

### Proposed Phase 5/6 Rollback Capabilities (OUT OF SCOPE FOR PHASE 4)

While Phase 4 doesn't implement rollback, it sets the foundation:

**Option A: Revert Merge (Simple)**
```sql
-- Would be added in Phase 5
pggit.revert_merge(p_merge_id UUID)
-- Finds result_commit from merge_operations
-- Creates new commit restoring previous state
-- Useful when: merge was correct but caused downstream issues
```

**Option B: Abort Merge (Soft Delete)**
```sql
-- Would be added in Phase 5
pggit.abort_merge(p_merge_id UUID)
-- Marks merge as ABORTED without changing current state
-- Useful when: merge failed partway through manual resolution
```

**Option C: Branch Rollback**
```sql
-- Would be added in Phase 6
pggit.checkout_commit(p_branch_name TEXT, p_commit_hash CHAR(64))
-- Restore branch to previous commit state
-- Allows time-travel within branch history
```

### Why Rollback Is Phase 5+ Not Phase 4

1. **Phase 4 Foundation**: Merge creates immutable audit trail + result commits
2. **Phase 5 Complexity**: Rollback requires:
   - Validating rollback won't break dependent objects
   - Handling cascade scenarios (if Branch A merged B, and C merged A, what does rollback do?)
   - Transaction semantics (do we want git-style revert or hard reset?)
3. **Phase 6 Advanced**: Time-travel, branch history inspection, bisect-style debugging

### Phase 4 Prevents Problems

Even without rollback, Phase 4 reduces need for undo:

1. **detect_merge_conflicts()** - Preview before merging prevents wrong merges
2. **ABORT_ON_CONFLICT** - Default strategy is safe (returns without changing anything)
3. **MANUAL_REVIEW** - Complex merges require explicit resolution
4. **Audit Trail** - Full history means you can always see what happened
5. **Result Commits** - Each merge creates immutable snapshot you can inspect

### Recommended Phase 4 Testing for Future Rollback Support

Tests should verify merge_operations records are complete:
- ✅ merge_id is unique and traceable
- ✅ source_branch_id, target_branch_id stored correctly
- ✅ result_commit_hash points to valid commit
- ✅ conflict_details JSONB captures full conflict info
- ✅ resolution_summary captures how conflicts were resolved

This ensures Phase 5 can implement rollback without data loss or ambiguity.

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

class TestDetectMergeConflicts:  # 10 tests (expanded from 8)
    - test_detect_no_conflicts
    - test_detect_source_modified_only
    - test_detect_target_modified_only
    - test_detect_both_modified_conflict
    - test_detect_deleted_source
    - test_detect_deleted_target
    - test_detect_three_way_merge_with_base
    - test_detect_breaking_change_with_dependents
    - test_detect_dependency_impact_count
    - test_detect_complex_scenario

class TestResolveConflict:       # 8 tests
    - test_resolve_with_source_choice
    - test_resolve_with_target_choice
    - test_resolve_with_valid_custom_definition
    - test_resolve_rejects_invalid_custom_definition
    - test_resolve_invalid_merge_id
    - test_resolve_single_conflict_completes
    - test_resolve_multiple_conflicts_partial
    - test_resolve_shows_progress

class TestIntegration:           # 6 tests (NEW)
    - test_merge_with_auto_discovered_merge_base
    - test_merge_with_explicit_merge_base
    - test_union_strategy_merges_compatible_columns
    - test_union_strategy_merges_non_overlapping_triggers
    - test_union_strategy_falls_back_on_complex_objects
    - test_full_workflow_detect_review_resolve
```

**Total**: 34 unit tests + 6 integration tests = 40 comprehensive tests

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

**Revised Estimated Breakdown** (based on added complexity):
- pggit.merge_branches(): 1.5 days (merge_base discovery + strategy application)
- pggit.detect_merge_conflicts(): 1.5 days (three-way merge + breaking change detection)
- pggit.resolve_conflict(): 1 day (validation + custom definition handling)
- Unit Testing (34 tests): 1.5 days (test fixture setup + all scenarios)
- Integration Testing (6 tests): 1 day (workflow validation)
- Documentation & QA: 0.5 days
- **Total: 5-6 days** (revised from 3-4 days due to clarifications)

**Key Milestones**:
- Day 1-1.5: merge_branches() complete with merge_base discovery
- Day 2: detect_merge_conflicts() with three-way merge analysis
- Day 2-2.5: resolve_conflict() with validation
- Day 3: Unit testing (34 tests) + fixes
- Day 4: Integration testing (6 tests) + cross-function validation
- Day 5: QA report + performance validation + commit with [GREEN] tag

**Why 5-6 days instead of 3-4?**
1. Merge base discovery adds complexity (LCA algorithm)
2. Three-way merge logic more intricate than two-way comparison
3. UNION strategy requires per-object-type merge rules
4. Custom definition validation requires SQL parsing
5. Integration tests verify complex multi-step workflows
6. Breaking change detection needs dependency graph analysis

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
