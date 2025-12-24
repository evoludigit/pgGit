# 🚀 Agent Launch Guide - Phase 2 Implementation

**Location**: `/home/lionel/code/pggit`

If you're launching a new agent to continue Phase 2 implementation, start here.

---

## TL;DR - Quick Start

```bash
# 1. Read the implementation guide
cat .claude/PHASE_2_IMPLEMENTATION.md

# 2. Review the complete plan
cat .claude/PHASE_2_PLAN.md

# 3. Check the skeleton structure reference
cat .claude/SKELETON_STRUCTURE.md

# 4. Start implementing functions:
cat sql/030_pggit_branch_management.sql

# 5. Review tests:
cat tests/unit/test_phase2_branch_management.py
```

---

## What Is This?

This is **pgGit Phase 2: Branch Management** - implementing 4 core functions for creating, deleting, listing, and switching database branches.

**Status**: Skeleton created and reviewed ✅ | Ready for implementation ⏳

**Files**:
- SQL skeleton: `sql/030_pggit_branch_management.sql`
- Test skeleton: `tests/unit/test_phase2_branch_management.py`
- Plans: `.claude/PHASE_2_*.md`

---

## Current Progress

### ✅ Completed (Day 1)
- Comprehensive Phase 2 plan created
- SQL skeleton with 4 function signatures
- Test skeleton with 34 comprehensive tests
- Database fixtures adapted
- Helper functions for test utilities
- All files reviewed and improved
- Committed to main branch

### 📋 Current Stage
- Skeleton review complete and all issues fixed
- Ready for implementation
- All files in correct location with full documentation

### ⏳ TODO (Days 2-5)
1. Implement `pggit.create_branch()` (Day 2)
2. Implement `pggit.delete_branch()` (Day 2)
3. Implement `pggit.list_branches()` (Day 3)
4. Implement `pggit.checkout_branch()` (Day 3)
5. Run full test suite (Day 4)
6. Fix any failing tests (Day 4)
7. Commit with [GREEN] tag (Day 5)

---

## Key Documents to Read

### 1. PHASE_2_IMPLEMENTATION.md (START HERE)
**Purpose**: Quick start guide for agent launch
**Content**:
- Overview of Phase 2
- Function descriptions
- Implementation strategy
- Database setup instructions
- Git workflow
- Common issues & solutions

**Read**: `cat .claude/PHASE_2_IMPLEMENTATION.md`

### 2. PHASE_2_PLAN.md (REFERENCE)
**Purpose**: Detailed specification for all functions
**Content**:
- Complete Phase 2 specification (500+ lines)
- Architecture overview
- Each function with:
  - Implementation steps
  - Test cases
  - Key considerations
- Risk mitigation
- Success criteria

**Read**: `cat .claude/PHASE_2_PLAN.md`

### 3. SKELETON_STRUCTURE.md (IMPLEMENTATION GUIDE)
**Purpose**: Line-by-line reference to skeleton
**Content**:
- File structure with line numbers
- Each function implementation map
- Variable declarations
- Test class organization
- Test patterns
- Key implementation notes

**Read**: `cat .claude/SKELETON_STRUCTURE.md`

---

## The 4 Functions (Quick Reference)

| Function | Lines | Tests | Purpose |
|----------|-------|-------|---------|
| **create_branch()** | 49-101 | 10 | Create new branches from parent |
| **delete_branch()** | 130-170 | 9 | Safely delete branches |
| **list_branches()** | 208-253 | 8 | List branches with metadata |
| **checkout_branch()** | 281-318 | 7 | Switch branches in session |

Each has TODO blocks marking implementation steps.

---

## Implementation Workflow

### Step 1: Read the Plan
```bash
cat .claude/PHASE_2_IMPLEMENTATION.md
```
Understand what needs to be built and why.

### Step 2: Review Skeleton
```bash
cat sql/030_pggit_branch_management.sql
```
See the function signatures and TODO blocks.

### Step 3: Study Skeleton Reference
```bash
cat .claude/SKELETON_STRUCTURE.md
```
Map each TODO block to implementation steps.

### Step 4: Implement Function
Edit `sql/030_pggit_branch_management.sql`:
- Replace TODO: Step 1 with actual SQL
- Replace TODO: Step 2 with actual SQL
- Continue through all steps
- Remove RAISE EXCEPTION placeholder

### Step 5: Run Tests
```bash
# Set environment if needed
export PGGIT_DB_HOST=localhost
export PGGIT_DB_PORT=5432

# Run tests for your function
pytest tests/unit/test_phase2_branch_management.py::TestCreateBranch -v
```

### Step 6: Repeat Steps 4-5
For each of the 4 functions.

### Step 7: Full Test Suite
```bash
pytest tests/unit/test_phase2_branch_management.py -v
# Expected: 34 passed
```

### Step 8: Commit
```bash
git add -A
git commit -m "feat(phase2): Implement branch management functions [GREEN]

- Implement pggit.create_branch() with full validation
- Implement pggit.delete_branch() with merge check
- Implement pggit.list_branches() with filtering
- Implement pggit.checkout_branch() with session state

All 34 tests passing. Ready for Phase 3."
```

---

## Key Files Reference

```
/home/lionel/code/pggit/
├── sql/
│   ├── 001_schema.sql           ← Phase 1 schema (reference)
│   └── 030_pggit_branch_management.sql  ← IMPLEMENT THIS
├── tests/
│   └── unit/
│       └── test_phase2_branch_management.py  ← 34 tests
├── .claude/
│   ├── PHASE_2_PLAN.md          ← Full spec (read first)
│   ├── PHASE_2_IMPLEMENTATION.md ← Quick start (read second)
│   └── SKELETON_STRUCTURE.md    ← Implementation map (read third)
└── git/ (if used)
    └── Phase 2 branch management functions
```

