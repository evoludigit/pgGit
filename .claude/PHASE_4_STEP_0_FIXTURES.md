# Phase 4 Step 0: Test Fixtures & Implementation Patterns

**Status**: Pre-Implementation Planning
**Date**: 2025-12-26
**Purpose**: Design robust test fixtures and extract implementation patterns from backup

---

## Overview

This document provides:
1. **Enhanced Test Fixture Strategy** - Comprehensive test data setup for 40 tests
2. **Implementation Pseudo Code** - Extracted from backup implementation with annotations
3. **Fixture Patterns** - Reusable components for consistent test data
4. **Known Issues & Solutions** - Edge cases to handle

---

## Part 1: Enhanced Test Fixture Architecture

### Fixture Scope

The test fixture must support these test scenarios:

```
Base Scenario Setup:
├── Branch 1 (main) - Base state
├── Branch 2 (feature-a) - Modified + added objects
├── Branch 3 (feature-b) - Different modifications
└── Branch 4 (dev) - Long-lived branch

Merge Scenarios:
├── Simple merge (no conflicts)
├── Single object conflict
├── Multiple conflicts
├── Three-way merge with LCA
├── Breaking change detection
├── UNION strategy scenarios
└── Custom definition resolution
```

### Fixture Components

#### 1. **Branch Hierarchy**
```python
# Fixture structure
main (id=1, parent=None, status=ACTIVE)
├── feature-a (id=2, parent=1, status=ACTIVE)
├── feature-b (id=3, parent=1, status=ACTIVE)
└── dev (id=4, parent=1, status=ACTIVE)

# Additional branches for advanced scenarios
feature-a → feature-a-2 (id=5, parent=2)
```

#### 2. **Test Objects Per Branch**

**Branch 1 (main) - Base state:**
- users table (id=101)
  - Column: id INT PRIMARY KEY
  - Column: name VARCHAR(100)
  - Hash: base_hash_users_v1
- orders table (id=102)
  - Column: id INT PRIMARY KEY
  - Column: user_id INT (FK)
  - Hash: base_hash_orders_v1
- get_user_count function (id=103)
  - Body: SELECT COUNT(*) FROM users
  - Hash: base_hash_func_v1
- payment_trigger (id=104)
  - ON: INSERT ON orders
  - Hash: base_hash_trigger_v1

**Branch 2 (feature-a) - Modified users, added products:**
- users table (id=101) - MODIFIED
  - Column: id INT PRIMARY KEY
  - Column: name VARCHAR(100)
  - Column: email VARCHAR(100)  [NEW in feature-a]
  - Hash: feature_a_hash_users_modified
  - Version: 2
  - Change: SOURCE_MODIFIED in merge to main
- products table (id=201) [NEW]
  - Column: id INT PRIMARY KEY
  - Column: product_name VARCHAR(100)
  - Hash: feature_a_hash_products_new
- get_user_count function (id=103) - UNCHANGED
  - Hash: base_hash_func_v1
- payment_trigger (id=104) - UNCHANGED
  - Hash: base_hash_trigger_v1

**Branch 3 (feature-b) - Modified users differently, added audit:**
- users table (id=101) - MODIFIED (different from feature-a)
  - Column: id INT PRIMARY KEY
  - Column: name VARCHAR(100)
  - Column: status VARCHAR(50)  [NEW in feature-b]
  - Hash: feature_b_hash_users_modified (different from feature-a!)
  - Version: 2
  - Change: TARGET_MODIFIED after feature-a merge
- orders table (id=102) - UNCHANGED
  - Hash: base_hash_orders_v1
- get_user_count function (id=103) - UNCHANGED
  - Hash: base_hash_func_v1
- audit_log table (id=202) [NEW]
  - Column: id INT PRIMARY KEY
  - Column: table_name VARCHAR(100)
  - Hash: feature_b_hash_audit_new
- payment_trigger (id=104) - UNCHANGED
  - Hash: base_hash_trigger_v1

**Branch 4 (dev) - Complex scenario:**
- users table (id=101) - MODIFIED
  - Version: 3
  - Has user_id column from feature-a + status from feature-b + role column
  - Hash: dev_hash_users_combined
