# Phase 3: Production Polish

**Quality Gain**: 8.5/10 → 9.0/10
**Prerequisites**: Phases 1-2 completed (all acceptance criteria met)

---

## Pre-Phase Checklist

Before starting Phase 3:

**Prerequisites**:
- [ ] Phase 2 PR merged to main
- [ ] All Phase 2 acceptance criteria verified
- [ ] Linting passing (`make lint`)
- [ ] API documentation 100% complete
- [ ] Security audit findings addressed
- [ ] Clean git status

**Setup**:
```bash
# Sync with main
git checkout main
git pull origin main

# Create phase branch
git checkout -b phase-3-production-polish

# Verify Phase 2 completion
make lint            # Should pass
make test-pgtap      # Should pass
test -f CODE_OF_CONDUCT.md && echo "✅ Phase 2 complete"

# Install packaging tools
sudo apt-get install debhelper rpm-build  # Debian/Ubuntu
# OR
sudo dnf install rpm-build  # RHEL/Rocky
```

**Focus**:
- Production readiness, not new features
- Operational excellence
- Safe deployment and upgrade paths

---

## Objective

Make pgGit production-ready: package distribution, upgrade paths, monitoring, backup procedures, and release automation. After this phase, pgGit can be safely deployed in production environments.

---

## Context

Phases 1-2 established quality. Phase 3 adds production infrastructure:
- Version upgrade migrations
- OS package distribution (.deb, .rpm)
- Monitoring and observability
- Backup/restore procedures
- Automated release pipeline
- Multi-architecture support
- Disaster recovery

---

## Files to Create

### Infrastructure
- `migrations/0.1.0--0.2.0.sql` - Upgrade script template
- `packaging/debian/` - Debian package files
- `packaging/rpm/` - RPM package files
- `.github/workflows/release.yml` - Release automation
- `.github/workflows/packages.yml` - Package building

### Operations
- `sql/pggit_monitoring.sql` - Metrics and observability
- `docs/operations/BACKUP_RESTORE.md`
- `docs/operations/DISASTER_RECOVERY.md`
- `docs/operations/UPGRADE_GUIDE.md`
- `docs/operations/MONITORING.md`

### Testing
- `.github/workflows/performance.yml` - Performance regression
- `tests/load/` - Load testing scenarios
- `tests/upgrade/` - Upgrade path testing

---

## Step Dependencies

Steps can be executed in this order:

```
Phase 3 Flow:
┌─────────────────────────────────────────────────┐
│ Step 1: Upgrade Migrations [HIGH]              │
└──────────────┬──────────────────────────────────┘
               ↓
┌──────────────┴──────────────────────────────────┐
│ Step 2: Debian Packages [HIGH]                 │
│ Step 3: RPM Packages [HIGH]  (parallel with 2) │
└──────────────┬──────────────────────────────────┘
               ↓
┌─────────────────────────────────────────────────┐
│ Step 4: Monitoring [MEDIUM]                    │
└──────────────┬──────────────────────────────────┘
               ↓
┌──────────────┴──────────────────────────────────┐
│ Step 5: Backup/Restore [MEDIUM] (parallel)     │
│ Step 6: Release Automation [HIGH] (parallel)   │
└─────────────────────────────────────────────────┘
```

**Parallel Execution Possible**:
- Steps 2 & 3 (independent packaging systems)
- Steps 5 & 6 (independent operational concerns)

**Sequential Required**:
- Step 2-3 depend on Step 1 (packages need migration scripts)
- Step 4 depends on Steps 2-3 (monitoring needs deployed system)
- Steps 5-6 depend on Step 4 (ops docs need monitoring in place)

---

## Implementation Steps

### Step 1: Version Upgrade Migrations [EFFORT: HIGH]

**Goal**: Safe upgrades from 0.1.x to 0.2.x and beyond.

