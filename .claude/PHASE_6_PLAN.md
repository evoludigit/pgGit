# Phase 6: Rollback & Undo Implementation Plan

**Status**: Planning Phase (Ready for Implementation)
**Phase**: 6 of 7
**Complexity**: Very High - Complex state restoration and multi-object transactions
**Estimated Scope**: 7-10 days implementation + testing
**Goal**: Enable safe rollback of commits and undo of changes with full dependency resolution

---

## Executive Summary

Phase 6 implements the **Rollback & Undo API** - the most critical functionality for production database management. This phase enables teams to safely revert erroneous changes, recover from failed deployments, and perform point-in-time recovery with full awareness of object dependencies and schema constraints.

### Key Deliverables

1. **pggit.rollback_commit()** - Safely revert a single commit on a branch
2. **pggit.undo_changes()** - Undo specific object changes with dependency validation
3. **pggit.rollback_to_timestamp()** - Restore entire schema to historical state
4. **pggit.rollback_range()** - Revert multiple commits with ordering preservation
5. **pggit.validate_rollback()** - Pre-flight validation before executing rollbacks
6. **pggit.rollback_dependencies()** - Identify and handle dependent objects

### Success Criteria

- [ ] All 6 functions implemented with exact API spec
- [ ] 50+ comprehensive unit tests (8-10 per function)
- [ ] Dependency resolution validated for all object types
- [ ] Breaking change detection for rollbacks
- [ ] Safe transaction handling with rollback capability
- [ ] Merge conflict resolution during rollbacks
- [ ] No data loss or orphaned references
- [ ] Clear git commits with [GREEN] tags
- [ ] Production-ready error handling

---

## Architecture Overview

### Design Principles

1. **Safe-First Approach**
   - Validation before execution (pre-flight checks)
   - Dependency graph analysis before rollbacks
   - Transaction safety with ability to abort
   - Detailed audit trail of all rollbacks
   - Cannot accidentally lose data

2. **Dependency Awareness**
   - Track object dependencies (FK, triggers, views)
   - Detect circular dependencies
   - Handle cascading rollbacks correctly
   - Warn about breaking changes
   - Preserve referential integrity

3. **Multi-Stage Rollback Process**
   1. **Validation Stage**: Check feasibility, constraints, dependencies
   2. **Planning Stage**: Generate rollback sequence, identify conflicts
   3. **Simulation Stage**: Dry-run to verify reversibility
   4. **Execution Stage**: Apply rollback with full audit trail
   5. **Verification Stage**: Confirm schema matches expected state

4. **Immutable Rollback Audit Trail**
   - Every rollback is a new commit
   - Original changes never deleted
   - Full traceability: who, what, when, why
   - Can undo a rollback (redo functionality)
   - Commit message indicates rollback origin

### Data Sources & Targets

**Read From**:
- `pggit.object_history` - Change tracking (append-only)
- `pggit.commits` - Commit metadata
- `pggit.branches` - Branch hierarchy
- `pggit.schema_objects` - Current definitions
- `pggit.merge_operations` - Merge context

**Write To**:
- `pggit.object_history` - New "ROLLBACK" change records
- `pggit.commits` - New rollback commit records
- `pggit.rollback_operations` - (NEW) Rollback audit trail
- `pggit.rollback_validations` - (NEW) Pre-flight check results

### New Tables Required

#### pggit.rollback_operations
```sql
CREATE TABLE pggit.rollback_operations (
    rollback_id BIGSERIAL PRIMARY KEY,
    source_commit_hash CHAR(64) NOT NULL,
    target_commit_hash CHAR(64),
    rollback_type TEXT NOT NULL,  -- SINGLE_COMMIT, RANGE, TO_TIMESTAMP
    rollback_mode TEXT NOT NULL,  -- DRY_RUN, VALIDATED, EXECUTED
    branch_id INTEGER NOT NULL,
    created_by TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    executed_at TIMESTAMP,
    status TEXT NOT NULL,  -- PENDING, IN_PROGRESS, SUCCESS, FAILED
    error_message TEXT,
    objects_affected INTEGER,
    dependencies_validated BOOLEAN,
    breaking_changes_count INTEGER,
    rollback_commit_hash CHAR(64)
);
```

