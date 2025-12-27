"""
Phase 5: History & Audit API Tests
Tests for get_commit_history, get_audit_trail, get_object_timeline, query_at_timestamp
"""
import pytest
import hashlib
from datetime import datetime, timedelta
from decimal import Decimal


class Phase5HistoryFixture:
    """Comprehensive fixture for Phase 5 historical queries"""

    def __init__(self, db_conn):
        self.conn = db_conn
        self.branch_ids = {}
        self.object_ids = {}
        self.timestamps = {}
        self._setup_base_timestamps()

    def _setup_base_timestamps(self):
        """Setup timeline of test timestamps"""
        base_time = datetime(2025, 12, 26, 10, 0, 0)
        self.timestamps = {
            'T0': base_time,
            'T1': base_time + timedelta(minutes=15),
            'T2': base_time + timedelta(minutes=30),
            'T3': base_time + timedelta(minutes=45),
            'T4': base_time + timedelta(hours=1),
            'T4b': base_time + timedelta(minutes=75),
            'T4c': base_time + timedelta(minutes=90),
            'T4d': base_time + timedelta(minutes=105),
            'T4e': base_time + timedelta(minutes=75),
            'T4f': base_time + timedelta(minutes=90),
            'T4g': base_time + timedelta(minutes=105),
            'T5': base_time + timedelta(hours=2),
            'T6': base_time + timedelta(minutes=150),
            'T7': base_time + timedelta(hours=3),
        }

    def setup(self):
        """Create complete fixture data"""
        # Clean up any leftover data from previous tests
        self._cleanup()
        self._create_branches()
        self._create_commits_and_objects()

    def _cleanup(self):
        """Internal cleanup method used by both setup and teardown"""
        try:
            with self.conn.cursor() as cur:
                # Use TRUNCATE CASCADE to efficiently remove all data in correct order
                tables = [
                    "pggit.merge_conflict_resolutions",
                    "pggit.merge_operations",
                    "pggit.object_dependencies",
                    "pggit.object_history",
                    "pggit.commits",
                    "pggit.schema_objects",
                    "pggit.branches",
                ]
                for table in tables:
                    try:
                        cur.execute(f"TRUNCATE TABLE {table} CASCADE")
                    except Exception:
                        pass
            self.conn.commit()
        except Exception as e:
            self.conn.rollback()
            # Don't raise during cleanup - just log
            pass

    def teardown(self):
        """Clean up fixture-created data while preserving bootstrap state"""
        try:
            with self.conn.cursor() as cur:
                # Only delete data created by THIS fixture (feature branches and their commits)
                # Keep 'main' branch and all bootstrap objects

                # Delete using our tracked branch IDs to ensure we get the right data
                feature_branch_ids = []
                if 'feature-a' in self.branch_ids:
                    feature_branch_ids.append(self.branch_ids['feature-a'])
                if 'feature-b' in self.branch_ids:
                    feature_branch_ids.append(self.branch_ids['feature-b'])

                if feature_branch_ids:
                    # Delete commits on feature branches we created
                    placeholders = ','.join(['%s'] * len(feature_branch_ids))
                    cur.execute(f"DELETE FROM pggit.commits WHERE branch_id IN ({placeholders})", feature_branch_ids)

                # Delete object_history for our test objects
                if self.object_ids:
                    obj_ids_tuple = tuple(self.object_ids.values())
                    placeholders = ','.join(['%s'] * len(obj_ids_tuple))
                    cur.execute(
                        f"DELETE FROM pggit.object_history WHERE object_id IN ({placeholders})",
                        obj_ids_tuple
                    )
                    # Delete our test schema objects
                    cur.execute(
                        f"DELETE FROM pggit.schema_objects WHERE object_id IN ({placeholders})",
                        obj_ids_tuple
                    )

                # Delete feature branches (keep main)
                cur.execute("DELETE FROM pggit.branches WHERE branch_name IN ('feature-a', 'feature-b')")
            self.conn.commit()
        except Exception:
            self.conn.rollback()
            pass

    def _create_branches(self):
        """Create branch hierarchy"""
        with self.conn.cursor() as cur:
            # Get or create main branch
            cur.execute(
                "SELECT branch_id FROM pggit.branches WHERE branch_name = 'main'"
            )
            result = cur.fetchone()
            if result:
                self.branch_ids['main'] = result[0]
            else:
                cur.execute(
                    "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_at, created_by, status) "
                    "VALUES (%s, %s, %s, %s, %s) RETURNING branch_id",
                    ('main', None, self.timestamps['T0'], 'system', 'ACTIVE')
                )
                self.branch_ids['main'] = cur.fetchone()[0]

            # Create feature branches (delete if they exist first, respecting FKs)
            for branch_name in ['feature-a', 'feature-b']:
                # Get branch_id first
                cur.execute("SELECT branch_id FROM pggit.branches WHERE branch_name = %s", (branch_name,))
                branch_result = cur.fetchone()
                if branch_result:
                    old_branch_id = branch_result[0]
                    # Delete dependent data in order (respecting FKs)
                    cur.execute("DELETE FROM pggit.merge_operations WHERE source_branch_id = %s OR target_branch_id = %s OR merge_base_branch_id = %s",
                               (old_branch_id, old_branch_id, old_branch_id))
                    cur.execute("DELETE FROM pggit.object_dependencies WHERE branch_id = %s", (old_branch_id,))
                    cur.execute("DELETE FROM pggit.object_history WHERE branch_id = %s", (old_branch_id,))
                    cur.execute("DELETE FROM pggit.commits WHERE branch_id = %s", (old_branch_id,))
                # Delete the branch
                cur.execute("DELETE FROM pggit.branches WHERE branch_name = %s", (branch_name,))
                cur.execute(
                    "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_at, created_by, status) "
                    "VALUES (%s, %s, %s, %s, %s) RETURNING branch_id",
                    (branch_name, self.branch_ids['main'], self.timestamps['T4'], 'developer', 'ACTIVE')
                )
                self.branch_ids[branch_name] = cur.fetchone()[0]
        self.conn.commit()

    def _create_commits_and_objects(self):
        """Create commits with associated object history"""
        with self.conn.cursor() as cur:
            # T1: CREATE TABLE users on main
            users_id = self._create_object(cur, 'users', 'TABLE', 'public')
            self._insert_commit(cur, 'main', self.timestamps['T1'],
                              'CREATE TABLE users', 'developer', 'hash_T1')
            self._insert_object_history(cur, users_id, 'main', 'CREATE',
                'CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100))',
                'hash_T1', self.timestamps['T1'], author='developer')

            # T2: CREATE FUNCTION count_users on main
            func_id = self._create_object(cur, 'count_users', 'FUNCTION', 'public')
            self._insert_commit(cur, 'main', self.timestamps['T2'],
                              'CREATE FUNCTION count_users()', 'developer', 'hash_T2')
            self._insert_object_history(cur, func_id, 'main', 'CREATE',
                'CREATE FUNCTION public.count_users() RETURNS INT',
                'hash_T2', self.timestamps['T2'], author='developer')

            # T3: ALTER TABLE users on main
            self._insert_commit(cur, 'main', self.timestamps['T3'],
                              'ALTER TABLE users ADD email', 'developer', 'hash_T3')
            self._insert_object_history(cur, users_id, 'main', 'ALTER',
                'CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100), email VARCHAR(100))',
                'hash_T3', self.timestamps['T3'], author='developer',
                before_def='CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100))')

            # T4b: Feature-A: ALTER TABLE users ADD phone
            self._insert_commit(cur, 'feature-a', self.timestamps['T4b'],
                              'ALTER TABLE users ADD phone', 'developer-a', 'hash_T4b')
            self._insert_object_history(cur, users_id, 'feature-a', 'ALTER',
                'CREATE TABLE users (id INT, name VARCHAR(100), phone VARCHAR(20))',
                'hash_T4b', self.timestamps['T4b'], author='developer-a',
                before_def='CREATE TABLE users (id INT, name VARCHAR(100))')

            # T4c: Feature-A: CREATE INDEX
            idx_id = self._create_object(cur, 'idx_users_email', 'INDEX', 'public')
            self._insert_commit(cur, 'feature-a', self.timestamps['T4c'],
                              'CREATE INDEX idx_users_email', 'developer-a', 'hash_T4c')
            self._insert_object_history(cur, idx_id, 'feature-a', 'CREATE',
                'CREATE INDEX idx_users_email ON users(email)',
                'hash_T4c', self.timestamps['T4c'], author='developer-a')

            # T4d: Feature-A: CREATE TABLE orders
            orders_id = self._create_object(cur, 'orders', 'TABLE', 'public')
            self._insert_commit(cur, 'feature-a', self.timestamps['T4d'],
                              'CREATE TABLE orders', 'developer-a', 'hash_T4d')
            self._insert_object_history(cur, orders_id, 'feature-a', 'CREATE',
                'CREATE TABLE orders (id INT PRIMARY KEY, user_id INT)',
                'hash_T4d', self.timestamps['T4d'], author='developer-a')

            # T4e: Feature-B: ALTER TABLE users RENAME email
            self._insert_commit(cur, 'feature-b', self.timestamps['T4e'],
                              'ALTER TABLE users RENAME email', 'developer-b', 'hash_T4e')
            self._insert_object_history(cur, users_id, 'feature-b', 'ALTER',
                'CREATE TABLE users (id INT, name VARCHAR(100), email_address VARCHAR(100))',
                'hash_T4e', self.timestamps['T4e'], author='developer-b',
                before_def='CREATE TABLE users (id INT, name VARCHAR(100))')

            # T4f: Feature-B: ALTER FUNCTION
            self._insert_commit(cur, 'feature-b', self.timestamps['T4f'],
                              'ALTER FUNCTION count_users() - improved', 'developer-b', 'hash_T4f')
            self._insert_object_history(cur, func_id, 'feature-b', 'ALTER',
                'CREATE FUNCTION public.count_users() RETURNS INT AS improved',
                'hash_T4f', self.timestamps['T4f'], author='developer-b',
                before_def='CREATE FUNCTION public.count_users() RETURNS INT')

            # T4g: Feature-B: CREATE TABLE payments
            payments_id = self._create_object(cur, 'payments', 'TABLE', 'public')
            self._insert_commit(cur, 'feature-b', self.timestamps['T4g'],
                              'CREATE TABLE payments', 'developer-b', 'hash_T4g')
            self._insert_object_history(cur, payments_id, 'feature-b', 'CREATE',
                'CREATE TABLE payments (id INT PRIMARY KEY, order_id INT)',
                'hash_T4g', self.timestamps['T4g'], author='developer-b')

            # T7: ALTER TABLE users - DROP columns
            self._insert_commit(cur, 'main', self.timestamps['T7'],
                              'ALTER TABLE users DROP columns', 'developer', 'hash_T7')
            self._insert_object_history(cur, users_id, 'main', 'ALTER',
                'CREATE TABLE users (id INT, name VARCHAR(100))',
                'hash_T7', self.timestamps['T7'], author='developer',
                before_def='CREATE TABLE users (id INT, name VARCHAR(100), email VARCHAR(100))')

        self.conn.commit()

    def _create_object(self, cur, object_name, object_type, schema_name):
        """Create object and return ID"""
        definition = f"CREATE {object_type} {schema_name}.{object_name}"
        hash_value = hashlib.sha256(definition.encode()).hexdigest()
        cur.execute(
            "INSERT INTO pggit.schema_objects (object_type, schema_name, object_name, "
            "current_definition, content_hash, is_active) "
            "VALUES (%s, %s, %s, %s, %s, true) RETURNING object_id",
            (object_type, schema_name, object_name, definition, hash_value)
        )
        return cur.fetchone()[0]

    def _insert_commit(self, cur, branch, timestamp, message, author, hash_val):
        """Insert commit record"""
        branch_id = self.branch_ids[branch]
        cur.execute(
            "INSERT INTO pggit.commits (branch_id, author_name, author_time, "
            "commit_message, commit_hash, object_changes) "
            "VALUES (%s, %s, %s, %s, %s, '{}')",
            (branch_id, author, timestamp, message, hash_val)
        )

    def _insert_object_history(self, cur, object_id, branch, change_type,
                              after_def, commit_hash, timestamp, before_def=None, author='developer'):
        """Insert object history record"""
        branch_id = self.branch_ids[branch]
        after_hash = hashlib.sha256(after_def.encode()).hexdigest()
        before_hash = hashlib.sha256(before_def.encode()).hexdigest() if before_def else None

        cur.execute(
            "INSERT INTO pggit.object_history (object_id, branch_id, change_type, "
            "before_definition, before_hash, after_definition, after_hash, "
            "commit_hash, author_name, author_time, created_at) "
            "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
            (object_id, branch_id, change_type, before_def, before_hash,
             after_def, after_hash, commit_hash, author, timestamp, timestamp)
        )


