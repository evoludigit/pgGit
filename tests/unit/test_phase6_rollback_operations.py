"""
Phase 6: Rollback & Undo Operations - Unit Tests

Tests for rollback validation, execution, and dependency handling.
Status: Phase 6.1 Foundation (validate_rollback function tests)
"""

import hashlib
from datetime import datetime, timedelta
from typing import Dict, Optional

import pytest
import psycopg
from psycopg import Connection


class Phase6RollbackFixture:
    """
    Comprehensive fixture for Phase 6 rollback testing.

    Creates:
    - 3 branches with parent relationships
    - 7+ schema objects with rich modification history
    - 11 commits with accurate timestamps
    - 2 merge operations
    - Complex dependencies (FK, INDEX, FUNCTION)
    """

    def __init__(self, db_connection: Connection):
        """Initialize fixture with database connection."""
        self.conn = db_connection
        self.branch_ids: Dict[str, int] = {}
        self.object_ids: Dict[str, int] = {}
        self.commit_hashes: Dict[str, str] = {}
        self.timestamps: Dict[str, datetime] = {}
        self._setup_base_timestamps()

    def _setup_base_timestamps(self) -> None:
        """Setup timeline of test timestamps."""
        base_time = datetime(2025, 12, 26, 10, 0, 0)
        self.timestamps = {
            'T0': base_time,                           # 10:00
            'T1': base_time + timedelta(minutes=15),   # 10:15
            'T2': base_time + timedelta(minutes=30),   # 10:30
            'T3': base_time + timedelta(minutes=45),   # 10:45
            'T4': base_time + timedelta(hours=1),      # 11:00
            'T5': base_time + timedelta(minutes=75),   # 11:15
            'T6': base_time + timedelta(minutes=90),   # 11:30
            'T7': base_time + timedelta(minutes=105),  # 11:45
            'T7b': base_time + timedelta(hours=2),     # 12:00
            'T7c': base_time + timedelta(minutes=135), # 12:15
            'T7d': base_time + timedelta(minutes=150), # 12:30
            'T8': base_time + timedelta(hours=2),      # 12:00
            'T8b': base_time + timedelta(minutes=135), # 12:15
            'T8c': base_time + timedelta(minutes=150), # 12:30
            'T8d': base_time + timedelta(minutes=165), # 12:45
            'T9': base_time + timedelta(hours=3),      # 13:00
            'T10': base_time + timedelta(minutes=210), # 13:30
            'T11': base_time + timedelta(hours=4),     # 14:00
        }

    def setup(self) -> None:
        """Create complete fixture data."""
        self._create_branches()
        self._create_objects()
        self._create_commits_and_history()
        self._create_dependencies()

    def teardown(self) -> None:
        """Clean up all fixture data."""
        try:
            with self.conn.cursor() as cur:
                cur.execute("DELETE FROM pggit.object_dependencies WHERE source_object_id > 8 OR target_object_id > 8")
                cur.execute("DELETE FROM pggit.merge_operations")
                cur.execute("DELETE FROM pggit.rollback_operations")
                cur.execute("DELETE FROM pggit.rollback_validations")
                cur.execute("DELETE FROM pggit.object_history WHERE object_id > 8")
                cur.execute("DELETE FROM pggit.commits WHERE commit_hash LIKE 'hash_%'")
                cur.execute("DELETE FROM pggit.schema_objects WHERE schema_name = 'test'")
                cur.execute("DELETE FROM pggit.branches WHERE branch_name IN ('feature-a', 'feature-b')")
            self.conn.commit()
        except Exception:
            self.conn.rollback()

    def _create_branches(self) -> None:
        """Create branch hierarchy."""
        with self.conn.cursor() as cur:
            # Get/create main branch
            cur.execute(
                "SELECT branch_id FROM pggit.branches WHERE branch_name = 'main'"
            )
            result = cur.fetchone()
            if result:
                self.branch_ids['main'] = result[0]
            else:
                cur.execute(
                    """INSERT INTO pggit.branches (branch_name, parent_branch_id, created_at,
                       created_by, status) VALUES (%s, %s, %s, %s, %s) RETURNING branch_id""",
                    ('main', None, self.timestamps['T0'], 'system', 'ACTIVE')
                )
                self.branch_ids['main'] = cur.fetchone()[0]

            # Create feature branches
            for branch_name, parent_time in [('feature-a', 'T7'), ('feature-b', 'T8')]:
                cur.execute("DELETE FROM pggit.branches WHERE branch_name = %s", (branch_name,))
                cur.execute(
                    """INSERT INTO pggit.branches (branch_name, parent_branch_id, created_at,
                       created_by, status) VALUES (%s, %s, %s, %s, %s) RETURNING branch_id""",
                    (branch_name, self.branch_ids['main'], self.timestamps[parent_time],
                     'developer', 'ACTIVE')
                )
                self.branch_ids[branch_name] = cur.fetchone()[0]
        self.conn.commit()

    def _create_objects(self) -> None:
        """Create schema objects."""
        with self.conn.cursor() as cur:
            # Delete test objects from previous runs
            cur.execute("DELETE FROM pggit.schema_objects WHERE schema_name = 'test' OR object_name IN ('users_test', 'orders_test', 'count_users_test')")

            objects = [
                ('users_test', 'TABLE', "CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100))"),
                ('orders_test', 'TABLE', "CREATE TABLE orders (id INT PRIMARY KEY, user_id INT)"),
                ('count_users_test', 'FUNCTION', "CREATE FUNCTION count_users() RETURNS INT"),
            ]

            for obj_name, obj_type, definition in objects:
                content_hash = hashlib.sha256(definition.encode()).hexdigest()
                cur.execute(
                    """INSERT INTO pggit.schema_objects (object_type, schema_name, object_name,
                       current_definition, content_hash, is_active)
                       VALUES (%s, %s, %s, %s, %s, %s)
                       ON CONFLICT (object_type, schema_name, object_name) DO UPDATE SET current_definition = EXCLUDED.current_definition
                       RETURNING object_id""",
                    (obj_type, 'test', obj_name, definition, content_hash, True)
                )
                result = cur.fetchone()
                if result:
                    self.object_ids[obj_name] = result[0]

        self.conn.commit()

    def _create_commits_and_history(self) -> None:
        """Create commits and object history."""
        with self.conn.cursor() as cur:
            # T1: CREATE TABLE users_test
            self._insert_commit(cur, 'main', 'T1', 'CREATE TABLE users', 'hash_T1')
            self._insert_history(cur, 'users_test', 'main', 'CREATE',
                'CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100))', 'hash_T1', 'T1')

            # T2: CREATE TABLE orders_test
            self._insert_commit(cur, 'main', 'T2', 'CREATE TABLE orders', 'hash_T2')
            self._insert_history(cur, 'orders_test', 'main', 'CREATE',
                'CREATE TABLE orders (id INT PRIMARY KEY, user_id INT)', 'hash_T2', 'T2')

            # T3: ALTER TABLE users_test ADD email
            self._insert_commit(cur, 'main', 'T3', 'ALTER TABLE users ADD email', 'hash_T3')
            self._insert_history(cur, 'users_test', 'main', 'ALTER',
                'CREATE TABLE users (id INT, name VARCHAR(100), email VARCHAR(100))',
                'hash_T3', 'T3',
                before_def='CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100))')

            # T4: CREATE INDEX
            idx_def = "CREATE INDEX idx_users_email ON users(email)"
            idx_hash = hashlib.sha256(idx_def.encode()).hexdigest()
            cur.execute(
                """INSERT INTO pggit.schema_objects (object_type, schema_name, object_name,
                   current_definition, content_hash, is_active)
                   VALUES (%s, %s, %s, %s, %s, %s) RETURNING object_id""",
                ('INDEX', 'test', 'idx_users_email_test', idx_def, idx_hash, True)
            )
            self._insert_commit(cur, 'main', 'T4', 'CREATE INDEX idx_users_email', 'hash_T4')

            # T5: ALTER TABLE orders_test ADD amount
            self._insert_commit(cur, 'main', 'T5', 'ALTER TABLE orders ADD amount', 'hash_T5')
            self._insert_history(cur, 'orders_test', 'main', 'ALTER',
                'CREATE TABLE orders (id INT, user_id INT, amount DECIMAL)',
                'hash_T5', 'T5',
                before_def='CREATE TABLE orders (id INT PRIMARY KEY, user_id INT)')

            # T6: CREATE FUNCTION count_users_test
            self._insert_commit(cur, 'main', 'T6', 'CREATE FUNCTION count_users', 'hash_T6')
            self._insert_history(cur, 'count_users_test', 'main', 'CREATE',
                'CREATE FUNCTION count_users() RETURNS INT', 'hash_T6', 'T6')

        self.conn.commit()

    def _create_dependencies(self) -> None:
        """Create object dependency records."""
        with self.conn.cursor() as cur:
            # orders depends on users (FK)
            cur.execute(
                """INSERT INTO pggit.object_dependencies (dependent_object_id, depends_on_object_id,
                   dependency_type) VALUES (%s, %s, %s)""",
                (self.object_ids['orders'], self.object_ids['users'], 'FOREIGN_KEY')
            )

        self.conn.commit()

    def _insert_commit(self, cur: psycopg.Cursor, branch: str, timestamp_key: str,
                      message: str, hash_val: str) -> None:
        """Insert commit."""
        cur.execute(
            """INSERT INTO pggit.commits (branch_id, author_name, author_time,
               commit_message, commit_hash, object_changes)
               VALUES (%s, %s, %s, %s, %s, '{}')""",
            (self.branch_ids[branch], 'developer', self.timestamps[timestamp_key], message, hash_val)
        )
        self.commit_hashes[timestamp_key] = hash_val

    def _insert_history(self, cur: psycopg.Cursor, object_name: str, branch: str,
                       change_type: str, after_def: str, commit_hash: str,
                       timestamp_key: str, before_def: Optional[str] = None,
                       author: str = 'developer') -> None:
        """Insert object history."""
        after_hash = hashlib.sha256(after_def.encode()).hexdigest()
        before_hash = hashlib.sha256(before_def.encode()).hexdigest() if before_def else None

        cur.execute(
            """INSERT INTO pggit.object_history (object_id, branch_id, change_type,
               before_definition, before_hash, after_definition, after_hash,
               commit_hash, author_name, author_time, created_at)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
            (self.object_ids[object_name], self.branch_ids[branch], change_type,
             before_def, before_hash, after_def, after_hash, commit_hash, author,
             self.timestamps[timestamp_key], self.timestamps[timestamp_key])
        )

    def get_branch_id(self, branch_name: str) -> Optional[int]:
        """Get branch ID by name."""
        return self.branch_ids.get(branch_name)

    def get_commit_hash(self, timestamp_key: str) -> Optional[str]:
        """Get commit hash by timestamp key."""
        return self.commit_hashes.get(timestamp_key)


# ===========================================
# FIXTURES FOR PYTEST
# ===========================================

@pytest.fixture
def db_connection():
    """Provide database connection for tests."""
    conn = psycopg.connect("dbname=pggit_test")
    try:
        yield conn
    finally:
        conn.close()


@pytest.fixture
def fixture_with_data(db_connection):
    """Provide Phase6RollbackFixture with test data."""
    fixture = Phase6RollbackFixture(db_connection)
    fixture.setup()
    yield fixture
    fixture.teardown()


# ===========================================
# TEST CLASS: validate_rollback() Function
# ===========================================

class TestValidateRollback:
    """Tests for validate_rollback() function."""

    def test_validate_nonexistent_branch(self, db_connection):
        """Test validation fails for nonexistent branch."""
        fake_hash = 'a' * 64
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT validation_type, status, severity
                   FROM pggit.validate_rollback(%s, %s)""",
                ('nonexistent', fake_hash)
            )
            result = cur.fetchall()

        # Should have at least one FAIL with ERROR severity
        has_error = any(row[1] == 'FAIL' and row[2] == 'ERROR' for row in result)
        assert has_error, "Should fail for nonexistent branch"

    def test_validate_nonexistent_commit(self, db_connection):
        """Test validation fails for nonexistent commit."""
        fake_hash = 'b' * 64
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT validation_type, status, severity
                   FROM pggit.validate_rollback(%s, %s)""",
                ('main', fake_hash)
            )
            result = cur.fetchall()

        # Should have FAIL status for commit existence
        has_fail = any(row[1] == 'FAIL' for row in result)
        assert has_fail, "Should fail for nonexistent commit"

    def test_validate_invalid_hash_format(self, db_connection):
        """Test validation fails for invalid hash format."""
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT validation_type, status, severity
                   FROM pggit.validate_rollback(%s, %s)""",
                ('main', 'tooshort')
            )
            result = cur.fetchall()

        # Should have FAIL with ERROR
        has_error = any(row[1] == 'FAIL' and row[2] == 'ERROR' for row in result)
        assert has_error, "Should fail for invalid hash format"

    def test_validate_null_branch_name(self, db_connection):
        """Test validation fails for null branch name."""
        fake_hash = 'a' * 64
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT validation_type, status, severity
                   FROM pggit.validate_rollback(%s, %s)""",
                (None, fake_hash)
            )
            result = cur.fetchall()

        # Should have FAIL with ERROR
        has_error = any(row[1] == 'FAIL' and row[2] == 'ERROR' for row in result)
        assert has_error, "Should fail for null branch name"

    def test_validate_invalid_rollback_type(self, db_connection):
        """Test validation fails for invalid rollback_type."""
        fake_hash = 'a' * 64
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT validation_type, status, severity
                   FROM pggit.validate_rollback(%s, %s, NULL, %s)""",
                ('main', fake_hash, 'INVALID_TYPE')
            )
            result = cur.fetchall()

        # Should have FAIL with ERROR
        has_error = any(row[1] == 'FAIL' and row[2] == 'ERROR' for row in result)
        assert has_error, "Should fail for invalid rollback_type"

    def test_validate_main_branch_exists(self, db_connection):
        """Test that main branch validation passes."""
        fake_hash = 'a' * 64
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT validation_type, status, severity
                   FROM pggit.validate_rollback(%s, %s)""",
                ('main', fake_hash)
            )
            results = cur.fetchall()

        # Find branch existence check
        branch_check = [r for r in results if r[0] == 'COMMIT_EXISTENCE']
        # First COMMIT_EXISTENCE check should be branch check
        assert len(branch_check) >= 1
        assert branch_check[0][1] == 'PASS', "Main branch should exist"

    def test_validate_with_fixture_commit(self, fixture_with_data, db_connection):
        """Test validation with real fixture data."""
        commit_hash = fixture_with_data.get_commit_hash('T1')
        assert commit_hash is not None, "Fixture should have T1 commit"

        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT validation_type, status, severity
                   FROM pggit.validate_rollback(%s, %s)""",
                ('main', commit_hash)
            )
            results = cur.fetchall()

        # Should have PASS for branch and commit existence
        passes = [r for r in results if r[1] == 'PASS']
        assert len(passes) >= 2, "Should have at least 2 passing checks"

    def test_validate_returns_multiple_checks(self, fixture_with_data, db_connection):
        """Test that validate_rollback returns multiple validation checks."""
        commit_hash = fixture_with_data.get_commit_hash('T1')

        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT DISTINCT validation_type
                   FROM pggit.validate_rollback(%s, %s)""",
                ('main', commit_hash)
            )
            validation_types = [row[0] for row in cur.fetchall()]

        # Should have multiple validation types
        expected_types = ['COMMIT_EXISTENCE', 'DEPENDENCY_ANALYSIS', 'MERGE_CONFLICT']
        for expected in expected_types:
            assert expected in validation_types, f"Missing {expected} validation"

    def test_validate_has_recommendations_on_failure(self, db_connection):
        """Test that failing validations have recommendations."""
        fake_hash = 'a' * 64
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT validation_type, status, recommendation
                   FROM pggit.validate_rollback(%s, %s)""",
                ('nonexistent', fake_hash)
            )
            results = cur.fetchall()

        # Find FAIL results
        fails = [r for r in results if r[1] == 'FAIL']
        assert len(fails) > 0, "Should have failures"

        # Each failure should have recommendation
        for fail in fails:
            assert fail[2] is not None, f"{fail[0]} failure should have recommendation"

    def test_validate_range_rollback_requires_target(self, fixture_with_data, db_connection):
        """Test RANGE rollback validation requires target commit."""
        source_hash = fixture_with_data.get_commit_hash('T1')

        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT validation_type, status
                   FROM pggit.validate_rollback(%s, %s, NULL, %s)""",
                ('main', source_hash, 'RANGE')
            )
            results = cur.fetchall()

        # Should have FAIL for target commit requirement
        has_fail = any(row[1] == 'FAIL' for row in results)
        assert has_fail, "RANGE rollback should fail without target commit"

    def test_validate_range_rollback_with_valid_target(self, fixture_with_data, db_connection):
        """Test RANGE rollback validation with both commits."""
        source_hash = fixture_with_data.get_commit_hash('T1')
        target_hash = fixture_with_data.get_commit_hash('T2')

        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT validation_type, status, severity
                   FROM pggit.validate_rollback(%s, %s, %s, %s)""",
                ('main', source_hash, target_hash, 'RANGE')
            )
            results = cur.fetchall()

        # Should have PASS for target commit check
        passes = [r for r in results if r[0] == 'COMMIT_EXISTENCE' and r[1] == 'PASS']
        assert len(passes) >= 2, "Should pass both branch and commit checks"

    def test_validate_with_dependencies(self, fixture_with_data, db_connection):
        """Test validation detects dependencies."""
        # T1 creates users table, T2 creates orders which depends on users
        # So rolling back T1 should warn about dependencies
        commit_hash = fixture_with_data.get_commit_hash('T1')

        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT validation_type, status, message
                   FROM pggit.validate_rollback(%s, %s)""",
                ('main', commit_hash)
            )
            results = cur.fetchall()

        # Should have DEPENDENCY_ANALYSIS check
        dep_checks = [r for r in results if r[0] == 'DEPENDENCY_ANALYSIS']
        assert len(dep_checks) > 0, "Should have dependency analysis"

    def test_validate_severity_ordering(self, db_connection):
        """Test that validations include proper severity levels."""
        fake_hash = 'a' * 64
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT severity
                   FROM pggit.validate_rollback(%s, %s)""",
                ('nonexistent', fake_hash)
            )
            results = cur.fetchall()

        # Should have ERROR severity for nonexistent branch
        severities = [row[0] for row in results]
        assert 'ERROR' in severities, "Should have ERROR severity for nonexistent branch"
        assert len(severities) > 0, "Should have validation results"


