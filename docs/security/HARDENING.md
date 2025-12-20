# Security Hardening Checklist

## Database Level

**Principle of Least Privilege**
```sql
-- Revoke public access
REVOKE ALL ON SCHEMA pggit FROM public;

-- Grant only necessary permissions
GRANT USAGE ON SCHEMA pggit TO app_user;
GRANT SELECT ON pggit.objects TO app_user;
```

**Row Level Security (RLS)**
```sql
-- Enable RLS on sensitive tables
ALTER TABLE pggit.history ENABLE ROW LEVEL SECURITY;

-- Policy: Users see only their changes
CREATE POLICY user_isolation ON pggit.history
    FOR SELECT
    USING (created_by = current_user);
```

**Audit All DDL**
```sql
-- Verify event triggers are active
SELECT evtname, evtenabled
FROM pg_event_trigger
WHERE evtname LIKE 'pggit%';
```

**Encrypted Connections Only**
```ini
# postgresql.conf
ssl = on
ssl_prefer_server_ciphers = on
ssl_min_protocol_version = 'TLSv1.2'
```

## Application Level

**Input Validation**
- All user inputs validated
- Use `quote_ident()` for identifiers
- Use `quote_literal()` or `format(%L)` for literals

**No Dynamic SQL from User Input**
```sql
-- ❌ NEVER DO THIS:
EXECUTE 'DROP TABLE ' || user_input;

-- ✅ DO THIS:
EXECUTE format('DROP TABLE %I', quote_ident(user_input));
```

**Rate Limiting**
```sql
-- Limit DDL operations per user
CREATE TABLE pggit.rate_limits (
    user_name TEXT PRIMARY KEY,
    last_reset TIMESTAMP DEFAULT NOW(),
    operation_count INT DEFAULT 0
);
```

## Infrastructure Level

**Regular Security Updates**
- PostgreSQL patched to latest minor version
- OS security updates applied weekly
- pgGit updated to latest release

**Firewall Rules**
- PostgreSQL port (5432) restricted to app servers
- No direct internet access to database

**Secrets Management**
- Database passwords in vault (HashiCorp Vault, AWS Secrets Manager)
- No passwords in code or config files

**Monitoring & Alerting**
- Failed login attempts monitored
- Unusual query patterns detected
- Performance anomalies alerted

## Compliance Level

**Data Retention**
```sql
-- Archive old history (GDPR: right to be forgotten)
CREATE TABLE pggit.history_archive (LIKE pggit.history);

-- Move data older than 7 years
INSERT INTO pggit.history_archive
SELECT * FROM pggit.history
WHERE created_at < NOW() - INTERVAL '7 years';

DELETE FROM pggit.history
WHERE created_at < NOW() - INTERVAL '7 years';
```

**Privacy by Design**
- Personal data minimization
- No unnecessary PII in metadata

**Audit Logging**
- All access logged
- Logs immutable (append-only)
- Log retention policy enforced

## Network Security

**TLS Configuration**
```ini
# postgresql.conf
ssl = on
ssl_cert_file = '/etc/ssl/certs/postgresql.crt'
ssl_key_file = '/etc/ssl/private/postgresql.key'
ssl_ca_file = '/etc/ssl/certs/ca.crt'
ssl_crl_file = '/etc/ssl/certs/crl.pem'
ssl_prefer_server_ciphers = on
ssl_min_protocol_version = 'TLSv1.2'
ssl_max_protocol_version = 'TLSv1.3'
ssl_ciphers = 'HIGH:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!SRP:!CAMELLIA'
```

**Connection Limits**
```ini
# postgresql.conf
max_connections = 100
superuser_reserved_connections = 3
```

**Host-Based Authentication**
```ini
# pg_hba.conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             postgres                                peer
hostssl all             app_user        10.0.0.0/8             scram-sha-256
hostssl all             app_user        192.168.0.0/16         scram-sha-256
hostssl replication     replica         10.0.0.0/8             scram-sha-256
```

