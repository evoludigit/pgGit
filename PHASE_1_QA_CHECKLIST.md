# Phase 1 QA Checklist - Foundation Fixes

**Goal**: Verify all critical Phase 1 fixes are correctly implemented

**Timeline**: Complete all checks before moving to Phase 2

**Pass Criteria**: All items checked ✓ and tests reach ~60% pass rate (39/65 E2E tests)

---

## QA Task 1.1: Verify create_temporal_snapshot() Signature

### 1.1.1 SQL Verification

```sql
-- Check current function signature
SELECT pg_get_functiondef(oid) FROM pg_proc 
WHERE proname = 'create_temporal_snapshot' 
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname='pggit');
```

**Expected Output**:
```
CREATE OR REPLACE FUNCTION pggit.create_temporal_snapshot(
    p_snapshot_name TEXT,
    p_branch_id INTEGER,
    p_snapshot_description TEXT DEFAULT NULL
)
RETURNS TABLE (snapshot_id UUID, name TEXT, created_at TIMESTAMPTZ)
```

**Status**: 
- [ ] Signature matches expected output
- [ ] Returns 3 columns: snapshot_id (UUID), name (TEXT), created_at (TIMESTAMPTZ)
- [ ] Parameter order: name, branch_id, description

**Verification Commands**:
```bash
# Check the function exists and has correct signature
psql -d postgres << 'SQL'
\df pggit.create_temporal_snapshot
SQL

# Test function works
psql -d postgres << 'SQL'
SELECT * FROM pggit.create_temporal_snapshot('test-snap', 1, 'Test snapshot');
SQL
```

**Notes**: 
- If signature is wrong, fix in `src/pggit/sql/060_time_travel.sql`
- If function doesn't exist, check if install script was run

---

### 1.1.2 Test Call Verification

**Count test calls** that need fixing:
```bash
grep -r "create_temporal_snapshot" tests/e2e/ | wc -l
```

Expected: ~30+ occurrences

**Before**: 
```python
db.execute_returning(
    "SELECT pggit.create_temporal_snapshot('public', 'test_table', %s)",
    json.dumps({'data': 'value'})
)
```

**After** (Example):
```python
result = db.execute_returning(
    "SELECT pggit.create_temporal_snapshot(%s, %s, %s)",
    "snapshot-1",           # p_snapshot_name
    1,                      # p_branch_id  
    json.dumps({'data': 'value'})  # p_snapshot_description
)
```

**Verification Checklist**:
- [ ] All 30+ calls updated with correct parameter order
- [ ] Parameter 1: string (snapshot name)
- [ ] Parameter 2: integer (branch_id)
- [ ] Parameter 3: string or NULL (description)
- [ ] No hardcoded schema.table in calls
- [ ] Return value properly used/assigned

**Test It**:
```bash
pytest tests/e2e/test_e2e_docker_integration.py::TestE2ETemporalOperations::test_temporal_snapshot_creation -xvs
```

Expected: PASS

---

## QA Task 1.2: Verify record_temporal_change() Return Type Fix

### 1.2.1 SQL Changes Verification

**Check if return type was created**:
```sql
-- Should exist
SELECT * FROM pg_type WHERE typname = 'record_change_result';
```

**Expected**: Returns 1 row with type definition

**Check function signature**:
```sql
SELECT pg_get_functiondef(oid) FROM pg_proc 
WHERE proname = 'record_temporal_change' 
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname='pggit');
```

**Expected Output** (partial):
```sql
RETURNS pggit.record_change_result AS
...
```

**Status**:
- [ ] `pggit.record_change_result` type exists
- [ ] Type has 3 columns: change_id UUID, change_timestamp TIMESTAMPTZ, operation_type TEXT
- [ ] Function returns `pggit.record_change_result`
- [ ] Function body returns proper tuple values

**Verification**:
```bash
# Test function returns proper tuple
psql -d postgres << 'SQL'
SELECT * FROM pggit.record_temporal_change(
    (SELECT id FROM pggit.temporal_snapshots LIMIT 1),
    'public', 'test_table', 'INSERT', 'row-1',
    '{"id": 1}'::jsonb, '{"id": 1, "name": "test"}'::jsonb
);
SQL
```

Expected: Returns 1 row with 3 columns

---

### 1.2.2 Test Code Verification

