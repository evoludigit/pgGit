# pgGit Development Workflow Guide

This guide explains how to use pgGit effectively in your development process.

## Core Principle

> **Default**: Use pgGit in development, migration tools in production.
>
> **Exception**: For compliance requirements (ISO 27001, SOC 2, DORA, GDPR, NIS2, HIPAA, PCI-DSS, SOX), pgGit in production provides automatic DDL audit trails.

pgGit helps you develop and coordinate schema changes. When those changes are ready, you export them as migrations and deploy via your migration tool of choice.

For production compliance use cases, see [Production Considerations](PRODUCTION_CONSIDERATIONS.md).

---

## Why This Separation?

### Development Needs

- Fast iteration (branch, try, revert)
- Parallel work (multiple features simultaneously)
- Experimentation (without fear of breaking things)
- Coordination (see what others are working on)

### Production Needs

- Stability (no event triggers overhead)
- Auditability (linear migration history)
- Reversibility (explicit UP/DOWN migrations)
- Validation (dry-run, preconditions)

pgGit excels at development needs. Migration tools excel at production needs. Use both for the best of both worlds.

---

## Workflow Patterns

### Pattern 1: Solo Developer

```
Local DB (pgGit)
    │
    ├─ Branch: feature/payments
    │   └─ Add payments table
    │   └─ Add stripe_id to users
    │
    ├─ Merge to main
    │
    └─ Generate migration file
           │
           ▼
Production DB (migration tool)
    └─ Apply migration
```

### Pattern 2: Team Development

```
Developer A (local DB + pgGit)          Developer B (local DB + pgGit)
    │                                        │
    ├─ Branch: feature/payments              ├─ Branch: feature/analytics
    │                                        │
    └─────────────┬──────────────────────────┘
                  │
                  ▼
           Staging DB (pgGit)
                  │
                  ├─ Merge feature/payments
                  ├─ Merge feature/analytics
                  ├─ Detect/resolve conflicts
                  │
                  └─ Generate combined migrations
                         │
                         ▼
                  Production DB
                  └─ Apply migrations (no pgGit)
```

### Pattern 3: AI Agent Coordination

```
Agent A (Claude)                    Agent B (Local Model)
    │                                    │
    ├─ Register intent                   ├─ Register intent
    │   "Adding payments"                │   "Adding analytics"
    │                                    │
    ├─ Branch: feature/payments          ├─ Branch: feature/analytics
    │                                    │
    └─────────────┬──────────────────────┘
                  │
                  ▼
           Coordination Layer
                  │
                  ├─ Detect conflict (both alter users table)
                  ├─ Resolve: combine into single migration
                  │
                  └─ Generate coordinated migrations
                         │
                         ▼
                  Production DB
                  └─ Apply migrations (no pgGit)
```

---

## Setting Up Your Environment

### Local Development Database

```bash
# Create development database (copy of staging schema)
createdb myapp_dev
pg_dump myapp_staging --schema-only | psql myapp_dev

# Install pgGit
psql myapp_dev << 'SQL'
CREATE EXTENSION pggit CASCADE;
SELECT pggit.init();
SQL

# Verify installation
psql myapp_dev -c "SELECT pggit.version();"
```

### Staging Database (Optional)

```bash
# Staging can also have pgGit for merge testing
createdb myapp_staging
# ... restore from production backup ...

psql myapp_staging << 'SQL'
CREATE EXTENSION pggit CASCADE;
SELECT pggit.init();
SQL
```

### Production Database

```bash
# Production does NOT have pgGit
# Migrations are applied via your migration tool

confiture migrate up --env production
# or
flyway migrate
# or
alembic upgrade head
```

---

## Daily Workflow

### Starting a New Feature

```sql
-- 1. Make sure you're on main and up to date
SELECT pggit.checkout('main');

-- 2. Create feature branch
SELECT pggit.create_branch('feature/my-feature');
SELECT pggit.checkout('feature/my-feature');

-- 3. Make schema changes
CREATE TABLE my_new_table (...);
ALTER TABLE users ADD COLUMN new_field TEXT;

-- 4. Check your changes
SELECT * FROM pggit.status();
SELECT * FROM pggit.diff('main', 'feature/my-feature');
```