## Operating System Security

**File Permissions**
```bash
# Secure PostgreSQL files
chown -R postgres:postgres /var/lib/postgresql
chmod 700 /var/lib/postgresql/data
chmod 600 /var/lib/postgresql/data/postgresql.conf
chmod 600 /var/lib/postgresql/data/pg_hba.conf

# Secure log files
chmod 600 /var/log/postgresql/*.log
```

**Service Configuration**
```ini
# /etc/systemd/system/postgresql.service
[Unit]
Description=PostgreSQL database server
After=network.target

[Service]
Type=forking
User=postgres
Group=postgres
PermissionsStartOnly=true
ExecStartPre=/usr/local/bin/check-postgres-permissions
ExecStart=/usr/bin/pg_ctl start -D /var/lib/postgresql/data
ExecStop=/usr/bin/pg_ctl stop -D /var/lib/postgresql/data
ExecReload=/usr/bin/pg_ctl reload -D /var/lib/postgresql/data
TimeoutSec=300

[Install]
WantedBy=multi-user.target
```

**Kernel Security**
```bash
# Enable security modules
echo "kernel.yama.ptrace_scope = 1" >> /etc/sysctl.d/99-security.conf
echo "kernel.kptr_restrict = 1" >> /etc/sysctl.d/99-security.conf
echo "kernel.dmesg_restrict = 1" >> /etc/sysctl.d/99-security.conf

# Apply settings
sysctl -p /etc/sysctl.d/99-security.conf
```

## Monitoring and Detection

**Intrusion Detection**
```sql
-- Monitor for suspicious patterns
CREATE OR REPLACE FUNCTION pggit.security_monitor()
RETURNS TABLE (
    alert_type TEXT,
    severity TEXT,
    description TEXT,
    detected_at TIMESTAMP
) AS $$
BEGIN
    -- SQL injection attempts
    RETURN QUERY
    SELECT
        'sql_injection'::TEXT,
        'high'::TEXT,
        format('Potential SQL injection detected: %s', query)::TEXT,
        NOW()
    FROM pg_stat_activity
    WHERE query LIKE '%1=1%'
       OR query LIKE '%'' OR ''%'
       OR query LIKE '%UNION SELECT%'
       AND query NOT LIKE '%pggit.%';

    -- Unusual connection patterns
    RETURN QUERY
    SELECT
        'unusual_connections'::TEXT,
        'medium'::TEXT,
        format('High connection rate from %s', client_addr)::TEXT,
        NOW()
    FROM pg_stat_activity
    WHERE client_addr IS NOT NULL
    GROUP BY client_addr
    HAVING COUNT(*) > 50;

END;
$$ LANGUAGE plpgsql;
```

**Automated Response**
```sql
-- Block suspicious IPs (requires pgbouncer or firewall integration)
CREATE OR REPLACE FUNCTION pggit.block_suspicious_ip(
    suspicious_ip INET
)
RETURNS void AS $$
BEGIN
    -- Log the blocking action
    INSERT INTO pggit.security_events (
        event_type, event_data, blocked_ip
    ) VALUES (
        'ip_blocked',
        jsonb_build_object('reason', 'suspicious_activity'),
        suspicious_ip
    );

    -- In a real implementation, this would integrate with:
    -- - Firewall rules (iptables, firewalld)
    -- - Load balancer blocking
    -- - pgbouncer configuration updates
END;
$$ LANGUAGE plpgsql;
```

## Backup Security

**Encrypted Backups**
```bash
# Encrypt backups with GPG
pg_dump -U postgres pggit_prod | gpg --encrypt --recipient security@company.com > pggit_backup_$(date +%Y%m%d).sql.gpg

# Verify backup integrity
gpg --decrypt pggit_backup_$(date +%Y%m%d).sql.gpg | psql -U postgres -d pggit_test_restore
```

