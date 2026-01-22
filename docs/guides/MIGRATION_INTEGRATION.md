# pgGit Migration Tool Integration

This guide explains how pgGit integrates with migration tools for a complete development-to-production workflow.

## Overview

pgGit handles **development coordination** (branching, merging, experimentation). Migration tools handle **production deployment** (safe, validated, reversible changes).

```
┌─────────────────────────────────────────────────────────────────┐
│                        DEVELOPMENT                              │
│                                                                 │
│   pgGit: Branch, merge, experiment, coordinate                  │
│                           │                                     │
│                           ▼                                     │
│                   Generate migrations                           │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                        PRODUCTION                               │
│                                                                 │
│   Migration Tool: Validate, apply, rollback                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Confiture Integration (Recommended)

[Confiture](https://github.com/fraiseql/confiture) is the official migration tool for the FraiseQL ecosystem with native pgGit integration.

### Setup

```bash
# Install Confiture
pip install fraiseql-confiture

# Initialize in your project
confiture init
```

### Workflow

#### 1. Develop with pgGit

```sql
-- Create feature branch
SELECT pggit.create_branch('feature/user-profiles');
SELECT pggit.checkout('feature/user-profiles');

-- Make schema changes
ALTER TABLE users ADD COLUMN avatar_url TEXT;
ALTER TABLE users ADD COLUMN bio TEXT;
CREATE INDEX idx_users_avatar ON users(avatar_url) WHERE avatar_url IS NOT NULL;

-- Review changes
SELECT * FROM pggit.status();
SELECT * FROM pggit.diff('main', 'feature/user-profiles');
```

#### 2. Generate Migration with Python API

Confiture's `MigrationGenerator` creates production-ready migrations from pgGit branches:

```python
from confiture.integrations.pggit import PgGitClient, MigrationGenerator
from pathlib import Path

# Connect to development database with pgGit
client = PgGitClient(connection)

# Generate migration from branch
generator = MigrationGenerator(client)
migration = generator.generate_from_branch(
    branch_name="feature/user-profiles",
    name="add_user_profile_fields"
)

# Write to migrations directory
migration_path = migration.write_to_file(Path("db/migrations/"))
print(f"Generated: {migration_path}")
```

**Generated migration file** (`db/migrations/20260122143022_001_add_user_profile_fields.py`):
```python
"""add_user_profile_fields

Generated from pgGit branch: feature/user-profiles
Source commits: ['abc123', 'def456']
"""

UP_SQL = """
ALTER TABLE users ADD COLUMN avatar_url TEXT;
ALTER TABLE users ADD COLUMN bio TEXT;
CREATE INDEX idx_users_avatar ON users(avatar_url) WHERE avatar_url IS NOT NULL;
"""

DOWN_SQL = """
DROP INDEX IF EXISTS idx_users_avatar;
ALTER TABLE users DROP COLUMN IF EXISTS bio;
ALTER TABLE users DROP COLUMN IF EXISTS avatar_url;
"""
```

#### 3. Merge in pgGit

```sql
-- Merge feature to main
SELECT pggit.checkout('main');
SELECT pggit.merge('feature/user-profiles', 'main');

-- Clean up
SELECT pggit.delete_branch('feature/user-profiles');
```

#### 4. Deploy to Production

```bash
# Test on staging first
confiture migrate up --env staging

# Deploy to production (no pgGit installed here)
confiture migrate up --env production
```

### Confiture pgGit Python API

Confiture provides a complete Python client for pgGit operations:

```python
from confiture.integrations.pggit import PgGitClient

client = PgGitClient(connection)

# Branch operations
client.create_branch("feature/payments", from_branch="main", copy_data=False)
client.checkout("feature/payments")
client.list_branches(status="ACTIVE")
client.delete_branch("feature/old")

# Commits
client.commit("Add stripe integration")
client.log(branch="main", limit=50)

# Diffs
diff = client.diff("main", "feature/payments")
for entry in diff:
    print(f"{entry.change_type}: {entry.object_name}")

# Merging
result = client.merge("feature/payments", target_branch="main")
if result.has_conflicts:
    for conflict in result.conflicts:
        client.resolve_conflict(conflict.object_name, resolution="ours")
```

### pgGit Detection

Check pgGit availability before using:

```python
from confiture.integrations.pggit import (
    is_pggit_available,
    get_pggit_version,
    require_pggit
)