**Before**: (Won't work - returns VOID)
```python
db.execute("SELECT pggit.record_temporal_change(...)")
```

**After**: (Works - returns tuple)
```python
result = db.execute_returning(
    "SELECT pggit.record_temporal_change(%s, %s, %s, %s, %s, %s, %s)",
    snapshot_id,
    "public",
    "test_table",
    "INSERT",
    "row-1",
    json.dumps({"id": 1}),
    json.dumps({"id": 1, "name": "test"})
)
# Now result is a tuple: (change_id, change_timestamp, operation_type)
```

**Verification**:
- [ ] All `record_temporal_change()` calls use `execute_returning()`
- [ ] Return value captured in variable
- [ ] Tests access result tuple elements (result[0], result[1], etc.)
- [ ] No calls to SELECT on VOID function

**Test It**:
```bash
pytest tests/e2e/test_e2e_docker_integration.py::TestE2ETemporalOperations::test_temporal_changelog_recording -xvs
```

Expected: PASS

---

## QA Task 1.3: Verify merge_branches() Function Exists

### 1.3.1 Function Existence Check

**Check if function exists**:
```bash
grep -n "CREATE.*FUNCTION.*merge_branches" src/pggit/sql/*.sql
```

**Status**:
- [ ] Function found in SQL files
- [ ] Location: _________________ (which file?)

**If NOT Found**: Implement it

```sql
-- In src/pggit/sql/050_branch_merge_operations.sql (or create new file)
CREATE OR REPLACE FUNCTION pggit.merge_branches(
    p_source_branch_id INTEGER,
    p_target_branch_id INTEGER,
    p_commit_message TEXT,
    p_strategy TEXT DEFAULT '3-way'
)
RETURNS TABLE (
    merge_id UUID,
    conflict_count INTEGER,
    success BOOLEAN
)
AS $$
BEGIN
    -- Implementation here
    -- Standard 3-way merge:
    -- 1. Find common ancestor
    -- 2. Apply changes from source and target
    -- 3. Detect and report conflicts
    -- 4. Return merge result
END;
$$ LANGUAGE plpgsql;
```

### 1.3.2 Function Signature Verification

**Get actual signature**:
```sql
SELECT pg_get_functiondef(oid) FROM pg_proc 
WHERE proname = 'merge_branches' 
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname='pggit');
```

**Verify**:
- [ ] Function takes 4 parameters: source_branch_id INT, target_branch_id INT, message TEXT, strategy TEXT
- [ ] Returns TABLE with: merge_id UUID, conflict_count INT, success BOOLEAN
- [ ] Has default strategy = '3-way'

**Test It**:
```bash
# Get branch IDs first
psql -d postgres << 'SQL'
SELECT id FROM pggit.branches LIMIT 2;
SQL

# Test merge function (replace IDs)
psql -d postgres << 'SQL'
SELECT * FROM pggit.merge_branches(1, 1, 'Test merge', '3-way');
SQL
```

Expected: Returns 1 row with merge_id, conflict_count, success

**Test in Tests**:
```bash
pytest tests/e2e/test_e2e_phase_a_quality_improvements.py -k "merge" -xvs 2>&1 | head -50
```

Expected: Should not error on "merge_branches not found"

---

## QA Task 1.4: Verify data_conflicts Table Created

### 1.4.1 Table Existence Check

**Check if table exists**:
```sql
SELECT to_regclass('pggit.data_conflicts');
```

**Expected**: Returns 'pggit.data_conflicts'::regclass (not NULL)

**Status**:
- [ ] Table `pggit.data_conflicts` exists
- [ ] Table is in `pggit` schema

**If NOT Found**: Create it

```sql
-- In src/pggit/sql/005_versioning_tables.sql or new 063_conflict_tables.sql
CREATE TABLE IF NOT EXISTS pggit.data_conflicts (
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

CREATE INDEX idx_data_conflicts_branches
ON pggit.data_conflicts(branch_id_1, branch_id_2);
CREATE INDEX idx_data_conflicts_table
ON pggit.data_conflicts(table_schema, table_name);
```

### 1.4.2 Table Structure Verification

**Check columns**:
```sql
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema = 'pggit' AND table_name = 'data_conflicts'
ORDER BY ordinal_position;
```

**Expected Output**:
```
conflict_id          | integer
branch_id_1          | integer
branch_id_2          | integer
table_schema         | text
table_name           | text
row_id               | text
base_data            | jsonb
source_data          | jsonb
target_data          | jsonb
conflict_type        | text
severity             | text
created_at           | timestamp with time zone
resolved             | boolean
resolution_data      | jsonb
created_by           | text
```

**Status**:
- [ ] All 15 columns present
- [ ] Column types correct (INT, TEXT, JSONB, TIMESTAMP, BOOLEAN)
- [ ] Indexes created on (branch_id_1, branch_id_2) and (table_schema, table_name)

**Test Inserts**:
```sql
-- Get main branch id
SELECT id FROM pggit.branches WHERE code = 'main' LIMIT 1;

-- Insert test conflict (replace IDs)
INSERT INTO pggit.data_conflicts 
(branch_id_1, branch_id_2, table_schema, table_name, row_id, base_data, source_data, target_data)
VALUES 
(1, 1, 'public', 'test_table', 'row-1', 
 '{"id": 1}'::jsonb, '{"id": 1, "v": "a"}'::jsonb, '{"id": 1, "v": "b"}'::jsonb);

-- Query it back
SELECT conflict_id, table_name, conflict_type FROM pggit.data_conflicts;
```

Expected: Insert succeeds, query returns 1 row

**Test in Tests**:
```bash
pytest tests/e2e/test_e2e_docker_integration.py::TestE2EConflictResolution::test_semantic_conflict_analysis -xvs
```

Expected: PASS (should find data_conflicts table)

---

## QA Task 1.5: Verify DB Fixture Thread-Safety

### 1.5.1 Check conftest.py Changes

**Location**: `tests/conftest.py`

**Before** (Unsafe):
```python
@pytest.fixture(scope="function")
def db(db_config):
    conn = psycopg.connect(db_config['dsn'])
    yield conn
    conn.close()
```

**After - Option A** (Connection Pool):
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

**After - Option B** (Thread-Local):
```python
import threading
_thread_local = threading.local()

@pytest.fixture
def db(db_config):
    if not hasattr(_thread_local, 'conn') or _thread_local.conn.closed:
        _thread_local.conn = psycopg.connect(db_config['dsn'])
    yield _thread_local.conn
```

**Status**:
- [ ] conftest.py has been updated
- [ ] One of the two options implemented
- [ ] Old single-connection code removed
- [ ] Fixture properly yields connection
- [ ] Cleanup is handled (putconn or close)

**Verify Implementation**:
```bash
grep -A 10 "@pytest.fixture" tests/conftest.py | grep -A 10 "def db"
```

Expected: Shows updated fixture code

### 1.5.2 Test Thread-Safety

**Create test file**: `tests/test_thread_safety.py`

```python
import threading
import pytest
from concurrent.futures import ThreadPoolExecutor

def test_db_fixture_thread_safe(db):
    """Verify DB fixture works correctly across threads."""
    
    results = []
    errors = []
    
    def worker(thread_id):
        try:
            # Each thread gets its own connection
            cursor = db.cursor()
            cursor.execute("SELECT 1")
            result = cursor.fetchone()
            results.append((thread_id, result[0]))
            cursor.close()
        except Exception as e:
            errors.append((thread_id, str(e)))
    
    # Run 5 concurrent threads
    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = [executor.submit(worker, i) for i in range(5)]
        for f in futures:
            f.result()
    
    assert len(errors) == 0, f"Thread errors: {errors}"
    assert len(results) == 5, f"Expected 5 results, got {len(results)}"
```

**Run the test**:
```bash
pytest tests/test_thread_safety.py -xvs
```

Expected: PASS (no connection errors, all 5 threads complete successfully)

---

## QA Task 1.6: Test Parameter Fixes - Wave 1

### 1.6.1 Search and Verify All Fixes

**Count fixes needed**:
```bash
grep -r "create_temporal_snapshot" tests/e2e/*.py | grep -v "# " | wc -l
```

**Expected**: ~30+ lines

**Verify each fix**:
```bash
# Check for old pattern (should be 0)
grep -r "create_temporal_snapshot('public'" tests/e2e/ | wc -l
# Expected: 0

# Check for new pattern (should be 30+)
grep -r "create_temporal_snapshot(%s, %s, %s" tests/e2e/ | wc -l
# Expected: ~30+
```

**Status**:
- [ ] Old pattern not found (0 occurrences)
- [ ] New pattern found (30+ occurrences)
- [ ] All fixes use parameterized queries (%s, %s, %s)

### 1.6.2 Fix query_historical_data() Calls

**Search for pattern**:
```bash
grep -r "query_historical_data" tests/e2e/*.py | head -5
```

**Expected Before**: Calls missing p_end_time or with wrong parameter order

**Expected After**: All calls have 4 parameters (table, start_time, end_time, where_clause)

**Status**:
- [ ] All query_historical_data() calls have 4 parameters
- [ ] Parameter 1: "schema.table" format
- [ ] Parameter 2: TIMESTAMP (start_time)
- [ ] Parameter 3: TIMESTAMP (end_time)
- [ ] Parameter 4: TEXT or NULL (where_clause)

**Example Fix**:
```python
# Before (WRONG)
db.execute(
    "SELECT * FROM pggit.query_historical_data(%s, %s)",
    "public.my_table",
    iso_time
)

# After (CORRECT)
db.execute(
    "SELECT * FROM pggit.query_historical_data(%s, %s, %s, %s)",
    "public.my_table",
    iso_time,
    iso_time + timedelta(hours=1),
    None
)
```

### 1.6.3 Fix restore_table_to_point_in_time() Calls

**Search for pattern**:
```bash
grep -r "restore_table_to_point_in_time" tests/e2e/*.py | head -5
```

**Expected**: Should have schema.table format, not separate schema and table

**Status**:
- [ ] All calls use "schema.table" format for table name
- [ ] Parameter 1: "schema.table" (TEXT)
- [ ] Parameter 2: TIMESTAMP (target_time)
- [ ] Parameter 3: BOOLEAN (create_temp_table)

---

## QA Task 1.7: Run Phase 1 Tests

### 1.7.1 Run E2E Docker Integration Tests

```bash
pytest tests/e2e/test_e2e_docker_integration.py -v --tb=short 2>&1 | tee /tmp/phase1_docker_tests.log
```

**Expected Result**: 
- Minimum 10/20 tests passing (50%)
- Maximum 15/20 failing (due to Phase 2 fixes not yet done)

**Verify**:
- [ ] test_temporal_snapshot_creation: PASS
- [ ] test_temporal_changelog_recording: PASS
- [ ] test_semantic_conflict_analysis: PASS
- [ ] test_pattern_learning: Might still fail (Phase 2)
- [ ] Others: Mix of PASS/FAIL expected

**Troubleshoot if failing**:
```bash
# See detailed error
pytest tests/e2e/test_e2e_docker_integration.py::TestE2ETemporalOperations::test_temporal_snapshot_creation -xvs
```

### 1.7.2 Run Full E2E Test Suite

```bash
pytest tests/e2e/ -v --tb=no 2>&1 | tail -20
```

**Expected Result**: 
- Before Phase 1: 53/112 passing (47%)
- After Phase 1: 60-65/112 passing (54-58%)
- Improvement: +7-12 tests

**Check Progress**:
```bash
# Count passes and failures
pytest tests/e2e/ -q --tb=no 2>&1 | tail -3
```

Expected pattern: `X passed, Y failed`

---

## QA Task 1.8: Verify No Regressions

### 1.8.1 Verify Chaos Tests Still Pass

```bash
pytest tests/chaos/ -v --tb=no 2>&1 | tail -10
```

**Expected Result**: 120/120 tests still passing (100%)

**Status**:
- [ ] All 120 chaos tests PASS
- [ ] No new failures introduced
- [ ] Execution time reasonable (<2 minutes)

---

## Summary Checklist

### Critical Items (MUST PASS)
- [ ] 1.1: create_temporal_snapshot() signature correct
- [ ] 1.2: record_temporal_change() returns tuple
- [ ] 1.3: merge_branches() function exists
- [ ] 1.4: data_conflicts table exists with correct columns
- [ ] 1.5: DB fixture is thread-safe
- [ ] 1.6: All parameter fix patterns applied
- [ ] 1.7: ~60% E2E tests passing (39/65)
- [ ] 1.8: 120/120 chaos tests still passing

### Phase 1 Completion Criteria

✅ **Phase 1 COMPLETE when ALL of the following are true**:

1. All SQL changes deployed and verified
2. All test parameter fixes applied
3. E2E tests showing improvement: 60%+ passing (39/65 minimum)
4. Chaos tests still at 100% (120/120)
5. No regressions in existing functionality
6. All checklist items marked complete

**Expected Timeline**: 2 days to complete all QA

---

## Troubleshooting Guide

### Issue: create_temporal_snapshot() still has wrong signature

**Solution**:
1. Edit `src/pggit/sql/060_time_travel.sql`
2. Find the function definition
3. Update parameter order to: (p_snapshot_name, p_branch_id, p_snapshot_description)
4. Rebuild schema: `psql -d postgres -f sql/install.sql`
5. Verify again

### Issue: record_temporal_change() still returns VOID

**Solution**:
1. Create the return type in 060_time_travel.sql
2. Update function RETURNS clause
3. Modify function body to return proper tuple
4. Rebuild schema
5. Test with: `SELECT * FROM pggit.record_temporal_change(...)`

### Issue: Tests still failing with parameter mismatches

**Solution**:
1. Check error message for exact function call
2. Verify parameter order in code
3. Check parameter types (INT vs TEXT, UUID vs STRING)
4. Run test with `-xvs` to see full error
5. Compare with correct pattern from plan

### Issue: Thread-safety test fails with "connection closed"

**Solution**:
1. Verify fixture uses ConnectionPool or thread-local
2. Check pool.putconn() is called in finally block
3. Verify max_size is adequate (20+ for safety)
4. Test with simple SELECT in multiple threads

---

**QA Approval**: ________________________  Date: __________

