# Your First Merge: A Complete Tutorial

**Status**: Production-ready
**Version**: v0.1.0
**Last Updated**: December 28, 2025

## Overview

This tutorial walks you through creating your first pgGit merge operation, from creating branches to resolving conflicts. You'll learn:

- Creating and managing branches
- Initiating merge operations
- Understanding merge strategies
- Resolving conflicts
- Verifying merge results

## Prerequisites

- pgGit API running (see `DOCKER_DEPLOYMENT.md` or `QUICKSTART.md`)
- Basic understanding of version control concepts
- `curl` or API client (Postman, Insomnia, etc.)

**Base URL**: `http://localhost:8000` (development)

## Part 1: Creating Branches

### Step 1: Create Source Branch

Let's create a branch for a feature we're working on:

```bash
curl -X POST http://localhost:8000/api/v1/branches \
  -H "Content-Type: application/json" \
  -d '{
    "branch_name": "feature/add-user-table",
    "description": "Adding user authentication table"
  }'
```

**Response** (201 Created):
```json
{
  "branch_id": 101,
  "branch_name": "feature/add-user-table",
  "description": "Adding user authentication table",
  "created_at": "2025-12-28T10:00:00Z",
  "is_active": true
}
```

**Note the `branch_id: 101`** - we'll use this later.

### Step 2: Create Target Branch

Now create the branch we want to merge into (typically `main` or `develop`):

```bash
curl -X POST http://localhost:8000/api/v1/branches \
  -H "Content-Type: application/json" \
  -d '{
    "branch_name": "main",
    "description": "Main production branch"
  }'
```

**Response**:
```json
{
  "branch_id": 100,
  "branch_name": "main",
  "description": "Main production branch",
  "created_at": "2025-12-28T09:00:00Z",
  "is_active": true
}
```

**Note the `branch_id: 100`** - this is our merge target.

### Step 3: Verify Branches

List all branches to confirm:

```bash
curl http://localhost:8000/api/v1/branches
```

**Response**:
```json
{
  "items": [
    {
      "branch_id": 100,
      "branch_name": "main",
      "description": "Main production branch",
      "is_active": true
    },
    {
      "branch_id": 101,
      "branch_name": "feature/add-user-table",
      "description": "Adding user authentication table",
      "is_active": true
    }
  ],
  "total": 2
}
```

## Part 2: Simple Merge (No Conflicts)

### Step 4: Initiate Merge

Merge `feature/add-user-table` (branch 101) into `main` (branch 100):

```bash
curl -X POST http://localhost:8000/api/v1/merge/100/merge \
  -H "Content-Type: application/json" \
  -d '{
    "source_branch_id": 101,
    "merge_message": "Merge feature/add-user-table into main",
    "merge_strategy": "auto"
  }'
```

**Request Parameters**:
- `source_branch_id`: Branch to merge FROM (101 = feature branch)
- Target is in URL path: `/merge/100/` (100 = main branch)
- `merge_message`: Descriptive commit message
- `merge_strategy`: See "Merge Strategies" section below

**Response** (200 OK - Auto-merge successful):
```json
{
  "merge_id": "mrg_abc123def456",
  "status": "completed",
  "conflicts_detected": false,
  "merge_commit_id": 523,
  "message": "Merge completed successfully",
  "created_at": "2025-12-28T10:15:00Z",
  "completed_at": "2025-12-28T10:15:01Z"
}
```

**Success!** The merge completed automatically with no conflicts.

### Step 5: Verify Merge Result

Check the merge status:

```bash
curl http://localhost:8000/api/v1/merge/mrg_abc123def456
```

**Response**:
```json
{
  "merge_id": "mrg_abc123def456",
  "source_branch_id": 101,
  "target_branch_id": 100,
  "merge_base_branch_id": null,
  "status": "completed",
  "merge_strategy": "auto",
  "conflicts_detected": false,
  "merge_commit_id": 523,
  "created_at": "2025-12-28T10:15:00Z",
  "completed_at": "2025-12-28T10:15:01Z"
}
```

## Part 3: Merge with Conflicts

### Step 6: Create Conflicting Changes

Let's create a scenario with conflicts:

```bash
# Create another feature branch
curl -X POST http://localhost:8000/api/v1/branches \
  -H "Content-Type: application/json" \
  -d '{
    "branch_name": "feature/modify-user-table",
    "description": "Modifying user table schema"
  }'
```