---

## Database Setup (For Testing)

### Default Setup
```bash
# Tests use these environment variables (with defaults):
# PGGIT_DB_HOST=localhost
# PGGIT_DB_PORT=5432
# PGGIT_DB_USER=postgres
# PGGIT_DB_PASSWORD=postgres
# PGGIT_DB_NAME=pggit_test

# Run tests (assumes PostgreSQL running)
pytest tests/unit/test_phase2_branch_management.py -v
```

### Custom Setup
```bash
# Override defaults with environment variables
export PGGIT_DB_HOST=my-server.com
export PGGIT_DB_PORT=5433
export PGGIT_DB_USER=myuser
export PGGIT_DB_PASSWORD=mypass
export PGGIT_DB_NAME=mydb

# Run tests
pytest tests/unit/test_phase2_branch_management.py -v
```

### Database Requirements
- PostgreSQL 12+ (v0.1.1 used 13+)
- psycopg3 library
- Phase 1 schema loaded (run: `psql < sql/001_schema.sql`)

---

## Common Commands

```bash
# View implementation progress
cat sql/030_pggit_branch_management.sql | grep "RAISE EXCEPTION" | wc -l
# Should show 4 at start, 0 when complete

# Run all tests
pytest tests/unit/test_phase2_branch_management.py -v

# Run specific function tests
pytest tests/unit/test_phase2_branch_management.py::TestCreateBranch -v
pytest tests/unit/test_phase2_branch_management.py::TestDeleteBranch -v
pytest tests/unit/test_phase2_branch_management.py::TestListBranches -v
pytest tests/unit/test_phase2_branch_management.py::TestCheckoutBranch -v

# Run specific test
pytest tests/unit/test_phase2_branch_management.py::TestCreateBranch::test_create_branch_happy_path -v

# View recent commits
git log --oneline | head -10

# View current status
git status
```

---

## Helpful Context

### Phase 1 (Foundation - COMPLETE ✅)
- Schema design with 8 tables
- Utility functions (60 tests passing)
- Event trigger infrastructure
- Immutable audit trail

### Phase 2 (Branch Management - THIS PROJECT)
- Create branches with validation
- Delete branches with merge checks
- List branches with filtering
- Switch branches (session state)

### Phase 3-7 (Future)
- Object tracking and versioning
- Merge algorithms and conflict resolution
- History and time-travel capabilities
- Data branching with copy-on-write
- Configuration and monitoring

---

## Implementation Strategy Notes

### Design Decisions Made
1. **Soft deletes**: Mark as DELETED, don't remove rows (audit trail preservation)
2. **Session variables**: Use PostgreSQL GUC for branch tracking
3. **Object copying**: New branches get full copy of parent's objects
4. **Validation**: Input validation at function boundary
5. **Enum casting**: Use `'ACTIVE'::pggit.branch_status` for type safety

### Testing Approach
- 34 comprehensive tests (8-10 per function)
- Happy paths, edge cases, error conditions
- Database fixtures that auto-setup/teardown
- Helper functions for clean test code

### Git Workflow
- Commit skeletons as [RED] (test infrastructure)
- Commit implementation as [GREEN] (all tests passing)
- Clear messages describing changes
- Small, logical commits

---

## Troubleshooting

### "Cannot connect to PostgreSQL"
**Check**:
- PostgreSQL is running
- Correct host/port/credentials
- Database exists

**Fix**:
```bash
export PGGIT_DB_HOST=your-host
export PGGIT_DB_PORT=your-port
export PGGIT_DB_USER=your-user
export PGGIT_DB_PASSWORD=your-pass
export PGGIT_DB_NAME=your-db
```

### "Cannot load Phase 1 schema"
**Check**: `sql/001_schema.sql` exists

**Fix**:
```bash
ls -la sql/001_schema.sql
```

### "Tests skip with database error"
**Check**:
- Environment variables set correctly
- PostgreSQL service running
- Firewall allows connection

**Fix**: Run `pytest -v` with explicit env vars

### Tests don't find functions
**Check**: Phase 2 SQL file loads correctly

**Fix**:
```bash
psql -U postgres pggit_test -f sql/030_pggit_branch_management.sql
```

---

## Next Steps (After Phase 2)

Once Phase 2 is complete and committed:
1. Launch new agent for Phase 3: Object Tracking
2. Implement: `get_current_schema()`, `get_object_definition()`, `get_object_history()`
3. Add version tracking mechanism
4. 20+ new tests for object tracking

---

## Final Checklist Before Launch

- [ ] Read PHASE_2_IMPLEMENTATION.md
- [ ] Read PHASE_2_PLAN.md (at least overview)
- [ ] Understand SKELETON_STRUCTURE.md
- [ ] Review `sql/030_pggit_branch_management.sql`
- [ ] Check PostgreSQL access with env vars
- [ ] Run one test to verify setup: `pytest tests/unit/test_phase2_branch_management.py::TestCreateBranch::test_create_branch_happy_path -v`

---

## Questions?

Refer to:
- **PHASE_2_PLAN.md**: For detailed specifications
- **SKELETON_STRUCTURE.md**: For implementation mapping
- **Test file**: For test patterns and expectations
- **Phase 1 code**: `sql/001_schema.sql` for table/function reference

---

**Ready to implement! Good luck!** 🚀
