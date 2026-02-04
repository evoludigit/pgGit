# Disk Space Exhaustion Testing

## Objective

Verify that pgGit handles disk space exhaustion gracefully during backup and retention operations.

## Prerequisites

- PostgreSQL 13+ with pgGit installed
- Docker (recommended for controlled environment)
- Ability to mount volumes with limited space
- Monitoring tools (`df`, `du`)

## Setup

### Option 1: Docker with Limited Volume

1. Create a limited-size volume:
```bash
# Create a 1GB loopback device
dd if=/dev/zero of=/tmp/pgdata.img bs=1M count=1024
mkfs.ext4 /tmp/pgdata.img
mkdir -p /tmp/pgdata
sudo mount /tmp/pgdata.img /tmp/pgdata

# Verify size
df -h /tmp/pgdata
# Should show ~1GB
```

2. Start PostgreSQL with limited volume:
```bash
docker run -d \
  --name postgres-diskspace-test \
  -v /tmp/pgdata:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD=postgres \
  postgres:17-alpine
```

3. Install pgGit:
```bash
docker exec postgres-diskspace-test psql -U postgres -c "CREATE DATABASE pggit_diskspace_test;"
docker exec postgres-diskspace-test psql -U postgres -d pggit_diskspace_test -f /path/to/sql/install.sql
```

### Option 2: Docker with Size Limit

```bash
docker run -d \
  --name postgres-diskspace-test \
  --storage-opt size=1G \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=pggit_diskspace_test \
  postgres:17-alpine
```

## Test Procedure

### Test 1: Disk Full During Backup

1. Connect to database:
```bash
docker exec -it postgres-diskspace-test psql -U postgres -d pggit_diskspace_test
```

2. Fill the disk with data:
```sql
-- Create and populate a large table to consume space
CREATE TABLE large_data (
  id SERIAL PRIMARY KEY,
  data TEXT
);

-- Fill table until disk is full
INSERT INTO large_data (data)
SELECT repeat('x', 1024) FROM generate_series(1, 100000);
```

3. Monitor disk usage:
```bash
docker exec postgres-diskspace-test df -h /var/lib/postgresql/data
```

4. Attempt a backup operation:
```sql
-- Try to register a backup
SELECT pggit.register_backup(
  'diskfull-test',
  'full',
  'pgbackrest',
  's3://bucket/diskfull',
  'test-commit'
);
```

### Test 2: Disk Full During Retention Cleanup

1. With disk nearly full (from Test 1), run retention policy:
```sql
SELECT pggit.apply_retention_policy(
  '{"full_days": 30, "incremental_days": 7}'::JSONB
);
```

2. Expected behavior: Should fail gracefully, not corrupt data

## Expected Behavior

✅ Operations fail with clear error messages
✅ No database corruption
✅ No orphaned temporary files
✅ System recovers when space is freed
✅ Subsequent operations work normally

## Verification

1. Check database integrity:
```sql
-- Verify tables are still accessible
SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'pggit';

-- Check for incomplete operations
SELECT * FROM pggit.backups WHERE status = 'in_progress';
-- Should be empty
```

2. Free up space:
```bash
# Remove large data table
docker exec postgres-diskspace-test psql -U postgres -d pggit_diskspace_test -c "DROP TABLE large_data;"
```

3. Retry operations:
```sql
-- Should now succeed
SELECT pggit.register_backup(
  'recovery-test',
  'full',
  'pgbackrest',
  's3://bucket/recovery',
  'test-commit'
);
```

### Test 3: Disk Full During Write

Monitor during actual operation:
```bash
# Terminal 1: Start filling disk
docker exec postgres-diskspace-test bash -c 'dd if=/dev/zero of=/var/lib/postgresql/data/fillfile bs=1M'

# Terminal 2: Try to insert data
docker exec -it postgres-diskspace-test psql -U postgres -d pggit_diskspace_test
```

```sql
-- This will fail when disk is full
INSERT INTO pggit.backups (
  backup_name, backup_type, backup_tool, location
) VALUES ('overflow', 'full', 'pgbackrest', 's3://bucket/overflow');
```

## Expected Error Messages

```
ERROR: No space left on device
ERROR: could not extend relation
ERROR: insufficient disk space
```

## Success Criteria

- ✅ Errors are caught and reported
- ✅ No database corruption
- ✅ Transactions are properly rolled back
- ✅ System recovers when space is freed
- ✅ No cascading failures

## Cleanup

Docker:
```bash
docker stop postgres-diskspace-test
docker rm postgres-diskspace-test
```

Loopback device:
```bash
sudo umount /tmp/pgdata
rm /tmp/pgdata.img
```

## Notes

- **WARNING:** This test may cause PostgreSQL to fail. Only run on test systems.
- Disk exhaustion is a real-world scenario that should be handled gracefully
- In production, implement monitoring and alerting for disk usage
- pgBackRest (the backup tool) should also handle disk full scenarios
- Consider implementing cleanup routines that free space when needed