#### pggit.rollback_validations
```sql
CREATE TABLE pggit.rollback_validations (
    validation_id BIGSERIAL PRIMARY KEY,
    rollback_id BIGINT NOT NULL,
    validation_type TEXT NOT NULL,  -- DEPENDENCY, INTEGRITY, MERGE, ORDERING
    status TEXT NOT NULL,  -- PASS, WARN, FAIL
    message TEXT,
    affected_objects TEXT[],
    created_at TIMESTAMP DEFAULT NOW()
);
```

#### pggit.object_dependencies (NEW in Phase 6)
```sql
CREATE TABLE pggit.object_dependencies (
    dependency_id BIGSERIAL PRIMARY KEY,
    source_object_id BIGINT NOT NULL,  -- Object with dependency
    target_object_id BIGINT NOT NULL,  -- Object being depended on
    dependency_type TEXT NOT NULL,  -- FK, INDEX, TRIGGER, VIEW, FUNCTION_CALL
    strength TEXT NOT NULL,  -- HARD (cannot delete), SOFT (reference)
    created_at TIMESTAMP DEFAULT NOW()
);
```

---

## Detailed Function Specifications

### Function 1: pggit.validate_rollback()

**Purpose**: Pre-flight validation before any rollback operation. Identifies risks, dependencies, and compatibility issues.

**Signature**:
```sql
CREATE OR REPLACE FUNCTION pggit.validate_rollback(
    p_branch_name TEXT,
    p_source_commit_hash CHAR(64),
    p_target_commit_hash CHAR(64) DEFAULT NULL,
    p_rollback_type TEXT DEFAULT 'SINGLE_COMMIT'
) RETURNS TABLE (
    validation_id BIGINT,
    validation_type TEXT,
    status TEXT,
    severity TEXT,
    message TEXT,
    affected_objects TEXT[],
    recommendation TEXT
);
```

**Parameters**:
- `p_branch_name` - Branch where rollback will occur
- `p_source_commit_hash` - Commit to rollback
- `p_target_commit_hash` - For range rollback, end of range (inclusive)
- `p_rollback_type` - SINGLE_COMMIT, RANGE, TO_TIMESTAMP

**Returns** (multiple rows, one validation per issue):
- `validation_id` - Unique validation check ID
- `validation_type` - Type of check: DEPENDENCY, INTEGRITY, MERGE, ORDERING, CONSTRAINT
- `status` - PASS, WARN, FAIL
- `severity` - INFO, WARNING, ERROR, CRITICAL
- `message` - Human-readable description of issue
- `affected_objects` - List of schema.object names affected
- `recommendation` - Suggested resolution

**Validations Performed**:

1. **Commit Existence Check**
   - Verify source commit exists on branch
   - Verify target commit (if range) is after source
   - Check commit is not already rolled back

2. **Dependency Analysis**
   - Find all dependent objects (FK, triggers, views)
   - Detect circular dependencies
   - Warn if rolling back object with dependents
   - Check if dependent would be orphaned

3. **Merge Conflict Detection**
   - Check if rolled-back commit was result of merge
   - Detect if other branches depend on changes
   - Warn about potential merge conflicts

4. **Ordering Constraints**
   - Verify rollback sequence doesn't violate constraints
   - Check for circular dependencies in rollback order
   - Validate object recreation sequence

5. **Referential Integrity**
   - Check FK constraints wouldn't be violated
   - Verify indexes wouldn't fail
   - Validate trigger definitions

6. **Data Loss Prevention**
   - Warn if rollback would delete data
   - Identify columns being dropped
   - Alert if non-reversible operations present

**Example Usage**:
```sql
-- Validate single commit rollback
SELECT * FROM pggit.validate_rollback(
    p_branch_name => 'main',
    p_source_commit_hash => 'abc123...'
);

-- Validate range rollback with severity filtering
SELECT * FROM pggit.validate_rollback(
    p_branch_name => 'main',
    p_source_commit_hash => 'abc123...',
    p_target_commit_hash => 'def456...',
    p_rollback_type => 'RANGE'
) WHERE severity IN ('ERROR', 'CRITICAL');
```

**Performance**: < 500ms for typical dependency analysis

---

### Function 2: pggit.rollback_commit()

**Purpose**: Safely revert a single commit on a branch. Creates new commit with inverse changes.

