# PGGIT E2E Test Fixes - Quick Reference

## Current Status
```
Chaos Tests:       120/120 ✅ (100%)
E2E Tests:          53/112 ❌ (47%) - 61 failing
Total Tests:       173/232 ❌ (75%)

Goal: Fix all 61 failing E2E tests in 5 phases
Timeline: 10-12 days (8-16 day range)
```

---

## Quick Problem Summary (Top Issues)

| # | Issue | Scope | Impact |
|---|-------|-------|--------|
| 1 | create_temporal_snapshot() wrong params | 35+ calls | 15+ tests fail |
| 2 | record_temporal_change() returns VOID | 5+ calls | 5+ tests fail |
| 3 | merge_branches() missing | 8 calls | 8+ tests fail |
| 4 | data_conflicts table missing | Schema | 6+ tests fail |
| 5 | DB fixture not thread-safe | Concurrency | 5+ tests fail |
| 6 | query_historical_data() wrong param order | 8 calls | 8+ tests fail |
| 7 | restore_table_to_point_in_time() wrong format | 4 calls | 4+ tests fail |
| 8 | ML function parameter types wrong | 3+ calls | 4+ tests fail |
| 9 | identify_conflict_patterns() missing params | 2+ calls | 2+ tests fail |
| 10 | Test data setup missing | Fixtures | 10+ tests fail |

---

## Phase Breakdown

### Phase 1: Foundation Fixes (Days 1-2)
**What**: Fix critical blockers
```
□ 1.1.1 Verify create_temporal_snapshot() signature
□ 1.1.2 Fix record_temporal_change() VOID issue
□ 1.1.3 Implement merge_branches()
□ 1.1.4 Create data_conflicts table
□ 1.2   Make DB fixture thread-safe
□ 1.3   Fix test parameter calls (35+ fixes)

Tests Fixed: ~26
Expected Pass Rate: 60%
```

### Phase 2: Advanced Function Fixes (Days 3-4)
**What**: Fix complex function parameter mismatches
```
□ 2.1 ML function parameter fixes
□ 2.2 Temporal function parameter fixes
□ 2.3 Conflict resolution function fixes

Tests Fixed: ~13
Expected Pass Rate: 75%
```

### Phase 3: Edge Cases & Schema (Days 5-6)
**What**: Handle edge cases and verify schema
```
□ 3.1 Edge case handling (NULL, constraints)
□ 3.2 Schema table verification
□ 3.3 Test fixture enhancement

Tests Fixed: ~13
Expected Pass Rate: 88%
```

### Phase 4: Test Refactoring (Days 7-8)
**What**: Update test code for fixed functions
```
□ 4.1 E2E Docker Integration tests (20)
□ 4.2 E2E Enhanced Coverage tests (35)
□ 4.3 E2E Phase A tests (26)
□ 4.4 E2E Phase B & C tests (31)

Tests Fixed: ~9
Expected Pass Rate: 98%
```

### Phase 5: Integration & Verification (Days 9-10)
**What**: Verify everything works together
```
□ 5.1 Test each file to 100% pass
□ 5.2 Full suite test run
□ 5.3 Documentation & commit

Tests Fixed: ~1
Expected Pass Rate: 100%
```

---

## Most Critical Fixes (Do First!)

### Fix #1: create_temporal_snapshot() Calls (35+ fixes)
**Change From**:
```python
db.execute_returning(
    "SELECT pggit.create_temporal_snapshot('public', 'test_table', %s)",
    json.dumps({'data': 'value'})
)
```

**Change To**:
```python
db.execute_returning(
    "SELECT pggit.create_temporal_snapshot(%s, %s, %s)",
    "snapshot-name",      # p_snapshot_name (TEXT)
    1,                    # p_branch_id (INTEGER)
    json.dumps({...})     # p_snapshot_description (TEXT)
)
```

**Location**: All E2E test files, search for "create_temporal_snapshot"

---

