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
| "Create table with 3 columns" | "Create ANY valid table with ANY valid columns" |
| "Commit message is preserved" | "ANY valid commit message is preserved" |
| "5 concurrent commits succeed" | "N concurrent commits (2-100) never corrupt data" |

**Results**:
- Property-based tests find edge cases traditional tests miss
- Concurrency tests reveal race conditions in production scenarios
- Failure tests prove ACID guarantees hold under stress
- Resource tests validate graceful degradation

## Test Suite Structure

```
tests/chaos/
├── README.md                      # Quick reference
├── TESTING.md                     # Comprehensive testing guide
├── pytest.ini                     # Pytest configuration
├── conftest.py                    # Pytest fixtures
├── fixtures.py                    # Reusable fixtures
├── utils.py                       # Chaos utilities
├── strategies.py                  # Hypothesis strategies
├── examples/                      # Learning examples
├── test_property_based_*.py       # Property-based tests
├── test_concurrent_*.py           # Concurrency tests
├── test_transaction_*.py          # Transaction failure tests
├── test_resource_*.py             # Resource exhaustion tests
└── test_corruption_*.py           # Corruption detection tests
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

# Specific test file
pytest tests/chaos/test_concurrent_commits.py -v

# Specific test
pytest tests/chaos/test_concurrent_commits.py::TestConcurrentCommits::test_concurrent_commits_same_branch -v
```

## Test Categories

### 1. Property-Based Tests (`@pytest.mark.property`)

**Purpose**: Test universal properties across wide input ranges

**Tools**: Hypothesis library

**Key Properties**:
- Trinity ID uniqueness (any input → unique ID)
- Version increment correctness (any version → valid increment)
- Commit message preservation (any message → exact storage)
- Schema evolution maintains integrity

**Files**:
- `test_property_based_core.py`
- `test_property_based_migrations.py`
- `test_property_based_data.py`

**Example**:
```python
from hypothesis import given, strategies as st

@pytest.mark.chaos
@pytest.mark.property
@given(msg=st.text(min_size=1, max_size=1000))
def test_commit_message_preserved(sync_conn, msg: str):
    """Property: Any commit message is preserved exactly."""
    # ... test implementation
```

### 2. Concurrency Tests (`@pytest.mark.concurrent`)

**Purpose**: Find race conditions, deadlocks, serialization failures

**Tools**: ThreadPoolExecutor, asyncio

**Scenarios**:
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

**Example**:
```python
from concurrent.futures import ThreadPoolExecutor

@pytest.mark.chaos
@pytest.mark.concurrent
def test_concurrent_commits(db_connection_string: str, num_workers: int):
    """Test: N concurrent commits never create collisions."""
    def worker(worker_id):
        # Concurrent operation
        pass

    with ThreadPoolExecutor(max_workers=num_workers) as executor:
        futures = [executor.submit(worker, i) for i in range(num_workers)]
        results = [f.result() for f in futures]

    # Validate no race conditions
```

### 3. Transaction Tests (`@pytest.mark.transaction`)

**Purpose**: Validate ACID properties and rollback correctness

**Tools**: PostgreSQL transactions, savepoints

**Scenarios**:
- Complete rollback on error
- Savepoint partial rollback
- Trinity ID consistency after rollback
- Constraint violation handling

**Files**:
- `test_transaction_rollback.py`
- `test_crash_recovery.py`
- `test_constraint_violations.py`
- `test_partial_failures.py`

### 4. Resource Tests (`@pytest.mark.resource`)

**Purpose**: Test behavior at system limits

**Tools**: Connection pools, large data generation

**Scenarios**:
- Connection pool exhaustion
- Large table versioning (100+ columns)
- Trinity ID generation at scale
- 100+ concurrent connections

**Files**:
- `test_connection_exhaustion.py`
- `test_memory_pressure.py`
- `test_disk_space.py`
- `test_load_stress.py`

### 5. Corruption Tests (`@pytest.mark.corruption`)

**Purpose**: Detect and recover from corruption

**Tools**: Manual database manipulation, validation queries

**Scenarios**:
- Manual schema changes (bypassing pgGit)
- Corrupted version metadata
- Missing Trinity ID references
- Migration failures

**Files**:
- `test_migration_failures.py`
- `test_schema_corruption.py`
- `test_data_integrity.py`
- `test_recovery_procedures.py`

## Key Concepts

