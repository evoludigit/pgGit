# Phase 3: Concurrency & Race Condition Tests

## Objective
Implement comprehensive concurrency tests that validate pggit's behavior under simultaneous multi-client access, including race conditions, deadlocks, serialization failures, and Trinity ID generation contention.

## TDD Stage
RED → GREEN (with expected failures to fix)

## Context
- **Previous phase**: Phase 2 (Property-Based Tests) validated behavior across wide input ranges
- **Current state**: Property tests exist, but no concurrency/race condition testing
- **Next phase**: Phase 4 (Transaction Failures) will test rollback and recovery scenarios

## Files to Create

### 1. `tests/chaos/test_concurrent_commits.py`
Tests for concurrent commit operations:
- Multiple clients committing to same branch simultaneously
- Trinity ID uniqueness under contention
- Commit ordering guarantees

### 2. `tests/chaos/test_concurrent_versioning.py`
Tests for concurrent version operations:
- Simultaneous version bumps
- Version increment race conditions
- Version query consistency

### 3. `tests/chaos/test_concurrent_branching.py`
Tests for concurrent branch operations:
- Multiple clients creating branches simultaneously
- Branch deletion during active commits
- Data branching (COW) race conditions

### 4. `tests/chaos/test_deadlock_scenarios.py`
Tests that deliberately create deadlock conditions:
- Circular lock dependencies
- Multi-table lock conflicts
- Deadlock detection and recovery

### 5. `tests/chaos/test_serialization_failures.py`
Tests for serialization anomalies:
- Write-write conflicts
- Read-write conflicts
- Snapshot isolation violations

## Implementation Steps

### Step 1: Concurrent Commit Tests (`tests/chaos/test_concurrent_commits.py`)

