# Installing pgGit

**Guide for installing pgGit on development and staging databases**

> **Recommended Usage**: pgGit is primarily designed for development and staging databases. For most production environments, deploy changes via migration tools. However, if your compliance requirements demand automatic DDL audit trails (ISO 27001, SOC 2, DORA, GDPR, NIS2, HIPAA, PCI-DSS, SOX), pgGit can provide value in production. See [Production Considerations](guides/PRODUCTION_CONSIDERATIONS.md).

---

## Overview

This guide covers installing pgGit on **development and staging databases**. pgGit is deployed as a set of SQL schemas and functions that run within PostgreSQL.

**Key Concepts**:
- pgGit installs into PostgreSQL as `pggit_v0` and `pggit_audit` schemas
- No separate service or daemon required
- All operations are SQL functions you call from your application
- Installation is idempotent (safe to re-run)

---

## Pre-Installation Requirements

### PostgreSQL Compatibility

**Minimum Requirements**:
- PostgreSQL 12 or later (PostgreSQL 17 recommended for full compression features)
- Superuser or role with CREATE SCHEMA privilege
- At least 100MB free space for pgGit schemas

**Tested Versions**:
- PostgreSQL 12, 13, 14, 15, 16, 17
- Docker PostgreSQL images
- Local PostgreSQL installations

### System Requirements

**Development/Testing**:
- 1 CPU core minimum
- 512MB RAM minimum
- 1GB disk space for schemas

---

## Development Installation

### Method 1: Direct Installation (Recommended)

```bash
# 1. Clone pgGit
git clone https://github.com/evoludigit/pgGit.git
cd pgGit

# 2. Create your development database (if needed)
createdb myapp_dev

# 3. Install pgGit extension
psql myapp_dev -c "CREATE EXTENSION pggit CASCADE;"

# 4. Initialize pgGit
psql myapp_dev -c "SELECT pggit.init();"

# 5. Verify installation
psql myapp_dev -c "SELECT pggit.version();"
```

### Method 2: From Schema Copy

If you're setting up a development database from a production schema:

```bash
# 1. Copy schema from staging (no data)
pg_dump myapp_staging --schema-only | psql myapp_dev

# 2. Install pgGit on development copy
psql myapp_dev -c "CREATE EXTENSION pggit CASCADE;"
psql myapp_dev -c "SELECT pggit.init();"

# 3. Verify
psql myapp_dev -c "SELECT pggit.version();"
```

### Method 3: Docker Development Environment

**Using Docker Compose**:

```yaml
version: '3.8'
services:
  postgres-dev:
    image: postgres:17-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: devpassword
      POSTGRES_DB: myapp_dev
    ports:
      - "5432:5432"
    volumes:
      - ./sql:/docker-entrypoint-initdb.d
      - postgres_dev_data:/var/lib/postgresql/data

volumes:
  postgres_dev_data:
```

```bash
# Start container
docker-compose up -d

# Install pgGit
docker-compose exec postgres-dev psql -U postgres -d myapp_dev -c "CREATE EXTENSION pggit CASCADE;"
docker-compose exec postgres-dev psql -U postgres -d myapp_dev -c "SELECT pggit.init();"
```

**Using Podman**:

```bash
# Start PostgreSQL container
podman run --name pggit-dev \
  -e POSTGRES_PASSWORD=devpassword \
  -e POSTGRES_DB=myapp_dev \
  -p 5432:5432 -d postgres:17

# Install pgGit
podman exec pggit-dev psql -U postgres -d myapp_dev -c "CREATE EXTENSION pggit CASCADE;"
```

---

## Staging Installation

Staging databases can optionally have pgGit installed to test merge workflows before generating migrations for production.

```bash
# Set up staging database
createdb myapp_staging

# Restore from production backup (schema only recommended)
pg_dump myapp_prod --schema-only | psql myapp_staging

# Install pgGit
psql myapp_staging << 'SQL'
CREATE EXTENSION pggit CASCADE;
SELECT pggit.init();
SQL
```

---

## CI/CD Test Databases

For automated testing, pgGit can be installed on ephemeral test databases:

```bash
#!/bin/bash
# ci-setup.sh

# Create test database
createdb "test_${CI_JOB_ID}"

# Install pgGit
psql "test_${CI_JOB_ID}" -c "CREATE EXTENSION pggit CASCADE;"
psql "test_${CI_JOB_ID}" -c "SELECT pggit.init();"

# Run tests...

# Cleanup
dropdb "test_${CI_JOB_ID}"
```

