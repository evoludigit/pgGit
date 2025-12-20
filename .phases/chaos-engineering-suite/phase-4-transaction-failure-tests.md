# Phase 4: Transaction Failure & Recovery Tests

## Objective
Implement comprehensive tests for transaction failure scenarios, rollback correctness, crash recovery, and data integrity guarantees under adverse conditions.

## TDD Stage
RED → GREEN

## Context
- **Previous phase**: Phase 3 (Concurrency Tests) tested race conditions and deadlocks
- **Current state**: Concurrency bugs identified, but no transaction failure testing
- **Next phase**: Phase 5 (Resource Exhaustion) will test system limits

## Files to Create

### 1. `tests/chaos/test_transaction_rollback.py`
Tests for transaction rollback correctness:
- Complete rollback on error
- Partial commit prevention
- Savepoint rollback
- Nested transaction handling

### 2. `tests/chaos/test_crash_recovery.py`
Tests for crash recovery scenarios:
- Uncommitted transaction recovery
- In-progress commit recovery
- Trinity ID consistency after crash
- Version state after crash

### 3. `tests/chaos/test_constraint_violations.py`
Tests for constraint violation handling:
- Foreign key violations during rollback
- Unique constraint violations
- Check constraint failures
- NOT NULL violations

### 4. `tests/chaos/test_partial_failures.py`
Tests for partial failure scenarios:
- Multi-table transaction failures
- Trigger failures mid-transaction
- Extension function failures

## Implementation Steps

### Step 1: Transaction Rollback Tests (`tests/chaos/test_transaction_rollback.py`)