### Property-Based Testing with Hypothesis

Instead of writing single examples:
```python
def test_commit_message():
    msg = "Initial commit"
    # ... test with "Initial commit"
```

Write properties that hold for ANY valid input:
```python
from hypothesis import given, strategies as st

@given(msg=st.text(min_size=1, max_size=1000))
def test_commit_message(msg: str):
    # ... test with ANY valid message
```

**Hypothesis Features**:
- Generates hundreds of examples automatically
- Finds edge cases (empty strings, unicode, max length)
- Shrinks failures to minimal examples
- Provides reproducible seeds

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
|---------|-------|-----------|----------|
| PR | Smoke tests | ✅ Yes | ~5 min |
| Main branch | Full suite | ⚠️ Can fail | ~60 min |
| Weekly | Comprehensive | ⚠️ Can fail | ~120 min |

### Smoke Tests (PR Gate)
- **Filter**: `pytest -m "chaos and not slow and not destructive"`
- **Duration**: ~5 minutes
- **Pass Rate**: 100% (enforced for PR merge)
- **Includes**: Basic property tests, simple transactions

### Full Suite (Main Branch)
- **Filter**: `pytest -m chaos`
- **Duration**: ~60 minutes
- **Pass Rate**: 85-95% (improving)
- **Includes**: All test categories

### Weekly Comprehensive
- **Schedule**: Sunday 3 AM UTC
- **Duration**: ~120 minutes
- **Coverage**: PostgreSQL 15, 16, 17
- **Action**: Creates GitHub issue on failure

## Writing Chaos Tests

See [PATTERNS.md](PATTERNS.md) for detailed examples and best practices.

### Quick Template

```python
import pytest
from hypothesis import given, strategies as st

@pytest.mark.chaos
@pytest.mark.property  # Change to: concurrent, transaction, resource, corruption
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

### Test Markers

| Marker | Purpose | Must Pass? |
|--------|---------|-----------|
| `@pytest.mark.chaos` | Mark as chaos test | - |
| `@pytest.mark.property` | Property-based test | Partial |
| `@pytest.mark.concurrent` | Concurrency test | Partial |
| `@pytest.mark.transaction` | Transaction test | Yes |
| `@pytest.mark.resource` | Resource exhaustion | No |
| `@pytest.mark.corruption` | Corruption detection | No |
| `@pytest.mark.migration` | Migration failure | No |
| `@pytest.mark.recovery` | Recovery procedure | No |
| `@pytest.mark.load` | Load/stress test | No |
| `@pytest.mark.slow` | Takes >30 seconds | - |
| `@pytest.mark.destructive` | Special setup needed | - |

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

## Available Fixtures

### Database Connections
- `sync_conn`: Synchronous connection (function scope)
- `async_conn`: Asynchronous connection (function scope)
- `conn_pool`: Pool of connections (configurable size)
- `async_conn_pool`: Async connection pool

### Isolation & Schema
- `isolated_schema`: Clean schema for each test
- `async_isolated_schema`: Async version
- `temp_table`: Temporary table for testing
- `async_temp_table`: Async version

### Chaos & Utilities
- `chaos_injector`: Delay/failure injection utilities
- `transaction_monitor`: Monitor locks and transactions
- `load_generator`: Generate database load
- `deadlock_setup`: Create deadlock scenarios

See `tests/chaos/conftest.py` for complete fixture documentation.

## Resources

- **Hypothesis**: https://hypothesis.readthedocs.io/
- **PostgreSQL Concurrency**: https://www.postgresql.org/docs/current/mvcc.html
- **Chaos Engineering**: https://principlesofchaos.org/
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
6. Update [PATTERNS.md](PATTERNS.md) if adding new patterns

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

**Q: How do I run specific test category?**
A: `pytest tests/chaos/ -v -m property` (or concurrent, transaction, etc.)

## Metrics

Track chaos test effectiveness:

- **Bug detection rate**: Bugs found per 100 chaos tests
- **Coverage**: % of failure modes tested
- **Stability**: % of tests passing consistently
- **Performance**: Time to run full suite
- **Shrinking**: Average shrink iterations to minimal case

## Next Steps

1. Review [PATTERNS.md](PATTERNS.md) for detailed examples
2. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues
3. Review existing tests in `tests/chaos/examples/`
4. Run tests locally to understand patterns
5. Write your first chaos test
6. Contribute improvements back to project
