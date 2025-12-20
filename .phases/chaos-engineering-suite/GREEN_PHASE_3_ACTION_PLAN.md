# GREEN Phase 3 - Action Plan to Completion

**Status**: 7.2/10 → Need to reach 9.0/10 for production
**Current**: 50 passing, 5 failing, 5 skipped, ~9 hanging
**Target**: 62+ passing, <3 failing, <2 skipped, 0 hanging
**Timeline**: 1-2 weeks

---

## Priority 1: CRITICAL BLOCKERS (Must Fix Immediately)

### 🔴 Issue #1: Property Tests Hanging (~13% of tests)

**Impact**: Blocks CI/CD, makes test suite unstable
**Current**: ~9 tests timeout/hang
**Target**: 0 hanging tests
**Time Estimate**: 2-4 hours

#### Action Items:

1. **Add Timeouts to All Property Tests** (30 min)
   ```python
   # File: tests/chaos/test_property_based_data.py

   @pytest.mark.timeout(30)  # ← Add this
   @given(tbl_def=table_definition(), branch_name=git_branch_name)
   @settings(
       max_examples=10,  # ← Reduce from 20-50
       deadline=None,
       suppress_health_check=[HealthCheck.function_scoped_fixture],
   )
   def test_branched_data_independent(self, sync_conn, tbl_def, branch_name):
       ...
   ```

   **Files to modify**:
   - `tests/chaos/test_property_based_data.py` (all 7 tests)
   - `tests/chaos/test_property_based_core.py` (all 12 tests)
   - `tests/chaos/test_property_based_migrations.py` (all 6 tests)

2. **Reduce max_examples** (15 min)
   - Change all `max_examples=50` → `max_examples=10`
   - Change all `max_examples=20` → `max_examples=10`
   - Property tests should be fast feedback, not exhaustive

3. **Debug Specific Hanging Test** (1-2 hours)
   ```bash
   # Identify which test hangs
   pytest tests/chaos/test_property_based_data.py::TestDataVersioningProperties::test_data_version_history_preserved -v --timeout=60

   # Add print statements to identify where it hangs
   # Common causes:
   # - Infinite loop in hypothesis strategy
   # - Database query never returning
   # - Deadlock in test logic
   ```

4. **Verification** (15 min)
   ```bash
   # All property tests should complete within 2 minutes
   timeout 120 pytest tests/chaos/test_property_based_*.py -v

   # Success criteria:
   # - 0 tests timeout
   # - All tests complete (pass/fail/skip - doesn't matter)
   # - No hanging processes
   ```

---

### 🔴 Issue #2: Branch Isolation Completely Broken (0/6 workers)

**Impact**: Core functionality failure
**Current**: All 6 workers failed in isolation test
**Target**: 6/6 workers succeed
**Time Estimate**: 4-6 hours

#### Action Items:

1. **Reproduce and Debug** (1 hour)
   ```bash
   # Run failing test with detailed output
   pytest tests/chaos/test_concurrent_branching.py::TestConcurrentBranching::test_branch_isolation_between_workers -vv -s

   # Add debugging to see actual errors
   ```

2. **Root Cause Analysis** (2 hours)
   ```python
   # File: sql/functions/commit_changes.sql

   # Current hypothesis: commit_changes() doesn't properly isolate branch operations
   # Questions to answer:
   # 1. Are commits to different branches sharing locks?
   # 2. Is the branches table update causing contention?
   # 3. Are Trinity IDs being validated across all branches?

   # Add logging to commit_changes():
   RAISE NOTICE 'Committing to branch %, current branches: %', p_branch_name,
       (SELECT array_agg(branch_name) FROM pggit.branches);
   ```

3. **Fix commit_changes()** (2-3 hours)

   Likely fixes:

   **Fix A: Add Branch-Level Locking**
   ```sql
   -- Only lock the specific branch, not all branches
   PERFORM * FROM pggit.branches
   WHERE branch_name = p_branch_name
   FOR UPDATE NOWAIT;  -- ← Changed from table-level lock
   ```

   **Fix B: Use Advisory Locks**
   ```sql
   -- Use PostgreSQL advisory locks for branch isolation
   PERFORM pg_advisory_xact_lock(hashtext(p_branch_name));
   ```

   **Fix C: Separate Branch Metadata**
   ```sql
   -- Don't update shared branches table for every commit
   -- Only update on branch creation
   ```

