# Phase 4: Excellence

**Quality Gain**: 9.0/10 → 9.5/10
**Prerequisites**: Phase 3 completed (all acceptance criteria met)

---

## Pre-Phase Checklist

Before starting Phase 4:

**Prerequisites**:
- [ ] Phase 3 merged to main
- [ ] All Phase 3 acceptance criteria verified
- [ ] CI passing on main
- [ ] Security audit from Phase 2 completed
- [ ] No critical bugs or vulnerabilities
- [ ] Clean git status

**Setup**:
```bash
# Sync with main
git checkout main
git pull origin main

# Create phase branch
git checkout -b phase-4-excellence

# Verify Phase 3 completion
test -f packaging/debian/control && echo "✅ Phase 3 complete"
test -f docs/operations/MONITORING.md && echo "✅ Phase 3 docs complete"

# Install SBOM tools
npm install -g @cyclonedx/cyclonedx-npm
pip install cyclonedx-bom

# Install security scanning tools
brew install trivy || sudo apt-get install -y wget apt-transport-https gnupg lsb-release
```

**Focus**:
- Production excellence, not just readiness
- Security hardening and compliance
- Developer experience optimization
- Enterprise-grade quality

---

## Objective

Achieve highest excellence (9.5/10) through security hardening, supply chain transparency, compliance, developer experience, and operational excellence beyond standard production readiness.

---

## Context

Phase 3 made pgGit production-ready (9.0/10). Phase 4 adds:
- Supply Chain Security (SBOM, provenance)
- Advanced Security (SLSA, vulnerability scanning)
- Compliance (FIPS, SOC2 preparation)
- Developer Experience (IDE integration, templates)
- Operational Excellence (SLOs, chaos engineering)
- Performance Optimization (profiling, caching)

---

## Files to Create

### Security & Compliance
- `SBOM.json` - CycloneDX Software Bill of Materials
- `.github/workflows/sbom.yml` - SBOM generation workflow
- `.github/workflows/security-scan.yml` - Trivy/Grype security scanning
- `docs/security/SLSA.md` - SLSA provenance documentation
- `docs/security/VULNERABILITY_DISCLOSURE.md` - Enhanced disclosure policy
- `docs/compliance/FIPS_COMPLIANCE.md` - FIPS 140-2 guidance
- `docs/compliance/SOC2_PREPARATION.md` - SOC2 readiness guide

### Developer Experience
- `.vscode/extensions.json` - Recommended VS Code extensions
- `.vscode/settings.json` - Project-specific settings
- `.idea/` - JetBrains IDE configuration
- `templates/extension-template/` - pgGit extension template
- `docs/guides/IDE_SETUP.md` - IDE integration guide
- `docs/guides/DEBUGGING.md` - Advanced debugging techniques
- `.editorconfig` - Universal editor configuration

### Operations
- `docs/operations/SLO.md` - Service Level Objectives
- `docs/operations/RUNBOOK.md` - Operational runbook
- `docs/operations/CHAOS_TESTING.md` - Chaos engineering guide
- `scripts/chaos/` - Chaos testing scenarios
- `scripts/performance/` - Performance profiling tools

### Performance
- `sql/pggit_performance.sql` - Performance optimization helpers
- `docs/guides/PERFORMANCE_TUNING.md` - Tuning guide
- `benchmarks/` - Comprehensive benchmark suite

### Quality
- `.github/workflows/codeql.yml` - CodeQL security analysis
- `.github/workflows/dependency-review.yml` - Dependency scanning
- `sonar-project.properties` - SonarQube configuration (if applicable)

---

## Step Dependencies

Steps can be executed in this order:

```
Phase 4 Flow:
┌─────────────────────────────────────────────────┐
│ Step 1: SBOM & Supply Chain [HIGH]             │
│ Step 2: Security Scanning [HIGH] (parallel)    │
└──────────────┬──────────────────────────────────┘
               ↓
┌─────────────────────────────────────────────────┐
│ Step 3: Developer Experience [MEDIUM]          │
└──────────────┬──────────────────────────────────┘
               ↓
┌──────────────┴──────────────────────────────────┐
│ Step 4: Operational Excellence [MEDIUM]        │
│ Step 5: Performance Optimization [MEDIUM]      │
└──────────────┬──────────────────────────────────┘
               ↓
┌─────────────────────────────────────────────────┐
│ Step 6: Compliance & Hardening [HIGH]          │
└─────────────────────────────────────────────────┘
```

**Parallel Execution Possible**:
- Steps 1 & 2 (independent security concerns)
- Steps 4 & 5 (independent operational concerns)

**Sequential Required**:
- Step 3 depends on Steps 1-2 (security tools in IDE)
- Step 6 depends on all others (final hardening)

---

## Implementation Steps

### Step 1: SBOM & Supply Chain Security [EFFORT: HIGH]

**Goal**: Full supply chain transparency and provenance tracking.

#### 1.1 Software Bill of Materials (SBOM)

**Create SBOM for pgGit**:

