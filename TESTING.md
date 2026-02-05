# pgGit Testing Infrastructure

## Overview

pgGit uses a modern, isolated test fixture architecture with guaranteed per-test cleanup and zero cross-test state pollution. This document guides developers in writing tests and choosing appropriate fixtures.

## Test Fixtures

### Four Fixture Types

The test infrastructure provides 4 specialized fixtures optimized for different test scenarios:

#### 1. **db_unit** - Unit Testing (TransactionDatabaseFixture)

**Isolation:** Transaction-based rollback
**Overhead:** ~1ms per test
**Scope:** Single-feature unit tests

**Use for:**
- SQL function tests
- Constraint validation
- Schema validation
- DDL tracking tests
- Individual feature behavior

**Guarantees:**
- Complete automatic isolation via `BEGIN/ROLLBACK`
- All changes rolled back after test
- No cleanup code needed

**Example:**
```python
def test_unique_constraint(db_unit):
    """Test that unique constraint works correctly."""
    db_unit.execute("CREATE TABLE test (id INT UNIQUE)")
    db_unit.execute("INSERT INTO test VALUES (1)")

    with pytest.raises(Exception):
        db_unit.execute("INSERT INTO test VALUES (1)")

    # Automatic rollback - no cleanup needed
```

#### 2. **db_integration** - Integration Testing (TransactionDatabaseFixture)

**Isolation:** Transaction-based rollback
**Overhead:** ~1ms per test
**Scope:** Multi-component workflows

**Use for:**
- Multi-operation workflows
- Dependency tracking tests
- Branch/merge operations
- Tests with explicit transaction testing
- Feature interaction tests

**Guarantees:**
- Per-test isolation via `BEGIN/ROLLBACK`
- Can test transaction behavior with explicit `BEGIN/COMMIT`
- Works with connection pooling
- Automatic cleanup

**Example:**
```python
def test_dependency_chain(db_integration):
    """Test that dependencies are properly tracked across tables."""
    db_integration.execute("CREATE TABLE base (id INT PRIMARY KEY)")
    db_integration.execute("CREATE TABLE dependent (id INT, base_id INT REFERENCES base(id))")

    # Verify dependency relationship
    deps = db_integration.execute("""
        SELECT * FROM pggit.dependencies
        WHERE dependent_table = 'dependent'
    """)
    assert len(deps) >= 1

    # Automatic rollback at test end
```

#### 3. **db_e2e** - End-to-End Testing (TransactionDatabaseFixture)

**Isolation:** Transaction-based rollback
**Overhead:** ~1ms per test
**Scope:** Full workflow scenarios

**Use for:**
- Full workflow tests
- Backup/recovery scenarios
- User journey tests
- Cross-feature integration
- Realistic PostgreSQL scenarios

**Guarantees:**
- Test-level isolation via `BEGIN/ROLLBACK`
- Realistic PostgreSQL environment
- Complete cleanup on test end
- No transaction limitations for test code

**Example:**
```python
def test_backup_recovery_workflow(db_e2e):
    """Test complete backup and recovery scenario."""
    # Setup data
    db_e2e.execute("CREATE TABLE data (id INT, value TEXT)")
    db_e2e.execute("INSERT INTO data VALUES (1, 'important')")

    # Create backup
    backup_id = db_e2e.execute_returning("""
        SELECT pggit.register_backup('test-backup', 'full', 'pgbackrest', 's3://bucket/path', 'commit-hash')
    """)

    # Verify backup metadata
    result = db_e2e.execute("""
        SELECT backup_id, status FROM pggit.backups
        WHERE backup_id = %s
    """, backup_id[0])
    assert result[0][1] == 'registered'

    # Test recovery
    db_e2e.execute("""
        SELECT pggit.restore_backup(%s)
    """, backup_id[0])

    # Automatic transaction rollback at test end
```

#### 4. **db_load** - Load/Performance Testing (LoadDatabaseFixture)

**Isolation:** Manual cleanup
**Overhead:** ~0ms per test (no auto-isolation)
**Scope:** Performance benchmarks

**Use for:**
- Performance benchmarks
- Stress tests
- Throughput measurements
- Connection pool exhaustion tests
- Load testing scenarios

**Guarantees:**
- Minimal overhead (no automatic cleanup)
- Manual cleanup responsibility
- Built-in timing metrics

**Important:** Must call `cleanup()` after test

**Example:**
```python
def test_commit_throughput(db_load):
    """Benchmark commit operation throughput."""
    iterations = 10000

    for i in range(iterations):
        db_load.execute_timed("SELECT pggit.commit_changes(...)")

    throughput = iterations / db_load.metrics['time']
    print(f"Throughput: {throughput:.0f} ops/sec")
    assert throughput > 100  # At least 100 ops/sec expected

    # Manual cleanup required
    db_load.cleanup()
```

---

## Fixture Selection Guide

