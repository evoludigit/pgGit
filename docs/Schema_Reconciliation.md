# Schema Reconciliation Best Practices

How to reconcile database schemas between production and development/staging when pg_gitversion is not yet installed.

## Overview

This guide provides a systematic approach to:

1. Analyze differences between two database schemas
2. Install pg_gitversion safely
3. Generate migrations to sync environments
4. Establish ongoing version tracking

## Prerequisites

- Access to both production and development databases
- Ability to install extensions (superuser or appropriate privileges)
- pg_dump and psql tools available

## Step 1: Capture Current Schema State

First, capture the current state of both schemas without installing anything.

### Production Schema Snapshot

```bash
# Dump production schema (structure only, no data)
pg_dump -h prod_host -U prod_user -d prod_db \
  --schema-only \
  --no-owner \
  --no-privileges \
  --no-tablespaces \
  --no-unlogged-table-data \
  -f production_schema.sql

# Also create a detailed catalog dump for comparison
psql -h prod_host -U prod_user -d prod_db <<'EOF' > production_catalog.txt
-- List all tables with columns
\d+ *.*

-- List all indexes
\di+ *.*

-- List all constraints
SELECT conname, contype, conrelid::regclass, confrelid::regclass
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
ORDER BY conrelid::regclass::text, conname;

-- List all views
\dv+ *.*

-- List all functions
\df+ *.*
EOF
```

### Development Schema Snapshot

```bash
# Same for development
pg_dump -h dev_host -U dev_user -d dev_db \
  --schema-only \
  --no-owner \
  --no-privileges \
  --no-tablespaces \
  --no-unlogged-table-data \
  -f development_schema.sql

psql -h dev_host -U dev_user -d dev_db <<'EOF' > development_catalog.txt
-- Same catalog queries as above
\d+ *.*
\di+ *.*
-- ... etc
EOF
```

## Step 2: Analyze Differences

### Manual Diff Analysis

```bash
# Basic diff
diff -u production_schema.sql development_schema.sql > schema_differences.diff

# Or use a more sophisticated tool
git diff --no-index production_schema.sql development_schema.sql > schema_differences_git.diff
```

### SQL-Based Difference Detection

Create a temporary analysis database:

```sql
-- Create analysis database
CREATE DATABASE schema_analysis;
\c schema_analysis

-- Create schemas for comparison
CREATE SCHEMA prod_snapshot;
CREATE SCHEMA dev_snapshot;
```

Load both schemas:

```bash
# Load production schema into prod_snapshot
sed 's/CREATE TABLE/CREATE TABLE prod_snapshot./g' production_schema.sql | \
sed 's/public\./prod_snapshot\./g' | \
psql -d schema_analysis

# Load development schema into dev_snapshot  
sed 's/CREATE TABLE/CREATE TABLE dev_snapshot./g' development_schema.sql | \
sed 's/public\./dev_snapshot\./g' | \
psql -d schema_analysis
```

Now analyze differences:

```sql
-- Find tables only in production
SELECT 
    'Table only in PRODUCTION' as difference,
    table_name
FROM information_schema.tables
WHERE table_schema = 'prod_snapshot'
AND table_name NOT IN (
    SELECT table_name 
    FROM information_schema.tables 
    WHERE table_schema = 'dev_snapshot'
);

-- Find tables only in development
SELECT
    'Table only in DEVELOPMENT' as difference,
    table_name
FROM information_schema.tables
WHERE table_schema = 'dev_snapshot'
AND table_name NOT IN (
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'prod_snapshot'
);

-- Compare columns for tables that exist in both
WITH prod_cols AS (
    SELECT table_name, column_name, data_type, is_nullable, column_default
    FROM information_schema.columns
    WHERE table_schema = 'prod_snapshot'
),
dev_cols AS (
    SELECT table_name, column_name, data_type, is_nullable, column_default
    FROM information_schema.columns
    WHERE table_schema = 'dev_snapshot'
)
SELECT 
    COALESCE(p.table_name, d.table_name) as table_name,
    COALESCE(p.column_name, d.column_name) as column_name,
    CASE
        WHEN p.column_name IS NULL THEN 'NEW in development'
        WHEN d.column_name IS NULL THEN 'MISSING in development'
        WHEN p.data_type != d.data_type THEN 'TYPE CHANGED'
        WHEN p.is_nullable != d.is_nullable THEN 'NULLABLE CHANGED'
        WHEN p.column_default != d.column_default THEN 'DEFAULT CHANGED'
        ELSE 'SAME'
    END as status,
    p.data_type as prod_type,
    d.data_type as dev_type
FROM prod_cols p
FULL OUTER JOIN dev_cols d 
    ON p.table_name = d.table_name 
    AND p.column_name = d.column_name
WHERE p.column_name IS NULL 
   OR d.column_name IS NULL 
   OR p.data_type != d.data_type
   OR p.is_nullable != d.is_nullable
ORDER BY table_name, column_name;
```

