# Chaos Engineering Test Suite

## Overview

This directory contains chaos engineering tests for pggit. These tests validate the system's behavior under adverse conditions, including:

- **Concurrency**: Race conditions, deadlocks, serialization failures
- **Failures**: Transaction rollbacks, connection losses, crashes
- **Resource exhaustion**: Connection pool limits, memory pressure, disk space
- **Data corruption**: Schema migration failures, partial commits

## Test Organization

```
tests/chaos/
├── conftest.py              # Pytest configuration and base fixtures
├── fixtures.py              # Reusable test fixtures
├── utils.py                 # Chaos injection utilities
├── test_concurrent_*.py     # Concurrency tests (Phase 3)
├── test_transaction_*.py    # Transaction failure tests (Phase 4)
├── test_resource_*.py       # Resource exhaustion tests (Phase 5)
└── test_corruption_*.py     # Schema corruption tests (Phase 6)
```

## Running Chaos Tests

### Run all chaos tests
```bash
pytest tests/chaos/ -v -m chaos
```

### Run specific test category
```bash
pytest tests/chaos/ -v -m concurrent
pytest tests/chaos/ -v -m destructive
pytest tests/chaos/ -v -m slow
```

### Run with parallelization
```bash
pytest tests/chaos/ -v -n 4  # 4 parallel workers
```

### Skip slow tests
```bash
pytest tests/chaos/ -v -m "not slow"
```

### Run only smoke tests (fast)
```bash
pytest tests/chaos/ -v -m "chaos and not slow"
```

## Test Markers

- `@pytest.mark.chaos`: All chaos tests
- `@pytest.mark.slow`: Tests taking >30 seconds
- `@pytest.mark.concurrent`: Concurrency/race condition tests
- `@pytest.mark.destructive`: Tests that may leave artifacts

## Writing Chaos Tests

### Example: Property-based concurrency test

```python
import pytest
from hypothesis import given, strategies as st

@pytest.mark.chaos
@pytest.mark.concurrent
@given(num_workers=st.integers(min_value=2, max_value=20))
async def test_concurrent_commits(conn_pool, num_workers: int):
    """Test concurrent commits to same branch."""
    # Test implementation
    pass
```

### Example: Transaction failure test

```python
@pytest.mark.chaos
async def test_rollback_on_error(async_conn):
    """Test that errors trigger complete rollback."""
    # Setup
    await async_conn.execute("BEGIN")

    # Inject failure
    with pytest.raises(psycopg.Error):
        await async_conn.execute("INVALID SQL")

    # Verify rollback
    await async_conn.rollback()
    # Assertions
```

### Example: Resource exhaustion test

```python
@pytest.mark.chaos
@pytest.mark.slow
@pytest.mark.destructive
def test_connection_pool_exhaustion(conn_pool):
    """Test behavior when connection pool is exhausted."""
    # Create maximum connections
    connections = conn_pool  # This uses the conn_pool fixture

    # Try to create one more (should fail gracefully)
    with pytest.raises(Exception):  # Specific exception type
        # Attempt to exhaust pool
        pass
```

## Available Fixtures

### Database Connections

- `sync_conn`: Synchronous database connection (per test)
- `async_conn`: Asynchronous database connection (per test)
- `conn_pool`: Pool of synchronous connections (configurable size)
- `async_conn_pool`: Pool of asynchronous connections (configurable size)

### Isolation

- `isolated_schema`: Isolated schema for testing (auto-cleanup)
- `async_isolated_schema`: Async version of isolated schema
- `temp_table`: Temporary table for testing (auto-cleanup)
- `async_temp_table`: Async version of temporary table

### Chaos Injection

- `chaos_injector`: Utilities for injecting delays, failures, retries
- `pg_sleep_injector`: PostgreSQL-based delay injection
- `async_pg_sleep_injector`: Async version of pg_sleep_injector

### Monitoring

- `transaction_monitor`: Monitor active transactions and locks
- `async_transaction_monitor`: Async version of transaction monitor

### Load Generation

- `load_generator`: Generate database load for stress testing
- `async_load_generator`: Async version of load generator

### Advanced Scenarios

- `deadlock_setup`: Utilities for creating deadlock scenarios
- `async_deadlock_setup`: Async version of deadlock setup
- `connection_stressor`: Utilities for stressing connections
- `schema_isolator`: Create isolated schemas for testing

## Chaos Injection Utilities

### ChaosInjector Class