- Function modified (id=103) - MODIFIED
  - Different implementation than base
  - Hash: dev_hash_func_modified

### 3. **Test Fixture Class Structure**

```python
class MergeOperationsFixture:
    """
    Comprehensive fixture for Phase 4 merge operations testing.

    Creates:
    - 4 branches with parent relationships
    - 7 schema objects with specific versions/hashes
    - object_history records for each modification
    - object_dependencies linking objects
    """

    def __init__(self, db_connection):
        self.conn = db_connection
        self.branch_ids = {}  # {'main': 1, 'feature-a': 2, ...}
        self.object_ids = {}  # {'users': 101, 'orders': 102, ...}
        self.hashes = {}      # {'users_base': 'abc123...', ...}

    def setup(self):
        """Create all fixture data."""
        self._create_branches()
        self._create_objects()
        self._create_object_history()
        self._create_object_dependencies()

    def teardown(self):
        """Clean up all fixture data (reverse order of setup)."""
        self._delete_object_dependencies()
        self._delete_object_history()
        self._delete_objects()
        self._delete_branches()

    def _create_branches(self):
        """Create branch hierarchy."""
        # Create main branch
        self.branch_ids['main'] = self._insert_branch(
            name='main',
            parent_id=None,
            status='ACTIVE'
        )

        # Create feature branches
        self.branch_ids['feature-a'] = self._insert_branch(
            name='feature-a',
            parent_id=self.branch_ids['main'],
            status='ACTIVE'
        )

        # ... more branches

    def _create_objects(self):
        """Create schema objects per branch with specific hashes."""
        # For each branch, create its objects
        # Hashes must be deterministic for testing

        # Main branch objects
        self._create_object_in_branch(
            branch_id=self.branch_ids['main'],
            object_type='TABLE',
            schema_name='public',
            object_name='users',
            definition='CREATE TABLE public.users (id INT PRIMARY KEY, name VARCHAR(100))',
            content_hash='base_users_hash_v1'
        )

    def _create_object_history(self):
        """Create object_history records showing modifications."""
        # Record when each object was modified
        # Tracks versions and hashes over time

    def _create_object_dependencies(self):
        """Create dependency relationships."""
        # Orders.user_id FK → users.id
        # payment_trigger → orders table
```

### 4. **Fixture Cleanup Strategy**

```python
@pytest.fixture(scope='function')
def merge_fixture(db_connection):
    """
    Function-scoped fixture ensures clean state for each test.

    Scope: function (not class, not module)
    - Each test gets fresh data
    - Prevents test pollution
    - Slower but safer

    For 40 tests:
    - Setup time per test: ~50-100ms
    - Total setup time: ~40-60 seconds
    - Total test runtime: 2-3 minutes
    """
    fixture = MergeOperationsFixture(db_connection)
    fixture.setup()

    yield fixture  # Test runs here

    fixture.teardown()  # Always cleanup
```

### 5. **Test Helper Methods**

```python
class MergeOperationsFixture:

    def assert_conflict_count(self, source, target, expected_count):
        """Helper to verify conflict count."""
        conflicts = self.detect_conflicts(source, target)
        assert len(conflicts) == expected_count
        return conflicts

    def assert_conflict_type(self, conflicts, object_name, expected_type):
        """Helper to find and verify specific conflict."""
        for c in conflicts:
            if c['object_name'] == object_name:
                assert c['conflict_type'] == expected_type
                return c
        raise AssertionError(f"Conflict for {object_name} not found")

    def get_branch_id(self, name):
        """Get branch ID by name."""
        return self.branch_ids[name]

    def get_object_id(self, branch_id, object_name):
        """Get object ID from branch."""
        # Query schema_objects table
        pass

    def get_hash(self, hash_key):
        """Get precomputed hash."""
        return self.hashes[hash_key]

    def create_custom_object(self, branch_id, object_type, definition):
        """Create ad-hoc object for specific test."""
        pass

    def delete_object_from_branch(self, branch_id, object_id):
        """Mark object as deleted in branch."""
        pass

    def modify_object_in_branch(self, branch_id, object_id, new_definition):
        """Update object definition and hash."""
        pass
```

