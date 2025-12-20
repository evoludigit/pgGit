# Phase 5: Resource Exhaustion & Load Tests

## Objective
Implement tests that push pggit to system limits, including connection pool exhaustion, memory pressure, disk space constraints, and high-load scenarios to validate graceful degradation and error handling.

## TDD Stage
RED → GREEN

## Context
- **Previous phase**: Phase 4 (Transaction Failures) tested rollback and recovery
- **Current state**: ACID properties validated, but no resource limit testing
- **Next phase**: Phase 6 (Schema Corruption) will test migration failures

## Files to Create

### 1. `tests/chaos/test_connection_exhaustion.py`
Tests for connection pool limits:
- Max connections reached handling
- Connection leak detection
- Connection timeout behavior
- Pool exhaustion recovery

### 2. `tests/chaos/test_memory_pressure.py`
Tests under memory constraints:
- Large table versioning
- Large commit message handling
- Trinity ID generation at scale
- Memory-efficient operations

### 3. `tests/chaos/test_disk_space.py`
Tests for disk space exhaustion:
- Graceful handling when disk full
- Transaction rollback on disk full
- Trinity ID storage limits

### 4. `tests/chaos/test_load_stress.py`
High-load stress tests:
- 100+ concurrent connections
- Rapid commit generation
- Large-scale versioning
- Performance degradation analysis

## Implementation Steps

### Step 1: Connection Exhaustion Tests (`tests/chaos/test_connection_exhaustion.py`)

```python
"""
Connection pool exhaustion tests.
"""

import pytest
import psycopg
from psycopg_pool import ConnectionPool
from concurrent.futures import ThreadPoolExecutor, as_completed
import time


@pytest.mark.chaos
@pytest.mark.resource
@pytest.mark.slow
class TestConnectionExhaustion:
    """Test connection pool limit handling."""

    @pytest.mark.parametrize("max_connections", [5, 10, 20])
    def test_connection_pool_limit(
        self, db_connection_string: str, max_connections: int
    ):
        """
        Test: Requesting more connections than pool limit.

        Expected: Pool blocks or rejects new connections gracefully.
        """
        pool = ConnectionPool(
            db_connection_string,
            min_size=1,
            max_size=max_connections,
            timeout=5.0  # 5 second timeout
        )

        acquired_connections = []
        errors = []

        def acquire_and_hold(worker_id: int):
            """Acquire connection and hold it."""
            try:
                conn = pool.getconn(timeout=2.0)
                acquired_connections.append(worker_id)

                # Hold connection for a while
                cursor = conn.execute("SELECT pg_sleep(1)")
                cursor.fetchone()

                pool.putconn(conn)
                return {'worker': worker_id, 'success': True}

            except Exception as e:
                errors.append({'worker': worker_id, 'error': str(e)})
                return {'worker': worker_id, 'success': False}

        # Try to acquire more than max_connections
        num_workers = max_connections + 5

        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(acquire_and_hold, i) for i in range(num_workers)]
            results = [f.result(timeout=10) for f in as_completed(futures)]

        # Validation: Some requests succeeded, some timed out (gracefully)
        successes = [r for r in results if r['success']]

        assert len(successes) <= max_connections, \
            f"Can't have more than {max_connections} concurrent connections"

        # Errors should be timeout errors, not crashes
        for err in errors:
            assert 'timeout' in err['error'].lower() or 'pool' in err['error'].lower(), \
                f"Unexpected error: {err['error']}"

        pool.close()
        print(f"\n✅ Pool handled {num_workers} requests with limit {max_connections}")
        print(f"   Successes: {len(successes)}, Timeouts: {len(errors)}")

    def test_connection_leak_detection(self, db_connection_string: str):
        """
        Test: Detect connections that aren't returned to pool.

        Expected: Pool can identify and recover from leaked connections.
        """
        pool = ConnectionPool(
            db_connection_string,
            min_size=1,
            max_size=5,
            timeout=3.0
        )

        # Acquire connection but don't return it (leak)
        leaked_conn = pool.getconn()

        # Try to acquire more connections
        acquired = []
        for i in range(4):  # Pool size is 5, one is leaked
            try:
                conn = pool.getconn(timeout=2.0)
                acquired.append(conn)
            except Exception:
                break

        # Should acquire 4 more (total 5)
        assert len(acquired) == 4, "Should acquire up to pool limit minus leak"

        # Return acquired connections
        for conn in acquired:
            pool.putconn(conn)

        # Return leaked connection
        pool.putconn(leaked_conn)

        pool.close()

    @pytest.mark.timeout(60)
    def test_connection_timeout_behavior(self, db_connection_string: str):
        """
        Test: Connection request times out gracefully when pool exhausted.

        Expected: Timeout exception, not hang or crash.
        """
        pool = ConnectionPool(
            db_connection_string,
            min_size=1,
            max_size=2,
            timeout=1.0  # 1 second timeout
        )

        # Exhaust pool
        conn1 = pool.getconn()
        conn2 = pool.getconn()

        # Try to get third connection (should timeout)
        start = time.time()

        with pytest.raises(Exception) as exc_info:
            conn3 = pool.getconn(timeout=2.0)

        elapsed = time.time() - start

        # Should timeout quickly (within 3 seconds)
        assert elapsed < 3.0, f"Timeout took too long: {elapsed}s"
        assert 'timeout' in str(exc_info.value).lower(), \
            "Should raise timeout exception"

        # Cleanup
        pool.putconn(conn1)
        pool.putconn(conn2)
        pool.close()


@pytest.mark.chaos
@pytest.mark.resource
class TestConnectionRecovery:
    """Test recovery from connection issues."""

    def test_recovery_after_pool_exhaustion(self, db_connection_string: str):
        """
        Test: Pool recovers after exhaustion when connections are returned.

        Expected: New connections work after previous ones are released.
        """
        pool = ConnectionPool(db_connection_string, min_size=1, max_size=3)

        # Exhaust pool
        conn1 = pool.getconn()
        conn2 = pool.getconn()
        conn3 = pool.getconn()

        # Return connections
        pool.putconn(conn1)
        pool.putconn(conn2)
        pool.putconn(conn3)

        # Try to acquire again (should work)
        conn4 = pool.getconn()
        assert conn4 is not None, "Pool should recover after connections returned"

        pool.putconn(conn4)
        pool.close()
```

