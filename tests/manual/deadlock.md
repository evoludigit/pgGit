# Deadlock Detection and Recovery Testing

## Objective

Verify that pgGit properly handles deadlock scenarios and recovers gracefully.

## Prerequisites

- PostgreSQL 13+ installed and running
- pgGit extension installed
- `psql` command-line tool available
- Two terminal windows for concurrent operations

## Setup

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

## Test Procedure

### Test 1: Basic Deadlock Scenario

**Terminal 1:**
```bash
psql -d pggit_deadlock_test
```

**Terminal 1 - SQL:**
```sql
BEGIN;
-- Create job 1
INSERT INTO pggit.backup_jobs (backup_id, job_type, command, tool, status)
VALUES (gen_random_uuid(), 'backup', 'cmd1', 'pgbackrest', 'pending')
RETURNING job_id INTO job1_id;

-- Lock job 1 (hold this lock)
SELECT pggit.reset_job(job1_id);
```

**Terminal 2 - SQL (while Terminal 1 is waiting):**
```bash
psql -d pggit_deadlock_test
```

```sql
BEGIN;
-- Create job 2
INSERT INTO pggit.backup_jobs (backup_id, job_type, command, tool, status)
VALUES (gen_random_uuid(), 'backup', 'cmd2', 'pgbackrest', 'pending')
RETURNING job_id INTO job2_id;

-- Try to lock job 1 (will wait)
SELECT pggit.reset_job(job1_id);

-- Commit this transaction
COMMIT;
```

**Terminal 1 - SQL (after timeout or release):**
```sql
-- Try to lock job 2 (would cause deadlock if not handled)
SELECT pggit.reset_job(job2_id);
COMMIT;
```

## Expected Behavior

One of the following should occur:

1. **Automatic Deadlock Detection:** PostgreSQL detects the deadlock and rolls back one transaction, logging an error
2. **Proper Error Handling:** The application catches the deadlock error and retries with backoff
3. **Transaction Isolation:** Individual transactions complete without interference

## Success Criteria

✅ No crashes or database corruption
✅ At least one transaction completes successfully
✅ Error messages are logged appropriately
✅ The system recovers without manual intervention

## Failure Scenarios

❌ Database hangs indefinitely
❌ Connections stuck in lock wait
❌ Data corruption or inconsistency
❌ Cascading failures affecting other operations

## Cleanup

```bash
psql -U postgres -c "DROP DATABASE pggit_deadlock_test;"
```

## Notes

- Deadlock is a normal part of concurrent database operations
- PostgreSQL handles most deadlocks automatically
- The key is that the application handles the error gracefully
- This test is difficult to automate due to race conditions and timing requirements
