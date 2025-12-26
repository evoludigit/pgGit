# Phase 5: Quick Reference Guide

**Function Signatures & Usage Patterns**

---

## Function 1: get_commit_history()

### Signature
```sql
pggit.get_commit_history(
    p_branch_name TEXT DEFAULT NULL,
    p_since_timestamp TIMESTAMP DEFAULT NULL,
    p_until_timestamp TIMESTAMP DEFAULT NULL,
    p_author_name TEXT DEFAULT NULL,
    p_search_message TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0,
    p_order_by TEXT DEFAULT 'author_time DESC'
)
RETURNS TABLE (
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
)
```

### Usage Examples
```sql
-- All commits on main branch
SELECT * FROM pggit.get_commit_history('main');

-- Recent commits by specific author
SELECT * FROM pggit.get_commit_history(
    p_branch_name => 'main',
    p_author_name => 'developer@example.com',
    p_limit => 20
);

-- Commits in date range
SELECT * FROM pggit.get_commit_history(
    p_branch_name => 'feature-a',
    p_since_timestamp => '2025-12-20 00:00:00',
    p_until_timestamp => '2025-12-27 00:00:00',
    p_limit => 100
);

-- Search commit messages
SELECT * FROM pggit.get_commit_history(
    p_search_message => 'ALTER TABLE'
);
```

### Performance Tips
- Use pagination (p_limit + p_offset) for large result sets
- Index on: commits.author_time, commits.branch_id
- Time range filters are most efficient

---

## Function 2: get_audit_trail()

### Signature
```sql
pggit.get_audit_trail(
    p_object_type TEXT DEFAULT NULL,
    p_schema_name TEXT DEFAULT NULL,
    p_object_name TEXT DEFAULT NULL,
    p_branch_name TEXT DEFAULT NULL,
    p_change_type TEXT DEFAULT NULL,
    p_since_timestamp TIMESTAMP DEFAULT NULL,
    p_until_timestamp TIMESTAMP DEFAULT NULL,
    p_limit INTEGER DEFAULT 100,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
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
)
```

### Usage Examples
```sql
-- All changes to a specific table
SELECT * FROM pggit.get_audit_trail(
    p_object_type => 'TABLE',
    p_object_name => 'users'
);

-- All breaking changes on a branch
SELECT * FROM pggit.get_audit_trail(
    p_branch_name => 'main',
    p_change_type => 'DROP'
)
WHERE is_breaking_change = true;

-- Changes by specific author
SELECT * FROM pggit.get_audit_trail(
    p_object_type => 'FUNCTION'
)
WHERE author_name = 'developer@example.com';

-- Recent ALTER operations
SELECT * FROM pggit.get_audit_trail(
    p_change_type => 'ALTER',
    p_since_timestamp => NOW() - INTERVAL '7 days'
);
```

### Performance Tips
- Index on: object_history.object_id, object_history.created_at
- Diff summary generation may be slow - use p_limit
- Can be memory intensive for large result sets

---

## Function 3: get_object_timeline()

### Signature
```sql
pggit.get_object_timeline(
    p_object_name TEXT,
    p_branch_name TEXT DEFAULT NULL,
    p_include_merged_history BOOLEAN DEFAULT FALSE,
    p_limit INTEGER DEFAULT 100
)
RETURNS TABLE (
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
)
ORDER BY timeline_version ASC
```

### Usage Examples
```sql
-- Complete timeline of users table on main
SELECT * FROM pggit.get_object_timeline('public.users', 'main');

-- Timeline including merged changes
SELECT * FROM pggit.get_object_timeline(
    p_object_name => 'orders',
    p_branch_name => 'main',
    p_include_merged_history => true
);

-- Count versions of a function
SELECT COUNT(*) as versions FROM pggit.get_object_timeline('count_users');

-- Find oldest version
SELECT * FROM pggit.get_object_timeline('users')
ORDER BY timeline_version ASC LIMIT 1;
```

### Performance Tips
- Usually fast (one object, limited history)
- Index on: object_history.object_id
- Merge history tracing may be slow

---

## Function 4: query_at_timestamp()

### Signature
```sql
pggit.query_at_timestamp(
    p_branch_name TEXT,
    p_target_timestamp TIMESTAMP,
    p_object_type TEXT DEFAULT NULL,
    p_schema_filter TEXT DEFAULT NULL,
    p_order_by TEXT DEFAULT 'object_name ASC'
)
RETURNS TABLE (
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
)
ORDER BY object_type, object_name ASC
```