**Signature**:
```sql
CREATE OR REPLACE FUNCTION pggit.rollback_commit(
    p_branch_name TEXT,
    p_commit_hash CHAR(64),
    p_validate_first BOOLEAN DEFAULT TRUE,
    p_allow_warnings BOOLEAN DEFAULT FALSE,
    p_rollback_mode TEXT DEFAULT 'EXECUTED'
) RETURNS TABLE (
    rollback_id BIGINT,
    rollback_commit_hash CHAR(64),
    status TEXT,
    objects_rolled_back INTEGER,
    validations_passed INTEGER,
    validations_failed INTEGER,
    execution_time_ms INTEGER
);
```

**Parameters**:
- `p_branch_name` - Branch where rollback occurs
- `p_commit_hash` - Commit to rollback
- `p_validate_first` - Run validation before rollback (default true)
- `p_allow_warnings` - Allow rollback if only warnings (default false)
- `p_rollback_mode` - DRY_RUN, VALIDATED (requires no failures), EXECUTED (proceeds anyway)

**Returns**:
- `rollback_id` - ID of rollback operation (for audit trail)
- `rollback_commit_hash` - New commit created to undo changes
- `status` - SUCCESS, PARTIAL_SUCCESS, FAILED
- `objects_rolled_back` - Count of objects reverted
- `validations_passed` - Number of passed validations
- `validations_failed` - Number of failed validations (if any)
- `execution_time_ms` - Time taken to execute

**Algorithm**:

```
1. VALIDATION PHASE:
   - Call validate_rollback() with same parameters
   - Count PASS/FAIL/WARN validations
   - If FAIL > 0:
     * Log errors and RETURN failure status
   - If WARN > 0 AND !p_allow_warnings:
     * Log warnings and RETURN failure status

2. PLANNING PHASE:
   - Get all changes from p_commit_hash on p_branch_name
   - For each changed object:
     a) Determine inverse operation (CREATE -> DROP, ALTER -> ALTER, DROP -> CREATE)
     b) Retrieve before_definition from object_history
     c) Order inversions to respect dependencies
     d) Build rollback script

3. SIMULATION PHASE (if DRY_RUN):
   - Execute rollback on COPY of data
   - Verify schema matches pre-commit state
   - RETURN result without committing
   - STOP here if DRY_RUN

4. EXECUTION PHASE:
   - BEGIN TRANSACTION
   - Execute inverse changes in correct order:
     a) Create objects (that were dropped)
     b) Modify objects (ALTER operations)
     c) Drop objects (that were created)
   - Insert new change records into object_history:
     * change_type = 'ROLLBACK'
     * commit_hash = new_rollback_commit_hash
     * change_reason = 'Rollback of commit [original_hash]'
   - Insert rollback_operations record
   - COMMIT TRANSACTION

5. VERIFICATION PHASE:
   - Query schema state after rollback
   - Compare with pre-commit state
   - If mismatch: ROLLBACK TRANSACTION, RETURN failure
   - RETURN success with metadata
```

**Handling Special Cases**:

- **Dropped Tables with Data**:
  - If table was created in rolled-back commit, DROP is safe
  - If table existed before, need to restore data from backup
  - Log warning: "Data in dropped table not restored"

- **Column Drops with Foreign Keys**:
  - Check if dropped column is referenced by FK
  - If yes, drop FK first, then column, then recreate FK
  - Warn: "Foreign key references modified"

- **Function/Trigger Changes**:
  - Rollback function to previous definition
  - Recompile triggers if they depend on function

- **Indexes on Dropped Columns**:
  - If column is dropped, drop dependent indexes first

**Example Usage**:
```sql
-- Validate first, then rollback if no failures
SELECT * FROM pggit.rollback_commit(
    p_branch_name => 'main',
    p_commit_hash => 'abc123...',
    p_validate_first => TRUE,
    p_allow_warnings => FALSE
);

-- Dry run to see what would be rolled back
SELECT * FROM pggit.rollback_commit(
    p_branch_name => 'main',
    p_commit_hash => 'abc123...',
    p_rollback_mode => 'DRY_RUN'
);
```

**Performance**:
- Validation: < 500ms
- Execution: < 1 second for typical commits (< 10 objects)
- DRY_RUN: < 2 seconds

