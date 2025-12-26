# Phase 5: History & Audit Implementation Plan

**Status**: Planning Phase (Ready for Review)
**Phase**: 5 of 7
**Complexity**: High - Complex historical queries and time-travel logic
**Estimated Scope**: 5-7 days implementation + testing
**Goal**: Enable complete audit trail visibility, historical queries, and time-travel capabilities

---

## Executive Summary

Phase 5 implements the **History & Audit API** - four core functions that provide complete visibility into schema history, audit trails, and temporal queries. This phase bridges the merge operations (Phase 4) with advanced features like rollback/undo (Phase 6).

### Key Deliverables

1. **pggit.get_commit_history()** - View commit history with filtering, pagination, and graph visualization
2. **pggit.get_audit_trail()** - Complete immutable audit trail of all object changes
3. **pggit.get_object_timeline()** - Timeline view of how specific objects evolved
4. **pggit.query_at_timestamp()** - Time-travel: Query schema state at any point in history

### Success Criteria

- [ ] All 4 functions implemented with exact API spec
- [ ] 40+ comprehensive unit tests (10 per function)
- [ ] Full audit trail immutability and integrity
- [ ] Efficient historical queries with proper indexing
- [ ] Time-travel queries work across all branches
- [ ] Change cause tracking and reasoning
- [ ] No data loss during historical queries
- [ ] Clear git commits with [GREEN] tags

---

## Architecture Overview

### Design Principles

1. **Immutable Audit Trail**
   - All historical data is append-only
   - No modification or deletion of audit records
   - Complete traceback of all changes
   - Tamper-proof timestamps

2. **Rich Change Metadata**
   - Who made the change (user/session)
   - When the change occurred
   - What changed (before/after definitions)
   - Why it changed (commit message, merge reason)
   - Where in the branch hierarchy

3. **Efficient Historical Queries**
   - Proper indexing on timestamps and object_id
   - CTEs for hierarchical queries
   - Pagination support for large result sets
   - Performance optimization for common queries

4. **Time-Travel Capability**
   - Reconstruct schema state at any point
   - Works across all branches
   - Respects branch creation times
   - Handles merge histories correctly

### Data Sources

**From Phase 1 (Foundation):**
- `pggit.object_history` - Change tracking (append-only)
  - Fields: history_id, object_id, change_type, before_hash, after_hash, commit_hash, branch_id, change_reason
- `pggit.commits` - Commit metadata
  - Fields: commit_id, commit_hash, branch_id, author_name, author_time, commit_message
- `pggit.schema_objects` - Current object definitions
  - Fields: object_id, object_type, schema_name, object_name, current_definition, content_hash

**From Phase 2 (Branch Management):**
- `pggit.branches` - Branch metadata
  - Fields: branch_id, branch_name, parent_branch_id, status, created_at, created_by

**From Phase 4 (Merge Operations):**
- `pggit.merge_operations` - Merge audit trail
  - Fields: id, source_branch_id, target_branch_id, merge_strategy, status, merged_at, merged_by

---

## Detailed Function Specifications

### Function 1: pggit.get_commit_history()

**Purpose**: View commit history with advanced filtering, pagination, and visualization.

**Signature**:
```sql
CREATE OR REPLACE FUNCTION pggit.get_commit_history(
    p_branch_name TEXT DEFAULT NULL,
    p_since_timestamp TIMESTAMP DEFAULT NULL,
    p_until_timestamp TIMESTAMP DEFAULT NULL,
    p_author_name TEXT DEFAULT NULL,
    p_search_message TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0,
    p_order_by TEXT DEFAULT 'author_time DESC'
) RETURNS TABLE (
    commit_id BIGINT,
    commit_hash CHAR(64),
    branch_name TEXT,
    parent_commit_hash CHAR(64),
    author_name TEXT,
    author_time TIMESTAMP,
    commit_message TEXT,
    objects_changed INTEGER,
    objects_added INTEGER,
    objects_deleted INTEGER,
    objects_modified INTEGER,
    merge_info TEXT,
    ancestry_depth INTEGER
);
```