**Backup Verification**
```bash
#!/bin/bash
# scripts/security/verify-backup-integrity.sh

BACKUP_FILE=$1
EXPECTED_CHECKSUM=$2

# Verify file integrity
ACTUAL_CHECKSUM=$(sha256sum "$BACKUP_FILE" | cut -d' ' -f1)

if [ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
    echo "❌ Backup integrity check failed!"
    exit 1
fi

echo "✅ Backup integrity verified"
```

## Incident Response

**Security Incident Procedures**
1. **Detection**: Automated monitoring alerts
2. **Assessment**: Evaluate impact and scope
3. **Containment**: Isolate affected systems
4. **Investigation**: Forensic analysis
5. **Recovery**: Restore from clean backups
6. **Lessons Learned**: Update security measures

**Forensic Logging**
```sql
-- Enhanced audit logging
CREATE TABLE pggit.security_audit (
    id BIGSERIAL PRIMARY KEY,
    event_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    event_type TEXT,
    user_name TEXT,
    client_addr INET,
    command_tag TEXT,
    object_name TEXT,
    success BOOLEAN,
    error_message TEXT
);

-- Log all DDL operations
CREATE OR REPLACE FUNCTION pggit.audit_ddl()
RETURNS event_trigger AS $$
DECLARE
    audit_record RECORD;
BEGIN
    FOR audit_record IN SELECT * FROM pg_event_trigger_ddl_commands()
    LOOP
        INSERT INTO pggit.security_audit (
            event_type, user_name, client_addr, command_tag,
            object_name, success
        ) VALUES (
            'DDL', current_user, inet_client_addr(),
            audit_record.command_tag, audit_record.object_identity, true
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER audit_ddl_trigger
    ON ddl_command_end
    EXECUTE FUNCTION pggit.audit_ddl();
```

## Compliance Validation

**Automated Security Checks**
```bash
#!/bin/bash
# scripts/security/hardening-check.sh

echo "=== Security Hardening Checklist ==="

# Check SSL configuration
psql -c "SHOW ssl;" | grep -q "on" && echo "✅ SSL enabled" || echo "❌ SSL not enabled"

# Check public permissions
psql -c "SELECT count(*) FROM information_schema.table_privileges WHERE grantee = 'PUBLIC';" | grep -q "0" && echo "✅ No public permissions" || echo "❌ Public permissions found"

# Check RLS
psql -c "SELECT count(*) FROM pg_class c JOIN pg_policy p ON c.oid = p.polrelid WHERE c.relname = 'history';" | grep -q "0" && echo "⚠️  RLS not enabled on history" || echo "✅ RLS enabled on history"

# Check audit triggers
psql -c "SELECT count(*) FROM pg_event_trigger WHERE evtname LIKE 'pggit%';" | grep -q "0" && echo "❌ No pgGit event triggers" || echo "✅ pgGit event triggers active"

echo "=== Security check complete ==="
```

**Vulnerability Scanning Integration**
```yaml
# .github/workflows/vulnerability-scan.yml
name: Vulnerability Scan

on:
  schedule:
    - cron: '0 6 * * *'  # Daily at 6 AM
  push:
    branches: [main]

jobs:
  security-scan:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Run security hardening check
      run: ./scripts/security/hardening-check.sh

    - name: Scan for vulnerabilities
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: 'fs'
        scan-ref: '.'
        format: 'sarif'
        output: 'security-results.sarif'

    - name: Upload security results
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: 'security-results.sarif'
```

## Security Training

**Developer Security Awareness**
- SQL injection prevention
- Secure coding practices
- Incident reporting procedures
- Security testing methodologies

**Administrator Training**
- System hardening procedures
- Security monitoring interpretation
- Incident response protocols
- Compliance requirements

## Continuous Security

**Security as Code**
- Infrastructure as Code with security validations
- Automated security testing in CI/CD
- Security policy as code
- Compliance monitoring as code

**Threat Modeling**
- Regular threat model updates
- Security control effectiveness reviews
- Attack surface analysis
- Risk assessment updates