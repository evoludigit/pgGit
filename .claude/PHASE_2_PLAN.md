# Phase 2: Branch Management Implementation Plan

**Status**: Ready for Approval
**Phase**: 2 of 7
**Target Completion**: After Phase 1 (60/60 tests passing ✅)
**Effort Estimate**: 3-4 days with proper implementation
**Goal**: Enable full Git-style branch operations with comprehensive testing

---

## Executive Summary

Phase 2 implements the **Core API for branch management** - four essential functions that enable users to create, delete, list, and switch database branches. This phase is critical because all subsequent phases (3-7) depend on a solid branch foundation.

### Success Criteria
- [ ] All 4 functions implemented with exact API spec signatures
- [ ] 35-40 comprehensive unit tests (8-10 per function)
- [ ] 100% test pass rate
- [ ] All edge cases and error conditions covered
- [ ] Clear, descriptive git commits

---

## Architecture Overview

### Design Principles

1. **Immutability**: Branch operations preserve history - deletions mark as DELETED, not removed
2. **Atomicity**: Each function completes fully or rolls back completely
3. **Auditability**: All operations tracked in history and commits tables
4. **Validation**: Input validation at function boundary, not in database
5. **Return Clarity**: Functions return rich TABLES with metadata, not just IDs

### Dependencies on Phase 1

Phase 2 functions rely on these Phase 1 components:
- **pggit.branches table** - stores branch metadata
- **pggit.objects table** - stores versioned schema objects per branch
- **pggit.commits table** - tracks commits linked to branches
- **pggit.history table** - audit trail of all changes
- **pggit.branch_status enum** - ACTIVE/MERGED/DELETED/CONFLICTED
- **Utility functions**:
  - `pggit.version()` - verify installation
  - `pggit.ensure_object()` - helper for object operations
  - `pggit.increment_version()` - semantic versioning

### Database Schema (Already in Phase 1)

```sql
-- Core table for Phase 2
pggit.branches (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    parent_branch_id INTEGER REFERENCES pggit.branches(id),
    head_commit_hash TEXT,
    status pggit.branch_status DEFAULT 'ACTIVE',  -- ACTIVE|MERGED|DELETED|CONFLICTED
    created_at TIMESTAMP,
    created_by TEXT,
    merged_at TIMESTAMP,
    merged_by TEXT,
    branch_type TEXT DEFAULT 'standard',
    total_objects INTEGER DEFAULT 0,
    modified_objects INTEGER DEFAULT 0,
    storage_efficiency DECIMAL(5,2) DEFAULT 100.00,
    description TEXT
);

-- Main branch auto-created
INSERT INTO pggit.branches (id, name) VALUES (1, 'main');
```

---

## Phase 2.1: pggit.create_branch()

### Specification

```sql
CREATE OR REPLACE FUNCTION pggit.create_branch(
    p_branch_name TEXT,
    p_parent_branch_name TEXT DEFAULT 'main',
    p_branch_type TEXT DEFAULT 'standard',
    p_metadata JSONB DEFAULT NULL
) RETURNS TABLE (
    branch_id INTEGER,
    branch_name TEXT,
    parent_branch_id INTEGER,
    parent_branch_name TEXT,
    status TEXT,
    branch_type TEXT,
    head_commit_hash CHAR(64),
    created_at TIMESTAMP,
    created_by TEXT
)
```

### Detailed Implementation Steps

**Step 1: Validate Inputs**
- Check `p_branch_name` is not empty and not NULL
- Check `p_branch_name` matches regex: `^[a-zA-Z0-9._/#-]+$`
- Check `p_branch_type` is one of: 'standard', 'tiered', 'temporal', 'compressed'
- Verify `p_branch_name` doesn't already exist (should be unique)
- Raise EXCEPTION for any validation failure with descriptive message

**Step 2: Find Parent Branch**
- Query `pggit.branches` for `p_parent_branch_name`
- Filter only ACTIVE branches (status = 'ACTIVE')
- If not found, raise: `'Parent branch % not found or is not active', p_parent_branch_name`
- Store parent_id in variable

