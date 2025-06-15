# pgGit Pattern Examples

Real-world patterns and best practices for using pgGit in your PostgreSQL database.

## Table of Contents

1. [Basic Usage Patterns](#basic-usage-patterns)
2. [Development Workflow](#development-workflow)
3. [Migration Strategies](#migration-strategies)
4. [Dependency Management](#dependency-management)
5. [Monitoring and Auditing](#monitoring-and-auditing)
6. [Advanced Patterns](#advanced-patterns)

## Basic Usage Patterns

### Installing and Verifying

```sql
-- Install the extension
CREATE EXTENSION pg_gitversion;

-- Verify it's working
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_gitversion';

-- Check what's being tracked
SELECT COUNT(*) as tracked_objects FROM gitversion.objects WHERE is_active = true;
```

### Understanding Automatic Tracking

```sql
-- Everything is tracked automatically!
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL
);

-- Immediately check the version
SELECT * FROM gitversion.get_version('public.users');
-- Result: version 1 (1.0.0)

-- Make changes - still automatic
ALTER TABLE users ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

-- Version bumped automatically
SELECT * FROM gitversion.get_version('public.users');
-- Result: version 2 (1.1.0) - minor bump for new column
```

## Development Workflow

### Feature Branch Simulation

```sql
-- Save current state before feature development
CREATE TABLE gitversion.feature_checkpoint AS
SELECT * FROM gitversion.objects WHERE is_active = true;

-- Develop your feature
CREATE TABLE user_preferences (
    user_id INTEGER PRIMARY KEY REFERENCES users(id),
    theme VARCHAR(20) DEFAULT 'light',
    notifications BOOLEAN DEFAULT true
);

ALTER TABLE users ADD COLUMN last_login TIMESTAMP;

-- Review changes made during feature development
SELECT 
    h.change_type,
    o.full_name,
    h.change_description,
    h.created_at
FROM gitversion.history h
JOIN gitversion.objects o ON o.id = h.object_id
WHERE h.created_at > (SELECT MAX(updated_at) FROM gitversion.feature_checkpoint)
ORDER BY h.created_at;

-- If happy, clean up checkpoint
DROP TABLE gitversion.feature_checkpoint;
```

### Development vs Production Sync

```sql
-- Generate migration after development changes
SELECT gitversion.generate_migration(
    'feature_user_preferences',
    'Added user preferences and last login tracking'
);

-- View the generated SQL
SELECT up_script FROM gitversion.migrations 
WHERE version = 'feature_user_preferences';

-- In production, apply the migration
SELECT gitversion.apply_migration('feature_user_preferences');
```

## Migration Strategies

### Incremental Migrations

```sql
-- Strategy: Generate small, focused migrations
-- After each feature is complete:

-- Feature 1: Add user profiles
CREATE TABLE user_profiles (
    user_id INTEGER PRIMARY KEY REFERENCES users(id),
    bio TEXT,
    avatar_url VARCHAR(500)
);

SELECT gitversion.generate_migration('add_user_profiles', 'User profile support');

-- Feature 2: Add messaging
CREATE TABLE messages (
    id SERIAL PRIMARY KEY,
    from_user_id INTEGER NOT NULL REFERENCES users(id),
    to_user_id INTEGER NOT NULL REFERENCES users(id),
    message TEXT NOT NULL,
    sent_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

SELECT gitversion.generate_migration('add_messaging', 'Direct messaging feature');
```

### Batch Migrations

```sql
-- Strategy: Accumulate changes, then generate one migration

-- Make multiple changes...
CREATE TABLE products (id SERIAL PRIMARY KEY, name VARCHAR(200));
CREATE TABLE categories (id SERIAL PRIMARY KEY, name VARCHAR(100));
ALTER TABLE products ADD COLUMN category_id INTEGER REFERENCES categories(id);
CREATE INDEX idx_products_category ON products(category_id);

-- Generate single migration for all changes
SELECT gitversion.generate_migration(
    'ecommerce_foundation',
    'Complete e-commerce schema: products, categories, and relationships'
);
```

### Migration Validation

```sql
-- Before applying a migration in production
-- Review what objects will be affected

-- Get migration details
SELECT 
    version,
    description,
    created_at,
    checksum,
    length(up_script) as script_size
FROM gitversion.migrations
WHERE applied_at IS NULL;

-- Preview impact of changes
WITH migration_objects AS (
    SELECT DISTINCT full_name
    FROM gitversion.objects
    WHERE updated_at > (
        SELECT MAX(created_at) 
        FROM gitversion.migrations 
        WHERE applied_at IS NOT NULL
    )
)
SELECT 
    mo.full_name as changed_object,
    array_agg(d.full_name) as dependent_objects
FROM migration_objects mo
LEFT JOIN gitversion.get_impact_analysis(mo.full_name) d ON true
GROUP BY mo.full_name;
```

## Dependency Management

### Detecting Dependencies

```sql
-- Auto-detect all foreign keys
SELECT gitversion.detect_foreign_keys();

-- Add custom logical dependencies
SELECT gitversion.add_dependency(
    'public.user_reports_view',    -- dependent
    'public.users',                 -- depends on
    'view_dependency'               -- type
);

-- Find all dependencies for a table
SELECT * FROM gitversion.get_impact_analysis('public.users');
```

### Safe Schema Changes

```sql
-- Before dropping or modifying a table, check impact
SELECT * FROM gitversion.get_impact_analysis('public.orders');

-- Get the dependency chain
WITH RECURSIVE dep_chain AS (
    -- Start with the target object
    SELECT 
        d.dependent_id,
        d.depends_on_id,
        o1.full_name as dependent_name,
        o2.full_name as depends_on_name,
        0 as level
    FROM gitversion.dependencies d
    JOIN gitversion.objects o1 ON o1.id = d.dependent_id
    JOIN gitversion.objects o2 ON o2.id = d.depends_on_id
    WHERE o2.full_name = 'public.users'
    
    UNION ALL
    
    -- Recursively find dependents
    SELECT 
        d.dependent_id,
        d.depends_on_id,
        o1.full_name,
        o2.full_name,
        dc.level + 1
    FROM gitversion.dependencies d
    JOIN gitversion.objects o1 ON o1.id = d.dependent_id
    JOIN gitversion.objects o2 ON o2.id = d.depends_on_id
    JOIN dep_chain dc ON dc.dependent_id = d.depends_on_id
)
SELECT DISTINCT dependent_name, level
FROM dep_chain
ORDER BY level, dependent_name;
```

### Circular Dependency Detection

```sql
-- Check all tables for circular dependencies
SELECT 
    o.full_name,
    CASE 
        WHEN gitversion.has_circular_dependency(o.id) 
        THEN 'CIRCULAR DEPENDENCY DETECTED!'
        ELSE 'OK'
    END as status
FROM gitversion.objects o
WHERE o.object_type = 'TABLE' 
AND o.is_active = true;
```

## Monitoring and Auditing

### Schema Change Dashboard

```sql
-- Recent activity summary
WITH daily_stats AS (
    SELECT 
        DATE(created_at) as change_date,
        COUNT(*) as changes,
        COUNT(DISTINCT object_id) as objects_changed,
        COUNT(DISTINCT created_by) as users_active,
        array_agg(DISTINCT change_type::text) as change_types
    FROM gitversion.history
    WHERE created_at > CURRENT_DATE - INTERVAL '30 days'
    GROUP BY DATE(created_at)
)
SELECT * FROM daily_stats ORDER BY change_date DESC;

-- Most active objects
SELECT 
    o.full_name,
    o.version,
    COUNT(h.id) as total_changes,
    MAX(h.created_at) as last_changed
FROM gitversion.objects o
JOIN gitversion.history h ON h.object_id = o.id
WHERE o.is_active = true
GROUP BY o.id, o.full_name, o.version
ORDER BY total_changes DESC
LIMIT 10;
```

### User Activity Tracking

```sql
-- Who's making changes?
SELECT 
    h.created_by as user_name,
    COUNT(*) as total_changes,
    COUNT(DISTINCT DATE(h.created_at)) as active_days,
    COUNT(DISTINCT h.object_id) as objects_modified,
    array_agg(DISTINCT o.object_type::text) as object_types,
    MIN(h.created_at)::date as first_change,
    MAX(h.created_at)::date as last_change
FROM gitversion.history h
JOIN gitversion.objects o ON o.id = h.object_id
GROUP BY h.created_by
ORDER BY total_changes DESC;
```

### Version Drift Detection

```sql
-- Find objects with many versions (might need consolidation)
SELECT 
    object_type,
    full_name,
    version,
    version_string,
    CASE 
        WHEN version > 20 THEN 'High - Consider refactoring'
        WHEN version > 10 THEN 'Medium - Monitor closely'
        ELSE 'Low - Normal evolution'
    END as attention_level
FROM gitversion.objects
WHERE is_active = true
AND object_type = 'TABLE'
ORDER BY version DESC;
```

## Advanced Patterns

### Schema Comparison

```sql
-- Compare two schemas
WITH schema_a AS (
    SELECT object_type, object_name, version
    FROM gitversion.objects
    WHERE schema_name = 'public' AND is_active = true
),
schema_b AS (
    SELECT object_type, object_name, version
    FROM gitversion.objects
    WHERE schema_name = 'archive' AND is_active = true
)
SELECT 
    COALESCE(a.object_type, b.object_type) as object_type,
    COALESCE(a.object_name, b.object_name) as object_name,
    a.version as public_version,
    b.version as archive_version,
    CASE
        WHEN a.object_name IS NULL THEN 'Only in archive'
        WHEN b.object_name IS NULL THEN 'Only in public'
        WHEN a.version = b.version THEN 'Same version'
        WHEN a.version > b.version THEN 'Public is newer'
        ELSE 'Archive is newer'
    END as status
FROM schema_a a
FULL OUTER JOIN schema_b b 
    ON a.object_type = b.object_type 
    AND a.object_name = b.object_name
ORDER BY object_type, object_name;
```

### Metadata Analysis

```sql
-- Analyze column changes across tables
SELECT 
    o.full_name as table_name,
    o.metadata->'columns' as columns,
    jsonb_object_keys(o.metadata->'columns') as column_name
FROM gitversion.objects o
WHERE o.object_type = 'TABLE' 
AND o.is_active = true
AND o.schema_name = 'public';

-- Find all nullable columns that could be NOT NULL
SELECT 
    o.full_name as table_name,
    col.key as column_name,
    col.value->>'type' as data_type
FROM gitversion.objects o,
    jsonb_each(o.metadata->'columns') as col
WHERE o.object_type = 'TABLE' 
AND o.is_active = true
AND (col.value->>'nullable')::boolean = true
AND col.key NOT LIKE '%_at'  -- Exclude timestamp fields
AND col.key NOT LIKE '%_date';
```

### Rollback Strategies

```sql
-- Create a restore point
CREATE TABLE gitversion.restore_point_20240614 AS
SELECT * FROM gitversion.objects WHERE is_active = true;

-- Make changes...
ALTER TABLE users DROP COLUMN last_login;

-- Realize you need to rollback
-- Option 1: Use migration history
SELECT down_script FROM gitversion.migrations
WHERE version = 'remove_last_login';

-- Option 2: Manual restore from point
-- Compare current state with restore point
SELECT 
    r.full_name,
    r.version as restore_version,
    o.version as current_version,
    r.metadata as restore_metadata,
    o.metadata as current_metadata
FROM gitversion.restore_point_20240614 r
JOIN gitversion.objects o ON o.id = r.id
WHERE r.metadata != o.metadata;
```

### Performance Optimization Patterns

```sql
-- Find unused indexes (candidates for removal)
WITH index_usage AS (
    SELECT 
        schemaname,
        tablename,
        indexname,
        idx_scan,
        idx_tup_read,
        idx_tup_fetch
    FROM pg_stat_user_indexes
    WHERE schemaname = 'public'
)
SELECT 
    o.full_name as index_name,
    o.version,
    o.created_at::date as created_date,
    COALESCE(iu.idx_scan, 0) as times_used,
    CASE 
        WHEN COALESCE(iu.idx_scan, 0) = 0 THEN 'UNUSED - Consider dropping'
        WHEN COALESCE(iu.idx_scan, 0) < 100 THEN 'Rarely used'
        ELSE 'Active'
    END as status
FROM gitversion.objects o
LEFT JOIN index_usage iu 
    ON o.full_name = iu.schemaname || '.' || iu.indexname
WHERE o.object_type = 'INDEX'
AND o.is_active = true
ORDER BY COALESCE(iu.idx_scan, 0), o.created_at;
```

### Emergency Procedures

```sql
-- Disable tracking temporarily (use with caution!)
ALTER EVENT TRIGGER gitversion_ddl_trigger DISABLE;
ALTER EVENT TRIGGER gitversion_drop_trigger DISABLE;

-- Make emergency changes...

-- Re-enable tracking
ALTER EVENT TRIGGER gitversion_ddl_trigger ENABLE;
ALTER EVENT TRIGGER gitversion_drop_trigger ENABLE;

-- Manually record what was done
INSERT INTO gitversion.history (
    object_id,
    change_type,
    change_severity,
    old_version,
    new_version,
    change_description,
    sql_executed,
    created_by
)
SELECT 
    id,
    'ALTER'::gitversion.change_type,
    'MAJOR'::gitversion.change_severity,
    version,
    version + 1,
    'Emergency maintenance - manual tracking',
    'See DBA notes',
    CURRENT_USER
FROM gitversion.objects
WHERE full_name = 'public.critical_table';
```

## Best Practices

1. **Regular Dependency Checks**: Run `detect_foreign_keys()` after schema changes
2. **Migration Testing**: Always review migration scripts before applying
3. **Version Monitoring**: Set up alerts for objects with high version numbers
4. **Impact Analysis**: Always check dependencies before dropping objects
5. **Checkpoint Strategy**: Create restore points before major changes
6. **Documentation**: Use COMMENT commands - they're tracked as patches
7. **Cleanup**: Periodically archive old history entries if needed