---

## Part 2: Implementation Patterns from Backup

### Pattern 1: LCA (Lowest Common Ancestor) Algorithm

**Location in backup**: Lines 41-157 (find_merge_base function)

**Pseudo code with annotations:**

```plpgsql
FUNCTION find_merge_base(p_branch1_id, p_branch2_id):

    INPUT VALIDATION:
        - Verify both branch IDs are not NULL
        - Verify both branches exist in pggit.branches
        - Return empty if branches are identical

    BUILD ANCESTRY PATHS:
        WITH RECURSIVE ancestry1(id, parent_id, depth):
            -- Base case: Start with branch1
            SELECT id, parent_id, 0
            FROM pggit.branches
            WHERE id = p_branch1_id

            UNION ALL

            -- Recursive case: Move up parent chain
            SELECT b.id, b.parent_id, a.depth + 1
            FROM pggit.branches b
            JOIN ancestry1 a ON b.id = a.parent_id
            WHERE a.parent_id IS NOT NULL

        -- Repeat for ancestry2 with branch2

    FIND COMMON ANCESTOR:
        -- Join both ancestry paths
        -- Find first common node (lowest in tree, highest depth)
        SELECT COALESCE(a1.id, a2.id) AS base_id,
               a1.depth AS depth_from_branch1,
               a2.depth AS depth_from_branch2
        FROM ancestry1 a1
        FULL OUTER JOIN ancestry2 a2 ON a1.id = a2.id
        WHERE a1.id IS NOT NULL AND a2.id IS NOT NULL
        ORDER BY a1.depth DESC LIMIT 1

    FALLBACK:
        IF no common ancestor found:
            -- Walk ancestry1 to root (where parent_id IS NULL)
            -- Use that as base
            -- Mark distance to branch2 as 999 (very far)

    RETURN:
        base_branch_id, base_branch_name, depth_from_branch1, depth_from_branch2

KEY INSIGHT:
    - This is recursive CTE solution to find LCA
    - O(H1 + H2) where H is height of branch tree
    - Efficient for typical small branch hierarchies
    - Handles unbalanced trees gracefully
```

**Implementation notes:**
- Use RECURSIVE CTE, not iterative loop (more efficient)
- Handle NULL parent_id as tree root
- Fallback to main (id=1) if no ancestor (safety net)
- Return depth metrics for user visibility

---

### Pattern 2: Three-Way Merge Conflict Classification

**Location in backup**: Lines 192-345 (detect_merge_conflicts function)

**Pseudo code with annotations:**