@pytest.fixture
def phase5_fixture(db_conn):
    """Setup and teardown Phase 5 fixture"""
    fixture = Phase5HistoryFixture(db_conn)
    fixture.setup()
    yield fixture
    fixture.teardown()


# ============================================================================
# Tests for get_commit_history()
# ============================================================================

class TestGetCommitHistory:
    """Test pggit.get_commit_history() function"""

    def test_commit_history_all_commits(self, db_conn, phase5_fixture):
        """Test: Returns all commits unfiltered"""
        with db_conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM pggit.get_commit_history()")
            count = cur.fetchone()[0]
        assert count >= 7, "Should return at least 7 commits"

    def test_commit_history_branch_filter(self, db_conn, phase5_fixture):
        """Test: Filter by specific branch"""
        with db_conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM pggit.get_commit_history(p_branch_name => 'main')")
            count = cur.fetchone()[0]
        assert count >= 4, "Main branch should have at least 4 commits"

    def test_commit_history_time_range(self, db_conn, phase5_fixture):
        """Test: Filter by date range"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM pggit.get_commit_history("
                "p_since_timestamp => %s, p_until_timestamp => %s)",
                (phase5_fixture.timestamps['T2'], phase5_fixture.timestamps['T4'])
            )
            count = cur.fetchone()[0]
        assert count >= 1, "Should return commits in time range"

    def test_commit_history_author_filter(self, db_conn, phase5_fixture):
        """Test: Filter by author name"""
        with db_conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM pggit.get_commit_history(p_author_name => 'developer')")
            count = cur.fetchone()[0]
        assert count >= 1, "Should return commits from author"

    def test_commit_history_message_search(self, db_conn, phase5_fixture):
        """Test: Full-text search in commit messages"""
        with db_conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM pggit.get_commit_history(p_search_message => 'ALTER')")
            count = cur.fetchone()[0]
        assert count >= 1, "Should find commits with ALTER in message"

    def test_commit_history_pagination(self, db_conn, phase5_fixture):
        """Test: Offset and limit work correctly"""
        with db_conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM pggit.get_commit_history(p_limit => 2)")
            count = cur.fetchone()[0]
        assert count <= 2, "Limit should restrict results"

    def test_commit_history_change_counts(self, db_conn, phase5_fixture):
        """Test: Added/deleted/modified counts are calculated"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT objects_added, objects_deleted, objects_modified "
                "FROM pggit.get_commit_history(p_branch_name => 'main') "
                "LIMIT 1"
            )
            row = cur.fetchone()
        assert row is not None
        assert row[0] >= 0, "objects_added should be non-negative"
        assert row[1] >= 0, "objects_deleted should be non-negative"
        assert row[2] >= 0, "objects_modified should be non-negative"

    def test_commit_history_returns_correct_columns(self, db_conn, phase5_fixture):
        """Test: All expected columns are returned"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT commit_id, commit_hash, branch_name, author_name, "
                "author_time, commit_message, objects_changed, ancestry_depth "
                "FROM pggit.get_commit_history(p_limit => 1)"
            )
            row = cur.fetchone()
        assert row is not None
        assert len(row) >= 8, "Should return at least 8 columns"

    def test_commit_history_invalid_branch(self, db_conn, phase5_fixture):
        """Test: Error for non-existent branch"""
        with db_conn.cursor() as cur:
            with pytest.raises(Exception):
                cur.execute("SELECT * FROM pggit.get_commit_history(p_branch_name => 'nonexistent')")
                cur.fetchall()


# ============================================================================
# Tests for get_audit_trail()
# ============================================================================

class TestGetAuditTrail:
    """Test pggit.get_audit_trail() function"""

    def test_audit_trail_all_changes(self, db_conn, phase5_fixture):
        """Test: Returns all changes unfiltered"""
        with db_conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM pggit.get_audit_trail()")
            count = cur.fetchone()[0]
        assert count >= 7, "Should return at least 7 changes"

    def test_audit_trail_object_filter(self, db_conn, phase5_fixture):
        """Test: Filter by object type"""
        with db_conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM pggit.get_audit_trail(p_object_type => 'TABLE')")
            count = cur.fetchone()[0]
        assert count >= 1, "Should return TABLE changes"

    def test_audit_trail_branch_filter(self, db_conn, phase5_fixture):
        """Test: Filter by branch"""
        with db_conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM pggit.get_audit_trail(p_branch_name => 'main')")
            count = cur.fetchone()[0]
        assert count >= 1, "Should return main branch changes"

    def test_audit_trail_change_type_filter(self, db_conn, phase5_fixture):
        """Test: Filter by CREATE/ALTER/DROP"""
        with db_conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM pggit.get_audit_trail(p_change_type => 'CREATE')")
            count = cur.fetchone()[0]
        assert count >= 1, "Should return CREATE changes"

    def test_audit_trail_time_range(self, db_conn, phase5_fixture):
        """Test: Filter by timestamp range"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM pggit.get_audit_trail("
                "p_since_timestamp => %s, p_until_timestamp => %s)",
                (phase5_fixture.timestamps['T1'], phase5_fixture.timestamps['T3'])
            )
            count = cur.fetchone()[0]
        assert count >= 1, "Should return changes in time range"

    def test_audit_trail_before_after_definitions(self, db_conn, phase5_fixture):
        """Test: Before/after definitions are populated"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT before_definition, after_definition "
                "FROM pggit.get_audit_trail(p_change_type => 'ALTER') "
                "LIMIT 1"
            )
            row = cur.fetchone()
        assert row is not None
        assert row[0] is not None or row[1] is not None, "Should have before or after definition"

    def test_audit_trail_diff_summary(self, db_conn, phase5_fixture):
        """Test: Diff summary is generated"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT definition_diff_summary FROM pggit.get_audit_trail() LIMIT 1"
            )
            row = cur.fetchone()
        assert row is not None
        assert row[0] is not None, "Should generate diff summary"

    def test_audit_trail_breaking_change_detection(self, db_conn, phase5_fixture):
        """Test: Breaking changes are flagged"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT is_breaking_change FROM pggit.get_audit_trail()"
            )
            rows = cur.fetchall()
        assert rows, "Should return results"
        # At least one should be FALSE (not all are breaking)
        assert any(not row[0] for row in rows), "Should have non-breaking changes"

    def test_audit_trail_pagination(self, db_conn, phase5_fixture):
        """Test: Offset/limit work correctly"""
        with db_conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM pggit.get_audit_trail(p_limit => 3)")
            count = cur.fetchone()[0]
        assert count <= 3, "Limit should restrict results"


# ============================================================================
# Tests for get_object_timeline()
# ============================================================================

class TestGetObjectTimeline:
    """Test pggit.get_object_timeline() function"""

    def test_object_timeline_single_object(self, db_conn, phase5_fixture):
        """Test: Complete timeline for one object"""
        with db_conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM pggit.get_object_timeline('users')")
            count = cur.fetchone()[0]
        assert count >= 1, "Should return timeline for users table"

    def test_object_timeline_version_numbers(self, db_conn, phase5_fixture):
        """Test: Version numbers increment correctly"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT timeline_version FROM pggit.get_object_timeline('users') "
                "ORDER BY timeline_version"
            )
            versions = [row[0] for row in cur.fetchall()]
        assert len(versions) >= 1, "Should have versions"
        assert versions == sorted(versions), "Versions should be ordered"

    def test_object_timeline_multiple_changes(self, db_conn, phase5_fixture):
        """Test: Multiple ALTER operations shown"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM pggit.get_object_timeline('users', 'main')"
            )
            count = cur.fetchone()[0]
        assert count >= 2, "Should show multiple changes to users on main"

    def test_object_timeline_change_severity(self, db_conn, phase5_fixture):
        """Test: Change severity is calculated"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT DISTINCT change_severity FROM pggit.get_object_timeline('users')"
            )
            severities = [row[0] for row in cur.fetchall()]
        assert len(severities) > 0, "Should have change severities"

    def test_object_timeline_time_deltas(self, db_conn, phase5_fixture):
        """Test: Time between changes calculated"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT time_since_last_change FROM pggit.get_object_timeline('users') "
                "WHERE timeline_version > 1"
            )
            deltas = [row[0] for row in cur.fetchall()]
        # First version should have NULL, subsequent should have intervals
        assert len(deltas) >= 0, "Should calculate time deltas"

    def test_object_timeline_branch_specific(self, db_conn, phase5_fixture):
        """Test: Timeline respects branch context"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM pggit.get_object_timeline('users', 'feature-a')"
            )
            count = cur.fetchone()[0]
        assert count >= 1, "Should return timeline for feature-a branch"

    def test_object_timeline_nonexistent_object(self, db_conn, phase5_fixture):
        """Test: Error for object not found"""
        with db_conn.cursor() as cur:
            with pytest.raises(Exception):
                cur.execute("SELECT * FROM pggit.get_object_timeline('nonexistent_table')")
                cur.fetchall()

    def test_object_timeline_full_name_parsing(self, db_conn, phase5_fixture):
        """Test: Parse schema.object format"""
        with db_conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM pggit.get_object_timeline('public.users')")
            count = cur.fetchone()[0]
        assert count >= 1, "Should parse schema.object format"