```sql
-- File: migrations/pggit--0.1.0--0.2.0.sql
-- Upgrade script from 0.1.0 to 0.2.0

BEGIN;

-- Record upgrade start
CREATE TABLE IF NOT EXISTS pggit.upgrade_log (
    upgrade_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_version TEXT NOT NULL,
    to_version TEXT NOT NULL,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    status TEXT CHECK (status IN ('in_progress', 'completed', 'failed', 'rolled_back')),
    error_message TEXT
);

INSERT INTO pggit.upgrade_log (from_version, to_version, status)
VALUES ('0.1.0', '0.2.0', 'in_progress')
RETURNING upgrade_id AS current_upgrade_id \gset

-- Backup existing data
CREATE SCHEMA IF NOT EXISTS pggit_backup_:current_upgrade_id;
CREATE TABLE pggit_backup_:current_upgrade_id.objects AS SELECT * FROM pggit.objects;
CREATE TABLE pggit_backup_:current_upgrade_id.history AS SELECT * FROM pggit.history;

-- Schema changes
DO $upgrade$
DECLARE
    v_error TEXT;
BEGIN
    -- Add new columns
    ALTER TABLE pggit.objects ADD COLUMN IF NOT EXISTS tags JSONB DEFAULT '[]'::jsonb;
    ALTER TABLE pggit.history ADD COLUMN IF NOT EXISTS performance_impact TEXT;

    -- Create new tables
    CREATE TABLE IF NOT EXISTS pggit.performance_metrics (
        metric_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        operation_type TEXT NOT NULL,
        execution_time_ms NUMERIC,
        object_count INTEGER,
        recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    -- Add new indexes
    CREATE INDEX IF NOT EXISTS idx_history_performance
        ON pggit.history(change_type, created_at);

    -- Update existing data
    UPDATE pggit.objects SET tags = '[]'::jsonb WHERE tags IS NULL;

    -- Version update
    CREATE OR REPLACE FUNCTION pggit.version() RETURNS TEXT AS $$
        SELECT '0.2.0'::TEXT;
    $$ LANGUAGE sql IMMUTABLE;

    -- Mark upgrade as completed
    UPDATE pggit.upgrade_log
    SET status = 'completed', completed_at = CURRENT_TIMESTAMP
    WHERE upgrade_id = :current_upgrade_id;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;

    -- Mark upgrade as failed
    UPDATE pggit.upgrade_log
    SET status = 'failed', error_message = v_error, completed_at = CURRENT_TIMESTAMP
    WHERE upgrade_id = :current_upgrade_id;

    RAISE EXCEPTION 'Upgrade failed: %', v_error;
END $upgrade$;

COMMIT;

-- Verification
DO $verify$
DECLARE
    v_version TEXT;
BEGIN
    SELECT pggit.version() INTO v_version;
    IF v_version != '0.2.0' THEN
        RAISE EXCEPTION 'Upgrade verification failed: expected 0.2.0, got %', v_version;
    END IF;

    RAISE NOTICE '✅ Successfully upgraded to version %', v_version;
END $verify$;
```

**Downgrade script** (migrations/pggit--0.2.0--0.1.0.sql):
```sql
-- Downgrade from 0.2.0 to 0.1.0

BEGIN;

-- Remove new features
DROP TABLE IF EXISTS pggit.performance_metrics CASCADE;
ALTER TABLE pggit.objects DROP COLUMN IF EXISTS tags;
ALTER TABLE pggit.history DROP COLUMN IF EXISTS performance_impact;
DROP INDEX IF EXISTS pggit.idx_history_performance;

-- Restore version
CREATE OR REPLACE FUNCTION pggit.version() RETURNS TEXT AS $$
    SELECT '0.1.0'::TEXT;
$$ LANGUAGE sql IMMUTABLE;

COMMIT;

RAISE NOTICE '⚠️  Downgraded to version 0.1.0';
```

**Test upgrade path**:
```bash
# File: tests/upgrade/test-upgrade-path.sh
#!/bin/bash
set -e

echo "Testing upgrade path: 0.1.0 → 0.2.0 → 0.1.0"

# Setup
psql -c "DROP DATABASE IF EXISTS upgrade_test"
psql -c "CREATE DATABASE upgrade_test"

# Install 0.1.0
psql -d upgrade_test -f pggit--0.1.0.sql
VERSION=$(psql -d upgrade_test -tA -c "SELECT pggit.version()")
echo "✅ Installed version: $VERSION"

# Create test data
psql -d upgrade_test <<EOF
CREATE TABLE test_table (id SERIAL PRIMARY KEY);
SELECT pggit.create_branch('test-branch');
INSERT INTO pggit.objects (schema_name, object_name, object_type)
VALUES ('public', 'test_table', 'TABLE');
EOF

# Upgrade to 0.2.0
psql -d upgrade_test -f migrations/pggit--0.1.0--0.2.0.sql
VERSION=$(psql -d upgrade_test -tA -c "SELECT pggit.version()")
echo "✅ Upgraded to: $VERSION"

# Verify data survived
COUNT=$(psql -d upgrade_test -tA -c "SELECT COUNT(*) FROM pggit.objects")
if [ "$COUNT" -lt 1 ]; then
    echo "❌ Data lost during upgrade"
    exit 1
fi
echo "✅ Data intact: $COUNT objects"

# Downgrade to 0.1.0
psql -d upgrade_test -f migrations/pggit--0.2.0--0.1.0.sql
VERSION=$(psql -d upgrade_test -tA -c "SELECT pggit.version()")
echo "✅ Downgraded to: $VERSION"

# Cleanup
psql -c "DROP DATABASE upgrade_test"
echo "✅ Upgrade path test passed"
```

