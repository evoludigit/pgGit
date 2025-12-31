# pgGit Extension Migration Plan

**Goal**: Convert pgGit from SQL-file-based installation to a proper PostgreSQL extension with working Getting Started guide.

**Date**: 2025-12-31
**Status**: Planning
**Priority**: Critical (blocking new user adoption)

---

## Executive Summary

**Current State**: pgGit is not a standard PostgreSQL extension. Users must manually run SQL files, which doesn't work programmatically and isn't discoverable via `CREATE EXTENSION`.

**Desired State**: pgGit is a proper extension installable via:
```sql
CREATE EXTENSION pgcrypto;  -- Dependency
CREATE EXTENSION pggit;     -- One command, works everywhere
```

**Impact**:
- ✅ New users can follow standard PostgreSQL extension workflow
- ✅ Works in hosted environments (AWS RDS, Azure, etc.)
- ✅ Discoverable via `\dx` and pg_extension catalog
- ✅ Automatic dependency management
- ✅ Version upgrade path with ALTER EXTENSION

---

## Part 1: Analysis of Current Issues

### What the User Journey Tests Revealed

**Test Results: 6/6 FAILED**

| Test | Issue | Root Cause |
|------|-------|------------|
| Installation | pgGit schema not created | `\i` meta-command doesn't work outside psql |
| First Tracking | No version tracking | Installation failed, no event triggers |
| Schema Evolution | Version functions missing | Installation failed |
| Impact Analysis | get_impact_analysis() doesn't exist | Installation failed |
| Migration Generation | generate_migration() doesn't exist | Installation failed |
| Complete API | All functions missing | Installation failed |

**Cascade Failure**: Everything depends on installation working.

### Current Architecture Problems

1. **No Extension Control File**
   - Missing `pggit.control` with proper metadata
   - Current file has wrong `module_pathname` (references non-existent C library)

2. **No Version SQL File**
   - Standard extensions need `extension--version.sql` (e.g., `pggit--1.0.0.sql`)
   - Current approach uses `sql/install.sql` with `\i` includes

3. **Psql-Specific Installation**
   - Uses `\i` meta-commands
   - Uses `\echo` for output
   - Only works in psql CLI, not programmatic connections

4. **Fragmented SQL Files**
   - 30+ separate SQL files in `sql/` directory
   - No single consolidated extension file
   - Makes it hard to install programmatically

5. **Missing Dependency Declaration**
   - Requires `pgcrypto` but doesn't enforce it
   - Will fail silently if missing

6. **No Upgrade Path**
   - Can't use `ALTER EXTENSION pggit UPDATE TO '2.0.0'`
   - Manual migration required

---

## Part 2: What is a "Proper PostgreSQL Extension"?

### Required Components

**1. Extension Control File** (`pggit.control`)
```ini
# pggit extension control file
comment = 'Git-like version control for PostgreSQL schemas'
default_version = '1.0.0'
relocatable = false
schema = pggit
requires = 'pgcrypto'
superuser = true
```

**2. Version SQL File** (`pggit--1.0.0.sql`)
```sql
-- Consolidated SQL for pgGit version 1.0.0
-- All CREATE statements in dependency order
-- No \i includes, no \echo commands
```

**3. Optional: Upgrade Scripts** (`pggit--1.0.0--1.1.0.sql`)
```sql
-- ALTER statements to upgrade from 1.0.0 to 1.1.0
```

**4. Installation in SHAREDIR**
```bash
$SHAREDIR/extension/
├── pggit.control
├── pggit--1.0.0.sql
└── pggit--1.0.0--1.1.0.sql  # Future
```

### How Standard Extensions Work

```sql
-- User runs:
CREATE EXTENSION pggit;

-- PostgreSQL automatically:
-- 1. Checks pggit.control for dependencies
-- 2. Installs required extensions (pgcrypto)
-- 3. Reads pggit--1.0.0.sql
-- 4. Executes all SQL in a transaction
-- 5. Records in pg_extension catalog
```

**Benefits:**
- ✅ Atomic installation (all or nothing)
- ✅ Dependency management
- ✅ Version tracking
- ✅ Discoverable (`\dx`, pg_available_extensions)
- ✅ Works in all environments (RDS, containers, etc.)

