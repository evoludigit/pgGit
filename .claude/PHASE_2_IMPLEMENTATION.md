# Phase 2: Branch Management Implementation

**Status**: Skeleton Complete, Ready for Implementation
**Branch**: main
**Commit**: bdc983c
**Location**: /home/lionel/code/pggit

---

## Quick Start for Agent

If you're relaunching an agent in this repository:

1. **Review the full plan**:
   ```bash
   cat .claude/PHASE_2_PLAN.md
   ```

2. **Understand the skeleton**:
   ```bash
   cat sql/030_pggit_branch_management.sql
   cat tests/unit/test_phase2_branch_management.py
   ```

3. **Key Files**:
   - **SQL Implementation**: `sql/030_pggit_branch_management.sql` (lines 49-318)
   - **Test Suite**: `tests/unit/test_phase2_branch_management.py` (1,454 lines, 34 tests)
   - **Schema Reference**: `sql/001_schema.sql` (Phase 1)

4. **Database Setup** (for testing):
   ```bash
   # Set environment variables if not using defaults
   export PGGIT_DB_HOST=localhost
   export PGGIT_DB_PORT=5432
   export PGGIT_DB_USER=postgres
   export PGGIT_DB_PASSWORD=postgres
   export PGGIT_DB_NAME=pggit_test

   # Run tests
   pytest tests/unit/test_phase2_branch_management.py -v
   ```

---

## What's Done (Phase 1)

✅ Schema design with 8 tables and proper constraints
✅ Utility functions (60 tests passing)
✅ Event trigger infrastructure
✅ Immutable audit trail

---

## What's Next (Phase 2 - This Implementation)

### Functions to Implement

**1. pggit.create_branch()** (Lines 49-101)
- Creates new branches from parent branches
- Validates input (name format, type, uniqueness)
- Copies parent's objects to new branch
- Returns complete branch information
- **Tests**: 10 (happy path, validation, hierarchy, metadata)

**2. pggit.delete_branch()** (Lines 130-170)
- Safely deletes branches with merge validation
- Prevents deletion of main branch
- Marks as DELETED (soft delete, not hard delete)
- Cascades cleanup to related data
- **Tests**: 9 (merge check, force flag, cascade, audit)

**3. pggit.list_branches()** (Lines 208-253)
- Lists branches with comprehensive metadata
- Filters by status (ACTIVE, MERGED, DELETED, CONFLICTED)
- Calculates metrics (object_count, storage_bytes)
- Supports ordering by created_at, name, status
- **Tests**: 8 (filtering, ordering, hierarchy)

**4. pggit.checkout_branch()** (Lines 281-318)
- Switches current branch in session
- Uses session variables (GUC: pggit.current_branch)
- Verifies branch is ACTIVE
- Returns previous and current branch
- **Tests**: 7 (session state, persistence, tracking)

---

## Implementation Strategy

### Day 2: Create & Delete
- Implement `pggit.create_branch()` (~80 lines)
- Implement `pggit.delete_branch()` (~70 lines)
- Run and pass create/delete tests

### Day 3: List & Checkout
- Implement `pggit.list_branches()` (~100 lines)
- Implement `pggit.checkout_branch()` (~50 lines)
- Run and pass list/checkout tests

### Day 4: Full Testing
- Run complete test suite
- Fix any failures
- Achieve 100% pass rate (34/34 tests)

### Day 5: Commit & Documentation
- Write function docstrings
- Create Phase 2 summary
- Commit with [GREEN] tag

---

## Key Design Decisions

### Soft Deletes
- Branch rows are marked as DELETED, never actually removed
- Preserves immutable audit trail
- Maintains referential integrity

### Session Variables
- `pggit.current_branch` tracks active branch per session
- SET/GET via PostgreSQL GUC mechanism
- Session-only, not persisted across connections

### Object Copying
- New branches get complete copy of parent's active objects
- Each branch is independent
- Enables safe parallel development

### Validation
- Input validation at function boundary
- Regex for branch names: `^[a-zA-Z0-9._/#-]+$`
- Enum validation for branch types: standard|tiered|temporal|compressed

---

## Test Execution

All tests use pytest with PostgreSQL database backend:

```bash
# Run all Phase 2 tests
pytest tests/unit/test_phase2_branch_management.py -v

# Run specific test class
pytest tests/unit/test_phase2_branch_management.py::TestCreateBranch -v

# Run specific test
pytest tests/unit/test_phase2_branch_management.py::TestCreateBranch::test_create_branch_happy_path -v
```

Expected output:
```
tests/unit/test_phase2_branch_management.py::TestCreateBranch::test_create_branch_happy_path PASSED
tests/unit/test_phase2_branch_management.py::TestCreateBranch::test_create_branch_from_custom_parent PASSED
... (32 more tests)

======================== 34 passed in X.XXs ========================
```

---

## Git Workflow

```bash
# Current status
git log --oneline | head -5
# bdc983c feat(phase2): Create skeleton for branch management functions [RED]
# e93cad1 fix(phase-1): Fix trigger API and function parameter ambiguities - all 60 tests passing

# After implementation, commit with:
git add -A
git commit -m "feat(phase2): Implement branch management functions [GREEN]

- Implement pggit.create_branch() with full validation
- Implement pggit.delete_branch() with merge check
- Implement pggit.list_branches() with filtering
- Implement pggit.checkout_branch() with session state

All 34 tests passing. Ready for Phase 3."
```

---

## Database Schema Reference

### tables.branches
```sql
CREATE TABLE pggit.branches (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    parent_branch_id INTEGER REFERENCES pggit.branches(id),
    head_commit_hash TEXT,
    status pggit.branch_status DEFAULT 'ACTIVE',  -- ACTIVE|MERGED|DELETED|CONFLICTED
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER,
    merged_at TIMESTAMP,
    merged_by TEXT,
    branch_type TEXT DEFAULT 'standard',  -- standard|tiered|temporal|compressed
    total_objects INTEGER DEFAULT 0,
    modified_objects INTEGER DEFAULT 0,
    storage_efficiency DECIMAL(5,2) DEFAULT 100.00,
    description TEXT
);
```

### tables.objects (per-branch tracking)
```sql
-- Stores objects per branch
-- branch_name TEXT - tracks which branch this object belongs to
-- branch_id INTEGER - references pggit.branches(id)
-- is_active BOOLEAN - soft deletes within a branch
```

### Enum: branch_status
```sql
CREATE TYPE pggit.branch_status AS ENUM (
    'ACTIVE',       -- Branch is usable
    'MERGED',       -- Branch has been merged
    'DELETED',      -- Branch marked for deletion (soft delete)
    'CONFLICTED'    -- Branch has unresolved merge conflicts
);
```

---

## Common Issues & Solutions

### Connection Error
```
Error: Cannot connect to PostgreSQL at localhost:5432/pggit_test
```
**Solution**: Set environment variables
```bash
export PGGIT_DB_HOST=your_host
export PGGIT_DB_PORT=your_port
export PGGIT_DB_USER=your_user
export PGGIT_DB_PASSWORD=your_password
export PGGIT_DB_NAME=your_db
```

### Schema Not Found
```
Error: Cannot load Phase 1 schema
```
**Solution**: Ensure `sql/001_schema.sql` exists
```bash
ls -la sql/001_schema.sql
```

### Test Skipped
```
SKIPPED: Cannot connect to PostgreSQL...
```
**Solution**: Start PostgreSQL and set correct connection variables

---

## Additional Resources

- **Phase 2 Full Plan**: `.claude/PHASE_2_PLAN.md` (500+ lines, detailed specs)
- **Phase 1 Schema**: `sql/001_schema.sql`
- **Test Fixtures**: `tests/unit/test_phase2_branch_management.py` (lines 1-175)
- **Implementation Roadmap**: `docs/IMPLEMENTATION_ROADMAP.md`

---

## Next Phase

After Phase 2 is complete:
- **Phase 3**: Object Tracking (get_current_schema, get_object_definition, get_object_history)
- **Phase 4**: Merging & Conflicts (detect_merge_conflicts, find_merge_base, merge_branches)
- **Phase 5**: History & Audit (get_commit_history, get_audit_trail, time-travel)

---

**Ready to implement! Launch agent with**: `claude --cwd /home/lionel/code/pggit`