## Step 3: Create Reconciliation Plan

Based on the analysis, create a reconciliation plan:

```sql
-- Create a reconciliation tracking table
CREATE TABLE reconciliation_plan (
    id SERIAL PRIMARY KEY,
    environment TEXT NOT NULL CHECK (environment IN ('production', 'development', 'both')),
    object_type TEXT NOT NULL,
    object_name TEXT NOT NULL,
    action_needed TEXT NOT NULL,
    sql_command TEXT,
    priority INTEGER DEFAULT 1000,
    status TEXT DEFAULT 'pending',
    notes TEXT
);

-- Insert reconciliation tasks based on differences
-- Example entries:
INSERT INTO reconciliation_plan (environment, object_type, object_name, action_needed, sql_command, priority) VALUES
('production', 'TABLE', 'users', 'Add missing column', 'ALTER TABLE users ADD COLUMN last_login TIMESTAMP;', 100),
('development', 'TABLE', 'legacy_data', 'Drop obsolete table', 'DROP TABLE legacy_data;', 200),
('production', 'INDEX', 'idx_orders_status', 'Create missing index', 'CREATE INDEX idx_orders_status ON orders(status);', 300);
```

## Step 4: Install pg_gitversion Safely

### Install in Development First

```sql
-- In development database
CREATE EXTENSION pg_gitversion;

-- Verify current state is captured
SELECT COUNT(*) as tracked_objects FROM gitversion.objects WHERE is_active = true;

-- Generate baseline migration
SELECT gitversion.generate_migration(
    'dev_baseline_' || to_char(CURRENT_DATE, 'YYYYMMDD'),
    'Development baseline before reconciliation'
);
```

### Install in Production with Baseline

```sql
-- In production database
BEGIN;

-- Install extension
CREATE EXTENSION pg_gitversion;

-- Verify installation
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_gitversion';

-- Check what was captured
SELECT object_type, COUNT(*)
FROM gitversion.objects
WHERE is_active = true
GROUP BY object_type;

-- If looks good, commit
COMMIT;

-- Generate production baseline
SELECT gitversion.generate_migration(
    'prod_baseline_' || to_char(CURRENT_DATE, 'YYYYMMDD'),
    'Production baseline before reconciliation'
);
```

## Step 5: Reconcile Using pg_gitversion

Now that both environments have pg_gitversion installed:

### Generate Reconciliation Scripts

```sql
-- In development, create reconciliation migration
SELECT gitversion.generate_migration(
    'reconcile_prod_to_dev',
    'Reconciliation migration to sync production with development'
);

-- Extract the migration
\COPY (SELECT up_script FROM gitversion.migrations WHERE version = 'reconcile_prod_to_dev') TO 'reconcile_up.sql';
\COPY (SELECT down_script FROM gitversion.migrations WHERE version = 'reconcile_prod_to_dev') TO 'reconcile_down.sql';
```

### Review and Categorize Changes

```sql
-- Analyze what the migration would do
WITH migration_analysis AS (
    SELECT 
        regexp_split_to_table(up_script, E'\n') as line
    FROM gitversion.migrations 
    WHERE version = 'reconcile_prod_to_dev'
)
SELECT 
    CASE 
        WHEN line ~* '^CREATE TABLE' THEN 'NEW TABLE'
        WHEN line ~* '^DROP TABLE' THEN 'DROP TABLE'
        WHEN line ~* '^ALTER TABLE.*ADD COLUMN' THEN 'NEW COLUMN'
        WHEN line ~* '^ALTER TABLE.*DROP COLUMN' THEN 'DROP COLUMN'
        WHEN line ~* '^CREATE INDEX' THEN 'NEW INDEX'
        WHEN line ~* '^DROP INDEX' THEN 'DROP INDEX'
        ELSE 'OTHER'
    END as change_type,
    COUNT(*) as count
FROM migration_analysis
WHERE line !~ '^\s*$' -- Skip empty lines
GROUP BY change_type
ORDER BY count DESC;
```

### Safe Application Strategy

