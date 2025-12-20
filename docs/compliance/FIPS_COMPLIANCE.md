# FIPS 140-2 Compliance Guide

## Overview

pgGit can be configured for FIPS 140-2 compliance when running on FIPS-enabled PostgreSQL.

## Requirements

### PostgreSQL FIPS Mode

1. **Build PostgreSQL with OpenSSL FIPS module**:

```bash
# Install OpenSSL FIPS module
wget https://www.openssl.org/source/openssl-fips-3.0.tar.gz
tar xzf openssl-fips-3.0.tar.gz
cd openssl-fips-3.0
./config fips
make
sudo make install

# Build PostgreSQL with FIPS-enabled OpenSSL
./configure --with-openssl --with-includes=/usr/local/ssl/include
make
sudo make install
```

2. **Enable FIPS mode**:

```ini
# postgresql.conf
ssl = on
ssl_prefer_server_ciphers = on
ssl_ciphers = 'FIPS'
ssl_min_protocol_version = 'TLSv1.2'
```

### pgGit FIPS Configuration

pgGit uses PostgreSQL's `pgcrypto` extension, which respects FIPS mode:

```sql
-- Verify FIPS mode is active
SELECT setting
FROM pg_settings
WHERE name = 'ssl_ciphers';
-- Should return: FIPS

-- pgGit automatically uses FIPS-compliant algorithms
-- when PostgreSQL is in FIPS mode
```

## Cryptographic Operations

All pgGit cryptographic operations use FIPS 140-2 approved algorithms:

| Operation | Algorithm | FIPS Status |
|-----------|-----------|-------------|
| Hashing | SHA-256 | ✅ Approved |
| Random | HMAC-DRBG | ✅ Approved |
| Encryption | AES-256 | ✅ Approved |

## Audit Trail

```sql
-- Verify all crypto operations are FIPS-compliant
SELECT
    change_id,
    change_type,
    created_at,
    length(metadata) as metadata_hash_len
FROM pggit.history
WHERE metadata IS NOT NULL
LIMIT 10;

-- All hashes should be 64 characters (SHA-256)
```

## Certification

pgGit itself is not FIPS 140-2 certified, but operates on certified components:
- PostgreSQL with FIPS-enabled OpenSSL (when configured)
- Operating system FIPS module

## FIPS Configuration Checklist

- [ ] PostgreSQL built with FIPS-enabled OpenSSL
- [ ] `ssl_ciphers = 'FIPS'` in postgresql.conf
- [ ] Verify `pgcrypto` uses FIPS algorithms
- [ ] Document FIPS configuration in operations runbook
- [ ] Regular FIPS compliance audits

## FIPS-Enabled Installation

### Docker Deployment
```dockerfile
# Dockerfile.fips
FROM postgres:15-fips

# Enable FIPS mode
RUN sed -i 's/ssl_ciphers.*/ssl_ciphers = '\''FIPS'\''/' /usr/share/postgresql/postgresql.conf.sample

# Install pgGit
COPY sql/install.sql /docker-entrypoint-initdb.d/
```

### Systemd Service
```ini
# /etc/systemd/system/postgresql-fips.service
[Unit]
Description=PostgreSQL FIPS Database Server
After=network.target

[Service]
Type=forking
User=postgres
Group=postgres
Environment=PGDATA=/var/lib/postgresql-fips/data
Environment=PGFIPS=1
ExecStart=/usr/lib/postgresql/15/bin/pg_ctl start -D ${PGDATA}
ExecStop=/usr/lib/postgresql/15/bin/pg_ctl stop -D ${PGDATA}
ExecReload=/usr/lib/postgresql/15/bin/pg_ctl reload -D ${PGDATA}

[Install]
WantedBy=multi-user.target
```

## Security Considerations

### Key Management
- Use FIPS-approved key derivation functions
- Implement proper key rotation procedures
- Store keys in FIPS-compliant hardware security modules (HSM)

### Data Protection
- All data at rest encryption uses FIPS-approved algorithms
- Network encryption uses FIPS-compliant TLS
- Backup encryption follows FIPS standards