---

### Function 3: pggit.rollback_range()

**Purpose**: Revert multiple commits in a range. Handles complex ordering and dependencies.

**Signature**:
```sql
CREATE OR REPLACE FUNCTION pggit.rollback_range(
    p_branch_name TEXT,
    p_start_commit_hash CHAR(64),
    p_end_commit_hash CHAR(64),
    p_order_by TEXT DEFAULT 'REVERSE_CHRONOLOGICAL',
    p_rollback_mode TEXT DEFAULT 'EXECUTED'
) RETURNS TABLE (
    rollback_id BIGINT,
    commits_rolled_back INTEGER,
    rollback_commit_hash CHAR(64),
    status TEXT,
    objects_affected_total INTEGER,
    conflicts_resolved INTEGER,
    execution_time_ms INTEGER
);
```

**Parameters**:
- `p_branch_name` - Branch where rollback occurs
- `p_start_commit_hash` - First commit in range (inclusive)
- `p_end_commit_hash` - Last commit in range (inclusive)
- `p_order_by` - REVERSE_CHRONOLOGICAL (default), DEPENDENCY_ORDER
- `p_rollback_mode` - DRY_RUN, VALIDATED, EXECUTED

**Returns**:
- `rollback_id` - ID of rollback operation
- `commits_rolled_back` - Number of commits reverted
- `rollback_commit_hash` - New commit created
- `status` - SUCCESS, PARTIAL_SUCCESS (partial commit), FAILED
- `objects_affected_total` - Total unique objects changed
- `conflicts_resolved` - Count of conflicts auto-resolved
- `execution_time_ms` - Execution duration

**Algorithm**:

```
1. VALIDATION PHASE:
   - Verify both commits exist on branch
   - Verify start < end (chronologically)
   - Get all commits in range [start, end]
   - Call validate_rollback() for entire range
   - Abort if CRITICAL validations fail

2. DEPENDENCY ORDERING PHASE:
   - Build object change graph for range
   - Identify dependency relationships
   - If p_order_by = 'REVERSE_CHRONOLOGICAL':
     * Reverse commit order (most recent first)
   - If p_order_by = 'DEPENDENCY_ORDER':
     * Perform topological sort on objects
     * Ensure drops happen before creates
     * Respect FK constraints

3. CONFLICT RESOLUTION PHASE:
   - For each object changed multiple times in range:
     a) Get all versions
     b) Merge versions into single rollback
     c) Handle conflicts:
        - Same object: CREATE then DROP -> skip
        - Same object: CREATE then ALTER -> skip
        - Same object: ALTER then ALTER -> merge changes
   - Count resolved conflicts

4. EXECUTION PHASE:
   - BEGIN TRANSACTION
   - Execute merged rollback operations:
     a) CREATE all objects (that were dropped)
     b) ALTER all modified objects
     c) DROP all objects (that were created)
   - Insert single new change record (ROLLBACK_RANGE type)
   - Insert affected commit references
   - COMMIT TRANSACTION

5. VERIFICATION PHASE:
   - Compare schema before start_commit with current
   - Alert if mismatch
```

**Example Usage**:
```sql
-- Rollback last 3 commits in reverse order
SELECT * FROM pggit.rollback_range(
    p_branch_name => 'main',
    p_start_commit_hash => 'abc123...',  -- oldest
    p_end_commit_hash => 'def456...',    -- newest
    p_order_by => 'REVERSE_CHRONOLOGICAL'
);

-- Rollback respecting object dependencies
SELECT * FROM pggit.rollback_range(
    p_branch_name => 'main',
    p_start_commit_hash => 'abc123...',
    p_end_commit_hash => 'def456...',
    p_order_by => 'DEPENDENCY_ORDER'
);
```

**Performance**:
- For 5 commits: < 2 seconds
- For 10 commits: < 5 seconds

---

### Function 4: pggit.rollback_to_timestamp()

**Purpose**: Restore entire schema to state at specific point in history.