**Parameters**:
- `p_branch_name` - Specific branch to query (NULL = all branches)
- `p_since_timestamp` - Show commits after this timestamp (NULL = all)
- `p_until_timestamp` - Show commits before this timestamp (NULL = all)
- `p_author_name` - Filter by commit author (NULL = all)
- `p_search_message` - Full-text search in commit messages (NULL = all)
- `p_limit` - Maximum results to return (default 50)
- `p_offset` - Pagination offset (default 0)
- `p_order_by` - Sort order (default 'author_time DESC')

**Returns**:
- `commit_id` - Unique commit identifier
- `commit_hash` - Content hash of commit
- `branch_name` - Which branch the commit belongs to
- `parent_commit_hash` - Parent commit (for ancestry)
- `author_name` - Who created the commit
- `author_time` - When the commit was created
- `commit_message` - User-provided commit description
- `objects_changed` - Total number of objects affected
- `objects_added` - Count of new objects
- `objects_deleted` - Count of deleted objects
- `objects_modified` - Count of modified objects
- `merge_info` - Description if this was a merge commit
- `ancestry_depth` - How deep in branch tree (for visualization)

**Algorithm**:

```
1. VALIDATE INPUTS:
   - Verify branch exists if specified
   - Validate timestamps are chronological
   - Check p_limit is reasonable (1-1000)

2. BUILD COMMIT QUERY:
   - Start with pggit.commits table
   - JOIN pggit.branches for branch_name
   - JOIN pggit.merge_operations for merge_info
   - JOIN LEFT to pggit.object_history for change counts

3. APPLY FILTERS:
   - IF p_branch_name: WHERE branch_id = (SELECT from branches)
   - IF p_since_timestamp: WHERE author_time >= p_since_timestamp
   - IF p_until_timestamp: WHERE author_time <= p_until_timestamp
   - IF p_author_name: WHERE author_name ILIKE p_author_name
   - IF p_search_message: WHERE commit_message ILIKE p_search_message

4. CALCULATE METRICS:
   - objects_changed = COUNT(DISTINCT object_id) in that commit
   - objects_added = COUNT(*) WHERE change_type = 'CREATE'
   - objects_deleted = COUNT(*) WHERE change_type = 'DROP'
   - objects_modified = COUNT(*) WHERE change_type = 'ALTER'

5. CALCULATE ANCESTRY DEPTH:
   - Use recursive CTE with pggit.branches.parent_branch_id
   - Count levels from branch to root (main)

6. MERGE INFO:
   - LEFT JOIN pggit.merge_operations
   - Format: "Merge branch-a -> branch-b (STRATEGY)"

7. ORDER & PAGINATE:
   - Apply ORDER BY p_order_by
   - OFFSET p_offset LIMIT p_limit

8. RETURN RESULTS
```

**Performance Considerations**:
- Index on: commits.author_time, commits.branch_id, commits.commit_hash
- Index on: object_history.commit_hash, object_history.object_id
- Use EXPLAIN ANALYZE for query planning
- Pagination critical for large histories (100K+ commits)

**Test Cases** (10 tests):
1. `test_commit_history_all_commits` - Returns all commits unfiltered
2. `test_commit_history_branch_filter` - Filter by specific branch
3. `test_commit_history_time_range` - Filter by date range
4. `test_commit_history_author_filter` - Filter by author name
5. `test_commit_history_message_search` - Full-text search in messages
6. `test_commit_history_pagination` - Offset and limit work correctly
7. `test_commit_history_change_counts` - Added/deleted/modified counts accurate
8. `test_commit_history_merge_detection` - Merge commits identified correctly
9. `test_commit_history_ancestry_depth` - Depth calculated correctly
10. `test_commit_history_combined_filters` - Multiple filters applied correctly

---

### Function 2: pggit.get_audit_trail()

**Purpose**: View complete immutable audit trail of all object changes with before/after comparisons.