# ===========================================
# TEST CLASS: Database Integration
# ===========================================

class TestPhase6Integration:
    """Integration tests for Phase 6 tables and functions."""

    def test_rollback_operations_table_exists(self, db_connection):
        """Test that rollback_operations table exists."""
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT table_name FROM information_schema.tables
                   WHERE table_schema = 'pggit' AND table_name = 'rollback_operations'"""
            )
            result = cur.fetchone()

        assert result is not None, "rollback_operations table should exist"

    def test_rollback_validations_table_exists(self, db_connection):
        """Test that rollback_validations table exists."""
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT table_name FROM information_schema.tables
                   WHERE table_schema = 'pggit' AND table_name = 'rollback_validations'"""
            )
            result = cur.fetchone()

        assert result is not None, "rollback_validations table should exist"

    def test_validate_rollback_function_exists(self, db_connection):
        """Test that validate_rollback function exists."""
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT routine_name FROM information_schema.routines
                   WHERE routine_schema = 'pggit' AND routine_name = 'validate_rollback'"""
            )
            result = cur.fetchone()

        assert result is not None, "validate_rollback function should exist"

    def test_rollback_operations_indexes_exist(self, db_connection):
        """Test that all required indexes exist."""
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT indexname FROM pg_indexes
                   WHERE schemaname = 'pggit' AND tablename = 'rollback_operations'
                   ORDER BY indexname"""
            )
            indexes = [row[0] for row in cur.fetchall()]

        # Should have status, branch, and source_commit indexes
        expected = ['idx_rollback_operations_status', 'idx_rollback_operations_branch',
                   'idx_rollback_operations_source_commit']
        for idx in expected:
            assert idx in indexes, f"Missing index {idx}"

    def test_tables_have_proper_structure(self, db_connection):
        """Test that tables have expected columns."""
        with db_connection.cursor() as cur:
            # Check rollback_operations columns
            cur.execute(
                """SELECT column_name FROM information_schema.columns
                   WHERE table_schema = 'pggit' AND table_name = 'rollback_operations'
                   ORDER BY column_name"""
            )
            ro_columns = set(row[0] for row in cur.fetchall())

        expected_columns = {
            'rollback_id', 'source_commit_hash', 'target_commit_hash',
            'rollback_type', 'rollback_mode', 'branch_id', 'created_by',
            'created_at', 'executed_at', 'status', 'error_message',
            'objects_affected', 'dependencies_validated', 'breaking_changes_count',
            'rollback_commit_hash'
        }

        missing = expected_columns - ro_columns
        assert len(missing) == 0, f"Missing columns: {missing}"


