# Phase 8: Documentation & Patterns Guide

## Objective
Create comprehensive documentation for chaos engineering practices, including patterns guide, examples, troubleshooting guide, and integration with existing pggit documentation.

## TDD Stage
GREENFIELD (Documentation)

## Context
- **Previous phase**: Phase 7 (CI Integration) completed CI setup
- **Current state**: Full chaos test suite with CI integration, needs documentation
- **Next phase**: N/A (final phase)

## Files to Create

### 1. `docs/testing/CHAOS_ENGINEERING.md`
Main chaos engineering guide for pggit.

### 2. `docs/testing/PATTERNS.md`
Common chaos testing patterns and examples.

### 3. `docs/testing/TROUBLESHOOTING.md`
Troubleshooting guide for common issues.

### 4. `tests/chaos/examples/`
Directory with example chaos tests for learning.

### 5. `README.md` (update)
Add chaos testing badge and link to documentation.

## Implementation Steps

### Step 1: Create Main Chaos Engineering Guide (`docs/testing/CHAOS_ENGINEERING.md`)

```markdown
# Chaos Engineering for pgGit

## Overview

pgGit uses chaos engineering to validate production readiness by testing behavior under adverse conditions:

- **Concurrency**: Race conditions, deadlocks, serialization failures
- **Failures**: Transaction rollbacks, connection losses, crashes
- **Resource limits**: Connection exhaustion, memory pressure, disk space
- **Corruption**: Schema drift, migration failures, data integrity violations

## Why Chaos Engineering?

Traditional testing validates **expected behavior** with **expected inputs**.

Chaos testing validates **unexpected behavior** with **unexpected inputs**:

| Traditional Test | Chaos Test |
|-----------------|------------|
| "Create table 'users' with 3 columns" | "Create ANY valid table with ANY valid columns" |
| "Commit message 'Initial commit' is preserved" | "ANY valid commit message is preserved" |
| "5 concurrent commits succeed" | "N concurrent commits (2-100) never corrupt data" |

**Results**:
- Property-based tests find edge cases traditional tests miss
- Concurrency tests reveal race conditions in production scenarios
- Failure tests prove ACID guarantees hold under stress
- Resource tests validate graceful degradation

## Test Suite Structure

```
tests/chaos/
├── conftest.py                      # Pytest fixtures
├── fixtures.py                      # Reusable fixtures
├── utils.py                         # Chaos utilities
├── strategies.py                    # Hypothesis strategies
├── test_property_based_*.py         # Property-based tests
├── test_concurrent_*.py             # Concurrency tests
├── test_transaction_*.py            # Transaction failure tests
├── test_resource_*.py               # Resource exhaustion tests
├── test_corruption_*.py             # Corruption detection tests
└── README.md                        # Quick reference
```

## Quick Start

### Prerequisites

```bash
# Install chaos testing dependencies
uv pip install -e ".[chaos]"

# Ensure PostgreSQL is running
# Default: postgresql://postgres@localhost/pggit_chaos_test
```

### Run Tests

```bash
# All chaos tests
pytest tests/chaos/ -v -m chaos

# By category
pytest tests/chaos/ -v -m property        # Property-based
pytest tests/chaos/ -v -m concurrent      # Concurrency
pytest tests/chaos/ -v -m transaction     # Transactions
pytest tests/chaos/ -v -m resource        # Resource limits
pytest tests/chaos/ -v -m corruption      # Corruption

# Smoke tests (fast, must pass)
pytest tests/chaos/ -v -m "chaos and not slow and not destructive"