**Signature**:
```sql
CREATE OR REPLACE FUNCTION pggit.get_audit_trail(
    p_object_type TEXT DEFAULT NULL,
    p_schema_name TEXT DEFAULT NULL,
    p_object_name TEXT DEFAULT NULL,
    p_branch_name TEXT DEFAULT NULL,
    p_change_type TEXT DEFAULT NULL,
    p_since_timestamp TIMESTAMP DEFAULT NULL,
    p_until_timestamp TIMESTAMP DEFAULT NULL,
    p_limit INTEGER DEFAULT 100,
    p_offset INTEGER DEFAULT 0
) RETURNS TABLE (
    history_id BIGINT,
    object_type TEXT,
    schema_name TEXT,
    object_name TEXT,
    full_name TEXT,
    branch_name TEXT,
    change_type TEXT,
    change_severity TEXT,
    before_hash CHAR(64),
    after_hash CHAR(64),
    before_definition TEXT,
    after_definition TEXT,
    definition_diff_summary TEXT,
    commit_hash CHAR(64),
    commit_message TEXT,
    author_name TEXT,
    changed_at TIMESTAMP,
    change_reason TEXT,
    is_breaking_change BOOLEAN
);
```

**Parameters**:
- `p_object_type` - Filter by type: TABLE, VIEW, FUNCTION, etc. (NULL = all)
- `p_schema_name` - Filter by schema (case-insensitive LIKE, NULL = all)
- `p_object_name` - Filter by object name (case-insensitive LIKE, NULL = all)
- `p_branch_name` - Filter by branch (NULL = all branches)
- `p_change_type` - Filter by change: CREATE, ALTER, DROP (NULL = all)
- `p_since_timestamp` - Changes after this time (NULL = all)
- `p_until_timestamp` - Changes before this time (NULL = all)
- `p_limit` - Max results (default 100, max 1000)
- `p_offset` - Pagination offset (default 0)

**Returns**:
- `history_id` - Unique history record ID
- `object_type` - Type of object (TABLE, FUNCTION, etc.)
- `schema_name` - Schema containing object
- `object_name` - Object name
- `full_name` - Fully qualified name (schema.object)
- `branch_name` - Which branch this change occurred on
- `change_type` - Type of change (CREATE, ALTER, DROP)
- `change_severity` - Severity of change (BREAKING, MAJOR, MINOR, PATCH)
- `before_hash` - Content hash before change
- `after_hash` - Content hash after change
- `before_definition` - SQL definition before change
- `after_definition` - SQL definition after change
- `definition_diff_summary` - Human-readable diff summary
- `commit_hash` - Associated commit
- `commit_message` - Commit message explaining change
- `author_name` - User who made the change
- `changed_at` - When the change occurred
- `change_reason` - Reason for change (from object_history.change_reason)
- `is_breaking_change` - Whether this breaks dependent objects

**Algorithm**:

```
1. VALIDATE INPUTS:
   - Check change_type IN ('CREATE', 'ALTER', 'DROP') if specified
   - Validate object_type is valid (check pggit.schema_objects constraints)
   - Validate p_limit <= 1000

2. QUERY OBJECT HISTORY:
   - SELECT from pggit.object_history oh
   - JOIN pggit.schema_objects so ON oh.object_id = so.object_id
   - JOIN pggit.commits c ON oh.commit_hash = c.commit_hash
   - JOIN pggit.branches b ON oh.branch_id = b.branch_id

3. APPLY FILTERS:
   - IF p_object_type: WHERE so.object_type = p_object_type
   - IF p_schema_name: WHERE so.schema_name ILIKE p_schema_name
   - IF p_object_name: WHERE so.object_name ILIKE p_object_name
   - IF p_branch_name: WHERE b.branch_name = p_branch_name
   - IF p_change_type: WHERE oh.change_type = p_change_type
   - IF p_since_timestamp: WHERE oh.created_at >= p_since_timestamp
   - IF p_until_timestamp: WHERE oh.created_at <= p_until_timestamp

4. CALCULATE DIFF SUMMARY:
   - Compare before_definition vs after_definition
   - Detect:
     * Added columns
     * Removed columns
     * Changed column types
     * Added/removed constraints
     * Function signature changes
   - Create human-readable summary

5. DETECT BREAKING CHANGES:
   - Query pggit.object_dependencies
   - If object is DROPPED and has dependents: is_breaking_change = true
   - If column removed from TABLE and referenced by FK: is_breaking_change = true
   - If function signature changed and called by triggers: is_breaking_change = true

6. ENRICH WITH COMMIT INFO:
   - SELECT author_name, commit_message from commits
   - Format change_reason for clarity

7. ORDER & PAGINATE:
   - ORDER BY oh.created_at DESC (newest first)
   - OFFSET p_offset LIMIT p_limit

8. RETURN RESULTS
```

