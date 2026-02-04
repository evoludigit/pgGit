# Deadlock Detection and Recovery Testing

## Overview

**Status**: Automated tests available in chaos suite

Deadlock detection and recovery testing is now integrated into the automated chaos test suite. See [`tests/chaos/test_deadlock_scenarios.py`](../../chaos/test_deadlock_scenarios.py) for comprehensive automated tests.

## Automated Test Suite

The chaos test suite provides dedicated deadlock testing:

### Available Tests
1. **`test_circular_lock_deadlock`** - Classic circular lock scenario
   - Worker 1: Lock A → Lock B
   - Worker 2: Lock B → Lock A
   - Validates PostgreSQL deadlock detection

2. **Additional deadlock scenarios** in `TestDeadlockScenarios` class

### Run Automated Tests

```bash
# Run all deadlock tests
pytest tests/chaos/test_deadlock_scenarios.py -v

# Run specific test
pytest tests/chaos/test_deadlock_scenarios.py::TestDeadlockScenarios::test_circular_lock_deadlock -v

# Run with timeout (deadlock tests can hang)
pytest tests/chaos/test_deadlock_scenarios.py -v --timeout=30
```

## Manual Testing (If Needed)

For manual deadlock verification:

### Prerequisites

- PostgreSQL 13+ installed and running
- pgGit extension installed
- `psql` command-line tool available
- Two terminal windows for concurrent operations

### Setup

1. Create a test database:
```bash
psql -U postgres -c "CREATE DATABASE pggit_deadlock_test;"
```

2. Install pgGit extension:
```bash
cd sql
psql -d pggit_deadlock_test -f install.sql
```

3. Verify installation:
```bash
psql -d pggit_deadlock_test -c "SELECT COUNT(*) FROM pggit.branches;"
```

### Test Procedure: Circular Lock Deadlock

**Terminal 1:**
```bash
psql -d pggit_deadlock_test
```

**Terminal 1 - SQL:**
```sql
CREATE TABLE deadlock_table_a (id INT);
CREATE TABLE deadlock_table_b (id INT);
INSERT INTO deadlock_table_a VALUES (1);
INSERT INTO deadlock_table_b VALUES (1);

BEGIN;
LOCK TABLE deadlock_table_a IN EXCLUSIVE MODE;
-- Sleep 1 second, giving terminal 2 time to lock table B
SELECT pg_sleep(1);
LOCK TABLE deadlock_table_b IN EXCLUSIVE MODE;
COMMIT;
```

**Terminal 2 - SQL (while Terminal 1 is waiting):**
```bash
psql -d pggit_deadlock_test
```

```sql
BEGIN;
LOCK TABLE deadlock_table_b IN EXCLUSIVE MODE;
-- Sleep 0.5 second to let terminal 1 proceed
SELECT pg_sleep(0.5);
LOCK TABLE deadlock_table_a IN EXCLUSIVE MODE;
COMMIT;
```

## Expected Behavior

One transaction will fail with deadlock error:
```
ERROR: deadlock detected
```

PostgreSQL will automatically:
1. Detect the circular lock dependency
2. Rollback one of the transactions
3. Return a deadlock error to the client

## Success Criteria

✅ One transaction completes successfully
✅ One transaction fails with deadlock error
✅ No database corruption
✅ No hanging connections
✅ System recovers automatically

## Failure Scenarios (Should NOT Occur)

❌ Database hangs indefinitely
❌ Connections stuck in lock wait state
❌ Data corruption or inconsistency
❌ Multiple transactions stuck (cascading deadlock)
❌ Orphaned locks

## Cleanup

```bash
psql -U postgres -c "DROP DATABASE pggit_deadlock_test;"
```

## Why Deadlock Testing is in Chaos Suite

Deadlock tests require:
- Precise timing and race condition setup
- Multiple concurrent connections
- Ability to control execution order
- Tolerance for timing-dependent behavior

These characteristics make deadlock testing better suited for the chaos suite rather than standard E2E tests. The chaos suite is specifically designed for:
- Complex concurrent scenarios
- Race condition reproduction
- Failure mode validation
- System resilience testing

## References

- [PostgreSQL Deadlock Documentation](https://www.postgresql.org/docs/current/explicit-locking.html)
- [Chaos Test Suite](../../chaos/README.md)
- [Test Status Report](../../chaos/TEST_STATUS.md)