**Acceptance Criteria**:
- [ ] Upgrade script 0.1.0 → 0.2.0 created
- [ ] Downgrade script 0.2.0 → 0.1.0 created
- [ ] Upgrade preserves all data
- [ ] Upgrade is transactional (all or nothing)
- [ ] Upgrade log tracks history
- [ ] Backup created before upgrade
- [ ] Upgrade tests pass in CI

---

### Step 2: Package Building - Debian/Ubuntu [EFFORT: HIGH]

**Goal**: `apt install pggit` works on Debian/Ubuntu.

```bash
# File: packaging/debian/control
Source: pggit
Section: database
Priority: optional
Maintainer: Your Name <email@example.com>
Build-Depends: debhelper-compat (= 13), postgresql-server-dev-all (>= 217~)
Standards-Version: 4.6.0
Homepage: https://github.com/evoludigit/pgGit
Vcs-Git: https://github.com/evoludigit/pgGit.git
Vcs-Browser: https://github.com/evoludigit/pgGit

Package: postgresql-PGVERSION-pggit
Architecture: any
Depends: ${shlibs:Depends}, ${misc:Depends}, postgresql-PGVERSION, postgresql-PGVERSION-pgcrypto
Description: Git-like version control for PostgreSQL
 pgGit provides Git-style version control for PostgreSQL schemas:
  - Automatic DDL tracking
  - Branch and merge database schemas
  - Complete audit trail
  - Time-travel queries
  .
  This package is for PostgreSQL PGVERSION.
```

```makefile
# File: packaging/debian/rules
#!/usr/bin/make -f

%:
	dh $@ --with pgxs

override_dh_auto_install:
	dh_auto_install -- USE_PGXS=1

override_dh_auto_test:
	# Run tests during package build
	pg_buildext installcheck
```

```
# File: packaging/debian/changelog
pggit (0.1.0-1) unstable; urgency=medium

  * Initial release
  * Core DDL tracking functionality
  * Git-style branching and merging
  * PostgreSQL 15-17 support

 -- Your Name <email@example.com>  Mon, 15 Jan 2024 10:00:00 +0000
```

**Build script**:
```bash
# File: scripts/build-deb.sh
#!/bin/bash
set -e

VERSION=${1:-0.1.0}

echo "Building .deb packages for pgGit $VERSION"

# For each PostgreSQL version
for PG_VERSION in 15 16 17; do
    echo "Building for PostgreSQL $PG_VERSION..."

    # Update changelog
    sed -i "s/PGVERSION/$PG_VERSION/g" packaging/debian/control

    # Build package
    dpkg-buildpackage -us -uc -b

    # Move to dist/
    mkdir -p dist
    mv ../postgresql-$PG_VERSION-pggit_${VERSION}*.deb dist/

    echo "✅ Built: dist/postgresql-$PG_VERSION-pggit_${VERSION}_amd64.deb"
done

# Create repository
cd dist
dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz

echo "✅ All packages built"
echo "To install: sudo dpkg -i postgresql-17-pggit_${VERSION}_amd64.deb"
```