**Performance Considerations**:
- Index on: object_history.object_id, object_history.created_at
- Index on: object_history.change_type, object_history.branch_id
- Diff summary generation may be slow for large objects - cache if possible
- Consider materialized views for frequently accessed audit trails

**Test Cases** (10 tests):
1. `test_audit_trail_all_changes` - Returns all changes unfiltered
2. `test_audit_trail_object_filter` - Filter by object type/schema/name
3. `test_audit_trail_branch_filter` - Filter by branch
4. `test_audit_trail_change_type_filter` - Filter by CREATE/ALTER/DROP
5. `test_audit_trail_time_range` - Filter by timestamp range
6. `test_audit_trail_before_after_comparison` - Before/after definitions correct
7. `test_audit_trail_diff_summary` - Diff summary is accurate
8. `test_audit_trail_breaking_changes_detected` - Breaking changes flagged
9. `test_audit_trail_pagination` - Offset/limit work correctly
10. `test_audit_trail_combined_filters` - Multiple filters applied together

---

### Function 3: pggit.get_object_timeline()

**Purpose**: View the complete evolution of a specific object across all its versions on a branch.

**Signature**:
```sql
CREATE OR REPLACE FUNCTION pggit.get_object_timeline(
    p_object_name TEXT,
    p_branch_name TEXT DEFAULT NULL,
    p_include_merged_history BOOLEAN DEFAULT FALSE,
    p_limit INTEGER DEFAULT 100
) RETURNS TABLE (
    timeline_version INTEGER,
    change_type TEXT,
    change_severity TEXT,
    version_major INT,
    version_minor INT,
    version_patch INT,
    current_definition TEXT,
    previous_definition TEXT,
    objects_hash CHAR(64),
    commit_hash CHAR(64),
    commit_message TEXT,
    author_name TEXT,
    changed_at TIMESTAMP,
    time_since_last_change INTERVAL,
    object_status TEXT,
    merge_source_branch TEXT
) ORDER BY timeline_version ASC;
```

**Parameters**:
- `p_object_name` - Object to trace (required, can be schema.object format)
- `p_branch_name` - Branch to trace on (NULL = current session branch, default = main)
- `p_include_merged_history` - Include history from merge source branches
- `p_limit` - Max versions to return (default 100)

**Returns**:
- `timeline_version` - Sequence number in object's timeline (1 = first, incrementing)
- `change_type` - Type of change (CREATE, ALTER, DROP)
- `change_severity` - Severity (BREAKING, MAJOR, MINOR, PATCH)
- `version_major/minor/patch` - Object version numbers
- `current_definition` - Definition at this point in time
- `previous_definition` - Definition before this change
- `objects_hash` - Hash of definition at this point
- `commit_hash` - Commit where this change occurred
- `commit_message` - Commit message
- `author_name` - User who made change
- `changed_at` - Timestamp of change
- `time_since_last_change` - Duration between this and previous change
- `object_status` - Current status (ACTIVE, DELETED, etc.)
- `merge_source_branch` - If from a merge, which branch it came from

**Algorithm**:

```
1. VALIDATE INPUTS:
   - Parse p_object_name (handle both "table" and "schema.table" formats)
   - Verify object exists in pggit.schema_objects
   - Find branch_id for p_branch_name

2. GET OBJECT ID:
   - SELECT object_id FROM pggit.schema_objects
   - WHERE (schema_name, object_name) matches parsed input
   - Raise error if not found

3. BUILD TIMELINE:
   - Start with CREATE change (first history record)
   - Query object_history for this object_id
   - Order by created_at ASC (oldest first)
   - Number rows as timeline_version

4. ENRICH WITH COMMIT DATA:
   - JOIN with pggit.commits for commit_message, author_name
   - JOIN with pggit.branches for branch_name

5. DETECT MERGE HISTORY (if p_include_merged_history):
   - Look for merge_operations records affecting this branch
   - Trace back to source branch
   - Include history from source branch before merge
   - Mark with merge_source_branch

6. CALCULATE TIME DELTAS:
   - LAG(changed_at) OVER (ORDER BY timeline_version)
   - time_since_last_change = changed_at - previous_changed_at

7. DETERMINE OBJECT STATUS:
   - If last change is DROP: status = 'DELETED'
   - If exists in schema_objects: status = 'ACTIVE'
   - If DROP then recreated: status = 'RECREATED'

8. ORDER BY TIMELINE:
   - ROWS 1..limit by timeline_version ASC

9. RETURN RESULTS
```

**Performance Considerations**:
- Index on: object_history.object_id, object_history.created_at
- Timeline for single object typically small (< 100 versions)
- Merge history trace may be expensive - consider caching
- Materialized view for frequently accessed timelines

**Test Cases** (10 tests):
1. `test_object_timeline_single_object` - Complete timeline for one object
2. `test_object_timeline_version_numbers` - Version numbers increment correctly
3. `test_object_timeline_multiple_changes` - Several ALTER operations shown
4. `test_object_timeline_deleted_object` - Timeline shows DROP and status
5. `test_object_timeline_recreated_object` - Object deleted then recreated
6. `test_object_timeline_time_deltas` - Time between changes calculated
7. `test_object_timeline_merge_history` - History from merged branches included
8. `test_object_timeline_branch_specific` - Timeline respects branch context
9. `test_object_timeline_pagination` - Limit works correctly
10. `test_object_timeline_nonexistent_object` - Error for object not found

---

### Function 4: pggit.query_at_timestamp()

**Purpose**: Time-travel query - reconstruct complete schema state at any point in history.

**Signature**:
```sql
CREATE OR REPLACE FUNCTION pggit.query_at_timestamp(
    p_branch_name TEXT,
    p_target_timestamp TIMESTAMP,
    p_object_type TEXT DEFAULT NULL,
    p_schema_filter TEXT DEFAULT NULL,
    p_order_by TEXT DEFAULT 'object_name ASC'
) RETURNS TABLE (
    object_id BIGINT,
    object_type TEXT,
    schema_name TEXT,
    object_name TEXT,
    full_name TEXT,
    definition TEXT,
    content_hash CHAR(64),
    version_major INT,
    version_minor INT,
    version_patch INT,
    was_active BOOLEAN,
    created_at TIMESTAMP,
    last_modified_at TIMESTAMP,
    last_modified_by TEXT,
    time_to_current INTERVAL
) ORDER BY object_type, object_name ASC;
```

**Parameters**:
- `p_branch_name` - Which branch's history to query (required)
- `p_target_timestamp` - Point in time to reconstruct (required)
- `p_object_type` - Filter results by type (NULL = all)
- `p_schema_filter` - Filter by schema name (NULL = all)
- `p_order_by` - Sort order (default 'object_name ASC')

**Returns**:
- `object_id` - Object identifier
- `object_type` - Type of object
- `schema_name` - Schema name
- `object_name` - Object name
- `full_name` - Fully qualified name
- `definition` - Definition at that point in time
- `content_hash` - Hash of definition
- `version_major/minor/patch` - Version at that time
- `was_active` - Whether object was active at that timestamp
- `created_at` - When object was created
- `last_modified_at` - Last modification before that timestamp
- `last_modified_by` - User who last modified it
- `time_to_current` - How long ago from current time

**Algorithm**:

```
1. VALIDATE INPUTS:
   - Verify branch exists and p_branch_name is valid
   - Verify p_target_timestamp is in the past (< NOW())
   - Verify branch existed at p_target_timestamp
     * SELECT created_at FROM pggit.branches WHERE branch_name = p_branch_name
     * If p_target_timestamp < branch.created_at: error "Branch didn't exist yet"

2. BUILD SCHEMA STATE AT TIMESTAMP:
   - For each object_id in pggit.schema_objects:
     a) Query object_history WHERE object_id = current
     b) Find most recent change <= p_target_timestamp
     c) That change defines object state at that time

3. RECONSTRUCT OBJECTS:
   FOR EACH object IN schema_objects:
     v_last_history := (
       SELECT TOP 1 * FROM pggit.object_history oh
       WHERE oh.object_id = object.object_id
         AND oh.branch_id = (SELECT branch_id FROM pggit.branches WHERE branch_name = p_branch_name)
         AND oh.created_at <= p_target_timestamp
       ORDER BY oh.created_at DESC
     )

     IF v_last_history IS NULL:
       -- Object didn't exist at that time
       SKIP (was_active = FALSE)
     ELSE:
       -- Check if object was deleted by that timestamp
       IF v_last_history.change_type = 'DROP':
         was_active = FALSE
       ELSE:
         was_active = TRUE
         definition = v_last_history.after_definition

4. HANDLE DELETED OBJECTS:
   - Find objects that were created AND deleted before p_target_timestamp
   - These should NOT appear in results (was_active = FALSE)
   - But track them for completeness

5. HANDLE BRANCH HISTORY:
   - If p_branch_name is not 'main':
     a) Get parent_branch_id
     b) For objects not found on this branch:
        Query parent branch at same timestamp
        (Object inherited from parent)
     c) Mark if inherited from parent

6. APPLY FILTERS:
   - IF p_object_type: WHERE object_type = p_object_type
   - IF p_schema_filter: WHERE schema_name ILIKE p_schema_filter
   - Filter to only was_active = TRUE objects

7. CALCULATE TIME DELTA:
   - time_to_current = NOW() - p_target_timestamp

8. ORDER & RETURN:
   - ORDER BY p_order_by
   - RETURN reconstructed schema state

9. ERROR CASES:
   - If p_target_timestamp < branch creation time: error
   - If p_target_timestamp is in future: error
   - If branch has been deleted: can still query (historical)
```

**Performance Considerations**:
- Very expensive query - scans entire object_history table
- Index on: object_history.object_id, object_history.created_at, object_history.branch_id
- Consider caching results for frequently queried timestamps
- May want to limit to recent history (last N days/months)
- For very old timestamps, performance will degrade

**Test Cases** (10 tests):
1. `test_query_at_timestamp_current_time` - Query at NOW() returns current state
2. `test_query_at_timestamp_past_time` - Query at historical time shows old definitions
3. `test_query_at_timestamp_object_creation` - Query right after object created
4. `test_query_at_timestamp_object_deletion` - Query after object deleted (not included)
5. `test_query_at_timestamp_before_object_exists` - Object not present before creation
6. `test_query_at_timestamp_branch_inheritance` - Parent branch objects inherited
7. `test_query_at_timestamp_multiple_modifications` - Multiple changes to same object
8. `test_query_at_timestamp_filtered_results` - Filters applied correctly
9. `test_query_at_timestamp_branch_too_young` - Error if timestamp before branch creation
10. `test_query_at_timestamp_merged_branch` - Query after merge includes both branches

---

## Implementation Strategy

### Phase 5.1: Foundation (Days 1-1.5)
- Implement `get_commit_history()` function
- Create 10 unit tests
- Verify pagination and filtering work
- Optimize indexes if needed

### Phase 5.2: Audit Trail (Day 2)
- Implement `get_audit_trail()` function
- Create 10 unit tests
- Implement diff calculation logic
- Detect breaking changes

### Phase 5.3: Timeline (Day 2-2.5)
- Implement `get_object_timeline()` function
- Create 10 unit tests
- Handle merge history tracking
- Calculate version increments

### Phase 5.4: Time-Travel (Day 3-3.5)
- Implement `query_at_timestamp()` function (most complex)
- Create 10 unit tests
- Optimize for performance
- Handle edge cases (deleted branches, etc.)

### Phase 5.5: Testing & QA (Days 4-5)
- Run full test suite (40+ tests)
- Regression test Phases 1-4
- Performance validation
- Documentation review

### Phase 5.6: Final Commit (Day 5)
- Final commit with [GREEN] tag
- Update README with Phase 5 info

