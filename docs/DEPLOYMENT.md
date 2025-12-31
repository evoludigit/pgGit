# pgGit Deployment Guide

**Complete guide for deploying pgGit to production environments**

---

## Overview

This guide covers deploying pgGit to production PostgreSQL instances. pgGit is deployed as a set of SQL schemas and functions that run within PostgreSQL.

**Key Concepts**:
- ✅ pgGit installs into PostgreSQL as `pggit_v0` and `pggit_audit` schemas
- ✅ No separate service or daemon required
- ✅ All operations are SQL functions you call from your application
- ✅ Deployment is idempotent (safe to re-run)
- ✅ Zero downtime deployment possible with careful procedure

---

## Pre-Deployment Requirements

### 1. PostgreSQL Compatibility

**Minimum Requirements**:
- PostgreSQL 12 or later
- Superuser or role with CREATE SCHEMA privilege
- At least 100MB free space for pgGit schemas

**Tested Versions**:
- ✅ PostgreSQL 12, 13, 14, 15, 16
- ✅ AWS RDS PostgreSQL (all versions above)
- ✅ Google Cloud SQL PostgreSQL
- ✅ Azure Database for PostgreSQL
- ✅ Managed PostgreSQL on DigitalOcean, Linode, etc.

### 2. System Requirements

**Development/Testing**:
- 1 CPU core minimum
- 512MB RAM minimum
- 1GB disk space for schemas

**Production**:
- 2+ CPU cores recommended
- 4GB+ RAM recommended
- 10GB+ disk space for schemas and audit logs
- Dedicated connection pool (10+ connections)

### 3. Database Configuration

Before deploying, verify PostgreSQL settings:

```bash
# Connect to target database
psql -h your-host -U postgres -d your_database

# Check required settings
SHOW shared_preload_libraries;
SHOW max_connections;
SHOW work_mem;
```

**Recommended Settings**:
```sql
-- For 100GB+ databases
SET shared_buffers = 256MB;      -- 25% of system RAM
SET effective_cache_size = 1GB;  -- 50-75% of system RAM
SET work_mem = 50MB;             -- For sorting operations
SET maintenance_work_mem = 1GB;  -- For index creation
```

### 4. Backup Before Deployment

```bash
# Create full backup before deploying pgGit
pg_dump -h your-host -U postgres your_database > backup_before_pggit.sql

# Verify backup is readable
file backup_before_pggit.sql
ls -lh backup_before_pggit.sql
```

---

## Deployment Methods

### Method 1: Direct Installation (Recommended for Most Cases)

**For**: Development, staging, or production with maintenance window

**Duration**: 5-15 minutes depending on database size

**Steps**:

```bash
# 1. Download pgGit SQL modules
git clone https://github.com/evoludigit/pgGit.git
cd pgGit

# 2. Connect to your database
export PGHOST=your-host
export PGUSER=postgres
export PGDATABASE=your_database

# 3. Run installation script
psql -f sql/install_pggit_v0.sql

# 4. Verify installation
psql -c "SELECT * FROM pggit_v0.version();"
# Expected output: pgGit v0.1.2, timestamp, status=ready
```

**Rollback** (if needed):
```bash
psql -f sql/uninstall_pggit_v0.sql
# Recreate from backup
psql your_database < backup_before_pggit.sql
```

### Method 2: Docker Deployment

**For**: Container-based infrastructure, Kubernetes, Docker Compose

**Duration**: 5-10 minutes

**Using Docker Compose**:

```yaml
version: '3.8'
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: your-secure-password
      POSTGRES_DB: your_database
    ports:
      - "5432:5432"
    volumes:
      - ./sql:/docker-entrypoint-initdb.d
      - postgres_data:/var/lib/postgresql/data
    networks:
      - pggit

  pggit-init:
    image: pggit:latest
    depends_on:
      - postgres
    environment:
      PGHOST: postgres
      PGUSER: postgres
      PGPASSWORD: your-secure-password
      PGDATABASE: your_database
    command: |
      sh -c "psql -h postgres -U postgres -d your_database -f /app/sql/install_pggit_v0.sql"
    networks:
      - pggit

volumes:
  postgres_data:

networks:
  pggit:
```

**Using Kubernetes**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: pggit-init
data:
  install.sh: |
    #!/bin/bash
    set -e
    psql -h $PGHOST -U $PGUSER -d $PGDATABASE -f /app/sql/install_pggit_v0.sql
    echo "pgGit installed successfully"

---
apiVersion: batch/v1
kind: Job
metadata:
  name: pggit-deploy