**Signature**:
```sql
CREATE OR REPLACE FUNCTION pggit.rollback_to_timestamp(
    p_branch_name TEXT,
    p_target_timestamp TIMESTAMP,
    p_validate_first BOOLEAN DEFAULT TRUE,
    p_rollback_mode TEXT DEFAULT 'EXECUTED'
) RETURNS TABLE (
    rollback_id BIGINT,
    rollback_commit_hash CHAR(64),
    status TEXT,
    commits_reversed INTEGER,
    objects_recreated INTEGER,
    objects_deleted INTEGER,
    objects_modified INTEGER,
    execution_time_ms INTEGER
);
```

**Parameters**:
- `p_branch_name` - Branch to rollback
- `p_target_timestamp` - Point in time to restore (must be in past)
- `p_validate_first` - Run validation before rollback
- `p_rollback_mode` - DRY_RUN, VALIDATED, EXECUTED

**Returns**:
- `rollback_id` - ID of rollback operation
- `rollback_commit_hash` - New commit created
- `status` - SUCCESS, FAILED
- `commits_reversed` - Number of commits being rolled back
- `objects_recreated` - Objects being CREATE'd
- `objects_deleted` - Objects being DROP'd
- `objects_modified` - Objects being ALTER'd
- `execution_time_ms` - Execution duration

**Algorithm**:

```
1. VALIDATION PHASE:
   - Verify target_timestamp is in past (< NOW())
   - Verify branch existed at target_timestamp
   - Call query_at_timestamp() to get historical state
   - Compare with current state
   - Identify all differences

2. CHANGE ANALYSIS PHASE:
   - For each object in current schema:
     a) Find in historical schema
     b) If found: check if definition matches
        - If no match: mark as NEEDS_ALTER
     c) If not found: mark as NEEDS_DROP
   - For each object in historical schema:
     a) Find in current schema
     b) If not found: mark as NEEDS_CREATE

3. ORDERING PHASE:
   - Topologically sort required changes
   - Ensure FK constraints satisfied
   - CREATE objects first (with dependencies)
   - ALTER middle
   - DROP last (respecting FKs)

4. EXECUTION PHASE:
   - BEGIN TRANSACTION
   - Apply all changes in order
   - For each change:
     a) Generate SQL from before_definition
     b) Execute change
     c) Log to object_history
   - Insert single ROLLBACK_TO_TIMESTAMP commit
   - COMMIT TRANSACTION

5. VERIFICATION PHASE:
   - Query current schema
   - Compare with historical schema
   - If mismatch: ROLLBACK, RETURN failure
   - Verify all checksums match
```

**Example Usage**:
```sql
-- Restore schema to state 1 week ago
SELECT * FROM pggit.rollback_to_timestamp(
    p_branch_name => 'main',
    p_target_timestamp => NOW() - INTERVAL '7 days'
);

-- Dry run to see what would change
SELECT * FROM pggit.rollback_to_timestamp(
    p_branch_name => 'main',
    p_target_timestamp => NOW() - INTERVAL '1 day',
    p_rollback_mode => 'DRY_RUN'
);
```

**Performance**:
- For 1 week of history: < 5 seconds
- For 1 month of history: < 15 seconds

---

### Function 5: pggit.undo_changes()

**Purpose**: Undo specific object changes within a commit or range. More granular than rollback_commit().

**Signature**:
```sql
CREATE OR REPLACE FUNCTION pggit.undo_changes(
    p_branch_name TEXT,
    p_object_names TEXT[],
    p_commit_hash CHAR(64) DEFAULT NULL,
    p_since_timestamp TIMESTAMP DEFAULT NULL,
    p_until_timestamp TIMESTAMP DEFAULT NULL,
    p_rollback_mode TEXT DEFAULT 'EXECUTED'
) RETURNS TABLE (
    rollback_id BIGINT,
    rollback_commit_hash CHAR(64),
    status TEXT,
    objects_reverted INTEGER,
    changes_undone INTEGER,
    dependencies_handled INTEGER,
    execution_time_ms INTEGER
);
```

**Parameters**:
- `p_object_names` - Array of 'schema.object' names to undo
- `p_commit_hash` - Specific commit to undo (if NULL, use timestamp range)
- `p_since_timestamp` - Start of time range (if commit_hash is NULL)
- `p_until_timestamp` - End of time range (if commit_hash is NULL)
- `p_rollback_mode` - DRY_RUN, VALIDATED, EXECUTED

