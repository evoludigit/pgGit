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

---

## Core Invariant

`pggit.objects.content_hash` is **never NULL**. It is computed synchronously
by the event trigger in the same transaction as the DDL command, using:

```sql
encode(sha256(normalized_ddl::bytea), 'hex')
```

The result is a 64-character lowercase hex string enforced by a CHECK constraint.