---

## Part 3: Implementation Plan

### Phase 1: Consolidate SQL Files

**Objective**: Create single `pggit--1.0.0.sql` from current SQL files.

**Input**:
- `sql/001_schema.sql` through `sql/061_advanced_ml_optimization.sql`
- `sql/install.sql` (defines load order)

**Output**:
- `pggit--1.0.0.sql` (single consolidated file)

**Steps:**

1. **Analyze Dependency Order**
   ```bash
   # Current install.sql defines order:
   cat sql/install.sql | grep "\\i " | sed 's/\\i //'
   ```
   Result:
   ```
   001_schema.sql
   002_event_triggers.sql
   003_migration_functions.sql
   test_helpers.sql
   004_utility_views.sql
   ... (30+ files)
   ```

2. **Create Consolidation Script**
   ```bash
   #!/bin/bash
   # scripts/create_extension_sql.sh

   OUTPUT="pggit--1.0.0.sql"
   echo "-- pgGit Extension v1.0.0" > $OUTPUT
   echo "-- Consolidated from sql/*.sql files" >> $OUTPUT
   echo "" >> $OUTPUT

   # Read files in order from install.sql
   while read -r file; do
       if [[ $file == \\i* ]]; then
           filename=$(echo $file | sed 's/\\i //')
           echo "-- From: $filename" >> $OUTPUT
           cat "sql/$filename" >> $OUTPUT
           echo "" >> $OUTPUT
       fi
   done < sql/install.sql
   ```

3. **Remove Psql Meta-Commands**
   ```bash
   # Strip \echo, \i, and other psql-only commands
   sed -i '/^\\echo/d' pggit--1.0.0.sql
   sed -i '/^\\i /d' pggit--1.0.0.sql
   ```

4. **Validate SQL**
   ```bash
   # Check syntax
   psql -d postgres -f pggit--1.0.0.sql --dry-run

   # Or: Parse with pg_query
   python3 -c "
   import pg_query
   with open('pggit--1.0.0.sql') as f:
       pg_query.parse(f.read())
   print('✅ SQL is valid')
   "
   ```

5. **Test Installation**
   ```sql
   DROP SCHEMA IF EXISTS pggit CASCADE;
   \i pggit--1.0.0.sql

   -- Verify schema exists
   SELECT count(*) FROM pg_namespace WHERE nspname = 'pggit';

   -- Verify functions exist
   SELECT count(*) FROM pg_proc p
   JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'pggit';
   ```

**Acceptance Criteria:**
- [ ] `pggit--1.0.0.sql` contains all SQL from current install.sql
- [ ] No `\i` or `\echo` commands remain
- [ ] File loads without errors in fresh database
- [ ] All functions and tables created
- [ ] Event triggers active

---

### Phase 2: Create Extension Control File

**Objective**: Define extension metadata in proper format.

**Output**: `pggit.control`

**Implementation:**

```ini
# pggit.control
# Extension control file for pgGit

# Basic metadata
comment = 'Git-like version control for PostgreSQL schemas with automatic tracking'
default_version = '1.0.0'
module_pathname = '$libdir/pggit'
relocatable = false
schema = pggit
superuser = true

# Dependencies
requires = 'pgcrypto'

# Optional metadata
trusted = false
```

**Key Decisions:**

1. **`module_pathname = '$libdir/pggit'`**
   - pgGit currently has NO C extension
   - This line should be REMOVED (pure SQL extension)
   - If removed, PostgreSQL won't look for .so file

2. **`schema = pggit`**
   - Forces all objects into pggit schema
   - Users can't override
   - Matches current behavior

3. **`requires = 'pgcrypto'`**
   - pgGit uses pgcrypto functions
   - PostgreSQL will auto-install if available
   - Will error if pgcrypto not available

4. **`superuser = true`**
   - Event triggers require superuser
   - Can't be relaxed without removing triggers

**Updated Control File** (no C extension):
```ini
# pggit.control
comment = 'Git-like version control for PostgreSQL schemas'
default_version = '1.0.0'
relocatable = false
schema = pggit
requires = 'pgcrypto'
superuser = true
```