**Step 3: Get Parent's Head Commit**
- Query parent branch's `head_commit_hash`
- If NULL (shouldn't happen for main), use parent's created_at timestamp
- This becomes the "branch point" in history

**Step 4: Create New Branch Entry**
- Generate new commit hash: `sha256(CURRENT_TIMESTAMP || p_branch_name || p_parent_branch_name)`
- INSERT into pggit.branches:
  ```
  name = p_branch_name
  parent_branch_id = parent_id
  head_commit_hash = generated_hash
  status = 'ACTIVE'
  branch_type = p_branch_type
  created_by = CURRENT_USER
  ```
- Get returned branch_id from INSERT RETURNING
- Raise EXCEPTION if UNIQUE constraint fails (duplicate name)

**Step 5: Copy Parent's Objects to New Branch**
- INSERT INTO pggit.objects (for new branch):
  ```
  SELECT
      object_type, schema_name, object_name, parent_id,
      content_hash, ddl_normalized, NEW_branch_id, p_branch_name,
      version, version_major, version_minor, version_patch, metadata, is_active
  FROM pggit.objects
  WHERE branch_name = p_parent_branch_name AND is_active = true
  ```
- This gives the new branch an initial snapshot of the parent's schema

**Step 6: Return Complete Information**
- RETURN QUERY with all requested fields
- Include parent_branch_name by joining back to parent branch

### Test Cases (10 tests)

1. **Happy path**: Create branch from main
   - Input: `create_branch('feature/test1')`
   - Expected: Returns all fields, status='ACTIVE', parent_branch_id=1

2. **Custom parent**: Create branch from non-main
   - Input: Create 'feature/sub1', then create 'feature/subsub' from 'feature/sub1'
   - Expected: Hierarchical branching works, parent_id points to feature/sub1

3. **Custom branch type**: All branch types work
   - Input: Create with each type ('standard', 'tiered', 'temporal', 'compressed')
   - Expected: All succeed, branch_type matches input

4. **Duplicate name fails**
   - Input: Create 'feature/dup', then create 'feature/dup' again
   - Expected: EXCEPTION with "already exists" message

5. **Invalid parent fails**
   - Input: `create_branch('test', 'nonexistent')`
   - Expected: EXCEPTION with "Parent branch...not found" message

6. **Invalid branch name - empty string**
   - Input: `create_branch('')`
   - Expected: EXCEPTION with validation error

7. **Invalid branch name - invalid chars**
   - Input: `create_branch('feature/test@invalid')`
   - Expected: EXCEPTION with "invalid characters" message

8. **Invalid branch type**
   - Input: `create_branch('test', 'main', 'invalid_type')`
   - Expected: EXCEPTION with validation error

9. **Deleted parent cannot be used**
   - Setup: Create branch A, mark as DELETED
   - Input: `create_branch('test', 'A')`
   - Expected: EXCEPTION with "not active" message

10. **With metadata**: Metadata stored correctly
    - Input: `create_branch('test', metadata='{"team": "backend"}'::jsonb)`
    - Expected: metadata returned in result set

### Key Considerations

- **Check Constraints**: Database enforces name format, not function
- **Cascading**: Objects copied, not linked - each branch is independent
- **Immutability**: Creating a branch doesn't modify the parent
- **Auditing**: CURRENT_USER automatically captured for created_by

---

## Phase 2.2: pggit.delete_branch()

### Specification

```sql
CREATE OR REPLACE FUNCTION pggit.delete_branch(
    p_branch_name TEXT,
    p_force BOOLEAN DEFAULT false
) RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    branch_id INTEGER,
    deleted_at TIMESTAMP
)
```

### Detailed Implementation Steps

**Step 1: Validate Input**
- Check `p_branch_name` is not NULL or empty
- Verify branch exists in pggit.branches

**Step 2: Prevent Deletion of main**
- If `p_branch_name = 'main'`, EXCEPTION: "Cannot delete main branch"
- This is non-negotiable - main is always there

**Step 3: Check Merge Status (unless force=true)**
- If `p_force = false`:
  - Check if branch status = 'MERGED'
  - If not MERGED, EXCEPTION: "Branch must be merged before deletion. Use force=true to override."
- If `p_force = true`:
  - Skip check, proceed to deletion

**Step 4: Cascade Cleanup**
- Delete from pggit.data_branches WHERE branch_id = target_id
- Delete from pggit.commits WHERE branch_id = target_id (via CASCADE FK)
- Delete from pggit.history WHERE branch_id = target_id (via CASCADE FK)
- Delete objects associated with this branch
  - Note: Objects have branch_id field - delete those specific to this branch

**Step 5: Mark Branch as DELETED**
- UPDATE pggit.branches SET:
  ```
  status = 'DELETED'
  merged_at = CURRENT_TIMESTAMP (if not already set)
  merged_by = CURRENT_USER
  ```
- Use conditional UPDATE: only update if currently ACTIVE or MERGED
- Don't actually DELETE row - preserves history (immutability)

**Step 6: Return Status**
- RETURN success=true
- Include message describing what happened
- Include branch_id and deleted_at timestamp

### Test Cases (9 tests)

1. **Happy path**: Delete merged branch
   - Setup: Create branch, mark status=MERGED
   - Input: `delete_branch('feature/old')`
   - Expected: success=true, status changes to DELETED

2. **Cannot delete main**
   - Input: `delete_branch('main')`
   - Expected: EXCEPTION "Cannot delete main"

3. **Cannot delete unmerged without force**
   - Setup: Create branch, leave status=ACTIVE
   - Input: `delete_branch('feature/unmerged')`
   - Expected: EXCEPTION with "must be merged" message

4. **Can force delete unmerged**
   - Setup: Create branch with status=ACTIVE
   - Input: `delete_branch('feature/unmerged', force=true)`
   - Expected: success=true, deleted_at set

5. **Branch doesn't exist**
   - Input: `delete_branch('nonexistent')`
   - Expected: EXCEPTION or success=false with message

6. **Already deleted branch**
   - Setup: Delete a branch once
   - Input: Delete same branch again
   - Expected: Either EXCEPTION or idempotent (safe to call twice)

7. **Cascade deletes related data**
   - Setup: Create branch, add objects, commits, history
   - Input: `delete_branch(branch, force=true)`
   - Expected: Verify via SELECT that objects/commits/history gone

8. **Audit trail preserved**
   - Setup: Create and delete branch
   - Input: Query pggit.branches
   - Expected: Row still exists with status=DELETED, not actually removed

9. **Respects created_by**
   - Setup: Create branch as user A, delete as user B
   - Expected: merged_by shows user B, original created_by shows user A

### Key Considerations

- **Soft Delete**: Don't actually DELETE rows - mark as DELETED (immutability)
- **Cascade Safety**: ForeignKey ON DELETE CASCADE handles related cleanup
- **Force Flag**: Override business logic when needed for admin
- **Idempotency**: Calling delete twice on same branch should be safe
- **Audit**: Keep full audit trail even after deletion

---

## Phase 2.3: pggit.list_branches()

### Specification

```sql
CREATE OR REPLACE FUNCTION pggit.list_branches(
    p_filter_status pggit.branch_status DEFAULT NULL,
    p_include_deleted BOOLEAN DEFAULT false,
    p_order_by TEXT DEFAULT 'created_at DESC'
) RETURNS TABLE (
    branch_id INTEGER,
    branch_name TEXT,
    parent_branch_id INTEGER,
    parent_branch_name TEXT,
    status TEXT,
    branch_type TEXT,
    head_commit_hash CHAR(64),
    object_count INTEGER,
    storage_bytes BIGINT,
    created_by TEXT,
    created_at TIMESTAMP,
    merged_at TIMESTAMP,
    merged_by TEXT,
    last_modified_at TIMESTAMP
)
```

### Detailed Implementation Steps

**Step 1: Build Base Query**
- START with:
  ```sql
  SELECT
      b.id, b.name, b.parent_branch_id, pb.name as parent_name,
      b.status, b.branch_type, b.head_commit_hash,
      b.total_objects, ...storage..., b.created_by, b.created_at,
      b.merged_at, b.merged_by, ...last_modified...
  FROM pggit.branches b
  LEFT JOIN pggit.branches pb ON b.parent_branch_id = pb.id
  ```

**Step 2: Apply Status Filter**
- If `p_filter_status IS NOT NULL`:
  - WHERE b.status = p_filter_status
- Otherwise: list all statuses

**Step 3: Apply Deleted Filter**
- If `p_include_deleted = false`:
  - WHERE b.status != 'DELETED'
- If `p_include_deleted = true`:
  - Include all statuses

**Step 4: Calculate Metrics**
- `object_count`: COUNT from pggit.objects where branch_id=b.id
- `storage_bytes`: SUM of object definition sizes
- `last_modified_at`: MAX(updated_at) from pggit.objects for this branch

**Step 5: Apply Ordering**
- Support ordering by: 'created_at ASC|DESC', 'name ASC|DESC', 'status ASC|DESC'
- Default: 'created_at DESC' (newest first)
- Validate p_order_by to prevent SQL injection

**Step 6: Return Results**
- RETURN QUERY with all calculated columns

### Test Cases (8 tests)

1. **List all branches**
   - Setup: Create branches A, B, C in various states
   - Input: `list_branches()` with no filters
   - Expected: All non-deleted branches returned

2. **Filter by ACTIVE status**
   - Setup: Create 2 ACTIVE, 1 MERGED, 1 DELETED
   - Input: `list_branches(p_filter_status='ACTIVE')`
   - Expected: Only ACTIVE branches returned

3. **Filter by MERGED status**
   - Input: `list_branches(p_filter_status='MERGED')`
   - Expected: Only MERGED branches returned

4. **Include deleted branches**
   - Setup: Create 2 active, 1 deleted
   - Input: `list_branches(p_include_deleted=true)`
   - Expected: All 3 branches returned

5. **Exclude deleted branches (default)**
   - Setup: Create 2 active, 1 deleted
   - Input: `list_branches()` (default)
   - Expected: Only 2 active branches returned

6. **Order by created_at DESC (default)**
   - Setup: Create branches in order A, B, C with small delays
   - Input: `list_branches()`
   - Expected: Results in order C, B, A (newest first)

7. **Order by name ASC**
   - Setup: Create branches 'zebra', 'apple', 'banana'
   - Input: `list_branches(p_order_by='name ASC')`
   - Expected: apple, banana, zebra

8. **Show parent branch names**
   - Setup: Create main → feature/a → feature/a/sub
   - Input: `list_branches()`
   - Expected: Each branch shows parent_branch_name correctly

### Key Considerations

- **Performance**: Could be slow with many objects - consider indexing
- **Metrics**: object_count and storage_bytes calculated, not stored
- **Parent Joins**: LEFT JOIN handles branches with NULL parent_id
- **Filtering**: Multiple filters work together (status AND deleted check)
- **Ordering**: Must be safe from SQL injection

---

## Phase 2.4: pggit.checkout_branch()

### Specification

```sql
CREATE OR REPLACE FUNCTION pggit.checkout_branch(
    p_branch_name TEXT
) RETURNS TABLE (
    success BOOLEAN,
    previous_branch TEXT,
    current_branch TEXT,
    message TEXT,
    switched_at TIMESTAMP
)
```

### Detailed Implementation Steps

**Step 1: Validate Input**
- Check `p_branch_name` is not NULL or empty

**Step 2: Get Previous Branch (Session State)**
- Query session variable: `current_setting('pggit.current_branch', true)`
- Store as v_previous_branch
- If not set, default to 'main'

**Step 3: Verify Target Branch Exists**
- Query pggit.branches for p_branch_name where status='ACTIVE'
- If not found or not ACTIVE, EXCEPTION: "Branch '%s' not found or not active"

**Step 4: Update Session Variable**
- Execute: `SET pggit.current_branch = p_branch_name`
- This persists for the current session

**Step 5: Record Checkout in Audit Trail**
- Optional but recommended: INSERT audit record
  ```sql
  INSERT INTO pggit.history (object_type, change_type, ...)
  VALUES ('BRANCH', 'BRANCH_CHECKOUT', ...)
  ```

**Step 6: Return Status**
- success = true
- previous_branch = v_previous_branch
- current_branch = p_branch_name
- message = formatted string describing the checkout
- switched_at = CURRENT_TIMESTAMP

### Test Cases (7 tests)

1. **Happy path**: Checkout from main to feature
   - Setup: Create feature branch
   - Input: `checkout_branch('feature/test')`
   - Expected: success=true, previous='main', current='feature/test'

2. **Checkout to same branch**
   - Input: Checkout to current branch
   - Expected: success=true, previous=current (no change)

3. **Cannot checkout to deleted branch**
   - Setup: Create and delete branch
   - Input: `checkout_branch('deleted_branch')`
   - Expected: EXCEPTION "not found or not active"

4. **Cannot checkout to non-existent branch**
   - Input: `checkout_branch('nonexistent')`
   - Expected: EXCEPTION "not found"

5. **Session state persists**
   - Input: Checkout A, then in same session checkout B, then query current_setting
   - Expected: current_setting returns 'B'

6. **Previous branch tracked correctly**
   - Input: Start at main, checkout A, checkout B
   - Expected: Second checkout shows previous='A'

7. **First checkout (no previous)**
   - Setup: Fresh session (no current_branch set)
   - Input: `checkout_branch('feature/test')`
   - Expected: previous_branch=NULL or 'main' (gracefully handled)

### Key Considerations

- **Session Variables**: Not persisted to disk - only for current connection
- **No Data Switching**: This function doesn't switch tables - just tracking state
- **Future Capability**: Phase 3+ will use this to determine which branch's objects to return
- **Audit**: Could optionally log all checkouts for audit trail

---

## File Structure

### SQL Implementation File

**Location**: `sql/030_pggit_branch_management.sql`

**Contents**:
1. Comment header with patent/license info
2. Phase 2.1: create_branch() - ~80 lines
3. Phase 2.2: delete_branch() - ~70 lines
4. Phase 2.3: list_branches() - ~100 lines
5. Phase 2.4: checkout_branch() - ~50 lines
6. **Total**: ~300 lines SQL

**Order**: Functions defined in dependency order (no forward references)

### Test Implementation File

**Location**: `tests/unit/test_phase2_branch_management.py`

**Contents**:
- Import statements (psycopg, pytest, fixtures)
- Fixtures for test database setup/teardown
- Test class: TestCreateBranch (10 tests)
- Test class: TestDeleteBranch (9 tests)
- Test class: TestListBranches (8 tests)
- Test class: TestCheckoutBranch (7 tests)
- **Total**: ~450 lines Python

**Test Pattern**:
```python
@pytest.mark.integration
def test_create_branch_happy_path(db_fixture):
    """Test creating branch from main with defaults."""
    # Arrange
    db_fixture.setup_pggit()

    # Act
    result = db_fixture.execute(
        "SELECT * FROM pggit.create_branch(%s)",
        'feature/test'
    )

    # Assert
    assert result[0]['branch_name'] == 'feature/test'
    assert result[0]['status'] == 'ACTIVE'
    assert result[0]['parent_branch_id'] == 1
```

---

## Implementation Strategy

### Step-by-Step Approach

**Day 1: Design & Setup**
- [ ] Review this plan with user
- [ ] Get approval on approach
- [ ] Set up test database fixtures
- [ ] Create sql/030_pggit_branch_management.sql skeleton

**Day 2: Phase 2.1 & 2.2 Implementation**
- [ ] Implement create_branch() (80 lines)
- [ ] Implement delete_branch() (70 lines)
- [ ] Test both functions end-to-end
- [ ] Fix any issues

**Day 3: Phase 2.3 & 2.4 Implementation**
- [ ] Implement list_branches() (100 lines)
- [ ] Implement checkout_branch() (50 lines)
- [ ] Test both functions end-to-end

**Day 4: Comprehensive Testing**
- [ ] Write all 34 unit tests
- [ ] Run full test suite
- [ ] Fix any failing tests
- [ ] Achieve 100% pass rate
- [ ] Verify test coverage (>95%)

**Day 5: Documentation & Commit**
- [ ] Write docstrings for all functions
- [ ] Create Phase 2 implementation summary
- [ ] Commit with [GREEN] tag
- [ ] Verify commit message clarity

### Testing Approach

**Unit Tests**: Direct database tests using psycopg
- Each test function is isolated
- Setup/teardown cleans state
- Uses real PostgreSQL, not mocks

**Test Categories**:
- Happy path (normal operation)
- Input validation (edge cases)
- Error conditions (exceptions)
- Integration with Phase 1 (object copying, etc.)
- Audit trail (history recorded)

**Test Execution**:
```bash
pytest tests/unit/test_phase2_branch_management.py -v
# Expected: 34/34 passed in ~5-10 seconds
```

---

## Risk Mitigation

### Known Risks

1. **SQL Injection via ORDER BY**
   - Mitigation: Whitelist valid order_by values
   - Test: Invalid order_by raises EXCEPTION

2. **Cascade Delete Cascades Too Much**
   - Mitigation: Test carefully with objects/commits/history
   - Test: Deletion cleanup test verifies only target branch affected

3. **Session Variables Tricky**
   - Mitigation: Test in same connection context
   - Test: Session state persistence test

4. **Soft Deletes Break Queries**
   - Mitigation: Always check status != 'DELETED' in WHERE
   - Test: Verify deleted branches excluded by default

### Rollback Plan

If implementation fails:
1. Keep Phase 1 intact (no changes)
2. Delete sql/030_pggit_branch_management.sql
3. Start over with revised approach
4. No production data affected (all local testing)

---

## Success Criteria Checklist

### Code Quality
- [ ] All 4 functions implemented exactly to spec
- [ ] No hardcoded values except defaults
- [ ] Clear variable naming (p_ for params, v_ for variables)
- [ ] Comments explaining non-obvious logic
- [ ] Consistent with Phase 1 patterns

### Testing
- [ ] 34 unit tests written
- [ ] All tests passing (100% success)
- [ ] Edge cases covered (invalid inputs, etc.)
- [ ] Happy paths tested
- [ ] Error conditions tested

### Git Workflow
- [ ] Feature branch created: `feature/phase-2-branch-management`
- [ ] Commits are small and logical
- [ ] Commit messages follow pattern: `feat(phase2): Description [GREEN]`
- [ ] Ready for code review

### Documentation
- [ ] Docstrings in all SQL functions
- [ ] Test names describe what they test
- [ ] README updated (optional)

---

## Implementation Notes

### PostgreSQL Patterns Used

1. **RETURNING clause**: Get generated IDs from INSERT
2. **TABLE return type**: Return multiple columns
3. **CTEs (WITH)**: Not needed for Phase 2
4. **Window functions**: Not needed for Phase 2
5. **EXCEPTION handling**: For input validation
6. **Session variables**: For checkout_branch

### No External Dependencies

- No Python packages beyond psycopg (already Phase 1)
- No stored procedures (just functions)
- No views (not needed yet)
- No indexes (Phase 1 created main ones)

### Performance Notes

- list_branches() could be slow with 10K+ branches
- Consider index on branches(status, created_at)
- Object counting might JOIN large tables - monitor

---

## Questions for User (Before Implementation)

1. **Delete Strategy**: Soft delete (mark DELETED) or hard delete?
   - Current plan: Soft delete (immutability)
   - Alternative: Hard delete with backup

2. **Checkout Persistence**: Session-only or persist to profile?
   - Current plan: Session-only (GUC)
   - Alternative: Store in pggit.session_state table

3. **Force Flag**: Allow force=true on delete_branch?
   - Current plan: Yes, for admin override
   - Alternative: Require explicit MERGE before delete

4. **Metadata Field**: Include metadata in create_branch return?
   - Current plan: Yes, for extensibility
   - Alternative: Omit until Phase 3

---

## Next Steps (Post-Approval)

1. User approves this plan
2. Start implementation Day 1
3. Commit Phase 2 implementation when complete
4. Proceed to Phase 3: Object Tracking

---

**Plan Status**: Ready for User Review and Approval

**Prepared By**: Claude Code Architect
**Date**: 2025-12-24
**Version**: 1.0 (FINAL for Review)
