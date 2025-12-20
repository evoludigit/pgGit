# Phase 1: Critical Fixes

**Quality Gain**: 6.5/10 → 7.5/10
**Prerequisites**: None (first phase)
**Priority**: URGENT - Must complete before any marketing or promotion

---

## Pre-Phase Checklist

Before starting Phase 1:

**Prerequisites**:
- [ ] Clean git status (no uncommitted changes)
- [ ] PostgreSQL 15+ running locally
- [ ] pgTAP extension available (or installable)
- [ ] GitHub CLI (`gh`) installed for workflow testing

**Setup**:
```bash
# Create phase branch
git checkout -b phase-1-critical-fixes

# Verify environment
psql --version  # Should be >= 15
git status      # Should be clean
gh --version    # For CI workflow testing

# Run baseline tests
make test 2>&1 | tee baseline-test-results.txt
```

**Focus**:
- Quality over speed - no hard deadlines
- Document decisions as you go
- Commit frequently with clear messages

---

## Objective

Fix critical issues that could damage credibility and prevent safe usage. These are blockers for any production consideration.

---

## Context

Current state has significant gaps:
- Documentation claims features that don't exist (security RBAC, compliance)
- CI tests failing intermittently
- No test coverage visibility
- Module architecture unclear (core/ vs sql/ relationship)
- No vulnerability reporting process

These issues create risk for:
1. **User trust** - Misleading docs destroy credibility
2. **Security** - No clear way to report vulnerabilities
3. **Stability** - Unknown test coverage means hidden bugs
4. **Contributor onboarding** - Unclear architecture

---

## Files to Modify

### Documentation Files
- `docs/guides/Security.md` - Remove or mark unimplemented features
- `docs/new-features-index.md` - Add implementation status
- `SECURITY.md` - CREATE NEW
- `docs/architecture/MODULES.md` - CREATE NEW
- `README.md` - Add stability/feature status badges

### Code Files
- `.github/workflows/test-with-fixes.yml` - Fix failing tests
- `.github/workflows/tests.yml` - Add test coverage reporting
- `tests/test-*.sql` - Add pgTAP structure
- `docs/contributing/ARCHITECTURE.md` - CREATE NEW

### Configuration Files
- `.sqlfluff` - CREATE NEW (linting config)
- `.pre-commit-config.yaml` - CREATE NEW

---

## Step Dependencies

Steps can be executed in this order:

```
Phase 1 Flow:
┌─────────────────────────────────────────────────┐
│ Step 1: Doc Audit [HIGH]                       │
│ Step 2: SECURITY.md [LOW]  (parallel with 1)   │
└──────────────┬──────────────────────────────────┘
               ↓
┌─────────────────────────────────────────────────┐
│ Step 3: pgTAP Integration [HIGH]               │
└──────────────┬──────────────────────────────────┘
               ↓
┌─────────────────────────────────────────────────┐
│ Step 4: Fix CI Failures [MEDIUM]               │
└──────────────┬──────────────────────────────────┘
               ↓
┌──────────────┴──────────────────────────────────┐
│ Step 5: Coverage Tracking [MEDIUM]             │
│ Step 6: Module Docs [LOW]  (parallel with 5)   │
└─────────────────────────────────────────────────┘
```

**Parallel Execution Possible**:
- Steps 1 & 2 (independent documentation tasks)
- Steps 5 & 6 (after Step 4 completes)

**Sequential Required**:
- Step 3 depends on Step 1 (accurate docs needed for test design)
- Step 4 depends on Step 3 (pgTAP must be installed)
- Step 5 depends on Step 4 (tests must pass to track coverage)

---

## Implementation Steps

### Step 1: Audit and Fix Documentation [EFFORT: HIGH]

**Goal**: Ensure all documentation is accurate and clearly marks experimental features.

```sql
-- 1.1: Find all referenced functions in Security.md
SELECT DISTINCT function_name
FROM (
    SELECT unnest(regexp_matches(content, 'pggit\\.([a-z_]+)\\(', 'g')) as function_name
    FROM unnest(pg_read_file('docs/guides/Security.md')::text[]) as content
) functions;

-- 1.2: Compare against actual implemented functions
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'pggit'
ORDER BY routine_name;
```

