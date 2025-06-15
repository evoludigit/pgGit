# DDL Hashing Usage Guide

How to use the new hash-based change detection features in pggit.

## Overview

DDL hashing adds efficient change detection to pggit by computing SHA-256
hashes of normalized database object definitions. This enables:

- **Fast change detection**: O(1) hash comparison vs. O(n) DDL comparison
- **Efficient storage**: Store 64-character hashes instead of full DDL
- **Cross-database sync**: Compare schemas by exchanging hash catalogs
- **False positive elimination**: Only track real semantic changes

## Installation

The hashing functionality is an add-on to the base pg_gitversion extension:

```sql
-- Install base extension first
CREATE EXTENSION pg_gitversion;

-- Load hashing functionality
\i sql/009_ddl_hashing.sql

-- Update existing objects with hashes
SELECT * FROM pggit.update_all_hashes();
```

## Core Concepts

### Hash Types

1. **DDL Hash**: Complete object definition hash
2. **Structure Hash**: Table columns only (for tables)
3. **Constraints Hash**: All constraints (for tables)
4. **Indexes Hash**: All indexes (for tables)

### Normalization

The system normalizes DDL before hashing to ensure:
- Case-insensitive comparison
- Whitespace independence
- Consistent data type representation
- Schema-agnostic hashing (portable across databases)

## Basic Usage

### Check for Changes

```sql
-- Quick check: which objects have changed?
SELECT full_name, has_changed
FROM pggit.changed_objects
WHERE has_changed = true;

-- Detailed change detection
SELECT 
    full_name,
    object_type,
    old_hash,
    new_hash,
    has_changed
FROM pggit.detect_changes_by_hash()
WHERE has_changed = true;
```

### Manual Hash Computation

```sql
-- Compute hash for a specific object
SELECT pggit.compute_ddl_hash(
    'TABLE'::pggit.object_type,
    'public',
    'users'
);

-- Component hashes for tables
SELECT * FROM pggit.compute_table_component_hashes('public', 'users');
```

### Export Schema Hashes

```sql
-- Export for comparison with another database
SELECT 
    object_type,
    object_name,
    ddl_hash
FROM pggit.export_schema_hashes('public');

-- Export as JSON for transmission
SELECT json_object_agg(object_name, ddl_hash)
FROM pggit.export_schema_hashes('public');
```

## Advanced Features

### Component-Level Change Detection

For tables, you can detect what type of change occurred:

```sql
-- Before changes
SELECT * FROM pggit.compute_table_component_hashes('public', 'users');
-- structure_hash: abc123..., constraints_hash: def456..., indexes_hash: ghi789...

-- Add a column
ALTER TABLE users ADD COLUMN phone VARCHAR(20);

-- After changes
SELECT * FROM pggit.compute_table_component_hashes('public', 'users');
-- structure_hash: xyz999... (changed), constraints_hash: def456... (same), indexes_hash: ghi789... (same)
```

### Cross-Database Schema Sync

```sql
-- Database A: Export schema fingerprint
\COPY (
    SELECT json_object_agg(object_name, ddl_hash) 
    FROM pggit.export_schema_hashes('public')
) TO '/tmp/db_a_hashes.json'

-- Database B: Import and compare
CREATE TEMP TABLE remote_hashes (hashes JSONB);
\COPY remote_hashes FROM '/tmp/db_a_hashes.json'

-- Find differences
WITH local_hashes AS (
    SELECT json_object_agg(object_name, ddl_hash) as hashes
    FROM pggit.export_schema_hashes('public')
),
comparison AS (
    SELECT 
        COALESCE(local_key, remote_key) as object_name,
        local_value as local_hash,
        remote_value as remote_hash,
        CASE 
            WHEN local_value IS NULL THEN 'missing_locally'
            WHEN remote_value IS NULL THEN 'missing_remotely'
            WHEN local_value = remote_value THEN 'identical'
            ELSE 'different'
        END as status
    FROM (
        SELECT key as local_key, value as local_value
        FROM json_each_text((SELECT hashes FROM local_hashes))
    ) l
    FULL OUTER JOIN (
        SELECT key as remote_key, value as remote_value
        FROM json_each_text((SELECT hashes FROM remote_hashes))
    ) r ON l.local_key = r.remote_key
)
SELECT * FROM comparison
WHERE status != 'identical'
ORDER BY status, object_name;
```

### Performance Monitoring

```sql
-- Hash computation performance
\timing on
SELECT COUNT(*) FROM pggit.detect_changes_by_hash();
\timing off

-- Hash distribution analysis
SELECT 
    object_type,
    COUNT(*) as total_objects,
    COUNT(DISTINCT ddl_hash) as unique_hashes,
    ROUND(COUNT(DISTINCT ddl_hash)::numeric / COUNT(*) * 100, 2) as uniqueness_pct
FROM pggit.objects
WHERE is_active = true AND ddl_hash IS NOT NULL
GROUP BY object_type;
```

### Change History Analysis