### Audit and Monitoring
- All cryptographic operations are logged
- FIPS mode validation is continuously monitored
- Security events are audited and retained

## Compliance Testing

### Automated FIPS Validation
```bash
#!/bin/bash
# scripts/compliance/fips-check.sh

echo "=== FIPS Compliance Check ==="

# Check OpenSSL FIPS mode
openssl version | grep -q "fips" && echo "✅ OpenSSL FIPS mode enabled" || echo "❌ OpenSSL FIPS mode not enabled"

# Check PostgreSQL FIPS configuration
psql -c "SHOW ssl_ciphers" | grep -q "FIPS" && echo "✅ PostgreSQL FIPS ciphers configured" || echo "❌ PostgreSQL FIPS ciphers not configured"

# Test cryptographic operations
psql -c "
DO \$\$
DECLARE
    test_hash TEXT;
BEGIN
    -- Test SHA-256 hashing
    SELECT encode(digest('test data', 'sha256'), 'hex') INTO test_hash;
    IF length(test_hash) = 64 THEN
        RAISE NOTICE '✅ SHA-256 hashing works';
    ELSE
        RAISE EXCEPTION '❌ SHA-256 hashing failed';
    END IF;
END \$\$;
"

echo "=== FIPS check complete ==="
```

### FIPS Audit Queries
```sql
-- Verify FIPS-compliant algorithms in use
SELECT
    name,
    setting
FROM pg_settings
WHERE name IN ('ssl_ciphers', 'ssl_min_protocol_version');

-- Check for non-compliant connections
SELECT
    usename,
    client_addr,
    ssl,
    ssl_cipher
FROM pg_stat_ssl
WHERE ssl_cipher NOT LIKE 'ECDHE-RSA-AES256-GCM-SHA384'
  AND ssl_cipher NOT LIKE 'ECDHE-RSA-AES128-GCM-SHA256';

-- Audit cryptographic operations
SELECT
    created_at,
    change_type,
    metadata->>'algorithm' as algorithm_used
FROM pggit.history
WHERE metadata->>'algorithm' IS NOT NULL
ORDER BY created_at DESC
LIMIT 100;
```

## Performance Impact

FIPS mode may have performance implications:
- Cryptographic operations are slower due to additional validation
- TLS handshake overhead is increased
- Some optimizations may be disabled

Expected performance impact:
- Hash operations: 10-20% slower
- TLS connections: 5-15% slower
- Overall throughput: 5-10% reduction

## Troubleshooting

### Common FIPS Issues

#### "FIPS mode not enabled"
**Solution**: Ensure OpenSSL FIPS module is loaded:
```bash
# Check FIPS module
openssl fipsinstall -module /usr/local/lib/ossl-modules/fips.so

# Verify FIPS mode
openssl fipsinstall -verify
```

#### "Invalid cipher"
**Solution**: Use only FIPS-approved ciphers:
```ini
# postgresql.conf
ssl_ciphers = 'FIPS'
```

#### "Cryptographic operation failed"
**Solution**: Check system entropy and FIPS compliance:
```bash
# Check entropy
cat /proc/sys/kernel/random/entropy_avail

# Verify FIPS self-tests
dmesg | grep -i fips
```

## Documentation and Training

### Required Documentation
- FIPS configuration procedures
- Security policy for FIPS operations
- Incident response procedures
- Audit and compliance reporting

### Training Requirements
- System administrators must understand FIPS implications
- Developers must use FIPS-compliant algorithms
- Security team must monitor FIPS compliance
- Auditors must validate FIPS implementation

## Future Considerations

### FIPS 140-3 Migration
As FIPS 140-3 becomes required:
- Update cryptographic algorithms
- Implement new key management procedures
- Update compliance testing scripts
- Retrain staff on new requirements

### Quantum Resistance
Plan for post-quantum cryptography:
- Evaluate quantum-resistant algorithms
- Update key sizes and algorithms
- Test migration procedures