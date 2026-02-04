# pgGit Architecture: Schema Version Control for PostgreSQL

## Overview

pgGit is a PostgreSQL extension that enables git-like version control for database schemas. Developers can create branches, make schema changes, merge branches, detect conflicts, and diff schemas—all within PostgreSQL.

**Phase 1 focuses exclusively on schema VCS:** branching, merging, and diffing. Data branching, temporal queries, and storage optimization are deferred to future phases.

---

## The Core Problem: PostgreSQL Plan Caching

### The Challenge

PostgreSQL compiles and caches query execution plans. When you reference a table in SQL:

```sql
SELECT * FROM users;
```

PostgreSQL resolves `users` at **compile time** (when the query is parsed), not runtime.

For version control to work, we need the same table reference to point to **different physical tables** depending on which branch is active. But if the table reference is resolved at parse time, we can't dynamically switch which table we're pointing to.

### The Solution: View-Based Routing

Instead of direct table references, pgGit uses **views with dynamic SQL routing**:

```sql
-- Public schema has VIEWs (not tables)
CREATE VIEW public.users AS
EXECUTE pggit._route_to_table('users', pggit.current_branch());

-- This forces runtime routing:
-- - If branch = 'main' → routes to pggit_base.users
-- - If branch = 'feature' → routes to pggit_branch_feature.users
```

By using `EXECUTE` statements in views, we force PostgreSQL to **defer table resolution until runtime**, enabling dynamic branch switching.

---

## Architecture: Schema Separation

pgGit organizes data across multiple PostgreSQL schemas:

```
pggit (internal metadata)
├── branches
│   ├── id
│   ├── name (main, feature/new-api, etc.)
│   ├── parent_branch_id
│   ├── head_commit_hash
│   └── created_at
├── commits
│   ├── hash
│   ├── branch_id
│   ├── message
│   ├── author
│   └── timestamp
├── versioned_objects (tables we're tracking)
└── version_history (which version is current)

pggit_base (main branch physical tables)
├── users (actual table)
├── products (actual table)
└── orders (actual table)

pggit_branch_* (feature branch physical tables)
├── pggit_branch_feature.users
├── pggit_branch_feature.products
└── pggit_branch_feature.orders

public (VIEWs that route to correct branch)
├── users (VIEW → pggit_base.users OR pggit_branch_*.users)
├── products (VIEW → pggit_base.products OR pggit_branch_*.products)
└── orders (VIEW → pggit_base.orders OR pggit_branch_*.orders)
```

### Why Schema Separation?

1. **Isolation**: Branch data is physically isolated; no risk of accidentally mixing branches
2. **Extensibility**: Phases 2+ can add new metadata without touching existing tables
3. **Performance**: Each branch can have independent indexes, statistics, and query plans
4. **Recoverability**: Corrupted branch can be recovered without affecting others

---

## How It Works: The Routing Mechanism

### Current Branch Context

