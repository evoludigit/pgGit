# Operational Runbook

## Overview

This runbook provides operational procedures for pgGit maintenance, troubleshooting, and incident response.

## Daily Operations

### Health Checks

```bash
#!/bin/bash
# Daily health check script

echo "=== pgGit Daily Health Check ==="

# Database connectivity
psql -h localhost -U postgres -d pggit_prod -c "SELECT 1;" >/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Database connectivity: OK"
else
    echo "❌ Database connectivity: FAILED"
    exit 1
fi

# pgGit health
HEALTH=$(psql -h localhost -U postgres -d pggit_prod -c "SELECT * FROM pggit.health_check();" -t -A)
if echo "$HEALTH" | grep -q "healthy"; then
    echo "✅ pgGit health: OK"
else
    echo "❌ pgGit health: FAILED"
    echo "Details: $HEALTH"
fi

# Storage usage
STORAGE=$(psql -h localhost -U postgres -d pggit_prod -c "SELECT pg_size_pretty(pg_total_relation_size('pggit.history'));" -t -A)
echo "📊 Storage usage: $STORAGE"

# Recent activity
RECENT=$(psql -h localhost -U postgres -d pggit_prod -c "SELECT COUNT(*) FROM pggit.history WHERE created_at > NOW() - INTERVAL '24 hours';" -t -A)
echo "📈 Changes in last 24h: $RECENT"

echo "=== Health check complete ==="
```

### Backup Verification

```bash
#!/bin/bash
# Backup verification script

BACKUP_DIR="/var/backups/pggit"
LATEST_BACKUP=$(ls -t $BACKUP_DIR/*.sql.gz | head -1)

echo "Verifying backup: $LATEST_BACKUP"

# Restore to test database
createdb pggit_test_restore
gunzip < $LATEST_BACKUP | psql -d pggit_test_restore

# Verify restore
TABLES=$(psql -d pggit_test_restore -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'pggit';" -t -A)
if [ "$TABLES" -gt 0 ]; then
    echo "✅ Backup verification: PASSED"
else
    echo "❌ Backup verification: FAILED"
fi

# Cleanup
dropdb pggit_test_restore
```

## Incident Response

### Severity Levels

- **P1 - Critical**: pgGit completely unavailable, affecting all users
- **P2 - High**: Significant functionality impaired, partial service
- **P3 - Medium**: Minor issues, workarounds available
- **P4 - Low**: Cosmetic issues, no functional impact

### P1 Response Process

1. **Acknowledge** (5 minutes)
   - Page on-call engineer
   - Create incident ticket
   - Notify stakeholders

2. **Assess** (15 minutes)
   - Check system status
   - Identify affected components
   - Determine scope and impact

3. **Mitigate** (30-60 minutes)
   - Implement immediate workaround
   - Roll back recent changes if needed
   - Scale resources if applicable

4. **Resolve** (2-4 hours)
   - Identify root cause
   - Implement permanent fix
   - Test fix thoroughly

5. **Review** (Next business day)
   - Conduct post-mortem
   - Update documentation
   - Implement preventive measures

### Common P1 Scenarios

#### Database Connection Failure

**Symptoms:**
- All pgGit operations fail
- Error: "could not connect to server"

**Immediate Actions:**
```bash
# Check PostgreSQL service
sudo systemctl status postgresql

# Restart if needed
sudo systemctl restart postgresql

# Check logs
sudo tail -f /var/log/postgresql/postgresql-*.log
```

**Root Cause Analysis:**
- Network connectivity issues
- PostgreSQL configuration changes
- Resource exhaustion (disk space, memory)

#### Event Trigger Disabled

**Symptoms:**
- DDL changes not tracked
- `pggit.health_check()` shows trigger issues

**Immediate Actions:**
```sql
-- Check trigger status
SELECT evtname, evtenabled FROM pg_event_trigger WHERE evtname LIKE 'pggit%';

-- Re-enable triggers
ALTER EVENT TRIGGER pggit_ddl_trigger ENABLE;
```

### P2 Response Process

Similar to P1 but with 30-minute acknowledgment and 4-hour resolution targets.

### Monitoring Alerts

#### Alert: High DDL Latency

```bash
# Investigate slow queries
psql -c "SELECT * FROM pggit.analyze_slow_queries(100);"

# Check system resources
top -p $(pgrep postgres | tr '\n' ',' | sed 's/,$//')

# Check locks
psql -c "SELECT * FROM pg_locks WHERE NOT granted;"
```

#### Alert: Storage Usage High

```bash
# Check table sizes
psql -c "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size FROM pg_tables WHERE schemaname = 'pggit' ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 10;"

# Archive old data
psql -c "SELECT pggit.archive_old_history(INTERVAL '1 year');"
```

## Maintenance Procedures

### Weekly Maintenance

