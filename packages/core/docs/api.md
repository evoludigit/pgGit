# pgGit v1.0 — API Reference

## Schemas

| Schema | Purpose |
|--------|---------|
| `pggit` | Public API. Application code uses only this schema. |
| `pggit_internal` | Internal implementation. Not for external use. |

## Branch Management

### `pggit.create_branch(name TEXT, parent_name TEXT DEFAULT NULL) → BIGINT`

Create a new branch. Copies all live objects from the parent branch (default:
current branch). Returns the new branch ID.

**Errors:**
- `Invalid branch name`: name contains disallowed characters (only `[a-zA-Z0-9._-]` allowed)
- `Branch "X" already exists`: duplicate name
- `Parent branch "X" not found or not active`: parent does not exist or is merged/deleted

---

### `pggit.switch_branch(name TEXT) → VOID`

Set the active branch for the current session. Subsequent DDL is tracked to
this branch.

**Errors:**
- `Branch "X" not found or not active`

---

### `pggit.delete_branch(name TEXT) → VOID`

Soft-delete a branch. Rejects `main`. Rejects branches with commits not yet
merged via `pggit.merge()`.

**Errors:**
- `Cannot delete the main branch`
- `Branch "X" has unmerged commits. Merge first or use force_delete_branch.`
- `Branch "X" not found`

---

### `pggit.force_delete_branch(name TEXT) → VOID`

Soft-delete a branch unconditionally (no merge check). Rejects `main`.

---

### `pggit.list_branches() → TABLE`

Returns all branches (active, merged, deleted) with:
- `name TEXT`
- `status pggit.branch_status`
- `parent_name TEXT`
- `head_commit_id BIGINT`
- `created_at TIMESTAMPTZ`

---

### `pggit.current_branch() → TEXT`

Returns the name of the active branch for the current session (defaults to
`'main'` if not set).

---

## Commit Graph

### `pggit.commit(message TEXT) → BIGINT`

Snapshot the current branch tree. Returns the new commit ID.

**Errors:**
- `Commit message must not be empty`
- `Nothing to commit on branch "X": tree unchanged since last commit`
- `Current branch "X" not found or not active`

---

### `pggit.log(branch_name TEXT DEFAULT NULL) → TABLE`

Return commit history for the given branch (default: current branch), most
recent first.

Returns: `id, parent_id, message, tree_hash, author, committed_at`

---

### `pggit.diff(from TEXT, to TEXT) → TABLE`

Compare object state between two branches. Returns one row per object that
differs.

Returns: `schema_name, object_name, object_type, change_type, from_hash, to_hash, from_ddl, to_ddl`

`change_type` values: `'added'`, `'removed'`, `'modified'`

**Errors:**
- `Branch "X" not found`

---

### `pggit.status` (view)

Shows uncommitted changes on the current branch:
`schema_name, object_name, object_type, operation, changed_at`

---

## Merging

### `pggit.merge(source_branch TEXT) → BIGINT`

Start a three-way merge from `source_branch` into the current branch.

- If no conflicts: auto-completes, returns merge ID with `status = 'completed'`
- If conflicts: stays `in_progress`, returns merge ID for resolution

**Errors:**
- `Source branch "X" not found or not active`
- `Cannot merge a branch into itself`
- `Source branch "X" has no commits`
- `No common ancestor found between "X" and "Y"`

---

### `pggit.resolve_conflict(merge_id BIGINT, schema_name TEXT, object_name TEXT, object_type pggit.object_type, resolution TEXT, manual_ddl TEXT DEFAULT NULL) → VOID`

Record the resolution for a conflicted object.

`resolution` values:
- `'ours'` — keep the target branch DDL
- `'theirs'` — apply the source branch DDL
- `'manual'` — apply `manual_ddl` (must be provided)

**Errors:**
- `No open conflict found for object X.Y (Z) in merge M`
- `resolution must be "ours", "theirs", or "manual"`
- `manual resolution requires p_manual_ddl to be provided`

---

### `pggit.complete_merge(merge_id BIGINT) → VOID`

Apply all resolved changes and create the merge commit. Fails if any conflicts
remain unresolved.

**Errors:**
- `Merge M has N unresolved conflict(s)`

---

## Tagging

### `pggit.tag(name TEXT, commit_id BIGINT DEFAULT NULL) → BIGINT`

Create a lightweight tag pointing to a commit. If `commit_id` is NULL, tags the
current branch head.

Returns the new tag ID.

**Errors:**
- `Invalid tag name`: name contains disallowed characters
- `Tag "X" already exists`
- `No commit_id provided and current branch has no commits`
- `Commit X does not exist`

---

### `pggit.untag(name TEXT) → VOID`

Delete a tag. Tags can be recreated later if needed.

**Errors:**
- `Tag "X" not found`

---

### `pggit.list_tags() → TABLE`

