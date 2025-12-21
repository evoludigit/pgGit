# Comprehensive Plan to Fix All Silent Test Failures

## Executive Summary

The pggit test suite has **38+ silent failure points** where tests pass even when they should fail. This plan provides a systematic approach to fix all of them, replacing silent skips with explicit assertions and proper error handling.

**Total scope**: 9 SQL test files + 2 shell scripts + 1 GitHub Actions workflow = 12 files to modify

---

## Part 1: Root Cause Analysis

### Problem Categories

#### 1. **Silent Test Skips (9 SQL test files)**
Tests that return without running assertions if optional features aren't loaded:
```sql
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'function_name'
                   AND pronamespace = 'pggit'::regnamespace) THEN
        RAISE NOTICE 'Feature not loaded, skipping test';
        RETURN;  -- ❌ SILENT EXIT - Test passes with 0 assertions
    END IF;
    -- Actual test code never executes
END $$;
```

**Impact**: If a required feature fails to install, tests still "pass"

---

#### 2. **Silent Exception Handlers (19+ occurrences)**
Tests that catch exceptions and log them instead of failing:
```sql
DO $$
BEGIN
    -- Test code
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Test failed: %', SQLERRM;  -- ❌ LOGS BUT DOESN'T FAIL
END $$;
```

**Impact**: Feature bugs are hidden behind warning messages

---

#### 3. **Shell Script Error Suppression (6+ occurrences)**
Installation scripts that suppress errors:
```bash
psql -f install.sql || true  # ❌ Ignores installation failures
```

**Impact**: pggit extension may not be installed when tests run

---

#### 4. **CI/CD Workflow Silent Suppression (8+ occurrences)**
GitHub Actions that dismiss errors as "expected":
```bash
for file in *.sql; do
  psql -f "$file" || echo "Warning: Some errors (may be expected)"  # ❌ Hidden failures
done
```

**Impact**: Installation errors go unnoticed in CI/CD pipelines

---

## Part 2: Fix Strategy

### Principle 1: Explicit Assertions
- ❌ Remove all `IF NOT EXISTS ... RETURN` patterns
- ✅ Replace with explicit assertions that required features exist
- ✅ Fail loudly if dependencies are missing

### Principle 2: Propagate Exceptions
- ❌ Remove all `EXCEPTION WHEN OTHERS THEN RAISE NOTICE`
- ✅ Either let exceptions propagate (test fails) or handle specific cases
- ✅ Use `EXCEPTION WHEN specific_error_type` only for expected error scenarios

### Principle 3: Fail on Installation Errors
- ❌ Remove all `|| true` and error suppression
- ✅ Let installation failures stop test execution
- ✅ Fix actual installation issues instead of hiding them

### Principle 4: Comprehensive Coverage
- ✅ Ensure all test dependencies are checked before tests run
- ✅ Generate clear error messages when dependencies are missing
- ✅ Separate "optional feature tests" from "required core tests"

---

## Part 3: Implementation Phases

### Phase 1: Create Test Infrastructure (Foundation)
**Objective**: Build utilities to support the new testing approach

#### 1.1 Create `sql/test_helpers.sql`
A new SQL module with assertion utilities:

```sql
-- Test assertion utilities for explicit failure
CREATE OR REPLACE FUNCTION pggit.assert_function_exists(
    p_function_name TEXT,
    p_schema TEXT DEFAULT 'pggit'
) RETURNS VOID AS $$
DECLARE
    v_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE proname = p_function_name
        AND pronamespace = p_schema::regnamespace
    ) INTO v_exists;

    IF NOT v_exists THEN
        RAISE EXCEPTION 'Required function %.%() does not exist',
            p_schema, p_function_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit.assert_table_exists(
    p_table_name TEXT,
    p_schema TEXT DEFAULT 'pggit'
) RETURNS VOID AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = p_schema
        AND table_name = p_table_name
    ) THEN
        RAISE EXCEPTION 'Required table %.% does not exist',
            p_schema, p_table_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit.assert_type_exists(
    p_type_name TEXT,
    p_schema TEXT DEFAULT 'pggit'
) RETURNS VOID AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.schemata s
        JOIN pg_type t ON t.typnamespace = (s.schema_name::regnamespace)::oid
        WHERE s.schema_name = p_schema
        AND t.typname = p_type_name
    ) THEN
        RAISE EXCEPTION 'Required type %.% does not exist',
            p_schema, p_type_name;
    END IF;
END;
$$ LANGUAGE plpgsql;
```