```sql
-- Create safety script that checks dependencies before applying
CREATE OR REPLACE FUNCTION safe_reconciliation()
RETURNS TABLE(
    step INTEGER,
    description TEXT,
    status TEXT
) AS $$
DECLARE
    v_migration_version TEXT := 'reconcile_prod_to_dev';
    v_can_proceed BOOLEAN := true;
BEGIN
    -- Step 1: Check for blocking dependencies
    RETURN QUERY
    SELECT 
        1,
        'Check dependencies',
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM gitversion.get_impact_analysis('public.users')
                WHERE impact LIKE '%CASCADE%'
            ) THEN 'WARNING: Cascade effects detected'
            ELSE 'OK'
        END;
    
    -- Step 2: Backup critical tables
    RETURN QUERY
    SELECT 
        2,
        'Backup critical tables',
        'Run: pg_dump -t users -t orders -t customers > critical_backup.sql';
    
    -- Step 3: Test migration in transaction
    RETURN QUERY
    SELECT 
        3,
        'Test migration',
        'Run migration in BEGIN/ROLLBACK first';
    
    -- Step 4: Apply for real
    RETURN QUERY
    SELECT 
        4,
        'Apply migration',
        CASE 
            WHEN v_can_proceed THEN 'Ready to apply'
            ELSE 'Cannot proceed - fix issues first'
        END;
END;
$$ LANGUAGE plpgsql;
```

## Step 6: Establish Ongoing Sync Process

### Set Up Regular Comparison

```sql
-- Create comparison view
CREATE VIEW schema_sync_status AS
WITH prod_versions AS (
    SELECT 
        object_type,
        full_name,
        version,
        updated_at
    FROM gitversion.objects
    WHERE is_active = true
    AND schema_name = 'public'
),
last_sync AS (
    SELECT MAX(applied_at) as last_sync_time
    FROM gitversion.migrations
    WHERE version LIKE '%reconcile%'
    AND applied_at IS NOT NULL
)
SELECT 
    pv.object_type,
    pv.full_name,
    pv.version,
    pv.updated_at,
    CASE 
        WHEN pv.updated_at > ls.last_sync_time THEN 'NEEDS SYNC'
        ELSE 'SYNCED'
    END as sync_status
FROM prod_versions pv
CROSS JOIN last_sync ls
ORDER BY sync_status DESC, pv.updated_at DESC;
```

### Automated Drift Detection

```bash
#!/bin/bash
# drift_check.sh - Run this regularly (e.g., via cron)

PROD_DB="postgresql://user@prod_host/prod_db"
DEV_DB="postgresql://user@dev_host/dev_db"

# Check version drift
psql $PROD_DB -t -c "
    SELECT COUNT(*) FROM gitversion.objects 
    WHERE updated_at > (
        SELECT COALESCE(MAX(created_at), '1900-01-01'::timestamp) 
        FROM gitversion.migrations 
        WHERE version LIKE '%sync%'
    )
" > /tmp/prod_changes.txt

psql $DEV_DB -t -c "
    SELECT COUNT(*) FROM gitversion.objects 
    WHERE updated_at > (
        SELECT COALESCE(MAX(created_at), '1900-01-01'::timestamp) 
        FROM gitversion.migrations 
        WHERE version LIKE '%sync%'
    )
" > /tmp/dev_changes.txt

# Alert if drift detected
PROD_CHANGES=$(cat /tmp/prod_changes.txt)
DEV_CHANGES=$(cat /tmp/dev_changes.txt)

if [ $PROD_CHANGES -gt 0 ] || [ $DEV_CHANGES -gt 0 ]; then
    echo "Schema drift detected!"
    echo "Production changes: $PROD_CHANGES"
    echo "Development changes: $DEV_CHANGES"
    # Send alert (email, Slack, etc.)
fi
```

## Best Practices

1. **Always Test First**: Run reconciliation in a test environment
2. **Backup Before Changes**: Keep full backups before major reconciliation
3. **Use Transactions**: Test migrations in BEGIN/ROLLBACK blocks
4. **Document Decisions**: Record why certain differences exist
5. **Monitor After Sync**: Watch for unexpected changes post-reconciliation
6. **Regular Sync Schedule**: Don't let environments drift too far

## Common Pitfalls to Avoid

1. **Data Type Mismatches**: Check for subtle differences (varchar(50) vs text)
2. **Constraint Names**: Different constraint names can cause false positives
3. **Index Names**: Same issue with indexes - focus on structure, not names
4. **Default Values**: NOW() vs CURRENT_TIMESTAMP can appear different
5. **Column Order**: Usually doesn't matter but can complicate diffs

## Emergency Rollback

If reconciliation goes wrong:

```sql
-- Use the down script generated earlier
\i reconcile_down.sql

-- Or restore from backup
pg_restore -d prod_db critical_backup.sql

-- Check state after rollback
SELECT * FROM gitversion.get_recent_changes(50);
```