**GitHub Actions for building**:
```yaml
# .github/workflows/packages.yml
name: Build Packages

on:
  release:
    types: [created]
  workflow_dispatch:

jobs:
  build-deb:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        pg-version: [15, 16, 17]

    steps:
    - uses: actions/checkout@v4

    - name: Install build dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y debhelper postgresql-server-dev-${{ matrix.pg-version }}

    - name: Build package
      run: |
        dpkg-buildpackage -us -uc -b

    - name: Upload artifact
      uses: actions/upload-artifact@v3
      with:
        name: postgresql-${{ matrix.pg-version }}-pggit
        path: ../postgresql-${{ matrix.pg-version }}-pggit_*.deb

    - name: Upload to release
      if: github.event_name == 'release'
      uses: actions/upload-release-asset@v1
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      with:
        upload_url: ${{ github.event.release.upload_url }}
        asset_path: ../postgresql-${{ matrix.pg-version }}-pggit_${{ github.event.release.tag_name }}.deb
        asset_name: postgresql-${{ matrix.pg-version }}-pggit_${{ github.event.release.tag_name }}.deb
        asset_content_type: application/vnd.debian.binary-package
```

**Acceptance Criteria**:
- [ ] Debian package builds for PostgreSQL 15, 16, 17
- [ ] Package installs cleanly on Ubuntu 22.04, 24.04
- [ ] Package includes all SQL files
- [ ] Package creates pggit schema on install
- [ ] Uninstall removes all pggit components
- [ ] CI builds packages on release

---

### Step 3: Package Building - RHEL/Rocky Linux [EFFORT: HIGH]

**Goal**: `dnf install pggit` works on RHEL/Rocky.

```spec
# File: packaging/rpm/pggit.spec
Name:           pggit
Version:        0.1.0
Release:        1%{?dist}
Summary:        Git-like version control for PostgreSQL

License:        MIT
URL:            https://github.com/evoludigit/pgGit
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  postgresql-devel >= 15
Requires:       postgresql-server >= 15
Requires:       postgresql-contrib >= 15

%description
pgGit provides Git-style version control for PostgreSQL schemas:
- Automatic DDL tracking
- Branch and merge database schemas
- Complete audit trail

%prep
%setup -q

%build
USE_PGXS=1 make

%install
USE_PGXS=1 make install DESTDIR=%{buildroot}

%files
%license LICENSE
%doc README.md
%{_datadir}/postgresql/extension/pggit*.sql
%{_datadir}/postgresql/extension/pggit.control

%changelog
* Mon Jan 15 2024 Your Name <email@example.com> - 0.1.0-1
- Initial release
```

**Build script**:
```bash
# File: scripts/build-rpm.sh
#!/bin/bash
set -e

VERSION=${1:-0.1.0}

echo "Building RPM for pgGit $VERSION"

# Setup RPM build environment
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Create source tarball
git archive --format=tar.gz --prefix=pggit-$VERSION/ HEAD > ~/rpmbuild/SOURCES/pggit-$VERSION.tar.gz

# Copy spec file
cp packaging/rpm/pggit.spec ~/rpmbuild/SPECS/

# Build RPM
rpmbuild -ba ~/rpmbuild/SPECS/pggit.spec

# Copy to dist/
mkdir -p dist
cp ~/rpmbuild/RPMS/x86_64/pggit-$VERSION-*.rpm dist/

echo "✅ Built: dist/pggit-$VERSION-1.el8.x86_64.rpm"
```

**Acceptance Criteria**:
- [ ] RPM package builds
- [ ] Package installs on Rocky Linux 8, 9
- [ ] Package works with PostgreSQL 15, 16, 17
- [ ] CI builds RPM packages

---

### Step 4: Monitoring and Metrics [EFFORT: MEDIUM]

**Goal**: Observability for production deployments.

