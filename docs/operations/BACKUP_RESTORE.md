# Backup and Restore Guide

## Overview

pgGit stores all version history in the `pggit` schema. Proper backup ensures you can recover full version history.

## Backup Strategies

### 1. Full Database Backup (Recommended)

Include pgGit schema in regular database backups:

```bash
# Backup entire database
pg_dump -Fc mydatabase > backup_$(date +%Y%m%d).dump

# Restore
pg_restore -d mydatabase backup_20240115.dump
```

### 2. pgGit Schema Only

Backup just version control data:

```bash
# Backup pgGit schema
pg_dump -Fc -n pggit mydatabase > pggit_backup_$(date +%Y%m%d).dump

# Restore
pg_restore -d mydatabase -n pggit pggit_backup_20240115.dump
```

### 3. Selective Export

Export specific branches or time ranges:

```sql
-- Export changes from last 30 days
\copy (SELECT * FROM pggit.history WHERE created_at > NOW() - INTERVAL '30 days') TO 'history_30days.csv' CSV HEADER;

-- Export specific branch
\copy (SELECT * FROM pggit.commits WHERE branch_id = (SELECT id FROM pggit.branches WHERE name = 'main')) TO 'main_branch.csv' CSV HEADER;
```

## Restore Procedures

### Full Restore

```bash
# 1. Drop existing schema
psql -d mydatabase -c "DROP SCHEMA IF EXISTS pggit CASCADE"

# 2. Restore from backup
pg_restore -d mydatabase backup.dump

# 3. Verify
psql -d mydatabase -c "SELECT COUNT(*) FROM pggit.objects"
```

### Point-in-Time Recovery

```sql
-- Restore to specific timestamp
BEGIN;

-- Create restore point
SELECT pggit.create_restore_point('before_disaster', NOW() - INTERVAL '1 hour');

-- Restore objects to that point
SELECT pggit.restore_to_point('before_disaster');

COMMIT;
```

## Backup Verification

```sql
-- Verify backup completeness
SELECT
    'objects' as table_name,
    COUNT(*) as row_count,
    pg_size_pretty(pg_total_relation_size('pggit.objects')) as size
FROM pggit.objects
UNION ALL
SELECT 'history', COUNT(*), pg_size_pretty(pg_total_relation_size('pggit.history'))
FROM pggit.history
UNION ALL
SELECT 'commits', COUNT(*), pg_size_pretty(pg_total_relation_size('pggit.commits'))
FROM pggit.commits;
```

## Automated Backups

```bash
#!/bin/bash
# File: scripts/backup-pggit.sh

DB_NAME=${1:-postgres}
BACKUP_DIR=/var/backups/pggit
RETENTION_DAYS=30

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/pggit_${DB_NAME}_${TIMESTAMP}.dump"

# Perform backup
pg_dump -Fc -n pggit $DB_NAME > $BACKUP_FILE

# Verify backup
if pg_restore -l $BACKUP_FILE > /dev/null 2>&1; then
    echo "✅ Backup successful: $BACKUP_FILE"

    # Compress
    gzip $BACKUP_FILE

    # Remove old backups
    find $BACKUP_DIR -name "pggit_*.dump.gz" -mtime +$RETENTION_DAYS -delete
else
    echo "❌ Backup verification failed"
    exit 1
fi
```

**Cron job**:
```cron
# Daily backup at 2 AM
0 2 * * * /path/to/scripts/backup-pggit.sh production >> /var/log/pggit-backup.log 2>&1
```

## Disaster Recovery Testing

```bash
# Test restore procedure quarterly
./scripts/test-restore.sh

# 1. Create test database
# 2. Restore latest backup
# 3. Verify data integrity
# 4. Test key operations
# 5. Report results
```