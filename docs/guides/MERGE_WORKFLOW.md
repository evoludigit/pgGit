# pgGit Merge Workflow Guide

## Overview

Merge operations in pgGit allow you to integrate schema changes from one branch into another. This guide covers the complete merge workflow, from simple merges to complex conflict resolution scenarios.

**What ships in v0.2:**
- `pggit.merge()` - Merge two branches
- `pggit.detect_conflicts()` - Identify conflicts
- `pggit.resolve_conflict()` - Manual resolution
- Merge history tracking and audit trail

---

## Quick Start

### Simple Merge (No Conflicts)

The simplest case: merge a feature branch into main when there are no conflicting changes.

```sql
-- 1. Create a feature branch from main
SELECT pggit.create_branch('feature/new-api', 'main', false);

-- 2. Make some schema changes in the feature branch
SELECT pggit.switch_branch('feature/new-api');
CREATE TABLE api_keys (id SERIAL, key TEXT);

-- 3. Switch back to main and merge
SELECT pggit.switch_branch('main');
SELECT * FROM pggit.merge('feature/new-api', 'main', 'auto');

-- Output (if no conflicts):
-- {
--   "merge_id": "550e8400-e29b-41d4-a716-446655440000",
--   "status": "completed",
--   "tables_merged": 1,
--   "conflict_count": 0
-- }
```

### Merge with Conflicts

When branches have conflicting changes, pgGit detects them and waits for resolution.

```sql
-- 1. Check for conflicts before merging
SELECT * FROM pggit.detect_conflicts('feature/modified-users', 'main');

-- Output:
-- {
--   "conflict_count": 2,
--   "conflicts": [
--     {
--       "table": "public.users",
--       "type": "column_modified",
--       "in_branch": "feature/modified-users"
--     },
--     {
--       "table": "public.posts",
--       "type": "table_added",
--       "in_branch": "feature/modified-users"
--     }
--   ]
-- }

-- 2. Attempt merge (will show conflicts)
SELECT * FROM pggit.merge('feature/modified-users', 'main', 'auto');

-- Output:
-- {
--   "merge_id": "550e8400-e29b-41d4-a716-446655440001",
--   "status": "awaiting_resolution",
--   "conflicts": [...],
--   "conflict_count": 2
-- }

-- 3. Get detailed conflict information
SELECT * FROM pggit.get_conflicts(
  '550e8400-e29b-41d4-a716-446655440001'::uuid
);

-- 4. Resolve each conflict
SELECT pggit.resolve_conflict(
  '550e8400-e29b-41d4-a716-446655440001'::uuid,
  'public.users',
  'ours'  -- Keep main's version
);

SELECT pggit.resolve_conflict(
  '550e8400-e29b-41d4-a716-446655440001'::uuid,
  'public.posts',
  'theirs'  -- Use feature branch's version
);

-- 5. Complete merge
SELECT pggit._complete_merge_after_resolution(
  '550e8400-e29b-41d4-a716-446655440001'::uuid
);

-- Check final status
SELECT * FROM pggit.merge_history
WHERE id = '550e8400-e29b-41d4-a716-446655440001'::uuid;

-- Output:
-- {
--   "status": "completed",
--   "resolved_conflicts": 2,
--   "unresolved_conflicts": 0
-- }
```

---

## Conflict Types

pgGit detects the following conflict types:

### Schema-Level Conflicts

**`table_added`** - Table exists in source but not in target
```
Branch A: Creates table "audit_log"
Branch B: No changes to audit_log
Resolution: Accept from branch A ('theirs') or skip ('ours')
```

**`table_removed`** - Table removed from source but exists in target
```
Branch A: Drops table "deprecated_feature"
Branch B: Still has deprecated_feature
Resolution: Keep in target ('ours') or remove ('theirs')
```

**`table_modified`** - Table structure differs between branches
```
Branch A: Adds column email_verified to users
Branch B: Adds column last_login to users
Resolution: Choose one version or custom merge
```

### Column-Level Conflicts

**`column_added`** - Column added in source but not in target
**`column_removed`** - Column removed from source but exists in target
**`column_modified`** - Column type, constraints, or properties differ

