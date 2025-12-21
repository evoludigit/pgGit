# Chaos Engineering Patterns

Common patterns for writing chaos engineering tests. Each pattern includes the problem, solution, and explanation.

## Pattern 1: Property-Based Trinity ID Uniqueness

**Problem**: Ensure Trinity IDs are always unique, regardless of inputs

**Solution**:
```python
import pytest
from hypothesis import given, strategies as st
from tests.chaos.strategies import git_branch_name, commit_message

@pytest.mark.chaos
@pytest.mark.property
@given(
    branch=git_branch_name(),
    msg=commit_message()
)
def test_trinity_id_always_unique(sync_conn, isolated_schema, branch: str, msg: str):
    """Property: Every commit gets a unique Trinity ID."""
    # Create table
    sync_conn.execute("CREATE TABLE test_table (id INT)")
    sync_conn.commit()

    # First commit
    cursor1 = sync_conn.execute(
        "SELECT pggit.commit_changes(%s, %s, %s)",
        ("commit-1", branch, msg)
    )
    trinity_id_1 = cursor1.fetchone()[0]
    sync_conn.commit()

    # Second commit
    cursor2 = sync_conn.execute(
        "SELECT pggit.commit_changes(%s, %s, %s)",
        ("commit-2", branch, msg)
    )
    trinity_id_2 = cursor2.fetchone()[0]
    sync_conn.commit()

    # Property: Must be different
    assert trinity_id_1 != trinity_id_2, "Trinity IDs must be unique"
```

**Why it works**: Hypothesis generates hundreds of branch/message combinations, catching edge cases like very long names, unicode characters, empty messages, and max-length inputs.

---

## Pattern 2: Concurrent Operations Without Collisions

**Problem**: Multiple workers operating simultaneously should not create collisions

**Solution**:
```python
import pytest
from concurrent.futures import ThreadPoolExecutor, as_completed
import psycopg

@pytest.mark.chaos
@pytest.mark.concurrent
@pytest.mark.parametrize("num_workers", [5, 10, 20])
def test_concurrent_commits_no_collisions(db_connection_string: str, num_workers: int):
    """Test: N concurrent commits create N unique Trinity IDs."""

    def worker(worker_id: int):
        """Worker: create table and commit."""
        conn = psycopg.connect(db_connection_string)
        conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")

        table_name = f"table_{worker_id}"
        conn.execute(f"CREATE TABLE {table_name} (id INT)")
        conn.commit()

        cursor = conn.execute(
            "SELECT pggit.commit_changes(%s, %s, %s)",
            (f"commit-{worker_id}", "main", f"Worker {worker_id}")
        )
        trinity_id = cursor.fetchone()[0]
        conn.commit()
        conn.close()

        return trinity_id

    # Run concurrent workers
    with ThreadPoolExecutor(max_workers=num_workers) as executor:
        futures = [executor.submit(worker, i) for i in range(num_workers)]
        trinity_ids = [f.result() for f in as_completed(futures)]

    # Validation: All unique
    assert len(trinity_ids) == len(set(trinity_ids)), \
        f"Found {len(trinity_ids) - len(set(trinity_ids))} collisions!"
```

**Why it works**: Real parallelism via threads exposes race conditions in Trinity ID generation that synchronous tests miss.

---

## Pattern 3: Complete Rollback on Error

**Problem**: Ensure transactions rollback completely, not partially

**Solution**:
```python
import pytest
from tests.chaos.utils import DatabaseStateSnapshot

@pytest.mark.chaos
@pytest.mark.transaction
def test_complete_rollback(sync_conn, isolated_schema):
    """Test: Transaction errors rollback ALL changes."""

    # Capture state before
    snapshot = DatabaseStateSnapshot(sync_conn)
    snapshot.capture("before", "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = current_schema()")

    try:
        sync_conn.execute("BEGIN")

        # Multiple operations
        sync_conn.execute("CREATE TABLE table1 (id INT)")
        sync_conn.execute("CREATE TABLE table2 (id INT)")
        sync_conn.execute("CREATE TABLE table3 (id INT)")

        # Cause error
        sync_conn.execute("INVALID SQL")

        sync_conn.commit()

    except psycopg.Error:
        sync_conn.rollback()

    # Verify complete rollback
    matches, msg = snapshot.compare("before", "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = current_schema()")

    assert matches, f"Rollback should be complete: {msg}"
```

**Why it works**: Snapshot comparison proves no partial state persists after errors.

---

