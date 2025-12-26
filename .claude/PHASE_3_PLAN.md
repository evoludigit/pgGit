# Phase 3: Object Tracking & Visibility Implementation Plan

**Status**: Ready for Implementation
**Phase**: 3 of 7
**Target Completion**: After Phase 2 (all 4 functions complete ✅)
**Effort Estimate**: 2-3 days with proper implementation
**Goal**: Enable querying schema objects from specific branches with change tracking

---

## Executive Summary

Phase 3 implements the **Object Tracking & Visibility API** - three essential functions that allow users to see what schema objects exist on each branch, track changes between branches, and understand the schema composition of any branch in the system.

### Success Criteria
- [ ] All 3 functions implemented with exact API spec signatures
- [ ] 25-30 comprehensive unit tests (8-10 per function)
- [ ] 100% test pass rate
- [ ] All edge cases and error conditions covered
- [ ] Clear, descriptive git commits with [GREEN] tag

---

## Architecture Overview

### Design Principles

1. **Current Branch Awareness**: Functions use session variable from Phase 2 to determine context
2. **Lazy Evaluation**: Change calculations done on-the-fly, not pre-computed
3. **Branch Isolation**: Objects queried via object_history table filtered by branch_id
4. **Change Tracking**: All modifications tracked with timestamps and users
5. **Performance**: Indexes on branch_id, object_type for fast queries

### Dependencies on Phase 1 & 2

Phase 3 relies on:
- **Phase 1**: pggit.schema_objects table with object metadata
- **Phase 1**: pggit.object_history table for change audit trail
- **Phase 1**: pggit.branches table with branch metadata
- **Phase 2**: pggit.list_branches() to get branch metadata
- **Phase 2**: pggit.checkout_branch() to set current branch context
- **Phase 2**: Session variable `pggit.current_branch` for current branch

### Key Schema Differences (v0.0.1 vs v0.1.1)

| Aspect | v0.1.1 | v0.0.1 | Adaptation |
|--------|--------|--------|-----------|
| **Objects Table** | `pggit.objects` with `branch_id` | `pggit.schema_objects` - **NO branch_id** | Track via object_history.branch_id |
| **History Tracking** | `pggit.history` | `pggit.object_history` | Same structure, use as-is |
| **Branch Reference** | Use `branch_id` FK | Filter history by branch_id | Query object_history first |
| **Object Identity** | id, branch_id, name | object_id, object_type, schema, name | Use UNIQUE (type, schema, name) |

**Critical Insight**: v0.0.1 doesn't track objects per-branch at table level. Instead:
- `schema_objects` has global metadata (definition, hash, version)
- `object_history` tracks changes per-branch via `branch_id` and `author_time`
- Querying "objects on branch X" = get latest state from history filtered by branch_id

---

## Phase 3.1: pggit.get_branch_objects()

### Specification

```sql
CREATE OR REPLACE FUNCTION pggit.get_branch_objects(
    p_branch_name TEXT DEFAULT NULL,
    p_object_type TEXT DEFAULT NULL,
    p_schema_filter TEXT DEFAULT NULL,
    p_order_by TEXT DEFAULT 'object_name ASC'
) RETURNS TABLE (
    object_id BIGINT,
    object_type TEXT,
    schema_name TEXT,
    object_name TEXT,
    full_name TEXT,
    version_major INTEGER,
    version_minor INTEGER,
    version_patch INTEGER,
    content_hash CHAR(64),
    is_active BOOLEAN,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    created_by TEXT
)
```

### Detailed Implementation Steps

**Step 1: Determine Target Branch**
- If `p_branch_name IS NULL`, use current session branch from `current_setting('pggit.current_branch')`
- Default to 'main' if session variable not set
- Query pggit.branches to get branch_id and validate branch exists
- Return empty set if branch not found (no exception)

**Step 2: Get Latest Objects Per Branch**
- Query pggit.object_history for all CREATE/ALTER entries on target branch
- For each object, get the LATEST (MAX author_time) entry per object_id
- Join with pggit.schema_objects to get current definition and metadata
- Filter WHERE is_active = true

**Step 3: Apply Type Filter**
- If `p_object_type IS NOT NULL`:
  - WHERE object_type = p_object_type
- Otherwise: include all types

