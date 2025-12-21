# Chaos Engineering Testing Guide

Comprehensive guide for running, understanding, and contributing to the pggit chaos engineering test suite.

## Quick Start

### Run all chaos tests
```bash
pytest tests/chaos/ -v -m chaos
```

### Run by category
```bash
pytest tests/chaos/ -v -m property        # Property-based tests
pytest tests/chaos/ -v -m concurrent      # Concurrency tests
pytest tests/chaos/ -v -m transaction     # Transaction tests
pytest tests/chaos/ -v -m resource        # Resource exhaustion
pytest tests/chaos/ -v -m corruption      # Corruption detection
pytest tests/chaos/ -v -m migration       # Migration tests
pytest tests/chaos/ -v -m recovery        # Recovery procedures
```

### Run smoke tests (fast, must pass)
```bash
pytest tests/chaos/ -v -m "chaos and not slow and not destructive"
```

### Run with Hypothesis statistics
```bash
pytest tests/chaos/ -v --hypothesis-show-statistics
```

## Test Categories

### Must-Pass Tests (Smoke)
These tests MUST pass for PR approval. They are fast (< 30s) and non-destructive:
- Basic property tests (non-slow variants)
- Simple concurrency tests (< 10 workers)
- Transaction rollback tests
- Basic data integrity tests

Run with:
```bash
pytest tests/chaos/ -v -m "chaos and not slow and not destructive"
```

**Expected**: ~5 minutes, 100% pass rate

### Can-Fail Tests (Full Suite)
These tests may fail while bugs are being fixed. They cover advanced scenarios:
- High-concurrency tests (50+ workers)
- Load tests (100+ connections)
- Crash recovery scenarios
- Corruption detection tests
- Complex migration failures

Run with:
```bash
pytest tests/chaos/ -v -m chaos
```

**Expected**: ~90 minutes, 85-95% pass rate during development

## Test Markers Reference

| Marker | Purpose | Must Pass? | Count |
|--------|---------|-----------|-------|
| `chaos` | All chaos engineering tests | Partial | 130+ |
| `property` | Property-based with Hypothesis | Yes (smoke) | 40+ |
| `concurrent` | Concurrency/race conditions | Partial | 20+ |
| `transaction` | Transaction failures/rollback | Yes | 15+ |
| `resource` | Resource exhaustion scenarios | Partial | 20+ |
| `corruption` | Corruption detection | No | 10+ |
| `migration` | Migration failure scenarios | No | 5+ |
| `recovery` | Recovery procedures | No | 6+ |
| `load` | Load/stress testing | No | 5+ |
| `slow` | Tests >30 seconds | No | 30+ |
| `destructive` | May require special setup | No | 10+ |

## Running Tests Locally

### Prerequisites
```bash
# Install chaos dependencies
uv pip install -e ".[chaos]"

# Ensure PostgreSQL is running
# Connection: postgresql://postgres@localhost/pggit_chaos_test
```

### Basic Usage

**Run entire chaos suite**:
```bash
pytest tests/chaos/ -v
```

**Run specific test file**:
```bash
pytest tests/chaos/test_concurrent_commits.py -v
```

**Run specific test**:
```bash
pytest tests/chaos/test_concurrent_commits.py::TestConcurrentCommits::test_concurrent_commits_same_branch -v
```

**Run with parallelization** (4 workers):
```bash
pytest tests/chaos/ -v -n 4
```

**Show Hypothesis statistics**:
```bash
pytest tests/chaos/ -v --hypothesis-show-statistics
```

**Debug with detailed output**:
```bash
pytest tests/chaos/test_name.py -v --tb=long -s
```

**Run with specific seed** (reproduce failing Hypothesis test):
```bash
pytest tests/chaos/ -v --hypothesis-seed=1234567890
```

## Test Organization

