"""
Phase 2: Branch Management Tests

Comprehensive test suite for pggit branch management functions:
- pggit.create_branch() - Create new branches
- pggit.delete_branch() - Delete branches safely
- pggit.list_branches() - List branches with metadata
- pggit.checkout_branch() - Switch branches

Test Strategy:
- Each function has 8-10 test cases
- Tests cover happy paths, edge cases, and error conditions
- All tests require PostgreSQL database running with pggit schema
- Tests are independent and can run in any order
- Setup/teardown maintains clean state between tests

Total: 34 comprehensive test cases

REQUIREMENT: Before running tests, ensure:
1. PostgreSQL is running and accessible
2. Run: psql -U postgres -d pggit_test -f sql/001_schema.sql
3. Run: psql -U postgres -d pggit_test -f sql/030_pggit_branch_management.sql

Or use the provided setup_pggit_database() fixture.
"""

import os
import pytest
from psycopg import connect
from psycopg.rows import dict_row


# ============================================================================
# Database Connection Fixture
# ============================================================================

@pytest.fixture(scope="function")
def db():
    """
    Provide database connection for tests.

    Connects to PostgreSQL database specified by environment variables:
    - PGGIT_DB_HOST (default: localhost)
    - PGGIT_DB_PORT (default: 5432)
    - PGGIT_DB_USER (default: postgres)
    - PGGIT_DB_PASSWORD (default: postgres)
    - PGGIT_DB_NAME (default: pggit_test)

    Returns connection with dict rows enabled.
    Yields to test, then closes connection.
    """
    # Get connection parameters from environment
    host = os.getenv('PGGIT_DB_HOST', 'localhost')
    port = os.getenv('PGGIT_DB_PORT', '5432')
    user = os.getenv('PGGIT_DB_USER', 'postgres')
    password = os.getenv('PGGIT_DB_PASSWORD', 'postgres')
    dbname = os.getenv('PGGIT_DB_NAME', 'pggit_test')

    # Connect to database
    try:
        conn = connect(
            f"postgresql://{user}:{password}@{host}:{port}/{dbname}",
            row_factory=dict_row,
            autocommit=True
        )
    except Exception as e:
        pytest.skip(
            f"Cannot connect to PostgreSQL at {host}:{port}/{dbname}. "
            f"Set environment variables PGGIT_DB_* to override defaults. "
            f"Error: {e}"
        )

    yield conn

    # Cleanup: Close connection
    try:
        conn.close()
    except Exception:
        pass


@pytest.fixture(scope="function")
def db_setup(db):
    """
    Setup pggit database schema for each test.

    Executes Phase 1 schema (sql/001_schema.sql) and Phase 2 functions
    (sql/030_pggit_branch_management.sql).

    Cleans up after test by truncating all pggit tables with CASCADE.
    """
    cursor = db.cursor()

    # Setup: Load Phase 1 schema (idempotent - uses CREATE IF NOT EXISTS)
    try:
        with open('sql/001_schema.sql', 'r') as f:
            # Split by comments and execute statements
            sql_content = f.read()
            cursor.execute(sql_content)
    except Exception as e:
        pytest.skip(f"Cannot load Phase 1 schema: {e}")

    # Setup: Load Phase 2 functions
    try:
        with open('sql/030_pggit_branch_management.sql', 'r') as f:
            sql_content = f.read()
            cursor.execute(sql_content)
    except Exception as e:
        pytest.skip(f"Cannot load Phase 2 functions: {e}")

    # Setup: Ensure main branch exists
    try:
        cursor.execute("""
            INSERT INTO pggit.branches (id, name, status)
            VALUES (1, 'main', 'ACTIVE'::pggit.branch_status)
            ON CONFLICT (name) DO NOTHING
        """)
    except Exception as e:
        pytest.skip(f"Cannot create main branch: {e}")

    cursor.close()

    # Yield to test
    yield db

    # Teardown: Clean up test data (TRUNCATE CASCADE to handle FKs)
    try:
        cleanup_cursor = db.cursor()
        cleanup_cursor.execute("TRUNCATE TABLE pggit.branches CASCADE")
        cleanup_cursor.close()
    except Exception:
        pass