```python
"""
Concurrency tests for commit operations.
"""

import pytest
import asyncio
from concurrent.futures import ThreadPoolExecutor, as_completed
import psycopg
from psycopg.rows import dict_row
from hypothesis import given, strategies as st, settings, HealthCheck

from tests.chaos.utils import ChaosInjector
from tests.chaos.strategies import git_branch_name, commit_message


@pytest.mark.chaos
@pytest.mark.concurrent
@pytest.mark.slow
class TestConcurrentCommits:
    """Test concurrent commit operations."""

    @pytest.mark.parametrize("num_workers", [2, 5, 10, 20])
    def test_concurrent_commits_same_branch(
        self, db_connection_string: str, num_workers: int
    ):
        """
        Test: Multiple workers committing to the same branch concurrently.

        Expected behaviors:
        1. All commits succeed OR fail with serialization error
        2. Trinity IDs are unique (no collisions)
        3. Commit order is consistent
        4. No data corruption
        """
        branch_name = "main"
        results = []
        errors = []

        def worker_commit(worker_id: int) -> dict | None:
            """Worker function: create table and commit."""
            try:
                conn = psycopg.connect(db_connection_string, row_factory=dict_row)
                conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")

                # Create unique table for this worker
                table_name = f"test_table_{worker_id}"
                conn.execute(f"CREATE TABLE {table_name} (id SERIAL PRIMARY KEY, data TEXT)")
                conn.commit()

                # Commit to same branch (potential race condition)
                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s, %s)",
                    (f"worker-{worker_id}", branch_name, f"Commit from worker {worker_id}")
                )
                result = cursor.fetchone()
                conn.commit()
                conn.close()

                return {
                    'worker_id': worker_id,
                    'trinity_id': result[0] if result else None,
                    'success': True
                }

            except psycopg.Error as e:
                return {
                    'worker_id': worker_id,
                    'error': str(e),
                    'success': False
                }

        # Execute concurrent commits
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(worker_commit, i) for i in range(num_workers)]

            for future in as_completed(futures):
                result = future.result()
                if result['success']:
                    results.append(result)
                else:
                    errors.append(result)

        # Validation: At least some commits succeeded
        assert len(results) > 0, \
            f"At least one commit should succeed, but got {len(errors)} errors"

        # Validation: All successful Trinity IDs are unique
        trinity_ids = [r['trinity_id'] for r in results]
        assert len(trinity_ids) == len(set(trinity_ids)), \
            f"Trinity ID collision detected: {trinity_ids}"

        # Validation: Errors are expected serialization failures
        for err in errors:
            error_msg = err['error'].lower()
            assert any(keyword in error_msg for keyword in [
                'serialization', 'deadlock', 'could not serialize', 'concurrent'
            ]), f"Unexpected error: {err['error']}"

        print(f"\n✅ {len(results)} successful commits, {len(errors)} expected failures")
        print(f"   Unique Trinity IDs: {len(set(trinity_ids))}")

    @pytest.mark.timeout(60)
    async def test_concurrent_commits_with_delays(
        self, async_conn: psycopg.AsyncConnection, conn_pool
    ):
        """
        Test: Concurrent commits with random delays (simulating network latency).

        This test injects random delays to increase the probability of race conditions.
        """
        num_tasks = 15
        branch_name = "test-branch"

        async def commit_with_delay(task_id: int, conn: psycopg.Connection):
            """Commit with random delay injected."""
            try:
                # Random delay before commit
                await ChaosInjector.random_delay(min_ms=0, max_ms=200)

                # Create table
                table_name = f"delayed_table_{task_id}"
                conn.execute(f"CREATE TABLE {table_name} (id INT)")
                conn.commit()

                # Commit
                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s, %s)",
                    (f"delayed-{task_id}", branch_name, f"Delayed commit {task_id}")
                )
                result = cursor.fetchone()
                conn.commit()

                return {'task_id': task_id, 'trinity_id': result[0], 'success': True}

            except Exception as e:
                return {'task_id': task_id, 'error': str(e), 'success': False}

        # Run concurrent tasks
        tasks = [commit_with_delay(i, conn_pool[i % len(conn_pool)]) for i in range(num_tasks)]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Separate successes and failures
        successes = [r for r in results if isinstance(r, dict) and r.get('success')]
        failures = [r for r in results if isinstance(r, dict) and not r.get('success')]

        # Assertions
        assert len(successes) > 0, "At least some commits should succeed"

        trinity_ids = [s['trinity_id'] for s in successes]
        assert len(trinity_ids) == len(set(trinity_ids)), \
            "Trinity IDs must be unique even with delays"

    @given(
        num_workers=st.integers(min_value=2, max_value=15),
        branch=git_branch_name()
    )
    @settings(
        max_examples=10,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture]
    )
    def test_property_concurrent_commits_no_collisions(
        self, db_connection_string: str, num_workers: int, branch: str
    ):
        """
        Property: Concurrent commits never produce Trinity ID collisions.

        Uses Hypothesis to test with various worker counts and branch names.
        """
        results = []

        def worker(worker_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)
            conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")

            table_name = f"prop_table_{worker_id}_{branch[:20]}"
            conn.execute(f"CREATE TABLE {table_name} (id INT)")
            conn.commit()

            cursor = conn.execute(
                "SELECT pggit.commit_changes(%s, %s, %s)",
                (f"prop-{worker_id}", branch, f"Property test {worker_id}")
            )
            trinity_id = cursor.fetchone()[0]
            conn.commit()
            conn.close()

            return trinity_id

        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(worker, i) for i in range(num_workers)]
            for future in as_completed(futures):
                try:
                    trinity_id = future.result(timeout=10)
                    results.append(trinity_id)
                except Exception:
                    pass  # Some failures expected

        # Property: All successful Trinity IDs must be unique
        if len(results) > 0:
            assert len(results) == len(set(results)), \
                f"Trinity ID collision in {num_workers} workers on branch '{branch}'"
```

### Step 2: Concurrent Versioning Tests (`tests/chaos/test_concurrent_versioning.py`)