**File**: `sql/test_helpers.sql` (NEW)
**Installation**: Add to `install.sql` before tests run

---

#### 1.2 Create Python Test Utilities
Enhance chaos test infrastructure to validate feature presence:

**File**: `tests/chaos/test_assertions.py` (NEW)

```python
import pytest
from contextlib import contextmanager

class FeatureRequirement:
    """Manages feature availability checks"""

    @staticmethod
    def require_function(conn, function_name, schema='pggit'):
        """Require that a function exists"""
        with conn.cursor() as cur:
            cur.execute("""
                SELECT 1 FROM pg_proc
                WHERE proname = %s
                AND pronamespace = %s::regnamespace
            """, (function_name, schema))
            if not cur.fetchone():
                pytest.skip(
                    f"Required function {schema}.{function_name}() not installed. "
                    "This feature module must be installed to run this test."
                )

    @staticmethod
    def require_table(conn, table_name, schema='pggit'):
        """Require that a table exists"""
        with conn.cursor() as cur:
            cur.execute("""
                SELECT 1 FROM information_schema.tables
                WHERE table_schema = %s AND table_name = %s
            """, (schema, table_name))
            if not cur.fetchone():
                pytest.skip(
                    f"Required table {schema}.{table_name} not installed. "
                    "This feature module must be installed to run this test."
                )

    @staticmethod
    def require_type(conn, type_name, schema='pggit'):
        """Require that a custom type exists"""
        with conn.cursor() as cur:
            cur.execute("""
                SELECT 1 FROM information_schema.schemata s
                JOIN pg_type t ON t.typnamespace = (s.schema_name::regnamespace)::oid
                WHERE s.schema_name = %s AND t.typname = %s
            """, (schema, type_name))
            if not cur.fetchone():
                pytest.skip(
                    f"Required type {schema}.{type_name} not installed. "
                    "This feature module must be installed to run this test."
                )

@contextmanager
def assert_no_exception(context="operation"):
    """Context manager that fails if ANY exception occurs"""
    try:
        yield
    except Exception as e:
        pytest.fail(f"Unexpected exception in {context}: {e}")
```

**Usage in tests**:
```python
def test_cqrs_tracking(sync_conn):
    # Explicitly require feature before running test
    FeatureRequirement.require_table(sync_conn, 'cqrs_changes')

    # Now safe to use the feature
    with sync_conn.cursor() as cur:
        cur.execute("SELECT * FROM pggit.cqrs_changes LIMIT 1")
```

---

### Phase 2: Fix SQL Test Files (9 files)
**Objective**: Replace all silent skips with explicit assertions

#### 2.1 **test-cqrs-support.sql** - HIGHEST PRIORITY
This is the exact file from your error message

**Current Problem** (Lines 29-47):
```sql
DO $$
DECLARE
    changeset_id uuid;
BEGIN
    BEGIN
        -- Create CQRS schemas
        CREATE SCHEMA IF NOT EXISTS command;
        CREATE SCHEMA IF NOT EXISTS query;

        -- Test CQRS change tracking
        changeset_id := pggit.track_cqrs_change(
            ROW(...)::pggit.cqrs_change  -- ❌ Type doesn't exist
        );

        RAISE NOTICE 'CQRS test passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'CQRS test skipped: %', SQLERRM;  -- ❌ SILENT SKIP
    END;
END $$;
```