spec:
  template:
    spec:
      containers:
      - name: pggit-init
        image: pggit:latest
        env:
        - name: PGHOST
          value: "postgres.default.svc.cluster.local"
        - name: PGUSER
          valueFrom:
            secretKeyRef:
              name: postgres-creds
              key: username
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-creds
              key: password
        - name: PGDATABASE
          value: "your_database"
        volumeMounts:
        - name: pggit-init
          mountPath: /scripts
      volumes:
      - name: pggit-init
        configMap:
          name: pggit-init
      restartPolicy: Never
```

### Method 3: Infrastructure as Code (Terraform)

**For**: AWS, Google Cloud, Azure, automated infrastructure

```hcl
# Terraform example for AWS RDS
resource "aws_db_instance" "pggit" {
  identifier     = "pggit-production"
  engine         = "postgres"
  engine_version = "16.1"
  instance_class = "db.t3.medium"
  allocated_storage = 100

  # pgGit doesn't need special parameters
  parameter_group_name = "default.postgres16"
}

# Post-deployment initialization
resource "null_resource" "pggit_install" {
  provisioner "local-exec" {
    command = "psql -h ${aws_db_instance.pggit.endpoint} -U postgres -d postgres -f sql/install_pggit_v0.sql"
  }

  depends_on = [aws_db_instance.pggit]
}
```

---

## Production Deployment Checklist

### Pre-Deployment (1 day before)

- [ ] Verify PostgreSQL version is 12+ with `SELECT version();`
- [ ] Backup entire database: `pg_dump > backup.sql`
- [ ] Verify backup integrity: `file backup.sql && wc -l backup.sql`
- [ ] Review [Release Checklist](docs/operations/RELEASE_CHECKLIST.md)
- [ ] Schedule maintenance window (optional, but recommended for first deployment)
- [ ] Notify team of deployment plan
- [ ] Review [Operations Runbook](docs/operations/RUNBOOK.md)

### Deployment Phase

- [ ] Stop non-critical applications (optional)
- [ ] Disable scheduled jobs/cron tasks that use database
- [ ] Execute installation: `psql -f sql/install_pggit_v0.sql`
- [ ] Verify installation: `SELECT pggit_v0.version();`
- [ ] Check for errors: `SELECT * FROM pggit_audit.audit_log LIMIT 10;`
- [ ] Re-enable applications and scheduled jobs

### Post-Deployment (verify)

- [ ] Run monitoring checks: `SELECT pggit_v0.validate_installation();`
- [ ] Create test branch: `SELECT pggit_v0.create_branch('main', 'test-branch');`
- [ ] List branches: `SELECT * FROM pggit_v0.list_branches();`
- [ ] Review [Monitoring Guide](docs/operations/MONITORING.md)
- [ ] Set up alerts (see Operations Runbook)
- [ ] Document deployment completion with timestamp

### Post-Deployment (wait period)

- [ ] Monitor for 24-48 hours
- [ ] Check audit logs daily
- [ ] Monitor database performance (no degradation expected)
- [ ] Collect baseline metrics for [SLO](docs/operations/SLO.md) monitoring

---

## Zero-Downtime Deployment

For production instances where downtime is not acceptable:

### Strategy 1: Parallel Deployment

```
1. Deploy to staging database (exact copy of prod)
2. Run full testing
3. Once verified, deploy to production
4. Applications switch connections via connection pooling
```

### Strategy 2: Read Replica Approach

```
1. Create read replica of production database
2. Install pgGit on replica
3. Run comprehensive testing
4. Promote replica to primary (if needed)
5. Install on original primary during off-peak hours
```

### Strategy 3: Connection Pooling

```bash
# Using PgBouncer for zero-downtime
# 1. Configure connection pooling before pgGit
pgbouncer -c pgbouncer.ini -R

# 2. Install pgGit (brief pause in query execution)
psql -f sql/install_pggit_v0.sql

# 3. Connection pool automatically routes connections to available servers
```

---

## Configuration After Deployment

### 1. Enable Audit Logging

```sql
-- Enable audit trail (default: ON)
SELECT pggit_v0.enable_audit();

-- Verify audit is working
SELECT COUNT(*) FROM pggit_audit.audit_log;
```

### 2. Configure Retention Policy

```sql
-- Set audit log retention (default: 90 days)
SELECT pggit_v0.set_audit_retention_days(90);

-- Or keep indefinitely
SELECT pggit_v0.set_audit_retention_days(NULL);
```

### 3. Initialize Main Branch

```sql
-- If this is a new database, pgGit creates 'main' automatically
-- Verify main branch exists
SELECT pggit_v0.get_current_branch();
-- Expected: 'main'
```

### 4. Set Up Monitoring

```sql
-- Create monitoring view (PostgreSQL 13+)
CREATE OR REPLACE VIEW public.pggit_status AS
SELECT
  pggit_v0.get_current_branch() as current_branch,
  (SELECT COUNT(*) FROM pggit_v0.list_branches()) as total_branches,
  (SELECT COUNT(*) FROM pggit_audit.audit_log) as total_changes,
  pggit_v0.get_storage_usage() as total_storage;

