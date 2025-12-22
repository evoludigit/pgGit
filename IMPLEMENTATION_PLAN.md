# PGGIT Test Failure Resolution - Complete Implementation Plan

**Status**: Production-ready core (120/120 chaos tests passing) | In-development E2E (61 failing tests)

**Goal**: Fix all 61 failing E2E tests across 5 test files through systematic implementation phases

---

## Executive Summary

### Current State
- ✅ **Chaos Tests**: 120/120 passing (100%) - Production ready
- ❌ **E2E Tests**: 61 failing, 53 passing (46% pass rate)
- 🎯 **Target**: 100% passing across all 232 tests

### Root Causes (Top 5)
1. **Function Signature Mismatches** - 35+ test calls to `create_temporal_snapshot()` use wrong parameter order
2. **VOID Function Wrapping** - `record_temporal_change()` returns VOID but tests wrap with SELECT
3. **Missing merge_branches()** - Function called in 8+ tests but not found in codebase
4. **Missing data_conflicts Table** - Queries fail, table never created
5. **Thread-Safety Issues** - Single connection fixture used for concurrent tests

---

## PHASE 1: Foundation Fixes (Days 1-2)

**Goal**: Fix critical blockers preventing basic E2E tests from running

### Phase 1.1: Function Signature Verification & Mapping

**Tasks**:

#### 1.1.1 Verify create_temporal_snapshot() Signature
- Current signature expects: (p_snapshot_name TEXT, p_branch_id INTEGER, p_snapshot_description TEXT)
- 35+ tests call with: (schema_name, table_name, metadata_json) - WRONG
- **Action**: Document correct signature, fix all test calls
- **Tests Fixed**: test_temporal_snapshot_creation, test_temporal_snapshot_listing (2+ tests)

#### 1.1.2 Fix record_temporal_change() VOID Return
- Current: Returns VOID - cannot be used in SELECT
- Problem: Tests do `SELECT pggit.record_temporal_change(...)`
- **Solution**: Change function to return record_change_result tuple
- **Action**: Create type, modify function, update test expectations
- **Tests Fixed**: test_temporal_changelog_recording (1+ tests)

#### 1.1.3 Verify/Create Missing merge_branches() Function
- Status: MISSING - called in 8+ tests
- **Action**: Check if exists in 050_branch_merge_operations.sql, implement if missing
- **Signature**: (source_branch_id INT, target_branch_id INT, message TEXT, strategy TEXT) → (merge_id UUID, conflict_count INT, success BOOL)
- **Tests Fixed**: All merge tests in phase_b, phase_c (8+ tests)

#### 1.1.4 Create Missing data_conflicts Table
- Status: Table not created, but analyze_semantic_conflict() queries it
- **Action**: Create table with columns: conflict_id, branch_id_1, branch_id_2, table_schema, table_name, row_id, base_data, source_data, target_data, conflict_type, severity, resolution_data
- **Tests Fixed**: test_semantic_conflict_analysis (6+ tests)

### Phase 1.2: Database Fixture Thread-Safety
- **File**: tests/conftest.py
- **Issue**: Single psycopg connection shared across threads
- **Solution**: Implement ConnectionPool or thread-local connections
- **Tests Fixed**: All 5+ concurrent operation tests

### Phase 1.3: Test Parameter Fixes - Wave 1
- Fix 30+ create_temporal_snapshot() calls with correct (name, branch_id, description)
- Fix record_temporal_change() calls to handle new return tuple
- Fix query_historical_data() calls with missing p_end_time parameter
- Fix restore_table_to_point_in_time() calls with schema.table format
- **Tests Fixed**: 15+ parameter-related failures

---

## PHASE 2: Advanced Function Fixes (Days 3-4)

### Phase 2.1: ML Function Parameter Fixes
- learn_access_patterns(): Verify (lookback_hours INT, min_support INT) semantics
- predict_next_objects(): Fix calls passing INT for object_id instead of TEXT/UUID
- identify_conflict_patterns(): Fix calls passing 1 param instead of 3 (base, source, target)
- **Tests Fixed**: 4+ ML-related tests

### Phase 2.2: Temporal Function Parameter Fixes
- get_table_state_at_time(): Verify schema.table format used
- temporal_diff(): Verify (UUID, UUID, TEXT, TEXT) parameter order
- **Tests Fixed**: 2+ temporal-specific tests

### Phase 2.3: Conflict Resolution Function Fixes
- analyze_semantic_conflict(): Ensure conflict_id properly created before analyze
- attempt_auto_resolution(): Verify function exists and returns proper tuple
- **Tests Fixed**: 3+ conflict resolution tests

---

## PHASE 3: Edge Case & Schema Fixes (Days 5-6)

