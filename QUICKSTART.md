# pgGit v0.0.1 - Quick Start Guide

## Repository Setup (First Time)

```bash
cd /home/lionel/code/pggit

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -e ".[dev]"

# Verify installation
python -c "import psycopg; print('psycopg installed')"
```

## Database Setup

```bash
# Create test database
createdb pggit_test

# Initialize schema (from repo root)
cd /home/lionel/code/pggit
psql -d pggit_test -f sql/v1.0.0/phase_1_schema.sql
psql -d pggit_test -f sql/v1.0.0/phase_1_utilities.sql
psql -d pggit_test -f sql/v1.0.0/phase_1_triggers.sql
psql -d pggit_test -f sql/v1.0.0/phase_1_bootstrap.sql

# Verify (should show 8 tables)
psql -d pggit_test -c "\dt pggit.*"
```

## Running Tests

```bash
# Run all tests
pytest tests/ -v

# Run only schema tests
pytest tests/unit/test_phase_1_schema.py -v

# Run only utility tests
pytest tests/unit/test_phase_1_utilities.py -v

# With coverage report
pytest tests/ -v --cov --cov-report=html

# View coverage
open htmlcov/index.html
```

## Project Structure

```
pggit/
├── sql/v1.0.0/              ← Database schemas
│   ├── phase_1_schema.sql
│   ├── phase_1_utilities.sql
│   ├── phase_1_triggers.sql
│   └── phase_1_bootstrap.sql
├── tests/                    ← Test code
│   ├── conftest.py          ← Test fixtures
│   └── unit/
│       ├── test_phase_1_schema.py
│       └── test_phase_1_utilities.py
├── src/                      ← Python source (for future phases)
├── README.md                 ← Full documentation
├── PHASE_1_SUMMARY.md        ← Detailed completion summary
└── pyproject.toml            ← Python configuration
```

## Common Commands

```bash
# Check git status
git status

# View recent commits
git log --oneline -10

# Make a change and commit
git add .
git commit -m "feat(phase-1): Your description"

# View specific file
cat sql/v1.0.0/phase_1_schema.sql

# Query database
psql -d pggit_test -c "SELECT * FROM pggit.branches;"
```

## Database Queries

```bash
# Connect to test database
psql -d pggit_test

# Inside psql:
-- Check all tables exist
\dt pggit.*

-- Check all functions
\df pggit.*

-- Check main branch
SELECT * FROM pggit.branches WHERE branch_name = 'main';

-- Check configuration
SELECT * FROM pggit.configuration;

-- Check commits
SELECT * FROM pggit.commits;

-- Exit
\q
```

## Phase 1 Components

### Tables (8)
- `schema_objects` - Track objects with versioning
- `commits` - Git-like history
- `branches` - Development branches
- `object_history` - Audit trail
- `merge_operations` - Merge tracking
- `object_dependencies` - Dependency graph
- `data_tables` - Copy-on-write
- `configuration` - System config

### Functions (10+)
- `generate_sha256()` - Hashing
- `get_current_branch()` - Current branch
- `validate_identifier()` - Identifier validation
- `raise_pggit_error()` - Error handling
- `set_current_branch()` - Branch switching
- `get_current_schema_hash()` - Schema hash
- `normalize_sql()` - SQL normalization
- `get_object_by_name()` - Object lookup
- `get_commit_by_hash()` - Commit lookup
- `get_branch_by_name()` - Branch lookup

### Triggers (1)
- `pggit_ddl_capture` - Auto-capture DDL

## Environment Variables

```bash
export PGHOST=localhost
export PGPORT=5432
export PGUSER=postgres
export PGPASSWORD=password
export PGDATABASE=pggit_test
```

## Testing Checklist

- [ ] Database created
- [ ] All 4 SQL files executed
- [ ] All 8 tables present
- [ ] All 10+ functions work
- [ ] Main branch initialized
- [ ] Tests run without errors
- [ ] All 90+ tests pass
- [ ] Coverage > 85%

## Documentation

- `README.md` - Complete project documentation
- `PHASE_1_SUMMARY.md` - Phase 1 completion details
- `/tmp/pggit-api-spec/` - Complete specification

## Next Steps

1. Run full test suite: `pytest tests/ -v`
2. Fix any failures
3. Plan Phase 2 (branch management functions)
4. Read Phase 2 spec in `/tmp/pggit-api-spec/IMPLEMENTATION_ROADMAP.md`

## Troubleshooting

**Database connection error:**
```bash
# Check PostgreSQL is running
psql --version

# Check connection
psql -h localhost -U postgres -d postgres -c "SELECT 1"
```

**Tests failing:**
```bash
# Check test database exists
psql -l | grep pggit_test

# Recreate if needed
dropdb pggit_test
createdb pggit_test
pytest tests/ -v
```

**Import errors:**
```bash
# Reinstall dependencies
pip install -e ".[dev]" --force-reinstall
```

## Quick Links

- Schema design: `/tmp/pggit-api-spec/SCHEMA_DESIGN.md`
- Function specs: `/tmp/pggit-api-spec/API_SPECIFICATION.md`
- Roadmap: `/tmp/pggit-api-spec/IMPLEMENTATION_ROADMAP.md`
- This repo: `/home/lionel/code/pggit`
- Old backup: `/home/lionel/code/pggit.v0.1.1.bk`

---

**Status**: ✅ Phase 1 Complete
**Version**: 0.0.1
**Last Updated**: 2025-12-24