if is_pggit_available(connection):
    version = get_pggit_version(connection)  # e.g., (0, 1, 2)
    print(f"pgGit {'.'.join(map(str, version))} available")

# Enforce minimum version
require_pggit(connection, min_version=(0, 1, 0))  # Raises if not met
```

---

## Flyway Integration

[Flyway](https://flywaydb.org/) is a popular database migration tool.

### Workflow

#### 1. Develop with pgGit

```sql
-- Same as above: branch, make changes, review
SELECT pggit.create_branch('feature/user-profiles');
SELECT pggit.checkout('feature/user-profiles');
-- ... make changes ...
```

#### 2. Generate Migration Manually

```sql
-- Get the diff as SQL
SELECT pggit.diff_as_sql('main', 'feature/user-profiles');
```

Copy output to Flyway migration file:

```
db/migration/V005__add_user_profile_fields.sql
```

#### 3. Deploy with Flyway

```bash
# Validate migrations
flyway validate

# Apply to production
flyway -url=jdbc:postgresql://prod-host/myapp migrate
```

### Flyway Naming Convention

| pgGit Branch | Flyway File |
|--------------|-------------|
| `feature/user-profiles` | `V005__add_user_profile_fields.sql` |
| `feature/payments` | `V006__add_payments_table.sql` |
| `hotfix/email-index` | `V007__add_email_index.sql` |

---

## Liquibase Integration

[Liquibase](https://www.liquibase.org/) uses XML/YAML/JSON changelogs.

### Workflow

#### 1. Develop with pgGit

```sql
SELECT pggit.create_branch('feature/user-profiles');
SELECT pggit.checkout('feature/user-profiles');
-- ... make changes ...
```

#### 2. Generate Changelog Entry

```sql
-- Get diff
SELECT pggit.diff_as_sql('main', 'feature/user-profiles');
```

Create changelog entry:

```yaml
# db/changelog/changes/005-add-user-profile-fields.yaml
databaseChangeLog:
  - changeSet:
      id: 005-add-user-profile-fields
      author: developer
      comment: "From pgGit branch: feature/user-profiles"
      changes:
        - addColumn:
            tableName: users
            columns:
              - column:
                  name: avatar_url
                  type: TEXT
              - column:
                  name: bio
                  type: TEXT
        - createIndex:
            indexName: idx_users_avatar
            tableName: users
            columns:
              - column:
                  name: avatar_url
            where: "avatar_url IS NOT NULL"
      rollback:
        - dropIndex:
            indexName: idx_users_avatar
        - dropColumn:
            tableName: users
            columnName: bio
        - dropColumn:
            tableName: users
            columnName: avatar_url
```

#### 3. Deploy with Liquibase

```bash
liquibase --url=jdbc:postgresql://prod-host/myapp update
```

---

## Alembic Integration (Python/SQLAlchemy)

[Alembic](https://alembic.sqlalchemy.org/) is the migration tool for SQLAlchemy.

### Workflow

#### 1. Develop with pgGit

```sql
SELECT pggit.create_branch('feature/user-profiles');
SELECT pggit.checkout('feature/user-profiles');
-- ... make changes ...
```

#### 2. Generate Alembic Migration

```bash
# Auto-generate from schema diff
alembic revision --autogenerate -m "add_user_profile_fields"
```

Or manually create from pgGit diff:

```python
# alembic/versions/005_add_user_profile_fields.py
"""add user profile fields

From pgGit branch: feature/user-profiles
"""
from alembic import op
import sqlalchemy as sa

revision = '005'
down_revision = '004'

def upgrade():
    op.add_column('users', sa.Column('avatar_url', sa.Text(), nullable=True))
    op.add_column('users', sa.Column('bio', sa.Text(), nullable=True))
    op.create_index('idx_users_avatar', 'users', ['avatar_url'],
                    postgresql_where=sa.text('avatar_url IS NOT NULL'))

def downgrade():
    op.drop_index('idx_users_avatar')
    op.drop_column('users', 'bio')
    op.drop_column('users', 'avatar_url')
```

#### 3. Deploy with Alembic

```bash
# Upgrade to latest
alembic upgrade head

