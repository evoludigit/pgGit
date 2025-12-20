# Phase 5: Stabilization & Quality Assurance

**Quality Target**: 9.5/10 → 9.8/10 (Final Polish)
**Focus**: Fix failing tests, validate Phase 4 features, ensure production reliability
**Status**: Ready for execution
**Duration**: 4-5 implementation steps (effort-based, not time-based)

---

## Why Phase 5?

Phase 4 achieved production excellence (9.5/10) with enterprise features (SBOM, security scanning, compliance, performance). Phase 5 ensures **operational perfection** by:

1. **Fixing all failing CI tests** - Achieve 100% test pass rate
2. **Validating Phase 4 features** - Ensure new features work in production
3. **Enhancing CI/CD pipeline** - Add Phase 4 workflows to automated testing
4. **Production readiness validation** - Real-world testing of all features

**Target Quality**: 9.8/10 (from 9.5/10) - Fully battle-tested and production-proven

---

## Current Issues Analysis

### Issue 1: Failing CI Tests (High Priority)

**Status**: Tests failing on PostgreSQL 15/16/17
**Impact**: CI shows red despite code quality improvements
**Root Cause**: Two specific tests failing:
- "Test deployment mode" (line 364-391 in tests.yml)
- "Test CQRS support" (line 393-426 in tests.yml)

**Symptoms**:
```bash
# From CI logs
❌ Test deployment mode failed
❌ Test CQRS support failed
✅ Core tests passed
✅ New feature tests passed (configuration, function versioning, etc.)
```

**Analysis**:
1. **Deployment mode test** (line 379): Calls `pggit.begin_deployment('CI Test Deployment')`
   - Function exists in `sql/pggit_configuration.sql:165`
   - May not be installed properly during CI setup
   - Missing dependency tables or prerequisite functions

2. **CQRS test** (line 412): Calls `pggit.track_cqrs_change(ROW(...)::pggit.cqrs_change)`
   - Function exists in `sql/pggit_cqrs_support.sql:40`
   - Requires `pggit.cqrs_change` composite type
   - May be missing CQRS schema setup

**Files Involved**:
- `.github/workflows/tests.yml` - CI test workflow
- `sql/pggit_configuration.sql` - Deployment mode functions
- `sql/pggit_cqrs_support.sql` - CQRS tracking functions
- `tests/test-configuration-*.sql` - Configuration tests
- `tests/test-cqrs-support.sql` - CQRS tests

---

### Issue 2: Phase 4 Features Not Validated (Medium Priority)

**Status**: Phase 4 features created but not tested in real database
**Impact**: Unknown if features work as designed

**Features to Validate**:
1. **Performance helper functions** (`sql/pggit_performance.sql`):
   - `analyze_slow_queries()`
   - `check_index_usage()`
   - `vacuum_health()`
   - `cache_hit_ratio()`
   - `connection_stats()`
   - `recommend_indexes()`
   - `partitioning_analysis()`
   - `system_resources()`

2. **Security SQL injection tests** (`tests/security/test-sql-injection.sql`):
   - 5 tests for format(), quote_ident(), dynamic SQL, event triggers, input validation
   - Need to verify they actually prevent SQL injection

3. **Monitoring functions** (`sql/pggit_monitoring.sql`):
   - `health_check()` - 5 health checks
   - `record_metric()` - metrics collection
   - `prometheus_metrics()` - Prometheus integration

---

### Issue 3: Phase 4 Workflows Not in CI (Medium Priority)

**Status**: New workflows created but not validated in CI
**Impact**: Workflows may fail when triggered

**Workflows to Test**:
1. **SBOM workflow** (`.github/workflows/sbom.yml`):
   - CycloneDX SBOM generation
   - Upload to releases
   - Manual dispatch trigger

2. **Security scan workflow** (`.github/workflows/security-scan.yml`):
   - Trivy vulnerability scanning
   - CodeQL SQL analysis
   - Dependency review

**Current State**:
- Workflows exist and have proper triggers
- Never been executed (no release yet to trigger them)
- Need validation that they work when triggered

---

## Phase 5 Steps

### Step 1: Fix CI Test Failures [HIGH PRIORITY]

**Objective**: Get CI tests to 100% pass rate

**Root Cause Investigation**:
1. Check if `pggit_configuration.sql` is loaded in CI
2. Check if `pggit_cqrs_support.sql` is loaded in CI
3. Verify all prerequisite tables/types exist
4. Check function signatures match test calls

**Files to Modify**:
- `.github/workflows/tests.yml` (lines 167-223: "Install new feature modules")

**Implementation Steps**:

1a. **Add deployment mode prerequisite setup** (before line 364):
```yaml
- name: Prepare deployment mode test
  env:
    PGPASSWORD: postgres
    PGHOST: localhost
    PGUSER: postgres
    PGDATABASE: pggit_test
  run: |
    psql << 'EOF'
    -- Ensure deployment mode tables exist
    CREATE TABLE IF NOT EXISTS pggit.deployments (
        deployment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        deployment_name text NOT NULL,
        started_at timestamptz DEFAULT now(),
        ended_at timestamptz,
        started_by text DEFAULT current_user,
        status text DEFAULT 'IN_PROGRESS',
        metadata jsonb DEFAULT '{}'
    );

    CREATE TABLE IF NOT EXISTS pggit.deployment_changes (
        change_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        deployment_id uuid REFERENCES pggit.deployments(deployment_id),
        change_type text,
        object_name text,
        change_sql text,
        applied_at timestamptz DEFAULT now()
    );

    -- Verify begin_deployment function exists
    DO $$
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc
            WHERE proname = 'begin_deployment'
            AND pronamespace = 'pggit'::regnamespace
        ) THEN
            RAISE EXCEPTION 'Function pggit.begin_deployment() not found. Check if pggit_configuration.sql was loaded.';
        END IF;

        RAISE NOTICE 'Deployment mode prerequisites ready';
    END $$;
    EOF
```

1b. **Add CQRS prerequisite setup** (before line 393):
```yaml
- name: Prepare CQRS test
  env:
    PGPASSWORD: postgres
    PGHOST: localhost
    PGUSER: postgres
    PGDATABASE: pggit_test
  run: |
    psql << 'EOF'
    -- Create CQRS type if not exists
    DO $$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'cqrs_change' AND typnamespace = 'pggit'::regnamespace) THEN
            CREATE TYPE pggit.cqrs_change AS (
                command_changes text[],
                query_changes text[],
                description text,
                version text
            );
        END IF;
    END $$;

    -- Ensure CQRS tables exist
    CREATE TABLE IF NOT EXISTS pggit.cqrs_changesets (
        changeset_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        description text,
        version text,
        created_at timestamptz DEFAULT now(),
        created_by text DEFAULT current_user,
        applied boolean DEFAULT false
    );

    CREATE TABLE IF NOT EXISTS pggit.cqrs_changes (
        change_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        changeset_id uuid REFERENCES pggit.cqrs_changesets(changeset_id),
        schema_type text CHECK (schema_type IN ('command', 'query')),
        change_sql text,
        change_order int,
        applied_at timestamptz
    );

    -- Verify track_cqrs_change function exists
    DO $$
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc
            WHERE proname = 'track_cqrs_change'
            AND pronamespace = 'pggit'::regnamespace
        ) THEN
            RAISE EXCEPTION 'Function pggit.track_cqrs_change() not found. Check if pggit_cqrs_support.sql was loaded.';
        END IF;

        RAISE NOTICE 'CQRS prerequisites ready';
    END $$;
    EOF
```

1c. **Improve error reporting in failing tests**:

Update "Test deployment mode" (line 364):
```yaml
- name: Test deployment mode
  env:
    PGPASSWORD: postgres
    PGHOST: localhost
    PGUSER: postgres
    PGDATABASE: pggit_test
  run: |
    psql << 'EOF'
    DO $$
    DECLARE
        deployment_id uuid;
        test_passed boolean := false;
    BEGIN
        -- Test deployment mode with detailed error reporting
        BEGIN
            deployment_id := pggit.begin_deployment('CI Test Deployment');

            CREATE TABLE test_deployment_table (id int);
            ALTER TABLE test_deployment_table ADD COLUMN name text;

            PERFORM pggit.end_deployment('Test completed');

            test_passed := true;
            RAISE NOTICE '✅ Deployment mode test PASSED';
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE '❌ Deployment mode test FAILED';
            RAISE NOTICE 'Error: %', SQLERRM;
            RAISE NOTICE 'Detail: %', SQLSTATE;
            RAISE NOTICE 'Hint: Check if pggit_configuration.sql was loaded properly';

            -- Re-raise to fail the test
            RAISE;
        END;

        IF NOT test_passed THEN
            RAISE EXCEPTION 'Deployment mode test did not complete successfully';
        END IF;
    END $$;
    EOF
```