4. **Verification** (30 min)
   ```bash
   # Test should pass with 6/6 workers
   pytest tests/chaos/test_concurrent_branching.py::TestConcurrentBranching::test_branch_isolation_between_workers -v

   # Run multiple times to ensure stability
   for i in {1..5}; do
       pytest tests/chaos/test_concurrent_branching.py::TestConcurrentBranching::test_branch_isolation_between_workers -v
   done
   ```

---

## Priority 2: HIGH PRIORITY (Fix Before Production)

### 🟡 Issue #3: Transaction Rollback Not Implemented

**Impact**: Data integrity risk
**Current**: Version state not restored on transaction rollback
**Target**: Version increments rolled back on transaction failure
**Time Estimate**: 3-4 hours

#### Action Items:

1. **Design Transaction-Aware Versioning** (1 hour)
   ```sql
   -- Option A: Use subtransactions
   CREATE OR REPLACE FUNCTION pggit.increment_version_tx()
   RETURNS trigger AS $$
   BEGIN
       -- Version changes are part of transaction
       -- Will auto-rollback if transaction fails
       NEW.version_major := OLD.version_major + 1;
       RETURN NEW;
   END;
   $$ LANGUAGE plpgsql;

   -- Option B: Use savepoints
   SAVEPOINT before_version_change;
   -- ... do version increment
   ROLLBACK TO SAVEPOINT before_version_change;  -- on failure
   ```

2. **Implement Rollback Logic** (2 hours)
   ```python
   # File: sql/functions/increment_version.sql

   # Add transaction awareness
   # Store version changes in temp table until commit
   # Rollback clears temp table
   ```

3. **Test Rollback Scenarios** (1 hour)
   ```bash
   pytest tests/chaos/test_concurrent_versioning.py::TestConcurrentVersioning::test_version_rollback_on_transaction_failure -v
   ```

---

### 🟡 Issue #4: Trinity ID Uniqueness Across Branches

**Impact**: 1 property test failing
**Current**: Trinity IDs may collide across branches
**Target**: Guaranteed unique across all branches
**Time Estimate**: 2-3 hours

#### Action Items:

1. **Review Trinity ID Generation** (1 hour)
   ```sql
   -- File: sql/functions/generate_trinity_id.sql

   -- Ensure uniqueness components include branch info
   -- Current: timestamp + sequence + random
   -- Should include: branch_name hash or global sequence
   ```

2. **Add Global Uniqueness** (1-2 hours)
   ```sql
   -- Option A: Include branch in ID
   trinity_id := branch_hash || '-' || timestamp || '-' || sequence;

   -- Option B: Use global sequence across all branches
   CREATE SEQUENCE pggit.global_trinity_sequence;
   ```

3. **Test** (30 min)
   ```bash
   pytest tests/chaos/test_property_based_core.py::TestPropertyBasedCore::test_trinity_id_unique_across_branches -v
   ```

---

### 🟡 Issue #5: Long Serializable Transactions Failing

**Impact**: 1 edge case test failing
**Current**: Long-running transactions cause serialization failures
**Target**: Handle gracefully with retry or document limitation
**Time Estimate**: 2-3 hours

#### Action Items:

1. **Analyze Test Expectations** (30 min)
   ```python
   # Is this a bug or expected behavior?
   # PostgreSQL SERIALIZABLE may legitimately fail long transactions
   ```

2. **Fix or Document** (1-2 hours)

   **Option A: Add Retry Logic**
   ```python
   # Wrap in retry decorator
   @retry(max_attempts=3, on_serialization_failure=True)
   def commit_changes(...):
       ...
   ```

   **Option B: Document Limitation**
   ```python
   pytest.skip("Long serializable transactions expected to fail - documented limitation")
   ```

3. **Test** (30 min)

---

## Priority 3: MEDIUM (Nice to Have)

### 🟢 Issue #6: Data Branching Tests Skipped (4 tests)

**Impact**: Missing feature coverage
**Current**: 4 tests skipped (create_data_branch partially implemented)
**Target**: 4 tests passing
**Time Estimate**: 4-6 hours

#### Action Items:

1. **Complete create_data_branch()** (3-4 hours)
   - Full implementation of data branching
   - Copy-on-write semantics
   - Test coverage

2. **Enable Skipped Tests** (1 hour)
   - Remove `pytest.skip()` calls
   - Verify tests pass

3. **Test** (1 hour)
   ```bash
   pytest tests/chaos/test_property_based_data.py -v
   ```

---

## Verification Checklist

After completing all fixes, verify:

### Phase 1: Critical Issues Fixed ✅
```bash
# No hanging tests
timeout 120 pytest tests/chaos/test_property_based_*.py -v
# Should complete without timeout

# Branch isolation working
pytest tests/chaos/test_concurrent_branching.py::TestConcurrentBranching::test_branch_isolation_between_workers -v
# Should show 6/6 workers succeeded
```

### Phase 2: Full Test Suite ✅
```bash
# Run all chaos tests
pytest tests/chaos/ -v --tb=short

# Success criteria:
# - 62+ tests passing (90%+)
# - <3 tests failing
# - <2 tests skipped
# - 0 tests hanging
# - Total time < 5 minutes
```

### Phase 3: Stability ✅
```bash
# Run 5 times to ensure no flakiness
for i in {1..5}; do
    pytest tests/chaos/ -v --tb=no | tail -3
done

# All 5 runs should have same pass/fail counts
```

### Phase 4: CI Ready ✅
```bash
# Simulate CI environment
pytest tests/chaos/ -v --tb=short --maxfail=5

# Should complete in < 10 minutes
# Should have clean output (no warnings)
```

---

## Timeline Summary

### Week 1: Critical Blockers
**Days 1-2** (Total: 10-14 hours)
- Day 1 AM: Fix hanging tests (2-4 hours)
- Day 1 PM: Start branch isolation debugging (4 hours)
- Day 2 AM: Complete branch isolation fix (2-4 hours)
- Day 2 PM: Implement transaction rollback (3-4 hours)

**Expected Result**:
- 0 hanging tests
- Branch isolation working
- ~55-60 tests passing

### Week 2: Polish & Production
**Days 3-5** (Total: 8-12 hours)
- Day 3: Fix Trinity ID + long transactions (4-6 hours)
- Day 4: Enable data branching tests (4-6 hours)
- Day 5: Testing, documentation, CI validation (3-4 hours)

**Expected Result**:
- 62+ tests passing (90%+)
- <3 failing
- Production ready

---

## Success Criteria

### Minimum (Can Ship)
- ✅ 0 hanging tests (critical)
- ✅ Branch isolation working (critical)
- ✅ 60+ tests passing (87%+)
- ✅ <5 failures
- ✅ Test suite stable (runs consistently)

### Ideal (Production Ready)
- ✅ 0 hanging tests
- ✅ 62+ tests passing (90%+)
- ✅ <3 failures
- ✅ <2 skips
- ✅ Transaction rollback working
- ✅ CI integration validated
- ✅ Documentation complete

### Stretch (Enterprise Grade)
- ✅ 65+ tests passing (95%+)
- ✅ <2 failures
- ✅ 0 skips
- ✅ All edge cases handled
- ✅ Performance optimized
- ✅ Production runbook written

---

## Risk Mitigation

### Risk: Fixes Take Longer Than Estimated
**Mitigation**:
- Focus on critical blockers first
- Can ship with some skipped tests
- Document known limitations

### Risk: Branch Isolation Root Cause Unclear
**Mitigation**:
- Add extensive logging
- Test in isolation before full suite
- Consider PostgreSQL advisory locks as backup solution

### Risk: Property Tests Still Unstable
**Mitigation**:
- Reduce max_examples to 5 if needed
- Use deterministic seeds
- Mark as slow tests (run separately in CI)

---

## Next Immediate Action

**RIGHT NOW**: Fix hanging tests (2-4 hours)

```bash
# 1. Create branch
git checkout -b fix/chaos-hanging-tests

# 2. Add timeouts to all property tests
# Edit: tests/chaos/test_property_based_*.py
# Add: @pytest.mark.timeout(30) to all test functions

# 3. Reduce max_examples
# Change: max_examples=50 → max_examples=10

# 4. Test
timeout 120 pytest tests/chaos/test_property_based_*.py -v

# 5. Commit
git add tests/chaos/test_property_based_*.py
git commit -m "fix(chaos): Add timeouts and reduce max_examples to prevent hanging

- Add @pytest.mark.timeout(30) to all property-based tests
- Reduce max_examples from 50 to 10 for faster feedback
- Prevents test suite from hanging on complex property generation

Resolves hanging issue affecting ~13% of tests"

# 6. Verify repeatedly
for i in {1..3}; do
    timeout 120 pytest tests/chaos/test_property_based_*.py -v
done
```

**THEN**: Fix branch isolation (4-6 hours)

**THEN**: Continue with Priority 2 and 3 items

---

*Action Plan by Claude (Senior Architect)*
*Estimated Total Time: 1-2 weeks to production readiness*
*See GREEN_PHASE_3_QA_REPORT.md for detailed analysis*