**Fix**:
```sql
DO $$
BEGIN
    -- Explicitly assert required type exists
    PERFORM pggit.assert_type_exists('cqrs_change', 'pggit');

    -- Now the test can safely run, and any exception will propagate
    CREATE SCHEMA IF NOT EXISTS command;
    CREATE SCHEMA IF NOT EXISTS query;

    -- Perform actual test
    DECLARE
        changeset_id uuid;
    BEGIN
        changeset_id := pggit.track_cqrs_change(
            ROW(
                ARRAY['CREATE TABLE command.test (id int)'],
                ARRAY['CREATE VIEW query.test_view AS SELECT * FROM command.test'],
                'Test CQRS change',
                '1.0.0'
            )::pggit.cqrs_change
        );

        RAISE NOTICE 'PASS: CQRS test passed';
    END;
END $$;
```

**Changes**:
- Add `PERFORM pggit.assert_type_exists()` at start
- Remove `EXCEPTION WHEN OTHERS THEN RAISE NOTICE`
- Let exceptions propagate naturally
- Change NOTICE from "test skipped" to "PASS:"

---

#### 2.2 **test-core.sql**
**Files to fix**: Lines 149-153

**Current**:
```sql
EXCEPTION WHEN OTHERS THEN
    DROP TABLE IF EXISTS test_child;
    DROP TABLE IF EXISTS test_parent;
    RAISE;  -- ✅ Actually re-raises (OK)
END;
```

**Status**: ✅ **No change needed** - This already re-raises exceptions correctly

---

#### 2.3 **test-data-branching.sql** (6 silent failures)
**Lines to fix**: 67-69, 113-115, 165-167, 203-205, 234-236, 262-264

**Current pattern**:
```sql
BEGIN
    -- Data branching operations
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'WARN: Data branching not implemented (%)', SQLERRM;  -- ❌ SILENT
END;
```

**Fix**:
1. Add assertion at start: `PERFORM pggit.assert_function_exists('branch_data');`
2. Remove exception handler
3. Let exceptions propagate
4. Use explicit `RAISE EXCEPTION` for expected error scenarios

**Pattern for all 6 occurrences**:
```sql
BEGIN
    PERFORM pggit.assert_function_exists('branch_data');
    -- Actual test code
    -- Use RAISE EXCEPTION for expected errors only:
    -- EXCEPTION WHEN division_by_zero THEN ...
END;
```

---

#### 2.4 **test-cold-hot-storage.sql** (9 silent failures)
**Lines to fix**: 62-64, 99-101, 145-147, 185-187, 217-219, 245-247, 289-291, 327-329, 366-368

Same pattern as test-data-branching.sql

**Required assertions**:
```sql
PERFORM pggit.assert_function_exists('classify_storage_tier');
PERFORM pggit.assert_function_exists('deduplicate_blocks');
PERFORM pggit.assert_function_exists('migrate_to_cold_storage');
-- etc.
```

---

#### 2.5 **test-diff-functionality.sql** (Lines 10-18)
**Current**:
```sql
DO $$
BEGIN
    IF NOT EXISTS (...'diff_schemas'...) THEN
        RAISE NOTICE 'Diff functionality not loaded, skipping all diff tests';
        RETURN;  -- ❌ SILENT SKIP
    END IF;
END $$;
```

**Fix**:
```sql
DO $$
BEGIN
    PERFORM pggit.assert_function_exists('diff_schemas');
    RAISE NOTICE 'PASS: Diff functionality is loaded';
END $$;
```

---

#### 2.6 **test-three-way-merge.sql** (Lines 11-19)
**Current**:
```sql
DO $$
BEGIN
    IF NOT EXISTS (...'create_commit'...) THEN
        RAISE NOTICE 'Three-way merge functionality not loaded, skipping all merge tests';
        RETURN;  -- ❌ SILENT SKIP
    END IF;
END $$;
```

**Fix**: Same as test-diff-functionality.sql, use assertions

---

#### 2.7 **test-configuration-system.sql** (2 silent skips)
**Lines 32-37 and 54-58**

Both have `RETURN` statements that skip tests silently.

**Fix**: Replace both with assertions:
```sql
PERFORM pggit.assert_table_exists('versioned_objects');
PERFORM pggit.assert_function_exists('configure_tracking');
```

---

#### 2.8 **test-migration-integration.sql** (Lines 27-36)
**Fix**: Replace silent RETURN with assertions for required functions

---

#### 2.9 **test-zero-downtime.sql** (Lines 20-28)
**Fix**: Replace silent RETURN with assertions