pgGit tracks the current branch in a **connection-level variable** (using PostgreSQL's GUC system):

```sql
-- User creates a branch
SELECT pggit.create_branch('feature/new-api', 'main');

-- User switches to branch
SELECT pggit.switch_branch('feature/new-api');

-- Internally: Sets pggit.current_branch = 'feature/new-api'
-- All subsequent queries route to pggit_branch_feature schema
```

### View-Based Routing in Action

Every user table becomes a view:

```sql
-- Before: SELECT * FROM users;
--         (resolves to pggit_base.users at compile time)

-- After: SELECT * FROM users;
--        (view dynamically routes based on current branch)

CREATE OR REPLACE VIEW public.users AS
SELECT * FROM pggit._route_to_branch(
    'users',
    pggit.current_branch()
);

-- The pggit._route_to_branch() function uses EXECUTE:
FUNCTION pggit._route_to_branch(table_name text, branch text)
RETURNS TABLE (...) AS $$
BEGIN
    RETURN QUERY EXECUTE format(
        'SELECT * FROM %I.%I',
        'pggit_' || branch,  -- e.g., 'pggit_main' or 'pggit_feature'
        table_name           -- e.g., 'users'
    );
END;
```

---

## Phase 1 Operations: Schema VCS

### 1. Create Branch

```sql
SELECT pggit.create_branch('feature/users-api', 'main');
```

**What happens:**
- Creates new schema `pggit_branch_users_api`
- Copies all table definitions from `pggit_base` to new schema
- Copies all data from `pggit_base` to new schema (copy-on-write semantics planned for Phase 4)
- Records branch in `pggit.branches` table

### 2. Switch Branch

```sql
SELECT pggit.switch_branch('feature/users-api');
```

**What happens:**
- Sets `pggit.current_branch = 'feature/users-api'`
- All subsequent queries route through views to `pggit_branch_users_api` schema
- User makes schema changes as normal:
  ```sql
  ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT false;
  CREATE INDEX idx_users_email ON users(email);
  ```
- Changes only affect the feature branch, not main

### 3. Merge Branches

```sql
SELECT pggit.merge('feature/users-api', 'main');
```

**What happens:**
- Detects conflicts between branch schemas:
  - Tables added in one but not other
  - Columns added/removed/modified
  - Constraint changes
- Returns conflicts for manual resolution, or auto-merges if compatible
- Copies resolved changes from source to target branch
- Records merge in `pggit.merge_history` table

### 4. Schema Diffing

```sql
SELECT * FROM pggit.schema_diff('main', 'feature/users-api');
```

**What happens:**
- Compares schema definitions between branches
- Returns structured diff showing what changed:
  ```
  change_type | object_type | object_name | sql_to_sync
  ━━━━━━━━━━━━┿━━━━━━━━━━━━┿━━━━━━━━━━━━┿━━━━━━━━━━━━
  added       | TABLE       | posts       | CREATE TABLE posts ...
  removed     | COLUMN      | users.bio   | ALTER TABLE users DROP COLUMN bio
  modified    | CONSTRAINT  | users.pk    | ALTER TABLE users DROP CONSTRAINT pk ...
  ```
- Can generate complete SQL patch to sync one branch to another

---

## Extensibility: How Phases 2+ Build On Phase 1

### Context System (Designed for Extensibility)

Phase 1 uses a minimal context:
```sql
context = { branch: 'main' }
```

This is intentionally designed to expand:

**Phase 2 - Temporal Queries:**
```sql
context = {
    branch: 'main',
    timestamp: '2024-01-15 10:00:00'  -- Time-travel added
}
```

**Phase 3 - Compliance Auditing:**
```sql
context = {
    branch: 'main',
    timestamp: '2024-01-15 10:00:00',
    audit_version: 'v1'  -- Audit layer added
}
```

**Phase 4 - Storage Optimization:**
```sql
context = {
    branch: 'main',
    timestamp: '2024-01-15 10:00:00',
    audit_version: 'v1',
    optimization: 'copy-on-write'  -- Copy-on-write tracking
}
```

Each phase adds new context fields without breaking existing code.

### Schema Separation Enables Independent Evolution

Because each layer has its own schema namespace:

- Phase 2 can add temporal tracking tables without touching Phase 1 tables
- Phase 3 can add audit tables without touching Phases 1-2
- Phase 4 can add optimization metadata without affecting others

---

## Phase 1 Limitations (By Design)

These features are explicitly deferred to future phases:

| Feature | Why Deferred | Phase |
|---------|-------------|-------|
| Data branching | Requires copy-on-write infrastructure | 2+ |
| Temporal queries | Needs timestamp tracking in all branches | 2 |
| Compliance auditing | Requires immutable audit log layer | 3 |
| Storage optimization | Needs deduplication infrastructure | 4 |
| Time-travel recovery | Requires temporal tracking | 2+ |
| Zero-copy branches | Needs filesystem-level integration | 4+ |

**This focus on schema VCS only enables:**
- Rapid development and user feedback
- Clear scope for Phase 1 (Feb-July 2026)
- Market validation before expanding

---

## Performance Characteristics

### Expected Overhead

- **View routing**: 5-10% query execution overhead (EXECUTE vs direct access)
- **Branch switching**: < 1ms (just updates GUC variable)
- **Merge operations**: O(n) where n = number of schema objects (typically < 100)
- **Schema diffing**: O(n²) in worst case, but fast for typical schemas (< 100 objects)

### Optimization Opportunities (Future Phases)

- Copy-on-write data to avoid full copies on branch creation (Phase 4)
- Materialized views for frequently-accessed branches (Phase 2+)
- Parallel merge operations (Phase 2+)
- Index-only scans on branch schemas (Phase 3+)

---

## Security Considerations

### Phase 1 Scope

pgGit does not provide:
- Role-based access control (planned Phase 2)
- Audit logging (planned Phase 3)
- Encryption at rest (planned Phase 5)
- Permission enforcement between branches

### Current Best Practice

- Run pgGit in trusted environments only (internal databases)
- Restrict schema access via PostgreSQL role permissions
- Assume all users with pgGit access can see all branch data
- No secrets should be stored in schemas being versioned

---

## Summary

pgGit's architecture consists of:

1. **Problem Solving**: View-based routing overcomes PostgreSQL's compile-time table resolution
2. **Schema Separation**: Four namespaces (pggit, pggit_base, pggit_branch_*, public) keep concerns separated
3. **Phase 1 Focus**: Branch, switch, merge, diff operations only
4. **Extensible Design**: Context system and schema namespaces support Phases 2-6 without changes to Phase 1 API
5. **Performance**: Acceptable 5-10% overhead for development workflows
6. **Simple Model**: No complex state management, just physical schema copies and GUC tracking

This architecture enables rapid Phase 1 validation while providing a solid foundation for expansion.

---

## Further Reading

- [Getting Started](./Getting_Started.md) - Quick start guide
- [USER_GUIDE.md](./USER_GUIDE.md) - Step-by-step usage examples
- [API_Reference.md](./API_Reference.md) - Complete function reference