**Actions**:
- Read `docs/guides/Security.md` completely
- For each function mentioned:
  - Check if it exists in core/sql/*.sql or sql/*.sql
  - If NOT exists: Either remove or add "🚧 PLANNED" badge
- Update all feature claims with status badges:
  - ✅ Implemented and tested
  - 🚧 Planned
  - 🧪 Experimental
  - 📝 Design phase

**Delegation Strategy**:

🤖 **Can Delegate to Local Model**:
- Adding status badges (✅/🚧/🧪) to feature lists (pattern-based replacement)
- Extracting function names from SQL files (grep + formatting)
- Formatting markdown tables consistently

❌ **Keep with Claude**:
- Deciding which features are misleading vs. accurate (requires judgment)
- Writing disclaimer language (requires understanding of legal/credibility risk)
- Architectural explanations (requires deep context)

**Verification**:
```bash
# Extract all pggit.* function calls from markdown
grep -rh "pggit\.[a-z_]*(" docs/ | sed 's/.*pggit\.\([a-z_]*\)(.*/\1/' | sort -u > /tmp/doc-functions.txt

# Extract all actual functions from SQL
grep -rh "CREATE OR REPLACE FUNCTION pggit\." core/sql sql/ | sed 's/.*pggit\.\([a-z_]*\)(.*/\1/' | sort -u > /tmp/impl-functions.txt

# Find mismatches (should be EMPTY after fixes)
comm -23 /tmp/doc-functions.txt /tmp/impl-functions.txt

# ✅ PASS: No output (all documented functions exist or marked planned)
# ❌ FAIL: Any function names appear (undocumented claims remain)
```

**Rollback Strategy**:
```bash
# If changes are incorrect, revert
git checkout HEAD -- docs/
```

**Acceptance Criteria**:
- [ ] All documented functions exist in codebase OR marked as planned (0 mismatches)
- [ ] Security.md has disclaimer about experimental status
- [ ] No misleading claims about compliance features
- [ ] Feature matrix has status badges on every row

---

### Step 2: Add SECURITY.md [EFFORT: LOW]

**Goal**: Provide clear vulnerability reporting process.

```markdown
# Security Policy

## Supported Versions

| Version | Supported          | Status |
| ------- | ------------------ | ------ |
| 0.1.x   | :warning: Experimental | Not for production |

## Reporting a Vulnerability

**DO NOT** open a public GitHub issue for security vulnerabilities.

### Reporting Process

1. **Email**: Send details to [your-email]@[domain]
   - Subject: "SECURITY: [brief description]"
   - Include: pgGit version, PostgreSQL version, description, reproduction steps

2. **Response Time**:
   - Initial acknowledgment: 48 hours
   - Status update: 7 days
   - Fix timeline: Based on severity

3. **Disclosure**:
   - We follow responsible disclosure (90 days)
   - You will be credited (unless you prefer anonymity)

### Security Best Practices

See [Security Guide](docs/guides/Security.md) for:
- Access control configuration
- Audit trail setup
- Production hardening

### Known Limitations

⚠️ **v0.1.x is experimental**:
- No security audit performed
- Not recommended for production
- Use at your own risk

## Security Features Status

| Feature | Status | Version |
|---------|--------|---------|
| DDL Audit Trail | ✅ Implemented | 0.1.0 |
| Event Trigger Security | ✅ Implemented | 0.1.0 |
| RBAC System | 🚧 Planned | Future |
| Compliance Reporting | 🚧 Planned | Future |
```

**Delegation Strategy**:

🤖 **Can Delegate to Local Model**:
- Filling in SECURITY.md template with project details
- Adding markdown link to README

❌ **Keep with Claude**:
- Choosing appropriate security contact email
- Reviewing security policy wording for completeness

**Verification**:
```bash
# Check SECURITY.md exists
test -f SECURITY.md && echo "✅ Created" || echo "❌ Missing"

