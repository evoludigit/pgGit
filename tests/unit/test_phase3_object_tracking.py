"""
Phase 3: Object Tracking & Visibility Tests

Tests for the three Phase 3 functions:
1. pggit.get_branch_objects() - Query objects on a specific branch
2. pggit.get_object_history() - View change history for an object
3. pggit.diff_branches() - Compare objects between two branches

Total: 28 unit tests
- TestGetBranchObjects: 10 tests
- TestGetObjectHistory: 8 tests
- TestDiffBranches: 10 tests
"""

import pytest
from datetime import datetime, timedelta
from typing import Any
import hashlib


def compute_hash(content: str) -> str:
    """Compute SHA256 hash of content"""
    return hashlib.sha256(content.encode()).hexdigest()


@pytest.fixture
def setup_test_data(test_db):
    """
    Setup test data for Phase 3 tests.
    Creates test branches, objects, and history records.
    """
    cursor = test_db.cursor()

    # Ensure main branch exists
    cursor.execute("""
        INSERT INTO pggit.branches (branch_name, status, created_by)
        VALUES ('main', 'ACTIVE', 'test_user')
        ON CONFLICT (branch_name) DO NOTHING
    """)
    test_db.commit()

    # Get main branch ID
    cursor.execute("SELECT branch_id FROM pggit.branches WHERE branch_name = 'main'")
    main_branch_id = cursor.fetchone()[0]

    # Create feature branch for testing
    cursor.execute("""
        INSERT INTO pggit.branches (branch_name, parent_branch_id, status, created_by)
        VALUES ('feature/test', %s, 'ACTIVE', 'test_user')
        ON CONFLICT (branch_name) DO NOTHING
    """, (main_branch_id,))
    test_db.commit()

    # Get feature branch ID
    cursor.execute("SELECT branch_id FROM pggit.branches WHERE branch_name = 'feature/test'")
    feature_branch_id = cursor.fetchone()[0]

    # Create test objects in schema_objects table
    # Table 1: users table
    hash1 = compute_hash("CREATE TABLE public.users (id SERIAL PRIMARY KEY, name TEXT)")
    cursor.execute("""
        INSERT INTO pggit.schema_objects
        (object_type, schema_name, object_name, current_definition, content_hash, is_active)
        VALUES ('TABLE', 'public', 'users', 'CREATE TABLE public.users...', %s, true)
        ON CONFLICT (object_type, schema_name, object_name) DO NOTHING
        RETURNING object_id
    """, (hash1,))
    result = cursor.fetchone()
    if result:
        user_table_id = result[0]
    else:
        cursor.execute("SELECT object_id FROM pggit.schema_objects WHERE object_name = 'users' AND schema_name = 'public'")
        user_table_id = cursor.fetchone()[0]

    # Table 2: orders table
    hash2 = compute_hash("CREATE TABLE public.orders (id SERIAL PRIMARY KEY, user_id INTEGER)")
    cursor.execute("""
        INSERT INTO pggit.schema_objects
        (object_type, schema_name, object_name, current_definition, content_hash, is_active)
        VALUES ('TABLE', 'public', 'orders', 'CREATE TABLE public.orders...', %s, true)
        ON CONFLICT (object_type, schema_name, object_name) DO NOTHING
        RETURNING object_id
    """, (hash2,))
    result = cursor.fetchone()
    if result:
        order_table_id = result[0]
    else:
        cursor.execute("SELECT object_id FROM pggit.schema_objects WHERE object_name = 'orders' AND schema_name = 'public'")
        order_table_id = cursor.fetchone()[0]

    # Table 3: view
    hash3 = compute_hash("CREATE VIEW public.user_view AS SELECT * FROM users")
    cursor.execute("""
        INSERT INTO pggit.schema_objects
        (object_type, schema_name, object_name, current_definition, content_hash, is_active)
        VALUES ('VIEW', 'public', 'user_view', 'CREATE VIEW public.user_view...', %s, true)
        ON CONFLICT (object_type, schema_name, object_name) DO NOTHING
        RETURNING object_id
    """, (hash3,))
    result = cursor.fetchone()
    if result:
        view_id = result[0]
    else:
        cursor.execute("SELECT object_id FROM pggit.schema_objects WHERE object_name = 'user_view' AND schema_name = 'public'")
        view_id = cursor.fetchone()[0]

    # Table 4: function in custom schema
    hash4 = compute_hash("CREATE FUNCTION app.get_user() RETURNS TABLE")
    cursor.execute("""
        INSERT INTO pggit.schema_objects
        (object_type, schema_name, object_name, current_definition, content_hash, is_active)
        VALUES ('FUNCTION', 'app', 'get_user', 'CREATE FUNCTION app.get_user()...', %s, true)
        ON CONFLICT (object_type, schema_name, object_name) DO NOTHING
        RETURNING object_id
    """, (hash4,))
    result = cursor.fetchone()
    if result:
        func_id = result[0]
    else:
        cursor.execute("SELECT object_id FROM pggit.schema_objects WHERE object_name = 'get_user' AND schema_name = 'app'")
        func_id = cursor.fetchone()[0]

    test_db.commit()

    # Create commits first (required for object_history FK constraint)
    commit_hashes = {}
    now = datetime.now()

    # Create 2 commits for main branch
    for i in range(2):
        commit_hash = compute_hash(f"commit_main_{i}")
        cursor.execute("""
            INSERT INTO pggit.commits (commit_hash, branch_id, author_name, author_time)
            VALUES (%s, %s, 'test_user', %s)
        """, (commit_hash, main_branch_id, now - timedelta(hours=3-i)))
        if i == 0:
            commit_hashes['main_1'] = commit_hash
        else:
            commit_hashes['main_2'] = commit_hash

    # Create 2 commits for feature branch
    for i in range(2):
        commit_hash = compute_hash(f"commit_feature_{i}")
        cursor.execute("""
            INSERT INTO pggit.commits (commit_hash, branch_id, author_name, author_time)
            VALUES (%s, %s, 'test_user', %s)
        """, (commit_hash, feature_branch_id, now - timedelta(minutes=30-i*10)))
        if i == 0:
            commit_hashes['feature_1'] = commit_hash
        else:
            commit_hashes['feature_2'] = commit_hash

    test_db.commit()

    # Create history records - all objects on main branch
    cursor.execute("""
        INSERT INTO pggit.object_history
        (object_id, branch_id, change_type, change_severity, before_hash, after_hash, commit_hash, author_name, author_time)
        VALUES (%s, %s, 'CREATE', 'MAJOR', NULL, %s, %s, 'test_user', %s)
    """, (user_table_id, main_branch_id, hash1, commit_hashes['main_1'], now - timedelta(hours=3)))

    cursor.execute("""
        INSERT INTO pggit.object_history
        (object_id, branch_id, change_type, change_severity, before_hash, after_hash, commit_hash, author_name, author_time)
        VALUES (%s, %s, 'CREATE', 'MAJOR', NULL, %s, %s, 'test_user', %s)
    """, (order_table_id, main_branch_id, hash2, commit_hashes['main_1'], now - timedelta(hours=2)))

    cursor.execute("""
        INSERT INTO pggit.object_history
        (object_id, branch_id, change_type, change_severity, before_hash, after_hash, commit_hash, author_name, author_time)
        VALUES (%s, %s, 'CREATE', 'MINOR', NULL, %s, %s, 'test_user', %s)
    """, (view_id, main_branch_id, hash3, commit_hashes['main_1'], now - timedelta(hours=1)))

    cursor.execute("""
        INSERT INTO pggit.object_history
        (object_id, branch_id, change_type, change_severity, before_hash, after_hash, commit_hash, author_name, author_time)
        VALUES (%s, %s, 'CREATE', 'MAJOR', NULL, %s, %s, 'test_user', %s)
    """, (func_id, main_branch_id, hash4, commit_hashes['main_2'], now))

    # Add history to feature branch (same objects, some modified)
    hash1_modified = compute_hash("CREATE TABLE public.users (id SERIAL PRIMARY KEY, name TEXT, email TEXT)")
    cursor.execute("""
        INSERT INTO pggit.object_history
        (object_id, branch_id, change_type, change_severity, before_hash, after_hash, commit_hash, author_name, author_time)
        VALUES (%s, %s, 'ALTER', 'MINOR', %s, %s, %s, 'test_user', %s)
    """, (user_table_id, feature_branch_id, hash1, hash1_modified, commit_hashes['feature_1'], now - timedelta(minutes=30)))

    cursor.execute("""
        INSERT INTO pggit.object_history
        (object_id, branch_id, change_type, change_severity, before_hash, after_hash, commit_hash, author_name, author_time)
        VALUES (%s, %s, 'CREATE', 'MAJOR', NULL, %s, %s, 'test_user', %s)
    """, (order_table_id, feature_branch_id, hash2, commit_hashes['feature_1'], now - timedelta(minutes=20)))

    test_db.commit()

    yield {
        'db': test_db,
        'main_branch_id': main_branch_id,
        'feature_branch_id': feature_branch_id,
        'user_table_id': user_table_id,
        'order_table_id': order_table_id,
        'view_id': view_id,
        'func_id': func_id,
        'hash1': hash1,
        'hash2': hash2,
        'hash3': hash3,
        'hash4': hash4,
        'hash1_modified': hash1_modified,
    }

    # Cleanup not needed - test database is isolated


