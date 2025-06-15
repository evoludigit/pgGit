# Security Guide

This guide covers security considerations for pggit installations.

## 🔒 Security Overview

pggit is designed with security in mind:
- **No external dependencies**: Everything runs within PostgreSQL
- **Minimal permissions**: Only tracks DDL changes
- **Local AI processing**: No data sent to external services
- **Standard PostgreSQL security**: Leverages existing database security

## 🛡️ Security Features

### 1. Built-in Authentication & RBAC
```sql
-- Create users with specific roles
SELECT pggit.create_user('dev_user', 'dev@company.com', 'SecurePass123!', 'Developer');

-- Grant specific permissions
SELECT pggit.grant_role(
    (SELECT user_id FROM pggit.users WHERE username = 'dev_user'),
    'developer'
);

-- Check permissions before operations
SELECT pggit.check_permission(user_id, 'branch.create');
```

### 2. Audit Trail
```sql
-- View all changes with user attribution
SELECT 
    h.object_name,
    h.change_type,
    h.changed_by,
    h.change_timestamp,
    h.change_description
FROM pggit.history h
ORDER BY h.change_timestamp DESC;
```

### 3. Data Classification
```sql
-- Automatic PII/PHI detection
SELECT * FROM pggit.auto_classify_data();

-- Check for sensitive data exposure
SELECT 
    table_name,
    column_name,
    classification,
    contains_pii,
    contains_phi
FROM pggit.data_classifications
WHERE contains_pii = true OR contains_phi = true;
```

## 🎯 Security Best Practices

### 1. Access Control
```sql
-- Principle of least privilege
REVOKE ALL ON SCHEMA pggit FROM PUBLIC;
GRANT USAGE ON SCHEMA pggit TO pggit_users;
GRANT SELECT ON pggit.objects TO pggit_readonly;
GRANT INSERT, UPDATE ON pggit.history TO pggit_developers;

-- Restrict sensitive functions
REVOKE EXECUTE ON FUNCTION pggit.generate_migration() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pggit.generate_migration() TO pggit_admins;
```

### 2. Password Security
```sql
-- Strong password requirements are enforced
-- Minimum 8 characters, uppercase, lowercase, number, special character
SELECT pggit.create_user('user', 'email@domain.com', 'WeakPass', 'User'); -- Will fail

-- Password hashing with bcrypt
SELECT password_hash FROM pggit.users WHERE username = 'test_user';
-- Returns: $2b$12$... (bcrypt hash)
```

### 3. Connection Security
```postgresql
# postgresql.conf security settings
ssl = on
ssl_cert_file = '/path/to/server.crt'
ssl_key_file = '/path/to/server.key'

# Require SSL for pggit users
# pg_hba.conf
hostssl all pggit_users 0.0.0.0/0 md5
```

## 🔍 Compliance Features

### 1. GDPR Compliance
```sql
-- Check GDPR compliance status
SELECT * FROM pggit.check_gdpr_compliance();

-- Results show:
-- - Right to be forgotten capabilities
-- - Data processing lawfulness
-- - Consent management
-- - Data breach detection
```

### 2. SOX Compliance
```sql
-- Audit trail for financial data
SELECT * FROM pggit.check_sox_compliance();

-- Ensures:
-- - Complete change tracking
-- - User accountability
-- - Immutable audit logs
-- - Segregation of duties
```

### 3. HIPAA Compliance
```sql
-- Healthcare data protection
SELECT * FROM pggit.check_hipaa_compliance();

-- Validates:
-- - PHI encryption requirements
-- - Access logging
-- - Data minimization
-- - Business associate compliance
```

## 🚨 Security Monitoring

### 1. Suspicious Activity Detection
```sql
-- Monitor for unusual patterns
SELECT 
    changed_by,
    COUNT(*) as change_count,
    MIN(change_timestamp) as first_change,
    MAX(change_timestamp) as last_change
FROM pggit.history 
WHERE change_timestamp > NOW() - INTERVAL '1 hour'
GROUP BY changed_by
HAVING COUNT(*) > 10;  -- More than 10 changes in an hour
```

### 2. Privileged Operations Audit
```sql
-- Track high-risk operations
SELECT 
    object_name,
    change_type,
    changed_by,
    change_timestamp
FROM pggit.history 
WHERE change_type IN ('DROP', 'ALTER') 
  AND object_name LIKE '%_sensitive_%'
ORDER BY change_timestamp DESC;
```