### Constraint Conflicts

**`constraint_added`** - New constraint in source (e.g., UNIQUE, CHECK)
**`constraint_removed`** - Constraint dropped from source
**`constraint_modified`** - Constraint definition changed

### Index Conflicts

**`index_added`** - New index created in source
**`index_removed`** - Index dropped from source

---

## Resolution Strategies

### `ours` - Keep Target Branch Version

Use the schema from the target branch (the branch being merged INTO).

```sql
SELECT pggit.resolve_conflict(
  merge_id,
  'public.users',
  'ours'
);
```

**When to use:**
- Target branch has the "correct" schema
- You want to preserve main branch's design decisions
- Source branch changes are unwanted

### `theirs` - Use Source Branch Version

Use the schema from the source branch (the branch being merged FROM).

```sql
SELECT pggit.resolve_conflict(
  merge_id,
  'public.users',
  'theirs'
);
```

**When to use:**
- Source branch has newer/better changes
- You want to adopt feature branch's improvements
- Main branch version is obsolete

### `custom` - Manual Resolution

Provide your own DDL to resolve the conflict.

```sql
SELECT pggit.resolve_conflict(
  merge_id,
  'public.users',
  'custom',
  'ALTER TABLE public.users ADD COLUMN email_verified BOOLEAN DEFAULT false;'::text
);
```

**When to use:**
- Both branches have valid but different changes
- You need to combine features from both branches
- Neither branch's version is acceptable as-is

---

## Common Workflows

### Workflow 1: Feature Branch Merge

Standard feature branch workflow:

```sql
-- Start: Create feature branch
SELECT pggit.create_branch('feature/user-profiles', 'main', false);
SELECT pggit.switch_branch('feature/user-profiles');

-- Make changes on feature branch
CREATE TABLE user_profiles (...);
CREATE INDEX idx_user_profiles_user_id ON user_profiles(user_id);

-- Back on main, merge when ready
SELECT pggit.switch_branch('main');
SELECT pggit.merge('feature/user-profiles', 'main', 'auto');

-- If conflicts exist, resolve them
SELECT * FROM pggit.get_conflicts(merge_id);
SELECT pggit.resolve_conflict(merge_id, 'table_name', 'theirs');
SELECT pggit._complete_merge_after_resolution(merge_id);
```

### Workflow 2: Multiple Developers

Two developers working on separate features, then merging to main:

```sql
-- Developer A: Feature branch
SELECT pggit.create_branch('feature/auth-improvements', 'main', false);
SELECT pggit.switch_branch('feature/auth-improvements');
ALTER TABLE public.users ADD COLUMN mfa_enabled BOOLEAN;

-- Developer B: Different feature branch
SELECT pggit.create_branch('feature/email-service', 'main', false);
SELECT pggit.switch_branch('feature/email-service');
CREATE TABLE email_queue (...);

-- Merge A first
SELECT pggit.switch_branch('main');
SELECT pggit.merge('feature/auth-improvements', 'main', 'auto');

-- Then merge B (may need conflict resolution)
SELECT pggit.merge('feature/email-service', 'main', 'auto');
```

### Workflow 3: Release Branch

Stabilize a release on a separate branch before merging to main:

```sql
-- Create release branch from main
SELECT pggit.create_branch('release/v0.2.0', 'main', false);
SELECT pggit.switch_branch('release/v0.2.0');

-- Apply bug fixes and stabilization changes
ALTER TABLE public.users ALTER COLUMN email SET NOT NULL;

-- Test thoroughly...

-- Merge back to main when ready
SELECT pggit.switch_branch('main');
SELECT pggit.merge('release/v0.2.0', 'main', 'auto');

-- Also merge to develop for next release
SELECT pggit.switch_branch('develop');
SELECT pggit.merge('release/v0.2.0', 'develop', 'auto');
```

### Workflow 4: Hotfix to Main

Merge a hotfix from a branch to multiple target branches:

```sql
-- Create hotfix branch
SELECT pggit.create_branch('hotfix/sql-injection', 'main', false);
SELECT pggit.switch_branch('hotfix/sql-injection');

-- Make security fix
ALTER TABLE public.api_keys ADD CONSTRAINT check_valid_key CHECK (length(key) >= 32);

-- Merge to main
SELECT pggit.switch_branch('main');
SELECT pggit.merge('hotfix/sql-injection', 'main', 'auto');

-- Also merge to release branch
SELECT pggit.switch_branch('release/v0.2.0');
SELECT pggit.merge('hotfix/sql-injection', 'release/v0.2.0', 'auto');
```

---

## Merge Operations Reference

### `pggit.merge(source_branch, target_branch, strategy)`

**Parameters:**
- `source_branch` (text): Branch to merge FROM
- `target_branch` (text): Branch to merge INTO (NULL = current branch)
- `strategy` (text): 'auto' (default) - automatic merge if no conflicts

**Returns:** jsonb with structure:
```json
{
  "merge_id": "uuid",
  "status": "completed|awaiting_resolution|failed",
  "tables_merged": 42,
  "conflict_count": 0,
  "conflicts": [...]
}
```

**Status meanings:**
- `completed` - Merge finished successfully
- `awaiting_resolution` - Conflicts detected, manual resolution required
- `failed` - Merge failed (check error_message)

### `pggit.detect_conflicts(source_branch, target_branch)`

**Parameters:**
- `source_branch` (text): First branch to compare
- `target_branch` (text): Second branch to compare

**Returns:** jsonb with structure:
```json
{
  "conflict_count": 2,
  "conflicts": [
    {
      "table": "schema.object_name",
      "type": "conflict_type",
      "source_hash": "...",
      "target_hash": "..."
    }
  ]
}
```

### `pggit.resolve_conflict(merge_id, table_name, resolution, custom_definition)`

**Parameters:**
- `merge_id` (uuid): ID from merge() operation
- `table_name` (text): Object name to resolve (schema.name format)
- `resolution` (text): 'ours', 'theirs', or 'custom'
- `custom_definition` (text, optional): DDL for custom resolution

**Returns:** void

### `pggit.get_conflicts(merge_id)`

**Parameters:**
- `merge_id` (uuid): ID from merge() operation

**Returns:** Table of conflicts with details for manual review

### `pggit.get_merge_status(merge_id)`

**Parameters:**
- `merge_id` (uuid): ID from merge() operation

**Returns:** jsonb with current merge status

### `pggit.abort_merge(merge_id)`

**Parameters:**
- `merge_id` (uuid): ID from merge() operation to cancel

**Returns:** void

---

## Best Practices

### 1. Always Check for Conflicts First

```sql
-- Before attempting merge, check what conflicts exist
SELECT * FROM pggit.detect_conflicts('feature/new-api', 'main');

-- Review and plan resolution strategy
-- THEN proceed with merge
```

### 2. Use Meaningful Branch Names

```sql
-- Good
feature/user-authentication
bugfix/email-validation
release/v1.2.0

-- Avoid
feature1
temp
test
```

### 3. Merge Frequently

Small, frequent merges are easier to resolve than large ones.

```sql
-- Good: Merge after completing a small feature
-- Every 2-3 days

-- Avoid: Merge only after weeks of development
-- Leads to merge conflicts
```

### 4. Keep Branches Short-Lived

Close branches soon after merging to reduce drift.

```sql
-- After successful merge
SELECT pggit.delete_branch('feature/completed-feature');
```

### 5. Document Complex Resolutions

When using custom resolutions, add notes to merge_history:

```sql
UPDATE pggit.merge_history
SET notes = jsonb_set(
  COALESCE(notes, '{}'::jsonb),
  '{resolution_explanation}',
  '"Combined column_modified with index from both branches"'::jsonb
)
WHERE id = merge_id;
```

### 6. Test After Merge

Always verify schema integrity after merging:

```sql
-- Check that merge didn't break anything
SELECT pg_sleep(0.1); -- Wait for async operations
\d+ schema.table_name
SELECT constraint_name FROM information_schema.constraint_column_usage
WHERE table_name = 'table_name';
```

---

## Troubleshooting

### Merge Status Shows "awaiting_resolution" Indefinitely