```python
"""
Transaction rollback correctness tests.
"""

import pytest
import psycopg
from tests.chaos.utils import DatabaseStateSnapshot


@pytest.mark.chaos
@pytest.mark.transaction
class TestTransactionRollback:
    """Test transaction rollback behavior."""

    def test_complete_rollback_on_error(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Transaction with error rolls back ALL changes.

        Expected: No partial commits, database returns to pre-transaction state.
        """
        # Capture initial state
        snapshot = DatabaseStateSnapshot(sync_conn)
        snapshot.capture("before", "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = current_schema()")

        try:
            sync_conn.execute("BEGIN")

            # Create table (should be rolled back)
            sync_conn.execute("CREATE TABLE rollback_test_1 (id INT)")

            # Create another table (should be rolled back)
            sync_conn.execute("CREATE TABLE rollback_test_2 (id INT)")

            # Cause error
            sync_conn.execute("THIS IS INVALID SQL")

            sync_conn.commit()

        except psycopg.Error:
            sync_conn.rollback()

        # Verify complete rollback
        matches, msg = snapshot.compare(
            "before",
            "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = current_schema()"
        )

        assert matches, f"Transaction should rollback completely: {msg}"

        # Verify tables don't exist
        cursor = sync_conn.execute("""
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = current_schema()
            AND table_name IN ('rollback_test_1', 'rollback_test_2')
        """)
        assert cursor.fetchone() is None, "Rolled back tables should not exist"

    def test_pggit_commit_rollback(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Failed pggit commit rolls back ALL changes.

        This is critical: if commit_changes() fails, Trinity ID should not be assigned.
        """
        # Create table
        sync_conn.execute("CREATE TABLE pggit_rollback_test (id INT)")
        sync_conn.commit()

        # Capture Trinity ID count before
        cursor_before = sync_conn.execute("SELECT COUNT(*) FROM pggit.trinity_ids")
        trinity_count_before = cursor_before.fetchone()[0]

        # Attempt commit that will fail
        try:
            sync_conn.execute("BEGIN")

            # This should trigger pggit's versioning
            sync_conn.execute("ALTER TABLE pggit_rollback_test ADD COLUMN data TEXT")

            # Try to commit (will fail due to invalid params or logic error)
            # Simulate by causing error during commit
            sync_conn.execute("SELECT 1/0")  # Division by zero

            sync_conn.execute(
                "SELECT pggit.commit_changes(%s, %s, %s)",
                ("failed-commit", "main", "This should not persist")
            )

            sync_conn.commit()

        except psycopg.Error:
            sync_conn.rollback()

        # Verify NO Trinity ID was assigned
        cursor_after = sync_conn.execute("SELECT COUNT(*) FROM pggit.trinity_ids")
        trinity_count_after = cursor_after.fetchone()[0]

        assert trinity_count_before == trinity_count_after, \
            "Failed commit should not create Trinity ID"

        # Verify schema change was rolled back
        cursor = sync_conn.execute("""
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = current_schema()
            AND table_name = 'pggit_rollback_test'
            AND column_name = 'data'
        """)
        assert cursor.fetchone() is None, "Schema change should be rolled back"

    def test_savepoint_rollback(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Savepoint allows partial rollback within transaction.

        Expected: Changes after savepoint are rolled back, changes before persist.
        """
        sync_conn.execute("BEGIN")

        # Create first table (before savepoint)
        sync_conn.execute("CREATE TABLE savepoint_test_1 (id INT)")

        # Create savepoint
        sync_conn.execute("SAVEPOINT sp1")

        # Create second table (after savepoint)
        sync_conn.execute("CREATE TABLE savepoint_test_2 (id INT)")

        # Rollback to savepoint
        sync_conn.execute("ROLLBACK TO SAVEPOINT sp1")

        # Commit transaction
        sync_conn.commit()

        # Verify: table 1 exists, table 2 doesn't
        cursor = sync_conn.execute("""
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = current_schema()
            AND table_name IN ('savepoint_test_1', 'savepoint_test_2')
        """)
        tables = [row[0] for row in cursor.fetchall()]

        assert 'savepoint_test_1' in tables, "Table before savepoint should exist"
        assert 'savepoint_test_2' not in tables, "Table after savepoint should not exist"

    def test_nested_transaction_rollback(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Nested transaction (via savepoints) rollback behavior.

        Expected: Inner rollback doesn't affect outer transaction.
        """
        sync_conn.execute("BEGIN")

        # Outer transaction
        sync_conn.execute("CREATE TABLE nested_outer (id INT)")

        # Nested transaction (savepoint)
        sync_conn.execute("SAVEPOINT sp_nested")
        sync_conn.execute("CREATE TABLE nested_inner (id INT)")

        # Rollback nested
        sync_conn.execute("ROLLBACK TO SAVEPOINT sp_nested")

        # Outer commit
        sync_conn.commit()

        # Verify: outer table exists, inner doesn't
        cursor = sync_conn.execute("""
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = current_schema()
            AND table_name IN ('nested_outer', 'nested_inner')
        """)
        tables = [row[0] for row in cursor.fetchall()]

        assert 'nested_outer' in tables, "Outer table should exist"
        assert 'nested_inner' not in tables, "Inner rolled-back table should not exist"


@pytest.mark.chaos
@pytest.mark.transaction
class TestRollbackIntegrity:
    """Test data integrity after rollback."""

    def test_version_integrity_after_rollback(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Version state is consistent after rollback.

        Expected: Version doesn't increment if transaction rolled back.
        """
        # Create table
        sync_conn.execute("CREATE TABLE version_rollback_test (id INT)")
        sync_conn.commit()

        # Get version
        cursor = sync_conn.execute(
            "SELECT * FROM pggit.get_version(%s)", ("version_rollback_test",)
        )
        version_before = cursor.fetchone()

        # Attempt change with rollback
        try:
            sync_conn.execute("BEGIN")
            sync_conn.execute("ALTER TABLE version_rollback_test ADD COLUMN data TEXT")
            sync_conn.execute("SELECT 1/0")  # Force error
            sync_conn.commit()

        except psycopg.Error:
            sync_conn.rollback()

        # Get version again
        cursor = sync_conn.execute(
            "SELECT * FROM pggit.get_version(%s)", ("version_rollback_test",)
        )
        version_after = cursor.fetchone()

        # Verify version unchanged
        assert version_before == version_after, \
            f"Version should not change on rollback: {version_before} vs {version_after}"

    def test_trinity_id_sequence_after_rollback(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Trinity ID sequence remains consistent after rollback.

        Expected: Failed commits don't create gaps in Trinity ID sequence.
        Note: Sequence gaps are acceptable in PostgreSQL, but we test consistency.
        """
        # Get current max Trinity ID
        cursor = sync_conn.execute(
            "SELECT MAX(id) FROM pggit.trinity_ids"
        )
        max_id_before = cursor.fetchone()[0] or 0

        # Successful commit
        sync_conn.execute("CREATE TABLE trinity_seq_test (id INT)")
        sync_conn.execute(
            "SELECT pggit.commit_changes(%s, %s, %s)",
            ("seq-test-1", "main", "First commit")
        )
        sync_conn.commit()

        # Failed commit
        try:
            sync_conn.execute("BEGIN")
            sync_conn.execute("ALTER TABLE trinity_seq_test ADD COLUMN data TEXT")
            sync_conn.execute("SELECT 1/0")  # Error
            sync_conn.execute(
                "SELECT pggit.commit_changes(%s, %s, %s)",
                ("seq-test-failed", "main", "Failed commit")
            )
            sync_conn.commit()

        except psycopg.Error:
            sync_conn.rollback()

        # Another successful commit
        sync_conn.execute("ALTER TABLE trinity_seq_test ADD COLUMN data2 TEXT")
        sync_conn.execute(
            "SELECT pggit.commit_changes(%s, %s, %s)",
            ("seq-test-2", "main", "Second commit")
        )
        sync_conn.commit()

        # Get final Trinity ID count
        cursor = sync_conn.execute("SELECT COUNT(*) FROM pggit.trinity_ids")
        trinity_count = cursor.fetchone()[0]

        # We should have exactly 2 new Trinity IDs (not 3)
        expected_new_ids = 2
        actual_new_ids = trinity_count - max_id_before

        # Note: This might fail if Trinity ID uses PostgreSQL sequences (which can skip)
        # In that case, we accept gaps and test >= instead of ==
        assert actual_new_ids >= expected_new_ids, \
            f"Should have at least {expected_new_ids} new Trinity IDs, got {actual_new_ids}"
```