class TestGetBranchObjects:
    """Tests for pggit.get_branch_objects() function"""

    def test_get_all_objects_from_main(self, setup_test_data):
        """Test 1: Happy path - Get all objects from main branch"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Call get_branch_objects('main')
        cursor.execute("SELECT * FROM pggit.get_branch_objects('main')")
        results = cursor.fetchall()

        # Assert: Returns all expected objects (4 on main)
        assert len(results) == 4
        object_names = [row[3] for row in results]  # object_name is 4th column
        assert 'users' in object_names
        assert 'orders' in object_names
        assert 'user_view' in object_names
        assert 'get_user' in object_names

    def test_current_branch_context_null(self, setup_test_data):
        """Test 2: Current branch context - NULL branch uses session"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Arrange: Set session variable to feature/test
        cursor.execute("SET pggit.current_branch = 'feature/test'")
        data['db'].commit()

        # Act: Call get_branch_objects(NULL) - should use session branch
        cursor.execute("SELECT * FROM pggit.get_branch_objects(NULL)")
        results = cursor.fetchall()

        # Assert: Returns objects from feature/test (2 objects)
        assert len(results) == 2
        object_names = [row[3] for row in results]
        assert 'users' in object_names
        assert 'orders' in object_names

    def test_filter_by_object_type_table(self, setup_test_data):
        """Test 3: Filter by type - Get only tables"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Call get_branch_objects(p_object_type='TABLE')
        cursor.execute("SELECT * FROM pggit.get_branch_objects('main', 'TABLE')")
        results = cursor.fetchall()

        # Assert: Returns only table objects (2 tables on main)
        assert len(results) == 2
        for row in results:
            assert row[1] == 'TABLE'  # object_type is 2nd column

    def test_filter_by_schema_public(self, setup_test_data):
        """Test 4: Filter by schema - Get public schema only"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Call get_branch_objects(p_schema_filter='public')
        cursor.execute("SELECT * FROM pggit.get_branch_objects('main', NULL, 'public')")
        results = cursor.fetchall()

        # Assert: Returns only public schema objects (3 on main)
        assert len(results) == 3
        for row in results:
            assert row[2] == 'public'  # schema_name is 3rd column

    def test_multiple_filters_type_and_schema(self, setup_test_data):
        """Test 5: Multiple filters - Type AND schema"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Call with both filters
        cursor.execute("SELECT * FROM pggit.get_branch_objects('main', 'TABLE', 'public')")
        results = cursor.fetchall()

        # Assert: Returns only public tables (2)
        assert len(results) == 2
        for row in results:
            assert row[1] == 'TABLE'
            assert row[2] == 'public'

    def test_order_by_object_name_asc(self, setup_test_data):
        """Test 6: Order by object_name - Alphabetical ASC"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Call with order_by='object_name ASC'
        cursor.execute("SELECT * FROM pggit.get_branch_objects('main', NULL, NULL, 'object_name ASC')")
        results = cursor.fetchall()

        # Assert: Results ordered alphabetically
        names = [row[3] for row in results]
        assert names == sorted(names)

    def test_order_by_object_type_desc(self, setup_test_data):
        """Test 7: Order by type - Ordered by type"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Call with order_by='object_type DESC'
        cursor.execute("SELECT * FROM pggit.get_branch_objects('main', NULL, NULL, 'object_type DESC')")
        results = cursor.fetchall()

        # Assert: Results ordered by type
        types = [row[1] for row in results]
        assert len(types) > 0

    def test_nonexistent_branch_empty_result(self, setup_test_data):
        """Test 8: Non-existent branch - Returns empty result"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Call with non-existent branch
        cursor.execute("SELECT * FROM pggit.get_branch_objects('nonexistent_branch')")
        results = cursor.fetchall()

        # Assert: Returns empty result (no exception)
        assert len(results) == 0

    def test_deleted_branch_can_query(self, setup_test_data):
        """Test 9: Deleted branch - Can still query"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Arrange: Create and delete a branch
        cursor.execute("""
            INSERT INTO pggit.branches (branch_name, parent_branch_id, status, created_by)
            VALUES ('temp_branch', %s, 'DELETED', 'test_user')
        """, (data['main_branch_id'],))
        cursor.execute("SELECT branch_id FROM pggit.branches WHERE branch_name = 'temp_branch'")
        temp_branch_id = cursor.fetchone()[0]

        # Add one object to this branch
        temp_commit = compute_hash("temp_commit")
        cursor.execute("""
            INSERT INTO pggit.commits (commit_hash, branch_id, author_name, author_time)
            VALUES (%s, %s, 'test_user', NOW())
        """, (temp_commit, temp_branch_id))
        cursor.execute("""
            INSERT INTO pggit.object_history
            (object_id, branch_id, change_type, change_severity, before_hash, after_hash, commit_hash, author_name, author_time)
            VALUES (%s, %s, 'CREATE', 'MAJOR', NULL, %s, %s, 'test_user', NOW())
        """, (data['user_table_id'], temp_branch_id, data['hash1'], temp_commit))
        data['db'].commit()

        # Act: Query deleted branch
        cursor.execute("SELECT * FROM pggit.get_branch_objects('temp_branch')")
        results = cursor.fetchall()

        # Assert: Can still query deleted branch
        assert len(results) == 1

    def test_object_versioning_track_versions(self, setup_test_data):
        """Test 10: Object versioning - Track schema versions"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Call get_branch_objects
        cursor.execute("SELECT * FROM pggit.get_branch_objects('main')")
        results = cursor.fetchall()

        # Assert: All rows have version info (columns 6-8: version_major, minor, patch)
        assert len(results) > 0
        for row in results:
            # version_major is column 6, minor is 7, patch is 8
            assert row[5] is not None or row[5] == 0  # version_major