**Problem:** Merge stuck, unable to complete
**Solution:**
```sql
-- Check which conflicts are still unresolved
SELECT * FROM pggit.merge_conflicts
WHERE merge_id = 'your-merge-id'::uuid AND resolution IS NULL;

-- Resolve remaining conflicts
SELECT pggit.resolve_conflict(merge_id, table_name, 'ours');

-- Complete the merge
SELECT pggit._complete_merge_after_resolution(merge_id);
```

### Unexpected Conflicts Detected

**Problem:** Conflicts found when you expected none
**Solution:**
```sql
-- Examine the actual differences
SELECT * FROM pggit.detect_conflicts('branch_a', 'branch_b');

-- Check both branches' schema
SELECT * FROM pggit.objects WHERE branch_name = 'branch_a';
SELECT * FROM pggit.objects WHERE branch_name = 'branch_b';
```

### Merge Failed with Error

**Problem:** Merge operation failed
**Solution:**
```sql
-- Check merge history for error details
SELECT error_message FROM pggit.merge_history
WHERE id = 'your-merge-id'::uuid;

-- Check for orphaned records
SELECT COUNT(*) FROM pggit.merge_conflicts
WHERE merge_id = 'your-merge-id'::uuid;

-- If needed, abort and retry
SELECT pggit.abort_merge('your-merge-id'::uuid);
```

---

## Performance Considerations

- **Schema size:** Merge performance scales linearly with schema size
- **Conflict complexity:** Resolving conflicts adds minimal overhead
- **Branches:** More branches don't affect merge speed
- **Concurrent merges:** Fully supported, no locking

**Typical performance:**
- 100 table schema: < 100ms
- 1000 object schema: < 500ms
- Conflict detection: < 10ms per comparison

---

## Limitations & Future Work

Current v0.2 limitations:
- ✅ Schema-level merging only (no data merging yet)
- ✅ Binary conflict resolution (ours/theirs/custom)
- ✅ No automatic merging of compatible changes
- 🔄 v0.3 will add: Three-way merge algorithm with smart conflict detection
- 🔄 v0.4 will add: Data branching with merge support

---

## Examples

### Example 1: Merging a User Authentication Feature

```sql
-- Create feature branch
SELECT pggit.create_branch('feature/oauth2', 'main', false);
SELECT pggit.switch_branch('feature/oauth2');

-- Add OAuth tables
CREATE TABLE oauth_providers (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  client_id TEXT,
  client_secret TEXT
);

CREATE TABLE oauth_tokens (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  provider_id INTEGER REFERENCES oauth_providers(id),
  token TEXT NOT NULL,
  refresh_token TEXT,
  expires_at TIMESTAMP
);

CREATE INDEX idx_oauth_tokens_user_id ON oauth_tokens(user_id);

-- Back to main
SELECT pggit.switch_branch('main');

-- Merge
SELECT pggit.merge('feature/oauth2', 'main', 'auto') AS merge_result;

-- If clean (no conflicts), merge_result.status = 'completed'
-- All new tables are now in main
```

### Example 2: Resolving a Column Modification Conflict

```sql
-- Detect conflicts
SELECT * FROM pggit.detect_conflicts('feature/user-email', 'feature/user-phone');

-- Output shows: conflict on users table, column_modified
-- Feature 1 changed email to VARCHAR(255)
-- Feature 2 changed email to VARCHAR(500)

-- Merge
SELECT pggit.merge('feature/user-email', 'feature/user-phone', 'auto')
INTO v_result;

-- Resolve: use the larger length
SELECT pggit.resolve_conflict(
  (v_result->>'merge_id')::uuid,
  'public.users',
  'custom',
  'ALTER TABLE public.users ALTER COLUMN email TYPE VARCHAR(500);'
);

-- Complete
SELECT pggit._complete_merge_after_resolution((v_result->>'merge_id')::uuid);
```

---

## Related Documentation

- [API Reference](/docs/API_Reference.md) - Complete function signatures
- [Architecture](/docs/ARCHITECTURE.md) - How merging works internally
- [Branching Guide](/docs/guides/DEVELOPMENT_WORKFLOW.md) - Branch creation strategies