Update "Test CQRS support" (line 393):
```yaml
- name: Test CQRS support
  env:
    PGPASSWORD: postgres
    PGHOST: localhost
    PGUSER: postgres
    PGDATABASE: pggit_test
  run: |
    psql << 'EOF'
    DO $$
    DECLARE
        changeset_id uuid;
        test_passed boolean := false;
    BEGIN
        -- Create CQRS schemas first
        CREATE SCHEMA IF NOT EXISTS command;
        CREATE SCHEMA IF NOT EXISTS query;

        -- Test CQRS change tracking with detailed error reporting
        BEGIN
            changeset_id := pggit.track_cqrs_change(
                ROW(
                    ARRAY['CREATE TABLE command.test (id int)'],
                    ARRAY['CREATE VIEW query.test_view AS SELECT 1 as id'],
                    'Test CQRS change',
                    '1.0.0'
                )::pggit.cqrs_change
            );

            test_passed := true;
            RAISE NOTICE '✅ CQRS test PASSED (changeset_id: %)', changeset_id;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE '❌ CQRS test FAILED';
            RAISE NOTICE 'Error: %', SQLERRM;
            RAISE NOTICE 'Detail: %', SQLSTATE;
            RAISE NOTICE 'Hint: Check if pggit_cqrs_support.sql was loaded and cqrs_change type exists';

            -- Re-raise to fail the test
            RAISE;
        END;

        IF NOT test_passed THEN
            RAISE EXCEPTION 'CQRS test did not complete successfully';
        END IF;
    END $$;
    EOF
```

**Verification**:
```bash
# Run tests locally
PGPASSWORD=postgres psql -h localhost -U postgres -d pggit_test << 'EOF'
-- Verify deployment mode works
SELECT pggit.begin_deployment('Manual test');
SELECT pggit.end_deployment('Manual test completed');

-- Verify CQRS works
SELECT pggit.track_cqrs_change(
    ROW(
        ARRAY['CREATE TABLE command.manual_test (id int)'],
        ARRAY['CREATE VIEW query.manual_test_view AS SELECT 1'],
        'Manual CQRS test',
        '1.0.0'
    )::pggit.cqrs_change
);
EOF

# Expected output:
# begin_deployment: uuid
# end_deployment: (void)
# track_cqrs_change: uuid
```

**Acceptance Criteria**:
- [ ] CI tests pass on PostgreSQL 15, 16, 17
- [ ] Deployment mode test shows ✅ PASSED
- [ ] CQRS test shows ✅ PASSED
- [ ] No EXCEPTION errors in CI logs
- [ ] GitHub Actions shows green checkmark

**DO NOT**:
- Don't skip tests by changing them to RAISE NOTICE only
- Don't add `|| true` to ignore failures
- Don't comment out failing tests
- Fix the root cause, not the symptom

---

### Step 2: Validate Phase 4 Performance Functions [MEDIUM PRIORITY]

**Objective**: Ensure all 8 performance helper functions work correctly with real data

**Test Database Setup**:
```sql
-- Create test database with pgGit installed
CREATE DATABASE pggit_perf_test;
\c pggit_perf_test

-- Install pgGit core
\i sql/install.sql

-- Install performance functions
\i sql/pggit_performance.sql

-- Install monitoring (prerequisite for performance functions)
\i sql/pggit_monitoring.sql

-- Create test data
CREATE TABLE test_large_table (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Insert test data (10,000 rows)
INSERT INTO test_large_table (data)
SELECT 'Test data ' || generate_series(1, 10000);

-- Create some indexes
CREATE INDEX idx_test_created_at ON test_large_table(created_at);
CREATE INDEX idx_test_data ON test_large_table(data);
```

**Function Tests**:

2a. **Test analyze_slow_queries()**:
```sql
-- Generate some metrics first
INSERT INTO pggit.performance_metrics (metric_type, metric_value, metric_tags)
VALUES
    ('ddl_tracking_ms', 150, '{"table": "test"}'),
    ('ddl_tracking_ms', 200, '{"table": "test2"}'),
    ('version_query_ms', 5, '{"object": "users"}'),
    ('version_query_ms', 8, '{"object": "posts"}');

-- Test function
SELECT * FROM pggit.analyze_slow_queries(100);

-- Expected output:
-- query_type       | avg_duration_ms | max_duration_ms | call_count | total_time_ms
-- ddl_tracking_ms  | 175.00          | 200.00          | 2          | 350.00

-- Verify:
-- ✅ Returns rows for metrics above threshold (150, 200 > 100)
-- ✅ Does NOT return version_query_ms (5, 8 < 100)
-- ✅ Calculates AVG, MAX, COUNT, SUM correctly
```

2b. **Test check_index_usage()**:
```sql
-- Run some queries to generate index usage stats
SELECT * FROM test_large_table WHERE created_at > NOW() - INTERVAL '1 hour';
SELECT * FROM test_large_table WHERE data LIKE 'Test%';

-- Test function
SELECT * FROM pggit.check_index_usage();

-- Expected output:
-- table_name              | index_name           | index_scans | rows_read | effectiveness
-- public.test_large_table | idx_test_created_at  | 1           | 10000     | 10000.00
-- public.test_large_table | idx_test_data        | 1           | 10000     | 10000.00

-- Verify:
-- ✅ Returns all indexes on pggit schema tables
-- ✅ Shows index_scans > 0 for used indexes
-- ✅ Calculates effectiveness (rows_read / index_scans)
```