List all tags with commit information:
- `name TEXT`
- `commit_id BIGINT`
- `branch_name TEXT` — which branch currently points to this commit (if any)
- `commit_message TEXT`
- `created_at TIMESTAMPTZ`

---

### `pggit.get_commit_by_tag(name TEXT) → BIGINT`

Get the commit_id associated with a tag. Returns NULL if tag not found.

---

## Monitoring

### `pggit.metrics_summary() → TABLE`

Return key metrics about the pggit installation:
- `metric_name TEXT` — e.g., 'branches_total', 'commits_total'
- `metric_value BIGINT`

Metrics include:
- `branches_total`, `branches_active`, `branches_merged`
- `commits_total`
- `objects_tracked`, `objects_deleted`
- `tags_total`
- `merges_total`, `merges_completed`
- `history_entries`

---

### `pggit.v_branch_activity` (view)

Branch-level activity summary:
- `branch_name TEXT`
- `status pggit.branch_status`
- `commit_count BIGINT`
- `object_count BIGINT`
- `last_commit_at TIMESTAMPTZ`
- `created_at TIMESTAMPTZ`

---

### `pggit.v_recent_changes` (view)

Last 100 DDL changes across all branches:
- `changed_at TIMESTAMPTZ`
- `branch_name TEXT`
- `schema_name TEXT`
- `object_name TEXT`
- `operation TEXT` — 'CREATE', 'ALTER', 'DROP'
- `status TEXT` — 'committed' or 'uncommitted'

---

## Multi-Tenancy (Row-Level Security)

pgGit supports multi-tenant deployments via PostgreSQL Row-Level Security (RLS).
Each tenant (typically a SaaS customer) has isolated access to their own branches,
commits, and objects. The `tenant_id` column on all tables enables this isolation.

### `pggit.set_tenant(tenant_id UUID) → VOID`

Set the tenant UUID for the current session. All subsequent operations will be
scoped to this tenant. Pass NULL to enter admin mode (access all tenants).

```sql
-- Set tenant for current session
SELECT pggit.set_tenant('550e8400-e29b-41d4-a716-446655440000'::UUID);

-- Clear tenant (admin mode)
SELECT pggit.set_tenant(NULL);
```

---

### `pggit.current_tenant() → UUID`

Get the current tenant UUID for this session. Returns NULL if in admin mode.

---

### `pggit.is_tenant_admin() → BOOLEAN`

Check if current user is a tenant admin or in admin mode (no tenant set).

---

### `pggit.v_my_branches` (view)

Tenant-scoped view of branches. In admin mode (no tenant set), shows all branches.
In tenant mode, shows only branches belonging to the current tenant.

---

### `pggit.v_my_commits` (view)

Tenant-scoped view of commits with the same behavior as `v_my_branches`.

---

### Security Model

**Default Behavior**:
- Every session starts with `tenant_id = NULL` (admin/shared mode)
- Tables have RLS policies filtering by `current_setting('pggit.tenant_id')`
- Admin functions bypass RLS using `SECURITY DEFINER`

**Tenant Isolation**:
- Tenants cannot see other tenants' branches, commits, objects, or history
- Cross-tenant queries return empty results (not errors)
- All core tables have `tenant_id` column with RLS policies

**Backward Compatibility**:
- Existing rows with NULL `tenant_id` are accessible to all (shared/admin rows)
- Existing installations work unchanged (admin mode by default)
- New features opt-in via `pggit.set_tenant()`

---

## Tracking Control

### `pggit.pause_tracking() → VOID`

Disable DDL capture for this session. Use before bulk operations that should
not be recorded.

### `pggit.resume_tracking() → VOID`

Re-enable DDL capture after `pause_tracking()`.

---

## Types

| Type | Values |
|------|--------|
| `pggit.branch_status` | `active`, `merged`, `deleted` |
| `pggit.object_type` | `table`, `view`, `materialized_view`, `function`, `procedure`, `trigger`, `index`, `sequence`, `type`, `domain` |
| `pggit.merge_status` | `pending`, `in_progress`, `completed`, `aborted` |
| `pggit.conflict_status` | `auto_merged`, `conflicted`, `resolved` |

---

## Tables

| Table | Purpose |
|-------|---------|
| `pggit.branches` | Named branches |
| `pggit.commits` | Immutable snapshots forming a DAG |
| `pggit.objects` | Current DDL state per branch (upserted by event trigger) |
| `pggit.history` | Append-only audit log of all DDL events |
| `pggit.merge_history` | One row per merge attempt |
| `pggit.merge_conflicts` | Per-object merge classification and resolution |
| `pggit.tags` | Lightweight named references to commits |

---

## Core Invariant

`pggit.objects.content_hash` is **never NULL**. It is computed synchronously
by the event trigger in the same transaction as the DDL command, using:

```sql
encode(sha256(normalized_ddl::bytea), 'hex')
```

The result is a 64-character lowercase hex string enforced by a CHECK constraint.