## Pattern 4: Resource Exhaustion Handling

**Problem**: System should handle connection pool exhaustion gracefully

**Solution**:
```python
import pytest
from psycopg_pool import ConnectionPool
from concurrent.futures import ThreadPoolExecutor
import time

@pytest.mark.chaos
@pytest.mark.resource
def test_pool_exhaustion_graceful(db_connection_string: str):
    """Test: Pool exhaustion causes timeout, not crash."""

    pool = ConnectionPool(
        db_connection_string,
        min_size=1,
        max_size=5,
        timeout=2.0
    )

    def worker(worker_id: int):
        """Hold connection for 3 seconds."""
        try:
            conn = pool.getconn(timeout=1.0)
            time.sleep(3)  # Hold longer than timeout
            pool.putconn(conn)
            return {'worker': worker_id, 'success': True}
        except Exception as e:
            return {'worker': worker_id, 'error': str(e), 'success': False}

    # Try to get 10 connections (pool size is 5)
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = [executor.submit(worker, i) for i in range(10)]
        results = [f.result() for f in futures]

    # Some succeed, some timeout (gracefully)
    successes = [r for r in results if r['success']]
    failures = [r for r in results if not r['success']]

    assert len(successes) <= 5, "Can't exceed pool size"
    assert all('timeout' in r['error'].lower() for r in failures), \
        "Failures should be timeouts, not crashes"

    pool.close()
```

**Why it works**: Tests graceful degradation under resource pressure without system crashes.

---

## Pattern 5: Schema Corruption Detection

**Problem**: Detect when schema is manually changed without pgGit

**Solution**:
```python
import pytest

@pytest.mark.chaos
@pytest.mark.corruption
def test_schema_drift_detection(sync_conn, isolated_schema):
    """Test: Detect manual schema changes."""

    # Create table via pgGit
    sync_conn.execute("CREATE TABLE drift_test (id INT)")
    sync_conn.commit()

    # Get schema hash
    cursor = sync_conn.execute(
        "SELECT pggit.calculate_schema_hash(%s)", ("drift_test",)
    )
    hash_before = cursor.fetchone()[0]

    # Manual change (bypassing pgGit)
    sync_conn.execute("ALTER TABLE drift_test ADD COLUMN sneaky_col TEXT")
    sync_conn.commit()

    # Get hash again
    cursor = sync_conn.execute(
        "SELECT pggit.calculate_schema_hash(%s)", ("drift_test",)
    )
    hash_after = cursor.fetchone()[0]

    # Should detect drift
    assert hash_before != hash_after, "Schema hash should detect manual changes"
```

**Why it works**: Hash comparison proves detection capability without complex reflection.

---

## Pattern 6: Deadlock Detection

**Problem**: PostgreSQL should detect circular lock dependencies

**Solution**:
```python
import pytest
from concurrent.futures import ThreadPoolExecutor
import time

@pytest.mark.chaos
@pytest.mark.concurrent
def test_deadlock_detection(db_connection_string: str):
    """Test: PostgreSQL detects circular lock dependencies."""

    # Setup tables
    setup_conn = psycopg.connect(db_connection_string)
    setup_conn.execute("CREATE TABLE lock_a (id INT)")
    setup_conn.execute("CREATE TABLE lock_b (id INT)")
    setup_conn.commit()
    setup_conn.close()

    def worker1():
        """Lock A → Lock B"""
        conn = psycopg.connect(db_connection_string)
        try:
            conn.execute("BEGIN")
            conn.execute("LOCK TABLE lock_a IN EXCLUSIVE MODE")
            time.sleep(0.5)
            conn.execute("LOCK TABLE lock_b IN EXCLUSIVE MODE")  # Deadlock!
            conn.commit()
            return {'worker': 1, 'success': True}
        except psycopg.Error as e:
            conn.rollback()
            return {'worker': 1, 'deadlock': 'deadlock' in str(e).lower()}

    def worker2():
        """Lock B → Lock A"""
        conn = psycopg.connect(db_connection_string)
        try:
            conn.execute("BEGIN")
            conn.execute("LOCK TABLE lock_b IN EXCLUSIVE MODE")
            time.sleep(0.5)
            conn.execute("LOCK TABLE lock_a IN EXCLUSIVE MODE")  # Deadlock!
            conn.commit()
            return {'worker': 2, 'success': True}
        except psycopg.Error as e:
            conn.rollback()
            return {'worker': 2, 'deadlock': 'deadlock' in str(e).lower()}

    # Run both workers
    with ThreadPoolExecutor(max_workers=2) as executor:
        future1 = executor.submit(worker1)
        future2 = executor.submit(worker2)

        result1 = future1.result()
        result2 = future2.result()

    # At least one should detect deadlock
    deadlocks = [r for r in [result1, result2] if r.get('deadlock')]
    assert len(deadlocks) > 0, "PostgreSQL should detect deadlock"
```

