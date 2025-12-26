# Phase 6: Quick Reference Guide

**Function Signatures & Usage Patterns**

---

## Function 1: validate_rollback()

### Signature
```sql
pggit.validate_rollback(
    p_branch_name TEXT,
    p_source_commit_hash CHAR(64),
    p_target_commit_hash CHAR(64) DEFAULT NULL,
    p_rollback_type TEXT DEFAULT 'SINGLE_COMMIT'
)
RETURNS TABLE (
    validation_id BIGINT,
    validation_type TEXT,
    status TEXT,
    severity TEXT,
    message TEXT,
    affected_objects TEXT[],
    recommendation TEXT
)
```

### Usage Examples
```sql
-- Check if safe to rollback a commit
SELECT * FROM pggit.validate_rollback(
    p_branch_name => 'main',
    p_source_commit_hash => 'abc123def456...'
);

-- Get only critical issues
SELECT * FROM pggit.validate_rollback(
    p_branch_name => 'main',
    p_source_commit_hash => 'abc123def456...'
) WHERE severity = 'CRITICAL';

-- Check range rollback feasibility
SELECT * FROM pggit.validate_rollback(
    p_branch_name => 'main',
    p_source_commit_hash => 'abc123...',
    p_target_commit_hash => 'def456...',
    p_rollback_type => 'RANGE'
);
```

### Performance
- < 500ms for typical commits
- Scales with dependency complexity

---

## Function 2: rollback_commit()

### Signature
```sql
pggit.rollback_commit(
    p_branch_name TEXT,
    p_commit_hash CHAR(64),
    p_validate_first BOOLEAN DEFAULT TRUE,
    p_allow_warnings BOOLEAN DEFAULT FALSE,
    p_rollback_mode TEXT DEFAULT 'EXECUTED'
)
RETURNS TABLE (
    rollback_id BIGINT,
    rollback_commit_hash CHAR(64),
    status TEXT,
    objects_rolled_back INTEGER,
    validations_passed INTEGER,
    validations_failed INTEGER,
    execution_time_ms INTEGER
)
```

### Usage Examples
```sql
-- Rollback single commit (validate first)
SELECT * FROM pggit.rollback_commit(
    p_branch_name => 'main',
    p_commit_hash => 'abc123...'
);

-- Dry run to preview changes
SELECT * FROM pggit.rollback_commit(
    p_branch_name => 'main',
    p_commit_hash => 'abc123...',
    p_rollback_mode => 'DRY_RUN'
);

-- Force rollback even with warnings
SELECT * FROM pggit.rollback_commit(
    p_branch_name => 'main',
    p_commit_hash => 'abc123...',
    p_allow_warnings => TRUE
);
```

### Performance
- Validation: < 500ms
- Execution: < 1 second for typical commits
- DRY_RUN: < 2 seconds

---

## Function 3: rollback_range()

### Signature
```sql
pggit.rollback_range(
    p_branch_name TEXT,
    p_start_commit_hash CHAR(64),
    p_end_commit_hash CHAR(64),
    p_order_by TEXT DEFAULT 'REVERSE_CHRONOLOGICAL',
    p_rollback_mode TEXT DEFAULT 'EXECUTED'
)
RETURNS TABLE (
    rollback_id BIGINT,
    commits_rolled_back INTEGER,
    rollback_commit_hash CHAR(64),
    status TEXT,
    objects_affected_total INTEGER,
    conflicts_resolved INTEGER,
    execution_time_ms INTEGER
)
```

### Usage Examples
```sql
-- Rollback last 3 commits
SELECT * FROM pggit.rollback_range(
    p_branch_name => 'main',
    p_start_commit_hash => 'abc123...',  -- oldest
    p_end_commit_hash => 'def456...'     -- newest
);

-- Use dependency ordering
SELECT * FROM pggit.rollback_range(
    p_branch_name => 'main',
    p_start_commit_hash => 'abc123...',
    p_end_commit_hash => 'def456...',
    p_order_by => 'DEPENDENCY_ORDER'
);

-- Dry run multiple commits
SELECT * FROM pggit.rollback_range(
    p_branch_name => 'main',
    p_start_commit_hash => 'abc123...',
    p_end_commit_hash => 'def456...',
    p_rollback_mode => 'DRY_RUN'
);
```

### Performance
- 5 commits: < 2 seconds
- 10 commits: < 5 seconds

---

## Function 4: rollback_to_timestamp()

### Signature
```sql
pggit.rollback_to_timestamp(
    p_branch_name TEXT,
    p_target_timestamp TIMESTAMP,
    p_validate_first BOOLEAN DEFAULT TRUE,
    p_rollback_mode TEXT DEFAULT 'EXECUTED'
)
RETURNS TABLE (
    rollback_id BIGINT,
    rollback_commit_hash CHAR(64),
    status TEXT,
    commits_reversed INTEGER,
    objects_recreated INTEGER,
    objects_deleted INTEGER,
    objects_modified INTEGER,
    execution_time_ms INTEGER
)
```