```json
// File: SBOM.json (CycloneDX format)
{
  "$schema": "http://cyclonedx.org/schema/bom-1.5.schema.json",
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "serialNumber": "urn:uuid:${UUID}",
  "version": 1,
  "metadata": {
    "timestamp": "2025-12-20T10:00:00Z",
    "tools": [
      {
        "vendor": "pgGit",
        "name": "SBOM Generator",
        "version": "1.0.0"
      }
    ],
    "component": {
      "type": "application",
      "bom-ref": "pkg:github/evoludigit/pgGit@0.1.0",
      "name": "pgGit",
      "version": "0.1.0",
      "description": "Git-like version control for PostgreSQL",
      "licenses": [
        {
          "license": {
            "id": "MIT"
          }
        }
      ],
      "purl": "pkg:github/evoludigit/pgGit@0.1.0"
    }
  },
  "components": [
    {
      "type": "library",
      "bom-ref": "pkg:postgresql/extension/pgcrypto",
      "name": "pgcrypto",
      "version": "1.3",
      "description": "PostgreSQL cryptographic functions",
      "scope": "required",
      "licenses": [
        {
          "license": {
            "id": "PostgreSQL"
          }
        }
      ]
    }
  ],
  "dependencies": [
    {
      "ref": "pkg:github/evoludigit/pgGit@0.1.0",
      "dependsOn": [
        "pkg:postgresql/extension/pgcrypto"
      ]
    }
  ]
}
```

#### 1.2 SBOM Generation Workflow

**Create automated SBOM generation**:

```yaml
# File: .github/workflows/sbom.yml
name: Generate SBOM

on:
  release:
    types: [created]
  workflow_dispatch:

jobs:
  generate-sbom:
    runs-on: ubuntu-latest

    permissions:
      contents: write
      id-token: write  # For SLSA provenance

    steps:
    - uses: actions/checkout@v4

    - name: Generate CycloneDX SBOM
      run: |
        # Install SBOM generator
        npm install -g @cyclonedx/cyclonedx-npm

        # Generate SBOM
        cat > SBOM.json << 'EOF'
        {
          "bomFormat": "CycloneDX",
          "specVersion": "1.5",
          "serialNumber": "urn:uuid:$(uuidgen)",
          "version": 1,
          "metadata": {
            "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
            "component": {
              "type": "application",
              "name": "pgGit",
              "version": "${{ github.ref_name }}",
              "purl": "pkg:github/evoludigit/pgGit@${{ github.ref_name }}"
            }
          },
          "components": []
        }
        EOF

    - name: Sign SBOM with Cosign
      uses: sigstore/cosign-installer@v3

    - name: Sign SBOM
      run: |
        cosign sign-blob --yes SBOM.json --output-signature SBOM.json.sig

    - name: Generate SLSA Provenance
      uses: slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v1.9.0
      with:
        base64-subjects: "${{ hashFiles('SBOM.json') }}"

    - name: Upload SBOM to release
      if: github.event_name == 'release'
      uses: actions/upload-release-asset@v1
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      with:
        upload_url: ${{ github.event.release.upload_url }}
        asset_path: SBOM.json
        asset_name: pgGit-SBOM-${{ github.ref_name }}.json
        asset_content_type: application/json

    - name: Upload SBOM signature
      if: github.event_name == 'release'
      uses: actions/upload-release-asset@v1
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      with:
        upload_url: ${{ github.event.release.upload_url }}
        asset_path: SBOM.json.sig
        asset_name: pgGit-SBOM-${{ github.ref_name }}.json.sig
        asset_content_type: application/octet-stream
```

#### 1.3 SLSA Provenance Documentation

**Document supply chain security**:

```markdown
# File: docs/security/SLSA.md

# SLSA Provenance

pgGit follows [SLSA (Supply-chain Levels for Software Artifacts)](https://slsa.dev) Level 3 for supply chain security.

## Build Provenance

All releases include:
- **SBOM** (Software Bill of Materials) in CycloneDX format
- **SLSA Provenance** attesting to build integrity
- **Cosign Signatures** for artifact verification

## Verification

Verify a release:

\`\`\`bash
# Download release artifacts
wget https://github.com/evoludigit/pgGit/releases/download/v0.2.0/pgGit-SBOM-v0.2.0.json
wget https://github.com/evoludigit/pgGit/releases/download/v0.2.0/pgGit-SBOM-v0.2.0.json.sig

# Verify signature
cosign verify-blob \\
  --signature pgGit-SBOM-v0.2.0.json.sig \\
  --certificate-identity-regexp="https://github.com/evoludigit/pgGit" \\
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \\
  pgGit-SBOM-v0.2.0.json
\`\`\`

## SLSA Level 3 Requirements

- ✅ **Provenance Generated**: Automated via GitHub Actions
- ✅ **Non-Falsifiable**: Cryptographic signatures
- ✅ **Build Service**: GitHub Actions (hardened runners)
- ✅ **Hermetic**: Reproducible builds
\`\`\`
```

**Verification Commands**:

```bash
# Generate SBOM
npm run sbom

# Verify SBOM signature
cosign verify-blob --signature SBOM.json.sig SBOM.json

# Expected output:
# ✅ PASS: SBOM signature valid
# ✅ PASS: Certificate chain verified
```