```sql
-- File: sql/pggit_monitoring.sql
-- Monitoring and metrics for pgGit

-- Performance metrics table
CREATE TABLE IF NOT EXISTS pggit.performance_metrics (
    metric_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    metric_type TEXT NOT NULL,
    metric_value NUMERIC NOT NULL,
    tags JSONB DEFAULT '{}'::jsonb,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_perf_metrics_type_time
    ON pggit.performance_metrics(metric_type, recorded_at DESC);

-- Record DDL operation metrics
CREATE OR REPLACE FUNCTION pggit.record_metric(
    p_type TEXT,
    p_value NUMERIC,
    p_tags JSONB DEFAULT '{}'
) RETURNS VOID AS $$
BEGIN
    INSERT INTO pggit.performance_metrics (metric_type, metric_value, tags)
    VALUES (p_type, p_value, p_tags);
END;
$$ LANGUAGE plpgsql;

-- Monitoring views
CREATE OR REPLACE VIEW pggit.metrics_summary AS
SELECT
    metric_type,
    COUNT(*) as sample_count,
    AVG(metric_value) as avg_value,
    MIN(metric_value) as min_value,
    MAX(metric_value) as max_value,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY metric_value) as p95_value,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY metric_value) as p99_value
FROM pggit.performance_metrics
WHERE recorded_at > NOW() - INTERVAL '1 hour'
GROUP BY metric_type;

COMMENT ON VIEW pggit.metrics_summary IS
'Performance metrics summary for the last hour.
Use for monitoring dashboards and alerting.';

-- Health check function
CREATE OR REPLACE FUNCTION pggit.health_check()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    message TEXT,
    details JSONB
) AS $$
BEGIN
    -- Check 1: Event triggers enabled
    RETURN QUERY
    SELECT
        'event_triggers'::TEXT,
        CASE WHEN COUNT(*) >= 2 THEN 'healthy' ELSE 'unhealthy' END::TEXT,
        format('%s event triggers active', COUNT(*))::TEXT,
        jsonb_build_object('count', COUNT(*), 'expected', 2)
    FROM pg_event_trigger
    WHERE evtname LIKE 'pggit%' AND evtenabled = 'O';

    -- Check 2: Recent activity
    RETURN QUERY
    SELECT
        'recent_activity'::TEXT,
        CASE WHEN COUNT(*) > 0 THEN 'healthy' ELSE 'warning' END::TEXT,
        format('%s changes in last hour', COUNT(*))::TEXT,
        jsonb_build_object('change_count', COUNT(*))
    FROM pggit.history
    WHERE created_at > NOW() - INTERVAL '1 hour';

    -- Check 3: Storage size
    RETURN QUERY
    SELECT
        'storage_size'::TEXT,
        CASE WHEN size_mb < 1000 THEN 'healthy'
             WHEN size_mb < 5000 THEN 'warning'
             ELSE 'critical' END::TEXT,
        format('%.2f MB used', size_mb)::TEXT,
        jsonb_build_object('size_mb', size_mb, 'threshold_mb', 5000)
    FROM (
        SELECT pg_total_relation_size('pggit.history')::NUMERIC / 1024 / 1024 as size_mb
    ) sizes;

    -- Check 4: Object count
    RETURN QUERY
    SELECT
        'object_count'::TEXT,
        'healthy'::TEXT,
        format('%s tracked objects', COUNT(*))::TEXT,
        jsonb_build_object('count', COUNT(*))
    FROM pggit.objects
    WHERE is_active = true;

END;
$$ LANGUAGE plpgsql;

-- Prometheus exporter function
CREATE OR REPLACE FUNCTION pggit.prometheus_metrics()
RETURNS TEXT AS $$
DECLARE
    v_output TEXT := '';
    v_metric RECORD;
BEGIN
    -- Metric: Total tracked objects
    v_output := v_output || format(E'# HELP pggit_objects_total Total number of tracked objects\n');
    v_output := v_output || format(E'# TYPE pggit_objects_total gauge\n');
    v_output := v_output || format(E'pggit_objects_total %s\n',
        (SELECT COUNT(*) FROM pggit.objects WHERE is_active = true)
    );

    -- Metric: Changes per hour
    v_output := v_output || format(E'# HELP pggit_changes_per_hour Changes in the last hour\n');
    v_output := v_output || format(E'# TYPE pggit_changes_per_hour gauge\n');
    v_output := v_output || format(E'pggit_changes_per_hour %s\n',
        (SELECT COUNT(*) FROM pggit.history WHERE created_at > NOW() - INTERVAL '1 hour')
    );

    -- Metric: Storage size
    v_output := v_output || format(E'# HELP pggit_storage_bytes Total storage used by pgGit\n');
    v_output := v_output || format(E'# TYPE pggit_storage_bytes gauge\n');
    v_output := v_output || format(E'pggit_storage_bytes %s\n',
        pg_total_relation_size('pggit.history') + pg_total_relation_size('pggit.objects')
    );

    -- Metric: Performance metrics by type
    FOR v_metric IN
        SELECT metric_type, AVG(metric_value) as avg_val
        FROM pggit.performance_metrics
        WHERE recorded_at > NOW() - INTERVAL '5 minutes'
        GROUP BY metric_type
    LOOP
        v_output := v_output || format(E'# HELP pggit_%s_avg Average %s\n',
            v_metric.metric_type, v_metric.metric_type);
        v_output := v_output || format(E'# TYPE pggit_%s_avg gauge\n', v_metric.metric_type);
        v_output := v_output || format(E'pggit_%s_avg %s\n',
            v_metric.metric_type, v_metric.avg_val);
    END LOOP;

    RETURN v_output;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.prometheus_metrics() IS
'Export metrics in Prometheus format.
Expose via pg_exporter or custom HTTP endpoint.';

-- Create metrics collection trigger
CREATE OR REPLACE FUNCTION pggit.collect_ddl_metrics()
RETURNS event_trigger AS $$
DECLARE
    v_start TIMESTAMP;
    v_duration NUMERIC;
BEGIN
    v_start := clock_timestamp();

    -- Track DDL execution time
    v_duration := EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) * 1000;

    PERFORM pggit.record_metric(
        'ddl_execution_ms',
        v_duration,
        jsonb_build_object('command', TG_TAG)
    );
END;
$$ LANGUAGE plpgsql;
```