```
tests/chaos/
├── README.md                      # Chaos testing overview
├── TESTING.md                     # This file
├── pytest.ini                     # Pytest configuration
├── conftest.py                    # Shared fixtures and configuration
├── utils.py                       # Chaos injection utilities
│
├── test_property_based_*.py       # Property-based tests (Hypothesis)
│   ├── test_property_based_core.py
│   ├── test_property_based_data.py
│   └── test_property_based_migrations.py
│
├── test_concurrent_*.py           # Concurrency tests
│   ├── test_concurrent_commits.py
│   ├── test_concurrent_branching.py
│   ├── test_concurrent_versioning.py
│   └── test_deadlock_scenarios.py
│
├── test_transaction_*.py          # Transaction safety tests
│   └── test_transaction_rollback.py
│
├── test_*_failures.py             # Failure scenario tests
│   ├── test_constraint_violations.py
│   ├── test_crash_recovery.py
│   ├── test_migration_failures.py
│   ├── test_partial_failures.py
│   └── test_serialization_failures.py
│
├── test_resource_*.py             # Resource exhaustion tests
│   ├── test_connection_exhaustion.py
│   ├── test_disk_space.py
│   ├── test_load_stress.py
│   └── test_memory_pressure.py
│
├── test_*_integrity.py            # Data integrity tests
│   ├── test_data_integrity.py
│   ├── test_schema_corruption.py
│   └── test_recovery_procedures.py
│
└── __pycache__/                   # pytest and Python cache
```

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

## Writing New Chaos Tests

### Example 1: Property-Based Test
```python
import pytest
from hypothesis import given, strategies as st

@pytest.mark.chaos
@pytest.mark.property
@given(num_items=st.integers(min_value=1, max_value=100))
def test_bulk_insert_property(sync_conn, num_items: int):
    """Property: bulk inserts should never lose data."""
    # Setup
    sync_conn.execute("CREATE TABLE test_items (id SERIAL PRIMARY KEY, value INT)")

    # Execute
    for i in range(num_items):
        sync_conn.execute("INSERT INTO test_items (value) VALUES (%s)", [i])

    # Verify
    result = sync_conn.execute("SELECT COUNT(*) FROM test_items").fetchone()
    assert result[0] == num_items, f"Expected {num_items} items, got {result[0]}"
```

### Example 2: Concurrency Test
```python
import pytest
from concurrent.futures import ThreadPoolExecutor

@pytest.mark.chaos
@pytest.mark.concurrent
def test_concurrent_updates(isolated_schema):
    """Test concurrent updates to same table."""

    def worker(worker_id):
        conn = isolated_schema.connection
        for i in range(10):
            conn.execute(
                "UPDATE test_table SET value = %s WHERE id = %s",
                [worker_id * 10 + i, worker_id]
            )
            conn.commit()

    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = [executor.submit(worker, i) for i in range(5)]
        results = [f.result() for f in futures]

    # Verify no conflicts
    conn = isolated_schema.connection
    count = conn.execute("SELECT COUNT(*) FROM test_table").fetchone()[0]
    assert count == 5
```

### Example 3: Transaction Rollback Test
```python
@pytest.mark.chaos
@pytest.mark.transaction
def test_partial_transaction_rollback(sync_conn, isolated_schema):
    """Test that partial transaction failures rollback completely."""

    try:
        sync_conn.execute("BEGIN")
        sync_conn.execute("INSERT INTO test_table (value) VALUES (1)")
        sync_conn.execute("INVALID SQL")  # Force error
        sync_conn.commit()
    except Exception as e:
        sync_conn.rollback()

    # Verify rollback
    result = sync_conn.execute("SELECT COUNT(*) FROM test_table").fetchone()
    assert result[0] == 0, "Transaction should have rolled back completely"
```

## CI Integration

### Automatic Runs
- **On PR**: Smoke tests only (must pass for merge)
- **On main push**: Full suite (can fail)
- **Weekly (Sunday 3 AM UTC)**: Comprehensive chaos tests on PostgreSQL 15, 16, 17

### Manual Trigger
Trigger via GitHub Actions UI:
1. Go to: Actions → Chaos Engineering Tests
2. Click "Run workflow"
3. Select test category (smoke, property, concurrent, etc.)
4. Click "Run workflow"

### View Results
- Go to: Actions → Recent workflow run
- Download artifacts (XML results and HTML reports)
- Review test results and statistics

## Debugging Failed Tests

### Get detailed output
```bash
pytest tests/chaos/test_name.py -v --tb=long --log-cli-level=DEBUG
```

### Run single failing test with PDB
```bash
pytest tests/chaos/test_name.py::test_function -v --pdb
```

### Check PostgreSQL state during test
```bash
psql -d pggit_chaos_test -c "SELECT * FROM pg_stat_activity;"
```

### View active locks
```bash
psql -d pggit_chaos_test -c "SELECT * FROM pg_locks;"
```

### Reproduce Hypothesis failure
Look for "Falsifying example" in output and rerun with seed:
```bash
pytest tests/chaos/ -v --hypothesis-seed=<SEED_NUMBER>
```