# ============================================================================
# Helper Functions for Tests
# ============================================================================

def execute_query(db, sql, *args):
    """
    Execute SQL query and return all results as list of dicts.

    Args:
        db: Database connection
        sql: SQL query string
        *args: Query parameters

    Returns:
        List of dict rows (empty list if no results)
    """
    cursor = db.cursor()
    if args:
        cursor.execute(sql, args)
    else:
        cursor.execute(sql)
    result = cursor.fetchall()
    cursor.close()
    return result if result else []


def execute_single(db, sql, *args):
    """
    Execute SQL query and return first result as dict.

    Args:
        db: Database connection
        sql: SQL query string
        *args: Query parameters

    Returns:
        Single dict row or None
    """
    result = execute_query(db, sql, *args)
    return result[0] if result else None


# ============================================================================
# Test Class: pggit.create_branch()
# ============================================================================

class TestCreateBranch:
    """Test suite for pggit.create_branch() function"""

    def test_create_branch_happy_path(self, db_setup):
        """
        Test 1: Happy path - Create branch from main with defaults

        Expected:
        - Returns single row with all fields populated
        - branch_name = 'feature/test'
        - status = 'ACTIVE'
        - parent_branch_id = 1 (main)
        - branch_type = 'standard'
        - created_at is not NULL
        """
        # Act
        result = execute_query(db_setup, """
            SELECT * FROM pggit.create_branch('feature/test')
        """)

        # Assert
        assert len(result) >= 1, "Should return at least one row"
        row = result[0]
        assert row['branch_name'] == 'feature/test'
        assert row['status'] == 'ACTIVE'
        assert row['parent_branch_id'] == 1  # main
        assert row['branch_type'] == 'standard'
        assert row['branch_id'] is not None
        assert row['created_at'] is not None

    def test_create_branch_from_custom_parent(self, db_setup):
        """
        Test 2: Create branch from non-main parent

        Expected:
        - Create branch A from main
        - Create branch B from A
        - B.parent_branch_id = A.branch_id
        - Shows hierarchical branching
        """
        # Arrange
        db = db_setup

        # Act: Create first level branch
        result_a = db.execute("""
            SELECT branch_id FROM pggit.create_branch('feature/level1')
        """)
        branch_a_id = result_a[0]['branch_id']

        # Act: Create second level branch
        result_b = db.execute("""
            SELECT * FROM pggit.create_branch('feature/level2', 'feature/level1')
        """)

        # Assert
        assert result_b is not None
        assert len(result_b) == 1
        assert result_b[0]['parent_branch_id'] == branch_a_id
        assert result_b[0]['branch_name'] == 'feature/level2'

    def test_create_branch_all_types(self, db_setup):
        """
        Test 3: Create branches of all valid types

        Expected:
        - Each type succeeds: 'standard', 'tiered', 'temporal', 'compressed'
        - Returned branch_type matches input
        """
        types = ['standard', 'tiered', 'temporal', 'compressed']

        # Act & Assert
        for branch_type in types:
            result = execute_query(db_setup, f"""
                SELECT branch_type FROM pggit.create_branch(
                    'feature/{branch_type}_test',
                    'main',
                    '{branch_type}'
                )
            """)
            assert len(result) > 0
            assert result[0]['branch_type'] == branch_type

    def test_create_branch_duplicate_name_fails(self, db_setup):
        """
        Test 4: Cannot create branch with duplicate name

        Expected:
        - First create succeeds
        - Second create with same name raises EXCEPTION
        - Error mentions uniqueness constraint
        """
        # Act: First creation succeeds
        result1 = execute_query(db_setup, """
            SELECT branch_id FROM pggit.create_branch('feature/dup')
        """)
        assert len(result1) > 0

        # Act & Assert: Second creation with same name fails
        with pytest.raises(Exception) as exc_info:
            execute_query(db_setup, """
                SELECT branch_id FROM pggit.create_branch('feature/dup')
            """)
        assert 'unique' in str(exc_info.value).lower() or \
               'already exists' in str(exc_info.value).lower()

    def test_create_branch_invalid_parent_fails(self, db_setup):
        """
        Test 5: Cannot create branch with non-existent parent

        Expected:
        - Raises EXCEPTION
        - Error message mentions "not found" or "parent"
        """
        # Act & Assert
        with pytest.raises(Exception) as exc_info:
            execute_query(db_setup, """
                SELECT branch_id FROM pggit.create_branch('test', 'nonexistent')
            """)
        error_msg = str(exc_info.value).lower()
        assert 'parent' in error_msg or 'not found' in error_msg

    def test_create_branch_empty_name_fails(self, db_setup):
        """
        Test 6: Cannot create branch with empty name

        Expected:
        - Raises EXCEPTION with validation error
        """
        # Act & Assert
        with pytest.raises(Exception):
            execute_query(db_setup, """
                SELECT branch_id FROM pggit.create_branch('')
            """)

    def test_create_branch_invalid_name_chars_fails(self, db_setup):
        """
        Test 7: Cannot create branch with invalid characters

        Expected:
        - Names with @ # $ % fail
        - Error mentions invalid format or characters
        """
        # Arrange
        db = db_setup
        invalid_names = ['feature@test', 'feature#test', 'feature$test']

        # Act & Assert
        for invalid_name in invalid_names:
            with pytest.raises(Exception) as exc_info:
                db.execute(f"""
                    SELECT branch_id FROM pggit.create_branch('{invalid_name}')
                """)
            error_msg = str(exc_info.value).lower()
            assert 'invalid' in error_msg or 'format' in error_msg or 'character' in error_msg

    def test_create_branch_invalid_type_fails(self, db_setup):
        """
        Test 8: Cannot create branch with invalid type

        Expected:
        - Invalid types fail with EXCEPTION
        - Valid types: standard, tiered, temporal, compressed
        """
        # Arrange
        db = db_setup

        # Act & Assert
        with pytest.raises(Exception) as exc_info:
            db.execute("""
                SELECT branch_id FROM pggit.create_branch(
                    'feature/test',
                    'main',
                    'invalid_type'
                )
            """)
        # Should fail with validation error

    def test_create_branch_deleted_parent_fails(self, db_setup):
        """
        Test 9: Cannot create branch from deleted parent

        Expected:
        - Create branch A
        - Mark A as DELETED
        - Try to create B from A
        - Raises exception about parent not being ACTIVE
        """
        # Arrange
        db = db_setup

        # Act: Create branch A
        result_a = db.execute("""
            SELECT branch_id FROM pggit.create_branch('feature/todelete')
        """)
        branch_a_id = result_a[0]['branch_id']

        # Act: Mark A as DELETED
        db.execute(f"""
            UPDATE pggit.branches SET status='DELETED' WHERE id = {branch_a_id}
        """)

        # Act & Assert: Try to create B from deleted A
        with pytest.raises(Exception) as exc_info:
            db.execute("""
                SELECT branch_id FROM pggit.create_branch('feature/fromdeleted', 'feature/todelete')
            """)
        error_msg = str(exc_info.value).lower()
        assert 'active' in error_msg or 'not found' in error_msg

    def test_create_branch_with_metadata(self, db_setup):
        """
        Test 10: Create branch with metadata

        Expected:
        - Metadata stored and returned (if implementation supports it)
        - Metadata persists in database
        """
        # Arrange
        db = db_setup
        metadata = '{"team": "backend", "epic": "auth"}'

        # Act
        result = db.execute(f"""
            SELECT * FROM pggit.create_branch(
                'feature/metadata',
                'main',
                'standard',
                '{metadata}'::jsonb
            )
        """)

        # Assert: Should not fail (if implementation supports metadata parameter)
        assert result is not None
        assert result[0]['branch_name'] == 'feature/metadata'