# Or specific revision
alembic upgrade 005
```

---

## Django Migrations Integration

For Django projects using built-in migrations.

### Workflow

#### 1. Develop with pgGit

Make changes via Django models or raw SQL tracked by pgGit.

#### 2. Generate Django Migration

```bash
# After model changes
python manage.py makemigrations

# Or create empty migration for raw SQL
python manage.py makemigrations --empty myapp
```

#### 3. Add pgGit Diff to Migration

```python
# myapp/migrations/0005_add_user_profile_fields.py
from django.db import migrations

class Migration(migrations.Migration):
    dependencies = [
        ('myapp', '0004_previous'),
    ]

    operations = [
        migrations.RunSQL(
            # From pgGit: SELECT pggit.diff_as_sql('main', 'feature/user-profiles');
            sql="""
                ALTER TABLE users ADD COLUMN avatar_url TEXT;
                ALTER TABLE users ADD COLUMN bio TEXT;
                CREATE INDEX idx_users_avatar ON users(avatar_url) WHERE avatar_url IS NOT NULL;
            """,
            reverse_sql="""
                DROP INDEX IF EXISTS idx_users_avatar;
                ALTER TABLE users DROP COLUMN IF EXISTS bio;
                ALTER TABLE users DROP COLUMN IF EXISTS avatar_url;
            """
        ),
    ]
```

#### 4. Deploy

```bash
python manage.py migrate
```

---

## Best Practices

### 1. Always Generate from Merged State

```sql
-- Good: Generate after merging to main
SELECT pggit.checkout('main');
SELECT pggit.merge('feature/user-profiles', 'main');
-- Then generate migration from main

-- Avoid: Generate from feature branch directly
-- (might miss conflicts with other features)
```

### 2. Include pgGit Reference in Migrations

```sql
-- Migration: add_user_profile_fields
-- Source: pgGit branch feature/user-profiles
-- Commit: abc123def
-- Author: developer@example.com
-- Date: 2026-01-22
```

### 3. Test on Staging with pgGit

```bash
# Staging has pgGit installed
# Apply migration and verify pgGit tracks it correctly
confiture migrate up --env staging

# Check pgGit captured the change
psql staging -c "SELECT * FROM pggit.log() LIMIT 5;"
```

### 4. Handle Conflicts Early

```sql
-- Before generating migration, check for conflicts
SELECT * FROM pggit.diff('main', 'feature/a');
SELECT * FROM pggit.diff('main', 'feature/b');

-- If both modify same objects, coordinate first
```

### 5. Use Consistent Branch Naming

| Branch Pattern | Migration Naming |
|----------------|------------------|
| `feature/X` | `add_X`, `create_X` |
| `fix/X` | `fix_X` |
| `refactor/X` | `refactor_X` |
| `hotfix/X` | `hotfix_X` |

---

## Troubleshooting

### Migration doesn't match pgGit diff

```sql
-- Regenerate diff to verify
SELECT pggit.diff_as_sql('main', 'feature/my-branch');

-- Check branch state
SELECT * FROM pggit.log('feature/my-branch');
```

### Conflicts between migrations

```bash
# Use pgGit to detect before generating
psql dev -c "SELECT * FROM pggit.detect_conflicts('feature/a', 'feature/b');"
```

### Production schema drifted from migrations

```sql
-- If pgGit is installed on production (for compliance)
SELECT * FROM pggit.detect_schema_drift();

-- Compare with expected migration state
SELECT * FROM pggit.diff('migrations_applied', 'actual_schema');
```

---

## Summary

| Tool | Generate Migration | Best For |
|------|-------------------|----------|
| **Confiture** | `confiture generate from-branch` | FraiseQL ecosystem, native integration |
| **Flyway** | Manual from `pggit.diff_as_sql()` | Java/JVM projects |
| **Liquibase** | Manual YAML/XML | Enterprise, multi-DB |
| **Alembic** | `--autogenerate` or manual | Python/SQLAlchemy |
| **Django** | `makemigrations` + RunSQL | Django projects |

pgGit provides the development workflow. Your migration tool provides production safety. Use both.

---

## Related Documentation

- [Development Workflow Guide](DEVELOPMENT_WORKFLOW.md) - pgGit branching and merging
- [Production Considerations](PRODUCTION_CONSIDERATIONS.md) - When to use pgGit in production
- [Confiture Documentation](https://github.com/fraiseql/confiture) - Full Confiture guide