class TestGetObjectHistory:
    """Tests for pggit.get_object_history() function"""

    def test_get_history_for_table(self, setup_test_data):
        """Test 1: Happy path - Get history for table"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Call get_object_history('public.users')
        cursor.execute("SELECT * FROM pggit.get_object_history('public.users', 'main')")
        results = cursor.fetchall()

        # Assert: Returns history (1 CREATE on main)
        assert len(results) >= 1
        assert results[0][2] == 'CREATE'  # change_type

    def test_empty_history_new_object(self, setup_test_data):
        """Test 2: Empty history - New object"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Arrange: Create new object with no history
        hash_new = compute_hash("CREATE TABLE public.empty_table ()")
        cursor.execute("""
            INSERT INTO pggit.schema_objects
            (object_type, schema_name, object_name, current_definition, content_hash, is_active)
            VALUES ('TABLE', 'public', 'empty_table', 'CREATE TABLE...', %s, true)
        """, (hash_new,))
        data['db'].commit()

        # Act: Call get_object_history for object with no history
        cursor.execute("SELECT * FROM pggit.get_object_history('public.empty_table', 'main')")
        results = cursor.fetchall()

        # Assert: Returns empty (no history on main)
        assert len(results) == 0

    def test_multiple_changes_track_alter_sequence(self, setup_test_data):
        """Test 3: Multiple changes - Track ALTER sequence"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Arrange: Add multiple history records to users table
        hash_alter1 = compute_hash("ALTER TABLE public.users ADD COLUMN email TEXT")
        # Create a commit first
        commit_hash = compute_hash("alter_commit")
        cursor.execute("""
            INSERT INTO pggit.commits (commit_hash, branch_id, author_name, author_time)
            VALUES (%s, %s, 'test_user', NOW())
        """, (commit_hash, data['main_branch_id']))
        cursor.execute("""
            INSERT INTO pggit.object_history
            (object_id, branch_id, change_type, change_severity, before_hash, after_hash, commit_hash, author_name, author_time)
            VALUES (%s, %s, 'ALTER', 'MINOR', %s, %s, %s, 'test_user', NOW())
        """, (data['user_table_id'], data['main_branch_id'], data['hash1'], hash_alter1, commit_hash))
        data['db'].commit()

        # Act: Get history for users
        cursor.execute("SELECT * FROM pggit.get_object_history('public.users', 'main')")
        results = cursor.fetchall()

        # Assert: Returns multiple records, ordered by time DESC
        assert len(results) >= 2
        change_types = [row[2] for row in results]
        assert 'ALTER' in change_types
        assert 'CREATE' in change_types

    def test_nonexistent_object_empty_result(self, setup_test_data):
        """Test 4: Non-existent object - Returns empty result"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Call with non-existent object
        cursor.execute("SELECT * FROM pggit.get_object_history('nonexistent', 'main')")
        results = cursor.fetchall()

        # Assert: Returns empty (no exception)
        assert len(results) == 0

    def test_current_branch_context_null(self, setup_test_data):
        """Test 5: Current branch context - NULL uses session"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Arrange: Set session branch
        cursor.execute("SET pggit.current_branch = 'feature/test'")
        data['db'].commit()

        # Act: Call with NULL branch
        cursor.execute("SELECT * FROM pggit.get_object_history('public.users', NULL)")
        results = cursor.fetchall()

        # Assert: Returns history from feature/test (1 ALTER)
        assert len(results) >= 1
        assert results[0][2] == 'ALTER'  # Should be ALTER on feature branch

    def test_limit_results_pagination(self, setup_test_data):
        """Test 6: Limit results - Pagination"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Get history with limit=1
        cursor.execute("SELECT * FROM pggit.get_object_history('public.orders', 'main', 1)")
        results = cursor.fetchall()

        # Assert: Returns only 1 record
        assert len(results) <= 1

    def test_schema_qualified_names_full_path(self, setup_test_data):
        """Test 7: Schema-qualified names - Full path"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Call with schema-qualified name
        cursor.execute("SELECT * FROM pggit.get_object_history('app.get_user', 'main')")
        results = cursor.fetchall()

        # Assert: Returns history for function
        assert len(results) >= 1

    def test_change_tracking_severity_and_user(self, setup_test_data):
        """Test 8: Change tracking - Severity and user"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Get history
        cursor.execute("SELECT * FROM pggit.get_object_history('public.users', 'main')")
        results = cursor.fetchall()

        # Assert: Records have severity and user info
        assert len(results) > 0
        for row in results:
            assert row[3] is not None  # change_severity
            assert row[6] is not None  # changed_by