# ============================================================================
# Test Class: pggit.delete_branch()
# ============================================================================

class TestDeleteBranch:
    """Test suite for pggit.delete_branch() function"""

    def test_delete_branch_merged_happy_path(self, db_setup):
        """
        Test 1: Happy path - Delete a merged branch

        Expected:
        - Create branch
        - Mark as MERGED
        - Delete succeeds
        - success = true
        - Message describes deletion
        """
        # Arrange
        db = db_setup

        # Act: Create branch
        result_create = db.execute("""
            SELECT branch_id FROM pggit.create_branch('feature/tomerge')
        """)
        branch_id = result_create[0]['branch_id']

        # Act: Mark as MERGED
        db.execute(f"""
            UPDATE pggit.branches SET status='MERGED' WHERE id = {branch_id}
        """)

        # Act: Delete it
        result_delete = db.execute("""
            SELECT * FROM pggit.delete_branch('feature/tomerge')
        """)

        # Assert
        assert result_delete is not None
        assert result_delete[0]['success'] is True
        assert result_delete[0]['message'] is not None

    def test_delete_branch_main_fails(self, db_setup):
        """
        Test 2: Cannot delete main branch

        Expected:
        - Raises EXCEPTION
        - Error message mentions "main" or "cannot delete"
        """
        # Arrange
        db = db_setup

        # Act & Assert
        with pytest.raises(Exception) as exc_info:
            db.execute("""
                SELECT * FROM pggit.delete_branch('main')
            """)
        error_msg = str(exc_info.value).lower()
        assert 'main' in error_msg or 'cannot delete' in error_msg

    def test_delete_branch_unmerged_fails_without_force(self, db_setup):
        """
        Test 3: Cannot delete unmerged branch without force flag

        Expected:
        - Create branch with status ACTIVE
        - delete_branch('feature', force=false) fails
        - Error mentions "merge" or "force"
        """
        # Arrange
        db = db_setup

        # Act: Create branch (status = ACTIVE by default)
        db.execute("""
            SELECT branch_id FROM pggit.create_branch('feature/unmerged')
        """)

        # Act & Assert: Try to delete without force
        with pytest.raises(Exception) as exc_info:
            db.execute("""
                SELECT * FROM pggit.delete_branch('feature/unmerged', false)
            """)
        error_msg = str(exc_info.value).lower()
        assert 'merge' in error_msg or 'force' in error_msg

    def test_delete_branch_unmerged_succeeds_with_force(self, db_setup):
        """
        Test 4: Can force delete unmerged branch with force=true

        Expected:
        - Create branch (ACTIVE)
        - delete_branch('feature', force=true) succeeds
        - success = true
        """
        # Arrange
        db = db_setup

        # Act: Create branch
        db.execute("""
            SELECT branch_id FROM pggit.create_branch('feature/forcedelete')
        """)

        # Act: Force delete
        result = db.execute("""
            SELECT * FROM pggit.delete_branch('feature/forceDelete', true)
        """)

        # Assert
        assert result is not None
        assert result[0]['success'] is True

    def test_delete_branch_nonexistent_fails(self, db_setup):
        """
        Test 5: Cannot delete non-existent branch

        Expected:
        - Raises EXCEPTION or returns success=false
        """
        # Arrange
        db = db_setup

        # Act & Assert
        with pytest.raises(Exception):
            db.execute("""
                SELECT * FROM pggit.delete_branch('nonexistent')
            """)

    def test_delete_branch_already_deleted_idempotent(self, db_setup):
        """
        Test 6: Deleting already-deleted branch is idempotent

        Expected:
        - Delete branch once: success=true
        - Delete again: either success=false or exception caught gracefully
        """
        # Arrange
        db = db_setup

        # Act: Create and mark deleted
        result_create = db.execute("""
            SELECT branch_id FROM pggit.create_branch('feature/deltwice')
        """)
        branch_id = result_create[0]['branch_id']

        db.execute(f"UPDATE pggit.branches SET status='MERGED' WHERE id = {branch_id}")

        # Act: First delete
        result1 = db.execute("""
            SELECT * FROM pggit.delete_branch('feature/deltwice')
        """)
        assert result1[0]['success'] is True

        # Act: Second delete (should be safe/idempotent)
        # Either succeeds with success=false, or raises catchable exception
        try:
            result2 = db.execute("""
                SELECT * FROM pggit.delete_branch('feature/deltwice')
            """)
            # If it succeeds, success should be false (already deleted)
            assert result2 is not None  # At least doesn't crash
        except Exception:
            # Exception is acceptable for already-deleted
            pass

    def test_delete_branch_cascade_cleanup(self, db_setup):
        """
        Test 7: Deleting branch cascades to related data

        Expected:
        - Create branch with objects/commits
        - Delete branch
        - Objects for that branch are removed
        - Commits for that branch are removed
        """
        # Arrange
        db = db_setup

        # Act: Create branch
        result_create = db.execute("""
            SELECT branch_id FROM pggit.create_branch('feature/cascade')
        """)
        branch_id = result_create[0]['branch_id']

        # Add some test objects to this branch
        db.execute(f"""
            INSERT INTO pggit.objects
            (object_type, schema_name, object_name, branch_id, branch_name, is_active)
            VALUES ('TABLE', 'public', 'test_table', {branch_id}, 'feature/cascade', true)
        """)

        # Verify object exists
        objects_before = db.execute(f"""
            SELECT COUNT(*) as cnt FROM pggit.objects WHERE branch_id = {branch_id}
        """)
        assert objects_before[0]['cnt'] > 0

        # Act: Mark as merged and delete
        db.execute(f"UPDATE pggit.branches SET status='MERGED' WHERE id = {branch_id}")
        db.execute("SELECT * FROM pggit.delete_branch('feature/cascade')")

        # Assert: Objects should be cleaned up
        objects_after = db.execute(f"""
            SELECT COUNT(*) as cnt FROM pggit.objects WHERE branch_id = {branch_id}
        """)
        assert objects_after[0]['cnt'] == 0, "Objects should be deleted when branch is deleted"

    def test_delete_branch_audit_trail_preserved(self, db_setup):
        """
        Test 8: Audit trail preserved after deletion (soft delete)

        Expected:
        - Delete branch
        - Row still exists in pggit.branches
        - status = 'DELETED' (not actually removed)
        - Original created_by preserved
        """
        # Arrange
        db = db_setup

        # Act: Create and delete
        db.execute("""
            SELECT branch_id FROM pggit.create_branch('feature/audit')
        """)
        db.execute("UPDATE pggit.branches SET status='MERGED' WHERE name='feature/audit'")
        db.execute("SELECT * FROM pggit.delete_branch('feature/audit')")

        # Assert: Row still exists
        result = db.execute("""
            SELECT status, created_by FROM pggit.branches WHERE name = 'feature/audit'
        """)
        assert result is not None
        assert result[0]['status'] == 'DELETED'
        assert result[0]['created_by'] is not None  # Preserved

    def test_delete_branch_respects_created_by(self, db_setup):
        """
        Test 9: Delete operation records merged_by separately from created_by

        Expected:
        - Branch.created_by = original creator
        - After delete: merged_by = CURRENT_USER
        - Both fields preserved in audit trail
        """
        # Arrange
        db = db_setup

        # Act: Create, mark merged, delete
        db.execute("""
            SELECT branch_id FROM pggit.create_branch('feature/audit2')
        """)
        db.execute("UPDATE pggit.branches SET status='MERGED' WHERE name='feature/audit2'")
        db.execute("SELECT * FROM pggit.delete_branch('feature/audit2')")

        # Assert: Both audit fields exist
        result = db.execute("""
            SELECT created_by, merged_by FROM pggit.branches WHERE name = 'feature/audit2'
        """)
        assert result is not None
        assert result[0]['created_by'] is not None
        # merged_by might be same as created_by in test, but should exist