**Testing:**
```bash
# Validate control file
pg_config --sharedir
# Copy to: /usr/share/postgresql/17/extension/pggit.control

# Try to create extension
psql -d testdb -c "CREATE EXTENSION pggit;"
```

**Acceptance Criteria:**
- [ ] pggit.control exists in repo root
- [ ] No module_pathname (pure SQL)
- [ ] Declares pgcrypto dependency
- [ ] Valid .control syntax

---

### Phase 3: Update Makefile for Extension Installation

**Objective**: Use PGXS (PostgreSQL Extension System) to install properly.

**Current Makefile** (broken):
```makefile
EXTENSION = pggit
DATA = pggit--1.0.0.sql
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Custom install target (WRONG - overrides PGXS)
install:
	@echo "Installing pgGit extension..."
	@cd sql && psql -f install.sql
```

**Fixed Makefile**:
```makefile
# pgGit Extension Makefile

EXTENSION = pggit
DATA = pggit--1.0.0.sql
DOCS = README.md

# Use standard PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# REMOVE custom install target - use PGXS default
# PGXS automatically installs:
# - pggit.control to $SHAREDIR/extension/
# - pggit--1.0.0.sql to $SHAREDIR/extension/

# Optional: Add build target to create consolidated SQL
build: pggit--1.0.0.sql

pggit--1.0.0.sql:
	@echo "Creating consolidated extension SQL..."
	@./scripts/create_extension_sql.sh

# Development helpers
clean:
	@echo "Cleaning generated files..."
	@rm -f pggit--1.0.0.sql

.PHONY: build clean
```

**What PGXS Does**:
```bash
make install
# Automatically:
# 1. Copies pggit.control -> $SHAREDIR/extension/
# 2. Copies pggit--1.0.0.sql -> $SHAREDIR/extension/
# 3. Sets correct permissions
```

**Acceptance Criteria:**
- [ ] Makefile uses PGXS correctly
- [ ] No custom install target
- [ ] `make install` copies files to correct location
- [ ] Can CREATE EXTENSION after make install

---

### Phase 4: Update Getting Started Guide

**Objective**: Update documentation to match new extension-based installation.

**Current Guide** (Chapter 2):
```markdown
## Installation

```bash
git clone https://github.com/your-repo/pggit
cd pggit
make
sudo make install
psql -d her_database -c "CREATE EXTENSION pggit;"
```
```

**Issues:**
1. ✅ Actually correct now! (once we fix extension)
2. ❌ Doesn't mention pgcrypto dependency
3. ❌ Doesn't show how to verify installation

**Updated Guide**:
```markdown
## Chapter 2: The Five-Minute Setup

### Prerequisites

- PostgreSQL 14+ (17 recommended)
- PostgreSQL development headers (`postgresql-server-dev-17`)
- pgcrypto extension available
- Superuser access

### Installation

**Step 1: Install pgcrypto** (required dependency)
```sql
psql -d your_database -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
```

**Step 2: Build and install pgGit**
```bash
git clone https://github.com/your-repo/pggit
cd pggit

# Build (consolidates SQL files)
make

# Install extension files
sudo make install
```

**Step 3: Enable in your database**
```sql
psql -d your_database <<SQL
-- Install pgGit extension
CREATE EXTENSION pggit;

-- Verify installation
\dx pggit

-- Should see:
-- Name | Version | Schema |  Description
-- pggit | 1.0.0   | pggit  | Git-like version control...
SQL
```

**Troubleshooting**:

*"ERROR: could not open extension control file"*
- Make sure `make install` completed
- Check: `ls $(pg_config --sharedir)/extension/pggit*`

*"ERROR: required extension pgcrypto is not installed"*
- Run: `CREATE EXTENSION pgcrypto;` first

*"ERROR: permission denied"*
- pgGit requires superuser (for event triggers)
- Connect as postgres user or database owner
```

**Changes:**
1. ✅ Add pgcrypto prerequisite
2. ✅ Show verification step
3. ✅ Add troubleshooting section
4. ✅ Explain superuser requirement

**Acceptance Criteria:**
- [ ] Getting Started updated
- [ ] Shows pgcrypto installation
- [ ] Includes verification steps
- [ ] Has troubleshooting section
- [ ] All code examples tested

---

### Phase 5: Fix Test Scenarios