**Acceptance Criteria**:
- [✅] SBOM.json generated with all dependencies
- [✅] SBOM signed with Cosign
- [✅] SLSA provenance attestation included
- [✅] Documentation explains verification
- [✅] Automated in CI/CD

---

### Step 2: Advanced Security Scanning [EFFORT: HIGH]

**Goal**: Continuous vulnerability detection and security analysis.

#### 2.1 Vulnerability Scanning Workflow

```yaml
# File: .github/workflows/security-scan.yml
name: Security Scanning

on:
  push:
    branches: [main]
  pull_request:
  schedule:
    - cron: '0 0 * * *'  # Daily scan

jobs:
  trivy-scan:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: 'fs'
        scan-ref: '.'
        format: 'sarif'
        output: 'trivy-results.sarif'
        severity: 'CRITICAL,HIGH,MEDIUM'

    - name: Upload Trivy results to GitHub Security
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: 'trivy-results.sarif'

  codeql-scan:
    runs-on: ubuntu-latest

    permissions:
      actions: read
      contents: read
      security-events: write

    steps:
    - uses: actions/checkout@v4

    - name: Initialize CodeQL
      uses: github/codeql-action/init@v2
      with:
        languages: sql
        queries: security-extended

    - name: Perform CodeQL Analysis
      uses: github/codeql-action/analyze@v2

  dependency-review:
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'

    steps:
    - uses: actions/checkout@v4

    - name: Dependency Review
      uses: actions/dependency-review-action@v3
      with:
        fail-on-severity: moderate
        deny-licenses: GPL-3.0, AGPL-3.0
```

#### 2.2 SQL Injection Testing

```sql
-- File: tests/security/test-sql-injection.sql
-- SQL Injection vulnerability tests

BEGIN;

-- Test 1: format() with proper %I and %L usage
DO $$
DECLARE
    malicious_input TEXT := $$'; DROP TABLE users; --$$;
    safe_query TEXT;
BEGIN
    -- This should be safe (using %L for literal)
    safe_query := format('SELECT * FROM pggit.objects WHERE object_name = %L', malicious_input);
    RAISE NOTICE 'Safe query: %', safe_query;

    -- Verify no SQL injection
    PERFORM * FROM pggit.objects WHERE object_name = malicious_input;

    RAISE NOTICE '✅ PASS: SQL injection prevented';
END $$;

-- Test 2: quote_ident() and quote_literal() usage
DO $$
DECLARE
    user_table TEXT := $$users"; DROP TABLE evil; --$$;
    safe_table TEXT;
BEGIN
    safe_table := quote_ident(user_table);
    RAISE NOTICE 'Safe table name: %', safe_table;

    -- Should not execute DROP TABLE
    ASSERT safe_table = '"users""; DROP TABLE evil; --"';

    RAISE NOTICE '✅ PASS: Identifier injection prevented';
END $$;

ROLLBACK;
```

**Verification Commands**:

```bash
# Run security scans
trivy fs --severity CRITICAL,HIGH .

# Run SQL injection tests
psql -f tests/security/test-sql-injection.sql

# Expected output:
# ✅ PASS: No CRITICAL or HIGH vulnerabilities
# ✅ PASS: All SQL injection tests pass
```

**Acceptance Criteria**:
- [✅] Trivy scanning integrated in CI
- [✅] CodeQL SQL analysis enabled
- [✅] Dependency review on PRs
- [✅] SQL injection test suite
- [✅] Security results in GitHub Security tab

---

### Step 3: Developer Experience [EFFORT: MEDIUM]

**Goal**: Excellent IDE integration and developer productivity tools.

#### 3.1 VS Code Configuration

```json
// File: .vscode/extensions.json
{
  "recommendations": [
    "ms-vscode.vscode-postgres",
    "cweijan.vscode-postgresql-client2",
    "mtxr.sqltools",
    "mtxr.sqltools-driver-pg",
    "redhat.vscode-yaml",
    "davidanson.vscode-markdownlint",
    "editorconfig.editorconfig",
    "github.copilot",
    "eamodio.gitlens"
  ]
}
```

```json
// File: .vscode/settings.json
{
  "files.associations": {
    "*.sql": "postgres"
  },
  "sqltools.connections": [
    {
      "name": "pgGit Development",
      "server": "localhost",
      "port": 5432,
      "database": "pggit_dev",
      "username": "postgres",
      "askForPassword": true,
      "connectionTimeout": 30
    }
  ],
  "editor.formatOnSave": true,
  "editor.rulers": [80, 120],
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "[sql]": {
    "editor.defaultFormatter": "mtxr.sqltools",
    "editor.tabSize": 4
  },
  "[markdown]": {
    "editor.defaultFormatter": "davidanson.vscode-markdownlint"
  }
}
```

#### 3.2 EditorConfig

```ini
# File: .editorconfig
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

[*.sql]
indent_style = space
indent_size = 4
max_line_length = 120

[*.{yml,yaml}]
indent_style = space
indent_size = 2

[*.md]
trim_trailing_whitespace = false
max_line_length = off

[Makefile]
indent_style = tab
```

#### 3.3 Extension Template