### Usage Examples
```sql
-- Restore schema to 1 week ago
SELECT * FROM pggit.rollback_to_timestamp(
    p_branch_name => 'main',
    p_target_timestamp => NOW() - INTERVAL '7 days'
);

-- Dry run time-travel
SELECT * FROM pggit.rollback_to_timestamp(
    p_branch_name => 'main',
    p_target_timestamp => NOW() - INTERVAL '1 day',
    p_rollback_mode => 'DRY_RUN'
);

-- Restore to specific timestamp
SELECT * FROM pggit.rollback_to_timestamp(
    p_branch_name => 'main',
    p_target_timestamp => '2025-12-20 14:30:00'::TIMESTAMP
);
```

### Performance
- 1 week of history: < 5 seconds
- 1 month of history: < 15 seconds

---

## Function 5: undo_changes()

### Signature
```sql
pggit.undo_changes(
    p_branch_name TEXT,
    p_object_names TEXT[],
    p_commit_hash CHAR(64) DEFAULT NULL,
    p_since_timestamp TIMESTAMP DEFAULT NULL,
    p_until_timestamp TIMESTAMP DEFAULT NULL,
    p_rollback_mode TEXT DEFAULT 'EXECUTED'
)
RETURNS TABLE (
    rollback_id BIGINT,
    rollback_commit_hash CHAR(64),
    status TEXT,
    objects_reverted INTEGER,
    changes_undone INTEGER,
    dependencies_handled INTEGER,
    execution_time_ms INTEGER
)
```

### Usage Examples
```sql
-- Undo changes to one table in specific commit
SELECT * FROM pggit.undo_changes(
    p_branch_name => 'main',
    p_object_names => ARRAY['public.users'],
    p_commit_hash => 'abc123...'
);

-- Undo changes to multiple objects
SELECT * FROM pggit.undo_changes(
    p_branch_name => 'main',
    p_object_names => ARRAY['public.users', 'public.orders', 'public.payments'],
    p_commit_hash => 'abc123...'
);

-- Undo changes in time range (partial rollback)
SELECT * FROM pggit.undo_changes(
    p_branch_name => 'main',
    p_object_names => ARRAY['public.users'],
    p_since_timestamp => NOW() - INTERVAL '2 days',
    p_until_timestamp => NOW() - INTERVAL '1 day'
);
```

### Performance
- < 1 second for 1-5 objects

---

## Function 6: rollback_dependencies()

### Signature
```sql
pggit.rollback_dependencies(
    p_object_id BIGINT
)
RETURNS TABLE (
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
)
```

### Usage Examples
```sql
-- Find all dependencies of users table
SELECT * FROM pggit.rollback_dependencies(
    p_object_id => (SELECT object_id FROM pggit.schema_objects
                    WHERE object_name = 'users' AND schema_name = 'public')
);

-- Get critical dependencies only
SELECT * FROM pggit.rollback_dependencies(
    p_object_id => (SELECT object_id FROM pggit.schema_objects
                    WHERE object_name = 'users' AND schema_name = 'public')
) WHERE breakage_severity IN ('ERROR', 'CRITICAL');

-- Analyze function dependencies
SELECT * FROM pggit.rollback_dependencies(
    p_object_id => (SELECT object_id FROM pggit.schema_objects
                    WHERE object_name = 'count_users' AND schema_name = 'public')
) WHERE dependency_type = 'TRIGGER';
```

### Performance
- < 100ms typical

---

## Common Patterns & Workflows

### Pattern 1: Safe Single Commit Rollback
```sql
-- Step 1: Validate
WITH validation AS (
    SELECT * FROM pggit.validate_rollback('main', 'abc123...')
)
SELECT * FROM validation WHERE severity = 'CRITICAL';

-- Step 2: Only proceed if no critical issues
SELECT * FROM pggit.rollback_commit(
    p_branch_name => 'main',
    p_commit_hash => 'abc123...'
);
```

### Pattern 2: Preview Before Rollback
```sql
-- Dry run to see what happens
SELECT * FROM pggit.rollback_commit(
    p_branch_name => 'main',
    p_commit_hash => 'abc123...',
    p_rollback_mode => 'DRY_RUN'
);

-- If satisfied, execute for real
SELECT * FROM pggit.rollback_commit(
    p_branch_name => 'main',
    p_commit_hash => 'abc123...',
    p_rollback_mode => 'EXECUTED'
);
```

### Pattern 3: Rollback Multiple Commits
```sql
-- Get commit hashes
WITH commits AS (
    SELECT commit_hash FROM pggit.get_commit_history('main')
    LIMIT 5 OFFSET 0
)
SELECT * FROM pggit.rollback_range(
    p_branch_name => 'main',
    p_start_commit_hash => (SELECT commit_hash FROM commits ORDER BY 1 LIMIT 1),
    p_end_commit_hash => (SELECT commit_hash FROM commits ORDER BY 1 DESC LIMIT 1)
);
```