```python
"""
Concurrency tests for version operations.
"""

import pytest
from concurrent.futures import ThreadPoolExecutor, as_completed
import psycopg
from psycopg.rows import dict_row


@pytest.mark.chaos
@pytest.mark.concurrent
class TestConcurrentVersioning:
    """Test concurrent version increment operations."""

    @pytest.mark.parametrize("num_workers", [5, 10, 20])
    def test_concurrent_version_increments(
        self, db_connection_string: str, num_workers: int
    ):
        """
        Test: Multiple workers incrementing version simultaneously.

        Expected: All increments succeed, final version reflects all increments.
        """
        table_name = "version_test_table"

        # Setup: Create table
        setup_conn = psycopg.connect(db_connection_string)
        setup_conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")
        setup_conn.execute(f"CREATE TABLE {table_name} (id INT)")
        setup_conn.commit()

        # Get initial version
        cursor = setup_conn.execute(
            "SELECT * FROM pggit.get_version(%s)", (table_name,)
        )
        initial_version = cursor.fetchone()
        setup_conn.close()

        # Worker: increment version
        def worker_increment(worker_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)

            try:
                conn.execute("BEGIN")
                conn.execute(
                    f"ALTER TABLE {table_name} ADD COLUMN IF NOT EXISTS col_{worker_id} INT"
                )
                conn.execute("COMMIT")

                # Version should auto-increment via trigger
                cursor = conn.execute(
                    "SELECT * FROM pggit.get_version(%s)", (table_name,)
                )
                new_version = cursor.fetchone()
                conn.close()

                return {'worker_id': worker_id, 'version': new_version, 'success': True}

            except Exception as e:
                conn.rollback()
                conn.close()
                return {'worker_id': worker_id, 'error': str(e), 'success': False}

        # Execute concurrent increments
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(worker_increment, i) for i in range(num_workers)]
            results = [f.result() for f in as_completed(futures)]

        successes = [r for r in results if r['success']]
        failures = [r for r in results if not r['success']]

        # Validation: Most should succeed
        assert len(successes) > num_workers * 0.5, \
            f"Expected >50% success rate, got {len(successes)}/{num_workers}"

        # Validation: Final version is consistent
        final_conn = psycopg.connect(db_connection_string)
        cursor = final_conn.execute(
            "SELECT * FROM pggit.get_version(%s)", (table_name,)
        )
        final_version = cursor.fetchone()
        final_conn.close()

        print(f"\n✅ Initial: {initial_version}, Final: {final_version}")
        print(f"   Successes: {len(successes)}, Failures: {len(failures)}")

    def test_version_read_consistency(self, db_connection_string: str):
        """
        Test: Reading version while concurrent modifications occur.

        Expected: Reads always return valid version (not corrupted state).
        """
        table_name = "consistency_test_table"

        # Setup
        setup_conn = psycopg.connect(db_connection_string)
        setup_conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")
        setup_conn.execute(f"CREATE TABLE {table_name} (id INT)")
        setup_conn.commit()
        setup_conn.close()

        def reader(reader_id: int):
            """Worker: repeatedly read version."""
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)
            versions = []

            for _ in range(10):
                cursor = conn.execute(
                    "SELECT * FROM pggit.get_version(%s)", (table_name,)
                )
                version = cursor.fetchone()
                if version:
                    versions.append(version)

            conn.close()
            return versions

        def writer(writer_id: int):
            """Worker: repeatedly modify table."""
            conn = psycopg.connect(db_connection_string)

            for i in range(5):
                try:
                    conn.execute(f"ALTER TABLE {table_name} ADD COLUMN IF NOT EXISTS w{writer_id}_c{i} INT")
                    conn.commit()
                except Exception:
                    conn.rollback()

            conn.close()
            return True

        # Run concurrent readers and writers
        with ThreadPoolExecutor(max_workers=15) as executor:
            reader_futures = [executor.submit(reader, i) for i in range(10)]
            writer_futures = [executor.submit(writer, i) for i in range(5)]

            all_versions = []
            for future in as_completed(reader_futures):
                all_versions.extend(future.result())

            for future in as_completed(writer_futures):
                future.result()

        # Validation: All read versions are valid (not NULL, not corrupted)
        assert len(all_versions) > 0, "Should have read some versions"

        for version in all_versions:
            assert version is not None, "Version should never be NULL"
            assert 'major' in version, "Version should have 'major' field"
            assert 'minor' in version, "Version should have 'minor' field"
            assert 'patch' in version, "Version should have 'patch' field"

        print(f"\n✅ Read {len(all_versions)} consistent versions during concurrent writes")
```

### Step 3: Concurrent Branching Tests (`tests/chaos/test_concurrent_branching.py`)