### Step 2: Memory Pressure Tests (`tests/chaos/test_memory_pressure.py`)

```python
"""
Tests under memory pressure.
"""

import pytest
import psycopg
from hypothesis import given, strategies as st, settings


@pytest.mark.chaos
@pytest.mark.resource
@pytest.mark.slow
class TestMemoryPressure:
    """Test behavior under memory pressure."""

    def test_large_table_versioning(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Version a table with many columns.

        Expected: Versioning handles large schemas without OOM.
        """
        # Create table with 100 columns
        columns = [f"col_{i} INT" for i in range(100)]
        create_sql = f"CREATE TABLE large_table ({', '.join(columns)})"

        sync_conn.execute(create_sql)
        sync_conn.commit()

        # Get version (should work without OOM)
        cursor = sync_conn.execute(
            "SELECT * FROM pggit.get_version(%s)", ("large_table",)
        )
        version = cursor.fetchone()

        assert version is not None, "Large table should be versioned"

    @given(message_size=st.integers(min_value=1000, max_value=100000))
    @settings(max_examples=10, deadline=None)
    def test_large_commit_message(
        self, sync_conn: psycopg.Connection, isolated_schema: str,
        message_size: int
    ):
        """
        Property: Commit handles large messages (up to 100KB).

        Expected: Large messages stored without truncation or error.
        """
        # Generate large message
        large_message = "A" * message_size

        # Create table and commit with large message
        sync_conn.execute("CREATE TABLE large_msg_test (id INT)")
        sync_conn.commit()

        try:
            cursor = sync_conn.execute(
                "SELECT pggit.commit_changes(%s, %s, %s)",
                ("large-msg", "main", large_message)
            )
            trinity_id = cursor.fetchone()[0]
            sync_conn.commit()

            # Verify message stored correctly
            cursor = sync_conn.execute(
                "SELECT message FROM pggit.commits WHERE trinity_id = %s",
                (trinity_id,)
            )
            stored_message = cursor.fetchone()[0]

            assert len(stored_message) == message_size, \
                f"Message should be {message_size} chars, got {len(stored_message)}"

            assert stored_message == large_message, "Message should not be truncated"

        except Exception as e:
            # If it fails, should be due to size limit, not crash
            assert 'too large' in str(e).lower() or 'limit' in str(e).lower(), \
                f"Unexpected error: {e}"

    def test_trinity_id_generation_at_scale(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Generate many Trinity IDs without memory issues.

        Expected: 1000+ Trinity IDs can be generated.
        """
        num_commits = 1000

        # Create table
        sync_conn.execute("CREATE TABLE scale_test (id INT)")
        sync_conn.commit()

        # Generate many commits
        for i in range(num_commits):
            sync_conn.execute(
                "SELECT pggit.commit_changes(%s, %s, %s)",
                (f"scale-{i}", "main", f"Commit {i}")
            )
            sync_conn.commit()

            if i % 100 == 0:
                print(f"Generated {i} commits...")

        # Verify all Trinity IDs exist
        cursor = sync_conn.execute("SELECT COUNT(*) FROM pggit.trinity_ids")
        count = cursor.fetchone()[0]

        assert count >= num_commits, \
            f"Should have at least {num_commits} Trinity IDs, got {count}"

        print(f"\n✅ Generated {count} Trinity IDs without memory issues")
```