---

#### 2.10 **test-advanced-features.sql** (Lines 20-28)
**Fix**: Replace silent RETURN with assertions

---

#### 2.11 **test-conflict-resolution.sql** (Lines 27-36)
**Fix**: Replace silent RETURN with assertions

---

#### 2.12 **test-function-versioning.sql** (Lines 28-37)
**Fix**: Replace silent RETURN with assertions

---

#### 2.13 **test-proper-three-way-merge.sql** (7 silent failures)
**Lines 40-42, 88-90, 151-153, 197-198, 206-208, 286-288, 351-353**

**Current**:
```sql
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Test 1 FAILED: %', SQLERRM;  -- ❌ LOGS BUT DOESN'T FAIL
END $$;
```

**Fix**: Remove exception handlers, let exceptions propagate

---

#### 2.14 **test-three-way-merge-simple.sql** (2 silent failures)
**Lines 49-51, 74-76**

**Current**:
```sql
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAIL: %', SQLERRM;  -- ❌ LOGS BUT DOESN'T FAIL
END $$;
```

**Fix**: Remove exception handlers

---

#### 2.15 **test-ai.sql** (1 silent failure)
**Line 106-108**

**Current**:
```sql
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Failed to analyze: %', v_migration[1];  -- ❌ CONTINUES ON ERROR
END;
```

**Fix**:
- For transient failures (DB unavailable): Use `EXCEPTION WHEN connection_failure`
- For logic errors: Let exception propagate
- Document which errors are expected vs. unexpected

---

### Phase 3: Fix Shell Scripts (2 files)

#### 3.1 **tests/test-full.sh** (Line 121)
**Current**:
```bash
psql -U "$DB_USER" -d "$DB_NAME" -f "/pggit/sql/$module" 2>/dev/null || echo "    (Some warnings are expected)"
```

**Fix**: Fail on installation errors
```bash
psql -U "$DB_USER" -d "$DB_NAME" -f "/pggit/sql/$module" || {
    echo "ERROR: Failed to install module: $module"
    exit 1
}
```

---

#### 3.2 **tests/test-full.sh** - Install pggit core
**Current**: Not shown but implied from test-full.sh structure

**Fix**: Add explicit check after installation:
```bash
# Install pggit core
psql -f "install.sql" || {
    echo "ERROR: Failed to install pggit core"
    exit 1
}

# Verify core installation
psql -c "SELECT pggit.version()" > /dev/null || {
    echo "ERROR: pggit core installation verification failed"
    exit 1
}
```

---

### Phase 4: Fix GitHub Actions Workflow

#### 4.1 **.github/workflows/tests.yml**

**Current problems**:
- Line 83: `psql -f install.sql || true`
- Line 87: `psql -f pggit_performance.sql || true`
- Lines 90-94: Module installation with `|| echo "Warning: ..."`
- Line 345: Feature module installation with error dismissal
- Lines 512-514, 547-549: Test blocks with silent exception handling

**Fix Strategy**:

**4.1.1 - Core Installation (Lines 83-87)**

**Current**:
```yaml
- name: Install pggit core
  run: |
    psql -f install.sql || true
    psql -f pggit_performance.sql || true
```

**Fixed**:
```yaml
- name: Install pggit core
  run: |
    psql -f install.sql
    if [ $? -ne 0 ]; then
      echo "ERROR: Failed to install pggit core"
      exit 1
    fi

    # Verify installation
    psql -c "SELECT pggit.version()" || {
      echo "ERROR: pggit core verification failed"
      exit 1
    }

    psql -f pggit_performance.sql
    if [ $? -ne 0 ]; then
      echo "WARNING: Performance helpers failed to install (optional)"
      # Don't exit - performance helpers are optional
    fi
```

**4.1.2 - Feature Module Installation (Lines 90-94)**

**Current**:
```yaml
- name: Install feature modules
  run: |
    for file in 041_zero_downtime_deployment.sql ...; do
      psql -f "$file" 2>&1 | tee -a /tmp/feature_install.log || echo "Warning: $file had errors (may be expected)"
    done
```