# Validate it's linked from README
grep -q "SECURITY.md" README.md && echo "✅ Linked" || echo "❌ Not linked"

# ✅ PASS: Both checks return ✅
# ❌ FAIL: Any check returns ❌
```

**Rollback Strategy**:
```bash
# If needed, remove SECURITY.md
git rm SECURITY.md
git checkout HEAD -- README.md
```

**Acceptance Criteria**:
- [ ] SECURITY.md created with email contact
- [ ] README.md links to SECURITY.md in Security section
- [ ] GitHub security tab configured (via repo settings)
- [ ] Security policy includes response timeline (48h ack, 7d update)

---

### Step 3: Integrate pgTAP Testing [EFFORT: HIGH]

**Goal**: Structured testing framework with pass/fail assertions.

**TDD Approach**:

This step follows RED → GREEN → REFACTOR workflow:

1. **RED Phase**: Write failing pgTAP tests first
   ```bash
   # Create tests/pgtap/test-core.sql with tests that fail
   psql -f tests/pgtap/test-core.sql  # Should show failures
   ```

2. **GREEN Phase**: Make tests pass with minimal code
   ```bash
   # Fix issues until tests pass
   psql -f tests/pgtap/test-core.sql  # All tests ok
   ```

3. **REFACTOR Phase**: Clean up test code while keeping green
   ```bash
   # Improve test organization, remove duplication
   psql -f tests/pgtap/test-core.sql  # Still passing
   ```

4. **QA Phase**: Add edge cases and error handling tests
   ```bash
   # Add tests for NULL inputs, invalid data, etc.
   ```

```sql
-- 3.1: Install pgTAP extension
CREATE EXTENSION IF NOT EXISTS pgtap;

-- 3.2: Example test conversion (tests/test-core-pgtap.sql)
BEGIN;
SELECT plan(10); -- Number of tests

-- Test 1: Schema exists
SELECT has_schema('pggit', 'pggit schema should exist');

-- Test 2: Core tables exist
SELECT has_table('pggit', 'objects', 'pggit.objects table should exist');
SELECT has_table('pggit', 'history', 'pggit.history table should exist');

-- Test 3: Event triggers exist
SELECT has_trigger('pggit_ddl_trigger', 'DDL trigger should exist');

-- Test 4: Function exists and returns correct type
SELECT has_function('pggit', 'ensure_object', 'ensure_object function should exist');

-- Test 5: Test actual functionality
CREATE TABLE test_versioning (id SERIAL PRIMARY KEY);
SELECT lives_ok(
    $$SELECT pggit.get_version('test_versioning')$$,
    'get_version should work on new table'
);

-- Test 6: Version format is correct
SELECT matches(
    (SELECT pggit.get_version('test_versioning')::text),
    '^\d+\.\d+\.\d+$',
    'Version should be in semver format'
);

DROP TABLE test_versioning CASCADE;