**Grafana dashboard**:
```json
{
  "dashboard": {
    "title": "pgGit Monitoring",
    "panels": [
      {
        "title": "Tracked Objects",
        "targets": [{
          "expr": "pggit_objects_total"
        }]
      },
      {
        "title": "Changes per Hour",
        "targets": [{
          "expr": "rate(pggit_changes_per_hour[5m])"
        }]
      },
      {
        "title": "Storage Usage",
        "targets": [{
          "expr": "pggit_storage_bytes / 1024 / 1024"
        }]
      }
    ]
  }
}
```

**Acceptance Criteria**:
- [ ] Monitoring SQL module created
- [ ] Health check function returns status
- [ ] Prometheus metrics exportable
- [ ] Grafana dashboard template
- [ ] Documentation in docs/operations/MONITORING.md

---

### Step 5: Backup and Restore Procedures [EFFORT: MEDIUM]

**Goal**: Safe backup and recovery of pgGit data.

```markdown
# File: docs/operations/BACKUP_RESTORE.md

# Backup and Restore Guide

## Overview

pgGit stores all version history in the `pggit` schema. Proper backup ensures you can recover full version history.

## Backup Strategies

### 1. Full Database Backup (Recommended)

Include pgGit schema in regular database backups:

```bash
# Backup entire database
pg_dump -Fc mydatabase > backup_$(date +%Y%m%d).dump

# Restore
pg_restore -d mydatabase backup_20240115.dump
```

### 2. pgGit Schema Only

Backup just version control data:

```bash
# Backup pgGit schema
pg_dump -Fc -n pggit mydatabase > pggit_backup_$(date +%Y%m%d).dump

# Restore
pg_restore -d mydatabase -n pggit pggit_backup_20240115.dump
```

### 3. Selective Export

Export specific branches or time ranges:

```sql
-- Export changes from last 30 days
\copy (SELECT * FROM pggit.history WHERE created_at > NOW() - INTERVAL '30 days') TO 'history_30days.csv' CSV HEADER;

-- Export specific branch
\copy (SELECT * FROM pggit.commits WHERE branch_id = (SELECT id FROM pggit.branches WHERE name = 'main')) TO 'main_branch.csv' CSV HEADER;
```

## Restore Procedures

### Full Restore

```bash
# 1. Drop existing schema
psql -d mydatabase -c "DROP SCHEMA IF EXISTS pggit CASCADE"

# 2. Restore from backup
pg_restore -d mydatabase backup.dump

# 3. Verify
psql -d mydatabase -c "SELECT COUNT(*) FROM pggit.objects"
```

### Point-in-Time Recovery

```sql
-- Restore to specific timestamp
BEGIN;

-- Create restore point
SELECT pggit.create_restore_point('before_disaster', NOW() - INTERVAL '1 hour');

-- Restore objects to that point
SELECT pggit.restore_to_point('before_disaster');

COMMIT;
```

## Backup Verification

```sql
-- Verify backup completeness
SELECT
    'objects' as table_name,
    COUNT(*) as row_count,
    pg_size_pretty(pg_total_relation_size('pggit.objects')) as size