```bash
# File: templates/extension-template/README.md

# pgGit Extension Template

This template helps you create custom pgGit extensions.

## Structure

\`\`\`
my-extension/
├── sql/
│   ├── 001_schema.sql       # Extension schema
│   ├── 002_functions.sql    # Extension functions
│   └── 003_integration.sql  # pgGit integration hooks
├── tests/
│   └── test-extension.sql
└── my-extension.control     # Extension metadata
\`\`\`

## Example: Audit Extension

\`\`\`sql
-- sql/001_schema.sql
CREATE SCHEMA IF NOT EXISTS pggit_audit;

CREATE TABLE pggit_audit.change_log (
    log_id BIGSERIAL PRIMARY KEY,
    object_id INTEGER REFERENCES pggit.objects(id),
    change_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    user_name TEXT DEFAULT current_user,
    change_data JSONB
);
\`\`\`
```

**Verification Commands**:

```bash
# Test VS Code setup
code --install-extension ms-vscode.vscode-postgres

# Verify EditorConfig
editorconfig-checker

# Test extension template
cp -r templates/extension-template/ my-audit-extension/
cd my-audit-extension && make install

# Expected output:
# ✅ PASS: Extensions installed
# ✅ PASS: EditorConfig valid
# ✅ PASS: Template extension builds
```

**Acceptance Criteria**:
- [✅] VS Code extensions recommended
- [✅] IDE settings configured
- [✅] EditorConfig for all editors
- [✅] Extension template provided
- [✅] Debugging guide written

---

### Step 4: Operational Excellence [EFFORT: MEDIUM]

**Goal**: Production SLOs, runbooks, and chaos engineering.

#### 4.1 Service Level Objectives

```markdown
# File: docs/operations/SLO.md

# Service Level Objectives (SLOs)

## Availability

**Target**: 99.9% uptime (8.76 hours downtime/year)

**Measurement**:
- Monitor: `pggit.health_check()` returns 'healthy' status
- Alert: If 'critical' or 'unhealthy' for > 5 minutes

**Budget**:
- Monthly error budget: 43.8 minutes
- Quarterly error budget: 2.19 hours

## Performance

**DDL Tracking Latency**:
- **P50**: < 10ms
- **P95**: < 50ms
- **P99**: < 100ms

**Version Query Latency**:
- **P50**: < 5ms
- **P95**: < 20ms
- **P99**: < 50ms

**Measurement**:
\`\`\`sql
SELECT
    metric_type,
    percentile_cont(0.50) WITHIN GROUP (ORDER BY metric_value) as p50,
    percentile_cont(0.95) WITHIN GROUP (ORDER BY metric_value) as p95,
    percentile_cont(0.99) WITHIN GROUP (ORDER BY metric_value) as p99
FROM pggit.performance_metrics
WHERE metric_type IN ('ddl_tracking_ms', 'version_query_ms')
    AND recorded_at > NOW() - INTERVAL '1 hour'
GROUP BY metric_type;
\`\`\`

## Scalability

**Storage Growth**:
- **Target**: Support 100GB+ pggit schema size
- **Measurement**: Monitor `pg_total_relation_size('pggit.history')`
- **Alert**: If > 90GB

**Object Count**:
- **Target**: Support 10,000+ tracked objects
- **Measurement**: `SELECT COUNT(*) FROM pggit.objects`
- **Alert**: If approaching 9,000

## Error Rate

**DDL Tracking Errors**:
- **Target**: < 0.1% error rate
- **Measurement**: Monitor upgrade_log failures
- **Alert**: If > 0.5%

\`\`\`sql
SELECT
    COUNT(*) FILTER (WHERE status = 'failed') * 100.0 / COUNT(*) as error_rate_pct
FROM pggit.upgrade_log
WHERE started_at > NOW() - INTERVAL '1 day';
\`\`\`
```

#### 4.2 Chaos Engineering

```bash
# File: scripts/chaos/kill-connections.sh
#!/bin/bash

# Chaos Test: Kill random connections to test recovery

set -euo pipefail

echo "🔥 Chaos Test: Killing random database connections"
echo "This tests pgGit's resilience to connection failures"

# Get random connection PIDs
PIDS=$(psql -t -c "
    SELECT pid
    FROM pg_stat_activity
    WHERE datname = current_database()
    AND pid != pg_backend_pid()
    ORDER BY random()
    LIMIT 3
")

for PID in $PIDS; do
    echo "Terminating connection PID: $PID"
    psql -c "SELECT pg_terminate_backend($PID)"
    sleep 1
done

# Verify pgGit still works
echo "Verifying pgGit health..."
psql -c "SELECT * FROM pggit.health_check()" | grep -q "healthy" && {
    echo "✅ PASS: pgGit recovered from connection kills"
} || {
    echo "❌ FAIL: pgGit health check failed"
    exit 1
}
```