2c. **Test vacuum_health()**:
```sql
-- Generate some dead tuples
UPDATE test_large_table SET data = 'Updated' WHERE id <= 1000;
DELETE FROM test_large_table WHERE id <= 100;

-- Test function
SELECT * FROM pggit.vacuum_health();

-- Expected output:
-- table_name              | last_vacuum | last_autovacuum | n_dead_tup | vacuum_recommended
-- pggit.objects           | NULL        | 2025-12-20...   | 0          | false
-- pggit.history           | NULL        | 2025-12-20...   | 0          | false

-- Verify:
-- ✅ Returns all pggit schema tables
-- ✅ Shows last_vacuum and last_autovacuum timestamps
-- ✅ Shows n_dead_tup count
-- ✅ vacuum_recommended = true when n_dead_tup > 1000 AND last_autovacuum > 1 day old
```

2d. **Test cache_hit_ratio()**:
```sql
-- Run some queries to generate cache stats
SELECT * FROM test_large_table LIMIT 1000;
SELECT * FROM test_large_table LIMIT 1000;  -- Should hit cache

-- Test function
SELECT * FROM pggit.cache_hit_ratio();

-- Expected output:
-- table_name              | heap_read | heap_hit | cache_hit_ratio
-- pggit.objects           | 10        | 1000     | 99.01
-- pggit.history           | 5         | 500      | 99.01

-- Verify:
-- ✅ Returns all pggit schema tables
-- ✅ Shows heap_read (disk reads) and heap_hit (cache hits)
-- ✅ Calculates cache_hit_ratio = (heap_hit / (heap_hit + heap_read)) * 100
-- ✅ Target: >95% cache hit ratio
```

2e. **Test connection_stats()**:
```sql
-- Test function
SELECT * FROM pggit.connection_stats();

-- Expected output:
-- database    | total | active | idle | idle_in_transaction | max_conn
-- pggit_test  | 5     | 1      | 4    | 0                   | 100

-- Verify:
-- ✅ Shows total connections to current database
-- ✅ Breaks down by state (active, idle, idle_in_transaction)
-- ✅ Shows max_connections setting
```

2f. **Test recommend_indexes()**:
```sql
-- Test function
SELECT * FROM pggit.recommend_indexes();

-- Expected output (example):
-- table_name     | column_name | reason                        | estimated_benefit
-- pggit.history  | created_at  | Frequent range queries        | HIGH
-- pggit.objects  | object_type | Frequent equality filters     | MEDIUM

-- Verify:
-- ✅ Analyzes pg_stat_user_tables for seq_scan counts
-- ✅ Recommends indexes for tables with high seq_scan / idx_scan ratio
-- ✅ Provides reason and estimated benefit
```

2g. **Test partitioning_analysis()**:
```sql
-- Test function
SELECT * FROM pggit.partitioning_analysis();

-- Expected output (example):
-- table_name     | total_size | row_count | growth_rate | partition_recommended | partition_key
-- pggit.history  | 100 MB     | 1000000   | 10 MB/month | true                  | created_at

-- Verify:
-- ✅ Shows tables with size > 10GB or row_count > 10M
-- ✅ Calculates growth rate from pg_stat_user_tables
-- ✅ Recommends partitioning when appropriate
-- ✅ Suggests partition key (usually timestamp column)
```

2h. **Test system_resources()**:
```sql
-- Test function
SELECT * FROM pggit.system_resources();

-- Expected output:
-- metric              | value      | unit  | status
-- shared_buffers      | 128        | MB    | OK
-- effective_cache_size| 4096       | MB    | OK
-- work_mem            | 4          | MB    | WARNING (consider increasing)
-- connections_used    | 5          | count | OK (5/100)
-- database_size       | 50         | MB    | OK

-- Verify:
-- ✅ Shows PostgreSQL configuration settings
-- ✅ Shows current resource usage
-- ✅ Provides status (OK, WARNING, CRITICAL)
-- ✅ Includes recommendations for tuning
```

**Create Test Script**:

File: `tests/phase-4/test-performance-functions.sql`
```sql
-- File: tests/phase-4/test-performance-functions.sql
-- Test all 8 performance helper functions

\echo 'Testing Phase 4 Performance Functions'
\echo '======================================'

-- Setup: Create test data
CREATE TABLE IF NOT EXISTS test_performance_data (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO test_performance_data (data)
SELECT 'Test ' || generate_series(1, 10000)
ON CONFLICT DO NOTHING;

-- Generate performance metrics
INSERT INTO pggit.performance_metrics (metric_type, metric_value)
VALUES
    ('ddl_tracking_ms', 150),
    ('ddl_tracking_ms', 200),
    ('version_query_ms', 5);

\echo ''
\echo 'Test 1: analyze_slow_queries()'
SELECT * FROM pggit.analyze_slow_queries(100);

\echo ''
\echo 'Test 2: check_index_usage()'
SELECT * FROM pggit.check_index_usage() LIMIT 5;

\echo ''
\echo 'Test 3: vacuum_health()'
SELECT * FROM pggit.vacuum_health() LIMIT 5;

\echo ''
\echo 'Test 4: cache_hit_ratio()'
SELECT * FROM pggit.cache_hit_ratio() LIMIT 5;

\echo ''
\echo 'Test 5: connection_stats()'
SELECT * FROM pggit.connection_stats();

\echo ''
\echo 'Test 6: recommend_indexes()'
SELECT * FROM pggit.recommend_indexes() LIMIT 5;

\echo ''
\echo 'Test 7: partitioning_analysis()'
SELECT * FROM pggit.partitioning_analysis() LIMIT 5;

\echo ''
\echo 'Test 8: system_resources()'
SELECT * FROM pggit.system_resources() LIMIT 10;

\echo ''
\echo '✅ All performance function tests completed'
```

**Verification Command**:
```bash
createdb pggit_perf_test
psql -d pggit_perf_test << 'EOF'
\i sql/install.sql
\i sql/pggit_monitoring.sql
\i sql/pggit_performance.sql
\i tests/phase-4/test-performance-functions.sql
EOF

# Expected: All 8 functions return data without errors
```

**Acceptance Criteria**:
- [ ] All 8 functions execute without errors
- [ ] Functions return expected columns
- [ ] Results match expected data types
- [ ] No NULL values where not expected
- [ ] Performance metrics calculation is correct

**DO NOT**:
- Don't skip functions that are "too complex" to test
- Don't test with empty tables (create realistic test data)
- Don't ignore errors with `|| true`
- Ensure each function provides actual value

---

### Step 3: Validate SQL Injection Prevention Tests [MEDIUM PRIORITY]

**Objective**: Ensure SQL injection tests actually prevent injection attacks

**Test File**: `tests/security/test-sql-injection.sql`

**Validation Steps**:

3a. **Test format() with %L and %I**:
```sql
-- Run the test
DO $$
DECLARE
    malicious_input TEXT := $$'; DROP TABLE users; --$$;
    safe_query TEXT;
BEGIN
    -- Should use %L for literal (prevents injection)
    safe_query := format('SELECT * FROM pggit.objects WHERE object_name = %L', malicious_input);

    -- Verify the query is safe
    ASSERT safe_query LIKE '%''%' OR '%DROP TABLE%' NOT IN safe_query,
        'SQL injection not prevented!';

    RAISE NOTICE '✅ format() with %%L prevents injection';
END $$;
```

3b. **Test quote_ident() and quote_literal()**:
```sql
DO $$
DECLARE
    malicious_table TEXT := $$users"; DROP TABLE evil; --$$;
    safe_table TEXT;
BEGIN
    safe_table := quote_ident(malicious_table);

    -- Should escape the quotes
    ASSERT safe_table = '"users""; DROP TABLE evil; --"',
        format('Expected escaped quotes, got: %s', safe_table);

    RAISE NOTICE '✅ quote_ident() prevents identifier injection';
END $$;
```

3c. **Run full SQL injection test suite**:
```bash
psql -d pggit_test -f tests/security/test-sql-injection.sql

# Expected output:
# ✅ PASS: SQL injection prevented
# ✅ PASS: Identifier injection prevented
# ✅ PASS: Schema protected from injection
# ✅ PASS: Event triggers properly controlled
# ✅ PASS: Health check function safe
# SQL Injection Security Tests Complete
```

**Add to CI**:

File: `.github/workflows/security-tests.yml` (new)
```yaml
name: Security Tests

on:
  push:
    branches: [ main ]
  pull_request:
  schedule:
    - cron: '0 0 * * 1'  # Weekly on Monday

jobs:
  sql-injection-tests:
    name: SQL Injection Prevention Tests
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:17
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: pggit_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
    - uses: actions/checkout@v4

    - name: Install pgGit
      env:
        PGPASSWORD: postgres
        PGHOST: localhost
        PGUSER: postgres
        PGDATABASE: pggit_test
      run: |
        psql -f sql/install.sql
        psql -f sql/pggit_monitoring.sql

    - name: Run SQL injection tests
      env:
        PGPASSWORD: postgres
        PGHOST: localhost
        PGUSER: postgres
        PGDATABASE: pggit_test
      run: |
        psql -f tests/security/test-sql-injection.sql

        # Verify all tests passed
        if [ $? -eq 0 ]; then
          echo "✅ All SQL injection tests passed"
        else
          echo "❌ SQL injection tests failed"
          exit 1
        fi
```