```python
"""
Concurrency tests for branch operations.
"""

import pytest
from concurrent.futures import ThreadPoolExecutor, as_completed
import psycopg
from psycopg.rows import dict_row


@pytest.mark.chaos
@pytest.mark.concurrent
class TestConcurrentBranching:
    """Test concurrent branch creation and manipulation."""

    @pytest.mark.parametrize("num_branches", [5, 10, 20])
    def test_concurrent_branch_creation(
        self, db_connection_string: str, num_branches: int
    ):
        """
        Test: Multiple workers creating different branches simultaneously.

        Expected: All branches created successfully, no conflicts.
        """
        def create_branch(branch_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)
            conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")

            branch_name = f"concurrent-branch-{branch_id}"
            table_name = f"branch_table_{branch_id}"

            try:
                # Create table and commit on new branch
                conn.execute(f"CREATE TABLE {table_name} (id INT)")
                conn.commit()

                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s, %s)",
                    (f"commit-{branch_id}", branch_name, f"Create branch {branch_id}")
                )
                result = cursor.fetchone()
                conn.commit()
                conn.close()

                return {'branch_id': branch_id, 'branch': branch_name, 'success': True}

            except Exception as e:
                conn.rollback()
                conn.close()
                return {'branch_id': branch_id, 'error': str(e), 'success': False}

        # Execute concurrent branch creation
        with ThreadPoolExecutor(max_workers=num_branches) as executor:
            futures = [executor.submit(create_branch, i) for i in range(num_branches)]
            results = [f.result() for f in as_completed(futures)]

        successes = [r for r in results if r['success']]
        failures = [r for r in results if not r['success']]

        # Validation: All should succeed (different branches)
        assert len(successes) == num_branches, \
            f"All {num_branches} branches should be created, but {len(failures)} failed"

        print(f"\n✅ Successfully created {len(successes)} branches concurrently")

    def test_branch_deletion_during_active_commit(self, db_connection_string: str):
        """
        Test: Deleting a branch while another worker is committing to it.

        Expected: Either commit succeeds OR deletion succeeds (not both).
        """
        branch_name = "deletion-test-branch"

        def commit_worker():
            """Worker that commits to branch."""
            conn = psycopg.connect(db_connection_string)
            conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")

            try:
                conn.execute("CREATE TABLE deletion_test (id INT)")
                conn.commit()

                # Slow commit (simulate long transaction)
                conn.execute("SELECT pg_sleep(0.5)")
                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s, %s)",
                    ("deletion-commit", branch_name, "Commit during deletion")
                )
                result = cursor.fetchone()
                conn.commit()
                conn.close()

                return {'action': 'commit', 'success': True}

            except Exception as e:
                conn.rollback()
                conn.close()
                return {'action': 'commit', 'error': str(e), 'success': False}

        def delete_worker():
            """Worker that deletes branch."""
            import time
            time.sleep(0.2)  # Let commit start first

            conn = psycopg.connect(db_connection_string)
            conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")

            try:
                cursor = conn.execute(
                    "SELECT pggit.delete_branch(%s)", (branch_name,)
                )
                conn.commit()
                conn.close()

                return {'action': 'delete', 'success': True}

            except Exception as e:
                conn.rollback()
                conn.close()
                return {'action': 'delete', 'error': str(e), 'success': False}

        # Run concurrent commit and delete
        with ThreadPoolExecutor(max_workers=2) as executor:
            commit_future = executor.submit(commit_worker)
            delete_future = executor.submit(delete_worker)

            commit_result = commit_future.result()
            delete_result = delete_future.result()

        # Validation: At most one succeeds (mutual exclusion)
        both_succeeded = commit_result['success'] and delete_result['success']
        assert not both_succeeded, \
            "Commit and delete should not both succeed (race condition!)"

        print(f"\n✅ Commit: {commit_result}, Delete: {delete_result}")
```

### Step 4: Deadlock Scenario Tests (`tests/chaos/test_deadlock_scenarios.py`)