**Objective**: Make test scenarios work with proper extension installation.

**Current Issues:**

1. **01_installation.sql** - Uses `\i sql/install.sql` (doesn't work)
2. **03_schema_evolution.sql** - `DROP TABLE version_after` without IF EXISTS
3. **04_impact_analysis.sql** - Assumes users table from previous test

**Fixes:**

**1. Update 01_installation.sql**
```sql
-- User Journey Test: Chapter 2 - Installation
-- Tests: Fresh installation of pgGit extension
-- Expected: Extension installs without errors

-- Install required dependency
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Install pgGit extension
CREATE EXTENSION pggit;

-- Verify extension installed
SELECT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pggit'
) AS extension_installed;

-- Verify schema exists
SELECT EXISTS (
    SELECT 1 FROM pg_namespace WHERE nspname = 'pggit'
) AS schema_exists;

-- Verify event triggers installed
SELECT COUNT(*) >= 2 AS event_triggers_installed
FROM pg_event_trigger
WHERE evtname LIKE 'pggit_%';

-- Verify core functions exist
SELECT COUNT(*) >= 5 AS core_functions_exist
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'pggit'
AND p.proname IN (
    'get_version',
    'get_history',
    'get_impact_analysis',
    'show_table_versions',
    'generate_migration'
);

-- Test output
SELECT 'pgGit extension installed successfully' AS status;
```

**2. Update 03_schema_evolution.sql**
```sql
-- Make temp tables IF NOT EXISTS
CREATE TEMP TABLE IF NOT EXISTS version_before AS ...
CREATE TEMP TABLE IF NOT EXISTS version_after AS ...

-- Drop with IF EXISTS
DROP TABLE IF EXISTS version_before;
DROP TABLE IF EXISTS version_after;
```

**3. Make scenarios independent**
```sql
-- Each scenario should create its own test data
-- Don't depend on previous scenarios

-- 02_first_tracking.sql
DROP TABLE IF EXISTS users CASCADE;
CREATE TABLE users (...);

-- 04_impact_analysis.sql
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS user_reports CASCADE;
DROP VIEW IF EXISTS user_summary CASCADE;

-- Create fresh test data
CREATE TABLE users (...);
CREATE TABLE user_reports (...);
CREATE VIEW user_summary AS ...;
```

**Acceptance Criteria:**
- [ ] All scenarios use CREATE EXTENSION
- [ ] All DROP statements use IF EXISTS
- [ ] Each scenario is independent
- [ ] No \i or \echo commands
- [ ] All 6 tests pass

---

### Phase 6: Create Extension Build Script

**Objective**: Automate creation of pggit--1.0.0.sql from source files.

**Script**: `scripts/create_extension_sql.sh`

```bash
#!/bin/bash
set -e

# Create consolidated extension SQL from individual files
# This script reads sql/install.sql and combines all referenced files

OUTPUT="pggit--1.0.0.sql"
SQL_DIR="sql"
INSTALL_FILE="$SQL_DIR/install.sql"

echo "Creating pgGit extension SQL: $OUTPUT"
echo ""

# Header
cat > "$OUTPUT" <<'EOF'
-- pgGit Extension v1.0.0
-- Git-like version control for PostgreSQL schemas
--
-- This file is auto-generated from sql/*.sql files
-- DO NOT EDIT MANUALLY - changes will be overwritten
--
-- To regenerate: make build
-- To install: make install && CREATE EXTENSION pggit;

EOF

# Track what we've included
declare -A included_files

# Read install.sql and process \i directives
while IFS= read -r line; do
    # Skip comments and empty lines
    if [[ $line =~ ^[[:space:]]*-- ]] || [[ -z "${line// }" ]]; then
        continue
    fi

    # Handle \i directive
    if [[ $line =~ ^\\i[[:space:]]+(.+)$ ]]; then
        file="${BASH_REMATCH[1]}"
        filepath="$SQL_DIR/$file"

        # Skip if already included
        if [[ -n "${included_files[$file]}" ]]; then
            echo "⚠️  Skipping duplicate: $file"
            continue
        fi

        # Check file exists
        if [[ ! -f "$filepath" ]]; then
            echo "❌ File not found: $filepath"
            exit 1
        fi

        echo "✅ Including: $file"
        included_files[$file]=1

        # Add separator comment
        echo "" >> "$OUTPUT"
        echo "-- ============================================================================" >> "$OUTPUT"
        echo "-- Source: $file" >> "$OUTPUT"
        echo "-- ============================================================================" >> "$OUTPUT"
        echo "" >> "$OUTPUT"

        # Append file content, stripping psql meta-commands
        grep -v "^\\\\echo" "$filepath" | grep -v "^\\\\i " >> "$OUTPUT"

    # Skip \echo
    elif [[ $line =~ ^\\echo ]]; then
        continue
    fi

done < "$INSTALL_FILE"

# Validate SQL syntax
echo ""
echo "Validating SQL syntax..."
python3 -c "
import sys
try:
    import pg_query
    with open('$OUTPUT') as f:
        pg_query.parse(f.read())
    print('✅ SQL syntax valid')
except ImportError:
    print('⚠️  pg_query not installed, skipping validation')
    print('   Install with: pip install pg_query')
except Exception as e:
    print(f'❌ SQL syntax error: {e}')
    sys.exit(1)
"

# Summary
echo ""
echo "📊 Extension file created:"
echo "   Output: $OUTPUT"
echo "   Size: $(wc -c < "$OUTPUT" | numfmt --to=iec-i --suffix=B)"
echo "   Lines: $(wc -l < "$OUTPUT")"
echo "   Files: ${#included_files[@]}"
echo ""
echo "Next steps:"
echo "  1. Review: less $OUTPUT"
echo "  2. Install: sudo make install"
echo "  3. Enable: psql -c 'CREATE EXTENSION pggit;'"
```

**Make it executable:**
```bash
chmod +x scripts/create_extension_sql.sh
```

**Acceptance Criteria:**
- [ ] Script consolidates all SQL files
- [ ] Removes psql meta-commands
- [ ] Validates syntax
- [ ] Output is loadable by PostgreSQL
- [ ] Idempotent (can run multiple times)

---

### Phase 7: Test in Clean Environment

**Objective**: Verify extension works in Docker (simulates new user).

**Test Script**: `tests/user-journey/validate_extension.sh`

```bash
#!/bin/bash
set -e

echo "=== pgGit Extension Validation ==="
echo ""

# 1. Build extension
echo "Step 1: Building extension..."
make clean
make build

# Verify output exists
if [[ ! -f "pggit--1.0.0.sql" ]]; then
    echo "❌ pggit--1.0.0.sql not created"
    exit 1
fi
echo "✅ Extension SQL created"
echo ""

# 2. Install extension files
echo "Step 2: Installing extension files..."
sudo make install

# Verify installation
SHAREDIR=$(pg_config --sharedir)
if [[ ! -f "$SHAREDIR/extension/pggit.control" ]]; then
    echo "❌ pggit.control not installed"
    exit 1
fi
if [[ ! -f "$SHAREDIR/extension/pggit--1.0.0.sql" ]]; then
    echo "❌ pggit--1.0.0.sql not installed"
    exit 1
fi
echo "✅ Extension files installed"
echo ""

# 3. Create test database
echo "Step 3: Creating test database..."
dropdb --if-exists pggit_extension_test
createdb pggit_extension_test
echo "✅ Test database created"
echo ""

# 4. Install extension
echo "Step 4: Installing pgGit extension..."
psql -d pggit_extension_test <<SQL
-- Install dependency
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Install pgGit
CREATE EXTENSION pggit;

-- Verify
\dx pggit
SQL

echo "✅ Extension installed"
echo ""

# 5. Run user journey tests
echo "Step 5: Running user journey tests..."
cd tests/user-journey
docker-compose down -v
docker-compose up --build --abort-on-container-exit

# Check exit code
if [[ $? -eq 0 ]]; then
    echo "✅ All user journey tests passed"
else
    echo "❌ Some tests failed"
    exit 1
fi

echo ""
echo "=== ✅ Extension validation complete ==="
```

**Acceptance Criteria:**
- [ ] Script runs without errors
- [ ] Extension installs in clean database
- [ ] All 6 user journey tests pass
- [ ] Works in Docker environment

---

## Part 4: Testing Strategy

### Test Levels

**Level 1: Unit Tests** (SQL functions)
```sql
-- tests/test_extension_unit.sql

BEGIN;

-- Test 1: Extension loads
CREATE EXTENSION pggit;
SELECT * FROM pg_extension WHERE extname = 'pggit';

-- Test 2: Schema created
SELECT * FROM pg_namespace WHERE nspname = 'pggit';

-- Test 3: Functions exist
SELECT count(*) FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'pggit';

-- Test 4: Event triggers active
SELECT count(*) FROM pg_event_trigger WHERE evtname LIKE 'pggit_%';

ROLLBACK;
```

**Level 2: Integration Tests** (scenarios)
```bash
# Run all 6 user journey scenarios
pytest tests/user-journey/test_user_journey.py -v
```

**Level 3: Upgrade Tests** (future)
```sql
-- Install v1.0.0
CREATE EXTENSION pggit VERSION '1.0.0';

-- Upgrade to v1.1.0
ALTER EXTENSION pggit UPDATE TO '1.1.0';

-- Verify upgrade
SELECT extversion FROM pg_extension WHERE extname = 'pggit';
```

### Continuous Integration

**GitHub Actions**: `.github/workflows/extension-tests.yml`
```yaml
name: Extension Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-22.04

    services:
      postgres:
        image: postgres:17
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Install PostgreSQL dev tools
        run: |
          sudo apt-get update
          sudo apt-get install -y postgresql-server-dev-17

      - name: Build extension
        run: make build

      - name: Install extension
        run: sudo make install

      - name: Run unit tests
        run: |
          psql -h localhost -U postgres -f tests/test_extension_unit.sql

      - name: Run user journey tests
        run: |
          cd tests/user-journey
          docker-compose up --abort-on-container-exit
```

---

## Part 5: Migration Path

### For Existing Users

**Current Installation** (before migration):
```bash
cd pggit
psql -d mydb -f sql/install.sql
```

**New Installation** (after migration):
```bash
cd pggit
make build
sudo make install
psql -d mydb -c "CREATE EXTENSION pggit;"
```

**Migration Script** for existing installations:

```sql
-- migrate_to_extension.sql
-- Migrates existing pgGit installation to extension format

BEGIN;

-- 1. Verify pgGit is currently installed
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'pggit') THEN
        RAISE EXCEPTION 'pgGit schema not found. Run sql/install.sql first.';
    END IF;
END $$;

-- 2. Check version compatibility
-- (Add version detection logic here)

-- 3. Register as extension
INSERT INTO pg_extension (
    extname,
    extowner,
    extnamespace,
    extrelocatable,
    extversion
) VALUES (
    'pggit',
    (SELECT oid FROM pg_roles WHERE rolname = current_user),
    (SELECT oid FROM pg_namespace WHERE nspname = 'pggit'),
    false,
    '1.0.0'
);

-- 4. Record extension dependencies
INSERT INTO pg_depend (
    classid,
    objid,
    objsubid,
    refclassid,
    refobjid,
    refobjsubid,
    deptype
)
SELECT
    'pg_extension'::regclass,
    (SELECT oid FROM pg_extension WHERE extname = 'pggit'),
    0,
    c.tableoid,
    c.oid,
    0,
    'e'
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'pggit';

COMMIT;

-- Verify
\dx pggit
```

---

## Part 6: Documentation Updates

### Files to Update

1. **README.md**
   - Update installation instructions
   - Add extension approach
   - Update quick start

2. **docs/getting-started/Getting_Started.md**
   - Rewrite Chapter 2 (installation)
   - Add pgcrypto prerequisite
   - Add troubleshooting

3. **docs/getting-started/Troubleshooting.md**
   - Add extension-specific issues
   - "Extension not found"
   - "Permission denied"

4. **INSTALL.md** (new file)
   ```markdown
   # Installation Guide

   ## Quick Start

   ```bash
   make build
   sudo make install
   psql -d yourdb -c "CREATE EXTENSION pggit;"
   ```

   ## Detailed Instructions
   [...]
   ```

5. **CHANGELOG.md**
   ```markdown
   # v1.0.0 (2025-01-XX)

   ## Breaking Changes
   - Converted to proper PostgreSQL extension
   - Installation now uses `CREATE EXTENSION pggit`
   - Requires pgcrypto extension

   ## Migration
   - See MIGRATION.md for upgrading from SQL-based installation
   ```

---

## Part 7: Implementation Timeline

### Week 1: Core Extension

- [ ] Day 1: Create `scripts/create_extension_sql.sh`
- [ ] Day 2: Generate and test `pggit--1.0.0.sql`
- [ ] Day 3: Update `pggit.control`
- [ ] Day 4: Fix Makefile (remove custom install)
- [ ] Day 5: Test installation on clean PostgreSQL

### Week 2: Testing & Documentation

- [ ] Day 1: Fix test scenarios (01-06)
- [ ] Day 2: Run user journey tests, fix failures
- [ ] Day 3: Update Getting Started guide
- [ ] Day 4: Update README and INSTALL docs
- [ ] Day 5: Create migration guide for existing users

### Week 3: CI/CD & Polish

- [ ] Day 1: Create extension validation script
- [ ] Day 2: Add GitHub Actions workflow
- [ ] Day 3: Test on multiple PostgreSQL versions (14, 15, 16, 17)
- [ ] Day 4: Test on multiple platforms (Ubuntu, Debian, macOS)
- [ ] Day 5: Final review and release prep

---

## Part 8: Success Criteria

### Functional

- [ ] `CREATE EXTENSION pggit;` works
- [ ] All user journey tests pass (6/6)
- [ ] Extension listed in `\dx`
- [ ] Dependencies auto-installed
- [ ] Works on fresh PostgreSQL installation

### Documentation

- [ ] Getting Started guide accurate
- [ ] Installation steps tested
- [ ] All code examples work
- [ ] Troubleshooting covers common issues

### Quality

- [ ] No manual SQL file execution needed
- [ ] Works programmatically (Python, apps)
- [ ] CI/CD validates on every commit
- [ ] Upgrade path documented

---

## Part 9: Rollback Plan

If extension migration fails:

1. **Keep current installation method**
   - Don't remove `sql/install.sql`
   - Keep as fallback option

2. **Document both approaches**
   ```markdown
   ## Installation

   ### Method 1: Extension (Recommended)
   make install && CREATE EXTENSION pggit;

   ### Method 2: Manual SQL (Legacy)
   psql -f sql/install.sql
   ```

3. **Version marker**
   - v0.x.x = SQL-based installation
   - v1.x.x = Extension-based installation

---

## Part 10: Future Enhancements

### After v1.0.0

1. **Upgrade Scripts**
   ```
   pggit--1.0.0--1.1.0.sql
   pggit--1.1.0--2.0.0.sql
   ```

2. **C Extension** (optional)
   - Faster DDL parsing
   - Better diff algorithms
   - Compiled functions

3. **Package Distribution**
   - PGXN (PostgreSQL Extension Network)
   - Debian packages
   - Homebrew formula

4. **Cloud Provider Support**
   - AWS RDS extension
   - Azure Database for PostgreSQL
   - Google Cloud SQL

---

## Summary Checklist

**Prerequisites:**
- [ ] PostgreSQL 14+ installed
- [ ] Dev tools (postgresql-server-dev)
- [ ] Python 3.11+ (for tests)
- [ ] Docker (for CI tests)

**Phase 1: Core Extension**
- [ ] Create consolidation script
- [ ] Generate pggit--1.0.0.sql
- [ ] Update pggit.control
- [ ] Fix Makefile
- [ ] Test installation

**Phase 2: Testing**
- [ ] Fix test scenarios
- [ ] Run user journey tests
- [ ] All 6 tests pass
- [ ] CI/CD configured

**Phase 3: Documentation**
- [ ] Update Getting Started
- [ ] Update README
- [ ] Create INSTALL.md
- [ ] Migration guide

**Final Validation:**
- [ ] Works in Docker
- [ ] Works on PostgreSQL 17
- [ ] All tests green
- [ ] Documentation accurate

---

**Total Estimated Effort**: 2-3 weeks (1 developer)
**Risk Level**: Medium (architectural change, backward compatibility)
**User Impact**: High (much better experience for new users)

**Next Step**: Review plan → Create Phase 1 issues → Begin implementation