```sql
-- View hash-based change history
SELECT 
    full_name,
    change_type,
    LEFT(old_hash, 12) || '...' as old_hash_preview,
    LEFT(new_hash, 12) || '...' as new_hash_preview,
    false_positive,
    created_at,
    created_by
FROM pggit.hash_history
WHERE created_at > CURRENT_DATE - INTERVAL '7 days'
ORDER BY created_at DESC;

-- False positive rate analysis
SELECT 
    DATE(created_at) as change_date,
    COUNT(*) as total_changes,
    COUNT(*) FILTER (WHERE false_positive) as false_positives,
    ROUND(
        COUNT(*) FILTER (WHERE false_positive)::numeric / 
        NULLIF(COUNT(*), 0) * 100, 2
    ) as false_positive_rate_pct
FROM pggit.hash_history
WHERE created_at > CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY change_date DESC;
```

## Best Practices

### 1. Regular Hash Updates

```sql
-- Ensure all objects have current hashes
SELECT * FROM pggit.update_all_hashes();

-- Monitor objects without hashes
SELECT 
    object_type,
    COUNT(*) - COUNT(ddl_hash) as missing_hashes
FROM pggit.objects
WHERE is_active = true
GROUP BY object_type
HAVING COUNT(*) - COUNT(ddl_hash) > 0;
```

### 2. Efficient Change Detection Workflow

```sql
-- Step 1: Quick hash-based scan
CREATE TEMP TABLE changed_objects AS
SELECT object_id, full_name
FROM pggit.detect_changes_by_hash()
WHERE has_changed = true;

-- Step 2: Detailed analysis only for changed objects
SELECT 
    co.full_name,
    o.version,
    h.change_description,
    h.created_at
FROM changed_objects co
JOIN pggit.objects o ON o.id = co.object_id
LEFT JOIN pggit.history h ON h.object_id = co.object_id
WHERE h.id = (
    SELECT MAX(id) FROM pggit.history 
    WHERE object_id = co.object_id
);
```

### 3. Schema Drift Monitoring

```sql
-- Create monitoring function
CREATE OR REPLACE FUNCTION check_schema_drift()
RETURNS TABLE(
    drift_detected BOOLEAN,
    changed_objects INTEGER,
    details TEXT
) AS $$
DECLARE
    v_changed_count INTEGER;
BEGIN
    -- Count changed objects
    SELECT COUNT(*) INTO v_changed_count
    FROM pggit.detect_changes_by_hash()
    WHERE has_changed = true;
    
    RETURN QUERY SELECT 
        v_changed_count > 0,
        v_changed_count,
        CASE 
            WHEN v_changed_count = 0 THEN 'No drift detected'
            WHEN v_changed_count < 5 THEN 'Minor drift detected'
            ELSE 'Significant drift detected'
        END;
END;
$$ LANGUAGE plpgsql;

-- Use in monitoring scripts
SELECT * FROM check_schema_drift();
```

### 4. Backup Before Hash Updates

```sql
-- Before major hash updates, backup existing hashes
CREATE TABLE pggit.hash_backup_20240614 AS
SELECT id, full_name, ddl_hash, updated_at
FROM pggit.objects
WHERE ddl_hash IS NOT NULL;

-- Update hashes
SELECT * FROM pggit.update_all_hashes();

-- Verify update
SELECT 
    'Objects updated' as metric,
    COUNT(*) as count
FROM pggit.objects o
JOIN pggit.hash_backup_20240614 b ON b.id = o.id
WHERE o.ddl_hash != b.ddl_hash;
```

## Troubleshooting

### Missing Hashes

```sql
-- Find objects without hashes
SELECT object_type, COUNT(*) as missing_hash_count
FROM pggit.objects
WHERE is_active = true AND ddl_hash IS NULL
GROUP BY object_type;

-- Update specific object types
UPDATE pggit.objects
SET ddl_hash = pggit.compute_ddl_hash(object_type, schema_name, object_name)
WHERE is_active = true 
AND ddl_hash IS NULL
AND object_type = 'TABLE';
```

### Hash Inconsistencies

```sql
-- Find objects where stored hash doesn't match computed hash
SELECT 
    full_name,
    object_type,
    ddl_hash as stored,
    pggit.compute_ddl_hash(object_type, schema_name, object_name) as computed
FROM pggit.objects
WHERE is_active = true
AND ddl_hash IS NOT NULL
AND ddl_hash != pggit.compute_ddl_hash(object_type, schema_name, object_name);
```

### Performance Issues

```sql
-- Check hash computation performance
EXPLAIN ANALYZE
SELECT COUNT(*) FROM pggit.detect_changes_by_hash();

-- Index usage for hash lookups
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pggit.objects WHERE ddl_hash = 'some_hash_value';
```

## Limitations

1. **Object Type Support**: Currently supports TABLE, VIEW, FUNCTION, INDEX
2. **Normalization Edge Cases**: Some DDL variations might not normalize perfectly
3. **PostgreSQL Version Differences**: Hash might vary across major PostgreSQL versions
4. **Large Objects**: Very large function definitions might impact hash computation time

## Migration from Non-Hash Version

If upgrading from a version without hashing:


```sql
-- 1. Add hashing functionality
\i sql/009_ddl_hashing.sql

-- 2. Populate hashes for existing objects
SELECT * FROM pggit.update_all_hashes();

-- 3. Verify coverage
SELECT 
    object_type,
    COUNT(*) as total,
    COUNT(ddl_hash) as with_hash,
    ROUND(COUNT(ddl_hash)::numeric / COUNT(*) * 100, 2) as coverage_pct
FROM pggit.objects
WHERE is_active = true
GROUP BY object_type;

-- 4. Enable hash-based event triggers (optional)
-- Replace existing triggers with hash-aware versions
```