-- Query monitoring view
SELECT * FROM public.pggit_status;
```

---

## Health Checks

After deployment, run these health checks:

```sql
-- 1. Verify schemas exist
SELECT COUNT(*) as schemas_found
FROM information_schema.schemata
WHERE schema_name IN ('pggit_v0', 'pggit_audit');
-- Expected: 2

-- 2. Verify functions exist
SELECT COUNT(*) as functions_found
FROM information_schema.routines
WHERE routine_schema = 'pggit_v0'
  AND routine_type = 'FUNCTION';
-- Expected: 50+ (exact number varies by version)

-- 3. Check version
SELECT pggit_v0.version();
-- Expected: pgGit v0.1.2 (or later)

-- 4. Test branch operations
SELECT pggit_v0.get_current_branch();
-- Expected: 'main'

-- 5. Check audit logging
SELECT COUNT(*) FROM pggit_audit.audit_log;
-- Expected: > 0 (shows audit log has entries)
```

---

## Troubleshooting Deployment

### Installation Fails: "Permission Denied"

```sql
-- Verify you have superuser or appropriate role
SELECT current_user;
SELECT usesuper FROM pg_user WHERE usename = current_user;

-- If not superuser, grant required privileges
ALTER USER your_user CREATEDB CREATEROLE;
```

### Installation Fails: "Schema Already Exists"

```bash
# Two options:

# Option 1: Uninstall first
psql -f sql/uninstall_pggit_v0.sql
psql -f sql/install_pggit_v0.sql

# Option 2: Clean and reinstall
psql -c "DROP SCHEMA pggit_v0, pggit_audit CASCADE;"
psql -f sql/install_pggit_v0.sql
```

### Audit Log Growing Too Large

```sql
-- Check size
SELECT pg_size_pretty(pg_total_relation_size('pggit_audit.audit_log'));

-- Archive old entries
SELECT pggit_v0.archive_audit_logs(days_to_keep := 30);

-- Or truncate (warning: permanent deletion)
TRUNCATE pggit_audit.audit_log;
```

### Performance Issues After Deployment

See [Performance Tuning Guide](docs/guides/PERFORMANCE_TUNING.md) for optimization strategies.

---

## Monitoring After Deployment

### Key Metrics to Monitor

```sql
-- 1. Audit log growth
SELECT
  COUNT(*) as total_records,
  MAX(timestamp) as latest_change,
  DATE(NOW()) - DATE(MIN(timestamp)) as days_of_history
FROM pggit_audit.audit_log;

-- 2. Storage usage
SELECT pggit_v0.analyze_storage_usage();

-- 3. Branch status
SELECT pggit_v0.list_branches();

-- 4. Recent changes
SELECT * FROM pggit_audit.audit_log
ORDER BY timestamp DESC
LIMIT 20;
```

### Alerting

Set up alerts for:
- ✅ Audit log errors
- ✅ Storage usage exceeding 80% of disk
- ✅ Schema integrity check failures
- ✅ Audit log not growing (indicates no activity or problem)

---

## Disaster Recovery

### Restore from Backup

```bash
# If deployment causes issues, restore
psql your_database < backup_before_pggit.sql

# pgGit will be removed but database restored to pre-deployment state
```

### Access pgGit After Recovery

```bash
# Re-deploy pgGit
psql -f sql/install_pggit_v0.sql

# Verify
SELECT pggit_v0.version();
```

---

## Compliance & Security

### FIPS 140-2 Compliance

For regulated environments, see [FIPS Compliance Guide](docs/compliance/FIPS_COMPLIANCE.md).

### SOC2 Compliance

For audit requirements, see [SOC2 Preparation](docs/compliance/SOC2_PREPARATION.md).

### Security Hardening

After deployment, review [Security Hardening Guide](docs/guides/Security.md) for 30+ security checklist items.

---

## Support & Monitoring

### Continued Support

- See [SUPPORT.md](SUPPORT.md) for help
- Review [Operations Runbook](docs/operations/RUNBOOK.md) for operational procedures
- Check [Monitoring Guide](docs/operations/MONITORING.md) for detailed monitoring setup

### Success Indicators

After successful deployment:
- ✅ `pggit_v0.version()` returns version info
- ✅ `pggit_v0.list_branches()` returns at least 'main' branch
- ✅ Audit log contains installation records
- ✅ No error messages in PostgreSQL logs
- ✅ Applications can call pgGit functions

---

**Last Updated**: December 31, 2025
**Version**: pgGit v0.1.2
**Maintainer**: pgGit Team