---

## Test Fixture Strategy

### Fixture Data Structure

Create a test fixture with rich history:

```
Main Branch (created T0):
  T1: CREATE TABLE users
  T2: ALTER TABLE users ADD COLUMN email (SOURCE_MODIFIED)
  T3: CREATE FUNCTION count_users()
  T4: ALTER FUNCTION count_users() MODIFY BODY

Feature-A Branch (created at T1, parent=main):
  T2: ALTER TABLE users ADD COLUMN phone (BOTH_MODIFIED conflict)
  T3: CREATE INDEX idx_users_email

Feature-B Branch (created at T2, parent=main):
  T3: ALTER TABLE users CHANGE email to email_address
  T4: ALTER FUNCTION count_users() DIFFERENT BODY

Merge events:
  T5: Merge feature-a -> main (UNION strategy)
  T6: Merge feature-b -> main (MANUAL_REVIEW strategy)

Timeline state at different points:
  T0: Empty (branch just created)
  T1: 1 table
  T2: 1 table + function (or 2 versions on different branches)
  T3: 2 tables + function + index
  T4: Multiple versions of function
  T5-6: Merge state
```

### Fixture Helper Methods

```python
class Phase5Fixture:
    def create_historical_commit(timestamp, branch, changes)
    def add_object_history_record(object_id, change_type, before/after)
    def create_merge_event(source, target, strategy, timestamp)
    def query_at_timestamp(branch, timestamp)
    def assert_timeline_length(object_name, expected_count)
    def assert_commit_count(branch, expected_count)
```

---

## Known Challenges & Solutions

| Challenge | Solution |
|-----------|----------|
| **Query Performance** | Proper indexing on object_history (object_id, created_at), commits (branch_id, author_time) |
| **Time-Travel Complexity** | Break into steps: 1) Find last change <= timestamp, 2) Reconstruct state, 3) Handle deleted objects |
| **Merge History Tracking** | Use merge_operations table to trace source branches, recursive CTEs for ancestry |
| **Breaking Change Detection** | Query object_dependencies for cascading failures |
| **Pagination with Filtering** | Use window functions (ROW_NUMBER) for proper pagination |
| **Large Audit Trails** | Implement reasonable defaults (LIMIT 100), allow streaming for big datasets |
| **Timestamp Precision** | Use TIMESTAMP WITH TIMEZONE, be careful with clock skew |
| **Deleted Branch Queries** | Can still query historical state of deleted branches |

---

## Expected Outcomes

### Code Deliverables
- `sql/033_pggit_history_audit.sql` (~800-1000 lines)
  - 4 core functions (~200 lines each)
  - Supporting helper functions
  - Performance indexes

- `tests/unit/test_phase5_history_audit.py` (~1200-1500 lines)
  - 40 comprehensive test cases (10 per function)
  - Phase5HistoryFixture class
  - Edge case coverage

### Documentation
- PHASE_5_PLAN.md - This plan (for reference)
- PHASE_5_QUICK_REFERENCE.md - Function signatures and usage
- PHASE_5_STEP_0_FIXTURES.md - Fixture architecture and algorithms
- Implementation guides and examples

### Quality Metrics
- ✅ 100% test pass rate (40+ tests)
- ✅ All functions compile without errors
- ✅ Performance queries < 5 seconds for typical use
- ✅ No regression in Phases 1-4
- ✅ Comprehensive documentation
- ✅ Production-ready code

---

## Success Criteria

Before Phase 5 is considered complete:

### Code Implementation
- [ ] All 4 functions implemented with exact API spec
- [ ] SQL compiles without errors
- [ ] Proper parameter validation in all functions
- [ ] Clear error messages for invalid inputs
- [ ] Consistent naming (p_ for params, v_ for vars)

### Conflict Classification
- [ ] Breaking changes detected correctly
- [ ] Change severity calculated properly
- [ ] Change reasons tracked and displayed
- [ ] Audit trail is immutable and complete

### Historical Queries
- [ ] Commit history queryable with multiple filters
- [ ] Audit trail shows before/after definitions
- [ ] Object timeline shows complete evolution
- [ ] Time-travel reconstruction accurate