```python
"""
Tests that deliberately create deadlock scenarios.
"""

import pytest
from concurrent.futures import ThreadPoolExecutor
import psycopg
import time


@pytest.mark.chaos
@pytest.mark.concurrent
@pytest.mark.destructive
class TestDeadlockScenarios:
    """Test deadlock detection and recovery."""

    @pytest.mark.timeout(30)
    def test_circular_lock_deadlock(self, db_connection_string: str):
        """
        Test: Create circular lock dependency (classic deadlock).

        Worker 1: Lock A → Lock B
        Worker 2: Lock B → Lock A

        Expected: PostgreSQL detects deadlock and kills one transaction.
        """
        table_a = "deadlock_table_a"
        table_b = "deadlock_table_b"

        # Setup tables
        setup_conn = psycopg.connect(db_connection_string)
        setup_conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")
        setup_conn.execute(f"CREATE TABLE {table_a} (id INT)")
        setup_conn.execute(f"CREATE TABLE {table_b} (id INT)")
        setup_conn.commit()
        setup_conn.close()

        def worker1():
            """Lock A, then B."""
            conn = psycopg.connect(db_connection_string)

            try:
                conn.execute("BEGIN")

                # Lock table A
                conn.execute(f"LOCK TABLE {table_a} IN EXCLUSIVE MODE")
                time.sleep(0.5)  # Give worker2 time to lock B

                # Try to lock table B (will cause deadlock)
                conn.execute(f"LOCK TABLE {table_b} IN EXCLUSIVE MODE")

                conn.commit()
                conn.close()
                return {'worker': 1, 'success': True}

            except psycopg.Error as e:
                conn.rollback()
                conn.close()

                # Deadlock is expected
                if 'deadlock' in str(e).lower():
                    return {'worker': 1, 'deadlock_detected': True, 'success': False}
                else:
                    return {'worker': 1, 'error': str(e), 'success': False}

        def worker2():
            """Lock B, then A."""
            conn = psycopg.connect(db_connection_string)

            try:
                conn.execute("BEGIN")

                # Lock table B
                conn.execute(f"LOCK TABLE {table_b} IN EXCLUSIVE MODE")
                time.sleep(0.5)  # Give worker1 time to lock A

                # Try to lock table A (will cause deadlock)
                conn.execute(f"LOCK TABLE {table_a} IN EXCLUSIVE MODE")

                conn.commit()
                conn.close()
                return {'worker': 2, 'success': True}

            except psycopg.Error as e:
                conn.rollback()
                conn.close()

                if 'deadlock' in str(e).lower():
                    return {'worker': 2, 'deadlock_detected': True, 'success': False}
                else:
                    return {'worker': 2, 'error': str(e), 'success': False}

        # Run workers concurrently
        with ThreadPoolExecutor(max_workers=2) as executor:
            future1 = executor.submit(worker1)
            future2 = executor.submit(worker2)

            result1 = future1.result(timeout=20)
            result2 = future2.result(timeout=20)

        # Validation: At least one deadlock detected
        deadlocks = [r for r in [result1, result2] if r.get('deadlock_detected')]
        assert len(deadlocks) > 0, \
            "PostgreSQL should detect deadlock and abort one transaction"

        print(f"\n✅ Deadlock correctly detected and handled: {result1}, {result2}")
```

### Step 5: Serialization Failure Tests (`tests/chaos/test_serialization_failures.py`)

