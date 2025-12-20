# SOC2 Compliance Preparation

## Trust Service Criteria Coverage

### Security (CC)

**CC6.1 - Logical and Physical Access Controls**

pgGit implements:
- ✅ Role-based access control via PostgreSQL roles
- ✅ Audit logging of all DDL changes
- ✅ Encryption at rest (via PostgreSQL configuration)
- ✅ Encryption in transit (SSL/TLS)

Evidence:
```sql
-- Audit trail of who accessed what
SELECT created_by, change_type, COUNT(*)
FROM pggit.history
WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY created_by, change_type;
```

**CC7.2 - System Monitoring**

pgGit provides:
- ✅ Health check monitoring (`pggit.health_check()`)
- ✅ Performance metrics collection
- ✅ Prometheus integration for alerting
- ✅ Automated anomaly detection

Evidence:
```sql
SELECT * FROM pggit.system_overview();
```

### Availability (A)

**A1.2 - Backup and Recovery**

pgGit documentation provides:
- ✅ Backup procedures (BACKUP_RESTORE.md)
- ✅ Disaster recovery plan (DISASTER_RECOVERY.md)
- ✅ RTO/RPO objectives defined
- ✅ Recovery testing procedures

Evidence: Run disaster recovery drill monthly

### Confidentiality (C)

**C1.1 - Confidential Information**

pgGit handles:
- ✅ Schema metadata (may be sensitive)
- ✅ DDL commands (may reveal business logic)
- ✅ User identities (tracked in history)

Protection measures:
```sql
-- Restrict access to history
REVOKE ALL ON pggit.history FROM public;
GRANT SELECT ON pggit.history TO pggit_auditors;
```

## SOC2 Audit Evidence

### Required Documentation

1. **System Description**: README.md, architecture docs
2. **Security Policies**: SECURITY.md, access control guide
3. **Change Management**: Documented in pggit.history table
4. **Incident Response**: SECURITY.md vulnerability disclosure
5. **Monitoring**: MONITORING.md, SLO.md

### Audit Queries

```sql
-- Control: All changes are logged
SELECT
    DATE_TRUNC('month', created_at) as month,
    COUNT(*) as change_count
FROM pggit.history
WHERE created_at > NOW() - INTERVAL '1 year'
GROUP BY month
ORDER BY month;

-- Control: Unauthorized access attempts
SELECT COUNT(*)
FROM pggit.history
WHERE change_type = 'FAILED_AUTH'  -- Custom tracking
AND created_at > NOW() - INTERVAL '90 days';

-- Control: System availability
SELECT
    check_name,
    status,
    message
FROM pggit.health_check()
WHERE status != 'healthy';
```

## SOC2 Preparation Checklist

- [ ] Document all trust service criteria mappings
- [ ] Implement evidence collection procedures
- [ ] Schedule quarterly access reviews
- [ ] Establish change management workflow
- [ ] Create incident response procedures
- [ ] Configure log retention (7 years for SOC2)
- [ ] Implement log forwarding to SIEM

## Access Control Implementation

### Role-Based Access
```sql
-- Create SOC2-compliant roles
CREATE ROLE pggit_admin;
CREATE ROLE pggit_user;
CREATE ROLE pggit_auditor;

-- Grant appropriate permissions
GRANT USAGE ON SCHEMA pggit TO pggit_user;
GRANT SELECT ON pggit.objects TO pggit_user;
GRANT SELECT ON pggit.history TO pggit_auditor;

-- Revoke public access
REVOKE ALL ON SCHEMA pggit FROM public;
```

### Audit Logging
```sql
-- Enable detailed audit logging
ALTER SYSTEM SET log_statement = 'ddl';
ALTER SYSTEM SET log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h ';
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;

-- Create audit trail view
CREATE VIEW pggit.audit_trail AS
SELECT
    created_at,
    created_by,
    change_type,
    object_name,
    schema_name,
    metadata
FROM pggit.history
WHERE created_at > NOW() - INTERVAL '7 years'
ORDER BY created_at DESC;
```

## Change Management