FROM pggit.objects
UNION ALL
SELECT 'history', COUNT(*), pg_size_pretty(pg_total_relation_size('pggit.history'))
FROM pggit.history
UNION ALL
SELECT 'commits', COUNT(*), pg_size_pretty(pg_total_relation_size('pggit.commits'))
FROM pggit.commits;
```

## Automated Backups

```bash
#!/bin/bash
# File: scripts/backup-pggit.sh

DB_NAME=${1:-postgres}
BACKUP_DIR=/var/backups/pggit
RETENTION_DAYS=30

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/pggit_${DB_NAME}_${TIMESTAMP}.dump"

# Perform backup
pg_dump -Fc -n pggit $DB_NAME > $BACKUP_FILE

# Verify backup
if pg_restore -l $BACKUP_FILE > /dev/null 2>&1; then
    echo "✅ Backup successful: $BACKUP_FILE"

    # Compress
    gzip $BACKUP_FILE

    # Remove old backups
    find $BACKUP_DIR -name "pggit_*.dump.gz" -mtime +$RETENTION_DAYS -delete
else
    echo "❌ Backup verification failed"
    exit 1
fi
```

**Cron job**:
```cron
# Daily backup at 2 AM
0 2 * * * /path/to/scripts/backup-pggit.sh production >> /var/log/pggit-backup.log 2>&1
```

## Disaster Recovery Testing

```bash
# Test restore procedure quarterly
./scripts/test-restore.sh

# 1. Create test database
# 2. Restore latest backup
# 3. Verify data integrity
# 4. Test key operations
# 5. Report results
```
```

**Acceptance Criteria**:
- [ ] Backup procedures documented
- [ ] Restore procedures tested
- [ ] Automated backup script
- [ ] Backup verification checks
- [ ] DR testing guide

---

### Step 6: Release Automation [EFFORT: HIGH]

**Goal**: One-click releases with packages and changelogs.

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  create-release:
    runs-on: ubuntu-latest
    outputs:
      upload_url: ${{ steps.create_release.outputs.upload_url }}

    steps:
    - uses: actions/checkout@v4

    - name: Generate changelog
      id: changelog
      run: |
        # Extract changes since last tag
        PREV_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")
        if [ -z "$PREV_TAG" ]; then
          CHANGES=$(git log --pretty=format:"- %s (%an)" --no-merges)
        else
          CHANGES=$(git log --pretty=format:"- %s (%an)" --no-merges $PREV_TAG..HEAD)
        fi
        echo "changes<<EOF" >> $GITHUB_OUTPUT
        echo "$CHANGES" >> $GITHUB_OUTPUT
        echo "EOF" >> $GITHUB_OUTPUT

    - name: Create Release
      id: create_release
      uses: actions/create-release@v1
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      with:
        tag_name: ${{ github.ref }}
        release_name: pgGit ${{ github.ref_name }}
        body: |
          ## Changes

          ${{ steps.changelog.outputs.changes }}

          ## Installation

          ### Debian/Ubuntu
          ```bash
          wget https://github.com/evoludigit/pgGit/releases/download/${{ github.ref_name }}/postgresql-17-pggit_${{ github.ref_name }}.deb
          sudo dpkg -i postgresql-17-pggit_${{ github.ref_name }}.deb
          ```

          ### RHEL/Rocky
          ```bash
          wget https://github.com/evoludigit/pgGit/releases/download/${{ github.ref_name }}/pggit-${{ github.ref_name }}.rpm
          sudo dnf install pggit-${{ github.ref_name }}.rpm
          ```

          ### From Source
          ```bash
          git clone --branch ${{ github.ref_name }} https://github.com/evoludigit/pgGit.git
          cd pgGit
          make && sudo make install
          ```
        draft: false
        prerelease: false

  build-packages:
    needs: create-release
    uses: ./.github/workflows/packages.yml
    secrets: inherit
```

**Release checklist**:
```markdown
# File: docs/operations/RELEASE_CHECKLIST.md

# Release Checklist

## Pre-Release (1 week before)

- [ ] All tests passing on main branch
- [ ] No open P0/P1 bugs
- [ ] Security audit complete (if major version)
- [ ] Performance benchmarks run
- [ ] Documentation up to date
- [ ] CHANGELOG.md updated
- [ ] Migration scripts created (if needed)
- [ ] Upgrade tested from previous version

## Release Day

- [ ] Create release branch: `git checkout -b release/vX.Y.Z`
- [ ] Update version in:
  - [ ] pggit.control
  - [ ] pggit--X.Y.Z.sql
  - [ ] README.md
  - [ ] package files