**Why it works**: Forces circular lock pattern that PostgreSQL must detect to prevent hangs.

---

## Pattern 7: Constraint Violation Handling

**Problem**: Ensure constraint violations rollback properly

**Solution**:
```python
import pytest

@pytest.mark.chaos
@pytest.mark.transaction
def test_constraint_violation_rollback(sync_conn, isolated_schema):
    """Test: Constraint violations trigger complete rollback."""

    # Setup: Create table with UNIQUE constraint
    sync_conn.execute(
        "CREATE TABLE users (id SERIAL PRIMARY KEY, email TEXT UNIQUE NOT NULL)"
    )
    sync_conn.execute("INSERT INTO users (email) VALUES ('test@example.com')")
    sync_conn.commit()

    count_before = sync_conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]

    # Try to insert duplicate
    try:
        sync_conn.execute("BEGIN")
        sync_conn.execute("INSERT INTO users (email) VALUES ('test@example.com')")
        sync_conn.commit()
    except Exception:
        sync_conn.rollback()

    # Verify rollback
    count_after = sync_conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
    assert count_before == count_after, "Constraint violation should rollback"
```

**Why it works**: Proves constraint enforcement and rollback atomicity.

---

## Custom Hypothesis Strategies

### Strategy: Valid PostgreSQL Identifier

```python
from hypothesis import strategies as st
import string

@st.composite
def pg_identifier(draw, max_length: int = 63):
    """Generate valid PostgreSQL identifier."""
    # First char: letter or underscore
    first_char = draw(st.sampled_from(string.ascii_lowercase + '_'))

    # Remaining chars
    remaining_length = draw(st.integers(min_value=0, max_value=max_length - 1))
    remaining = draw(st.text(
        alphabet=string.ascii_lowercase + string.digits + '_',
        min_size=remaining_length,
        max_size=remaining_length
    ))

    return first_char + remaining
```

### Strategy: Table Definition

```python
@st.composite
def table_definition(draw):
    """Generate complete table definition."""
    table_name = draw(pg_identifier())

    # 1-10 columns
    num_cols = draw(st.integers(min_value=1, max_value=10))
    columns = []

    for i in range(num_cols):
        col_name = draw(pg_identifier(max_length=30))
        col_type = draw(st.sampled_from(['INT', 'TEXT', 'BOOLEAN', 'TIMESTAMP']))
        columns.append(f"{col_name} {col_type}")

    return {
        'name': table_name,
        'columns': columns,
        'create_sql': f"CREATE TABLE {table_name} ({', '.join(columns)})"
    }
```

### Strategy: Commit Message

```python
def commit_message():
    """Generate valid commit message."""
    return st.text(
        min_size=1,
        max_size=1000,
        alphabet=st.characters(
            blacklist_categories=('Cc', 'Cs'),  # No control characters
            blacklist_characters='\x00'
        )
    )
```

---

## Tips and Tricks

### 1. Shrinking Hypothesis Examples

When a property test fails, Hypothesis automatically shrinks to minimal example:

```
Falsifying example: test_property(value=1000000)
  # Shrinking...
Falsifying example: test_property(value=1000)
  # Shrinking...
Falsifying example: test_property(value=0)  # Minimal!
```

Use this to find root cause quickly.

### 2. Reproduce Hypothesis Failures

```bash
# Use seed from failed run
pytest tests/chaos/test_name.py --hypothesis-seed=12345
```

### 3. Performance Benchmarking

```python
import time

start = time.perf_counter()
# Operation
elapsed = time.perf_counter() - start

print(f"Operation took {elapsed:.4f}s")
assert elapsed < 1.0, "Should complete in <1s"
```

### 4. Resource Monitoring

```python
import psutil

process = psutil.Process()
memory_before = process.memory_info().rss / 1024**2  # MB

# Operation

memory_after = process.memory_info().rss / 1024**2
memory_used = memory_after - memory_before

print(f"Memory used: {memory_used:.2f} MB")
assert memory_used < 100, "Should use <100MB"
```

### 5. Isolation with Savepoints

