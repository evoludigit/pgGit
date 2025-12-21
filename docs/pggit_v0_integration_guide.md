# pgGit v0 Integration Guide

**Date**: December 21, 2025
**Version**: 1.0 - Week 4 Greenfield Features
**Status**: Ready for Production

---

## Introduction

This guide shows developers how to use pgGit v0 for schema versioning, change tracking, and collaborative development. All examples are copy-paste ready and use the functions/views created in Week 4.

## Table of Contents

1. [Basic Operations](#basic-operations)
2. [Workflow Patterns](#workflow-patterns)
3. [Audit & Compliance](#audit--compliance)
4. [Integration with Apps](#integration-with-apps)
5. [Common Recipes](#common-recipes)
6. [Troubleshooting](#troubleshooting)

---

## Basic Operations

### Getting Started: Check Your Current Schema

See what objects are in the current (HEAD) version:

```sql
-- View all objects in current schema
SELECT * FROM pggit_v0.get_current_schema();

-- Quick summary
SELECT object_type, COUNT(*) as count
FROM pggit_v0.get_current_schema()
GROUP BY object_type
ORDER BY count DESC;
```

**Output**: Lists all tables, functions, views, indices, and other objects with their types and who created them.

### List All Objects at a Specific Point in Time

```sql
-- See schema as it was in a specific commit
SELECT * FROM pggit_v0.list_objects('a1b2c3d4e5f6...');

-- Same as above, but for HEAD (current)
SELECT * FROM pggit_v0.list_objects(NULL);
```

**Use case**: Audit what was in the schema 2 weeks ago, understand historical state.

### Get Object Definition

Retrieve the exact DDL for any object at any point in history:

```sql
-- Get current definition of a table
SELECT pggit_v0.get_object_definition('public', 'users');

-- Get how it looked in a specific commit
SELECT pggit_v0.get_object_definition('public', 'users', 'a1b2c3d4e5f6...');

-- Use the result to restore or document
\copy (SELECT pggit_v0.get_object_definition('public', 'users')) TO 'users_table.sql'
```

**Use case**: Get exact DDL for documentation, reproduction, or restoration.

### Get Object Metadata

Understand an object's history and current state:

```sql
-- Who last changed this function? When? What's its size?
SELECT * FROM pggit_v0.get_object_metadata('public', 'process_payment');

-- Track over time
SELECT *, pggit_v0.get_object_metadata('public', 'orders')
FROM pggit_v0.get_object_metadata('public', 'orders');
```

**Use case**: Compliance reporting, understanding who touched what and when.

---

## Workflow Patterns

### Pattern 1: Feature Branch Workflow

Standard feature branch development for schema changes:

```sql
-- 1. Create a feature branch from HEAD
SELECT pggit_v0.create_branch('feature/add-user-notifications');
-- Returns commit SHA this branch is based on

-- 2. Do your work on this branch (in your own environment/PR)
-- (In a real system, you'd make changes, test, commit them)

-- 3. See what changed in your branch vs main
SELECT * FROM pggit_v0.diff_branches('main', 'feature/add-user-notifications');
-- Shows: which tables/functions changed, old vs new definitions

-- 4. Merge when ready (Week 5 feature)
-- For now, you'd review the diff and approve manually

-- 5. Clean up after merging
SELECT pggit_v0.delete_branch('feature/add-user-notifications');
```

**Timeline**:
- Create branch: seconds
- Development: hours/days
- Review diffs: minutes
- Delete after merge: seconds

### Pattern 2: Release Branching

Create stable release branches:

```sql
-- Create release branch from current stable state
SELECT pggit_v0.create_branch('release/v2.1.0');

-- Work on release-specific hotfixes
SELECT * FROM pggit_v0.diff_branches('release/v2.1.0', 'main');

-- Compare all release branches
SELECT * FROM pggit_v0.branch_comparison
WHERE branch_name LIKE 'release/%'
ORDER BY head_commit_time DESC;
```

**Use case**: Parallel release and development work.

### Pattern 3: Hotfix Procedures

Quick emergency fixes:

```sql
-- Create hotfix branch from last production commit
-- (assume 'production' tag points to deployed version)
SELECT pggit_v0.create_branch(
    'hotfix/critical-index-missing',
    (SELECT commit_sha FROM pggit_v0.refs WHERE ref_name = 'production' AND ref_type = 'tag')
);

-- Make fix, test thoroughly

-- See exactly what changed
SELECT * FROM pggit_v0.diff_branches('hotfix/critical-index-missing', 'main');

-- Deploy and verify

-- Merge back to main (Week 5)

-- Clean up
SELECT pggit_v0.delete_branch('hotfix/critical-index-missing');
```

**Timeline**: Minutes for critical fixes.

### Pattern 4: Multiple Parallel Development Tracks

Support multiple teams working independently:

```sql
-- Team A: Analytics feature
SELECT pggit_v0.create_branch('feature/analytics-schema');

-- Team B: Payment system upgrade
SELECT pggit_v0.create_branch('feature/payment-v3');

-- Team C: Performance optimization
SELECT pggit_v0.create_branch('feature/query-optimization');

-- Check all active branches
SELECT * FROM pggit_v0.list_branches()
ORDER BY created_at DESC;

-- Track individual progress
SELECT * FROM pggit_v0.diff_branches('feature/analytics-schema', 'main');
SELECT * FROM pggit_v0.diff_branches('feature/payment-v3', 'main');
SELECT * FROM pggit_v0.diff_branches('feature/query-optimization', 'main');
```

**Benefit**: Non-blocking parallel development.

---

## Audit & Compliance

### View Commit History (Like Git Log)

```sql
-- See recent commits (last 20)
SELECT * FROM pggit_v0.get_commit_history();

-- Page through history
SELECT * FROM pggit_v0.get_commit_history(10, 20);  -- 10 commits, offset 20

-- Find who did what when
SELECT
    author,
    message,
    committed_at
FROM pggit_v0.get_commit_history()
WHERE message ILIKE '%payment%'
ORDER BY committed_at DESC;
```

**Output**: Git-style commit log with author, message, timestamp.

### Track Object Changes

See the history of changes to a specific object:

```sql
-- How many times was this table changed?
SELECT * FROM pggit_v0.get_object_history('public', 'users', 20);

-- When was it last modified?
SELECT * FROM pggit_v0.get_object_history('public', 'users', 1);

-- Full audit trail for compliance
SELECT
    commit_sha,
    change_type,
    author,
    committed_at,
    message
FROM pggit_v0.get_object_history('public', 'users', 100)
ORDER BY committed_at DESC;
```

**Use case**: Audit trail for compliance, change justification, impact analysis.

### Developer Activity Report

Who's been most active?

```sql
-- See developer stats
SELECT * FROM pggit_v0.recent_commits_by_author;

-- Activity by date
SELECT * FROM pggit_v0.author_activity
WHERE author = 'alice@example.com'
ORDER BY activity_date DESC
LIMIT 30;

-- What did each developer change?
SELECT
    author,
    schemas_touched,
    objects_modified,
    commits
FROM pggit_v0.author_activity
GROUP BY author
ORDER BY COUNT(*) DESC;
```

**Use case**: Team insights, performance review, load balancing.

### Compliance Checks

Data quality and governance:

```sql
-- Are all commits documented?
SELECT COUNT(*) as undocumented_commits
FROM pggit_v0.commits_without_message;

-- Too many changes in one commit? (refactoring red flag)
SELECT * FROM pggit_v0.large_commits
LIMIT 10;

-- Orphaned objects (cleanup opportunities)
SELECT * FROM pggit_v0.orphaned_objects;

-- Schema growth (capacity planning)
SELECT * FROM pggit_v0.schema_growth_history
LIMIT 30;
```

**Use case**: Governance, capacity planning, data quality.

---

## Integration with Apps

### Check Schema Version in Your App

At startup or in healthchecks:

```python
# Python example
import psycopg

def get_schema_version():
    """Get current pggit_v0 HEAD commit SHA"""
    with psycopg.connect("dbname=myapp") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT pggit_v0.get_head_sha()")
            return cur.fetchone()[0]

# Use in app
schema_version = get_schema_version()
app_config['schema_version'] = schema_version
logger.info(f"App started with schema {schema_version}")
```

**Use case**: Verify schema compatibility, ensure all instances use same schema.

### Validate Migration Success

After deploying a schema change:

```sql
-- Check what changed in this deployment
SELECT * FROM pggit_v0.diff_commits(
    'last_known_good_sha',
    'current_head_sha'
);

-- Verify all expected objects exist
SELECT
    schema_name,
    object_name,
    object_type
FROM pggit_v0.get_current_schema()
WHERE object_name IN ('new_table_1', 'new_table_2', 'new_function')
ORDER BY schema_name, object_name;

-- Show summary
SELECT object_type, COUNT(*) as count
FROM pggit_v0.get_current_schema()
GROUP BY object_type;
```

**Use case**: Post-deployment validation, migration verification.

### CI/CD Integration: Pre-Deployment Checks

```sql
-- Check if any undocumented commits would be deployed
SELECT COUNT(*) as undocumented
FROM pggit_v0.get_commit_history()
WHERE message IS NULL OR TRIM(message) = ''
LIMIT 1;

-- Flag large commits (might need extra testing)
SELECT COUNT(*) as large_commits
FROM pggit_v0.large_commits;

-- Verify no orphaned objects
SELECT COUNT(*) as orphaned
FROM pggit_v0.orphaned_objects;

-- Only proceed if all checks pass
-- If any above returns > 0, block deployment
```

**Use case**: Automated pipeline gates, quality assurance.

### Rollback to Known Good State

When something breaks:

```sql
-- What was the last good commit?
SELECT commit_sha FROM pggit_v0.get_commit_history(1)
WHERE committed_at < '2025-12-20 15:00:00'::timestamp;

-- Show what would be reverted
SELECT * FROM pggit_v0.diff_commits(
    'bad_commit_sha',
    'last_good_commit_sha'
);

-- In a real system:
-- 1. Get DDL from last good state
SELECT pggit_v0.get_object_definition('public', 'users', 'last_good_commit_sha');
-- 2. Apply that DDL to database
-- 3. Update pggit_v0 refs to point to good commit
```

**Use case**: Emergency recovery from bad deployments.

---

## Common Recipes

### Recipe 1: "What Changed Since Yesterday?"

```sql
-- Find all changes in last 24 hours
SELECT
    cg.committed_at,
    cg.author,
    cg.message,
    c.object_schema || '.' || c.object_name as object,
    c.change_type
FROM pggit_v0.commit_graph cg
JOIN pggit_audit.changes c ON c.commit_sha = cg.commit_sha
WHERE cg.committed_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
ORDER BY cg.committed_at DESC;
```

**Output**: Timeline of changes, who made them, what changed.

### Recipe 2: "Who Modified This Table?"

```sql
-- Get full history
SELECT
    pog.author,
    pog.committed_at,
    pog.message,
    poc.change_type
FROM pggit_v0.get_object_history('public', 'orders') poc
ORDER BY pog.committed_at DESC;

-- Just the most recent
SELECT
    author,
    committed_at,
    message
FROM pggit_v0.get_object_history('public', 'orders', 1);
```

**Output**: Who and when for audit trail.

### Recipe 3: "Can We Merge These Branches?"

```sql
-- Check for conflicts (objects modified in both)
SELECT
    object_path,
    COUNT(*) as times_modified
FROM (
    SELECT DISTINCT object_path, 'branch1' as branch
    FROM pggit_v0.diff_branches('feature/branch1', 'main')

    UNION ALL

    SELECT DISTINCT object_path, 'branch2' as branch
    FROM pggit_v0.diff_branches('feature/branch2', 'main')
) changes
GROUP BY object_path
HAVING COUNT(*) > 1;  -- Modified in both branches = potential conflict

-- If empty result set: safe to merge!
-- If conflicts found: need manual review before merging
```

**Output**: Objects that would conflict if both branches merged.

### Recipe 4: "Show Me the Impact of This Change"

```sql
-- What changed in this commit?
SELECT
    object_schema || '.' || object_name as object,
    change_type,
    LENGTH(old_definition) as old_size,
    LENGTH(new_definition) as new_size
FROM pggit_audit.changes
WHERE commit_sha = 'commit_sha_to_analyze'
ORDER BY object_name;

-- Count by type
SELECT
    change_type,
    COUNT(*) as count
FROM pggit_audit.changes
WHERE commit_sha = 'commit_sha_to_analyze'
GROUP BY change_type;
```

**Output**: What changed, how big the changes are, types of operations.

### Recipe 5: "Find Related Changes"

```sql
-- When was this table last modified?
SELECT
    commit_sha,
    change_type,
    author,
    committed_at
FROM pggit_v0.get_object_history('public', 'users', 1);

-- What else changed in that commit?
SELECT
    object_schema || '.' || object_name as other_object,
    change_type
FROM pggit_audit.changes
WHERE commit_sha = (
    SELECT commit_sha
    FROM pggit_v0.get_object_history('public', 'users', 1)
)
AND object_name != 'users';
```

**Output**: Related changes in same commit, understand context.

---

## Troubleshooting

### Issue: "Function pggit_v0.get_current_schema() not found"

**Solution**: Load the developer functions first:
```sql
-- From pggit_v0_developers.sql
\i sql/pggit_v0_developers.sql
```

### Issue: "Commit SHA not found"

**Solution**: Use a valid SHA from history:
```sql
-- List valid commits
SELECT commit_sha, committed_at, message
FROM pggit_v0.get_commit_history();
```

### Issue: "Branch already exists"

**Solution**: Delete first or use different name:
```sql
SELECT pggit_v0.delete_branch('feature/existing-name');
-- OR
SELECT pggit_v0.create_branch('feature/new-name');
```

### Issue: "Cannot delete main branch"

**Solution**: This is protected. Create different branch or work on a copy:
```sql
-- Create a working branch from main
SELECT pggit_v0.create_branch('feature/temp-work');
```

### Issue: "No data in views"

**Solution**: Data comes from pggit_audit layer. Ensure audit was populated:
```sql
-- Check if audit data exists
SELECT COUNT(*) FROM pggit_audit.changes;

-- If empty, backfill from commits (Week 5 feature)
```

---

## Best Practices

1. **Always Add Commit Messages**: Required for compliance and debugging
   ```sql
   -- Good message (from your VCS/app)
   "Add user notification preferences table with indices"

   -- Bad message
   "Updated schema" or NULL
   ```

2. **Create Feature Branches**: Never commit directly to main
   ```sql
   SELECT pggit_v0.create_branch('feature/my-change');
   ```

3. **Review Diffs Before Merging**: Understand impact
   ```sql
   SELECT * FROM pggit_v0.diff_branches('feature/my-change', 'main');
   ```

4. **Monitor Large Commits**: Might indicate refactoring that needs testing
   ```sql
   SELECT * FROM pggit_v0.large_commits;
   ```

5. **Regular Cleanup**: Delete merged branches
   ```sql
   SELECT pggit_v0.delete_branch('feature/completed-work');
   ```

6. **Document Changes**: Good commit messages help future maintainers
   ```sql
   -- Instead of "update"
   -- Use "Add column email_verified to users table for 2FA support"
   ```

---

## Next Steps: Week 5 Features

- **Branching & Merging**: Automated conflict detection and merge strategies
- **Analytics**: Performance metrics, storage analysis, health checks
- **Monitoring**: Alert functions, recommendations, dashboard-ready data

---

## Summary

This guide covered:
- ✅ Basic operations (list, view, get definitions)
- ✅ Workflow patterns (feature branches, releases, hotfixes)
- ✅ Audit & compliance (history, changes, activity)
- ✅ App integration (version checking, validation, rollback)
- ✅ Common recipes (what changed, who touched what, conflicts)
- ✅ Troubleshooting (common issues and solutions)

All examples are copy-paste ready. Start with Recipe 1 ("What Changed Since Yesterday?") to see pgGit v2 in action!

---

*pgGit v2 Integration Guide - Week 4 Greenfield Features*
*Ready for production developer use*