- [ ] Tag release: `git tag -a vX.Y.Z -m "Release X.Y.Z"`
- [ ] Push tag: `git push origin vX.Y.Z`
- [ ] Wait for CI to build packages
- [ ] Test installation from packages
- [ ] Publish release notes
- [ ] Update website/docs
- [ ] Announce on Twitter, Reddit, HN

## Post-Release

- [ ] Monitor issue tracker for bug reports
- [ ] Update Docker images
- [ ] Update package repositories
- [ ] Merge release branch back to main
- [ ] Create milestone for next version
```

**Acceptance Criteria**:
- [ ] Release workflow automated
- [ ] Packages built and uploaded automatically
- [ ] Changelog generated from commits
- [ ] Release notes templated
- [ ] Checklist documented

---

## Phase-Wide Rollback Strategy

If Phase 3 needs to be completely rolled back:

```bash
# Return to Phase 2 state
git checkout main
git branch -D phase-3-production-polish

# If changes were already merged
git revert <merge-commit-sha>

# Remove test packages
sudo dpkg -r postgresql-*-pggit  # Debian
sudo dnf remove pggit            # RHEL

# Drop monitoring schema elements
psql -c "DROP TABLE IF EXISTS pggit.performance_metrics CASCADE"
```

**Safe Checkpoints** (tag these as you go):
```bash
git tag phase-3-step-1-complete  # After migrations
git tag phase-3-step-3-complete  # After packaging
git tag phase-3-step-4-complete  # After monitoring
git tag phase-3-complete         # After all steps
```

---

## Verification Commands

```bash
# 1. Upgrade migrations work
# ✅ PASS: Upgrade and downgrade succeed, data intact
# ❌ FAIL: Any upgrade fails or data lost
bash tests/upgrade/test-upgrade-path.sh

# 2. Packages build
# ✅ PASS: Both .deb and .rpm created, install cleanly
# ❌ FAIL: Build fails or packages don't install
make build-deb && make build-rpm

# 3. Monitoring functional
# ✅ PASS: All health checks return 'healthy' or 'warning'
# ❌ FAIL: Any check returns error or times out
psql -c "SELECT * FROM pggit.health_check()" | grep -q "healthy"

# 4. Backup/restore works
# ✅ PASS: Backup created, restore succeeds, data verified
# ❌ FAIL: Backup fails or restore corrupts data
bash scripts/backup-pggit.sh && bash scripts/test-restore.sh

# 5. Release automation ready
# ✅ PASS: Workflow completes, packages uploaded
# ❌ FAIL: Workflow fails or packages missing
gh workflow view release.yml
```

---

## Acceptance Criteria

### Upgrades
- [ ] Upgrade scripts for version transitions
- [ ] Downgrade capability
- [ ] Automated upgrade testing in CI
- [ ] Upgrade preserves all data
- [ ] Documentation for upgrade process

### Packaging
- [ ] Debian packages for PostgreSQL 15-17
- [ ] RPM packages for RHEL/Rocky
- [ ] Packages install cleanly
- [ ] Packages tested on target OSes
- [ ] CI builds packages on release

### Operations
- [ ] Monitoring SQL module
- [ ] Health check function
- [ ] Prometheus metrics
- [ ] Backup procedures documented
- [ ] Disaster recovery guide
- [ ] Automated backup scripts

### Release
- [ ] Automated release workflow
- [ ] Changelog generation
- [ ] Package uploads
- [ ] Release notes
- [ ] Checklist documented

---

## Success Metrics

| Metric | Current | Target | How to Verify | Achieved |
|--------|---------|--------|---------------|----------|
| Upgrade success rate | N/A | 100% | Upgrade test passes | [ ] |
| Package installation | Manual | Automated | Packages install on target OSes | [ ] |
| Monitoring coverage | 0% | 100% | Health checks return status | [ ] |
| Backup automation | Manual | Automated | Automated backup script works | [ ] |
| Release time | N/A | Streamlined | Release workflow completes | [ ] |
| Documentation | Incomplete | Complete | All ops docs exist | [ ] |
| Overall quality | 8.5/10 | 9.0/10 | All above metrics met | [ ] |

---

## Next Phase

After Phase 3 → **Phase 4: Excellence** (optional)
- Video tutorials
- Enhanced community engagement
- Advanced features