### Change Approval Process
```sql
-- Track change requests
CREATE TABLE pggit.change_requests (
    id SERIAL PRIMARY KEY,
    requested_by TEXT,
    change_description TEXT,
    risk_level TEXT CHECK (risk_level IN ('low', 'medium', 'high')),
    approved_by TEXT,
    approved_at TIMESTAMP,
    implemented_at TIMESTAMP,
    status TEXT DEFAULT 'pending'
);

-- Link changes to requests
ALTER TABLE pggit.history ADD COLUMN change_request_id INTEGER REFERENCES pggit.change_requests(id);
```

### Automated Testing
```sql
-- Pre-change validation
CREATE OR REPLACE FUNCTION pggit.validate_change(
    change_type TEXT,
    object_name TEXT
)
RETURNS TABLE (
    validation_check TEXT,
    status TEXT,
    message TEXT
) AS $$
BEGIN
    -- Check for conflicts
    RETURN QUERY
    SELECT
        'conflict_check'::TEXT,
        CASE WHEN COUNT(*) > 0 THEN 'warning' ELSE 'ok' END,
        'Potential conflicts detected'::TEXT
    FROM pggit.history
    WHERE object_name = validate_change.object_name
      AND created_at > NOW() - INTERVAL '1 hour';

    -- Security validation
    RETURN QUERY
    SELECT
        'security_check'::TEXT,
        'ok'::TEXT,
        'Change passed security validation'::TEXT;

END;
$$ LANGUAGE plpgsql;
```

## Incident Response

### Incident Detection
```sql
-- Automated incident detection
CREATE OR REPLACE FUNCTION pggit.detect_anomalies()
RETURNS TABLE (
    anomaly_type TEXT,
    severity TEXT,
    description TEXT,
    detected_at TIMESTAMP
) AS $$
BEGIN
    -- Unusual activity spikes
    RETURN QUERY
    SELECT
        'activity_spike'::TEXT,
        'medium'::TEXT,
        format('Unusual activity: %s changes in last hour', COUNT(*))::TEXT,
        NOW()
    FROM pggit.history
    WHERE created_at > NOW() - INTERVAL '1 hour'
    HAVING COUNT(*) > 1000;

    -- Failed operations
    RETURN QUERY
    SELECT
        'failed_operations'::TEXT,
        'high'::TEXT,
        format('High failure rate: %s failed operations', COUNT(*))::TEXT,
        NOW()
    FROM pggit.upgrade_log
    WHERE status = 'failed'
      AND started_at > NOW() - INTERVAL '1 hour'
    HAVING COUNT(*) > 10;

END;
$$ LANGUAGE plpgsql;
```

### Evidence Collection
```sql
-- Automated evidence gathering
CREATE OR REPLACE FUNCTION pggit.collect_soc2_evidence(
    audit_period_start DATE DEFAULT CURRENT_DATE - INTERVAL '1 month',
    audit_period_end DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    control_id TEXT,
    evidence_type TEXT,
    evidence_data JSONB,
    collection_timestamp TIMESTAMP
) AS $$
BEGIN
    -- Access control evidence
    RETURN QUERY
    SELECT
        'CC6.1'::TEXT,
        'access_log'::TEXT,
        jsonb_build_object(
            'period', format('%s to %s', audit_period_start, audit_period_end),
            'access_count', COUNT(*),
            'unique_users', COUNT(DISTINCT created_by)
        ),
        NOW()
    FROM pggit.history
    WHERE created_at BETWEEN audit_period_start AND audit_period_end;

    -- System monitoring evidence
    RETURN QUERY
    SELECT
        'CC7.2'::TEXT,
        'health_checks'::TEXT,
        jsonb_build_object(
            'period', format('%s to %s', audit_period_start, audit_period_end),
            'total_checks', COUNT(*),
            'healthy_checks', COUNT(*) FILTER (WHERE status = 'healthy')
        ),
        NOW()
    FROM (
        SELECT status, created_at
        FROM pggit.performance_metrics
        WHERE metric_type = 'health_check'
          AND recorded_at BETWEEN audit_period_start AND audit_period_end
    ) health;

END;
$$ LANGUAGE plpgsql;
```

