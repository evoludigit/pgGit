# pgGit Backup Automation Guide

## Overview

pgGit's backup automation system provides enterprise-grade backup orchestration with:

- **Git-Native Integration**: Backups linked to commits, not branches
- **Multi-Tool Support**: pgBackRest, Barman, pg_dump, pg_basebackup
- **Job Queue**: Persistent queue with retry logic and exponential backoff
- **Async Execution**: Python service for executing backup commands
- **Monitoring**: Real-time job queue visibility

## Architecture

```
┌─────────────────┐
│  SQL Functions  │  ← Schedule backups via SQL
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Job Queue     │  ← Persistent queue in database
│  (backup_jobs)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Backup Listener │  ← Python service polling queue
│   (asyncio)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Backup Tools    │  ← pgBackRest / Barman / pg_dump
└─────────────────┘
```

**Key Concepts:**
- **Backup**: Metadata record linked to a commit hash
- **Job**: Executable task to perform the backup
- **Worker**: Instance of the backup listener service
- **Retry**: Automatic rescheduling with exponential backoff

## Prerequisites

### Required

1. **PostgreSQL 12+** with pgGit extension installed
2. **Python 3.10+** with `asyncpg` library
3. **One or more backup tools:**
   - [pgBackRest](https://pgbackrest.org/) (recommended for production)
   - [Barman](https://www.pgbarman.org/)
   - `pg_dump` (included with PostgreSQL)
   - `pg_basebackup` (included with PostgreSQL)

### Installation

Install Python dependencies:

```bash
# Using pip
pip install asyncpg

# Using uv (recommended)
uv pip install asyncpg
```

Install backup tools:

```bash
# pgBackRest (Ubuntu/Debian)
sudo apt-get install pgbackrest

# pgBackRest (RHEL/CentOS)
sudo yum install pgbackrest

# Barman
sudo apt-get install barman

# pg_dump and pg_basebackup are included with PostgreSQL
```

## Setup

### 1. Install Backup Automation Module

The backup automation module is included in `sql/install.sql`:

```bash
psql -d your_database -f sql/install.sql
```

Or install manually:

```bash
psql -d your_database -f sql/070_backup_integration.sql
psql -d your_database -f sql/071_backup_automation.sql
```

### 2. Verify Installation

```sql
-- Check that backup functions exist
SELECT proname
FROM pg_proc
WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname='pggit')
  AND proname LIKE 'backup_%'
ORDER BY proname;

-- Expected output:
-- backup_barman
-- backup_pg_dump
-- backup_pgbackrest
```

### 3. Configure Backup Tools

Configure your chosen backup tool according to its documentation:

**pgBackRest Example:**

```ini
# /etc/pgbackrest/pgbackrest.conf
[main]
pg1-path=/var/lib/postgresql/17/main
pg1-port=5432

[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
start-fast=y
```

**Barman Example:**

```ini
# /etc/barman.d/prod.conf
[prod]
description = "Production Database"
conninfo = host=localhost user=postgres dbname=mydb
backup_method = postgres
backup_options = concurrent_backup
```

## Running the Backup Listener

### Basic Usage

```bash
pggit-backup-listener postgresql://user:pass@host:port/dbname
```

### Systemd Service (Recommended)

Create `/etc/systemd/system/pggit-backup-listener.service`:

```ini
[Unit]
Description=pgGit Backup Listener Service
After=postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=postgres
Group=postgres
Environment="PGGIT_POLL_INTERVAL=10"
Environment="PGGIT_WORKER_ID=worker-01"
Environment="PGGIT_LOG_LEVEL=INFO"
ExecStart=/usr/local/bin/pggit-backup-listener postgresql://postgres@localhost:5432/mydb
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable pggit-backup-listener
sudo systemctl start pggit-backup-listener

# Check status
sudo systemctl status pggit-backup-listener

# View logs
sudo journalctl -u pggit-backup-listener -f
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PGGIT_POLL_INTERVAL` | `10` | Seconds between queue polls |
| `PGGIT_WORKER_ID` | hostname | Unique worker identifier |
| `PGGIT_LOG_LEVEL` | `INFO` | Log level (DEBUG, INFO, WARNING, ERROR) |

### Multiple Workers

Run multiple workers for high availability:

```bash
# Worker 1
PGGIT_WORKER_ID=worker-01 pggit-backup-listener postgresql://...

# Worker 2
PGGIT_WORKER_ID=worker-02 pggit-backup-listener postgresql://...
```

Workers use `FOR UPDATE SKIP LOCKED` to prevent job conflicts.

## Scheduling Backups

### pgBackRest Backups

```sql
-- Full backup of main branch
SELECT pggit.backup_pgbackrest(
    'full',                    -- backup_type: 'full', 'incr', 'diff'
    'main',                    -- branch_name
    'main',                    -- stanza name
    '{"repo": "1"}'::jsonb     -- optional parameters
);

-- Incremental backup
SELECT pggit.backup_pgbackrest('incr', 'main', 'main');

-- Differential backup
SELECT pggit.backup_pgbackrest('diff', 'main', 'main');
```

### Barman Backups

```sql
-- Backup with Barman
SELECT pggit.backup_barman(
    'prod-server',                   -- server name from Barman config
    'main',                          -- branch_name
    '{"wait": true}'::jsonb          -- optional parameters
);
```

### pg_dump Backups

```sql
-- Dump specific schema
SELECT pggit.backup_pg_dump(
    'main',                  -- branch_name
    'public',                -- schema to dump (NULL for all)
    'custom',                -- format: 'custom', 'tar', 'plain'
    '/backups',              -- output directory
    '{"compression_level": "9"}'::jsonb  -- optional parameters
);

-- Dump entire database
SELECT pggit.backup_pg_dump('main', NULL, 'custom', '/backups');
```

### Cron Scheduling

```bash
# /etc/cron.d/pggit-backups

# Full backup daily at 2 AM
0 2 * * * postgres psql -d mydb -c "SELECT pggit.backup_pgbackrest('full', 'main')" >> /var/log/pggit-backup.log 2>&1

# Incremental backup every 6 hours
0 */6 * * * postgres psql -d mydb -c "SELECT pggit.backup_pgbackrest('incr', 'main')" >> /var/log/pggit-backup.log 2>&1

# Weekly pg_dump export
0 3 * * 0 postgres psql -d mydb -c "SELECT pggit.backup_pg_dump('main', NULL, 'custom', '/backups/weekly')" >> /var/log/pggit-backup.log 2>&1
```

## Monitoring

### Job Queue View

```sql
-- View all jobs in queue
SELECT
    job_id,
    backup_name,
    tool,
    status,
    job_state,
    attempts,
    created_at,
    started_at,
    last_error
FROM pggit.backup_job_queue
ORDER BY created_at DESC;
```

**Job States:**
- `ready`: Queued and ready to execute
- `in_progress`: Currently running
- `will_retry`: Failed but will retry
- `permanently_failed`: Failed after max retries
- `completed`: Successfully completed

### Backup History

```sql
-- List all backups
SELECT * FROM pggit.list_backups(
    p_limit := 20,
    p_offset := 0
);

-- Get backup details
SELECT * FROM pggit.get_backup_info('backup_id_here');

-- Backups by branch
SELECT
    b.name as branch,
    COUNT(*) as backup_count,
    MAX(bk.created_at) as latest_backup
FROM pggit.backups bk
JOIN pggit.commits c ON bk.commit_hash = c.hash
JOIN pggit.branches b ON c.branch_id = b.id
GROUP BY b.name;
```

### Queue Statistics

```sql
-- Current queue state
SELECT
    COUNT(*) FILTER (WHERE status = 'queued') as queued,
    COUNT(*) FILTER (WHERE status = 'running') as running,
    COUNT(*) FILTER (WHERE status = 'completed') as completed,
    COUNT(*) FILTER (WHERE status = 'failed' AND attempts < max_attempts) as retrying,
    COUNT(*) FILTER (WHERE status = 'failed' AND attempts >= max_attempts) as permanently_failed
FROM pggit.backup_jobs
WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '24 hours';

-- Failed jobs
SELECT
    job_id,
    backup_id,
    tool,
    attempts,
    max_attempts,
    last_error,
    created_at
FROM pggit.backup_jobs
WHERE status = 'failed'
  AND attempts >= max_attempts
ORDER BY created_at DESC;
```

## Troubleshooting

### Common Issues

#### 1. Jobs Not Being Processed

**Symptoms:** Jobs remain in `queued` status

**Check:**
```bash
# Is the listener running?
sudo systemctl status pggit-backup-listener

# Check listener logs
sudo journalctl -u pggit-backup-listener -n 50
```

**Solutions:**
- Start the listener service
- Check database connectivity
- Verify environment variables

#### 2. Jobs Failing Repeatedly

**Symptoms:** Jobs stuck in `failed` with retry attempts

**Check:**
```sql
-- View error messages
SELECT job_id, tool, attempts, last_error
FROM pggit.backup_jobs
WHERE status = 'failed'
ORDER BY created_at DESC
LIMIT 5;
```

**Common Causes:**
- Backup tool not installed: `sudo apt-get install pgbackrest`
- Incorrect configuration: Check `/etc/pgbackrest/pgbackrest.conf`
- Insufficient permissions: Ensure listener runs as correct user
- Network issues: Verify connectivity to backup storage

#### 3. Exponential Backoff Not Working

**Symptoms:** Jobs retry immediately instead of waiting

**Check:**
```sql
-- Verify retry schedule
SELECT
    job_id,
    attempts,
    next_retry_at,
    EXTRACT(EPOCH FROM (next_retry_at - CURRENT_TIMESTAMP)) as seconds_until_retry
FROM pggit.backup_jobs
WHERE status = 'failed'
  AND attempts < max_attempts;
```

**Formula:** `delay = base_delay * 2^(attempts-1)`

#### 4. Duplicate Jobs

**Symptoms:** Multiple jobs created for same backup

**Prevention:**
- Use `FOR UPDATE SKIP LOCKED` (automatically handled)
- Don't run multiple workers with same `WORKER_ID`
- Check for duplicate cron entries

### Debug Mode

Enable debug logging:

```bash
PGGIT_LOG_LEVEL=DEBUG pggit-backup-listener postgresql://...
```

### Manual Job Management

```sql
-- Cancel a stuck job
UPDATE pggit.backup_jobs
SET status = 'cancelled'
WHERE job_id = 'job_id_here';

-- Reset a failed job to retry immediately
UPDATE pggit.backup_jobs
SET status = 'queued',
    next_retry_at = NULL,
    attempts = 0
WHERE job_id = 'job_id_here';

-- Clear old completed jobs (cleanup)
DELETE FROM pggit.backup_jobs
WHERE status = 'completed'
  AND completed_at < CURRENT_TIMESTAMP - INTERVAL '7 days';
```

## API Reference

### Core Functions

#### `backup_pgbackrest()`

Schedule pgBackRest backup.

```sql
pggit.backup_pgbackrest(
    p_backup_type TEXT DEFAULT 'full',     -- 'full', 'incr', 'diff'
    p_branch_name TEXT DEFAULT 'main',     -- branch to backup
    p_stanza TEXT DEFAULT 'main',          -- pgBackRest stanza
    p_options JSONB DEFAULT '{}'           -- additional options
) RETURNS UUID  -- backup_id
```

**Example:**
```sql
SELECT pggit.backup_pgbackrest(
    'full',
    'main',
    'prod-stanza',
    '{"repo": "1", "type": "full"}'::jsonb
);
```

#### `backup_barman()`

Schedule Barman backup.

```sql
pggit.backup_barman(
    p_server_name TEXT,                    -- Barman server name
    p_branch_name TEXT DEFAULT 'main',     -- branch to backup
    p_options JSONB DEFAULT '{}'           -- additional options
) RETURNS UUID  -- backup_id
```

**Example:**
```sql
SELECT pggit.backup_barman(
    'prod-db',
    'main',
    '{"wait": true, "reuse-backup": "incremental"}'::jsonb
);
```

#### `backup_pg_dump()`

Schedule pg_dump backup.

```sql
pggit.backup_pg_dump(
    p_branch_name TEXT DEFAULT 'main',     -- branch to backup
    p_schema TEXT DEFAULT NULL,            -- schema to dump (NULL = all)
    p_format TEXT DEFAULT 'custom',        -- 'custom', 'tar', 'plain'
    p_output_path TEXT DEFAULT '/backups', -- output directory
    p_options JSONB DEFAULT '{}'           -- additional options
) RETURNS UUID  -- backup_id
```

**Example:**
```sql
SELECT pggit.backup_pg_dump(
    'main',
    'public',
    'custom',
    '/backups/daily',
    '{"compression_level": "9", "jobs": "4"}'::jsonb
);
```

### Queue Management

#### `enqueue_backup_job()`

Manually enqueue a custom backup job.

```sql
pggit.enqueue_backup_job(
    p_backup_id UUID,                      -- backup ID
    p_command TEXT,                        -- shell command to execute
    p_tool TEXT,                           -- tool name
    p_max_attempts INTEGER DEFAULT 3,     -- max retry attempts
    p_metadata JSONB DEFAULT '{}'         -- job metadata
) RETURNS UUID  -- job_id
```

#### `get_next_backup_job()`

Get next job to process (used by listener).

```sql
pggit.get_next_backup_job(
    p_worker_id TEXT DEFAULT 'default-worker'
) RETURNS TABLE (
    job_id UUID,
    backup_id UUID,
    command TEXT,
    tool TEXT,
    attempts INTEGER,
    metadata JSONB
)
```

#### `complete_backup_job()`

Mark job as completed.

```sql
pggit.complete_backup_job(
    p_job_id UUID,
    p_output TEXT
) RETURNS BOOLEAN
```

#### `fail_backup_job()`

Mark job as failed with retry logic.

```sql
pggit.fail_backup_job(
    p_job_id UUID,
    p_error TEXT,
    p_retry_delay_seconds INTEGER DEFAULT 300  -- 5 minutes
) RETURNS BOOLEAN
```

### Backup Metadata

#### `register_backup()`

Register a new backup.

```sql
pggit.register_backup(
    p_backup_name TEXT,
    p_backup_type TEXT,                    -- 'full', 'incremental', 'differential', 'snapshot'
    p_backup_tool TEXT,                    -- 'pgbackrest', 'barman', 'pg_dump', etc.
    p_location TEXT,                       -- backup location
    p_commit_hash TEXT DEFAULT NULL,       -- commit to link to
    p_branch_name TEXT DEFAULT NULL,       -- or branch name
    p_create_snapshot BOOLEAN DEFAULT FALSE, -- create temporal snapshot
    p_metadata JSONB DEFAULT '{}'
) RETURNS UUID  -- backup_id
```

#### `complete_backup()`

Mark backup as completed.

```sql
pggit.complete_backup(
    p_backup_id UUID,
    p_backup_size BIGINT DEFAULT NULL,
    p_compressed_size BIGINT DEFAULT NULL,
    p_compression_type TEXT DEFAULT NULL
) RETURNS BOOLEAN
```

#### `fail_backup()`

Mark backup as failed.

```sql
pggit.fail_backup(
    p_backup_id UUID,
    p_error_message TEXT
) RETURNS BOOLEAN
```

## Advanced Usage

### Custom Backup Commands

Execute custom backup workflows:

```sql
-- Register custom backup
SELECT pggit.register_backup(
    'custom-backup-001',
    'full',
    'custom',
    's3://bucket/custom-001',
    (SELECT head_commit_hash FROM pggit.branches WHERE name = 'main')
) AS backup_id \gset

-- Enqueue custom command
SELECT pggit.enqueue_backup_job(
    :'backup_id'::UUID,
    'my-custom-backup-script.sh --output /backups',
    'custom',
    5,  -- 5 retry attempts
    '{"script": "custom", "notify": "admin@example.com"}'::jsonb
);
```

### Webhook Notifications

Add notifications on backup completion:

```sql
-- In backup metadata
SELECT pggit.backup_pgbackrest(
    'full',
    'main',
    'main',
    jsonb_build_object(
        'webhook_url', 'https://hooks.slack.com/...',
        'notify_on_success', true,
        'notify_on_failure', true
    )
);
```

### Backup Retention

Implement automatic cleanup:

```sql
-- Delete old backups (keep last 30 days)
DELETE FROM pggit.backups
WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '30 days'
  AND status = 'completed';

-- Keep minimum number of backups per branch
WITH ranked_backups AS (
    SELECT
        backup_id,
        ROW_NUMBER() OVER (
            PARTITION BY commit_hash
            ORDER BY created_at DESC
        ) as rn
    FROM pggit.backups
)
DELETE FROM pggit.backups
WHERE backup_id IN (
    SELECT backup_id FROM ranked_backups WHERE rn > 5
);
```

## Performance Tuning

### Concurrent Workers

Run multiple workers for throughput:

```bash
# Worker 1: High-priority backups
PGGIT_POLL_INTERVAL=5 PGGIT_WORKER_ID=worker-high \
    pggit-backup-listener postgresql://...

# Worker 2: Regular backups
PGGIT_POLL_INTERVAL=10 PGGIT_WORKER_ID=worker-regular \
    pggit-backup-listener postgresql://...
```

### Job Prioritization

Implement priority queue by modifying `get_next_backup_job()`:

```sql
-- Add priority column to backup_jobs
ALTER TABLE pggit.backup_jobs ADD COLUMN priority INTEGER DEFAULT 5;

-- Modify ORDER BY to use priority
ORDER BY
    priority ASC,  -- Lower number = higher priority
    CASE WHEN j.status = 'queued' THEN 0 ELSE 1 END,
    j.created_at ASC
```

### Database Tuning

Optimize for backup workload:

```sql
-- Increase connection pool for workers
ALTER SYSTEM SET max_connections = 200;

-- Tune work_mem for large backups
ALTER SYSTEM SET work_mem = '256MB';

-- Enable parallel workers for pg_dump
ALTER SYSTEM SET max_parallel_workers = 8;

SELECT pg_reload_conf();
```

## Security

### Access Control

```sql
-- Create dedicated backup user
CREATE USER pggit_backup WITH PASSWORD 'secure_password';

-- Grant minimum required permissions
GRANT USAGE ON SCHEMA pggit TO pggit_backup;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA pggit TO pggit_backup;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pggit TO pggit_backup;

-- Allow access to pg_catalog for metadata
GRANT SELECT ON ALL TABLES IN SCHEMA pg_catalog TO pggit_backup;
```

### Credential Management

Use PostgreSQL service file for credentials:

```bash
# ~/.pgpass (chmod 0600)
localhost:5432:mydb:pggit_backup:secure_password
```

### Network Security

- Run listener on same host as database (avoid network hop)
- Use SSL connections: `postgresql://user@host/db?sslmode=require`
- Firewall rules to restrict backup storage access

## Migration from Manual Backups

Transition from cron-based pg_dump:

```bash
# Old approach (cron)
0 2 * * * pg_dump -Fc mydb > /backups/mydb_$(date +\%Y\%m\%d).dump

# New approach (pgGit automation)
0 2 * * * psql -d mydb -c "SELECT pggit.backup_pg_dump('main')"
```

**Benefits:**
- Backup linked to Git commit (point-in-time consistency)
- Automatic retry on failure
- Job queue visibility
- Centralized monitoring
- Metadata tracking

## Production Checklist

Before deploying to production:

- [ ] Backup tools installed and configured
- [ ] Python dependencies installed (`asyncpg`)
- [ ] Systemd service configured and enabled
- [ ] Cron jobs scheduled for automated backups
- [ ] Monitoring dashboards configured
- [ ] Backup retention policy defined
- [ ] Disaster recovery procedure documented
- [ ] Test restore performed successfully
- [ ] Alert thresholds configured
- [ ] Log rotation configured (`/var/log/pggit-backup.log`)

## Support

**Documentation:**
- [pgGit GitHub](https://github.com/yourusername/pggit)
- [Backup Integration Design](/docs/implementation-plans/backup-integration.md)

**Backup Tool Documentation:**
- [pgBackRest](https://pgbackrest.org/user-guide.html)
- [Barman](https://docs.pgbarman.org/)
- [pg_dump](https://www.postgresql.org/docs/current/app-pgdump.html)

**Issues:**
- GitHub Issues: https://github.com/yourusername/pggit/issues