```python
from tests.chaos.utils import ChaosInjector

# Inject random delay
await ChaosInjector.random_delay(min_ms=10, max_ms=100)

# Retry with backoff
result = await ChaosInjector.with_retry(my_function, max_attempts=3)

# Simulate connection failure
with ChaosInjector.simulate_connection_failure(probability=0.1):
    # Code that might fail
    pass
```

### Database State Snapshots

```python
from tests.chaos.utils import DatabaseStateSnapshot

snapshot = DatabaseStateSnapshot(conn)

# Capture state
snapshot.capture("before", "SELECT * FROM my_table")

# Modify data
# ...

# Compare state
matches, message = snapshot.compare("before", "SELECT * FROM my_table")
assert matches, message
```

### Transaction Monitoring

```python
from tests.chaos.fixtures import transaction_monitor

# Get active transactions
transactions = transaction_monitor.get_active_transactions()

# Get current locks
locks = transaction_monitor.get_locks()

# Find blocking queries
blocking = transaction_monitor.get_blocking_queries()
```

## CI Integration

Chaos tests run in a separate CI job that is allowed to fail initially:

```yaml
# .github/workflows/chaos-tests.yml
test-chaos:
  continue-on-error: true  # Initially allowed to fail
```

As bugs are fixed, tests are moved from "allowed to fail" to "must pass".

## Development Workflow

### 1. Write Test Structure

```python
@pytest.mark.chaos
@pytest.mark.concurrent
def test_my_chaos_scenario(sync_conn, chaos_injector, transaction_monitor):
    """Test description."""
    # Setup
    # Inject chaos
    # Verify behavior
    # Assert expectations
```

### 2. Run Test Locally

```bash
# Run specific test
pytest tests/chaos/test_my_file.py::test_my_chaos_scenario -v

# Run with debugging
pytest tests/chaos/test_my_file.py::test_my_chaos_scenario -v -s

# Run with coverage
pytest tests/chaos/test_my_file.py::test_my_chaos_scenario --cov=pggit
```

### 3. Handle Expected Failures

Initially, most chaos tests will fail. This is expected! The goal is to:

1. **Document expected failures** in test comments
2. **Fix the underlying issues** in the main codebase
3. **Convert failing tests to passing tests**

### 4. Performance Considerations

- Use `@pytest.mark.slow` for tests >30 seconds
- Use parallel execution: `pytest -n 4`
- Limit resource-intensive tests to CI only
- Use fixtures with appropriate scopes (`function`, `session`)

## Best Practices

### Test Isolation
- Each test gets fresh database state
- Use isolated schemas to avoid conflicts
- Clean up after each test automatically

### Failure Injection
- Use realistic failure scenarios
- Document probability and timing of failures
- Ensure failures don't leave persistent state

### Performance Testing
- Separate slow tests with markers
- Use appropriate timeouts
- Monitor resource usage during tests

### Async Testing
- Use `async_conn` for async operations
- Prefer async fixtures for concurrent scenarios
- Handle async cleanup properly

## Troubleshooting

### Common Issues

**Connection Pool Exhausted**
```python
# Use smaller pool sizes for testing
@pytest.mark.parametrize("conn_pool", [5], indirect=True)
def test_with_small_pool(conn_pool):
    pass
```

**Deadlock Detection**
```python
# Monitor for deadlocks
locks = transaction_monitor.get_locks()
blocking = transaction_monitor.get_blocking_queries()
```

**Test Timeouts**
```python
# Add timeout to long-running tests
@pytest.mark.timeout(60)
def test_long_running_scenario():
    pass
```

### Debugging Failed Tests

```bash
# Run with detailed output
pytest tests/chaos/ -v -s --tb=long

# Run single failing test
pytest tests/chaos/test_file.py::test_name -v -s

# Check database state
psql -d pggit_chaos_test -c "SELECT * FROM pg_stat_activity;"

# View locks
psql -d pggit_chaos_test -c "SELECT * FROM pg_locks;"
```

## Contributing

When adding new chaos tests:

1. **Follow naming conventions**: `test_<category>_<scenario>.py`
2. **Add appropriate markers**: `@pytest.mark.chaos`, category markers
3. **Document expected behavior**: Clear docstrings and comments
4. **Include cleanup**: Use fixtures for automatic cleanup
5. **Test locally first**: Ensure tests run in development environment
6. **Update this README**: Document new patterns and utilities

## Related Documentation

- **Phase Plans**: See `.phases/chaos-engineering-suite/` for detailed implementation plans
- **CI Workflows**: See `.github/workflows/chaos-tests.yml` for CI configuration
- **Main Documentation**: See `docs/testing/CHAOS_ENGINEERING.md` (created in Phase 8)