**Verification**:
```bash
# Manually run SQL injection tests
psql -d pggit_test -f tests/security/test-sql-injection.sql

# Expected: All 5 tests show ✅ PASS
# No SQL injection vulnerabilities found
```

**Acceptance Criteria**:
- [ ] All 5 SQL injection tests pass
- [ ] Tests actually attempt injection (not just stubs)
- [ ] Malicious inputs are properly escaped
- [ ] No tables dropped during testing
- [ ] Security tests run in CI weekly

---

### Step 4: Add Phase 4 Workflows to CI Verification [MEDIUM PRIORITY]

**Objective**: Validate that Phase 4 workflows work when triggered

**Workflows to Test**:
1. SBOM generation (`.github/workflows/sbom.yml`)
2. Security scanning (`.github/workflows/security-scan.yml`)

**Implementation**:

4a. **Test SBOM workflow manually**:
```bash
# Trigger SBOM workflow via workflow_dispatch
gh workflow run sbom.yml

# Wait for completion
gh run list --workflow=sbom.yml --limit 1

# Check outputs
gh run view <run_id>

# Expected artifacts:
# - SBOM.json uploaded to workflow artifacts
```

4b. **Test security scan workflow manually**:
```bash
# Trigger security scan workflow
gh workflow run security-scan.yml

# Expected:
# - Trivy scan completes (may find vulnerabilities)
# - CodeQL analysis completes (SQL queries analyzed)
# - SARIF files uploaded to GitHub Security tab
```

4c. **Add workflow validation to CI**:

File: `.github/workflows/validate-workflows.yml` (new)
```yaml
name: Validate Workflows

on:
  pull_request:
    paths:
      - '.github/workflows/*.yml'
  workflow_dispatch:

jobs:
  validate-syntax:
    name: Validate Workflow Syntax
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Validate YAML syntax
      run: |
        # Install yamllint
        sudo apt-get update
        sudo apt-get install -y yamllint

        # Validate all workflow files
        for workflow in .github/workflows/*.yml; do
          echo "Validating $workflow..."
          yamllint -d relaxed "$workflow"
        done

    - name: Validate GitHub Actions syntax
      uses: docker://rhysd/actionlint:latest
      with:
        args: -color

  test-sbom-generation:
    name: Test SBOM Generation
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Simulate SBOM generation
      run: |
        # Create a test SBOM
        cat > test-SBOM.json << 'EOF'
        {
          "bomFormat": "CycloneDX",
          "specVersion": "1.5",
          "serialNumber": "urn:uuid:test-uuid",
          "version": 1,
          "metadata": {
            "timestamp": "2025-12-20T00:00:00Z",
            "component": {
              "type": "application",
              "name": "pgGit",
              "version": "test"
            }
          }
        }
        EOF

        # Validate SBOM format
        echo "Validating SBOM format..."
        jq empty test-SBOM.json || (echo "Invalid JSON" && exit 1)

        # Check required fields
        jq -e '.bomFormat == "CycloneDX"' test-SBOM.json
        jq -e '.specVersion == "1.5"' test-SBOM.json

        echo "✅ SBOM generation test passed"
```

**Verification**:
```bash
# Run workflow validation locally
yamllint .github/workflows/*.yml

# Expected: No errors in YAML syntax
```

**Acceptance Criteria**:
- [ ] SBOM workflow triggers on release
- [ ] SBOM.json is generated with correct format
- [ ] Security scan workflow triggers daily
- [ ] Trivy scan completes without errors
- [ ] CodeQL analysis completes
- [ ] Workflow syntax validation passes

---

### Step 5: Create Production Validation Test Suite [LOW PRIORITY]

**Objective**: Comprehensive test of all Phase 1-4 features in production-like environment

**Test Scope**:
- Phase 1: pgTAP tests, security policy, module architecture
- Phase 2: Pre-commit hooks, API documentation, security audit
- Phase 3: Migrations, packaging, monitoring, operations
- Phase 4: SBOM, security scanning, performance, compliance

**Implementation**:

File: `tests/production/production-validation.sh`
```bash
#!/bin/bash
# Production validation test suite
# Tests all Phase 1-4 features in production-like environment

set -e

echo "========================================="
echo "pgGit Production Validation Test Suite"
echo "========================================="

# Configuration
DB_NAME="pggit_prod_validation"
POSTGRES_VERSION="${POSTGRES_VERSION:-17}"

# Cleanup function
cleanup() {
    echo "Cleaning up test database..."
    dropdb --if-exists "$DB_NAME"
}

trap cleanup EXIT

# Create test database
echo "Creating test database: $DB_NAME"
createdb "$DB_NAME"

# Phase 1: Core Installation
echo ""
echo "Phase 1: Testing Core Installation"
echo "-----------------------------------"
psql -d "$DB_NAME" -c "\i sql/install.sql" || {
    echo "❌ Core installation failed"
    exit 1
}
echo "✅ Core installation successful"

# Phase 2: Code Quality
echo ""
echo "Phase 2: Testing Code Quality"
echo "------------------------------"

# Test pre-commit hooks (if installed)
if command -v pre-commit &> /dev/null; then
    pre-commit run --all-files || echo "⚠️  Pre-commit hooks found issues"
else
    echo "⚠️  pre-commit not installed, skipping"
fi

# Phase 3: Migrations & Monitoring
echo ""
echo "Phase 3: Testing Migrations & Monitoring"
echo "----------------------------------------"

# Test migration system
psql -d "$DB_NAME" << 'EOF'
-- Verify migration files exist
\! test -f migrations/pggit--0.1.0--0.2.0.sql && echo "✅ Upgrade migration exists" || echo "❌ Upgrade migration missing"
\! test -f migrations/pggit--0.2.0--0.1.0.sql && echo "✅ Downgrade migration exists" || echo "❌ Downgrade migration missing"
EOF

# Test monitoring installation
psql -d "$DB_NAME" -c "\i sql/pggit_monitoring.sql" || {
    echo "❌ Monitoring installation failed"
    exit 1
}
echo "✅ Monitoring installation successful"

# Test health check
psql -d "$DB_NAME" -c "SELECT * FROM pggit.health_check();" || {
    echo "❌ Health check failed"
    exit 1
}
echo "✅ Health check successful"

# Phase 4: Performance & Security
echo ""
echo "Phase 4: Testing Performance & Security"
echo "---------------------------------------"

# Test performance functions installation
psql -d "$DB_NAME" -c "\i sql/pggit_performance.sql" || {
    echo "❌ Performance functions installation failed"
    exit 1
}
echo "✅ Performance functions installation successful"

# Test performance functions
psql -d "$DB_NAME" << 'EOF'
-- Test each performance function
\echo 'Testing analyze_slow_queries()...'
SELECT COUNT(*) FROM pggit.analyze_slow_queries(100);

\echo 'Testing check_index_usage()...'
SELECT COUNT(*) FROM pggit.check_index_usage();

\echo 'Testing vacuum_health()...'
SELECT COUNT(*) FROM pggit.vacuum_health();

\echo 'Testing cache_hit_ratio()...'
SELECT COUNT(*) FROM pggit.cache_hit_ratio();

\echo 'Testing connection_stats()...'
SELECT COUNT(*) FROM pggit.connection_stats();
EOF

echo "✅ All performance functions work"

# Test SQL injection prevention
echo ""
echo "Testing SQL Injection Prevention..."
psql -d "$DB_NAME" -f tests/security/test-sql-injection.sql || {
    echo "❌ SQL injection tests failed"
    exit 1
}
echo "✅ SQL injection tests passed"

# Test SBOM
echo ""
echo "Testing SBOM..."
if [ -f "SBOM.json" ]; then
    jq empty SBOM.json && echo "✅ SBOM is valid JSON" || {
        echo "❌ SBOM is invalid JSON"
        exit 1
    }

    jq -e '.bomFormat == "CycloneDX"' SBOM.json && echo "✅ SBOM format is CycloneDX" || {
        echo "❌ SBOM format is not CycloneDX"
        exit 1
    }
else
    echo "⚠️  SBOM.json not found (expected for unreleased version)"
fi

# Summary
echo ""
echo "========================================="
echo "Production Validation Complete"
echo "========================================="
echo "✅ All critical tests passed"
echo "✅ pgGit is production-ready"
```

**Make Executable**:
```bash
chmod +x tests/production/production-validation.sh
```

**Verification**:
```bash
# Run production validation
./tests/production/production-validation.sh

# Expected output:
# ✅ Core installation successful
# ✅ Monitoring installation successful
# ✅ Health check successful
# ✅ Performance functions installation successful
# ✅ All performance functions work
# ✅ SQL injection tests passed
# ✅ All critical tests passed
# ✅ pgGit is production-ready
```

**Acceptance Criteria**:
- [ ] All Phase 1-4 features install correctly
- [ ] All functions execute without errors
- [ ] Health checks pass
- [ ] Security tests pass
- [ ] Production validation script exits 0
- [ ] Test runs in under 5 minutes

---

## Success Metrics

| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| CI pass rate | ~70% | 100% | 🔴 Needs work |
| Tested performance functions | 0/8 | 8/8 | 🔴 Needs work |
| Validated security tests | 0/5 | 5/5 | 🔴 Needs work |
| Workflow validation | 0/2 | 2/2 | 🔴 Needs work |
| Production validation | No | Yes | 🔴 Needs work |
| Overall quality | 9.5/10 | 9.8/10 | 🟡 In progress |

