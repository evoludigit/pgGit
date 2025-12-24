# Phase 2 Skeleton Structure Reference

Quick guide to the skeleton files created for Phase 2 implementation.

---

## SQL Skeleton: sql/030_pggit_branch_management.sql

### File Structure
```
Lines 1-17      : Header comments, schema creation
Lines 19-101    : pggit.create_branch() skeleton
Lines 103-170   : pggit.delete_branch() skeleton
Lines 172-253   : pggit.list_branches() skeleton
Lines 255-318   : pggit.checkout_branch() skeleton
Lines 320-325   : Footer comments
```

### Each Function Skeleton Contains

**Function Definition** (Lines X-Y)
```sql
CREATE OR REPLACE FUNCTION pggit.function_name(
    p_param1 TYPE,
    p_param2 TYPE DEFAULT 'default'
) RETURNS TABLE (
    output_col1 TYPE,
    output_col2 TYPE,
    ...
) AS $$
```

**DECLARE Block**
```sql
DECLARE
    v_variable_name TYPE;
    v_another_variable TYPE;
BEGIN
```

**Implementation Outline** (Marked with TODO)
```sql
    -- TODO: Step 1 - Description
    -- - Sub-step a
    -- - Sub-step b

    -- TODO: Step 2 - Description
    -- - Sub-step a
    -- - Sub-step b
```

**Exception Placeholder**
```sql
    RAISE EXCEPTION 'function_name() not yet implemented';
END;
$$ LANGUAGE plpgsql;
```

---

## pggit.create_branch() Implementation Map

**Location**: Lines 49-101

**Function Signature**:
- Input: `p_branch_name` (TEXT), `p_parent_branch_name` (TEXT, default 'main'), `p_branch_type` (TEXT, default 'standard'), `p_metadata` (JSONB, default NULL)
- Output: TABLE with 9 columns (branch_id, branch_name, parent_branch_id, parent_branch_name, status, branch_type, head_commit_hash, created_at, created_by)

**Implementation Steps**:
```
Step 1 (Lines 71-75): Validate Inputs
  - Check p_branch_name not NULL/empty
  - Regex: ^[a-zA-Z0-9._/#-]+$
  - Enum validation: branch_type
  - Uniqueness: name not in pggit.branches

Step 2 (Lines 77-80): Find Active Parent Branch
  - SELECT id FROM pggit.branches
  - WHERE name = p_parent_branch_name AND status = 'ACTIVE'
  - RAISE exception if not found

Step 3 (Lines 82-83): Get Parent's Head Commit
  - Query head_commit_hash from parent branch

Step 4 (Lines 85-86): Generate Commit Hash
  - sha256(CURRENT_TIMESTAMP || p_branch_name || p_parent_branch_name)

Step 5 (Lines 88-90): Insert New Branch Entry
  - INSERT INTO pggit.branches with all fields
  - INSERT RETURNING id

Step 6 (Lines 92-94): Copy Parent's Objects
  - INSERT INTO pggit.objects from parent
  - WHERE branch_name = p_parent_branch_name AND is_active = true

Step 7 (Lines 96-97): Return Results
  - RETURN QUERY with all fields
```

**Variable Declarations** (Lines 65-69):
```sql
v_parent_id INTEGER;
v_new_branch_id INTEGER;
v_commit_hash CHAR(64);
v_parent_head_commit TEXT;
```

---

## pggit.delete_branch() Implementation Map

**Location**: Lines 130-170

**Function Signature**:
- Input: `p_branch_name` (TEXT), `p_force` (BOOLEAN, default false)
- Output: TABLE with 4 columns (success, message, branch_id, deleted_at)

**Implementation Steps**:
```
Step 1 (Lines 144-146): Validate Input
  - Check p_branch_name not NULL/empty
  - Verify branch exists

Step 2 (Lines 148-149): Prevent Main Deletion
  - IF p_branch_name = 'main' THEN RAISE EXCEPTION

Step 3 (Lines 151-154): Check Merge Status
  - If p_force = false:
    - Check status = 'MERGED'
    - RAISE if not MERGED

Step 4 (Lines 156-160): Cascade Cleanup
  - DELETE from pggit.data_branches (CASCADE FK)
  - DELETE from pggit.commits (CASCADE FK)
  - DELETE from pggit.history (CASCADE FK)
  - DELETE from pggit.objects for branch

Step 5 (Lines 162-163): Mark as DELETED
  - UPDATE pggit.branches SET status='DELETED'
  - Set merged_at = CURRENT_TIMESTAMP

Step 6 (Lines 165-166): Return Status
  - RETURN QUERY with success, message, branch_id, deleted_at
```