### Usage Examples
```sql
-- Reconstruct main branch at specific time
SELECT * FROM pggit.query_at_timestamp(
    'main',
    '2025-12-25 12:00:00'
);

-- Schema on feature-a at point in time
SELECT * FROM pggit.query_at_timestamp(
    'feature-a',
    '2025-12-26 11:30:00',
    p_object_type => 'TABLE'
);

-- Check what tables existed yesterday
SELECT * FROM pggit.query_at_timestamp(
    'main',
    NOW() - INTERVAL '1 day',
    p_object_type => 'TABLE'
);

-- Compare schemas
-- Current state
SELECT object_name FROM pggit.query_at_timestamp('main', NOW())
WHERE object_type = 'TABLE'
EXCEPT
-- State 1 week ago
SELECT object_name FROM pggit.query_at_timestamp('main', NOW() - INTERVAL '1 week')
WHERE object_type = 'TABLE';
```

### Performance Tips
- **Very expensive query** - scans entire object_history
- Index on: object_history.object_id, object_history.created_at, object_history.branch_id
- Use most recent timestamps when possible
- Cache results for frequently accessed times
- Consider limiting to recent history (last N days)

---

## Common Patterns & Queries

### Pattern 1: Find Breaking Changes
```sql
SELECT author_name, changed_at, object_name, change_reason
FROM pggit.get_audit_trail()
WHERE is_breaking_change = true
AND changed_at > NOW() - INTERVAL '30 days'
ORDER BY changed_at DESC;
```

### Pattern 2: Track Object Evolution
```sql
SELECT
    timeline_version,
    change_type,
    changed_at,
    author_name
FROM pggit.get_object_timeline('users', 'main')
ORDER BY timeline_version ASC;
```

### Pattern 3: Commit Activity Report
```sql
SELECT
    DATE_TRUNC('day', author_time) as day,
    author_name,
    COUNT(*) as commits,
    SUM(objects_changed) as total_changes
FROM pggit.get_commit_history('main')
WHERE author_time > NOW() - INTERVAL '30 days'
GROUP BY DATE_TRUNC('day', author_time), author_name
ORDER BY day DESC;
```

### Pattern 4: Before/After Comparison
```sql
SELECT
    object_name,
    change_type,
    before_definition,
    after_definition,
    definition_diff_summary
FROM pggit.get_audit_trail(p_object_type => 'TABLE')
WHERE change_type = 'ALTER'
AND changed_at > NOW() - INTERVAL '1 day';
```

---

## Error Handling

### Common Errors & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `Branch does not exist` | Invalid p_branch_name | Use valid branch name from pggit.branches |
| `Object not found` | Object doesn't exist | Check schema.object name format |
| `Timestamp in future` | p_target_timestamp > NOW() | Use timestamp <= NOW() |
| `Branch didn't exist` | p_target_timestamp < branch.created_at | Use timestamp after branch creation |
| `Query timeout` | query_at_timestamp on very old data | Use more recent timestamp or object_type filter |
| `NULL returned` | No data at that timestamp | Verify object existed at that time |

---

## Performance Guidelines

### Query Complexity

| Function | Complexity | Typical Time |
|----------|-----------|--------------|
| get_commit_history() | O(N) where N = commits | < 100ms (50 results) |
| get_audit_trail() | O(M) where M = changes | < 500ms (100 results) |
| get_object_timeline() | O(V) where V = versions | < 100ms (single object) |
| query_at_timestamp() | O(O*H) expensive | 1-5 seconds (typical) |

### When to Use Which Function

| Need | Function | Reason |
|------|----------|--------|
| Browse commit history | get_commit_history() | Fast pagination |
| See all changes to an object | get_audit_trail() | Complete change history |
| Track one object evolution | get_object_timeline() | Focused, fast |
| Restore schema from backup | query_at_timestamp() | Full schema reconstruction |
| Find who changed something | get_audit_trail() | Author + timestamp |
| Compare two time periods | query_at_timestamp() | Two calls + compare |

---

## Testing Checklist

### Unit Tests to Write
- [ ] Test each function with NULL parameters
- [ ] Test filtering (single + combined filters)
- [ ] Test pagination (limit, offset)
- [ ] Test time ranges
- [ ] Test non-existent objects/branches
- [ ] Test deleted objects
- [ ] Test merged branch history
- [ ] Test breaking change detection
- [ ] Test diff summary generation
- [ ] Test error messages

### Integration Tests
- [ ] Query after merge operation
- [ ] Compare before/after merge
- [ ] Timeline across merge points
- [ ] Commit history shows merge commits
- [ ] Audit trail shows merged changes

### Performance Tests
- [ ] get_commit_history with 10K commits
- [ ] get_audit_trail with 1K changes
- [ ] query_at_timestamp for very old timestamp
- [ ] Pagination with large result sets

---

**Created**: 2025-12-26
**Status**: Ready for Implementation Reference
