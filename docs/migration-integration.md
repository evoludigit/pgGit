# pgGit Migration Integration

pgGit seamlessly integrates with traditional migration tools like Flyway, Liquibase, and custom migration systems, providing unified tracking of both manual changes and migration-based deployments.

## Table of Contents

- [Overview](#overview)
- [Basic Migration Tracking](#basic-migration-tracking)
- [Flyway Integration](#flyway-integration)
- [Liquibase Integration](#liquibase-integration)
- [Migration Validation](#migration-validation)
- [Impact Analysis](#impact-analysis)
- [Best Practices](#best-practices)

## Overview

Migration tools and pgGit serve complementary purposes:
- **Migration Tools**: Sequential, versioned scripts for deployment
- **pgGit**: Complete schema history and version control

The integration allows you to:
- Track migrations in pgGit's history
- Link migration IDs to pgGit commits
- Validate migration sequences
- Analyze migration impact
- Maintain compatibility with existing workflows

## Basic Migration Tracking

### Track a Migration

```sql
-- Start tracking a migration
DECLARE
    deployment_id uuid;
BEGIN
    deployment_id := pggit.begin_migration(
        migration_id => 20240120001,
        tool_name => 'flyway',
        migration_name => 'Add user preferences table'
    );
    
    -- Run your migration DDL
    CREATE TABLE user_preferences (
        user_id int PRIMARY KEY,
        preferences jsonb NOT NULL DEFAULT '{}',
        updated_at timestamptz DEFAULT now()
    );
    
    CREATE INDEX idx_preferences_updated ON user_preferences(updated_at);
    
    -- Complete the migration
    PERFORM pggit.end_migration(
        migration_id => 20240120001,
        checksum => 'abc123def456',  -- Your tool's checksum
        success => true
    );
END;
```

### Link Existing Migrations

```sql
-- Link historical migrations to pgGit
SELECT pggit.link_migration(
    migration_id => 20240101001,
    description => 'Initial schema creation',
    tool_name => 'flyway'
);
```

## Flyway Integration

### Automatic Flyway Tracking

```sql
-- Enable automatic tracking of Flyway migrations
SELECT pggit.integrate_flyway('public');  -- Schema where flyway_schema_history exists
```

This creates triggers that automatically track Flyway migrations in pgGit.

### Flyway Migration Example

```sql
-- V1__Create_user_tables.sql (Flyway migration file)
-- This will be automatically tracked by pgGit

CREATE TABLE users (
    id serial PRIMARY KEY,
    username text UNIQUE NOT NULL,
    email text UNIQUE NOT NULL,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE user_roles (
    user_id int REFERENCES users(id),
    role text NOT NULL,
    granted_at timestamptz DEFAULT now(),
    PRIMARY KEY (user_id, role)
);
```

### View Flyway Integration

```sql
-- See Flyway migrations in pgGit
SELECT 
    m.migration_id,
    m.migration_name,
    m.applied_at,
    m.checksum,
    c.message as commit_message,
    c.tree_id
FROM pggit.migration_history m
WHERE m.tool_name = 'flyway'
ORDER BY m.migration_id;
```

## Liquibase Integration

### Enable Liquibase Tracking

```sql
-- Enable automatic tracking of Liquibase changesets
SELECT pggit.integrate_liquibase('public');  -- Schema with databasechangelog table
```

### Liquibase Changeset Example

```xml
<!-- Liquibase changeset that will be tracked -->
<changeSet id="add-audit-fields" author="developer">
    <addColumn tableName="users">
        <column name="last_login" type="timestamptz"/>
        <column name="login_count" type="int" defaultValue="0"/>
    </addColumn>
</changeSet>
```

### Query Liquibase History

```sql
-- View Liquibase changesets in pgGit
SELECT 
    m.migration_id as changeset_order,
    m.migration_name,
    m.applied_at,
    m.applied_by as author
FROM pggit.migration_history m
WHERE m.tool_name = 'liquibase'
ORDER BY m.applied_at;
```

## Migration Validation

### Check Migration Sequence

```sql
-- Validate migration sequence for gaps or issues
SELECT * FROM pggit.validate_migrations('flyway');
```

Example output:
```
migration_id | status    | message
-------------|-----------|----------------------------------
NULL         | gap       | Missing migrations 102 to 104
105          | unlinked  | Migration not linked to pgGit commit
107          | failed    | Migration failed: Constraint violation
```

### Validate All Tools

```sql
-- Check all migration tools
SELECT 
    tool_name,
    COUNT(*) FILTER (WHERE status = 'gap') as gaps,
    COUNT(*) FILTER (WHERE status = 'failed') as failures,
    COUNT(*) FILTER (WHERE status = 'unlinked') as unlinked
FROM pggit.validate_migrations()
GROUP BY tool_name;
```

### Fix Validation Issues

```sql
-- Link unlinked migrations
DO $$
DECLARE
    unlinked record;
BEGIN
    FOR unlinked IN 
        SELECT migration_id 
        FROM pggit.validate_migrations()
        WHERE status = 'unlinked'
    LOOP
        PERFORM pggit.link_migration(
            unlinked.migration_id,
            'Retroactively linked migration'
        );
    END LOOP;
END $$;
```

## Impact Analysis

### Analyze Migration Impact

```sql
-- See what objects were affected by a migration
SELECT * FROM pggit.analyze_migration_impact(20240120001);
```

Example output:
```
object_type | object_name              | operation | impact_level
------------|--------------------------|-----------|-------------
table       | public.user_preferences  | CREATE    | medium
index       | idx_preferences_updated  | CREATE    | low
```

### Migration Change Summary

```sql
-- Summarize changes by migration
WITH migration_impacts AS (
    SELECT 
        m.migration_id,
        m.migration_name,
        COUNT(*) as objects_affected,
        array_agg(DISTINCT impact.object_type) as object_types
    FROM pggit.external_migrations m
    CROSS JOIN LATERAL pggit.analyze_migration_impact(m.migration_id) as impact
    GROUP BY m.migration_id, m.migration_name
)
SELECT * FROM migration_impacts
ORDER BY migration_id DESC
LIMIT 10;
```

### Export Migration Schema

```sql
-- Export schema state at specific migration
SELECT pggit.export_migration_schema(
    migration_id => 20240120001,
    output_path => '/tmp/schema_at_migration.sql'
);
```

## Best Practices

### 1. Use Migration Wrapper Functions

```sql
-- Create a wrapper for your migrations
CREATE OR REPLACE FUNCTION run_migration(
    p_migration_id bigint,
    p_name text,
    p_sql text
) RETURNS void AS $$
DECLARE
    v_deployment_id uuid;
BEGIN
    -- Start pgGit tracking
    v_deployment_id := pggit.begin_migration(p_migration_id, 'custom', p_name);
    
    -- Execute migration
    EXECUTE p_sql;
    
    -- End tracking
    PERFORM pggit.end_migration(p_migration_id, 
        checksum => md5(p_sql), 
        success => true
    );
EXCEPTION WHEN OTHERS THEN
    -- Record failure
    PERFORM pggit.end_migration(p_migration_id, 
        success => false, 
        error_message => SQLERRM
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
```

### 2. Coordinate with CI/CD

```bash
#!/bin/bash
# deploy.sh - Deployment script with pgGit integration

# Run Flyway migration
flyway migrate

# Verify in pgGit
psql -c "SELECT * FROM pggit.validate_migrations('flyway') WHERE status != 'ok'"

# Check for conflicts
psql -c "SELECT * FROM pggit.list_conflicts('unresolved')"
```

### 3. Migration Rollback Tracking

```sql
-- Track rollback operations
CREATE OR REPLACE FUNCTION rollback_migration(
    p_migration_id bigint
) RETURNS void AS $$
BEGIN
    -- Start rollback tracking
    PERFORM pggit.begin_deployment(
        format('Rollback migration %s', p_migration_id)
    );
    
    -- Your rollback logic here
    -- ...
    
    -- Link rollback to original migration
    INSERT INTO pggit.external_migrations (
        migration_id,
        tool_name,
        migration_name,
        success
    ) VALUES (
        -p_migration_id,  -- Negative ID for rollback
        'rollback',
        format('Rollback of migration %s', p_migration_id),
        true
    );
    
    PERFORM pggit.end_deployment();
END;
$$ LANGUAGE plpgsql;
```

### 4. Pre-Migration Validation

```sql
-- Validate before running migrations
CREATE OR REPLACE FUNCTION validate_before_migration()
RETURNS boolean AS $$
DECLARE
    v_issues int;
BEGIN
    -- Check for gaps
    SELECT COUNT(*) INTO v_issues
    FROM pggit.validate_migrations()
    WHERE status = 'gap';
    
    IF v_issues > 0 THEN
        RAISE NOTICE 'Found % gaps in migration sequence', v_issues;
        RETURN false;
    END IF;
    
    -- Check for unresolved conflicts
    SELECT COUNT(*) INTO v_issues
    FROM pggit.list_conflicts('unresolved');
    
    IF v_issues > 0 THEN
        RAISE NOTICE 'Found % unresolved conflicts', v_issues;
        RETURN false;
    END IF;
    
    RETURN true;
END;
$$ LANGUAGE plpgsql;
```

### 5. Migration Metrics

```sql
-- Track migration performance
CREATE VIEW migration_metrics AS
SELECT 
    tool_name,
    DATE_TRUNC('month', applied_at) as month,
    COUNT(*) as migration_count,
    AVG(execution_time) as avg_duration,
    MAX(execution_time) as max_duration,
    COUNT(*) FILTER (WHERE NOT success) as failures
FROM pggit.external_migrations
GROUP BY tool_name, DATE_TRUNC('month', applied_at)
ORDER BY month DESC, tool_name;
```

## Advanced Integration

### Custom Migration Tool

```sql
-- Integrate custom migration system
CREATE OR REPLACE FUNCTION setup_custom_migration_tracking()
RETURNS void AS $$
BEGIN
    -- Create custom migration table
    CREATE TABLE IF NOT EXISTS custom_migrations (
        version integer PRIMARY KEY,
        description text,
        script text,
        applied_at timestamptz DEFAULT now()
    );
    
    -- Create trigger for pgGit integration
    CREATE OR REPLACE FUNCTION track_custom_migration()
    RETURNS TRIGGER AS $trigger$
    BEGIN
        IF TG_OP = 'INSERT' THEN
            PERFORM pggit.link_migration(
                NEW.version,
                NEW.description,
                'custom'
            );
        END IF;
        RETURN NEW;
    END;
    $trigger$ LANGUAGE plpgsql;
    
    CREATE TRIGGER custom_migration_tracker
    AFTER INSERT ON custom_migrations
    FOR EACH ROW EXECUTE FUNCTION track_custom_migration();
END;
$$ LANGUAGE plpgsql;
```

### Migration Comparison

```sql
-- Compare migrations across environments
SELECT 
    prod.migration_id,
    prod.migration_name,
    prod.applied_at as prod_applied,
    staging.applied_at as staging_applied,
    CASE 
        WHEN staging.migration_id IS NULL THEN 'Not in staging'
        WHEN prod.applied_at < staging.applied_at THEN 'Staging is behind'
        ELSE 'OK'
    END as status
FROM pggit.external_migrations prod
FULL OUTER JOIN dblink(
    'host=staging-db dbname=myapp',
    'SELECT migration_id, applied_at FROM pggit.external_migrations'
) AS staging(migration_id bigint, applied_at timestamptz)
  ON prod.migration_id = staging.migration_id
WHERE prod.tool_name = 'flyway'
ORDER BY prod.migration_id;
```

## Migration Integration Reference

### Functions

| Function | Description |
|----------|-------------|
| `pggit.begin_migration()` | Start tracking a migration |
| `pggit.end_migration()` | Complete migration tracking |
| `pggit.link_migration()` | Link existing migration to pgGit |
| `pggit.validate_migrations()` | Check migration sequence integrity |
| `pggit.analyze_migration_impact()` | Analyze objects affected by migration |
| `pggit.integrate_flyway()` | Enable Flyway auto-tracking |
| `pggit.integrate_liquibase()` | Enable Liquibase auto-tracking |
| `pggit.export_migration_schema()` | Export schema at migration point |

### Tables

| Table | Description |
|-------|-------------|
| `pggit.external_migrations` | Migration tracking table |

### Views

| View | Description |
|------|-------------|
| `pggit.migration_history` | Complete migration history with pgGit correlation |