**Variable Declarations** (Lines 139-142):
```sql
v_branch_id INTEGER;
v_branch_status pggit.branch_status;
v_merge_message TEXT;
```

---

## pggit.list_branches() Implementation Map

**Location**: Lines 208-253

**Function Signature**:
- Input: `p_filter_status` (pggit.branch_status, default NULL), `p_include_deleted` (BOOLEAN, default false), `p_order_by` (TEXT, default 'created_at DESC')
- Output: TABLE with 14 columns (branch_id, branch_name, parent_branch_id, parent_branch_name, status, branch_type, head_commit_hash, object_count, storage_bytes, created_by, created_at, merged_at, merged_by, last_modified_at)

**Implementation Steps**:
```
Step 1 (Lines 229-231): Build Base Query
  - SELECT from pggit.branches b
  - LEFT JOIN pggit.branches pb ON b.parent_branch_id = pb.id

Step 2 (Lines 233-234): Apply Status Filter
  - If p_filter_status IS NOT NULL
  - WHERE b.status = p_filter_status

Step 3 (Lines 236-237): Apply Deleted Filter
  - If p_include_deleted = false
  - WHERE b.status != 'DELETED'

Step 4 (Lines 239-242): Calculate Metrics
  - object_count: COUNT(*) from pggit.objects
  - storage_bytes: SUM(LENGTH(ddl_normalized))
  - last_modified_at: MAX(updated_at)

Step 5 (Lines 244-246): Apply Ordering
  - Validate p_order_by against whitelist
  - Apply ORDER BY clause

Step 6 (Lines 248-249): Return Results
  - RETURN QUERY with all columns
```

---

## pggit.checkout_branch() Implementation Map

**Location**: Lines 281-318

**Function Signature**:
- Input: `p_branch_name` (TEXT)
- Output: TABLE with 5 columns (success, previous_branch, current_branch, message, switched_at)

**Implementation Steps**:
```
Step 1 (Lines 295-296): Validate Input
  - Check p_branch_name not NULL/empty

Step 2 (Lines 298-300): Get Previous Branch
  - current_setting('pggit.current_branch', true)
  - Default to 'main' if not set

Step 3 (Lines 302-305): Verify Target Exists
  - SELECT from pggit.branches
  - WHERE name = p_branch_name AND status = 'ACTIVE'
  - RAISE if not found/not active

Step 4 (Lines 307-308): Update Session Variable
  - EXECUTE: SET pggit.current_branch = p_branch_name

Step 5 (Lines 310-311): Optional Audit Trail
  - INSERT into pggit.history (optional)

Step 6 (Lines 313-314): Return Status
  - RETURN with success, previous, current, message, timestamp
```

**Variable Declarations** (Lines 290-293):
```sql
v_previous_branch TEXT;
v_branch_id INTEGER;
v_branch_status pggit.branch_status;
```

---

## Test Skeleton: tests/unit/test_phase2_branch_management.py

### File Structure
```
Lines 1-25      : File docstring and header
Lines 27-30     : Imports
Lines 32-179    : Database fixtures (db, db_setup)
Lines 135-174   : Helper functions (execute_query, execute_single)
Lines 181-210   : TestCreateBranch class (10 tests)
Lines 212-339   : TestDeleteBranch class (9 tests)
Lines 341-505   : TestListBranches class (8 tests)
Lines 507-664   : TestCheckoutBranch class (7 tests)
Lines 666-668   : Pytest markers
```

### Fixture: db()
- **Purpose**: Provide PostgreSQL connection
- **Environment Variables**: PGGIT_DB_* (host, port, user, password, name)
- **Returns**: psycopg connection with dict_row factory
- **Cleanup**: Auto-closes connection

### Fixture: db_setup(db)
- **Purpose**: Setup database schema for tests
- **Steps**:
  1. Load sql/001_schema.sql (Phase 1)
  2. Load sql/030_pggit_branch_management.sql (Phase 2)
  3. Create main branch
- **Cleanup**: TRUNCATE TABLE pggit.branches CASCADE
- **Returns**: db (PostgreSQL connection)

### Helper: execute_query(db, sql, *args)
- **Purpose**: Execute query and return list of dict rows
- **Returns**: List[dict] or empty list

### Helper: execute_single(db, sql, *args)
- **Purpose**: Execute query and return first dict row
- **Returns**: dict or None