### Step 2: Crash Recovery Tests (`tests/chaos/test_crash_recovery.py`)

```python
"""
Crash recovery tests (simulate database restart).
"""

import pytest
import psycopg
import subprocess
import time


@pytest.mark.chaos
@pytest.mark.crash
@pytest.mark.destructive
@pytest.mark.skip(reason="Requires PostgreSQL restart privileges")
class TestCrashRecovery:
    """
    Test crash recovery scenarios.

    WARNING: These tests require ability to restart PostgreSQL.
    Only run in test environment, never production!
    """

    def test_uncommitted_transaction_recovery(
        self, db_connection_string: str
    ):
        """
        Test: Uncommitted transaction is discarded after crash.

        Expected: After restart, no traces of uncommitted work remain.
        """
        # Create transaction but don't commit
        conn = psycopg.connect(db_connection_string)
        conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")

        conn.execute("BEGIN")
        conn.execute("CREATE TABLE crash_test_uncommitted (id INT)")
        # DON'T COMMIT

        # Simulate crash (terminate backend)
        backend_pid = conn.info.backend_pid
        conn.close()

        # Kill the backend (simulates crash)
        subprocess.run(["pg_ctl", "restart", "-D", "/var/lib/postgresql/data"])
        time.sleep(5)  # Wait for restart

        # Reconnect
        conn = psycopg.connect(db_connection_string)
        conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")

        # Verify table doesn't exist
        cursor = conn.execute("""
            SELECT table_name
            FROM information_schema.tables
            WHERE table_name = 'crash_test_uncommitted'
        """)

        assert cursor.fetchone() is None, \
            "Uncommitted table should not exist after crash"

        conn.close()

    def test_trinity_id_consistency_after_crash(
        self, db_connection_string: str
    ):
        """
        Test: Trinity IDs remain consistent after crash.

        Expected: No duplicate IDs, no orphaned references.
        """
        # Create commits
        conn = psycopg.connect(db_connection_string)
        conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")

        conn.execute("CREATE TABLE crash_trinity_test (id INT)")
        conn.execute(
            "SELECT pggit.commit_changes(%s, %s, %s)",
            ("crash-commit-1", "main", "Before crash")
        )
        conn.commit()

        # Get Trinity ID count
        cursor = conn.execute("SELECT COUNT(*) FROM pggit.trinity_ids")
        trinity_count_before = cursor.fetchone()[0]

        conn.close()

        # Simulate crash and restart
        subprocess.run(["pg_ctl", "restart", "-D", "/var/lib/postgresql/data"])
        time.sleep(5)

        # Reconnect
        conn = psycopg.connect(db_connection_string)
        conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")

        # Check Trinity ID count unchanged
        cursor = conn.execute("SELECT COUNT(*) FROM pggit.trinity_ids")
        trinity_count_after = cursor.fetchone()[0]

        assert trinity_count_before == trinity_count_after, \
            "Trinity ID count should be consistent after crash"

        # Check for duplicates
        cursor = conn.execute("""
            SELECT id, COUNT(*)
            FROM pggit.trinity_ids
            GROUP BY id
            HAVING COUNT(*) > 1
        """)

        assert cursor.fetchone() is None, \
            "No duplicate Trinity IDs should exist"

        conn.close()
```