### Test Coverage
- [ ] 40+ unit tests passing (100%)
- [ ] All conflict types tested
- [ ] All filter combinations tested
- [ ] Edge cases covered (deleted objects, merges, etc.)
- [ ] Performance acceptable for large datasets

### Integration
- [ ] Phase 1-4 not regressed
- [ ] Works with merge_operations data
- [ ] Branch history tracking accurate
- [ ] Timestamp handling correct

### Code Quality
- [ ] No SQL injection vulnerabilities
- [ ] Proper NULL handling
- [ ] Clear inline comments
- [ ] Parameter documentation
- [ ] Return value documentation

### Documentation
- [ ] Function signatures documented
- [ ] Algorithm explanations included
- [ ] Usage examples provided
- [ ] Performance notes included

---

## Risk Assessment

### Risk Level: **MEDIUM-HIGH** ⚠️

**Risks**:
1. ✅ **Time-Travel Complexity** - Most complex function in Phase 5
   - Mitigation: Break into steps, test thoroughly

2. ✅ **Performance Degradation** - Large audit trails may cause slowness
   - Mitigation: Proper indexing, pagination, caching strategies

3. ✅ **Timestamp Precision Issues** - Clock skew or timezone problems
   - Mitigation: Use TIMESTAMP WITH TIMEZONE, test edge cases

4. ✅ **Merge History Tracing** - Complex to track history across merges
   - Mitigation: Use merge_operations table, recursive CTEs

5. ✅ **Data Consistency** - Audit trail must be immutable
   - Mitigation: Only INSERT to object_history, never UPDATE/DELETE

**Mitigations**:
- Comprehensive test fixture with complex history
- Performance testing with large datasets
- Timezone edge case testing
- Immutability validation
- Clear error handling

---

## References & Resources

### Related Documentation
- PHASE_1_SCHEMA.md - table definitions (object_history, commits)
- PHASE_2_PLAN.md - branch management (branches table)
- PHASE_4_PLAN.md - merge operations (merge_operations table)

### Key Tables
- `pggit.object_history` - Append-only change log
- `pggit.commits` - Commit metadata
- `pggit.branches` - Branch hierarchy
- `pggit.schema_objects` - Current state
- `pggit.merge_operations` - Merge audit trail (Phase 4)

### Index Strategy
```sql
-- Performance critical indexes
CREATE INDEX idx_object_history_object_created ON pggit.object_history(object_id, created_at);
CREATE INDEX idx_object_history_branch_created ON pggit.object_history(branch_id, created_at);
CREATE INDEX idx_commits_branch_time ON pggit.commits(branch_id, author_time DESC);
CREATE INDEX idx_commits_author ON pggit.commits(author_name, author_time DESC);
```

---

## Next Steps

1. ✅ **Review this plan** - Validate approach with stakeholders
2. ⏭️ **Create PHASE_5_STEP_0_FIXTURES.md** - Detailed fixture architecture
3. ⏭️ **Create PHASE_5_QUICK_REFERENCE.md** - Function signatures reference
4. ⏭️ **Begin implementation** - Start with get_commit_history()
5. ⏭️ **Iterative testing** - Test after each function
6. ⏭️ **Performance tuning** - Optimize queries
7. ⏭️ **Final QA** - Regression testing and commit

---

## Timeline Summary

| Phase | Duration | Tasks |
|-------|----------|-------|
| 5.1 | 1-1.5 days | get_commit_history() + 10 tests |
| 5.2 | 1 day | get_audit_trail() + 10 tests |
| 5.3 | 1-1.5 days | get_object_timeline() + 10 tests |
| 5.4 | 1-1.5 days | query_at_timestamp() + 10 tests |
| 5.5 | 1-2 days | Testing, QA, optimization |
| 5.6 | 0.5 day | Final commit [GREEN] |
| **Total** | **5-7 days** | **All components** |

---

**Status**: Planning Complete - Ready for Implementation

**Created**: 2025-12-26
**Confidence Level**: ⭐⭐⭐⭐ (4/5 stars)
**Next Action**: Review plan, then proceed to implementation