**Fixed**:
```yaml
- name: Install feature modules
  run: |
    # Separate required from optional modules
    REQUIRED_MODULES=(
      "041_zero_downtime_deployment.sql"
      # Any truly required modules
    )

    OPTIONAL_MODULES=(
      "050_three_way_merge.sql"
      "030_ai_migration_analysis.sql"
      # Other optional modules
    )

    # Install required modules - fail if any fail
    for file in "${REQUIRED_MODULES[@]}"; do
      if [ -f "$file" ]; then
        psql -f "$file" || {
          echo "ERROR: Required module $file failed to install"
          exit 1
        }
      fi
    done

    # Install optional modules - warn but don't fail
    for file in "${OPTIONAL_MODULES[@]}"; do
      if [ -f "$file" ]; then
        if ! psql -f "$file" 2>&1 | tee -a /tmp/feature_install.log; then
          echo "WARNING: Optional module $file failed to install (skipping tests for this feature)"
        fi
      fi
    done
```

**4.1.3 - Test Execution (Lines 512-514, 547-549)**

**Current** (Deployment mode test):
```yaml
- name: Test deployment mode
  run: |
    psql << 'EOF'
    DO $$
    BEGIN
      ...
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Deployment mode test skipped: %', SQLERRM;
    END;
    $$ ;
    EOF
```

**Fixed**:
```yaml
- name: Test deployment mode (if feature installed)
  run: |
    psql << 'EOF'
    DO $$
    BEGIN
      -- Check if feature is installed
      IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit_deployment') THEN
        -- Feature not installed - skip this test (exit silently)
        -- This is OK because it's a feature module that's optional
        RAISE NOTICE 'INFO: Deployment mode feature not installed - skipping this test';
      ELSE
        -- Feature is installed - test it and fail if there's an error
        -- (No exception handler - let errors propagate)
        PERFORM pggit.start_zero_downtime_deployment(...);
        RAISE NOTICE 'PASS: Deployment mode test passed';
      END IF;
    END;
    $$ ;
    EOF
```

---

### Phase 5: Testing & Verification

#### 5.1 Unit Test: Each Modified File
For each modified SQL test file:
```bash
# Run the specific test
psql -f tests/test-cqrs-support.sql

# Should either:
# - PASS with PASS/FAIL notices
# - FAIL with explicit error (if feature missing or test fails)
# NOT: Pass silently or skip with warnings
```

#### 5.2 Integration Test: Full Suite
```bash
./tests/test-full.sh

# Should show:
# - Clear pass/fail for each test
# - Installation errors fail the suite
# - Feature module errors are visible
```

#### 5.3 CI/CD Test: GitHub Actions
```bash
# Run test workflow
gh workflow run tests.yml

# Should show:
# - All installation steps succeed or fail clearly
# - No "may be expected" errors
# - Test results are accurate
```

#### 5.4 Chaos Tests: Verify Still Pass
```bash
pytest tests/chaos/ -v

# Should show:
# - Same test results as before
# - No new failures introduced
# - Clear skip messages if features aren't installed
```

---

## Part 4: Implementation Checklist

### Phase 1: Create Infrastructure
- [ ] Create `sql/test_helpers.sql` with assertion functions
- [ ] Add `test_helpers.sql` to `install.sql` (early, before tests)
- [ ] Create `tests/chaos/test_assertions.py` with FeatureRequirement class
- [ ] Update conftest.py to use new assertion utilities

### Phase 2: Fix SQL Tests (Highest Priority)
- [ ] Fix test-cqrs-support.sql (1 file, 1 major issue)
- [ ] Fix test-data-branching.sql (6 fixes)
- [ ] Fix test-cold-hot-storage.sql (9 fixes)
- [ ] Fix test-diff-functionality.sql (1 fix)
- [ ] Fix test-three-way-merge.sql (1 fix)
- [ ] Fix test-configuration-system.sql (2 fixes)
- [ ] Fix test-migration-integration.sql (1 fix)
- [ ] Fix test-zero-downtime.sql (1 fix)
- [ ] Fix test-advanced-features.sql (1 fix)
- [ ] Fix test-conflict-resolution.sql (1 fix)
- [ ] Fix test-function-versioning.sql (1 fix)
- [ ] Fix test-proper-three-way-merge.sql (7 fixes)
- [ ] Fix test-three-way-merge-simple.sql (2 fixes)
- [ ] Fix test-ai.sql (1 fix)