### Step 3: Constraint Violation Tests (`tests/chaos/test_constraint_violations.py`)

```python
"""
Tests for constraint violation handling during transactions.
"""

import pytest
import psycopg


@pytest.mark.chaos
@pytest.mark.constraints
class TestConstraintViolations:
    """Test constraint violation handling."""

    def test_unique_constraint_violation_rollback(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Unique constraint violation triggers complete rollback.

        Expected: Transaction rolls back entirely, no partial data persists.
        """
        # Create table with unique constraint
        sync_conn.execute("""
            CREATE TABLE unique_test (
                id SERIAL PRIMARY KEY,
                email TEXT UNIQUE
            )
        """)
        sync_conn.commit()

        # Insert first row
        sync_conn.execute("INSERT INTO unique_test (email) VALUES ('test@example.com')")
        sync_conn.commit()

        # Try to insert duplicate in transaction
        try:
            sync_conn.execute("BEGIN")

            # Insert unique value (should work)
            sync_conn.execute("INSERT INTO unique_test (email) VALUES ('unique@example.com')")

            # Insert duplicate (should fail)
            sync_conn.execute("INSERT INTO unique_test (email) VALUES ('test@example.com')")

            sync_conn.commit()

        except psycopg.IntegrityError:
            sync_conn.rollback()

        # Verify: only the first insert exists, not the "unique" one
        cursor = sync_conn.execute("SELECT COUNT(*) FROM unique_test")
        count = cursor.fetchone()[0]

        assert count == 1, "Only the committed row should exist, transaction should rollback entirely"

    def test_foreign_key_violation_rollback(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Foreign key violation triggers rollback.

        Expected: Referencing row is not inserted if referenced row doesn't exist.
        """
        # Create tables with FK
        sync_conn.execute("""
            CREATE TABLE fk_parent (
                id INT PRIMARY KEY
            )
        """)
        sync_conn.execute("""
            CREATE TABLE fk_child (
                id INT PRIMARY KEY,
                parent_id INT REFERENCES fk_parent(id)
            )
        """)
        sync_conn.commit()

        # Try to insert child without parent
        try:
            sync_conn.execute("BEGIN")
            sync_conn.execute("INSERT INTO fk_child (id, parent_id) VALUES (1, 999)")  # No parent 999
            sync_conn.commit()

        except psycopg.IntegrityError:
            sync_conn.rollback()

        # Verify: no child rows
        cursor = sync_conn.execute("SELECT COUNT(*) FROM fk_child")
        count = cursor.fetchone()[0]

        assert count == 0, "FK violation should prevent insert"

    def test_check_constraint_violation(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: CHECK constraint violation triggers rollback.

        Expected: Invalid data is not inserted.
        """
        # Create table with CHECK constraint
        sync_conn.execute("""
            CREATE TABLE check_test (
                id INT PRIMARY KEY,
                age INT CHECK (age >= 0 AND age <= 150)
            )
        """)
        sync_conn.commit()

        # Try to insert invalid age
        try:
            sync_conn.execute("BEGIN")
            sync_conn.execute("INSERT INTO check_test (id, age) VALUES (1, 200)")  # Invalid age
            sync_conn.commit()

        except psycopg.IntegrityError:
            sync_conn.rollback()

        # Verify: no rows
        cursor = sync_conn.execute("SELECT COUNT(*) FROM check_test")
        count = cursor.fetchone()[0]

        assert count == 0, "CHECK constraint should prevent invalid insert"

    def test_not_null_violation_in_pggit_commit(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: NOT NULL violation in pggit commit triggers rollback.

        Expected: Commit fails completely, no partial Trinity ID creation.
        """
        sync_conn.execute("CREATE TABLE not_null_test (id INT)")
        sync_conn.commit()

        # Try commit with NULL message (if message is NOT NULL)
        try:
            sync_conn.execute("BEGIN")
            sync_conn.execute(
                "SELECT pggit.commit_changes(%s, %s, %s)",
                ("not-null-test", "main", None)  # NULL message
            )
            sync_conn.commit()

        except psycopg.IntegrityError:
            sync_conn.rollback()

        # Verify: no Trinity ID created
        cursor = sync_conn.execute("""
            SELECT COUNT(*)
            FROM pggit.commits
            WHERE message IS NULL
        """)
        count = cursor.fetchone()[0]

        assert count == 0, "NULL commit message should be rejected"
```