| Scenario | Fixture | Why |
|----------|---------|-----|
| Test single SQL function | `db_unit` | Atomic isolation, fastest |
| Test table constraints | `db_unit` | No cross-test pollution |
| Test multi-table workflow | `db_integration` | Captures interaction patterns |
| Test branch operations | `db_integration` | Can use explicit transactions |
| Test full recovery scenario | `db_e2e` | Realistic PostgreSQL behavior |
| Test user journey | `db_e2e` | Can test complex sequences |
| Benchmark query performance | `db_load` | Zero overhead for timing |
| Stress test connection pool | `db_load` | Need to control cleanup |

---

## Test Isolation Guarantees

### What's Guaranteed

✅ **Per-Test Isolation:** Each test starts with clean database state
✅ **Automatic Cleanup:** All changes rolled back at test end
✅ **No Cross-Test Pollution:** Tests pass individually and together
✅ **Deterministic Execution:** Tests pass/fail consistently (never flaky due to state)
✅ **Parallel Safe:** Tests can run in parallel with `-n` flag
✅ **Random Order Safe:** Tests pass with `--random-order` flag
✅ **Session Setup:** Tables created once per session, cleaned per-test

### Implementation Details

Each fixture (except `db_load`) follows this pattern:

```
Session Start:
  ↓
db_setup (runs once)
  - Creates pgGit schema tables
  - Verifies functions exist
  ↓
Per-Test:
  - Get connection from pool
  - BEGIN transaction (create savepoint)
  - Run test code
  - ROLLBACK transaction
  - Return connection to pool
  ↓
Session End:
  - Container cleanup
```

---

## Writing Tests

### Best Practices

#### 1. Choose the Right Fixture

```python
# ✅ GOOD - db_unit for single feature
def test_schema_exists(db_unit):
    result = db_unit.execute(
        "SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit'"
    )
    assert result is not None

# ✅ GOOD - db_integration for workflow
def test_branch_creation_and_tracking(db_integration):
    branch_id = db_integration.execute_returning(
        "SELECT pggit.create_branch('feature-branch')"
    )
    assert branch_id is not None

# ✅ GOOD - db_e2e for full scenario
def test_complete_git_workflow(db_e2e):
    # Create branch, add commits, merge - all in one test
    pass

# ❌ BAD - Wrong fixture choice
def test_single_query(db_e2e):  # Should be db_unit
    pass
```

#### 2. Don't Clean Up Manually

```python
# ❌ WRONG - Manual cleanup not needed
def test_something(db_unit):
    db_unit.execute("CREATE TABLE test ...")
    db_unit.execute("ROLLBACK")  # Don't do this!

# ✅ RIGHT - Automatic cleanup
def test_something(db_unit):
    db_unit.execute("CREATE TABLE test ...")
    # Cleanup happens automatically
```

#### 3. Use execute_returning for SELECT queries returning values

```python
# ✅ RIGHT - Use execute_returning for RETURNING clause
backup_id = db_e2e.execute_returning("""
    INSERT INTO pggit.backups (...) VALUES (...) RETURNING backup_id
""")
assert backup_id is not None

# ✅ RIGHT - Use execute_returning for SELECT returning single value
count = db_unit.execute_returning("SELECT COUNT(*) FROM pggit.branches")
assert count is not None

# ✅ RIGHT - Use execute for SELECT returning multiple rows
rows = db_unit.execute("SELECT * FROM pggit.branches WHERE status = 'ACTIVE'")
for row in rows:
    print(row)
```

#### 4. Test Independence

```python
# ✅ RIGHT - Tests are completely independent
def test_first_operation(db_unit):
    result = db_unit.execute("SELECT 1")
    assert result[0][0] == 1

def test_second_operation(db_unit):
    # This starts fresh, even though test_first_operation ran before
    result = db_unit.execute("SELECT 2")
    assert result[0][0] == 2

# ✅ RIGHT - Tests pass in any order
# pytest tests/test_file.py -v --random-order
```

#### 5. Error Testing

```python
# ✅ RIGHT - Use pytest.raises
def test_duplicate_key_error(db_unit):
    db_unit.execute("CREATE TABLE test (id INT UNIQUE)")
    db_unit.execute("INSERT INTO test VALUES (1)")

    with pytest.raises(Exception) as exc:
        db_unit.execute("INSERT INTO test VALUES (1)")

    assert 'unique' in str(exc.value).lower()
```

---

## Running Tests

### Run All E2E Tests

```bash
# Run all E2E tests
pytest tests/e2e/ -v

# Run with brief output
pytest tests/e2e/ -q

# Run specific test file
pytest tests/e2e/test_backup_automation.py -v

# Run specific test
pytest tests/e2e/test_backup_automation.py::TestJobQueue::test_enqueue_job -v
```

### Verify Test Isolation

```bash
# Run multiple times - should always pass
for i in {1..3}; do
  echo "Run $i:"
  pytest tests/e2e/test_backup_automation.py -q
done

# Run in random order - should always pass
pytest tests/e2e/test_backup_automation.py --random-order -q

# Run in parallel - should always pass
pytest tests/e2e/ -n 4 -q
```

### Run Validation Tests

```bash
# Verify fixture isolation guarantees
pytest tests/fixtures/test_fixture_isolation.py -v
```