```plpgsql
FUNCTION detect_merge_conflicts(p_source_id, p_target_id, p_base_id=NULL):

    STEP 1: AUTO-DETECT BASE IF NEEDED
        IF p_base_id IS NULL:
            v_base_id := find_merge_base(p_source_id, p_target_id).base_branch_id
            IF v_base_id IS NULL:
                v_base_id := 1  -- Default to main

    STEP 2: LOAD OBJECTS FROM EACH BRANCH
        source_objs := SELECT * FROM schema_objects
                       WHERE branch_id = p_source_id AND is_active = true

        target_objs := SELECT * FROM schema_objects
                       WHERE branch_id = p_target_id AND is_active = true

        base_objs := SELECT * FROM schema_objects
                     WHERE branch_id = v_base_id AND is_active = true

    STEP 3: FULL OUTER JOIN ALL OBJECTS
        -- Match on (object_type, schema_name, object_name)
        all_objects := FULL OUTER JOIN source_objs
                       FULL OUTER JOIN target_objs
                       LEFT JOIN base_objs

        -- This creates one row per unique object across all 3 branches
        -- NULLs in columns mean object doesn't exist in that branch

    STEP 4: CLASSIFY CONFLICTS (THIS IS THE CORE LOGIC)
        FOR EACH object IN all_objects:

            -- Case 1: No changes anywhere
            IF base_hash IS NULL AND source_hash IS NULL AND target_hash IS NULL:
                type := 'NO_CONFLICT'

            -- Case 2: Identical in all three branches
            ELSE IF base_hash = source_hash AND base_hash = target_hash:
                type := 'NO_CONFLICT'

            -- Case 3: Deleted in source, exists in target and base
            ELSE IF source IS NULL AND target IS NOT NULL AND base IS NOT NULL:
                type := 'DELETED_SOURCE'
                auto_resolvable := true  -- Safe to delete

            -- Case 4: Deleted in target, exists in source and base
            ELSE IF target IS NULL AND source IS NOT NULL AND base IS NOT NULL:
                type := 'DELETED_TARGET'
                auto_resolvable := true  -- Already gone

            -- Case 5: Source modified, target unchanged
            ELSE IF base_hash = target_hash AND source_hash != base_hash:
                type := 'SOURCE_MODIFIED'
                auto_resolvable := true  -- Safe to apply source's change

            -- Case 6: Target modified, source unchanged
            ELSE IF base_hash = source_hash AND target_hash != base_hash:
                type := 'TARGET_MODIFIED'
                auto_resolvable := true  -- Safe to keep target's change

            -- Case 7: Both modified differently
            ELSE IF source_hash != base_hash AND target_hash != base_hash:
                type := 'BOTH_MODIFIED'
                auto_resolvable := false  -- Requires manual review

            -- Case 8: Both added new (same definition)
            ELSE IF base IS NULL AND source_hash = target_hash:
                type := 'NO_CONFLICT'  -- Both added same thing
                auto_resolvable := true

            -- Case 9: Both added new (different definitions)
            ELSE IF base IS NULL AND source_hash != target_hash:
                type := 'BOTH_MODIFIED'
                auto_resolvable := false  -- Different additions

            -- Default: Conflict
            ELSE:
                type := 'BOTH_MODIFIED'
                auto_resolvable := false

    STEP 5: CALCULATE SEVERITY
        severity := CASE
            WHEN object_type IN ('TABLE', 'FUNCTION', 'VIEW') AND deleted: 'MAJOR'
            WHEN object is NULL in base: 'MAJOR'  -- New object with conflicts
            ELSE: 'MINOR'

    STEP 6: CHECK DEPENDENCIES
        -- Query object_dependencies table
        -- If object being dropped has dependents: severity = 'MAJOR'

    RETURN:
        All conflicts with classification, hashes, versions, auto_resolvable flag

KEY INSIGHTS:
    - This is TRUE three-way merge logic (not two-way diff)
    - Core classification uses hash comparisons
    - Prevents "lost deletion" problem
    - Auto-resolvable ≠ auto-resolved (user still sees them, but they're safe)
```

**Hash Comparison Logic Matrix:**

```
base   source target  classification
---    ---    ---
NULL   NULL   NULL    NO_CONFLICT (nothing changed)
H1     H1     H1      NO_CONFLICT (identical)
H1     H1     H2      TARGET_MODIFIED (source unchanged, target changed)
H1     H2     H1      SOURCE_MODIFIED (source changed, target unchanged)
H1     H2     H2      TARGET_MODIFIED (both adopted same version, but not base)
H1     H2     H3      BOTH_MODIFIED (all three different - true conflict)
NULL   H1     H1      NO_CONFLICT (both added same)
NULL   H1     H2      BOTH_MODIFIED (both added different)
NULL   NULL   H1      NO_CONFLICT (only target added - but source is null, so ADDED)
H1     NULL   H1      DELETED_SOURCE (source deleted, target unchanged)
H1     NULL   NULL    DELETED_SOURCE (both deleted - but target null, so DELETED_TARGET)
H1     H1     NULL    DELETED_TARGET (target deleted, source unchanged)

KEY: Hashes with _ prefix (like H1) are actual SHA256 hashes, NULL means object doesn't exist
```

---

### Pattern 3: Merge Strategy Application

**Location in backup**: Lines 640-802 (merge_branches function)

**Pseudo code:**