**Step 4: Apply Schema Filter**
- If `p_schema_filter IS NOT NULL`:
  - WHERE schema_name ILIKE p_schema_filter (case-insensitive)
- Otherwise: include all schemas

**Step 5: Apply Ordering**
- Support: 'object_name ASC|DESC', 'object_type ASC|DESC', 'schema_name ASC|DESC', 'created_at ASC|DESC'
- Default: 'object_name ASC'
- Validate p_order_by to prevent SQL injection

**Step 6: Return Results**
- RETURN QUERY with all requested fields
- Include version info for tracking schema evolution

### Implementation Approach

```sql
-- Get latest history entry per object on branch
WITH latest_history AS (
    SELECT
        oh.object_id,
        oh.branch_id,
        oh.author_name,
        oh.author_time,
        ROW_NUMBER() OVER (PARTITION BY oh.object_id ORDER BY oh.author_time DESC) as rn
    FROM pggit.object_history oh
    WHERE oh.branch_id = v_branch_id
)
SELECT
    so.object_id,
    so.object_type,
    so.schema_name,
    so.object_name,
    so.schema_name || '.' || so.object_name as full_name,
    so.version_major,
    so.version_minor,
    so.version_patch,
    so.content_hash,
    so.is_active,
    so.created_at,
    so.last_modified_at as updated_at,
    lh.author_name as created_by
FROM pggit.schema_objects so
JOIN latest_history lh ON so.object_id = lh.object_id AND lh.rn = 1
WHERE so.is_active = true
  AND (p_object_type IS NULL OR so.object_type = p_object_type)
  AND (p_schema_filter IS NULL OR so.schema_name ILIKE p_schema_filter)
ORDER BY [dynamic]
```

### Test Cases (10 tests)

1. **Happy path**: Get all objects from main
2. **Current branch context**: NULL branch uses session
3. **Filter by type**: Get only tables
4. **Filter by schema**: Get public schema only
5. **Multiple filters**: Type AND schema
6. **Order by object_name**: Alphabetical
7. **Order by type**: Group by type
8. **Non-existent branch**: Empty result
9. **Deleted branch**: Can still query
10. **Object versioning**: Track schema versions

---

## Phase 3.2: pggit.get_object_history()

### Specification

```sql
CREATE OR REPLACE FUNCTION pggit.get_object_history(
    p_object_name TEXT,
    p_branch_name TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 100
) RETURNS TABLE (
    history_id BIGINT,
    object_type TEXT,
    change_type TEXT,
    change_severity TEXT,
    before_hash CHAR(64),
    after_hash CHAR(64),
    changed_by TEXT,
    changed_at TIMESTAMP,
    description TEXT
)
```

### Detailed Implementation Steps

**Step 1: Validate Input**
- Check `p_object_name` is not NULL or empty
- Handle both 'schema.object' and 'object' formats

**Step 2: Determine Target Branch**
- If `p_branch_name IS NULL`, use current session branch
- Default to 'main' if not set

**Step 3: Find Object ID**
- Query pggit.schema_objects by name
- Handle schema-qualified names (split on '.' if present)
- If not found, return empty result (no exception)

**Step 4: Query History**
- SELECT from pggit.object_history where object_id = found_id AND branch_id = target_branch_id
- ORDER BY author_time DESC (most recent first)
- LIMIT to p_limit

**Step 5: Build Result Set**
- Include change_type, change_severity, before/after hashes
- Add description field (change_type + object_name)

**Step 6: Return Results**
- RETURN QUERY with complete change history

### Implementation Approach

```sql
-- Find object by name
v_object_id := (
    SELECT object_id FROM pggit.schema_objects
    WHERE object_name = v_obj_name
      AND (schema_name = v_schema OR (v_schema = '' AND schema_name = ''))
    LIMIT 1
);

-- Return history in reverse chronological order
SELECT
    history_id,
    object_type,
    change_type,
    change_severity,
    before_hash,
    after_hash,
    author_name as changed_by,
    author_time as changed_at,
    change_type || ' on ' || p_object_name as description
FROM pggit.object_history
WHERE object_id = v_object_id AND branch_id = v_branch_id
ORDER BY author_time DESC
LIMIT p_limit
```

### Test Cases (8 tests)

