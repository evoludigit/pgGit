# Disaster Recovery Guide

This guide covers disaster recovery procedures for pgGit installations.

## Overview

Disaster recovery ensures business continuity when pgGit deployments encounter critical failures.

## Recovery Scenarios

### 1. Database Corruption

**Symptoms:**
- PostgreSQL won't start
- Data integrity errors
- pgGit functions return errors

**Recovery Steps:**
```bash
# 1. Stop PostgreSQL
sudo systemctl stop postgresql

# 2. Restore from backup
sudo -u postgres pg_restore -d postgres /path/to/backup.dump

# 3. Verify pgGit integrity
sudo -u postgres psql -c "SELECT pggit.health_check();"

# 4. Restart PostgreSQL
sudo systemctl start postgresql
```

### 2. pgGit Schema Corruption

**Symptoms:**
- pgGit functions fail
- Objects not tracked
- History incomplete

**Recovery Steps:**
```bash
# 1. Drop corrupted schema
psql -c "DROP SCHEMA IF EXISTS pggit CASCADE;"

# 2. Recreate pgGit from backup
psql -f pggit--0.1.0.sql

# 3. Restore pgGit data only
pg_restore -d postgres -n pggit /path/to/pggit_backup.dump

# 4. Reinitialize tracking
psql -c "SELECT pggit.init();"
```

### 3. Partial Data Loss

**Symptoms:**
- Some objects missing from tracking
- Incomplete history
- Inconsistent state

**Recovery Steps:**
```sql
-- 1. Identify missing objects
SELECT schemaname, tablename
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
EXCEPT
SELECT schema_name, object_name
FROM pggit.objects;

-- 2. Manually re-add missing objects
SELECT pggit.create_object('public', 'missing_table', 'TABLE');

-- 3. Restore missing history if available
-- (From backup or log analysis)
```

### 4. Performance Degradation

**Symptoms:**
- Slow DDL operations
- High storage usage
- Monitoring alerts

**Recovery Steps:**
```sql
-- 1. Analyze performance
SELECT * FROM pggit.metrics_summary;

-- 2. Clean old data
DELETE FROM pggit.performance_metrics
WHERE recorded_at < NOW() - INTERVAL '7 days';

-- 3. Reindex if needed
REINDEX SCHEMA pggit;

-- 4. Vacuum tables
VACUUM ANALYZE pggit.objects, pggit.history;
```

## Business Continuity Planning

### Recovery Time Objectives (RTO)

- **Critical**: < 1 hour - Core database operations
- **Important**: < 4 hours - pgGit functionality
- **Normal**: < 24 hours - Full history recovery

### Recovery Point Objectives (RPO)

- **Critical**: < 15 minutes data loss
- **Important**: < 1 hour data loss
- **Normal**: < 4 hours data loss

## High Availability Setup

### Multi-Instance Deployment

```sql
-- Primary instance
SELECT pggit.init();

-- Replica instance (read-only)
-- pgGit automatically syncs via logical replication
-- Monitoring available on replicas
SELECT pggit.health_check();
```

### Load Balancing

- Route DDL operations to primary
- Use replicas for reporting and analysis
- Monitor replication lag

## Backup Strategy

### Automated Backups

```bash
# Daily full backup
pg_dump -Fc mydatabase > daily_$(date +%Y%m%d).dump

# Hourly pgGit schema backup
pg_dump -Fc -n pggit mydatabase > pggit_hourly_$(date +%Y%m%d_%H).dump

# Continuous WAL archiving
# Configure postgresql.conf:
# wal_level = replica
# archive_mode = on
# archive_command = 'cp %p /var/lib/postgresql/archive/%f'
```

### Backup Verification

```bash
# Test restore procedure monthly
#!/bin/bash
TEST_DB="disaster_test_$(date +%s)"
createdb $TEST_DB
pg_restore -d $TEST_DB latest_backup.dump
psql -d $TEST_DB -c "SELECT pggit.health_check();"
dropdb $TEST_DB
echo "✅ Backup restore successful"
```

## Incident Response

### Emergency Contacts

- **Database Admin**: [contact]
- **Application Owner**: [contact]
- **pgGit Developer**: [contact]

### Escalation Procedure

1. **Triage** (< 15 min): Assess impact and urgency
2. **Containment** (< 30 min): Stop damage propagation
3. **Recovery** (< RTO): Restore service
4. **Analysis** (< 24h): Root cause analysis
5. **Prevention**: Implement fixes and tests

## Testing

### Disaster Recovery Drills

**Quarterly Testing:**
- [ ] Full database restore
- [ ] pgGit schema recovery
- [ ] Point-in-time recovery
- [ ] Performance after recovery

**Documentation:**
- [ ] Runbook accuracy
- [ ] Contact information current
- [ ] Recovery procedures tested

### Failure Injection Testing

```bash
# Simulate disk failure
sudo systemctl stop postgresql
sudo rm /var/lib/postgresql/data/pg_wal/*.log  # CAUTION: Test only!
sudo systemctl start postgresql

# Test recovery
# Verify pgGit functionality restored
```

## Compliance

### Regulatory Requirements

- **Data Retention**: Maintain backups per compliance requirements
- **Audit Logging**: pgGit history provides DDL audit trail
- **Recovery Testing**: Documented quarterly DR tests

### Reporting

- **Monthly**: Backup success/failure reports
- **Quarterly**: DR test results and improvements
- **Annually**: DR plan review and updates

---

*Preparedness prevents disasters. Test regularly and update procedures.*