SELECT * FROM finish();
ROLLBACK;
```

**Actions**:
- Add pgTAP to dependencies in README
- Convert `tests/test-core.sql` to pgTAP format
- Create `tests/test-runner.sh` using `pg_prove`
- Add pgTAP to CI workflows

**Makefile additions**:
```makefile
# Test with pgTAP
test-pgtap:
	@echo "Running pgTAP tests..."
	@pg_prove -U postgres tests/pgtap/*.sql

test-coverage:
	@echo "Generating test coverage report..."
	@psql -f tests/coverage-check.sql
```

**Delegation Strategy**:

🤖 **Can Delegate to Local Model** (after you design first test):
- Converting remaining test files to pgTAP format (pattern from your example)
- Adding similar test cases across multiple files (e.g., has_table tests)
- Formatting test output consistently

❌ **Keep with Claude**:
- Designing the test strategy (which tests to write)
- Deciding test plan counts (how many assertions)
- Writing complex functional tests (requires understanding behavior)
- Debugging test failures

**Verification**:
```bash
# Run tests with pg_prove
pg_prove -d test_db tests/pgtap/*.sql

# ✅ PASS: All tests successful, exit code 0
# ❌ FAIL: Any test failures, exit code non-zero

# Should output:
# tests/pgtap/test-core.sql .. ok
# tests/pgtap/test-git.sql ... ok
# tests/pgtap/test-config.sql . ok
# All tests successful.
```

**Rollback Strategy**:
```bash
# If pgTAP integration breaks existing setup
psql -c "DROP EXTENSION IF EXISTS pgtap CASCADE"
git checkout HEAD -- tests/
```

**Acceptance Criteria**:
- [ ] pgTAP installed and documented in README
- [ ] At least 3 test files converted (test-core.sql, test-git.sql, test-config.sql)
- [ ] CI runs pgTAP tests with pg_prove
- [ ] All tests passing (100% pass rate)
- [ ] Makefile has `make test-pgtap` target

---

### Step 4: Fix All CI Test Failures [EFFORT: MEDIUM]

**Goal**: Green CI pipeline with reliable tests.

```yaml
# .github/workflows/tests.yml improvements
name: Tests

on:
  push:
    branches: [ main, dev ]
  pull_request:
    branches: [ main, dev ]

jobs:
  test:
    strategy:
      matrix:
        pg-version: [15, 16, 17]
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:${{ matrix.pg-version }}
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: test_db
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
    - uses: actions/checkout@v4

    - name: Install dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y postgresql-${{ matrix.pg-version }}-pgtap

    - name: Install pgGit
      env:
        PGPASSWORD: postgres
      run: |
        psql -h localhost -U postgres -d test_db -f sql/install.sql

    - name: Run pgTAP tests
      env:
        PGPASSWORD: postgres
      run: |
        pg_prove -h localhost -U postgres -d test_db tests/pgtap/*.sql

    - name: Upload coverage
      run: |
        psql -h localhost -U postgres -d test_db -f tests/coverage-report.sql > coverage.txt
        cat coverage.txt
```

**Actions**:
- Review recent CI failures from git history
- Fix module loading order issues
- Ensure clean database state between tests
- Add test isolation (transactions)
- Fix PostgreSQL version compatibility issues

**Delegation Strategy**:

🤖 **Can Delegate to Local Model**:
- Applying simple fixes across multiple test files (e.g., adding transactions)
- Updating test file headers with consistent format

❌ **Keep with Claude**:
- Debugging intermittent CI failures (requires analysis)
- Fixing module loading order issues (requires architecture understanding)
- Resolving PostgreSQL version compatibility (requires research)

**Verification**:
```bash
# Check CI status
gh run list --workflow=tests.yml --limit 5

# ✅ PASS: All runs show ✅ (completed, success)
# ❌ FAIL: Any runs show ❌ (failed)

# Run tests locally on each PG version (if Docker available)
for version in 15 16 17; do
    echo "Testing PostgreSQL $version"
    docker run --rm -e POSTGRES_PASSWORD=postgres -d -p 5432:5432 --name pg_test postgres:$version
    sleep 5
    PGPASSWORD=postgres psql -h localhost -U postgres -c "CREATE DATABASE test_db"
    PGPASSWORD=postgres psql -h localhost -U postgres -d test_db -f sql/install.sql
    PGPASSWORD=postgres pg_prove -h localhost -U postgres -d test_db tests/pgtap/*.sql
    docker stop pg_test
done

# ✅ PASS: All versions complete successfully
# ❌ FAIL: Any version fails
```

**Rollback Strategy**:
```bash
# If CI changes break workflows
git checkout HEAD -- .github/workflows/
```

**Acceptance Criteria**:
- [ ] All CI workflows passing (tests.yml shows green checkmark)
- [ ] Tests pass on PostgreSQL 15, 16, 17 (matrix build succeeds)
- [ ] No intermittent failures over 10 consecutive runs
- [ ] Green badges added to README.md

---

### Step 5: Add Test Coverage Tracking [EFFORT: MEDIUM]

**Goal**: Visibility into which functions are tested.

```sql
-- Create coverage tracking
-- File: tests/coverage-report.sql

-- Count total functions
CREATE TEMP TABLE total_functions AS
SELECT
    routine_schema,
    routine_name,
    COUNT(*) as overload_count
FROM information_schema.routines
WHERE routine_schema = 'pggit'
GROUP BY routine_schema, routine_name;

-- Track tested functions (from pgTAP tests)
CREATE TEMP TABLE tested_functions AS
SELECT DISTINCT
    'pggit' as schema_name,
    regexp_replace(
        test_description,
        '.*pggit\.([a-z_]+).*',
        '\1'
    ) as function_name
FROM pgtap_test_results
WHERE test_description ~ 'pggit\.[a-z_]+';

-- Coverage report
SELECT
    'Total Functions' as metric,
    COUNT(*)::text as value
FROM total_functions
UNION ALL
SELECT
    'Tested Functions',
    COUNT(*)::text
FROM tested_functions
UNION ALL
SELECT
    'Coverage %',
    ROUND(
        (SELECT COUNT(*)::numeric FROM tested_functions) /
        (SELECT COUNT(*) FROM total_functions) * 100,
        2
    )::text || '%';

-- List untested functions
SELECT
    routine_name as untested_function
FROM total_functions tf
WHERE NOT EXISTS (
    SELECT 1 FROM tested_functions tt
    WHERE tt.function_name = tf.routine_name
)
ORDER BY routine_name;
```

**Add to CI**:
```yaml
- name: Generate coverage report
  run: |
    psql -h localhost -U postgres -d test_db -f tests/coverage-report.sql

- name: Check coverage threshold
  run: |
    COVERAGE=$(psql -h localhost -U postgres -d test_db -tA -c "
      SELECT ROUND(
        (SELECT COUNT(*)::numeric FROM tested_functions) /
        (SELECT COUNT(*) FROM total_functions) * 100,
        0
      )
    ")
    echo "Coverage: $COVERAGE%"
    if [ "$COVERAGE" -lt 50 ]; then
      echo "❌ Coverage below 50%"
      exit 1
    fi
```

**Delegation Strategy**:

🤖 **Can Delegate to Local Model**:
- Extracting function counts from information_schema
- Formatting coverage report output
- Creating baseline coverage badge markdown

❌ **Keep with Claude**:
- Designing coverage tracking strategy (what to measure)
- Setting appropriate coverage thresholds (requires understanding risk)
- Identifying critical vs. non-critical functions

**Verification**:
```bash
make test-coverage

# ✅ PASS CRITERIA:
# - Coverage >= 50%
# - Report shows total, tested, and percentage
# - Exit code 0

# ❌ FAIL CRITERIA:
# - Coverage < 50%
# - Report missing any section
# - Exit code non-zero

# Should output:
# ========================================
# pgGit Test Coverage Report
# ========================================
# Total Functions:    47
# Tested Functions:   28
# Coverage:          59.57%
#
# Untested Functions:
# - pggit.create_data_branch
# - pggit.merge_compressed_branches
# ...
```

**Rollback Strategy**:
```bash
# If coverage tracking has issues
git checkout HEAD -- tests/coverage-report.sql Makefile .github/workflows/
```

**Acceptance Criteria**:
- [ ] Coverage tracking SQL implemented (tests/coverage-report.sql exists)
- [ ] Coverage report in CI output (visible in workflow runs)
- [ ] Baseline coverage ≥50% achieved and documented
- [ ] Coverage badge added to README.md
- [ ] Make target `test-coverage` works

---

### Step 6: Document Module Architecture [EFFORT: LOW]

**Goal**: Clear understanding of core/ vs sql/ and loading order.

```markdown
# File: docs/architecture/MODULES.md

# pgGit Module Architecture

## Overview

pgGit is organized into **core modules** (required) and **extension modules** (optional).

```
pggit/
├── core/sql/              # Required - Always loaded
│   ├── 001_schema.sql     # Base types, tables, enums
│   ├── 002_event_triggers.sql  # DDL capture
│   ├── 003-018_*.sql      # Core functionality
│   └── install.sql        # Load all core
│
├── sql/                   # Extensions - Optional features
│   ├── pggit_configuration.sql      # Selective tracking
│   ├── pggit_cqrs_support.sql       # CQRS patterns
│   ├── pggit_function_versioning.sql # Function overloads
│   ├── 020-054_*.sql                # Advanced features
│   └── install.sql                  # Load all extensions
│
└── pggit--0.1.0.sql       # Combined installation file
```

## Module Dependency Graph

```
001_schema.sql (base types, tables)
    ↓
002_event_triggers.sql (DDL capture)
    ↓
003_migration_functions.sql
    ↓
004_utility_views.sql
    ↓
006_git_implementation.sql (branching, commits)
    ↓
[Extensions - no dependencies between them]
    ├── pggit_configuration.sql
    ├── pggit_cqrs_support.sql
    ├── pggit_function_versioning.sql
    └── ...
```

## Installation Options

### Option 1: Full Installation (Recommended)
```sql
CREATE EXTENSION pggit;
-- OR
\i pggit--0.1.0.sql
```

### Option 2: Core Only
```sql
\i core/sql/install.sql
```

### Option 3: Core + Selected Extensions
```sql
\i core/sql/install.sql
\i sql/pggit_configuration.sql
\i sql/pggit_cqrs_support.sql
```

## Module Loading Order

**Critical**: Modules must be loaded in numerical order.

| Order | File | Purpose | Required |
|-------|------|---------|----------|
| 1 | 001_schema.sql | Types, tables, enums | ✅ |
| 2 | 002_event_triggers.sql | DDL capture | ✅ |
| 3 | 003_migration_functions.sql | Migration generation | ✅ |
| 4 | 004_utility_views.sql | Helper views | ✅ |
| 5 | 006_git_implementation.sql | Git operations | ✅ |
| 6+ | Extensions | Optional features | ❌ |

## Feature Matrix

| Feature | Module | Status |
|---------|--------|--------|
| DDL Tracking | core/002 | ✅ Stable |
| Git Branching | core/006 | ✅ Stable |
| CQRS Support | sql/pggit_cqrs | 🧪 Experimental |
| Function Versioning | sql/pggit_function | 🧪 Experimental |
| AI Analysis | sql/030_ai | 🚧 Planned |

## How to Add New Modules

1. Determine if core (required) or extension (optional)
2. Choose next available number (e.g., 055_)
3. Add dependency declarations in file header
4. Update install.sql to include new module
5. Add to this documentation
6. Add tests to tests/test-[module-name].sql
```

**Delegation Strategy**:

🤖 **Can Delegate to Local Model**:
- Creating directory tree ASCII art
- Formatting dependency tables
- Generating feature matrix from template

❌ **Keep with Claude**:
- Writing architectural explanations (requires deep understanding)
- Designing module dependency graph (requires analysis)
- Explaining installation options (requires context)

**Verification**:
```bash
# Check MODULES.md exists and is complete
test -f docs/architecture/MODULES.md && echo "✅ Created" || echo "❌ Missing"

# Verify it's linked from README
grep -q "Module Architecture" README.md && echo "✅ Linked" || echo "❌ Not linked"

# Check for required sections
for section in "Directory Structure" "Dependency Graph" "Installation Options" "Feature Matrix"; do
    grep -q "$section" docs/architecture/MODULES.md && echo "✅ $section" || echo "❌ Missing: $section"
done

# ✅ PASS: All checks return ✅
# ❌ FAIL: Any check returns ❌
```

**Rollback Strategy**:
```bash
# If module documentation is incorrect
git checkout HEAD -- docs/architecture/ README.md
```

**Acceptance Criteria**:
- [ ] MODULES.md created and linked from README
- [ ] Dependency graph shows load order (001→002→003...)
- [ ] Installation options documented (full, core-only, selective)
- [ ] core/ vs sql/ distinction clear with examples
- [ ] Feature matrix shows which module contains each feature

---

## Phase-Wide Rollback Strategy

If Phase 1 needs to be completely rolled back:

```bash
# Return to pre-phase state
git checkout main
git branch -D phase-1-critical-fixes

# If changes were already merged
git revert <merge-commit-sha>

# Database cleanup (if needed)
psql -c "DROP EXTENSION IF EXISTS pgtap CASCADE"
```

**Safe Checkpoints** (tag these as you go):
```bash
git tag phase-1-step-1-complete  # After doc audit
git tag phase-1-step-3-complete  # After pgTAP integration
git tag phase-1-step-4-complete  # After CI fixes
git tag phase-1-complete         # After all steps
```

---

## Verification Commands

After completing all steps:

```bash
# 1. Documentation accuracy check
# ✅ PASS: No mismatches between docs and implementation
# ❌ FAIL: Any undocumented functions found
comm -23 /tmp/doc-functions.txt /tmp/impl-functions.txt | wc -l  # Should be 0

# 2. Security policy exists
# ✅ PASS: Both checks succeed
# ❌ FAIL: Either check fails
test -f SECURITY.md && echo "✅ Security policy" || echo "❌ Missing"
grep -q "SECURITY.md" README.md && echo "✅ Linked" || echo "❌ Not linked"

# 3. All tests passing
# ✅ PASS: All tests ok, exit code 0
# ❌ FAIL: Any test failures, exit code non-zero
make test-pgtap

# 4. CI green
# ✅ PASS: Latest run shows success
# ❌ FAIL: Latest run shows failure
gh run list --workflow=tests.yml --limit 1

# 5. Coverage above threshold
# ✅ PASS: Coverage ≥ 50%
# ❌ FAIL: Coverage < 50%
make test-coverage | grep "Coverage:" | grep -E "[5-9][0-9]\.[0-9]+%|100%"

# 6. Architecture documented
# ✅ PASS: File exists and is linked
# ❌ FAIL: Missing or not linked
test -f docs/architecture/MODULES.md && echo "✅ Architecture" || echo "❌ Missing"
grep -q "Module Architecture" README.md && echo "✅ Linked" || echo "❌ Not linked"
```

---

## Acceptance Criteria

### Documentation
- [ ] All claimed functions in docs actually exist in code
- [ ] Feature status badges added (✅ 🧪 🚧 📝)
- [ ] SECURITY.md created with contact info
- [ ] MODULES.md explains architecture clearly
- [ ] README updated with stability warnings

### Testing
- [ ] pgTAP integrated and documented
- [ ] Minimum 3 test suites converted to pgTAP
- [ ] All CI workflows passing (green badges)
- [ ] Test coverage >50% and tracked in CI
- [ ] Coverage report generated on each run

### Code Quality
- [ ] No misleading documentation
- [ ] Clear module dependency graph
- [ ] Installation process documented with options

### Governance
- [ ] Vulnerability reporting process defined
- [ ] Security tab configured on GitHub
- [ ] Contributors know how to report issues

---

## DO NOT

- ❌ Add new features during this phase
- ❌ Refactor working code
- ❌ Change public API
- ❌ Add unrelated improvements
- ❌ Skip verification steps

**Focus**: Fix critical issues only. No scope creep.

---

## Success Metrics

After Phase 1 completion:

| Metric | Current | Target | How to Verify | Achieved |
|--------|---------|--------|---------------|----------|
| Documentation accuracy | 60% | 95% | 0 function mismatches | [ ] |
| CI success rate | 70% | 100% | All workflows green | [ ] |
| Test coverage | 0% | ≥50% | Coverage report shows ≥50% | [ ] |
| Security policy | ❌ | ✅ | SECURITY.md exists and linked | [ ] |
| Architecture clarity | Low | High | MODULES.md complete | [ ] |
| Overall quality | 6.5/10 | 7.5/10 | All above metrics met | [ ] |

---

## Next Phase

After Phase 1 completion → **Phase 2: Quality Foundation**
- sqlfluff linting
- Complete API reference
- Security audit
- Issue/PR templates