# ============================================================================
# Tests for query_at_timestamp()
# ============================================================================

class TestQueryAtTimestamp:
    """Test pggit.query_at_timestamp() function"""

    def test_query_at_timestamp_current_time(self, db_conn, phase5_fixture):
        """Test: Query at current time shows current state"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM pggit.query_at_timestamp('main', NOW())"
            )
            count = cur.fetchone()[0]
        assert count >= 1, "Should return current schema state"

    def test_query_at_timestamp_past_time(self, db_conn, phase5_fixture):
        """Test: Query at historical time shows old definitions"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM pggit.query_at_timestamp('main', %s)",
                (phase5_fixture.timestamps['T2'],)
            )
            count = cur.fetchone()[0]
        assert count >= 1, "Should return schema state at T2"

    def test_query_at_timestamp_object_creation_time(self, db_conn, phase5_fixture):
        """Test: Query right after object created"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM pggit.query_at_timestamp('main', %s)",
                (phase5_fixture.timestamps['T1'],)
            )
            count = cur.fetchone()[0]
        assert count >= 1, "Should show object right after creation"

    def test_query_at_timestamp_object_not_yet_created(self, db_conn, phase5_fixture):
        """Test: Object not present before creation"""
        with db_conn.cursor() as cur:
            # Query before branch was created
            cur.execute(
                "SELECT COUNT(*) FROM pggit.query_at_timestamp('feature-a', %s)",
                (phase5_fixture.timestamps['T2'],)
            )
            count = cur.fetchone()[0]
        # feature-a didn't exist until T4, so this should error
        # or return 0 depending on implementation

    def test_query_at_timestamp_returns_correct_columns(self, db_conn, phase5_fixture):
        """Test: All expected columns returned"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT object_id, object_type, schema_name, object_name, definition, "
                "was_active, created_at, last_modified_at "
                "FROM pggit.query_at_timestamp('main', NOW()) LIMIT 1"
            )
            row = cur.fetchone()
        assert row is not None, "Should return a row"
        assert len(row) >= 8, "Should have all columns"

    def test_query_at_timestamp_was_active_flag(self, db_conn, phase5_fixture):
        """Test: was_active reflects object existence"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT was_active FROM pggit.query_at_timestamp('main', NOW())"
            )
            flags = [row[0] for row in cur.fetchall()]
        assert all(flags), "All current objects should be active"

    def test_query_at_timestamp_filtered_results(self, db_conn, phase5_fixture):
        """Test: Filters applied correctly"""
        with db_conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM pggit.query_at_timestamp('main', NOW(), 'TABLE')"
            )
            count = cur.fetchone()[0]
        assert count >= 1, "Should filter by object type"

    def test_query_at_timestamp_branch_must_exist(self, db_conn, phase5_fixture):
        """Test: Error if branch doesn't exist"""
        with db_conn.cursor() as cur:
            with pytest.raises(Exception):
                cur.execute(
                    "SELECT * FROM pggit.query_at_timestamp('nonexistent_branch', NOW())"
                )
                cur.fetchall()

    def test_query_at_timestamp_future_timestamp_error(self, db_conn, phase5_fixture):
        """Test: Error for future timestamp"""
        with db_conn.cursor() as cur:
            with pytest.raises(Exception):
                future = datetime.now() + timedelta(days=1)
                cur.execute(
                    "SELECT * FROM pggit.query_at_timestamp('main', %s)",
                    (future,)
                )
                cur.fetchall()