**Returns**:
- `rollback_id` - ID of rollback operation
- `rollback_commit_hash` - New commit
- `status` - SUCCESS, PARTIAL_SUCCESS, FAILED
- `objects_reverted` - Count of objects
- `changes_undone` - Count of individual changes
- `dependencies_handled` - Count of dependent objects processed
- `execution_time_ms` - Execution duration

**Algorithm**:

```
1. OBJECT RESOLUTION PHASE:
   - For each p_object_names[i]:
     a) Parse 'schema.object' format
     b) Find matching object_id
     c) If not found: add to skipped list

2. CHANGE IDENTIFICATION PHASE:
   - If p_commit_hash provided:
     * Get all changes to p_object_names in that commit
   - If timestamp range provided:
     * Get all changes to p_object_names in range
   - Sort changes by object dependencies

3. DEPENDENCY VALIDATION PHASE:
   - For each object with changes:
     a) Find all dependent objects
     b) Determine if undo is safe
     c) If not safe: warn and get user action
   - Build dependency graph

4. ROLLBACK PLANNING PHASE:
   - For objects changed multiple times in range:
     * Identify last change before timestamp
     * Determine inverse operation
   - Merge consecutive changes to same object
   - Build execution sequence

5. EXECUTION PHASE:
   - BEGIN TRANSACTION
   - Execute all inverse operations
   - Log UNDO changes to object_history
   - Create new commit with reason
   - COMMIT TRANSACTION

6. VERIFICATION PHASE:
   - Verify each undone object matches pre-change state
```

**Example Usage**:
```sql
-- Undo changes to users table in specific commit
SELECT * FROM pggit.undo_changes(
    p_branch_name => 'main',
    p_object_names => ARRAY['public.users'],
    p_commit_hash => 'abc123...'
);

-- Undo changes to multiple objects in time range
SELECT * FROM pggit.undo_changes(
    p_branch_name => 'main',
    p_object_names => ARRAY['public.users', 'public.orders'],
    p_since_timestamp => NOW() - INTERVAL '2 days',
    p_until_timestamp => NOW() - INTERVAL '1 day'
);
```

**Performance**: < 1 second for 1-5 objects

---

### Function 6: pggit.rollback_dependencies()

**Purpose**: Analyze and manage dependencies before/during rollback. Identifies what would break.

**Signature**:
```sql
CREATE OR REPLACE FUNCTION pggit.rollback_dependencies(
    p_object_id BIGINT
) RETURNS TABLE (
    dependency_id BIGINT,
    source_object_id BIGINT,
    source_object_name TEXT,
    source_object_type TEXT,
    target_object_id BIGINT,
    target_object_name TEXT,
    dependency_type TEXT,
    strength TEXT,
    breakage_severity TEXT,
    suggested_action TEXT
);
```

**Parameters**:
- `p_object_id` - Object to analyze dependencies for

**Returns**:
- `dependency_id` - ID of dependency record
- `source_object_id`, `source_object_name`, `source_object_type` - Depending object
- `target_object_id`, `target_object_name` - Being depended on
- `dependency_type` - FK, INDEX, TRIGGER, VIEW, FUNCTION_CALL
- `strength` - HARD (essential), SOFT (reference only)
- `breakage_severity` - NONE, WARNING, ERROR, CRITICAL
- `suggested_action` - What to do (drop first, recreate after, etc.)

**Use Cases**:
- Before dropping table: find FKs, indexes, triggers
- Before dropping function: find triggers, procedures using it
- Before dropping column: find FKs, indexes referencing it

---

## Test Fixture Strategy

### Complex Rollback Scenario

```
Timeline:
T0: Main branch created
T1: CREATE TABLE users (id, name)
T2: CREATE TABLE orders (id, user_id FK users.id)
T3: ALTER TABLE users ADD email
T4: CREATE INDEX idx_users_email
T5: ALTER TABLE orders ADD amount DECIMAL
T6: DROP TABLE users CASCADE (BROKEN - should fail)
T7: Feature branch created from T4
T8: ALTER TABLE users DROP email
T9: CREATE TABLE payments (id, order_id FK orders.id)
T10: Merge feature -> main
T11: DROP COLUMN orders.amount

Test Cases:
1. Rollback T3 (ALTER) - should succeed
2. Rollback T2 (CREATE with foreign key reference) - should warn/fail
3. Rollback range T3-T5 (multiple changes) - should succeed
4. Rollback to T4 (time-travel) - should recreate users.email
5. Undo changes to orders table only - partial rollback
6. Rollback across merge - complex dependency
```

