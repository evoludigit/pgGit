# Phase 8 Deployment Rollback Runbook

**Document Version:** 1.0
**Last Updated:** 2025-12-27
**Audience:** DevOps, On-Call Engineers
**RTO:** < 5 minutes
**RPO:** < 1 minute

---

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Pre-Deployment Checklist](#pre-deployment-checklist)
3. [Rollback Decision Tree](#rollback-decision-tree)
4. [Rollback Procedures](#rollback-procedures)
5. [Post-Rollback Verification](#post-rollback-verification)
6. [Incident Communication](#incident-communication)
7. [Contacts & Escalation](#contacts--escalation)

---

## Quick Reference

### When to Rollback

**Automatic Rollback Triggers:**
- Error rate > 5% for 60 seconds
- Latency P99 > 5 seconds for 60 seconds
- Database connection pool exhaustion
- Replication lag > 30 seconds (multi-region deployments)
- Critical security vulnerability discovered

**Manual Rollback Triggers:**
- Data corruption detected
- Authentication/authorization bypass
- Deployment blocks webhook delivery completely

### Rollback Steps (90 seconds)

```bash
# 1. Stop new deployments (10 seconds)
kubectl scale deployment pggit-api --replicas=0 -n production

# 2. Restore previous version (30 seconds)
kubectl set image deployment/pggit-api \
  api=pggit-api:previous-stable-tag \
  -n production

# 3. Restore database state if needed (20 seconds)
# See "Database Rollback" section below

# 4. Wait for health checks (20 seconds)
kubectl rollout status deployment/pggit-api -n production --timeout=30s

# 5. Verify (10 seconds)
curl -s http://pggit-api.production.svc.cluster.local:8080/health
```

---

## Pre-Deployment Checklist

**Before deploying Phase 8 enhancements, verify:**

- [ ] Backup completed and tested
- [ ] Previous stable version documented (tag: `pggit-api:previous-stable-tag`)
- [ ] Monitoring alerts configured
- [ ] Incident response team available
- [ ] Slack channel #pggit-incidents created/active
- [ ] PagerDuty escalation configured
- [ ] Database replication verified (multi-region)
- [ ] All critical fixes (phase8_critical_fixes.sql) applied

### Backup Procedure

```bash
# Full database backup before deployment
pg_dump -U postgres -d pggit -Fc > /backups/pggit_pre-phase8.dump
# Upload to S3/cloud backup
aws s3 cp /backups/pggit_pre-phase8.dump s3://pggit-backups/

# Verify backup
pg_restore --list /backups/pggit_pre-phase8.dump | head -20
```

---

## Rollback Decision Tree

```
ERROR DETECTED
│
├─ Error Rate > 5%?
│  ├─ YES → ROLLBACK IMMEDIATELY (go to step 3)
│  └─ NO → Continue
│
├─ Latency P99 > 5s?
│  ├─ YES → ROLLBACK IMMEDIATELY
│  └─ NO → Continue
│
├─ Connection Pool Exhausted?
│  ├─ YES → ROLLBACK or RESTART
│  └─ NO → Continue
│
├─ Data Integrity Issue?
│  ├─ YES → ROLLBACK + RESTORE DB + INCIDENT POST-MORTEM
│  └─ NO → Continue
│
├─ Security Issue?
│  ├─ YES → ROLLBACK + SECURITY AUDIT + NOTIFY SECURITY TEAM
│  └─ NO → Continue
│
├─ Can Issue Be Fixed in Production?
│  ├─ YES → Apply hotfix + Monitor
│  └─ NO → ROLLBACK + ROOT CAUSE ANALYSIS

DECISION: ┌─────────────────────┐
          │ ROLLBACK or ROLLOUT │
          └─────────────────────┘
```

---

## Rollback Procedures

### Quick Rollback (5 minutes)

**1. Immediate Stop**

```bash
# Stop traffic to affected deployment
kubectl scale deployment pggit-api --replicas=0 -n production

# Notify team
echo "⚠️  ROLLBACK INITIATED: Phase 8 deployment" | slack-notify #pggit-incidents
```

**2. Database Rollback (if needed)**

```bash
# Check if database changes were applied
SELECT version FROM pggit.schema_versions WHERE name = 'phase8_analytics_dashboard';

# If needed, restore from backup
pg_restore -U postgres -d pggit --clean --if-exists /backups/pggit_pre-phase8.dump

# Verify data integrity
SELECT COUNT(*) FROM pggit.alert_delivery_queue;
SELECT COUNT(*) FROM pggit.webhook_health_metrics;
```

**3. Application Rollback**

```bash
# Restore previous Docker image
kubectl set image deployment/pggit-api \
  api=gcr.io/pggit/pggit-api:v1.0.3 \
  -n production

# Watch rollout
kubectl rollout status deployment/pggit-api -n production
```

**4. Restore Traffic**

```bash
# Scale back up gradually
kubectl scale deployment pggit-api --replicas=2 -n production
sleep 30
kubectl scale deployment pggit-api --replicas=4 -n production

# Monitor metrics
watch 'kubectl top nodes; kubectl top pods -n production'
```

### Full Rollback with Database Recovery

**Use this if data corruption or major issues detected:**

```bash
# STEP 1: Take database offline
kubectl set env deployment/pggit-api DB_READONLY=true -n production

# STEP 2: Backup current state for forensics
pg_dump -U postgres -d pggit -Fc > /backups/pggit_post-rollback.dump
aws s3 cp /backups/pggit_post-rollback.dump s3://pggit-backups/rollback-forensics/

# STEP 3: Stop the deployment
kubectl delete deployment pggit-api -n production

# STEP 4: Restore database from pre-deployment backup
# WARNING: This will lose all data since deployment
psql -U postgres -d pggit < /backups/pggit_pre-phase8.sql

# STEP 5: Verify database integrity
psql -U postgres -d pggit -c "SELECT COUNT(*) FROM pggit.alert_delivery_queue;"
psql -U postgres -d pggit -c "SELECT version FROM pggit.schema_versions;"

# STEP 6: Restore replicas (multi-region)
# See "Multi-Region Rollback" section below

# STEP 7: Deploy stable version
kubectl create -f deployment.yaml

# STEP 8: Verify and restore traffic
curl -s http://pggit-api:8080/health
```

### Multi-Region Rollback

**For deployments with replication across regions:**

```bash
# STEP 1: Check replication status
psql -U postgres -c "SELECT * FROM pggit.measure_replication_lag();"

# STEP 2: Stop replication on secondary regions
psql -U postgres -c "ALTER SUBSCRIPTION sub_from_primary DISABLE;"

# STEP 3: Rollback primary region first
# (Follow "Quick Rollback" steps above)

# STEP 4: Once primary stable, re-sync replicas
psql -U postgres -c "ALTER SUBSCRIPTION sub_from_primary ENABLE;"

# STEP 5: Monitor replication lag
watch 'psql -U postgres -c "SELECT * FROM pggit.measure_replication_lag();"'

# STEP 6: Once lag < 1 second, restore traffic to secondary regions
```

### Connection Pool Recovery

**If deployment causes connection pool exhaustion:**

```bash
# STEP 1: Identify pool exhaustion
SELECT count(*) FROM pg_stat_activity
WHERE state = 'active' AND datname = 'pggit';

# STEP 2: Kill long-running connections (if safe)
SELECT pg_terminate_backend(pid) FROM pg_stat_activity
WHERE state = 'idle in transaction' AND query_start < now() - interval '5 minutes';

# STEP 3: Force restart of connection pool
# In application code:
await app.state.db_pool.close()
app.state.db_pool = await asyncpg.create_pool(...)

# STEP 4: Gradually restore traffic
kubectl rolling-restart deployment pggit-api -n production
```

---

## Post-Rollback Verification

**After rollback, verify system health:**

### Health Checks

```bash
# API Health
curl -s http://pggit-api:8080/health | jq .

# Database Connectivity
psql -U postgres -d pggit -c "SELECT 1;"

# Queue Status
psql -U postgres -d pggit -c "
  SELECT
    delivery_status,
    COUNT(*) as count
  FROM pggit.alert_delivery_queue
  GROUP BY delivery_status;"

# Webhook Health
psql -U postgres -d pggit -c "
  SELECT
    health_status,
    COUNT(*) as count
  FROM pggit.webhook_health_metrics
  GROUP BY health_status;"

# Replication Lag (multi-region)
psql -U postgres -d pggit -c "
  SELECT * FROM pggit.measure_replication_lag();"
```

### Metrics Verification

```bash
# Check Prometheus metrics
curl -s http://prometheus:9090/api/v1/query?query=up{job=\"pggit-api\"} | jq .

# Check error rates
curl -s 'http://prometheus:9090/api/v1/query?query=rate(http_requests_total{status=~"5.."}[5m])' | jq .

# Check latency
curl -s 'http://prometheus:9090/api/v1/query?query=histogram_quantile(0.99,http_request_duration_seconds_bucket)' | jq .
```

### Data Integrity Check

```bash
# Verify no data loss
SELECT COUNT(*) as total_deliveries FROM pggit.alert_delivery_queue;

# Check for conflicts in multi-region
SELECT COUNT(*) as unresolved_conflicts
FROM pggit.replication_conflict_log
WHERE resolved = FALSE;

# Verify schema version
SELECT * FROM pggit.schema_versions
ORDER BY applied_at DESC LIMIT 5;
```

---

## Incident Communication

### Notification Template (Slack)

```
🚨 INCIDENT: Phase 8 Deployment Rollback

Severity: [CRITICAL|HIGH|MEDIUM]
Status: [IN_PROGRESS|RESOLVED]
Impact: Webhook delivery system

Timeline:
- 14:32 UTC: Deployment initiated
- 14:35 UTC: Error rate spike detected (> 5%)
- 14:36 UTC: Rollback initiated
- 14:38 UTC: Previous version restored
- 14:40 UTC: System stable, error rate < 1%

Root Cause: [To be determined]

Actions Taken:
- Rolled back to v1.0.3
- Verified data integrity
- Restored traffic

Next Steps:
- Root cause analysis
- Fix and test in staging
- Redeploy with fixes

ETA for Fix: [TIME]

On-Call: @[engineer-name]
Status Page: https://status.pggit.io
```

### Email Escalation

```
Subject: Incident Report: Phase 8 Deployment Rollback

To: engineering-leads@pggit.io, ops@pggit.io

Timeline:
- 2025-12-27 14:32 UTC: Phase 8 deployment started
- 2025-12-27 14:35 UTC: Error rate exceeded 5%
- 2025-12-27 14:36 UTC: Rollback decision made
- 2025-12-27 14:40 UTC: System restored

Impact Analysis:
- Duration: 8 minutes
- Affected webhooks: [COUNT]
- Failed deliveries: [COUNT]
- Data loss: None

Action Items:
1. [ ] Root cause analysis (assigned to: [NAME])
2. [ ] Fix development and testing (assigned to: [NAME])
3. [ ] Post-mortem meeting (scheduled for: [DATE/TIME])
4. [ ] Code review process improvement

See incident details: [LINK TO INCIDENT REPORT]
```

---

## Contacts & Escalation

### Escalation Path

```
On-Call Engineer (Level 1)
        ↓
   (Cannot resolve in 10 min)
        ↓
Engineering Lead (Level 2)
        ↓
   (Critical issue, Level 3 needed)
        ↓
Chief Architect / VP Engineering (Level 3)
```

### Contact Information

| Role | Name | Phone | Slack |
|------|------|-------|-------|
| On-Call | @pggit-oncall | +1-XXX-XXX-XXXX | #pggit-oncall |
| Eng Lead | Sarah Chen | +1-XXX-XXX-XXXX | @sarah-chen |
| DevOps Lead | Kevin Park | +1-XXX-XXX-XXXX | @kevin-park |
| Chief Architect | Marcus Rodriguez | +1-XXX-XXX-XXXX | @marcus-rodriguez |

### Incident Response SLA

- **Detection:** < 1 minute (automated alerts)
- **Acknowledgment:** < 5 minutes (on-call engineer)
- **Mitigation:** < 15 minutes (stop the bleeding)
- **Resolution:** < 4 hours (fix and redeploy)
- **Post-Mortem:** < 24 hours (learning and improvement)

---

## Recovery Checklist

**After Rollback, Complete These:**

- [ ] Notify all stakeholders (Slack, email, status page)
- [ ] Verify all systems operational
- [ ] Check for data loss or corruption
- [ ] Document what happened (incident report)
- [ ] Identify root cause
- [ ] Create fix in new branch
- [ ] Test fix in staging environment
- [ ] Get code review approval (2+ engineers)
- [ ] Schedule redeploy (after team agreement)
- [ ] Hold post-mortem meeting within 24 hours
- [ ] Update deployment procedures based on learnings
- [ ] Close incident ticket

---

## Appendix: Quick Commands Reference

```bash
# Check deployment status
kubectl get deployment pggit-api -n production -o wide

# View recent logs
kubectl logs deployment/pggit-api -n production --tail=50

# Check metrics
kubectl top pod -n production | grep pggit

# Restart if hung
kubectl rollout restart deployment/pggit-api -n production

# Restore from backup
pg_restore -U postgres -d pggit -j 4 /backups/pggit_pre-phase8.dump

# Monitor replication
watch 'psql -U postgres -c "SELECT * FROM pggit.measure_replication_lag();"'

# Alert on errors
kubectl logs deployment/pggit-api -n production -f | grep -i error

# Check database size
du -sh /var/lib/postgresql/data/base/*

# Kill idle connections
psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle';"
```

---

**Document Status:** APPROVED ✅
**Last Reviewed:** 2025-12-27
**Next Review:** 2026-01-27 (30 days after deployment)

For questions or updates, contact: devops@pggit.io