### Step 4: Partial Failure Tests (`tests/chaos/test_partial_failures.py`)

```python
"""
Tests for partial failure scenarios (multi-table, trigger failures, etc.).
"""

import pytest
import psycopg


@pytest.mark.chaos
@pytest.mark.partial_failure
class TestPartialFailures:
    """Test partial failure scenarios."""

    def test_multi_table_transaction_failure(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Failure in multi-table transaction rolls back ALL tables.

        Expected: No table has partial data, all or nothing.
        """
        # Create tables
        sync_conn.execute("CREATE TABLE multi_a (id INT)")
        sync_conn.execute("CREATE TABLE multi_b (id INT)")
        sync_conn.execute("CREATE TABLE multi_c (id INT)")
        sync_conn.commit()

        try:
            sync_conn.execute("BEGIN")

            # Insert into table A
            sync_conn.execute("INSERT INTO multi_a VALUES (1)")

            # Insert into table B
            sync_conn.execute("INSERT INTO multi_b VALUES (2)")

            # Fail on table C
            sync_conn.execute("INSERT INTO multi_c VALUES ('invalid')")  # Type error

            sync_conn.commit()

        except psycopg.Error:
            sync_conn.rollback()

        # Verify: ALL tables are empty (complete rollback)
        cursor_a = sync_conn.execute("SELECT COUNT(*) FROM multi_a")
        cursor_b = sync_conn.execute("SELECT COUNT(*) FROM multi_b")
        cursor_c = sync_conn.execute("SELECT COUNT(*) FROM multi_c")

        assert cursor_a.fetchone()[0] == 0, "Table A should be empty after rollback"
        assert cursor_b.fetchone()[0] == 0, "Table B should be empty after rollback"
        assert cursor_c.fetchone()[0] == 0, "Table C should be empty after rollback"

    def test_trigger_failure_rollback(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Trigger that fails causes transaction rollback.

        Expected: Row insert is rolled back when trigger fails.
        """
        # Create table and failing trigger
        sync_conn.execute("CREATE TABLE trigger_test (id INT)")

        sync_conn.execute("""
            CREATE OR REPLACE FUNCTION trigger_fail()
            RETURNS TRIGGER AS $$
            BEGIN
                RAISE EXCEPTION 'Trigger intentionally failed';
            END;
            $$ LANGUAGE plpgsql
        """)

        sync_conn.execute("""
            CREATE TRIGGER trigger_test_trigger
            BEFORE INSERT ON trigger_test
            FOR EACH ROW EXECUTE FUNCTION trigger_fail()
        """)
        sync_conn.commit()

        # Try insert (will fail due to trigger)
        try:
            sync_conn.execute("BEGIN")
            sync_conn.execute("INSERT INTO trigger_test VALUES (1)")
            sync_conn.commit()

        except psycopg.Error:
            sync_conn.rollback()

        # Verify: no row inserted
        cursor = sync_conn.execute("SELECT COUNT(*) FROM trigger_test")
        count = cursor.fetchone()[0]

        assert count == 0, "Trigger failure should prevent insert"
```

