# Chaos Testing Troubleshooting Guide

Common issues, solutions, and debugging techniques for chaos engineering tests.

## Issue 1: Tests Hang Indefinitely

**Symptoms**:
- Tests run forever without completing
- No output after initial test start
- Process becomes stuck

**Causes**:
- Deadlock in concurrent tests
- Missing timeout configuration
- Infinite loop in test code
- Thread not terminating

**Solutions**:

Add timeout to specific test:
```bash
pytest tests/chaos/test_name.py --timeout=60
```

Check for deadlocks in PostgreSQL:
```bash
psql -d pggit_chaos_test -c "SELECT * FROM pg_locks WHERE NOT granted;"
```

Add timeout decorator:
```python
@pytest.mark.timeout(60)
def test_that_might_hang():
    pass
```

Monitor thread count:
```python
import threading
print(f"Active threads: {threading.active_count()}")
```

---

## Issue 2: Connection Refused Errors

**Symptoms**:
```
psycopg.OperationalError: connection to server at "localhost" (::1), port 5432 failed: Connection refused
```

**Causes**:
- PostgreSQL not running
- Wrong connection parameters
- Database doesn't exist
- Wrong username/password

**Solutions**:

Check PostgreSQL status:
```bash
pg_ctl status -D /var/lib/postgresql/data
```

Start PostgreSQL:
```bash
pg_ctl start -D /var/lib/postgresql/data
```

Or on macOS:
```bash
brew services start postgresql
```

Create test database:
```bash
createdb pggit_chaos_test
```

Verify connection:
```bash
psql postgresql://postgres@localhost/pggit_chaos_test -c "SELECT 1"
```

Check connection string:
```bash
# Should look like:
postgresql://postgres:password@localhost/pggit_chaos_test
```

---

## Issue 3: Hypothesis Tests Fail Inconsistently

**Symptoms**:
- Test passes sometimes, fails other times
- Different failures on each run
- Cannot reproduce failure reliably

**Causes**:
- Flaky test (timing-dependent)
- Insufficient shrinking
- Random seed changing
- Resource contentions

**Solutions**:

Reproduce with specific seed:
```bash
pytest tests/chaos/test_name.py --hypothesis-seed=SEED_FROM_FAILURE
```

Increase examples to find consistent failure:
```bash
pytest tests/chaos/test_name.py --hypothesis-profile=thorough
```

Check for timing issues and add delays:
```python
@pytest.mark.chaos
def test_with_timing_fix(sync_conn):
    sync_conn.execute("SELECT pg_sleep(0.1)")  # Explicit delay
    # Rest of test
```

Save baseline for comparison:
```bash
pytest tests/chaos/test_name.py --hypothesis-seed=0 -x  # Stop on first failure
```

---

## Issue 4: Trinity ID Collision Detected

**Symptoms**:
```
AssertionError: Trinity ID collision detected: [123, 123, 124, 125]
```

**Causes**:
- Race condition in Trinity ID generation
- Database sequence issues
- Transaction isolation problem
- Clock/timing issues

**Solutions**:

Check sequence state:
```sql
SELECT last_value, is_called FROM pggit.trinity_id_seq;
```

Reset sequence if corrupted:
```sql
SELECT setval('pggit.trinity_id_seq', (SELECT MAX(id) FROM pggit.trinity_ids));
```

Verify transaction isolation level:
```sql
SHOW transaction_isolation;
-- Should be "read committed" or higher
```

Check PostgreSQL version:
```bash
psql --version  # Should be 15+
```

---

## Issue 5: Out of Memory Errors

**Symptoms**:
```
MemoryError: Unable to allocate array
```

**Causes**:
- Large data generation in property tests
- Memory leak in test
- Too many concurrent connections
- Unbounded collections

**Solutions**:

Limit Hypothesis examples:
```python
@pytest.mark.chaos
@settings(max_examples=10)  # Instead of default 50
def test_with_limited_examples(sync_conn):
    pass
```

Use smaller data in strategies:
```python
@given(msg=st.text(max_size=100))  # Instead of 10000
def test_message(sync_conn, msg: str):
    pass
```

Clean up connections explicitly:
```python
@pytest.fixture
def conn_pool():
    pool = create_pool()
    yield pool
    pool.close()  # Ensure cleanup
```

Monitor memory usage:
```python
import tracemalloc
tracemalloc.start()
# ... operation ...
current, peak = tracemalloc.get_traced_memory()
print(f"Current: {current / 1024**2:.1f} MB; Peak: {peak / 1024**2:.1f} MB")
```

---

## Issue 6: Transaction Isolation Errors

**Symptoms**:
```
psycopg.errors.SerializationFailure: could not serialize access due to concurrent update
```

**Causes**:
- Expected behavior in concurrent tests!
- High contention on same rows
- Serializable isolation level
- Concurrent modification

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

If unexpected, reduce concurrency:
```python
@pytest.mark.parametrize("num_workers", [2, 3, 5])  # Instead of [50, 100]
def test_with_reduced_concurrency(db_connection_string, num_workers):
    pass
```