### 3. Failed Authentication Monitoring
```sql
-- Monitor failed login attempts (if auth module loaded)
SELECT 
    username,
    COUNT(*) as failed_attempts,
    MAX(attempt_timestamp) as last_attempt
FROM pggit.auth_log 
WHERE success = false 
  AND attempt_timestamp > NOW() - INTERVAL '24 hours'
GROUP BY username
HAVING COUNT(*) > 5;
```

## 🔧 Security Configuration

### 1. Enable Security Features
```sql
-- Load enterprise security modules
\i sql/051_enterprise_auth_rbac.sql
\i sql/052_compliance_reporting.sql

-- Configure security settings
SELECT pggit.configure_security(
    'password_policy' => 'strict',
    'session_timeout_minutes' => 60,
    'max_failed_attempts' => 5,
    'audit_level' => 'full'
);
```

### 2. Network Security
```bash
# Firewall configuration
sudo ufw allow from 10.0.0.0/8 to any port 5432
sudo ufw deny from any to any port 5432

# VPN-only access
# Configure PostgreSQL to only accept connections from VPN subnet
```

### 3. Encryption at Rest
```postgresql
# Enable data encryption (PostgreSQL 15+)
ALTER SYSTEM SET cluster_encryption = on;
SELECT pg_reload_conf();

# Or use filesystem encryption
# LUKS, BitLocker, or cloud provider encryption
```

## 🚨 Incident Response

### 1. Security Breach Detection
```sql
-- Check for unauthorized schema changes
SELECT 
    object_name,
    change_type,
    changed_by,
    change_description
FROM pggit.history 
WHERE changed_by NOT IN (SELECT username FROM pggit.authorized_users)
  AND change_timestamp > NOW() - INTERVAL '24 hours';
```

### 2. Emergency Procedures
```sql
-- Disable all pggit triggers in emergency
SELECT pggit.disable_tracking('emergency');

-- Re-enable after investigation
SELECT pggit.enable_tracking();

-- Generate incident report
SELECT pggit.generate_security_report(
    'incident_start' => '2024-06-15 10:00:00',
    'incident_end' => '2024-06-15 12:00:00'
);
```

### 3. Recovery Procedures
```sql
-- Rollback to known good state
SELECT pggit.rollback_to_timestamp('2024-06-15 09:30:00');

-- Verify system integrity
SELECT pggit.verify_database_integrity();
```

## 📋 Security Checklist

### Installation Security
- [ ] Run pggit with minimal required permissions
- [ ] Enable SSL/TLS for all connections
- [ ] Configure strong authentication (certificates, LDAP, etc.)
- [ ] Set up network firewalls and access controls
- [ ] Enable audit logging in PostgreSQL

### Operational Security
- [ ] Regular security updates for PostgreSQL
- [ ] Monitor pggit audit logs daily
- [ ] Review user permissions quarterly
- [ ] Test backup and recovery procedures
- [ ] Validate compliance requirements

### Incident Preparedness
- [ ] Document emergency procedures
- [ ] Test rollback capabilities
- [ ] Establish communication protocols
- [ ] Define escalation procedures
- [ ] Regular security training for team

## 🔐 Advanced Security

### 1. Row-Level Security (RLS)
```sql
-- Enable RLS on pggit tables
ALTER TABLE pggit.history ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only see their own changes
CREATE POLICY user_history_policy ON pggit.history
FOR SELECT TO pggit_users
USING (changed_by = current_user);
```

### 2. Encrypted Columns
```sql
-- Encrypt sensitive migration data
ALTER TABLE pggit.history 
ADD COLUMN encrypted_details BYTEA;

-- Store encrypted change descriptions
UPDATE pggit.history 
SET encrypted_details = pgp_sym_encrypt(change_description, 'secret_key')
WHERE contains_sensitive_data = true;
```

### 3. Security Hardening
```sql
-- Remove default permissions
REVOKE ALL ON DATABASE postgres FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Create security-focused roles
CREATE ROLE pggit_security_admin;
GRANT ALL ON SCHEMA pggit TO pggit_security_admin;
```

## 📞 Security Support

Security concerns or questions?

- **Security Issues**: security@pggit.dev
- **Vulnerability Reports**: Use responsible disclosure
- **Compliance Questions**: compliance@pggit.dev
- **Community**: GitHub Security Advisories

---

## 🛡️ Remember

- **Defense in depth**: Layer multiple security controls
- **Least privilege**: Grant minimum required permissions
- **Regular monitoring**: Audit logs and access patterns
- **Stay updated**: Apply security patches promptly
- **Test regularly**: Verify security controls work as expected

---

*Security is a shared responsibility. pggit provides the tools - you provide the operational security.*