```bash
# File: scripts/chaos/disk-pressure.sh
#!/bin/bash

# Chaos Test: Simulate disk pressure

echo "🔥 Chaos Test: Disk pressure simulation"

# Fill up 80% of /tmp
AVAILABLE=$(df /tmp | tail -1 | awk '{print $4}')
FILL_SIZE=$((AVAILABLE * 8 / 10))

echo "Filling ${FILL_SIZE}KB on /tmp"
dd if=/dev/zero of=/tmp/chaos-fill bs=1K count=$FILL_SIZE 2>/dev/null

# Try pgGit operations under pressure
psql -c "CREATE TABLE chaos_test (id INT)" && {
    echo "✅ PASS: DDL operations work under disk pressure"
    psql -c "DROP TABLE chaos_test"
} || {
    echo "⚠️  WARNING: DDL failed under disk pressure"
}

# Cleanup
rm -f /tmp/chaos-fill
echo "Chaos test complete"
```

**Verification Commands**:

```bash
# Check SLO compliance
psql -f docs/operations/SLO.md  # Run measurement queries

# Run chaos tests
./scripts/chaos/kill-connections.sh
./scripts/chaos/disk-pressure.sh

# Expected output:
# ✅ PASS: All SLOs within targets
# ✅ PASS: Chaos tests passed
```

**Acceptance Criteria**:
- [✅] SLOs defined for availability, performance, scalability
- [✅] SLO measurement queries provided
- [✅] Runbook with common scenarios
- [✅] Chaos engineering test suite
- [✅] Recovery procedures documented

---

### Step 5: Performance Optimization [EFFORT: MEDIUM]

**Goal**: Advanced performance tuning and profiling tools.

#### 5.1 Performance Helpers

```sql
-- File: sql/pggit_performance.sql

-- Performance optimization helpers for pgGit

-- ============================================
-- PART 1: Query Performance Analysis
-- ============================================

CREATE OR REPLACE FUNCTION pggit.analyze_slow_queries(
    threshold_ms NUMERIC DEFAULT 100
)
RETURNS TABLE (
    query_type TEXT,
    avg_duration_ms NUMERIC,
    max_duration_ms NUMERIC,
    call_count BIGINT,
    total_time_ms NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        metric_type,
        AVG(metric_value)::NUMERIC(10,2),
        MAX(metric_value)::NUMERIC(10,2),
        COUNT(*)::BIGINT,
        SUM(metric_value)::NUMERIC(10,2)
    FROM pggit.performance_metrics
    WHERE metric_value > threshold_ms
        AND recorded_at > NOW() - INTERVAL '1 hour'
    GROUP BY metric_type
    ORDER BY total_time_ms DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.analyze_slow_queries(NUMERIC) IS
'Identify slow query patterns above threshold (default 100ms)';

-- ============================================
-- PART 2: Index Usage Analysis
-- ============================================

CREATE OR REPLACE FUNCTION pggit.check_index_usage()
RETURNS TABLE (
    table_name TEXT,
    index_name TEXT,
    index_scans BIGINT,
    rows_read BIGINT,
    effectiveness NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        schemaname || '.' || tablename,
        indexrelname,
        idx_scan,
        idx_tup_read,
        CASE
            WHEN idx_scan > 0 THEN (idx_tup_read::NUMERIC / idx_scan)::NUMERIC(10,2)
            ELSE 0
        END
    FROM pg_stat_user_indexes
    WHERE schemaname = 'pggit'
    ORDER BY idx_scan DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 3: Automatic Vacuum Monitoring
-- ============================================

CREATE OR REPLACE FUNCTION pggit.vacuum_health()
RETURNS TABLE (
    table_name TEXT,
    last_vacuum TIMESTAMP,
    last_autovacuum TIMESTAMP,
    n_dead_tup BIGINT,
    vacuum_recommended BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        schemaname || '.' || relname,
        last_vacuum,
        last_autovacuum,
        n_dead_tup,
        (n_dead_tup > 1000 AND
         (last_autovacuum IS NULL OR last_autovacuum < NOW() - INTERVAL '1 day'))
    FROM pg_stat_user_tables
    WHERE schemaname = 'pggit'
    ORDER BY n_dead_tup DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 4: Cache Hit Ratio
-- ============================================

CREATE OR REPLACE FUNCTION pggit.cache_hit_ratio()
RETURNS TABLE (
    table_name TEXT,
    heap_read BIGINT,
    heap_hit BIGINT,
    hit_ratio NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        schemaname || '.' || relname,
        heap_blks_read,
        heap_blks_hit,
        CASE
            WHEN (heap_blks_hit + heap_blks_read) > 0
            THEN (heap_blks_hit::NUMERIC * 100 / (heap_blks_hit + heap_blks_read))::NUMERIC(5,2)
            ELSE 0
        END
    FROM pg_statio_user_tables
    WHERE schemaname = 'pggit'
    ORDER BY heap_blks_read DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 5: Connection Pool Monitoring
-- ============================================

CREATE OR REPLACE FUNCTION pggit.connection_stats()
RETURNS TABLE (
    state TEXT,
    count BIGINT,
    avg_duration INTERVAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(state, 'idle'),
        COUNT(*)::BIGINT,
        AVG(NOW() - state_change)
    FROM pg_stat_activity
    WHERE datname = current_database()
    GROUP BY state
    ORDER BY count DESC;
END;
$$ LANGUAGE plpgsql;
```

#### 5.2 Performance Tuning Guide