# With Hypothesis statistics
pytest tests/chaos/ -v --hypothesis-show-statistics
```

## Test Categories

### 1. Property-Based Tests (`@pytest.mark.property`)

**Purpose**: Test universal properties across wide input ranges

**Tools**: Hypothesis library

**Examples**:
- Trinity ID uniqueness (any input → unique ID)
- Version increment correctness (any version → valid increment)
- Commit message preservation (any message → exact storage)

**Files**:
- `test_property_based_core.py`
- `test_property_based_migrations.py`
- `test_property_based_data.py`

### 2. Concurrency Tests (`@pytest.mark.concurrent`)

**Purpose**: Find race conditions, deadlocks, serialization failures

**Tools**: ThreadPoolExecutor, asyncio

**Examples**:
- Multiple workers committing to same branch
- Concurrent version increments
- Simultaneous branch creation
- Deadlock detection

**Files**:
- `test_concurrent_commits.py`
- `test_concurrent_versioning.py`
- `test_concurrent_branching.py`
- `test_deadlock_scenarios.py`
- `test_serialization_failures.py`

### 3. Transaction Tests (`@pytest.mark.transaction`)

**Purpose**: Validate ACID properties and rollback correctness

**Tools**: PostgreSQL transactions, savepoints

**Examples**:
- Complete rollback on error
- Savepoint partial rollback
- Trinity ID consistency after rollback
- Version integrity after failure

**Files**:
- `test_transaction_rollback.py`
- `test_crash_recovery.py` (requires special setup)
- `test_constraint_violations.py`
- `test_partial_failures.py`

### 4. Resource Tests (`@pytest.mark.resource`)

**Purpose**: Test behavior at system limits

**Tools**: Connection pools, large data generation

**Examples**:
- Connection pool exhaustion
- Large table versioning (100+ columns)
- 1000+ Trinity ID generation
- 100+ concurrent connections

**Files**:
- `test_connection_exhaustion.py`
- `test_memory_pressure.py`
- `test_disk_space.py` (requires special setup)
- `test_load_stress.py`

### 5. Corruption Tests (`@pytest.mark.corruption`)

**Purpose**: Detect and recover from corruption

**Tools**: Manual database manipulation, validation queries

**Examples**:
- Manual schema changes (bypassing pggit)
- Corrupted version metadata
- Missing Trinity ID references
- Migration failures

**Files**:
- `test_migration_failures.py`
- `test_schema_corruption.py`
- `test_data_integrity.py`
- `test_recovery_procedures.py`

## Key Concepts

### Property-Based Testing

Instead of writing:
```python
def test_commit_message():
    msg = "Initial commit"
    # ... test with "Initial commit"
```

Write:
```python
from hypothesis import given, strategies as st

@given(msg=st.text(min_size=1, max_size=1000))
def test_commit_message(msg: str):
    # ... test with ANY valid message
```

Hypothesis generates hundreds of examples, finds edge cases, and shrinks failures to minimal examples.

### Concurrency Patterns

```python
from concurrent.futures import ThreadPoolExecutor

def worker(worker_id):
    # Concurrent operation
    pass

with ThreadPoolExecutor(max_workers=10) as executor:
    futures = [executor.submit(worker, i) for i in range(10)]
    results = [f.result() for f in futures]

# Validate: no race conditions, data corruption, or crashes
```

### Chaos Injection

```python
from tests.chaos.utils import ChaosInjector

# Random delays (simulates network latency)
await ChaosInjector.random_delay(min_ms=0, max_ms=100)

# Connection failures (simulates network issues)
with ChaosInjector.simulate_connection_failure(probability=0.1):
    # Operation that may fail
    pass

# Retry with backoff
result = await ChaosInjector.with_retry(
    risky_operation,
    max_attempts=3,
    backoff=0.1
)
```

## CI Integration

### Automatic Testing

| Trigger | Tests | Must Pass? | Duration |
|---------|-------|------------|----------|
| PR | Smoke tests | ✅ Yes | ~5 min |
| Main branch | Full suite | ⚠️ Can fail | ~60 min |
| Weekly | Comprehensive | ⚠️ Can fail | ~120 min |

### Test Progression

As bugs are fixed, tests move from "can fail" to "must pass":

**Phase 1** (Weeks 1-2): Smoke tests must pass
- Basic property tests
- Simple transaction tests
- No concurrency edge cases

**Phase 2** (Weeks 3-4): Add transaction tests
- All rollback scenarios
- Constraint violations
- Savepoint handling

**Phase 3** (Weeks 5-6): Add simple concurrency
- 2-10 concurrent workers
- Basic race conditions
- Deadlock detection

**Phase 4** (Weeks 7-8): Add resource tests
- Connection pool limits
- Memory pressure
- Load testing

**Phase 5** (Weeks 9+): Full suite must pass
- All non-destructive tests
- High concurrency (50+ workers)
- Large-scale scenarios

## Writing Chaos Tests

See [PATTERNS.md](PATTERNS.md) for detailed examples and best practices.

### Quick Template

```python
import pytest
from hypothesis import given, strategies as st

@pytest.mark.chaos
@pytest.mark.category  # property, concurrent, transaction, etc.
def test_your_chaos_test(sync_conn, isolated_schema):
    """
    Test: [What scenario is being tested]

    Expected: [Expected behavior under chaos]
    """
    # Setup
    sync_conn.execute("CREATE TABLE test_table (id INT)")
    sync_conn.commit()

    # Chaos operation
    # ...

    # Validation
    assert condition, "Should handle chaos correctly"
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