### Test Class: TestCreateBranch (Lines 181-339)
```
test_create_branch_happy_path                   (Line 184)
test_create_branch_from_custom_parent           (Line 211)
test_create_branch_all_types                    (Line 241)
test_create_branch_duplicate_name_fails         (Line 263)
test_create_branch_invalid_parent_fails         (Line 286)
test_create_branch_empty_name_fails             (Line 302)
test_create_branch_invalid_name_chars_fails     (Line 315)
test_create_branch_invalid_type_fails           (Line 335)  # Not yet shown
test_create_branch_deleted_parent_fails         (Line ?)    # Not yet shown
test_create_branch_with_metadata                (Line ?)    # Not yet shown
```

### Test Class: TestDeleteBranch (Lines 341-?)
```
test_delete_branch_merged_happy_path
test_delete_branch_main_fails
test_delete_branch_unmerged_fails_without_force
test_delete_branch_unmerged_succeeds_with_force
test_delete_branch_nonexistent_fails
test_delete_branch_already_deleted_idempotent
test_delete_branch_cascade_cleanup
test_delete_branch_audit_trail_preserved
test_delete_branch_respects_created_by
```

### Test Class: TestListBranches (Lines 341-?)
```
test_list_branches_all
test_list_branches_filter_active
test_list_branches_filter_merged
test_list_branches_include_deleted
test_list_branches_exclude_deleted_default
test_list_branches_order_by_created_at_desc
test_list_branches_order_by_name_asc
test_list_branches_show_parent_hierarchy
```

### Test Class: TestCheckoutBranch (Lines 507-?)
```
test_checkout_branch_happy_path
test_checkout_branch_to_same_branch
test_checkout_branch_deleted_fails
test_checkout_branch_nonexistent_fails
test_checkout_branch_session_state_persists
test_checkout_branch_previous_tracking
test_checkout_branch_first_checkout_no_previous
```

---

## Test Patterns

### Happy Path Test
```python
def test_create_branch_happy_path(self, db_setup):
    """Test 1: Happy path - Create branch from main"""
    # Act
    result = execute_query(db_setup, """
        SELECT * FROM pggit.create_branch('feature/test')
    """)

    # Assert
    assert len(result) >= 1
    row = result[0]
    assert row['branch_name'] == 'feature/test'
    assert row['status'] == 'ACTIVE'
```

### Error Test
```python
def test_create_branch_invalid_parent_fails(self, db_setup):
    """Test 5: Cannot create branch with non-existent parent"""
    # Act & Assert
    with pytest.raises(Exception) as exc_info:
        execute_query(db_setup, """
            SELECT branch_id FROM pggit.create_branch('test', 'nonexistent')
        """)
    assert 'parent' in str(exc_info.value).lower()
```

### Setup Test
```python
def test_create_branch_from_custom_parent(self, db_setup):
    """Test 2: Create branch from non-main parent"""
    # Act: Create first level
    result_a = execute_query(db_setup, """
        SELECT branch_id FROM pggit.create_branch('feature/level1')
    """)
    branch_a_id = result_a[0]['branch_id']

    # Act: Create second level
    result_b = execute_query(db_setup, """
        SELECT * FROM pggit.create_branch('feature/level2', 'feature/level1')
    """)

    # Assert
    assert result_b[0]['parent_branch_id'] == branch_a_id
```

---

## Key Implementation Notes

1. **Variable Naming Conventions**:
   - `p_*` = parameter (e.g., p_branch_name)
   - `v_*` = variable (e.g., v_branch_id)

2. **Exception Handling**:
   - Use `RAISE EXCEPTION 'message'` for validation errors
   - Messages should be descriptive and mention what failed

3. **Soft Deletes**:
   - Mark status = 'DELETED' instead of actually deleting rows
   - This preserves audit trail

4. **Return Values**:
   - Functions return SETOF rows (may be 0-many rows)
   - Tests check `len(result) > 0` before accessing result[0]

5. **Test Assertions**:
   - Always use descriptive assertion messages
   - Check not just presence but actual values
   - Verify related fields (parent_id, status, created_by, etc.)

---

## How to Use This Reference

**When implementing a function**:
1. Open this file in one window
2. Open the SQL skeleton in another
3. Match the "Implementation Steps" to TODO blocks
4. Replace each TODO with actual SQL

**When writing tests**:
1. Review the test patterns above
2. Use `execute_query()` helper
3. Follow Arrange-Act-Assert structure
4. Add descriptive docstrings

---

**Ready to implement!** Each TODO block maps directly to one step in this reference.