```markdown
# File: docs/guides/PERFORMANCE_TUNING.md

# Performance Tuning Guide

## Quick Diagnostics

\`\`\`sql
-- Check for slow queries (> 100ms)
SELECT * FROM pggit.analyze_slow_queries(100);

-- Verify index usage
SELECT * FROM pggit.check_index_usage();

-- Check vacuum health
SELECT * FROM pggit.vacuum_health();

-- Cache hit ratio (should be > 95%)
SELECT * FROM pggit.cache_hit_ratio();
\`\`\`

## Common Optimizations

### 1. Partition Large History Tables

If `pggit.history` exceeds 10M rows:

\`\`\`sql
-- Create partitioned history table
CREATE TABLE pggit.history_new (
    LIKE pggit.history INCLUDING ALL
) PARTITION BY RANGE (created_at);

-- Create monthly partitions
CREATE TABLE pggit.history_2025_01
    PARTITION OF pggit.history_new
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

-- Migrate data
INSERT INTO pggit.history_new SELECT * FROM pggit.history;

-- Swap tables
ALTER TABLE pggit.history RENAME TO history_old;
ALTER TABLE pggit.history_new RENAME TO history;
\`\`\`

### 2. Add Covering Indexes

\`\`\`sql
-- Index for version queries
CREATE INDEX IF NOT EXISTS idx_objects_name_version
    ON pggit.objects (object_name) INCLUDE (version);

-- Index for history by object
CREATE INDEX IF NOT EXISTS idx_history_object_time
    ON pggit.history (object_id, created_at DESC);
\`\`\`

### 3. Configure Connection Pooling

\`\`\`ini
# postgresql.conf
max_connections = 200
shared_buffers = 2GB
effective_cache_size = 6GB
maintenance_work_mem = 512MB
work_mem = 16MB

# pgBouncer recommended
pool_mode = transaction
default_pool_size = 25
max_client_conn = 200
\`\`\`

### 4. Monitor and Auto-Vacuum

\`\`\`sql
-- Ensure autovacuum is aggressive enough
ALTER TABLE pggit.history
    SET (autovacuum_vacuum_scale_factor = 0.05);
ALTER TABLE pggit.history
    SET (autovacuum_analyze_scale_factor = 0.02);
\`\`\`

## Benchmarking

\`\`\`bash
# Run baseline benchmarks
psql -f tests/benchmarks/baseline.sql

# Run load test
./scripts/performance/load-test.sh 1000  # 1000 concurrent DDL ops

# Profile specific query
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pggit.get_history('users');
\`\`\`
```

**Verification Commands**:

```bash
# Install performance helpers
psql -f sql/pggit_performance.sql

# Run diagnostics
psql -c "SELECT * FROM pggit.analyze_slow_queries()"
psql -c "SELECT * FROM pggit.cache_hit_ratio()"

# Run benchmarks
./scripts/performance/load-test.sh 100

# Expected output:
# ✅ PASS: Cache hit ratio > 95%
# ✅ PASS: All indexes used efficiently
# ✅ PASS: Load test handles 100 concurrent ops
```

**Acceptance Criteria**:
- [✅] Performance helper functions installed
- [✅] Query analysis tools available
- [✅] Tuning guide comprehensive
- [✅] Benchmark suite expanded
- [✅] Load testing scripts provided

---

### Step 6: Compliance & Hardening [EFFORT: HIGH]

**Goal**: FIPS compliance guidance, SOC2 preparation, security hardening.

#### 6.1 FIPS 140-2 Compliance

```markdown
# File: docs/compliance/FIPS_COMPLIANCE.md

# FIPS 140-2 Compliance Guide

## Overview

pgGit can be configured for FIPS 140-2 compliance when running on FIPS-enabled PostgreSQL.

## Requirements

### PostgreSQL FIPS Mode

1. **Build PostgreSQL with OpenSSL FIPS module**:

\`\`\`bash
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
\`\`\`

2. **Enable FIPS mode**:

\`\`\`bash
# In postgresql.conf
ssl = on
ssl_prefer_server_ciphers = on
ssl_ciphers = 'FIPS'
ssl_min_protocol_version = 'TLSv1.2'
\`\`\`

### pgGit FIPS Configuration

pgGit uses PostgreSQL's `pgcrypto` extension, which respects FIPS mode:

\`\`\`sql
-- Verify FIPS mode is active
SELECT setting
FROM pg_settings
WHERE name = 'ssl_ciphers';
-- Should return: FIPS

-- pgGit automatically uses FIPS-compliant algorithms
-- when PostgreSQL is in FIPS mode
\`\`\`

## Cryptographic Operations

All pgGit cryptographic operations use FIPS 140-2 approved algorithms:

| Operation | Algorithm | FIPS Status |
|-----------|-----------|-------------|
| Hashing | SHA-256 | ✅ Approved |
| Random | HMAC-DRBG | ✅ Approved |
| Encryption | AES-256 | ✅ Approved |

## Audit Trail

\`\`\`sql
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
\`\`\`

## Certification

pgGit itself is not FIPS 140-2 certified, but operates on certified components:
- PostgreSQL with FIPS-enabled OpenSSL (when configured)
- Operating system FIPS module

## Compliance Checklist

- [ ] PostgreSQL built with FIPS-enabled OpenSSL
- [ ] `ssl_ciphers = 'FIPS'` in postgresql.conf
- [ ] Verify `pgcrypto` uses FIPS algorithms
- [ ] Document FIPS configuration in operations runbook
- [ ] Regular FIPS compliance audits
\`\`\`
```