Or add retries:
```python
from tests.chaos.utils import ChaosInjector

result = ChaosInjector.with_retry(
    operation,
    max_attempts=3,
    backoff=0.1
)
```

Check isolation level:
```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
```

---

## Issue 7: pytest Cannot Find Tests

**Symptoms**:
```
collected 0 items
```

**Causes**:
- Wrong working directory
- Missing `__init__.py`
- Tests not matching naming pattern
- File not found

**Solutions**:

Check current directory:
```bash
pwd  # Should be repo root (where pyproject.toml is)
```

Verify test discovery:
```bash
pytest tests/chaos/ --collect-only
```

Check test file naming:
```bash
# Must be: test_*.py or *_test.py
ls tests/chaos/test_*.py
```

Check function naming:
```bash
# Must be: test_*() or *_test()
grep -E "def (test_|.*_test)" tests/chaos/test_*.py
```

Verify __init__.py exists:
```bash
touch tests/__init__.py tests/chaos/__init__.py
```

---

## Issue 8: CI Tests Pass Locally, Fail in CI

**Symptoms**:
- Tests pass on your machine
- Same tests fail in GitHub Actions
- Different PostgreSQL version in CI

**Causes**:
- Different PostgreSQL version
- Timing differences (CI is slower)
- Resource limits in CI
- Environment variables missing

**Solutions**:

Match CI PostgreSQL version locally:
```bash
docker run -p 5432:5432 postgres:17
# or
docker run -p 5432:5432 postgres:16
```

Increase timeouts for CI:
```python
@pytest.mark.timeout(300)  # 5 minutes for CI (vs 60 for local)
def test_slow_scenario(sync_conn):
    pass
```

Check CI logs for specifics:
- GitHub Actions → Workflow run → Test job → Full output
- Look for PostgreSQL version, Python version, error messages

Test with PostgreSQL version matrix:
```bash
# Test with all versions locally
for version in 15 16 17; do
    docker run -p 5432:5432 postgres:$version
    pytest tests/chaos/ -v
done
```

Set environment variables:
```bash
export PGHOST=localhost
export PGPORT=5432
export PGUSER=postgres
export PGPASSWORD=postgres
export PGDATABASE=pggit_chaos_test
```

---

## Issue 9: Schema Corruption Tests Fail

**Symptoms**:
```
AssertionError: Should detect corruption, but didn't
```

**Causes**:
- Corruption detection not implemented yet
- Test expects feature that doesn't exist
- Manual changes not triggering detection
- Schema validation missing

**Solutions**:

Many corruption tests are **designed to fail initially** - they're requirements for future features:

```python
@pytest.mark.skip(reason="Corruption detection not implemented yet")
def test_detect_manual_schema_change():
    # This test documents required feature
    pass
```

Check if test is marked as "can fail" in CI configuration:
```yaml
# .github/workflows/chaos-tests.yml
chaos-full:
    continue-on-error: true  # Can fail
```

Verify schema validation function exists:
```sql
SELECT pggit.validate_schema();
```

Check test expectation vs implementation:
```python
# If test expects function:
SELECT pggit.detect_schema_drift('table_name');

# But function doesn't exist, add it first
```

---

## Issue 10: Deadlock Tests Never Trigger Deadlock

**Symptoms**:
```
AssertionError: Expected deadlock, but all transactions succeeded
```

**Causes**:
- Timing issue (workers not overlapping)
- Insufficient lock contention
- Transaction too fast
- Wrong lock type

**Solutions**:

Add delays to ensure overlap:
```python
def worker1():
    conn.execute("LOCK TABLE a")
    time.sleep(1.0)  # Ensure worker2 starts
    conn.execute("LOCK TABLE b")

def worker2():
    time.sleep(0.5)  # Let worker1 acquire lock on a
    conn.execute("LOCK TABLE b")
    time.sleep(0.5)
    conn.execute("LOCK TABLE a")  # Now we have a cycle
```

Use explicit locking:
```python
# ✅ Good: Exclusive locks guarantee contention
conn.execute("LOCK TABLE ... IN EXCLUSIVE MODE")

# ❌ Bad: Access share doesn't always cause deadlock
conn.execute("LOCK TABLE ... IN ACCESS SHARE MODE")
```

Verify lock is held:
```sql
SELECT * FROM pg_locks WHERE pid = YOUR_PID;
```

Use synchronization primitive:
```python
import threading

barrier = threading.Barrier(2)

def worker1():
    conn.execute("LOCK TABLE a")
    barrier.wait()  # Wait for worker2
    conn.execute("LOCK TABLE b")  # Deadlock here
```

---

## Debugging Techniques

### Enable Verbose Logging

Full pytest output with maximum verbosity:
```bash
pytest tests/chaos/ -vv --tb=long --log-cli-level=DEBUG
```

PostgreSQL query logging:
```sql
-- In postgresql.conf:
log_statement = 'all'
log_duration = on
log_min_duration_statement = 0
```

Check logs:
```bash
tail -f /var/log/postgresql/postgresql-*.log
```

### Use PDB Debugger