## Best Practices

1. **Isolate tests**: Use `isolated_schema` fixture
2. **Clean up**: Fixtures handle cleanup automatically
3. **Use markers**: Properly tag tests (`@pytest.mark.chaos`, etc.)
4. **Document expectations**: Clear docstrings with expected behavior
5. **Handle failures**: Chaos tests SHOULD fail initially (that's the point!)
6. **Shrink examples**: Let Hypothesis find minimal failing cases
7. **Measure performance**: Track degradation over time
8. **Test incrementally**: Start simple, add complexity gradually

## Resources

- **Hypothesis**: https://hypothesis.readthedocs.io/
- **PostgreSQL Concurrency**: https://www.postgresql.org/docs/current/mvcc.html
- **Chaos Engineering Book**: "Chaos Engineering" by Casey Rosenthal
- **Property-Based Testing**: "Property-Based Testing with PropEr, Erlang, and Elixir"

## Examples

See `tests/chaos/examples/` for complete working examples of each test pattern.

## Contributing

When adding chaos tests:

1. Choose appropriate category (property, concurrent, etc.)
2. Use custom strategies from `strategies.py`
3. Add clear docstring explaining scenario
4. Mark appropriately (`@pytest.mark.chaos`, `@pytest.mark.slow`, etc.)
5. Test locally before PR
6. Update documentation if adding new patterns

## FAQ

**Q: Why do chaos tests fail on my PR?**
A: Smoke tests must pass. Full suite can fail while bugs are being fixed.

**Q: How long do chaos tests take?**
A: Smoke tests: ~5 min. Full suite: ~60 min. Weekly: ~120 min.

**Q: Can I skip chaos tests locally?**
A: Yes: `pytest tests/ -v -m "not chaos"`

**Q: How do I debug a failing Hypothesis test?**
A: Look for "Falsifying example" in output - it's the minimal failing case.

**Q: What if tests are flaky?**
A: Use `--hypothesis-seed=X` to reproduce. Report flaky tests as bugs.

**Q: How do I add a new chaos test?**
A: See [PATTERNS.md](PATTERNS.md) for templates and examples.

## Metrics

Track chaos test effectiveness:

- **Bug detection rate**: Bugs found per 100 chaos tests
- **Coverage**: % of failure modes tested
- **Stability**: % of tests passing consistently
- **Performance**: Time to run full suite
- **Shrinking**: Average shrink iterations to minimal case

Current metrics (updated weekly):
- TBD after Phase 1-8 implementation
```

### Step 2: Create Patterns Guide (`docs/testing/PATTERNS.md`)

```markdown
# Chaos Engineering Patterns

## Common Test Patterns

### Pattern 1: Property-Based Trinity ID Uniqueness

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

**Why it works**: Hypothesis generates hundreds of branch/message combinations, catching edge cases like:
- Very long branch names
- Unicode characters
- Empty messages
- Max-length inputs

---

### Pattern 2: Concurrent Commit Without Collisions

**Problem**: Multiple workers committing simultaneously should not create Trinity ID collisions

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

**Why it works**: Real parallelism via threads exposes race conditions in Trinity ID generation.

---

### Pattern 3: Complete Rollback on Error

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

**Why it works**: Snapshot comparison proves no partial state persists.

---

### Pattern 4: Resource Exhaustion Handling

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

**Why it works**: Tests graceful degradation under resource pressure.

---

### Pattern 5: Corruption Detection

**Problem**: Detect when schema is manually changed without pggit

**Solution**:
```python
import pytest

@pytest.mark.chaos
@pytest.mark.corruption
def test_schema_drift_detection(sync_conn, isolated_schema):
    """Test: Detect manual schema changes."""

    # Create table via pggit
    sync_conn.execute("CREATE TABLE drift_test (id INT)")
    sync_conn.commit()

    # Get schema hash
    cursor = sync_conn.execute(
        "SELECT pggit.calculate_schema_hash(%s)", ("drift_test",)
    )
    hash_before = cursor.fetchone()[0]

    # Manual change (bypassing pggit)
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

**Why it works**: Hash comparison proves detection capability.

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

---

## Chaos Injection Utilities

### Random Delay Injection

```python
from tests.chaos.utils import ChaosInjector

async def operation_with_latency():
    """Simulate network latency."""
    await ChaosInjector.random_delay(min_ms=10, max_ms=500)
    # ... actual operation
```

### Retry with Backoff

```python
async def reliable_operation():
    """Operation with automatic retry."""
    return await ChaosInjector.with_retry(
        risky_database_call,
        max_attempts=3,
        backoff=0.1  # 100ms, 200ms, 400ms
    )
```

---

## Advanced Patterns

### Pattern: Deadlock Detection

```python
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

---

## Tips and Tricks

### 1. Shrinking Hypothesis Examples

When a property test fails, Hypothesis automatically shrinks to minimal example:

```
Falsifying example: test_property(value=1000000)
  # Shrinking...
Falsifying example: test_property(value=1000)
  # Shrinking...
Falsifying example: test_property(value=100)
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

---

## Next Steps

1. Review existing tests in `tests/chaos/`
2. Run tests locally to understand patterns
3. Write your first chaos test using templates above
4. Contribute new patterns back to this guide
```

### Step 3: Create Troubleshooting Guide (`docs/testing/TROUBLESHOOTING.md`)

```markdown
# Chaos Testing Troubleshooting Guide

## Common Issues and Solutions

### Issue 1: Tests Hang Indefinitely

**Symptoms**:
- Tests run forever without completing
- No output after initial test start

**Causes**:
- Deadlock in concurrent tests
- Missing timeout configuration
- Infinite loop in test code

**Solutions**:

```bash
# Add timeout to specific test
pytest tests/chaos/test_name.py --timeout=60

# Check for deadlocks in PostgreSQL
SELECT * FROM pg_locks WHERE NOT granted;

# Add timeout decorator
@pytest.mark.timeout(60)
def test_that_might_hang():
    pass
```

---

### Issue 2: Connection Refused Errors

**Symptoms**:
```
psycopg.OperationalError: connection to server at "localhost" (::1), port 5432 failed: Connection refused
```

**Causes**:
- PostgreSQL not running
- Wrong connection parameters
- Database doesn't exist

**Solutions**:

```bash
# Check PostgreSQL status
pg_ctl status -D /var/lib/postgresql/data

# Start PostgreSQL
pg_ctl start -D /var/lib/postgresql/data

# Create test database
createdb pggit_chaos_test

# Verify connection
psql postgresql://postgres@localhost/pggit_chaos_test -c "SELECT 1"
```

---

### Issue 3: Hypothesis Tests Fail Inconsistently

**Symptoms**:
- Test passes sometimes, fails other times
- Different failures on each run

**Causes**:
- Flaky test (timing-dependent)
- Insufficient shrinking
- Random seed changing

**Solutions**:

```bash
# Reproduce with specific seed
pytest tests/chaos/test_name.py --hypothesis-seed=SEED_FROM_FAILURE

# Increase examples to find consistent failure
pytest tests/chaos/test_name.py --hypothesis-profile=thorough

# Check for timing issues
# Add explicit delays or use fixed seeds
```

---

### Issue 4: Trinity ID Collision Detected

**Symptoms**:
```
AssertionError: Trinity ID collision detected: [123, 123, 124, 125]
```

**Causes**:
- Race condition in Trinity ID generation
- Database sequence issues
- Transaction isolation problem

**Solutions**:

```python
# Check sequence state
SELECT last_value FROM pggit.trinity_id_seq;

# Reset sequence if corrupted
SELECT setval('pggit.trinity_id_seq', (SELECT MAX(id) FROM pggit.trinity_ids));

# Verify transaction isolation
SHOW transaction_isolation;  # Should be "read committed" or higher
```

---

### Issue 5: Out of Memory Errors

**Symptoms**:
```
MemoryError: Unable to allocate array
```

**Causes**:
- Large data generation in property tests
- Memory leak in test
- Too many concurrent connections

**Solutions**:

```python
# Limit Hypothesis examples
@settings(max_examples=10)  # Instead of default 50

# Use smaller data in strategies
@given(msg=st.text(max_size=100))  # Instead of max_size=10000

# Clean up connections
@pytest.fixture
def conn_pool():
    pool = create_pool()
    yield pool
    pool.close()  # Ensure cleanup
```

---

### Issue 6: Transaction Isolation Errors

**Symptoms**:
```
psycopg.errors.SerializationFailure: could not serialize access due to concurrent update
```

**Causes**:
- Expected behavior in concurrent tests!
- High contention on same rows
- Serializable isolation level

**Solutions**:

This is often **expected** in chaos tests. Verify your test handles it:

```python
try:
    # Concurrent operation
    conn.execute("UPDATE ...")
    conn.commit()
except psycopg.errors.SerializationFailure:
    # Expected! This is correct behavior
    conn.rollback()
```

If unexpected, reduce concurrency or add retries.

---

### Issue 7: pytest Cannot Find Tests

**Symptoms**:
```
collected 0 items
```

**Causes**:
- Wrong working directory
- Missing `__init__.py`
- Tests not matching naming pattern

**Solutions**:

```bash
# Check current directory
pwd  # Should be repo root

# Verify test discovery
pytest tests/chaos/ --collect-only

# Check test file naming
# Must be: test_*.py or *_test.py

# Check function naming
# Must be: test_*() or *_test()
```

---

### Issue 8: CI Tests Pass Locally, Fail in CI

**Symptoms**:
- Tests pass on your machine
- Same tests fail in GitHub Actions

**Causes**:
- Different PostgreSQL version
- Timing differences (CI is slower)
- Resource limits in CI

**Solutions**:

```yaml
# Match CI PostgreSQL version locally
docker run -p 5432:5432 postgres:17

# Increase timeouts for CI
@pytest.mark.timeout(300)  # 5 minutes for CI

# Check CI logs for specifics
# GitHub Actions → Workflow run → Test job → Full output
```

---

### Issue 9: Schema Corruption Tests Fail

**Symptoms**:
```
AssertionError: Should detect corruption, but didn't
```

**Causes**:
- Corruption detection not implemented yet
- Test expects feature that doesn't exist
- Manual changes not triggering detection

**Solutions**:

Many corruption tests are **designed to fail initially** - they're requirements for future features:

```python
@pytest.mark.skip(reason="Corruption detection not implemented yet")
def test_detect_manual_schema_change():
    # This test documents required feature
    pass
```

Check if test is marked as "can fail" in CI configuration.

---

### Issue 10: Deadlock Tests Never Trigger Deadlock

**Symptoms**:
```
AssertionError: Expected deadlock, but all transactions succeeded
```

**Causes**:
- Timing issue (workers not overlapping)
- Insufficient lock contention
- Transaction too fast

**Solutions**:

```python
# Add delays to ensure overlap
def worker1():
    conn.execute("LOCK TABLE a")
    time.sleep(1.0)  # Ensure worker2 starts
    conn.execute("LOCK TABLE b")

# Use explicit locking
conn.execute("LOCK TABLE ... IN EXCLUSIVE MODE")  # Not ACCESS SHARE
```

---

## Debugging Techniques

### Enable Verbose Logging

```bash
# Full pytest output
pytest tests/chaos/ -v --tb=long --log-cli-level=DEBUG

# PostgreSQL query logging
# In postgresql.conf:
# log_statement = 'all'
# log_duration = on
```

### Use PDB Debugger

```bash
# Drop into debugger on failure
pytest tests/chaos/test_name.py --pdb

# In test code
import pdb; pdb.set_trace()
```

### Check PostgreSQL Logs

```bash
# View logs
tail -f /var/log/postgresql/postgresql-*.log

# Filter for errors
tail -f /var/log/postgresql/postgresql-*.log | grep ERROR

# Filter for deadlocks
tail -f /var/log/postgresql/postgresql-*.log | grep -i deadlock
```

### Monitor Database Activity

```sql
-- Active queries
SELECT pid, state, query FROM pg_stat_activity WHERE datname = 'pggit_chaos_test';

-- Locks
SELECT locktype, relation::regclass, mode, granted, pid FROM pg_locks;

-- Deadlocks
SELECT * FROM pg_stat_database WHERE datname = 'pggit_chaos_test';
```

---

## Getting Help

1. **Check test output**: Look for "Falsifying example" from Hypothesis
2. **Review logs**: Both pytest and PostgreSQL logs
3. **Reproduce**: Use `--hypothesis-seed` to reproduce failures
4. **Isolate**: Run single test with `-k test_name`
5. **Search issues**: Check GitHub issues for similar problems
6. **Ask**: Create issue with full output, logs, and reproduction steps

---

## Prevention

### Write Robust Tests

```python
# ✅ Good: Handles expected failures
try:
    result = risky_operation()
except ExpectedError:
    # Expected, not a test failure
    pass

# ❌ Bad: Assumes operation always succeeds
result = risky_operation()  # May raise unexpected error
```

### Use Timeouts

```python
# ✅ Good: Bounded execution time
@pytest.mark.timeout(60)
def test_with_timeout():
    pass

# ❌ Bad: Can hang indefinitely
def test_without_timeout():
    pass
```

### Clean Up Resources

```python
# ✅ Good: Guaranteed cleanup
@pytest.fixture
def resource():
    r = create_resource()
    yield r
    r.cleanup()

# ❌ Bad: May leak resources
def test():
    r = create_resource()
    # ... use r ...
    # Cleanup might not happen if test fails!
```

---

## Still Stuck?

Create a GitHub issue with:
- Full test output (with `-v --tb=long`)
- PostgreSQL logs
- System info (PostgreSQL version, Python version, OS)
- Minimal reproduction steps
- What you've tried so far
```

### Step 4: Update Main README

Add chaos testing section to main README.md:

```markdown
<!-- Add after existing testing section -->

### Chaos Engineering Tests

pggit includes comprehensive chaos engineering tests to validate production readiness:

```bash
# Run chaos engineering test suite
pytest tests/chaos/ -v -m chaos

# Quick smoke tests
pytest tests/chaos/ -v -m "chaos and not slow"
```

**Test Coverage**:
- ✅ Property-based testing (Hypothesis)
- ✅ Concurrency and race conditions
- ✅ Transaction failures and rollback
- ✅ Resource exhaustion
- ✅ Schema corruption detection

See [Chaos Engineering Guide](docs/testing/CHAOS_ENGINEERING.md) for details.
```

## Verification Commands

```bash
# Verify documentation exists
ls -la docs/testing/CHAOS_ENGINEERING.md docs/testing/PATTERNS.md docs/testing/TROUBLESHOOTING.md

# Check markdown formatting
markdownlint docs/testing/*.md

# Verify links work
markdown-link-check docs/testing/CHAOS_ENGINEERING.md

# Test that documentation examples are valid code
# (Extract code blocks and run through syntax checker)
```

## Expected Outcome

### Documentation Should:
- ✅ Provide clear introduction to chaos testing
- ✅ Include runnable examples
- ✅ Cover all test categories
- ✅ Have troubleshooting guide
- ✅ Link to related resources
- ✅ Be maintainable and extensible

### Users Should Be Able To:
- ✅ Understand chaos testing purpose
- ✅ Run chaos tests successfully
- ✅ Write new chaos tests
- ✅ Debug failures
- ✅ Contribute improvements

## Acceptance Criteria

- [ ] Main chaos engineering guide created (CHAOS_ENGINEERING.md)
- [ ] Patterns guide with 5+ examples (PATTERNS.md)
- [ ] Troubleshooting guide with 10+ issues (TROUBLESHOOTING.md)
- [ ] README updated with chaos testing section
- [ ] All code examples are syntactically valid
- [ ] Documentation cross-references are correct
- [ ] Markdown formatting is consistent

## DO NOT

- ❌ Write documentation without examples (include code)
- ❌ Skip troubleshooting section (critical for adoption)
- ❌ Assume users know Hypothesis (explain it)
- ❌ Ignore CI integration docs (show how it fits)
- ❌ Leave broken links or references

## Notes

**Documentation Philosophy**:
1. **Show, don't tell**: More code examples, less prose
2. **Progressive disclosure**: Start simple, add complexity gradually
3. **Real-world focus**: Use actual pggit patterns, not toy examples
4. **Troubleshooting first**: Most users will read docs when stuck
5. **Link everything**: Connect related concepts

**Maintenance**:
- Update docs when adding new test patterns
- Keep troubleshooting guide current with common issues
- Add new examples as patterns emerge
- Review quarterly for accuracy

**Success Metrics**:
- Time to first chaos test (< 15 minutes)
- Contribution rate (new chaos tests from community)
- Issue resolution (troubleshooting guide effectiveness)
- Adoption (% of PRs including chaos tests)

**Final Phase**:
This completes the chaos engineering test suite implementation! All 8 phases provide:
1. Infrastructure (Phase 1)
2. Property tests (Phase 2)
3. Concurrency tests (Phase 3)
4. Transaction tests (Phase 4)
5. Resource tests (Phase 5)
6. Corruption tests (Phase 6)
7. CI integration (Phase 7)
8. Documentation (Phase 8)

Ready for user execution via opencode!