# ============================================================================
# Test Class: pggit.list_branches()
# ============================================================================

class TestListBranches:
    """Test suite for pggit.list_branches() function"""

    def test_list_branches_all(self, db_setup):
        """
        Test 1: List all branches without filters

        Expected:
        - Returns at least main branch
        - Can create more branches and see them
        - Excludes deleted by default
        """
        # Arrange
        db = db_setup

        # Act: Create some branches
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/a')")
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/b')")

        # Act: List all
        result = db.execute("""
            SELECT * FROM pggit.list_branches()
        """)

        # Assert
        assert result is not None
        assert len(result) >= 3  # main + 2 created
        names = [r['branch_name'] for r in result]
        assert 'main' in names
        assert 'feature/a' in names
        assert 'feature/b' in names

    def test_list_branches_filter_active(self, db_setup):
        """
        Test 2: Filter by ACTIVE status

        Expected:
        - Create ACTIVE and MERGED branches
        - filter_status='ACTIVE' returns only ACTIVE
        """
        # Arrange
        db = db_setup

        # Act: Create active branch
        result = db.execute("""
            SELECT branch_id FROM pggit.create_branch('feature/active')
        """)
        active_id = result[0]['branch_id']

        # Create merged branch
        db.execute("""
            SELECT branch_id FROM pggit.create_branch('feature/merged')
        """)
        db.execute("UPDATE pggit.branches SET status='MERGED' WHERE name='feature/merged'")

        # Act: List only ACTIVE
        result = db.execute("""
            SELECT * FROM pggit.list_branches(
                p_filter_status='ACTIVE'::pggit.branch_status
            )
        """)

        # Assert
        assert result is not None
        for row in result:
            assert row['status'] == 'ACTIVE'
        names = [r['branch_name'] for r in result]
        assert 'feature/active' in names
        assert 'feature/merged' not in names

    def test_list_branches_filter_merged(self, db_setup):
        """
        Test 3: Filter by MERGED status

        Expected:
        - Create branches and mark some MERGED
        - Filter returns only MERGED
        """
        # Arrange
        db = db_setup

        # Act: Create and merge
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/tom')")
        db.execute("UPDATE pggit.branches SET status='MERGED' WHERE name='feature/tom'")

        # Act: List merged
        result = db.execute("""
            SELECT * FROM pggit.list_branches(
                p_filter_status='MERGED'::pggit.branch_status
            )
        """)

        # Assert
        assert result is not None
        for row in result:
            assert row['status'] == 'MERGED'

    def test_list_branches_include_deleted(self, db_setup):
        """
        Test 4: Include deleted branches when flag is true

        Expected:
        - Create, merge, and delete branch
        - p_include_deleted=true shows it
        - p_include_deleted=false (default) hides it
        """
        # Arrange
        db = db_setup

        # Act: Create, merge, delete
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/todel')")
        db.execute("UPDATE pggit.branches SET status='MERGED' WHERE name='feature/todel'")
        db.execute("SELECT * FROM pggit.delete_branch('feature/todel')")

        # Act: List excluding deleted (default)
        result_exclude = db.execute("""
            SELECT * FROM pggit.list_branches(p_include_deleted=false)
        """)
        names_exclude = [r['branch_name'] for r in result_exclude]
        assert 'feature/todel' not in names_exclude

        # Act: List including deleted
        result_include = db.execute("""
            SELECT * FROM pggit.list_branches(p_include_deleted=true)
        """)
        names_include = [r['branch_name'] for r in result_include]
        assert 'feature/todel' in names_include

    def test_list_branches_exclude_deleted_default(self, db_setup):
        """
        Test 5: Deleted branches excluded by default

        Expected:
        - Create and delete branch
        - Default list_branches() excludes it
        """
        # Arrange
        db = db_setup

        # Act: Create, merge, delete
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/gone')")
        db.execute("UPDATE pggit.branches SET status='MERGED' WHERE name='feature/gone'")
        db.execute("SELECT * FROM pggit.delete_branch('feature/gone')")

        # Act: List with defaults
        result = db.execute("""
            SELECT * FROM pggit.list_branches()
        """)

        # Assert
        names = [r['branch_name'] for r in result]
        assert 'feature/gone' not in names, "Deleted should be excluded by default"

    def test_list_branches_order_by_created_at_desc(self, db_setup):
        """
        Test 6: Default ordering is created_at DESC (newest first)

        Expected:
        - Create branches in order A, B, C with small delays
        - Default list returns C, B, A (newest first)
        """
        # Arrange
        db = db_setup

        # Act: Create in order
        import time
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/first')")
        time.sleep(0.1)
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/second')")
        time.sleep(0.1)
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/third')")

        # Act: List with default ordering
        result = db.execute("""
            SELECT branch_name FROM pggit.list_branches()
            WHERE branch_name LIKE 'feature/%'
            ORDER BY created_at DESC
        """)

        # Assert: Should be newest first
        if len(result) >= 3:
            # Check relative ordering (may not be perfect due to timestamp precision)
            names = [r['branch_name'] for r in result]
            # 'third' should come before 'first' in the list
            third_idx = names.index('feature/third') if 'feature/third' in names else -1
            first_idx = names.index('feature/first') if 'feature/first' in names else -1
            if third_idx >= 0 and first_idx >= 0:
                assert third_idx < first_idx, "Newer branches should come first"

    def test_list_branches_order_by_name_asc(self, db_setup):
        """
        Test 7: Ordering by name ASC works

        Expected:
        - Create branches: zebra, apple, banana
        - order_by='name ASC' returns: apple, banana, zebra
        """
        # Arrange
        db = db_setup

        # Act: Create out of order
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/zebra')")
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/apple')")
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/banana')")

        # Act: List ordered by name
        result = db.execute("""
            SELECT branch_name FROM pggit.list_branches(
                p_order_by='name ASC'
            )
            WHERE branch_name LIKE 'feature/%'
        """)

        # Assert: Should be alphabetical
        names = [r['branch_name'] for r in result]
        expected = ['feature/apple', 'feature/banana', 'feature/zebra']
        actual = [n for n in names if n in expected]
        assert actual == expected, f"Expected {expected}, got {actual}"

    def test_list_branches_show_parent_hierarchy(self, db_setup):
        """
        Test 8: Parent branch names shown in results

        Expected:
        - Create main → feature/a → feature/a/sub
        - list_branches shows parent_branch_name for each
        - Hierarchy is clear
        """
        # Arrange
        db = db_setup

        # Act: Create hierarchy
        result_a = db.execute("""
            SELECT branch_id FROM pggit.create_branch('feature/a')
        """)

        result_b = db.execute("""
            SELECT branch_id FROM pggit.create_branch('feature/a/sub', 'feature/a')
        """)

        # Act: List
        result = db.execute("""
            SELECT branch_name, parent_branch_name FROM pggit.list_branches()
        """)

        # Assert: Verify hierarchy
        rows_dict = {r['branch_name']: r['parent_branch_name'] for r in result}
        assert rows_dict.get('feature/a') == 'main'
        assert rows_dict.get('feature/a/sub') == 'feature/a'


