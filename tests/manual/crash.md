# Crash Recovery Testing

## Objective

Verify that pgGit maintains data integrity and recovers gracefully when the database crashes or connections are forcefully terminated.

## Prerequisites

- PostgreSQL 13+ installed in a container or VM (for safe crash testing)
- pgGit extension installed
- `psql` command-line tool available
- Docker (optional, but recommended for safety)

## Setup

### Option 1: Docker Container (Recommended)

1. Start PostgreSQL in Docker:
```bash
docker run -d \
  --name postgres-crash-test \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=pggit_crash_test \
  postgres:17-alpine
```

2. Install pgGit:
```bash
docker exec postgres-crash-test psql -U postgres -d pggit_crash_test -f /path/to/sql/install.sql
```

### Option 2: Local PostgreSQL

Create a test database:
```bash
psql -U postgres -c "CREATE DATABASE pggit_crash_test;"
cd sql
psql -d pggit_crash_test -f install.sql
```

## Test Procedure

### Test 1: Connection Drop During Operation

**Terminal 1:**
```bash
psql -d pggit_crash_test
```

**SQL:**
```sql
-- Start a long-running operation
BEGIN;
INSERT INTO pggit.backups (
  backup_name, backup_type, backup_tool, location, status
) VALUES (
  'crash-test-1', 'full', 'pgbackrest', 's3://bucket/crash1', 'in_progress'
);

-- This will be interrupted
SELECT pg_sleep(10);
COMMIT;
```

**While the sleep is running (Terminal 2):**
```bash
# Kill the connection
pkill -f "psql -d pggit_crash_test"
```

## Expected Behavior

- The transaction should be rolled back automatically
- The database should remain consistent
- No orphaned locks should remain
- Subsequent connections should work normally

## Verification

After the crash:

```bash
# Connect to the database
psql -d pggit_crash_test

# Check for data consistency
SELECT COUNT(*) FROM pggit.backups WHERE status = 'in_progress';
-- Should return 0 (incomplete backup was rolled back)

# Verify no locks are held
SELECT * FROM pg_stat_activity WHERE state = 'active';
-- Should show minimal activity

# Test normal operations
INSERT INTO pggit.backups (
  backup_name, backup_type, backup_tool, location, status
) VALUES (
  'recovery-test', 'full', 'pgbackrest', 's3://bucket/recovery', 'completed'
);
-- Should succeed without errors
```

### Test 2: Forced Database Restart

**Terminal 1:**
```bash
psql -d pggit_crash_test
```

**SQL - Start a transaction:**
```sql
BEGIN;
INSERT INTO pggit.backup_jobs (
  backup_id, job_type, command, tool, status
) VALUES (
  gen_random_uuid(), 'backup', 'cmd', 'pgbackrest', 'pending'
);

-- Keep transaction open
SELECT pg_sleep(30);
```

**Terminal 2 - Restart PostgreSQL:**

Docker:
```bash
docker restart postgres-crash-test
```

Local:
```bash
sudo systemctl restart postgresql
```

## Expected Outcome

✅ Database starts up without issues
✅ No data corruption
✅ WAL logs are applied correctly
✅ Normal operations resume after restart
✅ Incomplete transactions are rolled back

## Success Criteria

- ✅ Database recovers automatically
- ✅ Data consistency is maintained
- ✅ No manual intervention needed
- ✅ No error messages about corrupted data
- ✅ Subsequent operations work normally

## Failure Scenarios

❌ Database fails to start
❌ Data corruption detected
❌ Orphaned locks prevent operations
❌ Manual intervention needed (fsck, recovery tools)

## Cleanup

Docker:
```bash
docker stop postgres-crash-test
docker rm postgres-crash-test
```

Local:
```bash
psql -U postgres -c "DROP DATABASE pggit_crash_test;"
```

## Notes

- **WARNING:** This test will interrupt database operations. Only run on test systems.
- PostgreSQL is designed to handle crashes gracefully through WAL (Write-Ahead Logging)
- The key test is whether pgGit applications handle connection errors properly
- Consider monitoring system logs during crash testing