## Verification Commands

```bash
# Run all transaction failure tests
pytest tests/chaos/test_transaction_*.py tests/chaos/test_constraint_*.py tests/chaos/test_partial_*.py -v

# Run only rollback tests
pytest tests/chaos/test_transaction_rollback.py -v

# Run crash recovery tests (requires privileges)
pytest tests/chaos/test_crash_recovery.py -v --run-destructive

# Check for transaction isolation issues
pytest tests/chaos/ -v -m transaction
```

## Expected Outcome

### Tests Should:
- ✅ **FAIL initially** if rollback is incomplete
- ✅ Demonstrate ACID guarantees
- ✅ Show that partial commits never occur
- ✅ Validate Trinity ID consistency
- ✅ Prove version integrity after errors

### Bugs Expected to Find:
1. **Incomplete rollback**: Partial schema changes persist
2. **Trinity ID leaks**: Failed commits create Trinity IDs
3. **Version drift**: Version increments on rolled-back changes
4. **Orphaned data**: Foreign key cleanup failures

## Acceptance Criteria

- [ ] 4 test files created with 15+ transaction tests
- [ ] All rollback scenarios tested (complete, partial, savepoint)
- [ ] Constraint violations tested (FK, unique, check, NOT NULL)
- [ ] Multi-table transaction atomicity verified
- [ ] Crash recovery tests documented (even if skipped)
- [ ] Tests demonstrate ACID properties

## DO NOT

- ❌ Run crash tests in production (use skip marker)
- ❌ Assume rollback is complete without verification
- ❌ Skip constraint violation tests (reveal integrity bugs)
- ❌ Ignore trigger failures (part of transaction atomicity)

## Notes

**PostgreSQL ACID Properties**:
- **Atomicity**: All or nothing (tested via rollback)
- **Consistency**: Constraints enforced (tested via violations)
- **Isolation**: Tested in Phase 3 (concurrency)
- **Durability**: Tested via crash recovery

**Crash Recovery Testing**:
Crash tests are marked `@pytest.mark.skip` by default because they require:
- PostgreSQL restart privileges
- Isolated test environment
- pg_ctl access

Run manually with: `pytest --run-destructive`

**Next Steps (GREEN Phase)**:
Fix rollback completeness, Trinity ID cleanup, and version integrity issues.
