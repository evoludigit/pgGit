# pgGit v2 Operations Guide

**Open Source Project Maintenance Guide**

---

## Support Channels

### 🐛 **Bug Reports & Issues**
- **GitHub Issues**: [github.com/yourusername/pgGit/issues](https://github.com/yourusername/pgGit/issues)
- **Priority**: Security issues, data corruption, critical bugs
- **Response Time**: Within 24-48 hours for urgent issues

### 💬 **Community Support**
- **GitHub Discussions**: General questions and troubleshooting
- **Documentation**: Self-service troubleshooting guides
- **Stack Overflow**: Community-driven Q&A (tag: pggit)

---

## System Architecture Overview

### Core Components
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Applications   │────│  pgGit v2 API   │────│ PostgreSQL DB   │
│  (DDL Changes)  │    │   (Functions)   │    │   (pggit_v0.*)  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                        │                        │
         └────────────────────────┼────────────────────────┘
                                  ▼
                       ┌─────────────────┐
                       │  Monitoring &   │
                       │   Alerting      │
                       └─────────────────┘
```

### Key Data Stores
- **pggit_v0.objects**: Git-like object storage (blobs, trees, commits)
- **pggit_v0.refs**: Branch and tag references
- **pggit_v0.commit_graph**: Commit history and metadata
- **pggit_audit.changes**: Detailed change audit trail
- **pggit_v0.performance_metrics**: Query performance data

---

## Health Checks & Monitoring

### Daily Health Checks (Required)

#### 1. System Integrity Validation
```sql
-- Run every morning at 6:00 AM
SELECT * FROM pggit_v0.validate_data_integrity();

-- Expected: All rows should show 'OK' status
-- Alert if: Any row shows 'FAILED' status
```

#### 2. Alert Monitoring
```sql
-- Check for active alerts every 15 minutes
SELECT * FROM pggit_v0.check_for_alerts();

-- Expected: severity = 'OK' for all alerts
-- Alert if: Any alerts with severity 'CRITICAL' or 'WARNING'
```

#### 3. Performance Monitoring
```sql
-- Check query performance daily
SELECT * FROM pggit_v0.analyze_query_performance()
WHERE avg_duration > INTERVAL '100 ms';

-- Expected: No queries slower than 100ms
-- Alert if: Queries exceed performance thresholds
```

### Dashboard Monitoring

#### Real-time Metrics Dashboard
```sql
-- Executive dashboard (refresh every 5 minutes)
SELECT * FROM pggit_v0.get_dashboard_summary();

-- Key metrics to monitor:
-- - Total Objects: Should grow steadily
-- - Active Branches: Should be reasonable (< 50)
-- - Storage Used: Should be within capacity limits
-- - Recent Commits: Should show active development
```

#### Weekly Performance Review
```sql
-- Run every Monday morning
SELECT * FROM pggit_v0.estimate_storage_growth();
SELECT * FROM pggit_v0.get_recommendations();

-- Review trends and plan optimizations
```

---

## Issue Resolution Process

### Issue Triage

#### 🚨 **Critical Priority** (Response: Same day)
- Data corruption or loss
- Security vulnerabilities
- System crashes in production
- Breaking changes without migration path

#### 📋 **High Priority** (Response: 1-2 days)
- Major functionality broken
- Performance degradation
- Incorrect behavior
- Missing documentation

#### 💡 **Medium Priority** (Response: 1 week)
- Feature requests
- Minor bugs
- Documentation improvements
- Enhancement suggestions

#### ❓ **Low Priority** (Response: Best effort)
- General questions
- Minor UI/UX issues
- Code cleanup suggestions

### Resolution Workflow

#### 1. **Initial Assessment**
- Reproduce the issue if possible
- Check existing issues and documentation
- Determine severity and priority

#### 2. **Investigation**
```sql
-- For performance issues
SELECT * FROM pggit_v0.analyze_query_performance();

-- For data integrity issues
SELECT * FROM pggit_v0.validate_data_integrity();

-- For general diagnostics
SELECT * FROM pggit_v0.get_dashboard_summary();
```

#### 3. **Solution Development**
- Identify root cause
- Develop fix or workaround
- Test solution thoroughly

#### 4. **Communication**
- Update issue with findings
- Provide workaround if available
- Schedule fix deployment

#### 5. **Follow-up**
- Close issue when resolved
- Update documentation if needed
- Consider preventive measures

---

## Maintenance Tasks

### Regular Health Checks

#### System Validation
```sql
-- Basic health check
SELECT * FROM pggit_v0.check_for_alerts();
SELECT * FROM pggit_v0.validate_data_integrity();

-- Performance overview
SELECT * FROM pggit_v0.get_dashboard_summary();
```

#### GitHub Repository Maintenance
- Review and triage open issues
- Update pull requests
- Monitor CI/CD pipeline status
- Update documentation as needed

### Code Quality Maintenance

#### Dependency Updates
- Monitor for security vulnerabilities in dependencies
- Update PostgreSQL extension versions
- Test compatibility with new PostgreSQL versions

#### Performance Monitoring
```sql
-- Check for performance regressions
SELECT * FROM pggit_v0.analyze_query_performance()
ORDER BY avg_duration DESC
LIMIT 5;

-- Monitor storage growth
SELECT * FROM pggit_v0.estimate_storage_growth();
```

### Monthly Maintenance

#### Storage Optimization (1st of Month)
```sql
-- Review storage usage
SELECT * FROM pggit_v0.analyze_storage_usage();
SELECT * FROM pggit_v0.get_object_size_distribution();

-- Archive old data if needed
-- (Implement based on retention policies)
```

#### Security Audit (1st of Month)
```sql
-- Review permissions
SELECT * FROM information_schema.role_table_grants
WHERE table_schema IN ('pggit', 'pggit_v0', 'pggit_audit');

-- Check for orphaned objects
SELECT * FROM pggit_v0.detect_anomalies();
```

---

## Backup & Recovery

### Backup Strategy

#### Daily Backups
- **Full Database Backup**: 2:00 AM daily
- **Transaction Log Backup**: Every 15 minutes
- **pgGit Metadata Backup**: Included in full backup

#### Weekly Backups
- **Schema-only Backup**: Sunday 3:00 AM
- **Test Restore Validation**: Monday 4:00 AM

### Recovery Procedures

#### Point-in-Time Recovery
```sql
-- Stop the database
pg_ctl stop -D $PGDATA

-- Restore base backup
pg_restore -d postgres /path/to/base_backup.dump

-- Apply WAL logs to target time
pg_wal_replay --target-time "2025-12-22 14:30:00"
```

#### pgGit-Specific Recovery
```sql
-- After database recovery, validate pgGit integrity
SELECT * FROM pggit_v0.validate_data_integrity();

-- Rebuild any missing refs
-- (Main branch should exist, recreate others as needed)

-- Validate commit graph
SELECT COUNT(*) FROM pggit_v0.commit_graph;
```

### Disaster Recovery Testing

#### Quarterly DR Tests
1. Restore database to separate instance
2. Validate pgGit functionality
3. Test application connectivity
4. Verify data integrity
5. Document results and improvements

---

## Performance Tuning

### Query Optimization

#### Slow Query Identification
```sql
-- Find slow pgGit queries
SELECT
    query,
    avg_time,
    calls,
    total_time
FROM pg_stat_statements
WHERE query LIKE '%pggit_v0%'
ORDER BY avg_time DESC
LIMIT 10;
```

#### Index Optimization
```sql
-- Check index usage
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname IN ('pggit', 'pggit_v0', 'pggit_audit')
ORDER BY idx_scan DESC;
```

### Memory Tuning

#### Work Mem Settings
```sql
-- For complex pgGit queries
SET work_mem = '256MB';  -- Temporary increase for large diffs

-- Reset after operation
RESET work_mem;
```

#### Shared Buffers
- Monitor buffer hit ratio: `SELECT sum(blks_hit)*100/sum(blks_hit+blks_read) FROM pg_stat_database;`
- Target: > 95% buffer hit ratio
- Adjust shared_buffers if needed

### Storage Optimization

#### Table Partitioning
```sql
-- Partition large audit tables by month
CREATE TABLE pggit_audit.changes_y2025m12 PARTITION OF pggit_audit.changes
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');
```

#### Compression
```sql
-- Enable compression for large objects
ALTER TABLE pggit.objects SET (autovacuum_enabled = true);
ALTER TABLE pggit_audit.changes SET (autovacuum_enabled = true);
```

---

## Troubleshooting Guide

### Common Issues & Solutions

#### Issue: "No commits found" Error
**Symptoms**: Branch creation fails
**Solution**:
```sql
SELECT pggit_v0.create_basic_commit('Initialize repository');
```

#### Issue: Slow Performance
**Symptoms**: Queries taking > 100ms
**Diagnosis**:
```sql
SELECT * FROM pggit_v0.analyze_query_performance();
ANALYZE;  -- Update statistics
```

#### Issue: Data Integrity Failures
**Symptoms**: Integrity checks failing
**Solution**:
```sql
SELECT * FROM pggit_v0.validate_data_integrity();
-- Investigate and fix root cause
-- Run REINDEX if index corruption suspected
```

#### Issue: Storage Growth Issues
**Symptoms**: Database growing too fast
**Solution**:
```sql
SELECT * FROM pggit_v0.estimate_storage_growth();
SELECT * FROM pggit_v0.get_recommendations();
-- Implement archiving/cleanup strategies
```

#### Issue: Branch Conflicts
**Symptoms**: Merge operations failing
**Solution**:
```sql
-- Check what differs
SELECT * FROM pggit_v0.diff_branches('main', 'feature/branch');

-- Resolve conflicts manually
-- Re-run merge after fixes
```

---

## Escalation Procedures

### When to Escalate

#### Immediate Escalation (SEV 1)
- System unavailable for > 15 minutes
- Data loss or corruption detected
- Security breach identified
- Multiple critical applications affected

#### Fast Escalation (SEV 2)
- System performance < 50% of normal
- Major functionality broken
- Significant user impact
- No clear resolution path

#### Standard Escalation (SEV 3-4)
- Follow normal incident response
- Involve subject matter experts as needed
- Escalate if resolution > 4 hours

### Communication Templates

#### Incident Notification
```
Subject: [SEV X] pgGit System Incident - [Brief Description]

Incident Details:
- Detection Time: [Time]
- Affected Systems: [Systems]
- Impact: [User/Application Impact]
- Initial Assessment: [What we know]
- Actions Taken: [Immediate response]
- ETA: [Estimated resolution time]

On-call Team: [Responding team members]
CC: [Stakeholders]
```

#### Resolution Update
```
Subject: [RESOLVED] pgGit System Incident - [Brief Description]

Resolution Summary:
- Root Cause: [What caused the issue]
- Resolution: [How it was fixed]
- Duration: [Total downtime]
- Impact Assessment: [Business impact]

Preventive Actions:
- [Actions to prevent recurrence]

Post-Mortem: [Link to detailed analysis]
```

---

## Compliance & Auditing

### Regulatory Requirements

#### SOX Compliance
- Complete audit trail of all schema changes
- User accountability for DDL operations
- Change approval workflows
- Automated compliance reporting

#### GDPR Compliance
- Data retention policies
- Right to erasure procedures
- Audit logging of data access
- Breach notification procedures

### Audit Procedures

#### Monthly Compliance Audit
```sql
-- Review change history
SELECT
    author,
    COUNT(*) as changes,
    MIN(change_timestamp) as first_change,
    MAX(change_timestamp) as last_change
FROM pggit.history
WHERE change_timestamp >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY author
ORDER BY changes DESC;
```

#### Annual Security Audit
- Review access controls
- Validate encryption at rest
- Test backup/restore procedures
- Audit user permissions

---

## Training & Knowledge Transfer

### Team Training Requirements

#### Required Training
- All developers: pgGit Developer Training (4 hours)
- SRE/Operations: pgGit Operations Training (2 hours)
- Architects: Advanced pgGit Patterns (4 hours)

#### Certification
- pgGit Developer Certification (80% quiz score + practical exam)
- pgGit Operations Certification (hands-on runbook walkthrough)

### Knowledge Base

#### Documentation Locations
- **Runbook**: This document (internal wiki)
- **API Reference**: `/docs/api-reference.md`
- **User Guide**: `/docs/user-guide.md`
- **Training Materials**: `/training/` directory

#### Support Resources
- **Internal Slack**: #pgGit-support
- **Email**: pgGit support team
- **Wiki**: companywiki.com/pgGit
- **GitHub**: github.company.com/pgGit

---

## Metrics & Reporting

### Key Performance Indicators

#### System Health Metrics
- **Uptime**: > 99.9% availability
- **Response Time**: < 50ms for all functions
- **Data Integrity**: 100% validation success rate
- **Storage Growth**: Predictable within 20% of projections

#### Usage Metrics
- **Active Users**: > 80% of development team
- **Daily Commits**: Steady development activity
- **Branch Count**: < 50 active branches
- **Query Volume**: Sustainable load patterns

### Reporting Cadence

#### Daily Reports
- System health summary (email to stakeholders)
- Alert summary (if any alerts occurred)
- Performance metrics (response times, error rates)

#### Weekly Reports
- Usage statistics (commits, branches, users)
- Performance trends (response times, storage growth)
- Incident summary (if any incidents occurred)

#### Monthly Reports
- Compliance audit results
- Capacity planning recommendations
- Feature usage analysis
- Team training status

---

## Getting Help

### Community Support
- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: General questions and troubleshooting
- **Documentation**: Self-service guides and tutorials
- **Stack Overflow**: Community-driven Q&A (tag: pggit)

### Contributing
- **Pull Requests**: Code contributions welcome
- **Documentation**: Help improve guides and tutorials
- **Testing**: Report bugs and edge cases
- **Feedback**: Share your experience and suggestions

---

**Version**: 2.0
**Last Updated**: December 22, 2025
**Review Cycle**: Quarterly
**Document Owner**: SRE Team Lead

*This runbook ensures 24/7 operational excellence for pgGit v2 systems.*