---

## Production Installation

### Standard Production (No Compliance Requirements)

For most production environments, migration tools are sufficient:

- **[Confiture](https://github.com/fraiseql/confiture)** (with pgGit integration)
- **[Flyway](https://flywaydb.org/)**
- **[Liquibase](https://www.liquibase.org/)**
- **[Alembic](https://alembic.sqlalchemy.org/)**

Generate migrations from your pgGit-tracked development database, then apply them to production:

```bash
# Development: Use pgGit for branching/merging
psql myapp_dev -c "SELECT pggit.diff('main', 'feature/my-feature');"

# Generate migration for production
confiture generate from-branch feature/my-feature

# Production: Apply via migration tool
confiture migrate up --env production
```

### Production with Compliance Requirements

If your organization requires automatic DDL audit trails (ISO 27001, SOC 2, DORA, GDPR, NIS2, HIPAA, PCI-DSS, SOX), pgGit can be deployed to production:

```bash
# Install pgGit on production for audit capabilities
psql myapp_prod << 'SQL'
CREATE EXTENSION pggit CASCADE;
SELECT pggit.init();

-- Configure for audit-only mode (disable branching features)
SELECT pggit.configure_tracking(
    track_schemas => ARRAY['public', 'api'],
    ignore_schemas => ARRAY['pg_catalog'],
    audit_mode => true
);

-- Set retention policy for compliance
SELECT pggit.set_audit_retention_days(365);  -- Adjust for your compliance window
SQL
```

**Benefits in production**:
- Automatic capture of all DDL changes (including ad-hoc/emergency fixes)
- Immutable audit trail with timestamps and user attribution
- Detection of unauthorized schema changes
- Forensic capabilities for incident response

See [Production Considerations](guides/PRODUCTION_CONSIDERATIONS.md) for detailed guidance.

---

## Post-Installation Configuration

### 1. Verify Installation

```sql
-- Check version
SELECT pggit.version();

-- Check status
SELECT * FROM pggit.status();

-- Verify main branch exists
SELECT * FROM pggit.list_branches();
```

### 2. Configure Tracking (Optional)

```sql
-- Configure which schemas to track
SELECT pggit.configure_tracking(
    track_schemas => ARRAY['public', 'api'],
    ignore_schemas => ARRAY['pg_catalog', 'information_schema']
);
```

### 3. Create Your First Branch

```sql
-- Create a feature branch
SELECT pggit.create_branch('feature/my-first-feature');
SELECT pggit.checkout('feature/my-first-feature');

-- Make some changes
CREATE TABLE test_table (id SERIAL PRIMARY KEY);

-- Check status
SELECT * FROM pggit.status();
```

---

## Health Checks

After installation, verify pgGit is working:

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
SELECT pggit.version();
-- Expected: pgGit v0.1.2 (or later)

-- 4. Test branch operations
SELECT pggit.get_current_branch();
-- Expected: 'main'
```

---

## Troubleshooting

### Installation Fails: "Permission Denied"

```sql
-- Verify you have superuser or appropriate role
SELECT current_user;
SELECT usesuper FROM pg_user WHERE usename = current_user;

-- If not superuser, grant required privileges
ALTER USER your_user CREATEDB CREATEROLE;
```

### Installation Fails: "Extension Not Found"

```bash
# Make sure pgGit is installed in PostgreSQL's extension directory
sudo make install

# Or check if extension files exist
ls $(pg_config --sharedir)/extension/pggit*
```

### Installation Fails: "Schema Already Exists"

```bash
# Uninstall first, then reinstall
psql myapp_dev -c "DROP EXTENSION pggit CASCADE;"
psql myapp_dev -c "CREATE EXTENSION pggit CASCADE;"
```

---

## Uninstalling pgGit

To remove pgGit from a development database:

```sql
-- Remove extension and all pgGit schemas
DROP EXTENSION pggit CASCADE;

-- Or manually remove schemas
DROP SCHEMA pggit_v0 CASCADE;
DROP SCHEMA pggit_audit CASCADE;
```

---

## Next Steps

- [Development Workflow Guide](guides/DEVELOPMENT_WORKFLOW.md) - How to use pgGit effectively
- [Getting Started](Getting_Started.md) - Quick tutorial
- [User Guide](USER_GUIDE.md) - Full feature documentation
- [API Reference](API_Reference.md) - All functions

---

**Last Updated**: January 2026
**Version**: pgGit v0.1.2
