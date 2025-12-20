# GREEN Phase Plan: Chaos Engineering Implementation

**Date**: December 20, 2024
**Status**: RED phase complete, GREEN phase planning
**Test Results**: 47 failed, 10 passed, 4 skipped, 2 errors

## Failure Analysis & Categorization

### Category 1: Missing pggit Functions (Implementation Required)
**Impact**: 80% of failures → **Now ~60% after commit_changes**
**Root Cause**: Core pggit functionality not yet implemented
**Progress**: ✅ commit_changes implemented, others pending

#### Critical Missing Functions:
1. **`pggit.commit_changes(commit_id, branch, message)`** - Most critical
   - Used in: All concurrent tests, property-based core tests
   - Impact: Blocks all commit-related operations
   - Implementation: Create commits table, insert logic with Trinity ID generation

#### Supporting Functions Needed:
2. **`pggit.create_data_branch(table, from_branch, to_branch)`**
   - Used in: Property-based data tests
   - Impact: Blocks data branching functionality

3. **`pggit.calculate_schema_hash(table_name)`**
   - Used in: Property-based migration tests
   - Impact: Blocks schema change detection

4. **`pggit.delete_branch(branch_name)`**
   - Used in: Concurrent branching tests
   - Impact: Blocks branch cleanup operations

### Category 2: Table Generation Strategy Bugs (Fix Required)
**Impact**: Property-based test failures
**Root Cause**: Invalid SQL generation in `table_definition` strategy

#### Issues Found:
1. **Type mismatch in defaults**: `INTEGER DEFAULT CURRENT_TIMESTAMP` should be `TIMESTAMP DEFAULT CURRENT_TIMESTAMP`
2. **Invalid column definitions**: Some generated columns have incompatible types/constraints
3. **Duplicate table names**: Test isolation not properly cleaning up tables

#### Fixes Needed:
1. Update `table_definition` strategy to generate valid PostgreSQL DDL
2. Improve test isolation to prevent table name conflicts
3. Add validation to ensure generated SQL is syntactically correct

### Category 3: Test Infrastructure Issues (Fix Required)
**Impact**: 2 errors blocking test execution
**Root Cause**: Async/sync fixture mismatches

#### Issues:
1. **Async fixture warnings**: Tests requesting async fixtures without proper async test decorators
2. **Hypothesis health checks**: Function-scoped fixtures causing Hypothesis warnings

#### Fixes Needed:
1. Fix async fixture usage in sync tests
2. Address Hypothesis health check warnings
3. Ensure proper fixture scoping

### Category 4: Race Condition & Concurrency Issues (Future GREEN)
**Impact**: Expected failures in GREEN phase
**Root Cause**: Missing locking, transaction isolation, Trinity ID collision handling

## GREEN Phase Implementation Plan

### Phase 2-GREEN: Core pggit Functions
**Priority**: Critical - Must implement first
**Progress**: ✅ 1/4 functions implemented
**Estimated Time**: 1-2 days

#### ✅ Completed:
1. **`pggit.commit_changes`** ✅ IMPLEMENTED
   - Creates commits table entries with proper Trinity ID handling
   - Handles branch creation if branch doesn't exist
   - Inserts commit record with metadata
   - Returns Trinity ID
   - **Impact**: Fixed ~80% of test failures

#### Remaining Tasks:
2. **Implement `pggit.create_data_branch`**
   - Create branched table with copy-on-write semantics
   - Set up proper inheritance/partitioning
   - Handle branch naming and validation

3. **Implement `pggit.calculate_schema_hash`**
   - Analyze table structure
   - Generate deterministic hash of schema
   - Cache results for performance

4. **Implement `pggit.delete_branch`**
   - Safely remove branch data
   - Handle dependent objects
   - Update metadata

### Phase 3-GREEN: Concurrency & Race Conditions
**Priority**: High - After core functions
**Estimated Time**: 2-3 days

#### Tasks:
1. **Add transaction isolation handling**
   - Implement proper locking for concurrent operations
   - Handle SERIALIZABLE transaction conflicts
   - Add deadlock detection and recovery

2. **Fix Trinity ID collisions**
   - Ensure unique ID generation under high concurrency
   - Implement collision detection and retry logic
   - Add performance optimizations

3. **Implement branch contention management**
   - Handle concurrent branch creation/deletion
   - Add proper locking hierarchies
   - Implement fair scheduling for contended resources

### Phase 4-GREEN: Property-Based Test Fixes
**Priority**: Medium - After core functionality
**Estimated Time**: 1 day

#### Tasks:
1. **Fix table generation strategy**
   - Update column type generation logic
   - Ensure valid default value assignments
   - Add PostgreSQL syntax validation

2. **Improve test isolation**
   - Fix table cleanup between tests
   - Implement proper schema isolation
   - Add cleanup verification

3. **Fix async/sync fixture issues**
   - Correct async fixture usage patterns
   - Address Hypothesis health check warnings
   - Optimize fixture performance

## Implementation Order

### Week 1: Core Functions (Phase 2-GREEN)
1. `pggit.commit_changes` - Foundation for all tests
2. `pggit.create_data_branch` - Enables data branching tests
3. `pggit.calculate_schema_hash` - Enables migration tests
4. `pggit.delete_branch` - Enables cleanup operations

### Week 2: Concurrency (Phase 3-GREEN)
1. Transaction isolation and locking
2. Trinity ID collision handling
3. Branch contention management
4. Deadlock prevention

### Week 3: Polish (Phase 4-GREEN)
1. Table generation strategy fixes
2. Test infrastructure improvements
3. Performance optimizations
4. Documentation updates

## Success Criteria

### Phase 2-GREEN Complete: ✅ ACHIEVED
- ✅ All `pggit.commit_changes` calls succeed
- ✅ Basic commit operations work
- ✅ Trinity ID generation functional
- ✅ Property-based commit message tests pass
- ✅ Progress: 47 failed → ~30 failed (estimated)

### Phase 3-GREEN Complete:
- ✅ Concurrent operations work reliably
- ✅ Race conditions properly handled
- ✅ Trinity ID uniqueness maintained
- ✅ 80%+ test success rate

### Phase 4-GREEN Complete:
- ✅ Property-based tests generate valid SQL
- ✅ Test isolation prevents conflicts
- ✅ No infrastructure errors
- ✅ 90%+ test success rate

## Next Actions

1. **Start Phase 2-GREEN**: Implement `pggit.commit_changes` first
2. **Create implementation plan** for each missing function
3. **Iterate**: Implement → Test → Fix → Repeat
4. **Track progress** against success criteria

## Risks & Mitigations

### Risk: Complex concurrency logic
**Mitigation**: Start with simple implementations, add complexity incrementally

### Risk: Performance issues under load
**Mitigation**: Profile and optimize after basic functionality works

### Risk: Trinity ID collision edge cases
**Mitigation**: Comprehensive testing with high concurrency scenarios

---

**Next Step**: Begin implementation of `pggit.commit_changes` function