### Step 3: Disk Space Tests (`tests/chaos/test_disk_space.py`)

```python
"""
Tests for disk space exhaustion scenarios.
"""

import pytest
import psycopg


@pytest.mark.chaos
@pytest.mark.resource
@pytest.mark.destructive
@pytest.mark.skip(reason="Requires ability to fill disk space")
class TestDiskSpace:
    """
    Test disk space exhaustion.

    WARNING: These tests simulate disk full conditions.
    Only run in isolated test environments!
    """

    def test_graceful_handling_disk_full(
        self, sync_conn: psycopg.Connection
    ):
        """
        Test: Behavior when disk is full during commit.

        Expected: Error raised, no corruption, transaction rolled back.
        """
        # This test requires:
        # 1. Small test partition
        # 2. Fill disk during test
        # 3. Verify pggit handles gracefully

        # Implementation depends on test environment setup
        pytest.skip("Requires disk space control")

    def test_transaction_rollback_on_disk_full(
        self, sync_conn: psycopg.Connection
    ):
        """
        Test: Transaction rolls back completely when disk fills.

        Expected: No partial writes, clean rollback.
        """
        pytest.skip("Requires disk space control")
```

### Step 4: Load Stress Tests (`tests/chaos/test_load_stress.py`)

```python
"""
High-load stress tests.
"""

import pytest
import psycopg
from concurrent.futures import ThreadPoolExecutor, as_completed
import time


@pytest.mark.chaos
@pytest.mark.load
@pytest.mark.slow
class TestLoadStress:
    """High-load stress tests."""

    @pytest.mark.timeout(300)  # 5 minutes
    def test_100_concurrent_connections(self, db_connection_string: str):
        """
        Test: 100 concurrent connections performing commits.

        Expected: System handles load, degrades gracefully if overloaded.
        """
        num_workers = 100
        results = []
        errors = []

        def worker(worker_id: int):
            """Worker: connect, create table, commit."""
            start = time.time()

            try:
                conn = psycopg.connect(db_connection_string)
                conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")

                table_name = f"load_test_{worker_id}"
                conn.execute(f"CREATE TABLE {table_name} (id INT)")
                conn.commit()

                cursor = conn.execute(
                    "SELECT pggit.commit_changes(%s, %s, %s)",
                    (f"load-{worker_id}", f"branch-{worker_id % 10}", f"Load test {worker_id}")
                )
                result = cursor.fetchone()
                conn.commit()
                conn.close()

                elapsed = time.time() - start

                return {
                    'worker': worker_id,
                    'success': True,
                    'elapsed': elapsed,
                    'trinity_id': result[0] if result else None
                }

            except Exception as e:
                elapsed = time.time() - start
                return {
                    'worker': worker_id,
                    'success': False,
                    'error': str(e),
                    'elapsed': elapsed
                }

        # Execute load test
        print("\n🔥 Starting 100-connection load test...")

        with ThreadPoolExecutor(max_workers=100) as executor:
            futures = [executor.submit(worker, i) for i in range(num_workers)]

            for future in as_completed(futures):
                result = future.result()

                if result['success']:
                    results.append(result)
                else:
                    errors.append(result)

        # Analysis
        success_rate = len(results) / num_workers
        avg_time = sum(r['elapsed'] for r in results) / len(results) if results else 0
        max_time = max(r['elapsed'] for r in results) if results else 0

        print(f"\n✅ Load test results:")
        print(f"   Success rate: {success_rate:.1%} ({len(results)}/{num_workers})")
        print(f"   Average time: {avg_time:.2f}s")
        print(f"   Max time: {max_time:.2f}s")
        print(f"   Errors: {len(errors)}")

        # Validation: At least 80% success rate
        assert success_rate >= 0.8, \
            f"Success rate should be >= 80%, got {success_rate:.1%}"

        # Trinity IDs should be unique
        trinity_ids = [r['trinity_id'] for r in results]
        assert len(trinity_ids) == len(set(trinity_ids)), \
            "Trinity IDs must be unique under load"

    @pytest.mark.timeout(120)
    def test_rapid_commit_generation(self, db_connection_string: str):
        """
        Test: Generate commits as fast as possible.

        Expected: No crashes, consistent behavior, performance metrics.
        """
        num_commits = 500
        conn = psycopg.connect(db_connection_string)
        conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")

        # Create table
        conn.execute("CREATE TABLE rapid_commit_test (id INT)")
        conn.commit()

        # Rapid commits
        start = time.time()

        for i in range(num_commits):
            conn.execute(
                "SELECT pggit.commit_changes(%s, %s, %s)",
                (f"rapid-{i}", "main", f"Rapid commit {i}")
            )
            conn.commit()

        elapsed = time.time() - start
        commits_per_second = num_commits / elapsed

        print(f"\n✅ Rapid commit test:")
        print(f"   {num_commits} commits in {elapsed:.2f}s")
        print(f"   {commits_per_second:.1f} commits/second")

        conn.close()

    def test_performance_degradation_analysis(self, db_connection_string: str):
        """
        Test: Measure performance as database grows.

        Expected: Performance degrades linearly, not exponentially.
        """
        conn = psycopg.connect(db_connection_string)
        conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")

        conn.execute("CREATE TABLE perf_test (id INT)")
        conn.commit()

        # Measure commit time at different scales
        measurements = []

        for batch in range(10):
            batch_start = time.time()

            # 50 commits per batch
            for i in range(50):
                commit_id = batch * 50 + i
                conn.execute(
                    "SELECT pggit.commit_changes(%s, %s, %s)",
                    (f"perf-{commit_id}", "main", f"Perf test {commit_id}")
                )
                conn.commit()

            batch_time = time.time() - batch_start
            measurements.append(batch_time)

            print(f"Batch {batch}: {batch_time:.2f}s (total commits: {(batch + 1) * 50})")

        # Analysis: Check for exponential degradation
        first_batch = measurements[0]
        last_batch = measurements[-1]
        degradation_factor = last_batch / first_batch

        print(f"\n📊 Performance degradation: {degradation_factor:.2f}x")

        # Validation: Less than 3x degradation over 500 commits
        assert degradation_factor < 3.0, \
            f"Performance degraded too much: {degradation_factor:.2f}x"

        conn.close()
```