---

## Debugging Tests

### Enable Verbose Output

```bash
pytest tests/e2e/test_file.py::TestClass::test_method -vv
```

### Capture stdout

```bash
pytest tests/e2e/test_file.py -s  # Shows print() statements
```

### Drop into Debugger

```python
def test_something(db_unit):
    import pdb; pdb.set_trace()  # Debugger will break here
    db_unit.execute("SELECT 1")
```

### Check Database State

```python
def test_debug(db_unit):
    # Query what exists
    schemas = db_unit.execute("""
        SELECT schema_name FROM information_schema.schemata
    """)
    print(f"Schemas: {schemas}")

    tables = db_unit.execute("""
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'pggit'
    """)
    print(f"pgGit tables: {tables}")
```

---

## Fixture API Reference

### Common Methods

All fixtures (db_unit, db_integration, db_e2e) provide:

```python
# Execute query and return all results (list of tuples)
results = db_unit.execute("SELECT * FROM pggit.branches")

# Execute query and return first row (tuple)
first_row = db_unit.execute_returning("SELECT * FROM pggit.branches LIMIT 1")

# Get first column value
count = db_unit.execute_returning("SELECT COUNT(*) FROM pggit.branches")[0]
```

### db_load Specific

```python
db_load.execute(query)              # Execute query
db_load.execute_timed(query)        # Execute with timing
db_load.cleanup()                   # Return connection to pool
print(db_load.metrics['queries'])   # Query count
print(db_load.metrics['time'])      # Total time
```

---

## Troubleshooting

### "FAILED - InFailedSqlTransaction: current transaction is aborted"

**Cause:** An earlier query failed, connection is in error state
**Solution:** Transaction automatically rolls back and connection is cleaned up for next test

**In test:**
```python
def test_with_error(db_unit):
    try:
        db_unit.execute("INVALID SQL")
    except:
        pass  # Error is expected

    # Subsequent queries might fail - this is expected with broken transaction
    # Use a fresh fixture for the actual test
```

### "duplicate key value violates unique constraint"

**Cause:** Data from previous test persisted
**Solution:** Verify you're using correct fixture with automatic cleanup

```python
# ✅ RIGHT - Uses db_e2e with automatic rollback
def test_with_persistence_issue(db_e2e):
    pass

# ❌ WRONG - Using db_load without cleanup()
def test_with_persistence_issue(db_load):
    # Need to call cleanup() or data persists
    pass
```

### Tests Pass Individually But Fail Together

**Cause:** Cross-test state pollution (fixture issue)
**Solution:** Verify all tests use appropriate fixtures

```bash
# If test fails in full suite but passes individually:
pytest tests/e2e/test_file.py::TestClass::test_method -v  # Passes
pytest tests/e2e/test_file.py -v  # Fails - indicates isolation issue

# Check fixture usage
grep "def test_" tests/e2e/test_file.py | head -5
```

---

## Architecture

### Fixture Implementation

Fixtures are implemented in `/tests/fixtures/isolated_database.py`:

- `IsolatedDatabaseFixture` - Base class with persistent connection
- `TransactionDatabaseFixture` - Uses BEGIN/ROLLBACK for isolation
- `SavepointDatabaseFixture` - Uses SAVEPOINTs (not currently used)
- `LoadDatabaseFixture` - No automatic isolation, manual cleanup

Fixture definitions are in `/tests/e2e/conftest.py`:

- `db_setup` - Session-scoped setup
- `db_unit` - Unit test fixture
- `db_integration` - Integration test fixture
- `db_e2e` - E2E test fixture
- `db_load` - Load test fixture

### Database Setup

```
PostgreSQL Container (Docker)
  ↓
pggit extension installed via sql/install.sql
  ↓
Session starts: creates pgGit schema tables once
  ↓
Per-test: transaction isolation, automatic rollback
  ↓
Session ends: container cleaned up
```

---

## Performance

### Overhead per Test

| Fixture | Overhead | Reason |
|---------|----------|--------|
| db_unit | ~1ms | BEGIN/ROLLBACK |
| db_integration | ~1ms | BEGIN/ROLLBACK |
| db_e2e | ~1ms | BEGIN/ROLLBACK |
| db_load | ~0ms | No cleanup |

### Suite Execution

- Full E2E suite: ~13-15 seconds for ~400 tests
- Validation tests: ~3 seconds for 15 tests
- Single test: ~3 seconds (includes container startup on first test)

---

## Contributing

When adding new tests:

1. **Choose fixture first:** Unit/Integration/E2E/Load
2. **Write test code:** Use fixture to access database
3. **Don't clean up:** Automatic rollback handles it
4. **Run verification:** `pytest test_file.py --random-order`
5. **Commit:** Submit PR with test

For more information, see:
- [pgGit README](README.md)
- [Test Infrastructure Phase 6-7 Implementation](CHANGELOG.md)
- Test fixture source: `/tests/fixtures/isolated_database.py`
- Test fixture definitions: `/tests/e2e/conftest.py`