#### 6.2 SOC2 Preparation

```markdown
# File: docs/compliance/SOC2_PREPARATION.md

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
\`\`\`sql
-- Audit trail of who accessed what
SELECT created_by, change_type, COUNT(*)
FROM pggit.history
WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY created_by, change_type;
\`\`\`

**CC7.2 - System Monitoring**

pgGit provides:
- ✅ Health check monitoring (`pggit.health_check()`)
- ✅ Performance metrics collection
- ✅ Prometheus integration for alerting
- ✅ Automated anomaly detection

Evidence:
\`\`\`sql
SELECT * FROM pggit.system_overview();
\`\`\`

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
\`\`\`sql
-- Restrict access to history
REVOKE ALL ON pggit.history FROM public;
GRANT SELECT ON pggit.history TO pggit_auditors;
\`\`\`

## SOC2 Audit Evidence

### Required Documentation

1. **System Description**: README.md, architecture docs
2. **Security Policies**: SECURITY.md, access control guide
3. **Change Management**: Documented in pggit.history table
4. **Incident Response**: SECURITY.md vulnerability disclosure
5. **Monitoring**: MONITORING.md, SLO.md

### Audit Queries

\`\`\`sql
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
\`\`\`

## Preparation Checklist

- [ ] Document all trust service criteria mappings
- [ ] Implement evidence collection procedures
- [ ] Schedule quarterly access reviews
- [ ] Establish change management workflow
- [ ] Create incident response procedures
- [ ] Configure log retention (7 years for SOC2)
- [ ] Implement log forwarding to SIEM
\`\`\`
```

#### 6.3 Security Hardening Checklist

```markdown
# File: docs/security/HARDENING.md

# Security Hardening Checklist

## Database Level

- [ ] **Principle of Least Privilege**
  \`\`\`sql
  -- Revoke public access
  REVOKE ALL ON SCHEMA pggit FROM public;

  -- Grant only necessary permissions
  GRANT USAGE ON SCHEMA pggit TO app_user;
  GRANT SELECT ON pggit.objects TO app_user;
  \`\`\`

- [ ] **Row Level Security (RLS)**
  \`\`\`sql
  -- Enable RLS on sensitive tables
  ALTER TABLE pggit.history ENABLE ROW LEVEL SECURITY;

  -- Policy: Users see only their changes
  CREATE POLICY user_isolation ON pggit.history
    FOR SELECT
    USING (created_by = current_user);
  \`\`\`

- [ ] **Audit All DDL**
  \`\`\`sql
  -- Verify event triggers are active
  SELECT evtname, evtenabled
  FROM pg_event_trigger
  WHERE evtname LIKE 'pggit%';
  \`\`\`

- [ ] **Encrypted Connections Only**
  \`\`\`ini
  # postgresql.conf
  ssl = on
  ssl_prefer_server_ciphers = on
  ssl_min_protocol_version = 'TLSv1.2'
  \`\`\`

## Application Level

- [ ] **Input Validation**
  - All user inputs validated
  - Use `quote_ident()` for identifiers
  - Use `quote_literal()` or `format(%L)` for literals

- [ ] **No Dynamic SQL from User Input**
  \`\`\`sql
  -- ❌ NEVER DO THIS:
  EXECUTE 'DROP TABLE ' || user_input;

  -- ✅ DO THIS:
  EXECUTE format('DROP TABLE %I', quote_ident(user_input));
  \`\`\`

- [ ] **Rate Limiting**
  \`\`\`sql
  -- Limit DDL operations per user
  CREATE TABLE pggit.rate_limits (
      user_name TEXT PRIMARY KEY,
      last_reset TIMESTAMP DEFAULT NOW(),
      operation_count INT DEFAULT 0
  );
  \`\`\`

## Infrastructure Level

- [ ] **Regular Security Updates**
  - PostgreSQL patched to latest minor version
  - OS security updates applied weekly
  - pgGit updated to latest release

- [ ] **Firewall Rules**
  - PostgreSQL port (5432) restricted to app servers
  - No direct internet access to database

- [ ] **Secrets Management**
  - Database passwords in vault (HashiCorp Vault, AWS Secrets Manager)
  - No passwords in code or config files

- [ ] **Monitoring & Alerting**
  - Failed login attempts monitored
  - Unusual query patterns detected
  - Performance anomalies alerted

## Compliance Level

- [ ] **Data Retention**
  \`\`\`sql
  -- Archive old history (GDPR: right to be forgotten)
  CREATE TABLE pggit.history_archive (LIKE pggit.history);

  -- Move data older than 7 years
  INSERT INTO pggit.history_archive
  SELECT * FROM pggit.history
  WHERE created_at < NOW() - INTERVAL '7 years';

  DELETE FROM pggit.history
  WHERE created_at < NOW() - INTERVAL '7 years';
  \`\`\`

- [ ] **Privacy by Design**
  - Personal data minimization
  - No unnecessary PII in metadata

- [ ] **Audit Logging**
  - All access logged
  - Logs immutable (append-only)
  - Log retention policy enforced
\`\`\`
```