Assume this branch (102) modifies the same table as our previous merge, creating a conflict.

### Step 7: Attempt Merge

```bash
curl -X POST http://localhost:8000/api/v1/merge/100/merge \
  -H "Content-Type: application/json" \
  -d '{
    "source_branch_id": 102,
    "merge_message": "Merge feature/modify-user-table into main",
    "merge_strategy": "auto"
  }'
```

**Response** (409 Conflict):
```json
{
  "merge_id": "mrg_xyz789abc012",
  "status": "pending_conflicts",
  "conflicts_detected": true,
  "conflicts": [
    {
      "conflict_id": 1,
      "table_name": "users",
      "conflict_type": "schema_mismatch",
      "source_schema": {...},
      "target_schema": {...},
      "description": "Column 'email' type mismatch: varchar(100) vs varchar(255)"
    }
  ],
  "message": "Merge requires manual conflict resolution",
  "created_at": "2025-12-28T10:20:00Z"
}
```

**Conflict detected!** We need to resolve it manually.

### Step 8: Resolve Conflict

Review the conflict and decide on resolution:

```bash
curl -X POST http://localhost:8000/api/v1/merge/mrg_xyz789abc012/conflicts/1/resolve \
  -H "Content-Type: application/json" \
  -d '{
    "resolution_strategy": "use_source",
    "resolution_notes": "Using source schema (varchar(255)) for better compatibility"
  }'
```

**Resolution Strategies**:
- `use_source`: Accept changes from source branch
- `use_target`: Keep target branch version
- `custom`: Provide custom resolution (requires `custom_schema` field)

**Response** (200 OK):
```json
{
  "conflict_id": 1,
  "resolution_id": "res_123456",
  "resolution_strategy": "use_source",
  "resolution_notes": "Using source schema (varchar(255)) for better compatibility",
  "resolved_at": "2025-12-28T10:22:00Z",
  "resolved_by": "user_id_123"
}
```

### Step 9: Complete Merge

After resolving all conflicts, complete the merge:

```bash
curl -X POST http://localhost:8000/api/v1/merge/mrg_xyz789abc012/complete \
  -H "Content-Type: application/json" \
  -d '{
    "merge_message": "Resolved conflicts and merged feature/modify-user-table"
  }'
```

**Response** (200 OK):
```json
{
  "merge_id": "mrg_xyz789abc012",
  "status": "completed",
  "conflicts_detected": true,
  "conflicts_resolved": 1,
  "merge_commit_id": 524,
  "message": "Merge completed after conflict resolution",
  "created_at": "2025-12-28T10:20:00Z",
  "completed_at": "2025-12-28T10:23:00Z"
}
```

**Success!** Merge completed after manual conflict resolution.

## Part 4: Merge Strategies

pgGit supports multiple merge strategies:

### Auto (Default)

```json
{
  "merge_strategy": "auto"
}
```

**Behavior**:
- Attempts automatic merge
- Succeeds if no conflicts detected
- Returns `pending_conflicts` status if conflicts exist
- **Use when**: Standard merge, most common case

### Three-Way Merge

```json
{
  "merge_strategy": "three-way",
  "base_branch_id": 99
}
```

**Behavior**:
- Uses common ancestor (base branch) for comparison
- Better conflict detection and resolution
- Requires specifying `base_branch_id`
- **Use when**: Complex branch history, need precise conflict detection

### Fast-Forward

```json
{
  "merge_strategy": "fast-forward"
}
```

**Behavior**:
- Only succeeds if target is direct ancestor of source
- No merge commit created (linear history)
- Fails if branches have diverged
- **Use when**: Linear history required, no divergence

### Ours

```json
{
  "merge_strategy": "ours"
}
```

**Behavior**:
- Always uses target branch version on conflict
- Auto-resolves conflicts in favor of target
- **Use when**: Merging experimental branch, want to keep main intact

### Theirs

```json
{
  "merge_strategy": "theirs"
}
```

**Behavior**:
- Always uses source branch version on conflict
- Auto-resolves conflicts in favor of source
- **Use when**: Accepting all changes from source, e.g., hotfix

## Part 5: Advanced Scenarios

### Scenario 1: Aborting a Merge