### Collaborating with Others

```sql
-- See what branches exist
SELECT * FROM pggit.list_branches();

-- See what others are working on
SELECT * FROM pggit.log('feature/other-persons-branch');

-- Check for potential conflicts before merging
SELECT * FROM pggit.diff('main', 'feature/my-feature');
SELECT * FROM pggit.diff('main', 'feature/other-feature');
-- If both modify same tables, coordinate before merging
```

### Merging Your Changes

```sql
-- 1. Switch to main
SELECT pggit.checkout('main');

-- 2. Merge your feature
SELECT pggit.merge('feature/my-feature', 'main');

-- If conflicts:
-- - Review conflicts: SELECT * FROM pggit.conflicts;
-- - Resolve each: SELECT pggit.resolve_conflict(id, 'ours'|'theirs'|'custom', custom_sql);

-- 3. Clean up
SELECT pggit.delete_branch('feature/my-feature');
```

### Generating Migrations

```bash
# Option 1: Using Confiture integration
confiture generate from-branch feature/my-feature --output db/migrations/

# Option 2: Manual migration creation
psql myapp_dev -c "SELECT * FROM pggit.diff('before-feature', 'main');"
# Copy the DDL into your migration file
```

---

## Best Practices

### DO

- Create a branch for each feature/ticket
- Merge to main frequently (avoid long-lived branches)
- Generate migrations before deploying
- Test migrations on staging before production
- Delete branches after merging

### DON'T

- Install pgGit on production databases
- Make direct DDL changes on main branch
- Keep branches open for weeks
- Skip the staging validation step
- Assume merged = deployed

---

## Integration with Migration Tools

### Confiture (Recommended)

```bash
# Confiture has native pgGit integration
confiture branch create feature/x      # Wraps pggit.create_branch
confiture branch merge feature/x main  # Wraps pggit.merge
confiture generate from-branch feature/x  # Generates migration files
confiture migrate up --env production  # Deploys (no pgGit involved)
```

### Flyway / Liquibase / Alembic

```bash
# 1. Get the diff from pgGit
psql myapp_dev -c "SELECT * FROM pggit.diff('main~5', 'main');" > changes.sql

# 2. Create migration file manually
# Flyway: V005__my_feature.sql
# Liquibase: changelog entry
# Alembic: alembic revision --autogenerate

# 3. Deploy via your tool
flyway migrate
# or
liquibase update
# or
alembic upgrade head
```

---

## Troubleshooting

### "I made changes directly on main"

```sql
-- pgGit still tracked them, check the log
SELECT * FROM pggit.log('main', 10);

-- You can still generate migrations from these changes
```

### "Merge conflict I can't resolve"

```sql
-- See all conflicts
SELECT * FROM pggit.conflicts WHERE resolved = false;

-- Option 1: Take one side
SELECT pggit.resolve_conflict(conflict_id, 'ours');  -- or 'theirs'

-- Option 2: Custom resolution
SELECT pggit.resolve_conflict(conflict_id, 'custom',
    'ALTER TABLE users ADD COLUMN combined_field TEXT;');

-- Option 3: Abort and start over
SELECT pggit.abort_merge();
```

### "I want to undo my branch changes"

```sql
-- Switch to main (abandons uncommitted changes)
SELECT pggit.checkout('main');

-- Delete the branch
SELECT pggit.delete_branch('feature/my-mistake', force => true);
```

---

## Summary

| Environment | pgGit? | Purpose |
|-------------|--------|---------|
| Local dev | **Yes** | Branch, experiment, iterate |
| Staging | **Yes** | Test merges, validate workflow |
| Production (standard) | Optional | Migration tools often sufficient |
| Production (compliance) | **Consider** | Audit trails, drift detection, forensics |

pgGit makes development easier. For production, evaluate based on your compliance and audit requirements.

---

## Related Documentation

- [Production Considerations](PRODUCTION_CONSIDERATIONS.md) - When to use pgGit in production
- [Getting Started](../Getting_Started.md) - Initial setup guide
- [User Guide](../USER_GUIDE.md) - Complete feature documentation
- [API Reference](../API_Reference.md) - All functions