## Verification Commands

```bash
# Run resource exhaustion tests
pytest tests/chaos/test_connection_*.py tests/chaos/test_memory_*.py -v

# Run load tests (slow)
pytest tests/chaos/test_load_*.py -v -m load

# Run with resource monitoring
pytest tests/chaos/test_memory_pressure.py -v --show-capture=no

# Skip destructive disk tests
pytest tests/chaos/ -v -m "resource and not destructive"
```

## Expected Outcome

### Tests Should:
- ✅ **FAIL initially** if connection limits aren't handled
- ✅ Demonstrate graceful degradation under load
- ✅ Show performance characteristics
- ✅ Validate connection pool behavior
- ✅ Measure memory efficiency

### Bugs Expected to Find:
1. **Connection leaks**: Connections not returned to pool
2. **Memory leaks**: Trinity ID storage grows unbounded
3. **Poor scalability**: Exponential performance degradation
4. **Crash on OOM**: No graceful handling of memory pressure

## Acceptance Criteria

- [ ] 4 test files created with resource/load tests
- [ ] Connection pool exhaustion tested (5, 10, 20 limit)
- [ ] Memory pressure tested (large tables, messages)
- [ ] Load tests demonstrate 100+ concurrent connections
- [ ] Performance metrics collected and validated
- [ ] Graceful degradation verified
- [ ] Destructive tests properly marked/skipped

## DO NOT

- ❌ Run disk space tests on production systems
- ❌ Exhaust system resources without limits
- ❌ Skip timeout decorators on load tests
- ❌ Assume infinite resources available
- ❌ Ignore performance metrics (collect and analyze)

## Notes

**Resource Limits**:
- PostgreSQL default max_connections: 100
- Connection pool size: Typically 10-50
- Commit message typical limit: 1MB
- Memory per connection: ~10MB

**Load Testing Best Practices**:
- Start with small loads (10 connections)
- Gradually increase to find limits
- Monitor PostgreSQL metrics (pg_stat_activity)
- Use connection pooling (psycopg_pool)

**Performance Baselines**:
- Simple commit: <100ms
- 100 concurrent commits: <10s total
- 1000 commits sequential: <60s

**Next Steps (GREEN Phase)**:
Optimize connection handling, add connection pooling, improve memory efficiency.