### Pattern 4: Time-Travel Restore
```sql
-- Check what would be restored
SELECT * FROM pggit.rollback_to_timestamp(
    p_branch_name => 'main',
    p_target_timestamp => NOW() - INTERVAL '3 days',
    p_rollback_mode => 'DRY_RUN'
);

-- Execute restoration
SELECT * FROM pggit.rollback_to_timestamp(
    p_branch_name => 'main',
    p_target_timestamp => NOW() - INTERVAL '3 days'
);
```

### Pattern 5: Selective Object Undo
```sql
-- Undo changes to specific table only
SELECT * FROM pggit.undo_changes(
    p_branch_name => 'main',
    p_object_names => ARRAY['public.users'],
    p_commit_hash => 'abc123...'
);
```

### Pattern 6: Check Dependencies Before Drop
```sql
-- Find what depends on users table
SELECT * FROM pggit.rollback_dependencies(
    p_object_id => (SELECT object_id FROM pggit.schema_objects
                    WHERE object_name = 'users')
) WHERE dependency_type IN ('FK', 'TRIGGER', 'INDEX')
ORDER BY breakage_severity DESC;
```

---

## Error Handling

### Common Errors & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `Commit does not exist` | Invalid commit hash | Use get_commit_history() to find correct hash |
| `Validation failed - CRITICAL` | Dependencies broken | Check rollback_dependencies() for affected objects |
| `Cannot rollback merged commit` | Commit was merge result | Use rollback_range() or manually resolve |
| `Data loss detected` | Operation would delete data | Set p_allow_warnings or review with undo_changes |
| `Branch didn't exist at time` | Timestamp before branch creation | Use later timestamp |
| `Circular dependencies detected` | Objects depend on each other | Use dependency ordering or partial rollback |
| `Transaction aborted` | Constraint violation during rollback | Review suggested_action from dependencies |

---

## Performance Guidelines

### When to Use Which Function

| Need | Function | Reason |
|------|----------|--------|
| Check if rollback is safe | validate_rollback() | Pre-flight validation |
| Undo one commit | rollback_commit() | Simple and fast |
| Undo multiple commits | rollback_range() | Handles ordering |
| Restore to past state | rollback_to_timestamp() | Time-travel capability |
| Undo specific objects | undo_changes() | Granular control |
| Analyze dependencies | rollback_dependencies() | Plan rollback sequence |

### Query Complexity

| Function | Complexity | Typical Time |
|----------|-----------|--------------|
| validate_rollback() | O(D) | < 500ms |
| rollback_commit() | O(N) | < 1s |
| rollback_range() | O(R*N) | < 5s |
| rollback_to_timestamp() | O(H) | < 15s |
| undo_changes() | O(N log N) | < 1s |
| rollback_dependencies() | O(D log D) | < 100ms |

---

## Safety Best Practices

1. **Always Validate First**
   ```sql
   -- Before any rollback, always validate
   SELECT COUNT(*) FROM pggit.validate_rollback(...)
   WHERE severity = 'CRITICAL';
   ```

2. **Dry Run Before Execute**
   ```sql
   -- Preview the changes
   SELECT * FROM pggit.rollback_commit(..., p_rollback_mode => 'DRY_RUN');
   ```

3. **Check Dependencies**
   ```sql
   -- Understand what might break
   SELECT * FROM pggit.rollback_dependencies(p_object_id);
   ```

4. **Use Partial Rollback When Possible**
   ```sql
   -- Instead of full rollback, undo specific objects
   SELECT * FROM pggit.undo_changes(p_object_names => ARRAY[...]);
   ```

5. **Review Audit Trail**
   ```sql
   -- After rollback, verify what happened
   SELECT * FROM pggit.get_audit_trail()
   WHERE change_type = 'ROLLBACK'
   ORDER BY changed_at DESC;
   ```

---

## Testing Checklist

### Unit Tests to Write
- [ ] Test each function with valid inputs
- [ ] Test with invalid commit hashes
- [ ] Test with future timestamps
- [ ] Test dependency detection
- [ ] Test circular dependency handling
- [ ] Test with merged commits
- [ ] Test with cascade operations
- [ ] Test constraint violations
- [ ] Test partial failures
- [ ] Test DRY_RUN mode

### Integration Tests
- [ ] Rollback then commit new change
- [ ] Rollback after merge
- [ ] Undo partial rollback
- [ ] Time-travel then forward
- [ ] Multiple rollbacks in sequence

### Performance Tests
- [ ] Validate on 10K+ objects
- [ ] Rollback 100+ commits
- [ ] Time-travel 1+ year
- [ ] Dependencies 1000+ objects

---

**Created**: 2025-12-26
**Status**: Ready for Implementation Reference