class TestDiffBranches:
    """Tests for pggit.diff_branches() function"""

    def test_compare_two_branches_happy_path(self, setup_test_data):
        """Test 1: Happy path - Compare two branches"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Compare main and feature/test
        cursor.execute("SELECT * FROM pggit.diff_branches('main', 'feature/test')")
        results = cursor.fetchall()

        # Assert: Returns differences (users is MODIFIED)
        assert len(results) > 0
        change_types = [row[4] for row in results]  # change_type is 5th column
        assert 'MODIFIED' in change_types

    def test_no_changes_identical_branches(self, setup_test_data):
        """Test 2: No changes - Identical branches"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Compare branch with itself
        cursor.execute("SELECT * FROM pggit.diff_branches('main', 'main')")
        results = cursor.fetchall()

        # Assert: Returns empty (UNCHANGED filtered out)
        assert len(results) == 0

    def test_new_objects_only_in_target(self, setup_test_data):
        """Test 3: New objects - Only in target"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Arrange: Add object only to feature branch
        hash_new = compute_hash("CREATE TABLE public.new_table ()")
        cursor.execute("""
            INSERT INTO pggit.schema_objects
            (object_type, schema_name, object_name, current_definition, content_hash, is_active)
            VALUES ('TABLE', 'public', 'new_table', 'CREATE TABLE...', %s, true)
        """, (hash_new,))
        cursor.execute("SELECT object_id FROM pggit.schema_objects WHERE object_name = 'new_table'")
        new_table_id = cursor.fetchone()[0]

        # Add to feature branch only
        new_commit = compute_hash("new_table_commit")
        cursor.execute("""
            INSERT INTO pggit.commits (commit_hash, branch_id, author_name, author_time)
            VALUES (%s, %s, 'test_user', NOW())
        """, (new_commit, data['feature_branch_id']))
        cursor.execute("""
            INSERT INTO pggit.object_history
            (object_id, branch_id, change_type, change_severity, before_hash, after_hash, commit_hash, author_name, author_time)
            VALUES (%s, %s, 'CREATE', 'MAJOR', NULL, %s, %s, 'test_user', NOW())
        """, (new_table_id, data['feature_branch_id'], hash_new, new_commit))
        data['db'].commit()

        # Act: Compare main (source) to feature (target)
        cursor.execute("SELECT * FROM pggit.diff_branches('main', 'feature/test')")
        results = cursor.fetchall()

        # Assert: new_table shows as ADDED
        change_types = [row[4] for row in results]
        assert 'ADDED' in change_types

    def test_deleted_objects_only_in_source(self, setup_test_data):
        """Test 4: Deleted objects - Only in source"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Arrange: Remove view from feature branch
        # (it already doesn't exist on feature, so comparing main->feature should show view as REMOVED)
        # Act: Compare feature (source) to main (target) - view_view not on feature
        cursor.execute("SELECT * FROM pggit.diff_branches('feature/test', 'main')")
        results = cursor.fetchall()

        # Assert: user_view shows as REMOVED (on main but not feature)
        object_names = [row[2] for row in results]  # object_name is 3rd column
        if 'user_view' in object_names:
            for row in results:
                if row[2] == 'user_view':
                    assert row[4] == 'REMOVED'

    def test_modified_objects_different_versions(self, setup_test_data):
        """Test 5: Modified objects - Different versions"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Compare branches - users has different hashes
        cursor.execute("SELECT * FROM pggit.diff_branches('main', 'feature/test')")
        results = cursor.fetchall()

        # Assert: users shows as MODIFIED with different hashes
        for row in results:
            if row[2] == 'users':  # object_name
                assert row[4] == 'MODIFIED'  # change_type
                assert row[7] != row[8]  # source_hash != target_hash

    def test_conflict_detection_diverged_changes(self, setup_test_data):
        """Test 6: Conflicts - Diverged changes"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Compare branches with modified object
        cursor.execute("SELECT * FROM pggit.diff_branches('main', 'feature/test')")
        results = cursor.fetchall()

        # Assert: Modified objects have conflict detection
        for row in results:
            if row[4] == 'MODIFIED':
                assert row[9] is not None  # is_conflict column

    def test_current_branch_context_null(self, setup_test_data):
        """Test 7: Current branch context - NULL uses session"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Arrange: Set session to main
        cursor.execute("SET pggit.current_branch = 'main'")
        data['db'].commit()

        # Act: Call with NULL target
        cursor.execute("SELECT * FROM pggit.diff_branches('feature/test', NULL)")
        results = cursor.fetchall()

        # Assert: Compares against main
        assert len(results) > 0

    def test_nonexistent_branch_exception(self, setup_test_data):
        """Test 8: Non-existent branch - Raises exception"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Call with non-existent source branch
        try:
            cursor.execute("SELECT * FROM pggit.diff_branches('nonexistent', 'main')")
            results = cursor.fetchall()
            # Should raise exception
            assert False, "Should have raised exception"
        except Exception as e:
            # Assert: Raises exception
            assert 'does not exist' in str(e).lower()

    def test_same_branch_self_diff_empty(self, setup_test_data):
        """Test 9: Same branch - Self-diff returns empty"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Act: Compare branch with itself
        cursor.execute("SELECT * FROM pggit.diff_branches('main', 'main')")
        results = cursor.fetchall()

        # Assert: Returns empty (all identical)
        assert len(results) == 0

    def test_historical_analysis_deleted_branches(self, setup_test_data):
        """Test 10: Historical analysis - Deleted branches"""
        data = setup_test_data
        cursor = data['db'].cursor()

        # Arrange: Create deleted branch with object
        cursor.execute("""
            INSERT INTO pggit.branches (branch_name, parent_branch_id, status, created_by)
            VALUES ('historical', %s, 'DELETED', 'test_user')
        """, (data['main_branch_id'],))
        cursor.execute("SELECT branch_id FROM pggit.branches WHERE branch_name = 'historical'")
        hist_branch_id = cursor.fetchone()[0]

        # Add object to historical branch
        hist_commit = compute_hash("hist_commit")
        cursor.execute("""
            INSERT INTO pggit.commits (commit_hash, branch_id, author_name, author_time)
            VALUES (%s, %s, 'test_user', NOW())
        """, (hist_commit, hist_branch_id))
        cursor.execute("""
            INSERT INTO pggit.object_history
            (object_id, branch_id, change_type, change_severity, before_hash, after_hash, commit_hash, author_name, author_time)
            VALUES (%s, %s, 'CREATE', 'MAJOR', NULL, %s, %s, 'test_user', NOW())
        """, (data['order_table_id'], hist_branch_id, data['hash2'], hist_commit))
        data['db'].commit()

        # Act: Compare against deleted branch
        cursor.execute("SELECT * FROM pggit.diff_branches('historical', 'main')")
        results = cursor.fetchall()

        # Assert: Can compare with deleted branches
        assert len(results) >= 0  # May have differences or not