1. **Happy path**: Get history for table
2. **Empty history**: New object
3. **Multiple changes**: Track ALTER sequence
4. **Non-existent object**: Empty result
5. **Current branch context**: NULL uses session
6. **Limit results**: Pagination
7. **Schema-qualified names**: Full path
8. **Change tracking**: Severity and user

---

## Phase 3.3: pggit.diff_branches()

### Specification

```sql
CREATE OR REPLACE FUNCTION pggit.diff_branches(
    p_source_branch TEXT,
    p_target_branch TEXT DEFAULT NULL
) RETURNS TABLE (
    object_type TEXT,
    schema_name TEXT,
    object_name TEXT,
    full_name TEXT,
    change_type TEXT,
    source_version INTEGER,
    target_version INTEGER,
    source_hash CHAR(64),
    target_hash CHAR(64),
    is_conflict BOOLEAN,
    description TEXT
)
```

### Detailed Implementation Steps

**Step 1: Validate Inputs**
- Check `p_source_branch` is not NULL or empty
- If `p_target_branch IS NULL`, use current session branch

**Step 2: Get Both Branch IDs**
- Query pggit.branches for both branch_ids
- Validate both exist (can be any status)
- Allow querying deleted branches (historical analysis)

**Step 3: Get Latest Object State Per Branch**
- Build CTE for source branch: latest object_history entries by object
- Build CTE for target branch: latest object_history entries by object
- Join schema_objects for metadata

**Step 4: Classify Differences**
- **ADDED**: In target but not in source
- **REMOVED**: In source but not in target
- **MODIFIED**: In both but different hash
- **UNCHANGED**: In both with same hash
- **CONFLICT**: In both, different hash, diverged

**Step 5: Filter Results**
- Exclude UNCHANGED objects
- Show CONFLICTS prominently
- Include metadata for merge planning

**Step 6: Return Results**
- RETURN QUERY with diff information
- Sorted by schema_name, object_name

### Implementation Approach

```sql
-- Get latest state per branch
WITH source_objects AS (
    SELECT so.object_id, so.object_type, so.schema_name, so.object_name,
           so.version_major, so.content_hash
    FROM pggit.schema_objects so
    WHERE EXISTS (
        SELECT 1 FROM pggit.object_history oh
        WHERE oh.object_id = so.object_id
          AND oh.branch_id = v_source_branch_id
    )
),
target_objects AS (
    SELECT so.object_id, so.object_type, so.schema_name, so.object_name,
           so.version_major, so.content_hash
    FROM pggit.schema_objects so
    WHERE EXISTS (
        SELECT 1 FROM pggit.object_history oh
        WHERE oh.object_id = so.object_id
          AND oh.branch_id = v_target_branch_id
    )
)
SELECT
    COALESCE(s.object_type, t.object_type) as object_type,
    COALESCE(s.schema_name, t.schema_name) as schema_name,
    COALESCE(s.object_name, t.object_name) as object_name,
    COALESCE(s.schema_name, t.schema_name) || '.' || COALESCE(s.object_name, t.object_name),
    CASE
        WHEN s.object_id IS NULL THEN 'ADDED'
        WHEN t.object_id IS NULL THEN 'REMOVED'
        WHEN s.content_hash = t.content_hash THEN 'UNCHANGED'
        WHEN s.content_hash != t.content_hash THEN CASE
            WHEN EXISTS (...) THEN 'CONFLICT'
            ELSE 'MODIFIED'
        END
    END as change_type,
    ...
FROM source_objects s
FULL OUTER JOIN target_objects t ON s.object_id = t.object_id
WHERE change_type != 'UNCHANGED'
ORDER BY schema_name, object_name
```

### Test Cases (10 tests)

1. **Happy path**: Compare two branches
2. **No changes**: Identical branches
3. **New objects**: Only in target
4. **Deleted objects**: Only in source
5. **Modified objects**: Different versions
6. **Conflicts**: Diverged changes
7. **Current branch context**: NULL uses session
8. **Non-existent branch**: Exception
9. **Same branch**: Self-diff (empty)
10. **Historical analysis**: Deleted branches

---

## File Structure

### SQL Implementation File

**Location**: `sql/031_pggit_object_tracking.sql`

