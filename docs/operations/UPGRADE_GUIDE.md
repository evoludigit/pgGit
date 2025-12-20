# Upgrade Guide

This guide covers upgrading pgGit installations between versions, including migration procedures and compatibility notes.

## Overview

pgGit follows [Semantic Versioning](https://semver.org/) (MAJOR.MINOR.PATCH):

- **MAJOR**: Breaking changes requiring migration
- **MINOR**: New features, backward compatible
- **PATCH**: Bug fixes, security updates

## Upgrade Paths

### Current Version: 0.2.0

#### From 0.1.0 → 0.2.0

**Migration Required**: Yes (schema changes)

**Upgrade Steps**:
1. **Backup your data** (see BACKUP_RESTORE.md)
2. **Stop application connections** to pgGit databases
3. **Run migration script**:
   ```sql
   -- In each pgGit-enabled database:
   \i migrations/pggit--0.1.0--0.2.0.sql
   ```
4. **Verify migration**:
   ```sql
   SELECT pggit.get_version();
   -- Should return: 0.2.0
   ```
5. **Restart applications**

**Changes in 0.2.0**:
- Enhanced monitoring capabilities
- Improved AI integration
- Performance optimizations
- New enterprise features

### Future Version Upgrades

#### Planned: 0.2.0 → 0.3.0 (Minor Release)

**Migration Required**: No (backward compatible)

**New Features**:
- Enhanced cold storage
- Improved performance monitoring
- Additional AI capabilities

#### Planned: 0.3.0 → 1.0.0 (Major Release)

**Migration Required**: Yes

**Breaking Changes**:
- API changes for enterprise features
- Schema restructuring for performance

## Automated Upgrades

### Using Package Managers

#### Debian/Ubuntu
```bash
# Update package list
sudo apt update

# Upgrade pgGit
sudo apt install --only-upgrade pggit

# Restart PostgreSQL
sudo systemctl restart postgresql
```

#### RHEL/Rocky Linux
```bash
# Update package
sudo dnf update pggit

# Or with yum
sudo yum update pggit

# Restart PostgreSQL
sudo systemctl restart postgresql
```

### Using Migration Scripts

For manual upgrades or complex environments:

```bash
# Download migration scripts
git clone https://github.com/evoludigit/pgGit.git
cd pgGit

# Run appropriate migration
psql -d your_database -f migrations/pggit--CURRENT--TARGET.sql
```

## Pre-Upgrade Checklist

- [ ] **Backup verified**: Recent backup available and tested
- [ ] **Downtime scheduled**: Application maintenance window planned
- [ ] **Dependencies checked**: Compatible PostgreSQL version (15+)
- [ ] **Testing completed**: Upgrade tested in staging environment
- [ ] **Rollback plan**: Downgrade procedure documented
- [ ] **Monitoring ready**: Performance monitoring configured

## Upgrade Procedure

### Step 1: Preparation
```bash
# Create backup
pg_dump -Fc your_database > backup_pre_upgrade.dump

# Stop application services
sudo systemctl stop your-app

# Note current version
psql -d your_database -c "SELECT pggit.version();"
```

### Step 2: Upgrade pgGit
```bash
# Method 1: Package manager
sudo apt update && sudo apt install pggit

# Method 2: Manual install
cd /path/to/pggit
make clean
make install
```

### Step 3: Run Migrations
```sql
-- Connect to your database
psql your_database

-- Run migration (adjust versions as needed)
\i migrations/pggit--0.1.0--0.2.0.sql

-- Verify upgrade
SELECT pggit.version();
```

### Step 4: Verification
```sql
-- Test core functionality
SELECT pggit.get_history();
SELECT pggit.generate_migration();

-- Test enterprise features (if applicable)
SELECT pggit.analyze_enterprise_impact();
```

### Step 5: Restart Services
```bash
# Start application
sudo systemctl start your-app

# Monitor for errors
tail -f /var/log/postgresql/postgresql-*.log
```

## Rollback Procedure

If upgrade fails:

### Immediate Rollback
```bash
# Stop services
sudo systemctl stop your-app

# Restore from backup
pg_restore -d your_database backup_pre_upgrade.dump

# Downgrade pgGit if needed
# See migration scripts for downgrade path
psql -d your_database -f migrations/pggit--0.2.0--0.1.0.sql

# Restart services
sudo systemctl start your-app
```

### Partial Rollback (Schema Only)
```sql
-- If only schema changes need rollback
\i migrations/pggit--TARGET--CURRENT.sql

-- Verify rollback
SELECT pggit.version();
```

## Troubleshooting

### Common Issues

**"function pggit.get_version() does not exist"**
- Migration incomplete, re-run migration script
- Check PostgreSQL search_path

**"permission denied for schema pggit"**
- Ensure running as superuser or schema owner
- Check GRANT permissions

**"extension pggit does not exist"**
- Package installation failed, reinstall packages
- Check PostgreSQL extension directory

### Performance Issues Post-Upgrade

- Run `ANALYZE` on pgGit tables
- Check monitoring metrics
- Review PostgreSQL logs for slow queries

### Compatibility Matrix

| pgGit Version | PostgreSQL 15 | PostgreSQL 16 | PostgreSQL 17 |
|---------------|----------------|----------------|----------------|
| 0.1.0        | ✅             | ✅             | ✅             |
| 0.2.0        | ✅             | ✅             | ✅             |
| 1.0.0 (planned)| ✅           | ✅             | ✅             |

## Testing Upgrades

### Automated Testing
```bash
# Run upgrade tests
./tests/upgrade/test-upgrade-path.sh

# Full test suite
make test-all
```

### Manual Testing
- Create test schema changes
- Verify history tracking
- Test migration generation
- Check AI analysis (if enabled)

## Support

- **Documentation**: See API Reference and guides
- **Issues**: GitHub Issues for bugs
- **Security**: security@pggit.dev for security issues
- **Community**: GitHub Discussions for questions