### Phase 3: Fix Shell Scripts
- [ ] Fix tests/test-full.sh installation error handling
- [ ] Add verification checks after installation

### Phase 4: Fix GitHub Actions Workflow
- [ ] Update .github/workflows/tests.yml core installation (lines 83-87)
- [ ] Update feature module installation (lines 90-94)
- [ ] Update test execution blocks (remove exception handlers)
- [ ] Add feature presence checks before optional tests

### Phase 5: Verification
- [ ] Test each SQL file individually
- [ ] Run test-full.sh end-to-end
- [ ] Run chaos tests
- [ ] Run GitHub Actions workflow
- [ ] Verify all failures are now visible (not silent)
- [ ] Document changes in PR

---

## Part 5: Success Criteria

### Before Fixes
```
PASS: test-cqrs-support.sql
PASS: test-data-branching.sql (but 6 internal failures hidden)
PASS: test-cold-hot-storage.sql (but 9 internal failures hidden)
PASS: GitHub Actions workflow (but installations may have failed silently)
```

### After Fixes
```
PASS: test-cqrs-support.sql (with proper PASS notices or FAIL with explicit error)
FAIL: test-cqrs-support.sql (if cqrs_change type missing - now visible!)
FAIL: GitHub Actions (if any module installation fails - now visible!)
PASS: All chaos tests (unchanged, still passing)
```

### Verification Checklist
- [ ] No silent exception handlers remain in SQL tests
- [ ] No `RETURN` statements in test blocks without preceding assertions
- [ ] All `EXCEPTION WHEN OTHERS` blocks either:
  - Handle specific known errors, OR
  - Re-raise with RAISE, OR
  - Are removed entirely
- [ ] No `|| true` in critical installation paths
- [ ] No "may be expected" errors in CI/CD workflows
- [ ] All test results clearly pass or fail (no hidden skips)
- [ ] Installation failures stop test execution

---

## Part 6: Risk Analysis

### Low Risk
- Creating new assertion functions (backward compatible, doesn't break existing tests)
- Fixing exception handlers that don't re-raise (these were bugs)
- Adding verification checks after installation

### Medium Risk
- Removing silent `RETURN` statements (may expose previously hidden bugs)
- Changing exception handling in optional feature tests

### Mitigation Strategy
1. Fix Phase 1 (infrastructure) first
2. Fix Phase 2 (SQL tests) one file at a time, test each individually
3. Fix Phase 3-4 (shell scripts and CI/CD) together with proper verification
4. Run full test suite after each phase

---

## Part 7: Maintenance Going Forward

### Guidelines for New Tests
1. Always use explicit assertions: `PERFORM pggit.assert_function_exists(...)`
2. Never use `RETURN` to skip tests - use assertions instead
3. Never use `EXCEPTION WHEN OTHERS` - use specific exception types
4. Let exceptions propagate unless handling a specific known case
5. Use `pytest.skip()` in Python tests only for truly optional features

### Documentation
1. Add comment to test files explaining what features they test
2. Document required vs. optional modules in install.sql
3. Create test README with feature dependencies

---

## Effort Estimation

| Phase | Task | Scope | Effort |
|-------|------|-------|--------|
| 1 | Create test_helpers.sql | 1 file | 30 min |
| 1 | Create test_assertions.py | 1 file | 20 min |
| 2 | Fix SQL tests | 14 files, ~38 issues | 3-4 hours |
| 3 | Fix shell scripts | 2 files | 30 min |
| 4 | Fix GitHub Actions | 1 file | 1 hour |
| 5 | Verification & testing | Full suite | 2-3 hours |
| **Total** | | | **7-9 hours** |

---

## Next Steps

1. Review this plan and confirm approach
2. Start with Phase 1 (infrastructure) - lowest risk
3. Proceed through phases sequentially
4. Test after each phase
5. Document findings and update guidelines