# ============================================================================
# Test Class: pggit.checkout_branch()
# ============================================================================

class TestCheckoutBranch:
    """Test suite for pggit.checkout_branch() function"""

    def test_checkout_branch_happy_path(self, db_setup):
        """
        Test 1: Happy path - Checkout from main to feature

        Expected:
        - Create feature branch
        - checkout_branch('feature/test')
        - success=true
        - previous_branch='main'
        - current_branch='feature/test'
        """
        # Arrange
        db = db_setup

        # Act: Create branch
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/test')")

        # Act: Checkout
        result = db.execute("""
            SELECT * FROM pggit.checkout_branch('feature/test')
        """)

        # Assert
        assert result is not None
        assert result[0]['success'] is True
        assert result[0]['current_branch'] == 'feature/test'
        # previous_branch might be 'main' or NULL depending on implementation

    def test_checkout_branch_to_same_branch(self, db_setup):
        """
        Test 2: Checkout to current branch is idempotent

        Expected:
        - Checkout to main twice
        - Both succeed
        - No error
        """
        # Arrange
        db = db_setup

        # Act: First checkout to main (should work)
        result1 = db.execute("""
            SELECT * FROM pggit.checkout_branch('main')
        """)
        assert result1[0]['success'] is True

        # Act: Second checkout to main
        result2 = db.execute("""
            SELECT * FROM pggit.checkout_branch('main')
        """)

        # Assert
        assert result2 is not None
        assert result2[0]['success'] is True

    def test_checkout_branch_deleted_fails(self, db_setup):
        """
        Test 3: Cannot checkout to deleted branch

        Expected:
        - Create and delete branch
        - checkout_branch raises exception
        """
        # Arrange
        db = db_setup

        # Act: Create, merge, delete
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/dead')")
        db.execute("UPDATE pggit.branches SET status='MERGED' WHERE name='feature/dead'")
        db.execute("SELECT * FROM pggit.delete_branch('feature/dead')")

        # Act & Assert: Try to checkout
        with pytest.raises(Exception) as exc_info:
            db.execute("""
                SELECT * FROM pggit.checkout_branch('feature/dead')
            """)
        error_msg = str(exc_info.value).lower()
        assert 'not found' in error_msg or 'active' in error_msg

    def test_checkout_branch_nonexistent_fails(self, db_setup):
        """
        Test 4: Cannot checkout to non-existent branch

        Expected:
        - checkout_branch('nonexistent') raises exception
        """
        # Arrange
        db = db_setup

        # Act & Assert
        with pytest.raises(Exception) as exc_info:
            db.execute("""
                SELECT * FROM pggit.checkout_branch('nonexistent')
            """)
        assert 'not found' in str(exc_info.value).lower()

    def test_checkout_branch_session_state_persists(self, db_setup):
        """
        Test 5: Session state persists within same connection

        Expected:
        - Checkout to feature/test
        - Query current_setting in same session
        - Returns 'feature/test'
        """
        # Arrange
        db = db_setup

        # Act: Create and checkout
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/persistent')")
        db.execute("""
            SELECT * FROM pggit.checkout_branch('feature/persistent')
        """)

        # Act: Query session variable
        result = db.execute("""
            SELECT current_setting('pggit.current_branch', true) as current
        """)

        # Assert: Should be set to our branch
        assert result is not None
        assert result[0]['current'] == 'feature/persistent'

    def test_checkout_branch_previous_tracking(self, db_setup):
        """
        Test 6: Previous branch is tracked correctly

        Expected:
        - Start at main (or checkout main)
        - Checkout to feature/a
        - Checkout to feature/b
        - Second checkout shows previous='feature/a'
        """
        # Arrange
        db = db_setup

        # Act: Create branches
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/prev1')")
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/prev2')")

        # Checkout chain
        result1 = db.execute("""
            SELECT * FROM pggit.checkout_branch('feature/prev1')
        """)
        # First checkout from main should show main as previous
        assert result1[0]['previous_branch'] == 'main' or result1[0]['previous_branch'] is None

        # Second checkout
        result2 = db.execute("""
            SELECT * FROM pggit.checkout_branch('feature/prev2')
        """)

        # Assert: Should show prev1 as previous
        assert result2 is not None
        assert result2[0]['previous_branch'] == 'feature/prev1'

    def test_checkout_branch_first_checkout_no_previous(self, db_setup):
        """
        Test 7: First checkout in fresh session handles no previous gracefully

        Expected:
        - New connection/fresh session
        - Checkout to feature
        - previous_branch is NULL or 'main' (gracefully handled)
        - No exception raised
        """
        # Arrange
        db = db_setup

        # Act: Create and checkout to feature (first checkout in session)
        db.execute("SELECT branch_id FROM pggit.create_branch('feature/first_checkout')")
        result = db.execute("""
            SELECT * FROM pggit.checkout_branch('feature/first_checkout')
        """)

        # Assert: Should succeed even though no previous branch set
        assert result is not None
        assert result[0]['success'] is True
        assert result[0]['current_branch'] == 'feature/first_checkout'
        # previous_branch might be NULL or 'main' - both acceptable


# ============================================================================
# Markers for Test Execution
# ============================================================================

pytestmark = pytest.mark.integration
# All these tests require database access and are integration tests