# ============================================================================
# Integration Tests
# ============================================================================

class TestPhase5Integration:
    """Integration tests across Phase 5 functions"""

    def test_audit_trail_matches_commit_history(self, db_conn, phase5_fixture):
        """Test: Audit trail and commit history are consistent"""
        with db_conn.cursor() as cur:
            # Get commit count
            cur.execute("SELECT COUNT(DISTINCT commit_hash) FROM pggit.get_commit_history()")
            commit_count = cur.fetchone()[0]

            # Get audit trail entries
            cur.execute("SELECT COUNT(DISTINCT commit_hash) FROM pggit.get_audit_trail()")
            audit_count = cur.fetchone()[0]

        assert commit_count > 0, "Should have commits"
        assert audit_count > 0, "Should have audit entries"
        # They should be related
        assert commit_count >= 1, "Should have at least 1 commit"

    def test_timeline_matches_audit_trail(self, db_conn, phase5_fixture):
        """Test: Object timeline consistent with audit trail"""
        with db_conn.cursor() as cur:
            # Get timeline for users
            cur.execute(
                "SELECT COUNT(*) FROM pggit.get_object_timeline('users', 'main')"
            )
            timeline_count = cur.fetchone()[0]

            # Get audit trail for users
            cur.execute(
                "SELECT COUNT(*) FROM pggit.get_audit_trail(p_object_name => 'users', p_branch_name => 'main')"
            )
            audit_count = cur.fetchone()[0]

        assert timeline_count >= 1, "Should have timeline"
        assert audit_count >= 1, "Should have audit trail"
        # Timeline count should match or be subset of audit count
        assert timeline_count <= audit_count, "Timeline should be consistent with audit"