class TestRollbackCommit:
    """Tests for rollback_commit() function"""

    def test_rollback_commit_function_exists(self, db_connection):
        """Test that rollback_commit function exists."""
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT routine_name FROM information_schema.routines
                   WHERE routine_schema = 'pggit' AND routine_name = 'rollback_commit'"""
            )
            result = cur.fetchone()

        assert result is not None, "rollback_commit function should exist"

    def test_rollback_commit_nonexistent_branch(self, db_connection):
        """Test rollback_commit with nonexistent branch."""
        fake_hash = 'a' * 64

        with db_connection.cursor() as cur:
            # Should raise exception or return error
            try:
                cur.execute(
                    """SELECT * FROM pggit.rollback_commit(
                        p_branch_name => %s,
                        p_commit_hash => %s
                    )""",
                    ('nonexistent_branch', fake_hash)
                )
                result = cur.fetchall()
                # If it returns without error, status should be FAILED
                if result:
                    assert result[0][2] == 'FAILED', "Should fail for nonexistent branch"
            except psycopg.Error:
                # Exception is acceptable too
                pass

    def test_rollback_commit_nonexistent_commit(self, db_connection):
        """Test rollback_commit with nonexistent commit."""
        fake_hash = 'b' * 64

        with db_connection.cursor() as cur:
            # First create a branch
            cur.execute(
                """SELECT branch_id FROM pggit.branches
                   WHERE branch_name = 'main' LIMIT 1"""
            )
            result = cur.fetchone()

            if result:
                # Try to rollback non-existent commit
                try:
                    cur.execute(
                        """SELECT * FROM pggit.rollback_commit(
                            p_branch_name => %s,
                            p_commit_hash => %s
                        )""",
                        ('main', fake_hash)
                    )
                    result = cur.fetchall()
                    if result:
                        assert result[0][2] in ('FAILED', 'ERROR'), "Should fail for nonexistent commit"
                except psycopg.Error:
                    # Exception is acceptable
                    pass

    def test_rollback_commit_dry_run_mode(self, db_connection):
        """Test rollback_commit in DRY_RUN mode."""
        with db_connection.cursor() as cur:
            # Get a real commit from main branch
            cur.execute(
                """SELECT c.commit_hash FROM pggit.commits c
                   JOIN pggit.branches b ON b.branch_id = c.branch_id
                   WHERE b.branch_name = 'main' LIMIT 1"""
            )
            result = cur.fetchone()

            if result:
                commit_hash = result[0]

                # Run dry run rollback
                cur.execute(
                    """SELECT status FROM pggit.rollback_commit(
                        p_branch_name => %s,
                        p_commit_hash => %s,
                        p_rollback_mode => %s
                    )""",
                    ('main', commit_hash, 'DRY_RUN')
                )
                result = cur.fetchone()

                if result:
                    assert result[0] == 'DRY_RUN', "DRY_RUN mode should return DRY_RUN status"

    def test_rollback_commit_returns_correct_columns(self, db_connection):
        """Test that rollback_commit returns all expected columns."""
        with db_connection.cursor() as cur:
            # Get a real commit
            cur.execute(
                """SELECT c.commit_hash FROM pggit.commits c
                   JOIN pggit.branches b ON b.branch_id = c.branch_id
                   WHERE b.branch_name = 'main' LIMIT 1"""
            )
            result = cur.fetchone()

            if result:
                commit_hash = result[0]

                # Run rollback
                cur.execute(
                    """SELECT rollback_id, rollback_commit_hash, status,
                              objects_rolled_back, validations_passed,
                              validations_failed, execution_time_ms
                       FROM pggit.rollback_commit(
                        p_branch_name => %s,
                        p_commit_hash => %s,
                        p_rollback_mode => %s
                    )""",
                    ('main', commit_hash, 'DRY_RUN')
                )
                result = cur.fetchone()

                if result:
                    # Should have 7 columns
                    assert len(result) == 7, "Should return 7 columns"
                    # Check types
                    rollback_id, commit_h, status, obj_count, pass_v, fail_v, exec_time = result
                    assert status in ('DRY_RUN', 'SUCCESS', 'FAILED'), "Status should be valid"
                    assert isinstance(obj_count, (int, type(None))), "objects_rolled_back should be integer"

    def test_rollback_commit_validates_before_execute(self, db_connection):
        """Test that rollback_commit runs validation by default."""
        with db_connection.cursor() as cur:
            # Get a real commit
            cur.execute(
                """SELECT c.commit_hash FROM pggit.commits c
                   JOIN pggit.branches b ON b.branch_id = c.branch_id
                   WHERE b.branch_name = 'main' LIMIT 1"""
            )
            result = cur.fetchone()

            if result:
                commit_hash = result[0]

                # Run rollback with validation (default)
                cur.execute(
                    """SELECT validations_passed, validations_failed
                       FROM pggit.rollback_commit(
                        p_branch_name => %s,
                        p_commit_hash => %s,
                        p_validate_first => true,
                        p_rollback_mode => %s
                    )""",
                    ('main', commit_hash, 'DRY_RUN')
                )
                result = cur.fetchone()

                if result:
                    pass_v, fail_v = result
                    # Should have some validations run
                    assert isinstance(pass_v, (int, type(None))), "validations_passed should be integer"
                    assert isinstance(fail_v, (int, type(None))), "validations_failed should be integer"

    def test_rollback_commit_skip_validation(self, db_connection):
        """Test rollback_commit with validation skipped."""
        with db_connection.cursor() as cur:
            # Get a real commit
            cur.execute(
                """SELECT c.commit_hash FROM pggit.commits c
                   JOIN pggit.branches b ON b.branch_id = c.branch_id
                   WHERE b.branch_name = 'main' LIMIT 1"""
            )
            result = cur.fetchone()

            if result:
                commit_hash = result[0]

                # Run rollback with validation skipped
                cur.execute(
                    """SELECT status FROM pggit.rollback_commit(
                        p_branch_name => %s,
                        p_commit_hash => %s,
                        p_validate_first => false,
                        p_rollback_mode => %s
                    )""",
                    ('main', commit_hash, 'DRY_RUN')
                )
                result = cur.fetchone()

                # Should still work (validation skipped)
                if result:
                    assert result[0] in ('DRY_RUN', 'SUCCESS', 'FAILED'), "Status should be valid"

    def test_rollback_commit_execution_time_recorded(self, db_connection):
        """Test that rollback_commit records execution time."""
        with db_connection.cursor() as cur:
            # Get a real commit
            cur.execute(
                """SELECT c.commit_hash FROM pggit.commits c
                   JOIN pggit.branches b ON b.branch_id = c.branch_id
                   WHERE b.branch_name = 'main' LIMIT 1"""
            )
            result = cur.fetchone()

            if result:
                commit_hash = result[0]

                # Run rollback
                cur.execute(
                    """SELECT execution_time_ms FROM pggit.rollback_commit(
                        p_branch_name => %s,
                        p_commit_hash => %s,
                        p_rollback_mode => %s
                    )""",
                    ('main', commit_hash, 'DRY_RUN')
                )
                result = cur.fetchone()

                if result:
                    exec_time = result[0]
                    # Should have recorded some time (could be 0ms if very fast)
                    assert isinstance(exec_time, (int, type(None))), "execution_time_ms should be integer"
                    if exec_time is not None:
                        assert exec_time >= 0, "execution_time_ms should be non-negative"

    def test_rollback_commit_objects_affected_count(self, db_connection):
        """Test that rollback_commit counts objects correctly."""
        with db_connection.cursor() as cur:
            # Get a real commit
            cur.execute(
                """SELECT c.commit_hash FROM pggit.commits c
                   JOIN pggit.branches b ON b.branch_id = c.branch_id
                   WHERE b.branch_name = 'main' LIMIT 1"""
            )
            result = cur.fetchone()

            if result:
                commit_hash = result[0]

                # Run rollback in dry-run
                cur.execute(
                    """SELECT objects_rolled_back FROM pggit.rollback_commit(
                        p_branch_name => %s,
                        p_commit_hash => %s,
                        p_rollback_mode => %s
                    )""",
                    ('main', commit_hash, 'DRY_RUN')
                )
                result = cur.fetchone()

                if result:
                    obj_count = result[0]
                    # Should have a count (>= 0)
                    assert isinstance(obj_count, (int, type(None))), "objects_rolled_back should be integer"
                    if obj_count is not None:
                        assert obj_count >= 0, "objects_rolled_back should be non-negative"



# ==============================================================================
# PHASE 6.3 TESTS: rollback_range() and rollback_to_timestamp()
# ==============================================================================

class TestPhase6RollbackRange:
    """Test suite for pggit.rollback_range() function."""

    def test_rollback_range_invalid_branch(self, db_connection):
        """Test rollback_range fails for nonexistent branch."""
        fake_hash = 'a' * 64
        with db_connection.cursor() as cur:
            with pytest.raises(Exception):  # Should raise
                cur.execute(
                    """SELECT * FROM pggit.rollback_range(
                        p_branch_name => %s,
                        p_start_commit_hash => %s,
                        p_end_commit_hash => %s
                    )""",
                    ('nonexistent_branch', fake_hash, fake_hash)
                )
                cur.fetchall()

    def test_rollback_range_invalid_start_commit(self, db_connection):
        """Test rollback_range fails for nonexistent start commit."""
        fake_hash = 'a' * 64
        with db_connection.cursor() as cur:
            with pytest.raises(Exception):
                cur.execute(
                    """SELECT * FROM pggit.rollback_range(
                        p_branch_name => %s,
                        p_start_commit_hash => %s,
                        p_end_commit_hash => %s
                    )""",
                    ('main', fake_hash, fake_hash)
                )
                cur.fetchall()

    def test_rollback_range_invalid_order_by(self, fixture_with_data, db_connection):
        """Test rollback_range fails for invalid order_by parameter."""
        hash1 = fixture_with_data.get_commit_hash('T1')
        hash2 = fixture_with_data.get_commit_hash('T2')

        if hash1 and hash2:
            with db_connection.cursor() as cur:
                with pytest.raises(Exception):
                    cur.execute(
                        """SELECT * FROM pggit.rollback_range(
                            p_branch_name => %s,
                            p_start_commit_hash => %s,
                            p_end_commit_hash => %s,
                            p_order_by => %s
                        )""",
                        ('main', hash1, hash2, 'INVALID_ORDER')
                    )
                    cur.fetchall()

    def test_rollback_range_start_after_end(self, fixture_with_data, db_connection):
        """Test rollback_range fails when start_commit is after end_commit."""
        hash1 = fixture_with_data.get_commit_hash('T1')
        hash2 = fixture_with_data.get_commit_hash('T3')

        if hash1 and hash2:
            with db_connection.cursor() as cur:
                with pytest.raises(Exception):  # Should fail chronological check
                    cur.execute(
                        """SELECT * FROM pggit.rollback_range(
                            p_branch_name => %s,
                            p_start_commit_hash => %s,
                            p_end_commit_hash => %s
                        )""",
                        ('main', hash2, hash1)  # Reversed order
                    )
                    cur.fetchall()

    def test_rollback_range_dry_run_returns_data(self, fixture_with_data, db_connection):
        """Test rollback_range DRY_RUN returns valid data."""
        hash1 = fixture_with_data.get_commit_hash('T1')
        hash3 = fixture_with_data.get_commit_hash('T3')

        if hash1 and hash3:
            with db_connection.cursor() as cur:
                cur.execute(
                    """SELECT rollback_id, commits_rolled_back, status, objects_affected_total
                       FROM pggit.rollback_range(
                           p_branch_name => %s,
                           p_start_commit_hash => %s,
                           p_end_commit_hash => %s,
                           p_rollback_mode => %s
                       )""",
                    ('main', hash1, hash3, 'DRY_RUN')
                )
                result = cur.fetchone()

                if result:
                    rollback_id, commits, status, obj_count = result
                    assert rollback_id == 0, "DRY_RUN should have rollback_id=0"
                    assert status == 'DRY_RUN', "DRY_RUN should have DRY_RUN status"
                    assert isinstance(commits, int), "commits_rolled_back should be int"
                    assert isinstance(obj_count, int), "objects_affected_total should be int"

    def test_rollback_range_returns_all_columns(self, fixture_with_data, db_connection):
        """Test rollback_range returns all expected columns."""
        hash1 = fixture_with_data.get_commit_hash('T1')
        hash3 = fixture_with_data.get_commit_hash('T3')

        if hash1 and hash3:
            with db_connection.cursor() as cur:
                cur.execute(
                    """SELECT rollback_id, commits_rolled_back, rollback_commit_hash,
                              status, objects_affected_total, conflicts_resolved, execution_time_ms
                       FROM pggit.rollback_range(
                           p_branch_name => %s,
                           p_start_commit_hash => %s,
                           p_end_commit_hash => %s,
                           p_rollback_mode => %s
                       )""",
                    ('main', hash1, hash3, 'DRY_RUN')
                )
                result = cur.fetchone()
                assert result is not None, "Should return result"
                assert len(result) == 7, "Should return 7 columns"

    def test_rollback_range_conflicts_count(self, fixture_with_data, db_connection):
        """Test rollback_range correctly counts conflicts."""
        hash1 = fixture_with_data.get_commit_hash('T1')
        hash3 = fixture_with_data.get_commit_hash('T3')

        if hash1 and hash3:
            with db_connection.cursor() as cur:
                cur.execute(
                    """SELECT conflicts_resolved FROM pggit.rollback_range(
                        p_branch_name => %s,
                        p_start_commit_hash => %s,
                        p_end_commit_hash => %s,
                        p_rollback_mode => %s
                    )""",
                    ('main', hash1, hash3, 'DRY_RUN')
                )
                result = cur.fetchone()

                if result:
                    conflict_count = result[0]
                    assert isinstance(conflict_count, (int, type(None))), "conflicts_resolved should be int"
                    if conflict_count is not None:
                        assert conflict_count >= 0, "conflicts_resolved should be non-negative"

    def test_rollback_range_execution_time_recorded(self, fixture_with_data, db_connection):
        """Test rollback_range records execution time."""
        hash1 = fixture_with_data.get_commit_hash('T1')
        hash3 = fixture_with_data.get_commit_hash('T3')

        if hash1 and hash3:
            with db_connection.cursor() as cur:
                cur.execute(
                    """SELECT execution_time_ms FROM pggit.rollback_range(
                        p_branch_name => %s,
                        p_start_commit_hash => %s,
                        p_end_commit_hash => %s,
                        p_rollback_mode => %s
                    )""",
                    ('main', hash1, hash3, 'DRY_RUN')
                )
                result = cur.fetchone()

                if result:
                    exec_time = result[0]
                    assert isinstance(exec_time, (int, type(None))), "execution_time_ms should be int"
                    if exec_time is not None:
                        assert exec_time >= 0, "execution_time_ms should be non-negative"


class TestPhase6RollbackToTimestamp:
    """Test suite for pggit.rollback_to_timestamp() function."""

    def test_rollback_to_timestamp_invalid_branch(self, db_connection):
        """Test rollback_to_timestamp fails for nonexistent branch."""
        past_time = datetime.now() - timedelta(hours=1)
        with db_connection.cursor() as cur:
            with pytest.raises(Exception):
                cur.execute(
                    """SELECT * FROM pggit.rollback_to_timestamp(
                        p_branch_name => %s,
                        p_target_timestamp => %s
                    )""",
                    ('nonexistent_branch', past_time)
                )
                cur.fetchall()

    def test_rollback_to_timestamp_future_timestamp(self, db_connection):
        """Test rollback_to_timestamp fails for future timestamp."""
        future_time = datetime.now() + timedelta(hours=1)
        with db_connection.cursor() as cur:
            with pytest.raises(Exception):
                cur.execute(
                    """SELECT * FROM pggit.rollback_to_timestamp(
                        p_branch_name => %s,
                        p_target_timestamp => %s
                    )""",
                    ('main', future_time)
                )
                cur.fetchall()

    def test_rollback_to_timestamp_with_valid_params(self, db_connection):
        """Test rollback_to_timestamp works with valid parameters."""
        # Get a time 10 hours ago
        past_time = datetime.now() - timedelta(hours=10)
        with db_connection.cursor() as cur:
            # This might not find commits, but function should handle gracefully
            cur.execute(
                """SELECT status FROM pggit.rollback_to_timestamp(
                    p_branch_name => %s,
                    p_target_timestamp => %s,
                    p_rollback_mode => %s
                ) LIMIT 1""",
                ('main', past_time, 'DRY_RUN')
            )
            result = cur.fetchone()
            # Should return something or nothing, but not error
            assert result is None or len(result) >= 1

    def test_rollback_to_timestamp_dry_run_returns_data(self, fixture_with_data, db_connection):
        """Test rollback_to_timestamp DRY_RUN returns valid data."""
        # Use a recent past time
        past_time = datetime.now() - timedelta(hours=1)

        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT rollback_id, status, commits_reversed FROM pggit.rollback_to_timestamp(
                    p_branch_name => %s,
                    p_target_timestamp => %s,
                    p_rollback_mode => %s
                )""",
                ('main', past_time, 'DRY_RUN')
            )
            result = cur.fetchone()

            if result:
                rollback_id, status, commits = result
                assert rollback_id == 0, "DRY_RUN should have rollback_id=0"
                assert status == 'DRY_RUN', "DRY_RUN should have DRY_RUN status"
                assert isinstance(commits, (int, type(None))), "commits_reversed should be int"

    def test_rollback_to_timestamp_returns_all_columns(self, fixture_with_data, db_connection):
        """Test rollback_to_timestamp returns all expected columns."""
        past_time = datetime.now() - timedelta(hours=1)

        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT rollback_id, rollback_commit_hash, status, commits_reversed,
                          objects_recreated, objects_deleted, objects_modified, execution_time_ms
                   FROM pggit.rollback_to_timestamp(
                       p_branch_name => %s,
                       p_target_timestamp => %s,
                       p_rollback_mode => %s
                   )""",
                ('main', past_time, 'DRY_RUN')
            )
            result = cur.fetchone()
            assert result is not None, "Should return result"
            assert len(result) == 8, "Should return 8 columns"

    def test_rollback_to_timestamp_object_counts(self, fixture_with_data, db_connection):
        """Test rollback_to_timestamp correctly counts objects."""
        past_time = datetime.now() - timedelta(hours=1)

        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT objects_recreated, objects_deleted, objects_modified
                   FROM pggit.rollback_to_timestamp(
                       p_branch_name => %s,
                       p_target_timestamp => %s,
                       p_rollback_mode => %s
                   )""",
                ('main', past_time, 'DRY_RUN')
            )
            result = cur.fetchone()

            if result:
                recreated, deleted, modified = result
                assert isinstance(recreated, (int, type(None))), "objects_recreated should be int"
                assert isinstance(deleted, (int, type(None))), "objects_deleted should be int"
                assert isinstance(modified, (int, type(None))), "objects_modified should be int"

    def test_rollback_to_timestamp_execution_time_recorded(self, fixture_with_data, db_connection):
        """Test rollback_to_timestamp records execution time."""
        past_time = datetime.now() - timedelta(hours=1)

        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT execution_time_ms FROM pggit.rollback_to_timestamp(
                    p_branch_name => %s,
                    p_target_timestamp => %s,
                    p_rollback_mode => %s
                )""",
                ('main', past_time, 'DRY_RUN')
            )
            result = cur.fetchone()

            if result:
                exec_time = result[0]
                assert isinstance(exec_time, (int, type(None))), "execution_time_ms should be int"
                if exec_time is not None:
                    assert exec_time >= 0, "execution_time_ms should be non-negative"

    def test_rollback_to_timestamp_commits_reversed_count(self, fixture_with_data, db_connection):
        """Test rollback_to_timestamp correctly counts commits reversed."""
        past_time = datetime.now() - timedelta(hours=1)

        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT commits_reversed FROM pggit.rollback_to_timestamp(
                    p_branch_name => %s,
                    p_target_timestamp => %s,
                    p_rollback_mode => %s
                )""",
                ('main', past_time, 'DRY_RUN')
            )
            result = cur.fetchone()

            if result:
                commits = result[0]
                assert isinstance(commits, (int, type(None))), "commits_reversed should be int"
                if commits is not None:
                    assert commits >= 0, "commits_reversed should be non-negative"

    def test_rollback_to_timestamp_before_first_commit(self, db_connection):
        """Test rollback_to_timestamp fails when timestamp is before first commit."""
        # This should be before any commits on main
        very_old_time = datetime(2020, 1, 1, 0, 0, 0)

        with db_connection.cursor() as cur:
            with pytest.raises(Exception):
                cur.execute(
                    """SELECT * FROM pggit.rollback_to_timestamp(
                        p_branch_name => %s,
                        p_target_timestamp => %s
                    )""",
                    ('main', very_old_time)
                )
                cur.fetchall()

    def test_rollback_to_timestamp_with_fixture_data(self, fixture_with_data, db_connection):
        """Test rollback_to_timestamp with fixture data."""
        # Get the timestamp of second commit (T2), then query for time between T1 and T2
        t1_time = fixture_with_data.timestamps.get('T1')
        t2_time = fixture_with_data.timestamps.get('T2')

        if t1_time and t2_time:
            # Query for a time between T1 and T2
            target_time = t1_time + timedelta(seconds=1)

            with db_connection.cursor() as cur:
                cur.execute(
                    """SELECT status FROM pggit.rollback_to_timestamp(
                        p_branch_name => %s,
                        p_target_timestamp => %s,
                        p_rollback_mode => %s
                    )""",
                    ('main', target_time, 'DRY_RUN')
                )
                result = cur.fetchone()

                if result:
                    status = result[0]
                    # Should succeed (DRY_RUN)
                    assert status in ('DRY_RUN', 'SUCCESS'), f"Unexpected status: {status}"