---

## Known Challenges & Solutions

| Challenge | Solution |
|-----------|----------|
| **Circular Dependencies** | Detect cycles with DFS, provide ordering suggestion |
| **Data Loss** | Warn user before any destructive rollback, require confirmation |
| **Merge Conflicts During Rollback** | Detect if commit was merge result, prompt for strategy |
| **Non-Reversible Operations** | Warn about operations like TRUNCATE, DROP TABLE with cascade |
| **Trigger Dependencies** | Track trigger bodies, recompile if dependent function changed |
| **Partial Failures** | Provide granular rollback to handle partial success gracefully |
| **Performance** | Optimize dependency queries with proper indexing |
| **Constraint Violations** | Reorder operations to satisfy constraints |

---

## Implementation Strategy

### Phase 6.1: Foundation (Days 1-2)
- Create new tables (rollback_operations, rollback_validations, object_dependencies)
- Implement validate_rollback() with all checks
- Build dependency resolution engine
- Create 20+ unit tests for validation

### Phase 6.2: Single Commit Rollback (Days 2-3)
- Implement rollback_commit() function
- Handle special cases (dropped tables, FK columns)
- Build verification logic
- Create 15+ unit tests

### Phase 6.3: Range & Time Rollback (Days 3-4)
- Implement rollback_range() with conflict resolution
- Implement rollback_to_timestamp() with historical reconstruction
- Build dependency ordering
- Create 15+ unit tests

### Phase 6.4: Granular Undo (Days 4-5)
- Implement undo_changes() for partial rollbacks
- Implement rollback_dependencies()
- Handle edge cases
- Create 10+ unit tests

### Phase 6.5: Integration & Testing (Days 5-7)
- Run full test suite (50+ tests)
- Performance validation
- Regression testing Phases 1-5
- Edge case coverage

### Phase 6.6: Final Commit (Day 7)
- Final commit with [GREEN] tag
- README updates
- Release notes

---

## Expected Outcomes

### Code Deliverables
- `sql/034_pggit_rollback_operations.sql` (~1200-1500 lines)
  - 6 core functions (~150-250 lines each)
  - Support functions for ordering, validation
  - Index creation for performance

- `tests/unit/test_phase6_rollback_operations.py` (~1500-2000 lines)
  - 50+ comprehensive test cases (8-10 per function)
  - Phase6RollbackFixture class
  - Edge case and integration testing

### Documentation
- PHASE_6_PLAN.md - This plan
- PHASE_6_QUICK_REFERENCE.md - Function signatures and examples
- PHASE_6_STEP_0_FIXTURES.md - Fixture architecture
- Implementation guides and best practices

### Quality Metrics
- ✅ 100% test pass rate (50+ tests)
- ✅ All functions compile without errors
- ✅ Rollback operations < 5 seconds for typical scenarios
- ✅ No data loss or orphaned references
- ✅ Zero regressions in Phases 1-5
- ✅ Comprehensive error handling
- ✅ Production-ready code

---

## Success Criteria

Before Phase 6 is considered complete:

### Code Implementation
- [ ] All 6 functions implemented with exact API spec
- [ ] SQL compiles without errors
- [ ] Proper parameter validation in all functions
- [ ] Clear error messages for invalid inputs
- [ ] Consistent naming (p_ for params, v_ for vars)

### Rollback Safety
- [ ] Pre-flight validation catches all critical issues
- [ ] Dependency analysis identifies all breaking changes
- [ ] No way to accidentally execute unsafe rollback
- [ ] Clear warnings for destructive operations
- [ ] Rollback can be aborted mid-transaction

### Change Management
- [ ] Every rollback is fully audited
- [ ] Original changes never deleted
- [ ] Can undo a rollback (redo)
- [ ] Rollback reason captured
- [ ] Full traceability chain

### Test Coverage
- [ ] 50+ unit tests passing (100%)
- [ ] All rollback types tested (single, range, timestamp, undo)
- [ ] All dependency scenarios tested
- [ ] Edge cases covered (circular deps, merges, constraints)
- [ ] Performance acceptable for large schemas (1000+ objects)