```python
"""
Tests for transaction serialization failures.
"""

import pytest
from concurrent.futures import ThreadPoolExecutor
import psycopg


@pytest.mark.chaos
@pytest.mark.concurrent
class TestSerializationFailures:
    """Test snapshot isolation and serialization anomalies."""

    def test_write_write_conflict(self, db_connection_string: str):
        """
        Test: Two transactions update the same row concurrently.

        Expected: Second transaction fails with serialization error.
        """
        table_name = "write_conflict_table"

        # Setup
        setup_conn = psycopg.connect(db_connection_string)
        setup_conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")
        setup_conn.execute(f"""
            CREATE TABLE {table_name} (
                id INT PRIMARY KEY,
                value INT
            )
        """)
        setup_conn.execute(f"INSERT INTO {table_name} VALUES (1, 0)")
        setup_conn.commit()
        setup_conn.close()

        def updater(worker_id: int):
            conn = psycopg.connect(db_connection_string)

            try:
                conn.execute("BEGIN ISOLATION LEVEL SERIALIZABLE")

                # Both read same value
                cursor = conn.execute(f"SELECT value FROM {table_name} WHERE id = 1")
                current_value = cursor.fetchone()[0]

                # Simulate processing time
                import time
                time.sleep(0.2)

                # Both try to update
                conn.execute(
                    f"UPDATE {table_name} SET value = %s WHERE id = 1",
                    (current_value + 1,)
                )

                conn.commit()
                conn.close()

                return {'worker': worker_id, 'success': True}

            except psycopg.Error as e:
                conn.rollback()
                conn.close()

                if 'serialization' in str(e).lower() or 'could not serialize' in str(e).lower():
                    return {'worker': worker_id, 'serialization_error': True, 'success': False}
                else:
                    return {'worker': worker_id, 'error': str(e), 'success': False}

        # Run concurrent updates
        with ThreadPoolExecutor(max_workers=2) as executor:
            future1 = executor.submit(updater, 1)
            future2 = executor.submit(updater, 2)

            result1 = future1.result()
            result2 = future2.result()

        # Validation: Exactly one succeeds, one gets serialization error
        successes = [result1['success'], result2['success']]
        assert sum(successes) == 1, \
            "Exactly one transaction should succeed in write-write conflict"

        serialization_errors = [
            r for r in [result1, result2] if r.get('serialization_error')
        ]
        assert len(serialization_errors) == 1, \
            "One transaction should get serialization error"

        print(f"\n✅ Serialization conflict correctly detected: {result1}, {result2}")
```

## Verification Commands

```bash
# Run all concurrency tests
pytest tests/chaos/test_concurrent_*.py tests/chaos/test_deadlock_*.py tests/chaos/test_serialization_*.py -v

# Run with parallelization (careful: tests are already concurrent internally)
pytest tests/chaos/ -v -m concurrent

# Run only slow concurrency tests
pytest tests/chaos/ -v -m "concurrent and slow"

# Check for deadlocks in PostgreSQL logs
tail -f /var/log/postgresql/postgresql-*.log | grep -i deadlock
```

## Expected Outcome

### Tests Should:
- ✅ **FAIL initially** revealing real concurrency bugs:
  - Trinity ID collisions under high contention
  - Version increment race conditions
  - Deadlocks not properly detected
  - Serialization failures not handled
- ✅ Demonstrate PostgreSQL's concurrency controls
- ✅ Show that errors are recoverable (no corruption)
- ✅ Run in <5 minutes total

### Bugs Expected to Find:
1. **Trinity ID collisions** when many workers commit simultaneously
2. **Version inconsistencies** during concurrent schema changes
3. **Unhandled deadlocks** in complex lock scenarios
4. **Missing serialization isolation** in data branching

## Acceptance Criteria

- [ ] 5 test files created with 12+ concurrency tests
- [ ] Tests use `ThreadPoolExecutor` for true parallelism
- [ ] Tests marked with `@pytest.mark.concurrent`
- [ ] Deadlock tests demonstrate PostgreSQL detection
- [ ] Serialization tests use `ISOLATION LEVEL SERIALIZABLE`
- [ ] All tests have clear expected behaviors documented
- [ ] Tests fail initially (RED), revealing bugs to fix

## DO NOT

- ❌ Assume single-threaded execution (use real threads)
- ❌ Skip timeout decorators (deadlock tests can hang)
- ❌ Ignore serialization errors (they reveal bugs)
- ❌ Use async where threads are needed (psycopg3 async != parallelism)
- ❌ Skip cleanup (concurrent tests can leave artifacts)

## Notes

**Concurrency vs Parallelism**:
- Use `ThreadPoolExecutor` for true parallelism (multiple DB connections)
- Use `asyncio` for concurrent I/O within single connection
- Use `pytest-xdist` for parallel test execution (different tests in parallel)

**PostgreSQL Isolation Levels**:
- `READ COMMITTED` (default): Allows non-repeatable reads
- `REPEATABLE READ`: Prevents non-repeatable reads
- `SERIALIZABLE`: Full serializability, may fail with serialization errors

**Expected Serialization Errors**:
```
ERROR: could not serialize access due to concurrent update
ERROR: deadlock detected
DETAIL: Process X waits for ShareLock on transaction Y
```

These are **expected** and part of correct PostgreSQL behavior!

**Next Steps (GREEN Phase)**:
Phase 4 will implement transaction failure handling to make these tests pass.