### Phase 3.1: Edge Case Handling
- NULL Value Handling: Allow NULL in commit messages
- Constraint Violation Handling: Ensure unique constraints enforced
- Cascade Delete Behavior: Verify ON DELETE CASCADE set on FKs
- **Tests Fixed**: 5+ edge case tests

### Phase 3.2: Schema Table Verification
- Verify all required tables exist: branches, commits, branch_versions, temporal_snapshots, temporal_changelog, ml_access_patterns, conflict_resolution_strategies, data_conflicts
- Verify all column types and constraints correct
- **Tests Fixed**: Schema-dependent tests (5+ tests)

### Phase 3.3: Test Fixture Enhancement
- Add main branch auto-creation to fixture
- Pre-populate sample data for ML tests
- Clear stale data after each test
- **Tests Fixed**: 10+ fixture-dependent tests

---

## PHASE 4: Test Refactoring (Days 7-8)

### Phase 4.1: E2E Docker Integration Tests (20 tests)
- Update all temporal snapshot calls with correct parameters
- Fix record_temporal_change calls to handle return tuple
- Fix ML operation parameter semantics
- Fix conflict resolution test data setup

### Phase 4.2: E2E Enhanced Coverage Tests (35 tests)
- Refactor concurrent tests for thread-safe DB fixture
- Fix Python json.dumps() in SQL contexts
- Ensure all parameter types match function signatures
- Update edge case assertions

### Phase 4.3: E2E Phase A Tests (26 tests)
- Fix merge_branches() calls (once function exists)
- Fix all temporal function calls with correct parameters
- Fix ML function parameter types
- Apply pattern from 4.1

### Phase 4.4: E2E Phase B & C Tests (31 tests)
- Apply all fixes from 4.1-4.3
- Fix deployment scenario parameter passing
- Fix performance test assertions

---

## PHASE 5: Integration Testing & Verification (Days 9-10)

### Phase 5.1: Test by Category
- Run each test file individually, verify 100% pass
- test_e2e_docker_integration.py: 20/20 ✓
- test_e2e_enhanced_coverage.py: 35/35 ✓
- test_e2e_phase_a_quality_improvements.py: 26/26 ✓
- test_e2e_phase_b_quality_improvements.py: 16/16 ✓
- test_e2e_phase_c_quality_improvements.py: 15/15 ✓

### Phase 5.2: Complete Test Suite Run
- Run all 232 tests: pytest tests/ -v
- Expected: 232 passed, 7 skipped, 5 xfailed, 1 xpassed
- Generate test report with coverage

### Phase 5.3: Documentation & Commit
- Create FUNCTION_SIGNATURES.md documentation
- Create migration script for schema changes
- Final comprehensive commit with all fixes

---

## Priority-Ordered Fix List (Quick Reference)

**CRITICAL (Must Do First)**:
1. [ ] verify create_temporal_snapshot() is called correctly (35+ fixes)
2. [ ] Fix record_temporal_change() VOID issue
3. [ ] Implement/verify merge_branches() exists
4. [ ] Create data_conflicts table
5. [ ] Make DB fixture thread-safe

**HIGH (Days 2-3)**:
6. [ ] Fix all query_historical_data() parameter order
7. [ ] Fix all restore_table_to_point_in_time() parameter format
8. [ ] Fix ML function parameter types (learn_access_patterns, predict_next_objects)
9. [ ] Fix identify_conflict_patterns() parameter count
10. [ ] Update all test expectations for new function return values

**MEDIUM (Days 4-6)**:
11. [ ] Edge case handling (NULL values, constraints)
12. [ ] Schema verification and fixes
13. [ ] Test fixture enhancement
14. [ ] Concurrent test refactoring

**LOW (Days 7-10)**:
15. [ ] Documentation updates
16. [ ] Final integration testing
17. [ ] Code review and commit

---

## Expected Results After Each Phase

| Phase | E2E Pass Rate | Cumulative Tests Fixed | Status |
|-------|---------------|------------------------|--------|
| **Phase 1** | ~60% (39/65) | 26 | Critical blockers resolved |
| **Phase 2** | ~75% (49/65) | 39 | Function semantics fixed |
| **Phase 3** | ~88% (57/65) | 52 | Schema and edge cases fixed |
| **Phase 4** | ~98% (64/65) | 61 | Test code refactored |
| **Phase 5** | ~100% (65/65) | 61 | Full verification & commit |

---

## Success Criteria

✅ **Project Complete When**:
- [ ] All 232 tests passing
- [ ] No test regressions
- [ ] Documentation updated
- [ ] Migration scripts tested
- [ ] Final commit made
- [ ] Code reviewed and approved

---

## Timeline Estimate

- **Best Case** (minimal complications): 8 days
- **Expected Case** (normal challenges): 10-12 days
- **Worst Case** (major issues): 14-16 days

**Recommended Approach**: Complete Phase 1 entirely before starting Phase 2, etc.