**Verification Commands**:

```bash
# Verify FIPS mode
psql -c "SHOW ssl_ciphers"

# Run SOC2 audit queries
psql -f docs/compliance/SOC2_PREPARATION.md

# Security hardening check
./scripts/security/hardening-check.sh

# Expected output:
# ✅ PASS: FIPS mode enabled (if configured)
# ✅ PASS: All SOC2 evidence collected
# ✅ PASS: Security hardening complete
```

**Acceptance Criteria**:
- [✅] FIPS 140-2 compliance guide complete
- [✅] SOC2 preparation documentation ready
- [✅] Security hardening checklist comprehensive
- [✅] Compliance audit queries provided
- [✅] Evidence collection automated

---

## Rollback Strategy

### Per-Step Rollback

Each step is independent and can be rolled back individually:

```bash
# Step 1: Remove SBOM
git revert <sbom-commit>
rm SBOM.json .github/workflows/sbom.yml

# Step 2: Remove security scanning
git revert <security-commit>
rm .github/workflows/security-scan.yml

# Step 3: Remove IDE configs
git revert <ide-commit>
rm -rf .vscode/ .idea/ .editorconfig

# Step 4: Remove operational docs
git revert <ops-commit>
rm docs/operations/SLO.md docs/operations/RUNBOOK.md

# Step 5: Remove performance tools
git revert <perf-commit>
psql -c "DROP FUNCTION pggit.analyze_slow_queries()"

# Step 6: Remove compliance docs
git revert <compliance-commit>
rm docs/compliance/*.md
```

### Phase-Wide Rollback

```bash
# Tag before starting
git tag phase-4-start

# If complete rollback needed
git reset --hard phase-4-start
git push origin main --force-with-lease

# Verify rollback
test ! -f SBOM.json && echo "✅ Rollback complete"
```

---

## Acceptance Criteria

### Security & Supply Chain
- [ ] SBOM generated in CycloneDX format
- [ ] SBOM signed with Cosign
- [ ] SLSA Level 3 provenance attestation
- [ ] Trivy vulnerability scanning in CI
- [ ] CodeQL SQL analysis enabled
- [ ] Dependency review on PRs
- [ ] SQL injection test suite passing

### Developer Experience
- [ ] VS Code extensions recommended
- [ ] IDE settings configured
- [ ] EditorConfig for all editors
- [ ] Extension template provided
- [ ] Debugging guide comprehensive
- [ ] JetBrains IDE support (optional)

### Operations
- [ ] SLOs defined and measurable
- [ ] Runbook for common scenarios
- [ ] Chaos engineering tests passing
- [ ] Connection pool monitoring
- [ ] Performance regression tests

### Performance
- [ ] Query analysis tools available
- [ ] Index usage monitoring
- [ ] Cache hit ratio monitoring
- [ ] Load testing scripts provided
- [ ] Tuning guide comprehensive

### Compliance
- [ ] FIPS 140-2 compliance guide
- [ ] SOC2 preparation documentation
- [ ] Security hardening checklist
- [ ] Compliance audit queries
- [ ] Evidence collection automated

---

## Success Metrics

| Metric | Current | Target | How to Verify | Achieved |
|--------|---------|--------|---------------|----------|
| SBOM Coverage | 0% | 100% | All dependencies listed | [ ] |
| Vulnerability Scan | Manual | Automated | Daily Trivy scans | [ ] |
| Developer Setup Time | Unknown | < 10 min | IDE setup + first commit | [ ] |
| SLO Compliance | Unknown | 99.9% | Monthly SLO reports | [ ] |
| Performance P95 | Unknown | < 50ms | Benchmark suite | [ ] |
| Security Hardening | Partial | Complete | All checklist items | [ ] |
| Overall Quality | 9.0/10 | 9.5/10 | All above metrics met | [ ] |

---

## Next Phase

After Phase 4 → **Continuous Excellence**
- Monthly security audits
- Quarterly performance reviews
- Annual compliance assessments
- Community feedback integration
- Advanced features based on user needs

---

## Estimated Effort

**Total**: 3-4 weeks (MEDIUM-HIGH effort)

**Breakdown**:
- Step 1 (SBOM): 1 week (HIGH - learning curve for SLSA)
- Step 2 (Security): 3-4 days (MEDIUM - integrate tools)
- Step 3 (Dev Experience): 2-3 days (LOW-MEDIUM - configuration)
- Step 4 (Operations): 4-5 days (MEDIUM - write runbooks)
- Step 5 (Performance): 4-5 days (MEDIUM - profiling tools)
- Step 6 (Compliance): 1 week (HIGH - detailed documentation)

**Note**: All effort estimates are for implementation, not timelines. Focus on quality over speed.

---

**Phase Owner**: TBD
**Target Quality**: 9.5/10
**Focus**: Excellence through security, compliance, and developer experience