**Contents**:
1. Comment header with license info
2. Phase 3.1: get_branch_objects() - ~120 lines
3. Phase 3.2: get_object_history() - ~80 lines
4. Phase 3.3: diff_branches() - ~150 lines
5. **Total**: ~350-400 lines SQL

### Test Implementation File

**Location**: `tests/unit/test_phase3_object_tracking.py`

**Contents**:
- Import statements
- Database setup fixtures
- TestGetBranchObjects (10 tests)
- TestGetObjectHistory (8 tests)
- TestDiffBranches (10 tests)
- **Total**: ~500-600 lines Python

---

## Implementation Strategy

### Key Decisions

1. **No Objects-Per-Branch Table**
   - v0.0.1 doesn't have `objects` table with `branch_id`
   - Solution: Query `object_history` to get branch-specific view
   - Trade-off: Slightly slower query (one more JOIN) but much simpler

2. **History-Driven Design**
   - Object state on branch = latest history entry for that branch
   - Enables time-travel queries naturally
   - Handles deleted/modified objects cleanly

3. **Graceful Degradation**
   - Non-existent branches return empty (no exception)
   - Non-existent objects return empty (no exception)
   - Allows safe exploratory queries

4. **Version Tracking**
   - Use version_major/minor/patch from schema_objects
   - Allows semantic versioning in queries
   - Enables changelog generation

### Execution Plan

**Step 1: Create Skeleton** (30 min)
- Create `sql/031_pggit_object_tracking.sql` with function signatures
- Create `tests/unit/test_phase3_object_tracking.py` with test classes

**Step 2: Implement Functions** (4-6 hours)
- get_branch_objects() - 2 hours (query builder + filter logic)
- get_object_history() - 1.5 hours (simple history query)
- diff_branches() - 2.5 hours (complex FULL OUTER JOIN + classification)

**Step 3: Write & Run Tests** (3-4 hours)
- Write all 28 unit tests
- Fix any failing tests
- Achieve 100% pass rate

**Step 4: Documentation & Commit** (30 min)
- Add docstrings to all functions
- Commit with [GREEN] tag
- Create implementation summary

---

## Success Criteria Checklist

### Code Quality
- [ ] All 3 functions implemented exactly to spec
- [ ] No hardcoded values except defaults
- [ ] Clear variable naming (p_ for params, v_ for variables)
- [ ] Comments explaining non-obvious logic
- [ ] Consistent with Phase 1-2 patterns

### Testing
- [ ] 28 unit tests written
- [ ] All tests passing (100% success)
- [ ] Edge cases covered
- [ ] Happy paths tested
- [ ] Error conditions tested

### Git Workflow
- [ ] Commits are small and logical
- [ ] Commit messages follow pattern: `feat(phase3): Description [GREEN]`
- [ ] Ready for code review

### Documentation
- [ ] Docstrings in all SQL functions
- [ ] Test names describe what they test
- [ ] Phase 3 implementation summary written

---

## Risk Mitigation

### Known Risks

1. **Object Identity Without Per-Branch Table**
   - Mitigation: Use object_history join to get branch-specific view
   - Test: Verify same object on different branches shows correct state

2. **History Query Performance**
   - Mitigation: Leverage existing indexes on object_history(branch_id, author_time)
   - Test: Performance with 1000+ objects

3. **Schema-Qualified Name Parsing**
   - Mitigation: Simple split on '.' for schema qualification
   - Test: Both 'schema.object' and 'object' formats

4. **Conflict Detection Accuracy**
   - Mitigation: Use content_hash comparison, not string diff
   - Test: Same hash = unchanged, different hash = modified

### Rollback Plan

If implementation fails:
1. Keep Phases 1-2 intact
2. Delete `sql/031_pggit_object_tracking.sql`
3. Start over with revised approach
4. No production data affected (all local testing)

---

## Next Steps (Post-Approval)

1. User reviews this plan
2. User approves implementation approach
3. Start Phase 3 implementation
4. Commit Phase 3 implementation when complete
5. Proceed to Phase 4: Merge Operations

---

**Plan Status**: Ready for User Review and Approval

**Prepared By**: Claude Code Architect
**Date**: 2025-12-26
**Version**: 1.0 (Ready for Implementation)