```plpgsql
FUNCTION merge_branches(p_source, p_target, p_message, p_strategy):

    STEP 1: VALIDATION
        Verify source != target (no self-merge)
        Verify both branches exist and are ACTIVE
        Validate strategy in (TARGET_WINS, SOURCE_WINS, UNION, MANUAL_REVIEW, ABORT_ON_CONFLICT)

    STEP 2: FIND MERGE BASE
        base_id := find_merge_base(source_id, target_id).base_branch_id
        IF NULL: base_id := 1 (default to main)

    STEP 3: DETECT CONFLICTS
        conflicts := detect_merge_conflicts(source_id, target_id, base_id)
        total_count := COUNT(conflicts)
        auto_resolvable_count := COUNT(conflicts WHERE auto_resolvable = true)
        manual_count := COUNT(conflicts WHERE auto_resolvable = false)

    STEP 4: APPLY STRATEGY
        CASE p_strategy:

            WHEN 'ABORT_ON_CONFLICT':
                IF total_count > 0:
                    RAISE EXCEPTION 'Merge aborted due to conflicts'
                    RETURN ABORTED status

            WHEN 'TARGET_WINS':
                -- Apply target branch definitions for all conflicts
                FOR EACH conflict WHERE conflict_type IN (SOURCE_MODIFIED, BOTH_MODIFIED):
                    object_definition := get_object_from_branch(target_id, object_id)
                    apply_definition_to_target(object_id, object_definition)

            WHEN 'SOURCE_WINS':
                -- Apply source branch definitions for all conflicts
                FOR EACH conflict WHERE conflict_type IN (TARGET_MODIFIED, BOTH_MODIFIED):
                    object_definition := get_object_from_branch(source_id, object_id)
                    apply_definition_to_target(object_id, object_definition)

            WHEN 'UNION':
                -- Smart merge for compatible objects
                FOR EACH conflict:
                    IF object_type = 'TABLE':
                        -- Try to merge ADD COLUMN statements
                        result := try_merge_table_columns(source_obj, target_obj)
                        IF result IS NOT NULL:
                            apply_definition_to_target(object_id, result)
                        ELSE:
                            -- Fallback to MANUAL_REVIEW
                            mark_for_manual_review(conflict_id)

                    ELSE IF object_type = 'TRIGGER':
                        -- Try to merge non-overlapping triggers
                        result := try_merge_triggers(source_obj, target_obj)
                        IF result IS NOT NULL:
                            apply_definition_to_target(object_id, result)
                        ELSE:
                            mark_for_manual_review(conflict_id)

                    ELSE:
                        -- FUNCTION, VIEW, etc. don't support UNION
                        mark_for_manual_review(conflict_id)

            WHEN 'MANUAL_REVIEW':
                -- Mark all conflicts for manual resolution
                FOR EACH conflict:
                    mark_for_manual_review(conflict_id)
                RETURN CONFLICT status (merge not complete)

    STEP 5: CREATE RESULT COMMIT
        result_commit_hash := compute_hash(merged_objects)
        INSERT INTO pggit.commits:
            branch_id: target_id
            parent_commit_hash: target_branch.latest_commit
            objects_hash: result_commit_hash
            commit_message: p_message OR 'Merge ' + source + ' -> ' + target
            created_by: CURRENT_USER

    STEP 6: UPDATE MERGE OPERATIONS RECORD
        INSERT INTO pggit.merge_operations:
            merge_id: generated_uuid
            source_branch_id: source_id
            target_branch_id: target_id
            merge_strategy: p_strategy
            status: 'SUCCESS' or 'CONFLICT'
            conflicts_detected: total_count
            conflicts_resolved: (if UNION succeeded count)
            result_commit_hash: result_commit_hash
            merged_by: CURRENT_USER
            merged_at: NOW()

    STEP 7: UPDATE SOURCE BRANCH STATUS
        IF merge complete (no pending conflicts):
            UPDATE pggit.branches
            SET status = 'MERGED',
                merged_at = NOW(),
                merged_by = CURRENT_USER
            WHERE id = source_id

    RETURN:
        merge_id, status, conflicts_detected, auto_resolvable_count,
        manual_count, merge_complete, result_commit_hash

KEY INSIGHTS:
    - Strategy determines which branch "wins"
    - AUTO_MERGE (no conflicts) always succeeds
    - ABORT_ON_CONFLICT is safest default
    - UNION is opt-in smart merge (must explicitly request)
    - MANUAL_REVIEW pauses merge for user decision
```