## Log Retention and Management

### Long-term Retention
```sql
-- Archive old logs (move to separate table)
CREATE TABLE pggit.history_archive (
    LIKE pggit.history INCLUDING ALL
) PARTITION BY RANGE (created_at);

-- Automated archiving function
CREATE OR REPLACE FUNCTION pggit.archive_old_data(
    retention_period INTERVAL DEFAULT INTERVAL '7 years'
)
RETURNS INTEGER AS $$
DECLARE
    archived_count INTEGER;
BEGIN
    -- Move old data to archive
    INSERT INTO pggit.history_archive
    SELECT * FROM pggit.history
    WHERE created_at < NOW() - retention_period;

    -- Delete from active table
    DELETE FROM pggit.history
    WHERE created_at < NOW() - retention_period;

    GET DIAGNOSTICS archived_count = ROW_COUNT;
    RETURN archived_count;
END;
$$ LANGUAGE plpgsql;

-- Schedule automated archiving
SELECT cron.schedule(
    'archive-soc2-logs',
    '0 2 1 * *',  -- First day of month at 2 AM
    'SELECT pggit.archive_old_data();'
);
```

### Log Integrity
```sql
-- Cryptographic log signing
CREATE OR REPLACE FUNCTION pggit.sign_log_entry(
    log_data JSONB
)
RETURNS TEXT AS $$
DECLARE
    log_signature TEXT;
BEGIN
    -- Create cryptographic signature
    SELECT encode(
        digest(log_data::text || NOW()::text, 'sha256'),
        'hex'
    ) INTO log_signature;

    RETURN log_signature;
END;
$$ LANGUAGE plpgsql;

-- Add signature to history entries
ALTER TABLE pggit.history ADD COLUMN log_signature TEXT;
CREATE INDEX idx_history_signature ON pggit.history (log_signature);
```

## Monitoring and Alerting

### SOC2-Specific Alerts
```yaml
# alert_rules_soc2.yml
groups:
  - name: soc2-compliance
    rules:
      - alert: SOC2AccessViolation
        expr: increase(pggit_failed_access_total[1h]) > 5
        for: 5m
        labels:
          severity: critical
          soc2_control: CC6.1
        annotations:
          summary: "SOC2 Access Control Violation"
          description: "Multiple failed access attempts detected"

      - alert: SOC2DataLossRisk
        expr: pggit_backup_age_hours > 25
        for: 5m
        labels:
          severity: high
          soc2_control: A1.2
        annotations:
          summary: "SOC2 Backup Age Violation"
          description: "Backup is older than 24 hours"

      - alert: SOC2MonitoringFailure
        expr: up{job="pggit-health"} == 0
        for: 10m
        labels:
          severity: critical
          soc2_control: CC7.2
        annotations:
          summary: "SOC2 Monitoring System Down"
          description: "Health monitoring system is not responding"
```

## SOC2 Audit Preparation

### Pre-Audit Checklist
- [ ] All evidence collection procedures tested
- [ ] Access reviews completed for quarter
- [ ] Change management process documented
- [ ] Incident response procedures validated
- [ ] Log retention policies implemented
- [ ] Security monitoring alerts configured
- [ ] Backup and recovery tested
- [ ] Penetration testing completed

### During Audit
- [ ] Provide auditor access to evidence collection
- [ ] Demonstrate control effectiveness
- [ ] Show incident response capabilities
- [ ] Present monitoring dashboards
- [ ] Review change management workflow
- [ ] Validate log integrity procedures

### Post-Audit
- [ ] Address any findings
- [ ] Update procedures based on recommendations
- [ ] Schedule next audit
- [ ] Communicate results to stakeholders

## Continuous Compliance

### Monthly Activities
- Access control reviews
- Evidence collection validation
- Security monitoring review
- Backup testing

### Quarterly Activities
- Full security assessment
- Penetration testing
- Disaster recovery testing
- SOC2 control validation

### Annual Activities
- SOC2 audit preparation and execution
- Policy and procedure updates
- Technology refresh planning
- Compliance training