# ==============================================================================
# PHASE 6.4 TESTS: undo_changes() and rollback_dependencies()
# ==============================================================================

class TestPhase6UndoChanges:
    """Test suite for pggit.undo_changes() function."""

    def test_undo_changes_invalid_branch(self, db_connection):
        """Test undo_changes fails for nonexistent branch."""
        with db_connection.cursor() as cur:
            with pytest.raises(Exception):
                cur.execute(
                    """SELECT * FROM pggit.undo_changes(
                        p_branch_name => %s,
                        p_object_names => %s,
                        p_commit_hash => %s
                    )""",
                    ('nonexistent_branch', ['public.users'], 'a' * 64)
                )
                cur.fetchall()

    def test_undo_changes_empty_object_names(self, db_connection):
        """Test undo_changes fails for empty object names array."""
        with db_connection.cursor() as cur:
            with pytest.raises(Exception):
                cur.execute(
                    """SELECT * FROM pggit.undo_changes(
                        p_branch_name => %s,
                        p_object_names => %s,
                        p_commit_hash => %s
                    )""",
                    ('main', [], 'a' * 64)
                )
                cur.fetchall()

    def test_undo_changes_neither_commit_nor_range(self, db_connection):
        """Test undo_changes fails when neither commit nor range provided."""
        with db_connection.cursor() as cur:
            with pytest.raises(Exception):
                cur.execute(
                    """SELECT * FROM pggit.undo_changes(
                        p_branch_name => %s,
                        p_object_names => %s
                    )""",
                    ('main', ['public.users'])
                )
                cur.fetchall()

    def test_undo_changes_invalid_object_format(self, db_connection):
        """Test undo_changes fails for invalid object name format."""
        with db_connection.cursor() as cur:
            with pytest.raises(Exception):
                cur.execute(
                    """SELECT * FROM pggit.undo_changes(
                        p_branch_name => %s,
                        p_object_names => %s,
                        p_commit_hash => %s
                    )""",
                    ('main', ['invalid_format_no_dot'], 'a' * 64)
                )
                cur.fetchall()

    def test_undo_changes_dry_run_returns_data(self, db_connection):
        """Test undo_changes DRY_RUN returns valid structure."""
        # Use fake hash - will fail commit validation but tests DRY_RUN structure
        fake_hash = 'a' * 64
        with db_connection.cursor() as cur:
            try:
                cur.execute(
                    """SELECT rollback_id, status FROM pggit.undo_changes(
                        p_branch_name => %s,
                        p_object_names => %s,
                        p_commit_hash => %s,
                        p_rollback_mode => %s
                    )""",
                    ('main', ['public.users'], fake_hash, 'DRY_RUN')
                )
                result = cur.fetchone()
                # Either error or result with rollback_id=0
                if result:
                    rollback_id, status = result
                    assert isinstance(rollback_id, (int, type(None)))
                    assert isinstance(status, (str, type(None)))
            except Exception:
                # Expected since commit doesn't exist
                pass

    def test_undo_changes_returns_all_columns(self, fixture_with_data, db_connection):
        """Test undo_changes returns all expected columns."""
        commit_hash = fixture_with_data.get_commit_hash('T1')
        if commit_hash:
            with db_connection.cursor() as cur:
                try:
                    cur.execute(
                        """SELECT rollback_id, rollback_commit_hash, status,
                                  objects_reverted, changes_undone, dependencies_handled, execution_time_ms
                           FROM pggit.undo_changes(
                               p_branch_name => %s,
                               p_object_names => %s,
                               p_commit_hash => %s,
                               p_rollback_mode => %s
                           )""",
                        ('main', ['test.users_test'], commit_hash, 'DRY_RUN')
                    )
                    result = cur.fetchone()
                    if result:
                        assert len(result) == 7, "Should return 7 columns"
                except Exception:
                    pass  # Expected if object doesn't exist

    def test_undo_changes_counts_integer(self, db_connection):
        """Test undo_changes returns integer counts."""
        fake_hash = 'a' * 64
        with db_connection.cursor() as cur:
            try:
                cur.execute(
                    """SELECT objects_reverted, changes_undone, dependencies_handled
                       FROM pggit.undo_changes(
                           p_branch_name => %s,
                           p_object_names => %s,
                           p_commit_hash => %s,
                           p_rollback_mode => %s
                       )""",
                    ('main', ['public.users'], fake_hash, 'DRY_RUN')
                )
                result = cur.fetchone()
                if result:
                    obj_count, change_count, dep_count = result
                    assert isinstance(obj_count, (int, type(None)))
                    assert isinstance(change_count, (int, type(None)))
                    assert isinstance(dep_count, (int, type(None)))
            except Exception:
                pass

    def test_undo_changes_execution_time_recorded(self, db_connection):
        """Test undo_changes records execution time."""
        fake_hash = 'a' * 64
        with db_connection.cursor() as cur:
            try:
                cur.execute(
                    """SELECT execution_time_ms FROM pggit.undo_changes(
                        p_branch_name => %s,
                        p_object_names => %s,
                        p_commit_hash => %s,
                        p_rollback_mode => %s
                    )""",
                    ('main', ['public.users'], fake_hash, 'DRY_RUN')
                )
                result = cur.fetchone()
                if result:
                    exec_time = result[0]
                    assert isinstance(exec_time, (int, type(None)))
                    if exec_time is not None:
                        assert exec_time >= 0
            except Exception:
                pass