---

## Part 3: Edge Cases & Solutions

### Edge Case 1: Circular Branch Dependencies

**Problem**: Branch A ← B ← C ← A (circular parent chain)

**Solution**:
```plpgsql
-- Detect cycles in LCA algorithm
WITH RECURSIVE path_check AS (
    -- Build path, track visited nodes
    SELECT id, parent_id, ARRAY[id] AS visited_path
    FROM pggit.branches WHERE id = p_branch1_id

    UNION ALL

    SELECT b.id, b.parent_id,
           path_check.visited_path || b.id
    FROM pggit.branches b
    JOIN path_check ON b.id = path_check.parent_id
    WHERE NOT b.id = ANY(visited_path)  -- Cycle detection
      AND array_length(visited_path, 1) < 100  -- Max depth
)
-- If we hit max depth before reaching root: circular
```

### Edge Case 2: Object Deleted in Base, Re-added in Branch

**Problem**:
```
Base: users table exists (hash_v1)
Branch A: deletes users
Branch B: re-creates users with same definition (hash_v1)
Merge A→B: Is this a conflict or no-conflict?
```

**Classification**:
```
base_hash: hash_v1
source_hash: NULL (deleted)
target_hash: hash_v1 (recreated, same as base)

Classification: DELETED_SOURCE + same as target = AUTO-RESOLVABLE
Action: Delete from target (one branch wanted it gone)
```

### Edge Case 3: Deleted Object with Dependents

**Problem**:
```
users table has foreign key from orders
Branch A wants to drop users table
Merge would break orders table
```

**Solution**:
```plpgsql
-- Check dependencies before applying deletion
IF conflict_type = 'DELETED_SOURCE':
    dependent_count := SELECT COUNT(*) FROM object_dependencies
                       WHERE depends_on_object_id = object_id
    IF dependent_count > 0:
        severity := 'MAJOR'
        auto_resolvable := false  -- Override! Require manual review
```

### Edge Case 4: Version Number Mismatch

**Problem**: Object version doesn't match hash (data corruption)

**Solution**:
```plpgsql
-- Recompute hash from definition
new_hash := compute_hash(object_definition)
IF new_hash != stored_hash:
    -- Version numbers can drift, use hashes for truth
    -- Only warn if definition is empty (corrupted)
    IF object_definition IS NULL OR object_definition = '':
        RAISE WARNING 'Object % has no definition', object_id
```

### Edge Case 5: Multi-Level Merge (A→B→C)

**Problem**: User merges feature-a into feature-b, then later merges feature-b into main

**Solution**:
```
Merge 1: feature-a → feature-b
  - Creates merge record
  - Updates feature-b with feature-a changes
  - Result commit stored

Merge 2: feature-b → main
  - feature-b now has combined definitions
  - Merge against main, not original feature-a
  - Uses feature-b's merged result as source
  - Result: clean multi-level merge
```

---

## Part 4: Test Fixture Implementation Guide

### Fixture Initialization Sequence

```python
@pytest.fixture(scope='function', autouse=False)
def merge_fixture(db_connection):
    """
    Provides complete test fixture for merge operations.

    Sequence:
    1. Create 4 branches with parent hierarchy
    2. Create 7 schema objects with specific definitions
    3. Compute and store deterministic hashes
    4. Create object_history records
    5. Create object_dependencies
    6. Validate fixture is complete

    On cleanup:
    1. Delete object_dependencies (foreign keys)
    2. Delete object_history
    3. Delete schema_objects
    4. Delete branches
    5. Verify all cleaned up
    """

    fixture = MergeOperationsFixture(db_connection)
    fixture.setup()

    # Validate fixture
    assert len(fixture.branch_ids) == 4
    assert len(fixture.object_ids) >= 7

    yield fixture

    # Cleanup
    fixture.teardown()
```