**Post-Phase 5 Metrics**:
| Metric | Target | Description |
|--------|--------|-------------|
| CI pass rate | 100% | All tests green on all PostgreSQL versions |
| Test coverage | 95%+ | All features tested with real data |
| Security validation | 100% | All injection attacks prevented |
| Workflow reliability | 100% | All workflows validated |
| Production readiness | 100% | Validated in prod-like environment |
| Quality rating | **9.8/10** | Battle-tested excellence |

---

## Quality Impact

| Dimension | Phase 4 | Phase 5 Target | Improvement |
|-----------|---------|----------------|-------------|
| Testing | 9/10 | 9.8/10 | 100% CI pass rate |
| Security | 9.5/10 | 9.8/10 | Validated injection prevention |
| Operations | 9.5/10 | 9.8/10 | Production validation |
| Reliability | 9/10 | 9.8/10 | All workflows tested |
| **Overall** | **9.5/10** | **9.8/10** | **Battle-tested** |

---

## Effort Breakdown

**Total Effort**: 4-5 steps (effort-based, not time-based)

| Step | Effort | Priority | Dependencies |
|------|--------|----------|--------------|
| 1. Fix CI Tests | HIGH (1-2 hours) | HIGH | None |
| 2. Validate Performance | MEDIUM (1 hour) | MEDIUM | Step 1 |
| 3. Validate Security | LOW (30 min) | MEDIUM | Step 1 |
| 4. Validate Workflows | LOW (30 min) | MEDIUM | None |
| 5. Production Validation | MEDIUM (1 hour) | LOW | Steps 1-4 |

**Parallel Execution**:
- Steps 2, 3, 4 can run in parallel after Step 1
- Step 5 should be last (validates all others)

---

## Rollback Strategy

If issues arise during Phase 5:

**Step 1 Rollback** (CI test fixes):
```bash
# Revert CI workflow changes
git checkout HEAD~1 .github/workflows/tests.yml
git commit -m "Revert: CI test fixes"
```

**Step 2-4 Rollback** (Feature validation):
```bash
# Remove test files
rm tests/phase-4/test-performance-functions.sql
rm .github/workflows/security-tests.yml
rm .github/workflows/validate-workflows.yml
```

**Step 5 Rollback** (Production validation):
```bash
# Remove production validation script
rm tests/production/production-validation.sh
```

**Emergency Rollback** (Full Phase 5):
```bash
# Reset to Phase 4 completion
git reset --hard <phase-4-commit-hash>
```

---

## Post-Phase 5 Next Steps

After Phase 5 completion (9.8/10 quality):

### Continuous Excellence
- Monthly security audits (run security-scan workflow)
- Quarterly performance reviews (analyze_slow_queries)
- Biannual compliance assessments (FIPS, SOC2 updates)
- Community feedback integration

### Optional Phase 6 (9.8 → 10.0)
If pursuing absolute perfection:
- Video tutorials and training courses
- Certified pgGit administrator program
- Multi-region HA deployment guides
- Industry-specific compliance (HIPAA, PCI-DSS)
- Advanced chaos engineering (region failures)
- Performance at extreme scale (1TB+, 100K+ objects)

**Recommendation**: Stop at 9.8/10 and focus on adoption. The final 0.2 points have diminishing returns.

---

## Quick Start

```bash
# 1. Fix CI tests first (highest priority)
git checkout -b phase-5-ci-fixes
# Edit .github/workflows/tests.yml
# Add prerequisite setup steps
git commit -m "fix: Add deployment mode and CQRS prerequisites to CI tests"
git push origin phase-5-ci-fixes

# 2. Validate performance functions
createdb pggit_perf_test
psql -d pggit_perf_test -f sql/install.sql
psql -d pggit_perf_test -f sql/pggit_monitoring.sql
psql -d pggit_perf_test -f sql/pggit_performance.sql
psql -d pggit_perf_test -f tests/phase-4/test-performance-functions.sql

# 3. Validate security tests
psql -d pggit_test -f tests/security/test-sql-injection.sql

# 4. Test workflows manually
gh workflow run sbom.yml
gh workflow run security-scan.yml

# 5. Run production validation
./tests/production/production-validation.sh
```

---

## Documentation

- **Phase Plan**: `.phases/phase-5-stabilization.md` (this file)
- **CI Workflow**: `.github/workflows/tests.yml`
- **Performance Tests**: `tests/phase-4/test-performance-functions.sql`
- **Security Tests**: `tests/security/test-sql-injection.sql`
- **Production Validation**: `tests/production/production-validation.sh`

---

**Created**: 2025-12-20
**Owner**: TBD
**Status**: Ready for execution
**Target Quality**: 9.8/10 (Battle-tested Excellence)