```bash
#!/bin/bash
# Weekly maintenance script

echo "=== pgGit Weekly Maintenance ==="

# Vacuum analyze
psql -d pggit_prod -c "VACUUM ANALYZE pggit.*;"

# Update statistics
psql -d pggit_prod -c "ANALYZE pggit.objects, pggit.history;"

# Check for bloat
psql -d pggit_prod -c "SELECT * FROM pggit.vacuum_health();"

# Verify backups
./scripts/backup/verify-backup.sh

echo "=== Weekly maintenance complete ==="
```

### Monthly Maintenance

```bash
#!/bin/bash
# Monthly maintenance script

echo "=== pgGit Monthly Maintenance ==="

# Archive old history (keep 1 year)
psql -d pggit_prod -c "SELECT pggit.archive_old_history(INTERVAL '1 year');"

# Reindex if needed
psql -d pggit_prod -c "REINDEX SCHEMA pggit;"

# Update extensions
psql -d pggit_prod -c "ALTER EXTENSION pgcrypto UPDATE;"

# Performance baseline
./scripts/performance/benchmark.sh

echo "=== Monthly maintenance complete ==="
```

### Quarterly Maintenance

```bash
#!/bin/bash
# Quarterly maintenance script

echo "=== pgGit Quarterly Maintenance ==="

# SLO compliance review
./scripts/operations/slo-review.sh

# Security audit
./scripts/security/audit.sh

# Dependency updates
./scripts/maintenance/update-dependencies.sh

# Disaster recovery test
./scripts/backup/disaster-recovery-test.sh

echo "=== Quarterly maintenance complete ==="
```

## Troubleshooting Guide

### DDL Tracking Not Working

**Check 1: Event triggers enabled**
```sql
SELECT evtname, evtenabled FROM pg_event_trigger;
-- Should show pggit_ddl_trigger as enabled
```

**Check 2: Function exists**
```sql
SELECT proname FROM pg_proc WHERE proname = 'pggit_track_ddl';
-- Should return the function name
```

**Check 3: Permissions**
```sql
SELECT has_function_privilege('pggit_track_ddl()', 'execute');
-- Should return true
```

### Performance Issues

**Slow queries**
```sql
SELECT * FROM pggit.analyze_slow_queries();
EXPLAIN ANALYZE SELECT * FROM pggit.get_history('table_name');
```

**High memory usage**
```bash
# Check PostgreSQL memory
ps aux | grep postgres
free -h
```

**Lock contention**
```sql
SELECT * FROM pg_locks WHERE NOT granted;
SELECT * FROM pg_stat_activity WHERE wait_event IS NOT NULL;
```

### Data Corruption

**Symptoms:**
- Inconsistent history data
- Missing change records
- Invalid object references

**Recovery:**
```bash
# Create backup immediately
./scripts/backup/create-backup.sh emergency

# Check data integrity
psql -c "SELECT pggit.validate_data_integrity();"

# Rebuild corrupted indexes
psql -c "REINDEX SCHEMA pggit;"
```

## Escalation Matrix

| Issue Type | Initial Response | Escalation |
|------------|------------------|------------|
| Database down | On-call engineer | DBA team (15 min) |
| Data corruption | On-call engineer | Senior engineer (30 min) |
| Security incident | Security team | CISO (immediate) |
| Performance issue | DevOps engineer | SRE team (1 hour) |

## Communication Templates

### Incident Notification
```
Subject: [P1] pgGit Service Outage - Database Connectivity Issues

Impact: All DDL tracking operations are failing
Status: Investigating
ETA: 30 minutes
Affected: All pgGit users
```

### Status Update
```
Subject: [P1] pgGit Service Outage - Update #2

Status: Identified root cause - PostgreSQL service restart required
ETA: 10 minutes
Next Update: When service restored
```

### Resolution Notification
```
Subject: [P1] pgGit Service Restored

Issue: PostgreSQL service restart due to memory exhaustion
Resolution: Increased memory allocation, monitoring alerts configured
Duration: 45 minutes
Post-mortem: Will be scheduled for tomorrow
```

## Post-Mortem Template

### Incident Summary
- **Date/Time**: [timestamp]
- **Duration**: [X minutes/hours]
- **Impact**: [description]
- **Root Cause**: [analysis]

### Timeline
- [time] - Issue detected via monitoring alert
- [time] - Initial investigation started
- [time] - Root cause identified
- [time] - Fix implemented
- [time] - Service restored

### Actions Taken
- [ ] Immediate mitigation steps
- [ ] Communication with stakeholders
- [ ] Coordination with other teams

### Lessons Learned
- **What went well**: [positive aspects]
- **What could improve**: [areas for improvement]
- **Preventive measures**: [actions to prevent recurrence]

### Follow-up Actions
- [ ] Update runbook with new procedures
- [ ] Implement monitoring improvements
- [ ] Schedule training/knowledge sharing
- [ ] Update incident response playbooks