Drop into debugger on failure:
```bash
pytest tests/chaos/test_name.py --pdb
```

In test code:
```python
import pdb; pdb.set_trace()

# Commands:
# h     - help
# c     - continue
# n     - next line
# s     - step into
# p var - print variable
# pp    - pretty print
```

### Check PostgreSQL State

Active queries:
```sql
SELECT pid, state, query FROM pg_stat_activity WHERE datname = 'pggit_chaos_test';
```

All locks:
```sql
SELECT locktype, relation::regclass, mode, granted, pid FROM pg_locks;
```

Waiting locks:
```sql
SELECT * FROM pg_stat_activity WHERE wait_event_type IS NOT NULL;
```

Deadlocks (past statistics):
```sql
SELECT * FROM pg_stat_database WHERE datname = 'pggit_chaos_test';
-- deadlocks column shows count
```

### Isolate and Reproduce

Run single failing test:
```bash
pytest tests/chaos/test_name.py::TestClass::test_method -v
```

Use marker filtering:
```bash
pytest tests/chaos/ -m "chaos and not slow" -v
```

Reproduce Hypothesis failure:
```bash
pytest tests/chaos/test_name.py --hypothesis-seed=12345678
```

Add print debugging:
```python
@pytest.mark.chaos
def test_with_debug(sync_conn):
    print("\n=== TEST START ===")
    print(f"Connection info: {sync_conn}")

    sync_conn.execute("CREATE TABLE debug_test (id INT)")
    print(f"Created table")

    print("=== TEST END ===")
```

Run with `-s` flag to see print output:
```bash
pytest tests/chaos/test_name.py -v -s
```

---

## Prevention

### Write Robust Tests

✅ **Good**: Handles expected failures
```python
try:
    result = risky_operation()
except ExpectedError:
    # Expected, not a test failure
    pass
```

❌ **Bad**: Assumes operation always succeeds
```python
result = risky_operation()  # May raise unexpected error
```

### Use Timeouts

✅ **Good**: Bounded execution time
```python
@pytest.mark.timeout(60)
def test_with_timeout():
    pass
```

❌ **Bad**: Can hang indefinitely
```python
def test_without_timeout():
    pass
```

### Clean Up Resources

✅ **Good**: Guaranteed cleanup
```python
@pytest.fixture
def resource():
    r = create_resource()
    yield r
    r.cleanup()

def test_with_resource(resource):
    # Use resource - cleanup automatic
    pass
```

❌ **Bad**: May leak resources
```python
def test():
    r = create_resource()
    # ... use r ...
    # Cleanup might not happen if test fails!
```

### Write Deterministic Tests

✅ **Good**: Uses fixed seeds
```python
@pytest.mark.chaos
def test_deterministic(sync_conn):
    # Don't rely on random timing
    sync_conn.execute("SELECT pg_sleep(1)")  # Explicit delay
```

❌ **Bad**: Relies on timing
```python
# Hope that operations complete in 100ms!
time.sleep(0.1)
assert condition  # May fail under load
```

---

## Getting Help

When stuck, provide this information:

1. **Full test output**:
   ```bash
   pytest tests/chaos/test_name.py -v --tb=long > output.txt 2>&1
   ```

2. **PostgreSQL logs**:
   ```bash
   tail -f /var/log/postgresql/postgresql-*.log
   ```

3. **System information**:
   ```bash
   psql --version
   python --version
   uname -a
   ```

4. **Minimal reproduction**:
   - Exact steps to reproduce
   - Specific test name
   - Hypothesis seed (if applicable)

5. **What you've tried**:
   - Changes you made
   - Solutions attempted
   - Results of each attempt

Create GitHub issue with all this information.

---

## FAQ

**Q: Why are my tests hanging?**
A: Check for deadlocks. Use `--timeout=60` to force exit. Review locks with `pg_locks` view.

**Q: How do I reproduce a flaky test?**
A: Use `--hypothesis-seed=SEED` where SEED is from failed run output.

**Q: Can I skip chaos tests for quick development?**
A: Yes: `pytest tests/ -m "not chaos"` runs only regular tests.

**Q: How much memory do chaos tests use?**
A: Typically <500MB per test. Smoke tests: ~2GB total. Full suite: ~5GB.

**Q: Why do concurrent tests sometimes timeout?**
A: Try increasing timeout: `pytest --timeout=300` or add explicit synchronization.

**Q: What if only one PostgreSQL version fails?**
A: Test with that version: `pytest --hypothesis-seed=0` then debug specific version.

**Q: Can I run tests in parallel?**
A: Use `pytest -n 4` for 4 workers (if tests are isolated).

**Q: How do I monitor test progress?**
A: Use `-v` for verbose: `pytest -v` shows each test as it runs.

---

## Still Stuck?

1. Check [CHAOS_ENGINEERING.md](CHAOS_ENGINEERING.md) for overview
2. Review [PATTERNS.md](PATTERNS.md) for examples
3. Search issue tracker: https://github.com/your-repo/issues
4. Create new issue with reproduction steps

**Remember**: Chaos tests are supposed to find failures. If a test fails, it means it's working!