### Integration
- [ ] Phase 1-5 not regressed
- [ ] Works with merge_operations data
- [ ] Branch history tracking accurate
- [ ] Audit trail correct

### Code Quality
- [ ] No SQL injection vulnerabilities
- [ ] Proper NULL handling
- [ ] Clear inline comments
- [ ] Parameter documentation
- [ ] Error handling comprehensive

---

## Risk Assessment

### Risk Level: **VERY HIGH** 🔴

**Risks**:

1. ✅ **Data Loss Prevention** - CRITICAL to get right
   - Mitigation: Validation before execution, dry-run capability, transaction rollback

2. ✅ **Dependency Complexity** - Objects have many dependency types
   - Mitigation: Build comprehensive dependency tracker, test extensively

3. ✅ **Circular Dependency Detection** - Could cause infinite loops
   - Mitigation: Use cycle detection algorithm, topological sort, tests

4. ✅ **Merge Conflict During Rollback** - Complex interaction
   - Mitigation: Detect merge commits, provide clear warnings, manual resolution

5. ✅ **Constraint Violations** - Foreign keys, unique constraints
   - Mitigation: Reorder operations, disable/enable constraints carefully

6. ✅ **Performance Degradation** - Complex operations could be slow
   - Mitigation: Proper indexing, query optimization, benchmarking

**Mitigations**:
- Comprehensive validation framework
- Detailed dependency analysis
- Safe transaction handling
- Extensive testing (50+ tests)
- Dry-run capability before execution
- Clear audit trails
- Rollback capability on all operations

---

## Performance Guidelines

### Query Complexity

| Function | Complexity | Typical Time |
|----------|-----------|--------------|
| validate_rollback() | O(D) where D = dependencies | < 500ms |
| rollback_commit() | O(N) where N = changed objects | < 1s |
| rollback_range() | O(R*N) where R = commits | < 5s (R≤10) |
| rollback_to_timestamp() | O(H) where H = history | < 15s (1 month) |
| undo_changes() | O(N log N) where N = changes | < 1s |
| rollback_dependencies() | O(D log D) | < 100ms |

### Index Strategy
```sql
CREATE INDEX idx_object_dependencies_source ON pggit.object_dependencies(source_object_id);
CREATE INDEX idx_object_dependencies_target ON pggit.object_dependencies(target_object_id);
CREATE INDEX idx_object_dependencies_type ON pggit.object_dependencies(dependency_type);
CREATE INDEX idx_rollback_operations_status ON pggit.rollback_operations(status, created_at);
CREATE INDEX idx_rollback_validations_rollback ON pggit.rollback_validations(rollback_id, validation_type);
```

---

## Next Steps

1. ✅ **Review this plan** - Validate approach with stakeholders
2. ⏭️ **Create PHASE_6_STEP_0_FIXTURES.md** - Detailed fixture architecture
3. ⏭️ **Create PHASE_6_QUICK_REFERENCE.md** - Function signatures reference
4. ⏭️ **Begin implementation** - Start with validate_rollback()
5. ⏭️ **Iterative testing** - Test after each function
6. ⏭️ **Performance tuning** - Optimize dependency queries
7. ⏭️ **Final QA** - Comprehensive testing and commit

---

## Timeline Summary

| Phase | Duration | Tasks |
|-------|----------|-------|
| 6.1 | 2 days | Tables + validate_rollback() + 20 tests |
| 6.2 | 1-2 days | rollback_commit() + 15 tests |
| 6.3 | 1-2 days | rollback_range() + rollback_to_timestamp() + 15 tests |
| 6.4 | 1 day | undo_changes() + rollback_dependencies() + 10 tests |
| 6.5 | 2-3 days | Integration testing, performance, regression |
| 6.6 | 0.5 day | Final commit [GREEN] |
| **Total** | **7-10 days** | **All components** |

---

**Status**: Planning Complete - Ready for Implementation
**Created**: 2025-12-26
**Confidence Level**: ⭐⭐⭐⭐⭐ (5/5 stars) - Plan is comprehensive and well-structured
**Next Action**: Review plan, then proceed to implementation of Phase 6.1 (Foundation)