### Fix #2: record_temporal_change() Return Value
**Current**: Returns VOID (can't SELECT)
**Fix**: Change to return (change_id UUID, change_timestamp TIMESTAMPTZ, operation_type TEXT)

**Files**:
- SQL: `src/pggit/sql/060_time_travel.sql` - Add type, modify function
- Tests: All calls to record_temporal_change() - Update to handle return tuple

---

### Fix #3: merge_branches() Missing
**Status**: Check if exists in `src/pggit/sql/050_branch_merge_operations.sql`
**If Missing**: Implement with signature:
```sql
CREATE FUNCTION pggit.merge_branches(
    source_branch_id INT,
    target_branch_id INT,
    message TEXT,
    strategy TEXT DEFAULT '3-way'
) RETURNS TABLE (merge_id UUID, conflict_count INT, success BOOL)
```

---

### Fix #4: data_conflicts Table
**SQL to Add**:
```sql
CREATE TABLE pggit.data_conflicts (
    conflict_id SERIAL PRIMARY KEY,
    branch_id_1 INTEGER REFERENCES pggit.branches(id),
    branch_id_2 INTEGER REFERENCES pggit.branches(id),
    table_schema TEXT NOT NULL,
    table_name TEXT NOT NULL,
    row_id TEXT NOT NULL,
    base_data JSONB,
    source_data JSONB,
    target_data JSONB,
    conflict_type TEXT,
    severity TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    resolved BOOLEAN DEFAULT FALSE,
    resolution_data JSONB,
    created_by TEXT DEFAULT CURRENT_USER
);
```

**Location**: `src/pggit/sql/005_versioning_tables.sql` or new `063_conflict_tables.sql`

---

### Fix #5: Thread-Safe DB Fixture
**File**: `tests/conftest.py`

**Option A** - Connection Pool (Recommended):
```python
from psycopg_pool import ConnectionPool

@pytest.fixture(scope="function")
def db(db_config):
    if not hasattr(db, '_pool'):
        db._pool = ConnectionPool(db_config['dsn'], min_size=1, max_size=20)
    conn = db._pool.getconn()
    try:
        yield conn
    finally:
        db._pool.putconn(conn)
```

**Option B** - Thread-Local:
```python
import threading
_thread_local = threading.local()

@pytest.fixture
def db(db_config):
    if not hasattr(_thread_local, 'conn') or _thread_local.conn.closed:
        _thread_local.conn = psycopg.connect(db_config['dsn'])
    yield _thread_local.conn
```

---

## Test Files & Expected Fixes

| File | Tests | Status | Primary Issue | Fix Strategy |
|------|-------|--------|---------------|--------------|
| test_e2e_docker_integration.py | 20 | 50% pass | Function params | Phase 1-2 |
| test_e2e_enhanced_coverage.py | 35 | 51% pass | Thread safety | Phase 1-4 |
| test_e2e_phase_a_quality_improvements.py | 26 | 50% pass | merge_branches | Phase 1-3 |
| test_e2e_phase_b_quality_improvements.py | 16 | 44% pass | Thread safety | Phase 1-4 |
| test_e2e_phase_c_quality_improvements.py | 15 | 20% pass | Performance | Phase 1-4 |
| **TOTAL** | **112** | **47%** | Multiple | **5 Phases** |

---

## Execution Checklist

### Phase 1 (Days 1-2)
- [ ] Verify create_temporal_snapshot() signature
- [ ] Implement record_temporal_change() return type fix
- [ ] Check/implement merge_branches()
- [ ] Create data_conflicts table
- [ ] Update DB fixture for thread-safety
- [ ] Fix all 35+ create_temporal_snapshot() calls
- [ ] **Verify**: Run tests, expect ~60% pass rate

### Phase 2 (Days 3-4)
- [ ] Fix ML function parameter types
- [ ] Fix temporal function calls
- [ ] Fix conflict resolution function calls
- [ ] **Verify**: Run tests, expect ~75% pass rate

### Phase 3 (Days 5-6)
- [ ] Handle NULL values in schema
- [ ] Verify all constraints
- [ ] Enhance test fixtures
- [ ] **Verify**: Run tests, expect ~88% pass rate

### Phase 4 (Days 7-8)
- [ ] Refactor docker_integration tests
- [ ] Refactor enhanced_coverage tests
- [ ] Refactor phase_a tests
- [ ] Refactor phase_b/c tests
- [ ] **Verify**: Run tests, expect ~98% pass rate

### Phase 5 (Days 9-10)
- [ ] Run docker_integration tests: 20/20 ✓
- [ ] Run enhanced_coverage tests: 35/35 ✓
- [ ] Run phase_a tests: 26/26 ✓
- [ ] Run phase_b tests: 16/16 ✓
- [ ] Run phase_c tests: 15/15 ✓
- [ ] Run full suite: 232/232 ✓
- [ ] Create documentation
- [ ] Final commit
- [ ] **Verify**: 100% pass rate achieved!

---

## Key Files to Modify

### SQL Files
- `src/pggit/sql/060_time_travel.sql` - record_temporal_change() type
- `src/pggit/sql/005_versioning_tables.sql` - data_conflicts table
- `src/pggit/sql/050_branch_merge_operations.sql` - verify merge_branches()
- New: `sql/migrations/003_fix_e2e_schema.sql` - migration script

### Python Test Files
- `tests/e2e/test_e2e_docker_integration.py` - 20 test fixes
- `tests/e2e/test_e2e_enhanced_coverage.py` - 35 test fixes
- `tests/e2e/test_e2e_phase_a_quality_improvements.py` - 26 test fixes
- `tests/e2e/test_e2e_phase_b_quality_improvements.py` - 16 test fixes
- `tests/e2e/test_e2e_phase_c_quality_improvements.py` - 15 test fixes
- `tests/conftest.py` - DB fixture thread-safety

### Documentation
- New: `docs/FUNCTION_SIGNATURES.md` - Function reference
- New: `IMPLEMENTATION_PLAN.md` - This plan
- New: `QUICK_REFERENCE.md` - This quick ref

---

## Success Metrics

### After Phase 1
- ✓ All 5 critical blockers resolved
- ✓ ~60% E2E tests passing
- ✓ Docker integration tests mostly working

### After Phase 2
- ✓ All function parameter mismatches fixed
- ✓ ~75% E2E tests passing
- ✓ All function calls use correct parameters

### After Phase 3
- ✓ All schema verified
- ✓ ~88% E2E tests passing
- ✓ Edge cases handled

### After Phase 4
- ✓ All test code refactored
- ✓ ~98% E2E tests passing
- ✓ Ready for final verification

### After Phase 5 (DONE!)
- ✓ **232/232 tests passing (100%)**
- ✓ All documentation complete
- ✓ All changes committed
- ✓ **PRODUCTION READY**

---

## Next Steps

1. **Read Full Plan**: See `IMPLEMENTATION_PLAN.md` for detailed implementation steps
2. **Start Phase 1**: Begin with the 5 critical fixes
3. **Verify Regularly**: Run tests after each major change
4. **Document Issues**: Keep track of any blockers discovered
5. **Iterate by Phase**: Complete each phase before starting next

Good luck! 🚀