If you decide not to proceed with a merge:

```bash
curl -X POST http://localhost:8000/api/v1/merge/mrg_xyz789abc012/abort \
  -H "Content-Type: application/json"
```

**Response**:
```json
{
  "merge_id": "mrg_xyz789abc012",
  "status": "aborted",
  "message": "Merge operation aborted",
  "aborted_at": "2025-12-28T10:25:00Z"
}
```

### Scenario 2: Listing Active Merges

View all ongoing merge operations:

```bash
curl http://localhost:8000/api/v1/merge?status=pending_conflicts
```

**Response**:
```json
{
  "items": [
    {
      "merge_id": "mrg_pending123",
      "source_branch_id": 103,
      "target_branch_id": 100,
      "status": "pending_conflicts",
      "conflicts_detected": true,
      "created_at": "2025-12-28T10:30:00Z"
    }
  ],
  "total": 1
}
```

### Scenario 3: Viewing Conflict Details

Get detailed information about a specific conflict:

```bash
curl http://localhost:8000/api/v1/merge/mrg_xyz789abc012/conflicts/1
```

**Response**:
```json
{
  "conflict_id": 1,
  "merge_id": "mrg_xyz789abc012",
  "conflict_type": "schema_mismatch",
  "table_name": "users",
  "column_name": "email",
  "source_schema": {
    "column_name": "email",
    "data_type": "varchar",
    "max_length": 255,
    "nullable": false
  },
  "target_schema": {
    "column_name": "email",
    "data_type": "varchar",
    "max_length": 100,
    "nullable": false
  },
  "description": "Column 'email' type mismatch: varchar(100) vs varchar(255)",
  "resolution_status": "resolved",
  "resolved_at": "2025-12-28T10:22:00Z"
}
```

### Scenario 4: Custom Conflict Resolution

Provide a custom schema to resolve conflicts:

```bash
curl -X POST http://localhost:8000/api/v1/merge/mrg_xyz789abc012/conflicts/1/resolve \
  -H "Content-Type: application/json" \
  -d '{
    "resolution_strategy": "custom",
    "custom_schema": {
      "column_name": "email",
      "data_type": "varchar",
      "max_length": 320,
      "nullable": false,
      "unique": true
    },
    "resolution_notes": "Using RFC 5321 max length (320) for email addresses"
  }'
```

## Part 6: Merge Workflow Patterns

### Pattern 1: Feature Branch Workflow

```bash
# 1. Create feature branch
curl -X POST .../branches -d '{"branch_name": "feature/X"}'

# 2. Work on feature (commits to feature/X)
# ... development happens ...

# 3. Merge to main
curl -X POST .../merge/100/merge -d '{
  "source_branch_id": 101,
  "merge_strategy": "auto",
  "merge_message": "Merge feature/X"
}'

# 4. If conflicts, resolve and complete
curl -X POST .../merge/{merge_id}/conflicts/{conflict_id}/resolve -d {...}
curl -X POST .../merge/{merge_id}/complete
```

### Pattern 2: Hotfix Workflow

```bash
# 1. Create hotfix branch from main
curl -X POST .../branches -d '{"branch_name": "hotfix/critical-bug"}'

# 2. Apply fix (commits to hotfix branch)
# ... fix development ...

# 3. Fast-forward merge (no conflicts expected)
curl -X POST .../merge/100/merge -d '{
  "source_branch_id": 102,
  "merge_strategy": "fast-forward",
  "merge_message": "Hotfix: Critical bug fix"
}'
```

### Pattern 3: Release Branch Workflow

```bash
# 1. Create release branch from develop
curl -X POST .../branches -d '{"branch_name": "release/v1.0"}'

# 2. Prepare release (commits to release/v1.0)
# ... release preparation ...

# 3. Merge to main with three-way strategy
curl -X POST .../merge/100/merge -d '{
  "source_branch_id": 103,
  "base_branch_id": 99,
  "merge_strategy": "three-way",
  "merge_message": "Release v1.0"
}'

# 4. Also merge back to develop
curl -X POST .../merge/104/merge -d '{
  "source_branch_id": 103,
  "merge_strategy": "auto",
  "merge_message": "Merge release/v1.0 back to develop"
}'
```

## Part 7: Best Practices

### ✅ DO