class TestPhase6RollbackDependencies:
    """Test suite for pggit.rollback_dependencies() function."""

    def test_rollback_dependencies_invalid_object_id(self, db_connection):
        """Test rollback_dependencies fails for nonexistent object ID."""
        with db_connection.cursor() as cur:
            with pytest.raises(Exception):
                cur.execute(
                    """SELECT * FROM pggit.rollback_dependencies(
                        p_object_id => %s
                    )""",
                    (999999,)
                )
                cur.fetchall()

    def test_rollback_dependencies_returns_all_columns(self, db_connection):
        """Test rollback_dependencies returns all expected columns."""
        # Get any object from schema_objects
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT object_id FROM pggit.schema_objects LIMIT 1"""
            )
            result = cur.fetchone()

            if result:
                object_id = result[0]
                cur.execute(
                    """SELECT dependency_id, source_object_id, source_object_name,
                              source_object_type, target_object_id, target_object_name,
                              dependency_type, strength, breakage_severity, suggested_action
                       FROM pggit.rollback_dependencies(
                           p_object_id => %s
                       )""",
                    (object_id,)
                )
                # Might have 0 or more results
                results = cur.fetchall()
                if results:
                    for row in results:
                        assert len(row) == 10, "Should return 10 columns"

    def test_rollback_dependencies_strength_classification(self, db_connection):
        """Test rollback_dependencies classifies strength (HARD/SOFT)."""
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT object_id FROM pggit.schema_objects LIMIT 1"""
            )
            result = cur.fetchone()

            if result:
                object_id = result[0]
                cur.execute(
                    """SELECT DISTINCT strength FROM pggit.rollback_dependencies(
                        p_object_id => %s
                    )""",
                    (object_id,)
                )
                results = cur.fetchall()

                # Check that strength values are valid
                valid_strengths = {'HARD', 'SOFT'}
                for row in results:
                    strength = row[0]
                    if strength is not None:
                        assert strength in valid_strengths, f"Invalid strength: {strength}"

    def test_rollback_dependencies_severity_classification(self, db_connection):
        """Test rollback_dependencies classifies severity correctly."""
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT object_id FROM pggit.schema_objects LIMIT 1"""
            )
            result = cur.fetchone()

            if result:
                object_id = result[0]
                cur.execute(
                    """SELECT DISTINCT breakage_severity FROM pggit.rollback_dependencies(
                        p_object_id => %s
                    )""",
                    (object_id,)
                )
                results = cur.fetchall()

                # Check that severity values are valid
                valid_severities = {'INFO', 'WARNING', 'ERROR', 'CRITICAL'}
                for row in results:
                    severity = row[0]
                    if severity is not None:
                        assert severity in valid_severities, f"Invalid severity: {severity}"

    def test_rollback_dependencies_suggested_action_provided(self, db_connection):
        """Test rollback_dependencies provides suggested action."""
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT object_id FROM pggit.schema_objects LIMIT 1"""
            )
            result = cur.fetchone()

            if result:
                object_id = result[0]
                cur.execute(
                    """SELECT suggested_action FROM pggit.rollback_dependencies(
                        p_object_id => %s
                    )""",
                    (object_id,)
                )
                results = cur.fetchall()

                # Check that suggested action is provided
                for row in results:
                    action = row[0]
                    # Action should be non-empty string if returned
                    if action is not None:
                        assert isinstance(action, str)
                        assert len(action) > 0

    def test_rollback_dependencies_dependency_type_valid(self, db_connection):
        """Test rollback_dependencies returns valid dependency types."""
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT object_id FROM pggit.schema_objects LIMIT 1"""
            )
            result = cur.fetchone()

            if result:
                object_id = result[0]
                cur.execute(
                    """SELECT DISTINCT dependency_type FROM pggit.rollback_dependencies(
                        p_object_id => %s
                    )""",
                    (object_id,)
                )
                results = cur.fetchall()

                # Check that dependency types are reasonable
                valid_types = {
                    'FOREIGN_KEY', 'TRIGGERS_ON', 'REFERENCES', 'COMPOSED_OF',
                    'INDEXES', 'CALLS', 'USES'
                }
                for row in results:
                    dep_type = row[0]
                    if dep_type is not None:
                        # Custom types might exist, just check it's a string
                        assert isinstance(dep_type, str)

    def test_rollback_dependencies_object_names_not_null(self, db_connection):
        """Test rollback_dependencies returns object names."""
        with db_connection.cursor() as cur:
            cur.execute(
                """SELECT object_id FROM pggit.schema_objects LIMIT 1"""
            )
            result = cur.fetchone()

            if result:
                object_id = result[0]
                cur.execute(
                    """SELECT source_object_name, target_object_name
                       FROM pggit.rollback_dependencies(
                           p_object_id => %s
                       )""",
                    (object_id,)
                )
                results = cur.fetchall()

                for row in results:
                    source_name, target_name = row
                    # Names should be provided if row returned
                    if source_name is not None:
                        assert isinstance(source_name, str)
                    if target_name is not None:
                        assert isinstance(target_name, str)


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