### Check for deadlocks
```bash
psql -d pggit_chaos_test -c "
  SELECT * FROM pg_stat_statements
  WHERE query LIKE '%LOCK%' ORDER BY calls DESC LIMIT 10;
"
```

## Performance Considerations

### Test Execution Time Breakdown

| Category | Count | Time | Per Test |
|----------|-------|------|----------|
| Property-based | 40+ | ~20 min | 30 sec |
| Concurrent | 20+ | ~25 min | 1 min |
| Transaction | 15+ | ~5 min | 20 sec |
| Resource | 20+ | ~30 min | 1.5 min |
| Corruption | 10+ | ~10 min | 1 min |
| Other | 25+ | ~5 min | 12 sec |
| **Total** | **130+** | **~95 min** | **44 sec** |

### Optimization Tips
- Use `pytest -n 4` for parallel execution (4 workers)
- Skip slow tests: `pytest -v -m "chaos and not slow"`
- Run categories individually: `pytest -v -m property`
- Use `--maxfail=5` to stop after 5 failures

### Resource Limits
- Default timeout: 300 seconds (5 minutes)
- Connection pool: 10 connections
- Memory per test: ~500 MB
- Total test suite: ~5 GB memory

## Troubleshooting

### Connection Errors
```
psycopg.OperationalError: connection refused
```
**Solution**: Ensure PostgreSQL is running:
```bash
postgres -D /usr/local/var/postgres  # macOS
sudo service postgresql start         # Linux
```

### Test Timeouts
```
pytest.PytestUnraisableExceptionWarning: TimeoutError
```
**Solution**: Increase timeout or check for deadlocks:
```bash
pytest tests/chaos/ --timeout=600  # 10 minutes
```

### Hypothesis Health Check Failures
```
hypothesis.errors.FailedHealthCheck
```
**Solution**: Check for issues in test or adjust settings:
```python
@settings(suppress_health_check=[HealthCheck.too_slow])
```

### Out of Memory
**Solution**: Reduce parallel workers:
```bash
pytest tests/chaos/ -n 2  # Instead of -n 4
```

## Best Practices

### For Test Authors
1. **Always clean up**: Use fixtures with proper cleanup
2. **Isolated tests**: Each test should be independent
3. **Clear assertions**: Use descriptive error messages
4. **Appropriate markers**: Tag tests correctly
5. **Document assumptions**: Explain what the test validates
6. **Use fixtures**: Don't reinvent database setup

### For Contributors
1. **Run smoke tests locally**: `pytest -m "chaos and not slow and not destructive"`
2. **Test with multiple PostgreSQL versions**: 15, 16, 17
3. **Check for flakiness**: Run tests multiple times
4. **Review test output**: Look for warnings and deprecations
5. **Update documentation**: Document new patterns and fixtures

### For Maintainers
1. **Monitor pass rates**: Track trends over time
2. **Investigate failures**: Triage and create issues
3. **Update baselines**: Adjust expected pass rates quarterly
4. **Performance tracking**: Monitor test execution time
5. **Regression detection**: Catch performance degradation

## Contribution Workflow

### Adding a New Chaos Test

1. **Create test file** in appropriate directory:
   ```bash
   tests/chaos/test_my_scenario.py
   ```

2. **Import required fixtures**:
   ```python
   import pytest
   from tests.chaos.conftest import sync_conn, isolated_schema
   ```

3. **Write test with markers**:
   ```python
   @pytest.mark.chaos
   @pytest.mark.mymarker
   def test_my_scenario(sync_conn):
       # Test implementation
       pass
   ```

4. **Run locally**:
   ```bash
   pytest tests/chaos/test_my_scenario.py -v
   ```

5. **Update this guide** if adding new patterns

6. **Commit with message**:
   ```
   test(chaos): add test_my_scenario [RED/GREEN/REFACTOR]
   ```

## Resources

- [Hypothesis Documentation](https://hypothesis.readthedocs.io/)
- [Pytest Documentation](https://docs.pytest.org/)
- [PostgreSQL Concurrency Control](https://www.postgresql.org/docs/current/mvcc.html)
- [Chaos Engineering Principles](https://principlesofchaos.org/)

## Next Steps

- Review Phase 8 documentation (coming next)
- Monitor test execution trends
- Gradually increase must-pass test coverage
- Establish incident response procedures