1. **Use descriptive merge messages**
   ```json
   {"merge_message": "Merge feature/user-auth: Add JWT authentication"}
   ```
   Not: `{"merge_message": "merge"}`

2. **Choose appropriate merge strategy**
   - `auto`: Default for most cases
   - `three-way`: Complex histories
   - `fast-forward`: Linear history
   - `ours`/`theirs`: Policy-based auto-resolution

3. **Review conflicts carefully**
   - Read conflict descriptions
   - Understand source vs target schemas
   - Test after resolution

4. **Document conflict resolutions**
   ```json
   {
     "resolution_notes": "Using source schema because it includes new required fields for GDPR compliance"
   }
   ```

5. **Verify merge results**
   - Check merge status after completion
   - Review merge commit
   - Test affected functionality

### ❌ DON'T

1. **Don't merge a branch into itself**
   ```bash
   # ❌ WRONG - will fail
   curl -X POST .../merge/100/merge -d '{"source_branch_id": 100}'
   ```

2. **Don't ignore conflicts**
   - Always resolve conflicts before completing merge
   - Never use `ours`/`theirs` without understanding implications

3. **Don't use fast-forward with diverged branches**
   - Will fail if branches have diverged
   - Use `auto` or `three-way` instead

4. **Don't lose conflict context**
   - Add meaningful `resolution_notes`
   - Document why you chose specific resolution

5. **Don't merge without testing**
   - Test source branch before merging
   - Review changes carefully

## Part 8: Troubleshooting

### Error: "Cannot merge branch into itself"

**Problem**: Source and target are the same branch

**Solution**:
```bash
# Check branch IDs carefully
curl http://localhost:8000/api/v1/branches

# Ensure source_branch_id ≠ target_branch_id
```

### Error: "Concurrent merge operation in progress"

**Problem**: Advisory lock held by another merge

**Solution**:
```bash
# Wait for other merge to complete, or
# Check active merges:
curl http://localhost:8000/api/v1/merge?status=pending_conflicts

# Abort stuck merges if needed:
curl -X POST http://localhost:8000/api/v1/merge/{merge_id}/abort
```

### Error: "Fast-forward merge not possible"

**Problem**: Branches have diverged

**Solution**:
```bash
# Use a different strategy
curl -X POST .../merge/100/merge -d '{
  "source_branch_id": 101,
  "merge_strategy": "auto"  # Changed from fast-forward
}'
```

### Error: "Invalid merge strategy"

**Problem**: Typo in strategy name

**Valid strategies**:
- `auto`
- `three-way`
- `fast-forward`
- `ours`
- `theirs`

## Part 9: API Reference Quick Links

### Merge Operations
- `POST /api/v1/merge/{target_id}/merge` - Initiate merge
- `GET /api/v1/merge/{merge_id}` - Get merge status
- `GET /api/v1/merge` - List merges
- `POST /api/v1/merge/{merge_id}/complete` - Complete merge after resolving conflicts
- `POST /api/v1/merge/{merge_id}/abort` - Abort merge

### Conflict Resolution
- `GET /api/v1/merge/{merge_id}/conflicts` - List conflicts
- `GET /api/v1/merge/{merge_id}/conflicts/{conflict_id}` - Get conflict details
- `POST /api/v1/merge/{merge_id}/conflicts/{conflict_id}/resolve` - Resolve conflict

### Branch Management
- `POST /api/v1/branches` - Create branch
- `GET /api/v1/branches` - List branches
- `GET /api/v1/branches/{branch_id}` - Get branch details

## Next Steps

1. **Try the examples** in this tutorial with your own data
2. **Read the API documentation** (`API.md`) for complete endpoint reference
3. **Review merge strategies** to understand which fits your workflow
4. **Set up automated merges** via CI/CD pipelines
5. **Monitor merge operations** using health checks and logging

## Support

For issues or questions:
- API Documentation: See `API.md`
- Deployment Guide: See `DOCKER_DEPLOYMENT.md`
- Health Check: `GET /health/deep`
- GitHub Issues: <repository-url>/issues

---

**Congratulations!** You've completed your first pgGit merge. You now understand:
- ✅ Creating and managing branches
- ✅ Initiating merge operations
- ✅ Handling merge conflicts
- ✅ Different merge strategies
- ✅ Best practices and troubleshooting