```python
@pytest.mark.chaos
@pytest.mark.transaction
def test_savepoint_rollback(sync_conn, isolated_schema):
    """Test: Savepoints provide partial rollback."""

    sync_conn.execute("BEGIN")
    sync_conn.execute("CREATE TABLE sp_test (id INT)")
    sync_conn.execute("SAVEPOINT sp1")

    sync_conn.execute("INSERT INTO sp_test (id) VALUES (1)")

    # Rollback to savepoint
    sync_conn.execute("ROLLBACK TO sp1")

    # Verify insert was rolled back but table exists
    count = sync_conn.execute("SELECT COUNT(*) FROM sp_test").fetchone()[0]
    assert count == 0, "Savepoint rollback should work"

    sync_conn.commit()
```

---

## Best Practices

### 1. Use Descriptive Names

```python
# ✅ Good
def test_concurrent_commits_to_same_branch_dont_collide(sync_conn, num_workers):
    pass

# ❌ Bad
def test_concurrent(sync_conn, num_workers):
    pass
```

### 2. Clear Docstrings

```python
@pytest.mark.chaos
@pytest.mark.property
def test_version_increment(sync_conn):
    """
    Property: Any valid version always increments correctly.

    Given: A table with current version V
    When: We increment to next version
    Then: New version is V+1 and is unique
    """
    pass
```

### 3. Separate Concerns

```python
# ✅ Good: One scenario per test
@pytest.mark.chaos
def test_concurrent_commits_same_branch(db_connection_string):
    # Test 1: concurrent commits to same branch
    pass

# ❌ Bad: Multiple unrelated scenarios
@pytest.mark.chaos
def test_chaos(db_connection_string):
    # Test 1: concurrent commits
    # Test 2: connection pool
    # Test 3: deadlock
    # Test 4: corruption
    pass
```

### 4. Cleanup Resources

```python
@pytest.fixture
def resource():
    r = create_resource()
    yield r
    r.cleanup()  # Guaranteed cleanup

def test_with_resource(resource):
    # Use resource - cleanup automatic
    pass
```

---

## Common Scenarios

### Scenario: Testing Data Loss Prevention

```python
@pytest.mark.chaos
@pytest.mark.property
@given(rows=st.integers(min_value=1, max_value=1000))
def test_no_data_loss_on_concurrent_inserts(sync_conn, isolated_schema, rows: int):
    """Property: Concurrent inserts never lose data."""

    sync_conn.execute("CREATE TABLE data (id SERIAL, value INT)")
    sync_conn.commit()

    def worker(worker_id: int):
        conn = psycopg.connect(os.getenv('DATABASE_URL'))
        for i in range(rows // 10):
            conn.execute("INSERT INTO data (value) VALUES (%s)", [worker_id])
        conn.commit()
        conn.close()

    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = [executor.submit(worker, i) for i in range(10)]
        [f.result() for f in futures]

    # All rows should exist
    count = sync_conn.execute("SELECT COUNT(*) FROM data").fetchone()[0]
    assert count == rows, f"Expected {rows} rows, got {count}"
```

### Scenario: Testing Consistency Under Stress

```python
@pytest.mark.chaos
@pytest.mark.resource
@pytest.mark.slow
def test_consistency_under_high_load(db_connection_string):
    """Test: System remains consistent under high load."""

    # Setup
    pool = ConnectionPool(db_connection_string, max_size=20)
    executor = ThreadPoolExecutor(max_workers=20)

    def heavy_workload(worker_id: int):
        conn = pool.getconn()
        for i in range(100):
            conn.execute("INSERT INTO load_test (value) VALUES (%s)", [worker_id])
            conn.execute("UPDATE load_test SET value = %s WHERE id = %s", [i, worker_id])
        conn.commit()
        pool.putconn(conn)

    futures = [executor.submit(heavy_workload, i) for i in range(20)]
    [f.result() for f in futures]

    # Verify consistency
    conn = pool.getconn()
    count = conn.execute("SELECT COUNT(*) FROM load_test").fetchone()[0]
    max_id = conn.execute("SELECT MAX(id) FROM load_test").fetchone()[0]
    pool.putconn(conn)

    assert count > 0, "Should have data"
    assert max_id == count, "IDs should be sequential"
```

---

## Next Steps

1. Review [CHAOS_ENGINEERING.md](CHAOS_ENGINEERING.md) for overview
2. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues
3. Study existing tests in `tests/chaos/examples/`
4. Write your first chaos test using these patterns
5. Contribute new patterns back to project