### Computing Deterministic Hashes

```python
def compute_fixture_hash(definition: str, version: int = 1) -> str:
    """
    Compute deterministic hash for test fixture objects.

    Important: Must match pggit.compute_hash() behavior
    """
    import hashlib

    # Normalize definition (remove extra whitespace)
    normalized = ' '.join(definition.split()).lower()

    # Include version in hash
    hash_input = f"{version}:{normalized}"

    # SHA256 hash
    return hashlib.sha256(hash_input.encode()).hexdigest()

# Example fixtures
FIXTURE_HASHES = {
    'users_base': compute_fixture_hash(
        'CREATE TABLE public.users (id INT PRIMARY KEY, name VARCHAR(100))',
        version=1
    ),
    'users_feature_a': compute_fixture_hash(
        'CREATE TABLE public.users (id INT PRIMARY KEY, name VARCHAR(100), email VARCHAR(100))',
        version=2
    ),
    # ... more hashes
}
```

---

## Part 5: Test Structure Template

```python
class TestMergeBranches:
    """Tests for pggit.merge_branches() function."""

    def test_merge_no_conflicts(self, merge_fixture):
        """Happy path: merge with zero conflicts."""
        # Setup
        fixture = merge_fixture

        # Detect conflicts first
        conflicts = fixture.detect_conflicts(
            fixture.get_branch_id('feature-a'),
            fixture.get_branch_id('main')
        )
        assert len(conflicts) == 0  # No conflicts

        # Execute merge
        result = fixture.merge_branches(
            'feature-a',
            'main',
            strategy='ABORT_ON_CONFLICT'
        )

        # Verify
        assert result['status'] == 'SUCCESS'
        assert result['conflicts_detected'] == 0
        assert result['merge_complete'] == True

    def test_merge_three_way_with_auto_discovered_base(self, merge_fixture):
        """Three-way merge using auto-discovered LCA."""
        # This tests the merge_base parameter working correctly
        fixture = merge_fixture

        # Merge feature-a into feature-b
        # Should auto-discover merge_base = main
        result = fixture.merge_branches(
            'feature-a',
            'feature-b',
            strategy='UNION'  # Try to merge compatible changes
        )

        # Verify merge_base was auto-discovered
        assert result['merge_base_branch_id'] == fixture.get_branch_id('main')

        # Verify merge used three-way logic
        # (If feature-a and feature-b made independent changes, should auto-merge)
        assert result['status'] == 'SUCCESS'

    def test_merge_abort_on_conflict(self, merge_fixture):
        """ABORT_ON_CONFLICT strategy prevents merge with conflicts."""
        fixture = merge_fixture

        # Create conflict: both branches modify same object
        fixture.modify_object_in_branch(
            fixture.get_branch_id('feature-a'),
            fixture.get_object_id(fixture.get_branch_id('feature-a'), 'users'),
            'CREATE TABLE public.users (id INT, email VARCHAR(100), age INT)'
        )

        # Try merge with ABORT_ON_CONFLICT
        try:
            fixture.merge_branches(
                'feature-a',
                'main',
                strategy='ABORT_ON_CONFLICT'
            )
            assert False, "Should have raised exception"
        except Exception as e:
            assert 'conflict' in str(e).lower()
```

---

## Summary

This Step 0 fixture improvement provides:

1. ✅ **Complete test fixture architecture** - 4 branches, 7+ objects, proper hierarchy
2. ✅ **LCA algorithm pseudo code** - Extracted from backup, ready to implement
3. ✅ **Three-way merge classification** - Full conflict detection logic with all 6 types
4. ✅ **Merge strategy patterns** - How each strategy (ABORT, WINS, UNION, MANUAL) works
5. ✅ **Edge case solutions** - Handles circles, deletions, dependents, versions
6. ✅ **Fixture helper methods** - Reusable patterns for 40 tests
7. ✅ **Hash computation** - Deterministic and matches pggit.compute_hash()

**Ready for Phase 4 implementation with concrete patterns and proven algorithms.**

---

**Created**: 2025-12-26
**Status**: Ready for implementation review
