# Security Guide

This guide covers security considerations for pggit installations.

## ⚠️ IMPORTANT SECURITY NOTICE

**pggit v0.1.x is experimental software and should NOT be used for production systems requiring security compliance.**

### Current Security Status
- ✅ **Implemented**: Basic DDL audit trail and event triggers
- 🚧 **Planned**: User authentication, RBAC, compliance features, advanced security
- ❌ **Not Available**: Production-ready security features

**Most security features documented below are planned for future versions and do not currently exist in the codebase.**

## 🔒 Security Overview

pggit is designed with security in mind:
- **No external dependencies**: Everything runs within PostgreSQL
- **Minimal permissions**: Only tracks DDL changes
- **Local AI processing**: No data sent to external services
- **Standard PostgreSQL security**: Leverages existing database security

## 🛡️ Security Features

### 1. Built-in Authentication & RBAC 🚧 PLANNED
```sql
-- These functions do NOT exist in v0.1.x
-- Planned for future versions:
-- SELECT pggit.create_user('dev_user', 'dev@company.com', 'SecurePass123!', 'Developer');
-- SELECT pggit.grant_role(user_id, 'developer');
-- SELECT pggit.check_permission(user_id, 'branch.create');
```

**Current Status**: No user authentication or RBAC system exists. All operations run with current PostgreSQL user permissions.

### 2. Audit Trail ✅ IMPLEMENTED
```sql
-- View version history for a specific object
SELECT * FROM pggit.get_history('your_table_name');

-- View detailed change information from history table
SELECT
    object_name,
    change_type,
    change_timestamp,
    change_description
FROM pggit.history
ORDER BY change_timestamp DESC;
```

**Current Status**: Basic DDL change tracking is implemented. User attribution is limited to current PostgreSQL session user.

### 3. Data Classification 🚧 PLANNED
```sql
-- These features do NOT exist in v0.1.x
-- Planned for future versions:
-- SELECT * FROM pggit.auto_classify_data();
-- SELECT * FROM pggit.data_classifications WHERE contains_pii = true;
```

**Current Status**: No automatic data classification or PII/PHI detection exists. Manual classification must be handled by application layer.

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

### 2. Password Security 🚧 PLANNED
```sql
-- These features do NOT exist in v0.1.x
-- Password management must be handled by PostgreSQL or external systems
-- No built-in password validation or hashing exists
```

**Current Status**: No password security features. Authentication must be handled by PostgreSQL's built-in mechanisms.

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

## 🔍 Compliance Features 🚧 PLANNED

**All compliance features are planned for future versions and do not exist in v0.1.x.**

### 1. GDPR Compliance 🚧 PLANNED
- Right to be forgotten capabilities
- Data processing lawfulness verification
- Consent management
- Data breach detection

### 2. SOX Compliance 🚧 PLANNED
- Audit trail for financial data
- User accountability
- Immutable audit logs
- Segregation of duties

### 3. HIPAA Compliance 🚧 PLANNED
- PHI encryption requirements
- Access logging
- Data minimization
- Business associate compliance

**Current Status**: No compliance checking functions exist. Basic audit trail provides some change tracking but no compliance validation.

## 🚨 Security Monitoring 🧪 EXPERIMENTAL

### 1. Suspicious Activity Detection ✅ PARTIALLY IMPLEMENTED
```sql
-- Monitor for unusual patterns (limited by current user tracking)
SELECT
    change_type,
    COUNT(*) as change_count,
    MIN(change_timestamp) as first_change,
    MAX(change_timestamp) as last_change
FROM pggit.history
WHERE change_timestamp > NOW() - INTERVAL '1 hour'
GROUP BY change_type
HAVING COUNT(*) > 10;  -- More than 10 changes in an hour
```

### 2. Privileged Operations Audit ✅ PARTIALLY IMPLEMENTED
```sql
-- Track high-risk operations
SELECT
    object_name,
    change_type,
    change_timestamp
FROM pggit.history
WHERE change_type IN ('DROP', 'ALTER')
ORDER BY change_timestamp DESC;
```

### 3. Failed Authentication Monitoring 🚧 PLANNED
```sql
-- No authentication system exists in v0.1.x
-- Failed login monitoring requires external authentication
```

**Current Status**: Basic change monitoring is possible via the history table, but user-specific tracking is limited.

## 🔧 Security Configuration 🚧 MOSTLY PLANNED

### 1. Enable Security Features 🚧 PLANNED
```sql
-- No enterprise security modules exist in v0.1.x
-- Security configuration must be done manually via PostgreSQL settings

-- Emergency disable/enable functions DO exist:
SELECT pggit.emergency_disable('1 hour');  -- Disable tracking temporarily
SELECT pggit.emergency_enable();           -- Re-enable tracking
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

## 🚨 Incident Response 🧪 LIMITED

### 1. Security Breach Detection ✅ PARTIALLY IMPLEMENTED
```sql
-- Check for unauthorized schema changes (limited by user tracking)
SELECT
    object_name,
    change_type,
    change_description
FROM pggit.history
WHERE change_timestamp > NOW() - INTERVAL '24 hours'
ORDER BY change_timestamp DESC;
```

### 2. Emergency Procedures ✅ IMPLEMENTED
```sql
-- Disable all pggit triggers in emergency
SELECT pggit.emergency_disable('1 hour');

-- Re-enable after investigation
SELECT pggit.emergency_enable();
```

### 3. Recovery Procedures 🚧 PLANNED
```sql
-- No automated rollback or integrity verification exists
-- Manual recovery required via PostgreSQL backups
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

## 🔐 Advanced Security 🚧 PLANNED

**All advanced security features are planned for future versions.**

### 1. Row-Level Security (RLS) 🚧 PLANNED
- No RLS policies exist on pggit tables
- Manual permission management required

### 2. Encrypted Columns 🚧 PLANNED
- No built-in column encryption
- Use PostgreSQL's pgcrypto extension manually

### 3. Security Hardening 🧪 MANUAL
```sql
-- Manual security hardening (not automated)
REVOKE ALL ON DATABASE postgres FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Create roles manually
CREATE ROLE pggit_admin;
GRANT ALL ON SCHEMA pggit TO pggit_admin;
```

## 📞 Security Support

**IMPORTANT**: pggit v0.1.x has not undergone security audit and should not be used for security-critical applications.

Security concerns or questions?

- **Security Issues**: Create GitHub issue (see SECURITY.md)
- **Vulnerability Reports**: Follow responsible disclosure process
- **Compliance Questions**: Not applicable for v0.1.x
- **Community**: GitHub Issues and Discussions

---

## 🛡️ Remember

- **Defense in depth**: Layer multiple security controls
- **Least privilege**: Grant minimum required permissions
- **Regular monitoring**: Audit logs and access patterns
- **Stay updated**: Apply security patches promptly
- **Test regularly**: Verify security controls work as expected

---

*Security is a shared responsibility. pggit provides the tools - you provide the operational security.*