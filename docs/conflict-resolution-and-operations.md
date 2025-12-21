# pgGit Conflict Resolution & Operations

> ⚠️ **PARTIALLY EXPERIMENTAL**
>
> Some features in this documentation (advanced merge strategies, conflict auto-resolution)
> are planned for future releases and are **NOT available in pgGit v0.1.1**.
>
> **Implemented in v0.1.1**: Basic conflict detection, manual resolution
> **Planned for v0.3.0+**: Advanced strategies (recursive, ours, theirs), auto-resolution
>
> See each section for feature availability status.

This guide covers pgGit's conflict resolution API and operational commands for maintenance, emergency controls, and system monitoring.

## Table of Contents

- [Conflict Resolution](#conflict-resolution)
  - [Conflict Types](#conflict-types)
  - [Resolution API](#resolution-api)
  - [Resolution Strategies](#resolution-strategies)
- [Emergency Controls](#emergency-controls)
  - [Emergency Disable](#emergency-disable)
  - [Pause and Resume](#pause-and-resume)
- [Maintenance Operations](#maintenance-operations)
  - [History Management](#history-management)
  - [Consistency Checks](#consistency-checks)
  - [Performance Monitoring](#performance-monitoring)
- [System Operations](#system-operations)
  - [Status Dashboard](#status-dashboard)
  - [Environment Comparison](#environment-comparison)
  - [Schema Export](#schema-export)

## Conflict Resolution

### Conflict Types

pgGit tracks four types of conflicts:

1. **Merge Conflicts**: Different versions of the same object
2. **Version Conflicts**: Version number mismatches
3. **Constraint Conflicts**: Conflicting constraint definitions
4. **Dependency Conflicts**: Circular or missing dependencies

### Resolution API

#### Register a Conflict

```sql
-- Register a merge conflict
DECLARE
    conflict_id uuid;
BEGIN
    conflict_id := pggit.register_conflict(
        conflict_type => 'merge',
        object_type => 'table',
        object_identifier => 'public.users',
        conflict_data => jsonb_build_object(
            'base_version', '1.0.0',
            'current_version', '1.1.0',
            'incoming_version', '1.2.0',
            'current_definition', 'CREATE TABLE users (id int, name text)',
            'incoming_definition', 'CREATE TABLE users (id int, name text, email text)'
        )
    );
    
    RAISE NOTICE 'Conflict registered: %', conflict_id;
END;
```

#### List Active Conflicts

```sql
-- View all unresolved conflicts
SELECT * FROM pggit.list_conflicts('unresolved');

-- View resolved conflicts
SELECT * FROM pggit.list_conflicts('resolved');

-- View all conflicts
SELECT * FROM pggit.list_conflicts(NULL);
```

#### Show Conflict Details

```sql
-- Get detailed information about a conflict
SELECT * FROM pggit.show_conflict_details('conflict-uuid-here');
```

Example output:
```
detail_type      | detail_value
-----------------|------------------------------------------
Type             | merge
Object           | public.users
Status           | unresolved
Created          | 2024-01-20 10:30:00
Base Version     | 1.0.0
Current Version  | 1.1.0
Incoming Version | 1.2.0
Resolution Options |
  use_current    | Keep current version
  use_tracked    | Use incoming version
  merge          | Attempt automatic merge
  custom         | Apply custom resolution
```

### Resolution Strategies

#### Use Current Version

```sql
-- Keep the current version and ignore incoming changes
SELECT pggit.resolve_conflict(
    conflict_id => 'conflict-uuid',
    resolution => 'use_current',
    reason => 'Current version has production-critical changes'
);
```

#### Use Tracked Version

```sql
-- Accept the incoming version
SELECT pggit.resolve_conflict(
    conflict_id => 'conflict-uuid',
    resolution => 'use_tracked',
    reason => 'Feature branch has the latest approved changes'
);
```

#### Automatic Merge

```sql
-- Attempt three-way merge
SELECT pggit.resolve_conflict(
    conflict_id => 'conflict-uuid',
    resolution => 'merge',
    reason => 'Non-conflicting changes can be merged automatically'
);
```

#### Custom Resolution

```sql
-- Apply custom resolution
SELECT pggit.resolve_conflict(
    conflict_id => 'conflict-uuid',
    resolution => 'custom',
    reason => 'Manual merge required for complex changes',
    custom_resolution => jsonb_build_object(
        'sql', 'ALTER TABLE public.users ADD COLUMN email text, ADD COLUMN phone text'
    )
);
```

## Emergency Controls

### Emergency Disable

For critical situations where pgGit needs to be disabled immediately:

```sql
-- Disable for 2 hours
SELECT pggit.emergency_disable('2 hours'::interval);

-- Disable for 30 minutes
SELECT pggit.emergency_disable('30 minutes'::interval);
```

Output:
```
WARNING: pgGit EMERGENCY DISABLED until 2024-01-20 12:30:00. 
Use pggit.emergency_enable() to re-enable sooner.
```

#### Re-enable After Emergency

```sql
-- Re-enable when it's safe
SELECT pggit.emergency_enable();
```

### Pause and Resume

For planned maintenance windows:

```sql
-- Pause tracking for maintenance
SELECT pggit.pause_tracking('1 hour'::interval);

-- Do maintenance work...
VACUUM FULL large_table;
REINDEX DATABASE mydb;

-- Resume when done
SELECT pggit.resume_tracking();
```

## Maintenance Operations

### History Management

#### Purge Old History

```sql
-- Dry run to see what would be deleted
SELECT * FROM pggit.purge_history(
    older_than => '6 months'::interval,
    keep_milestones => true,
    dry_run => true
);
```

Example output:
```
action       | object_type | count | space_freed
-------------|-------------|-------|-------------
would_delete | commits     | 1523  | 15 MB
would_delete | versions    | 4521  | 43 MB
would_delete | blobs       | 234   | 125 MB
```

#### Execute Purge

```sql
-- Actually purge old data
SELECT * FROM pggit.purge_history(
    older_than => '6 months'::interval,
    keep_milestones => true,
    dry_run => false
);

-- More aggressive purge
SELECT * FROM pggit.purge_history(
    older_than => '3 months'::interval,
    keep_milestones => false,
    dry_run => false
);
```

### Consistency Checks

#### Verify Database Consistency

```sql
-- Run consistency checks
SELECT * FROM pggit.verify_consistency(
    fix_issues => false,  -- Just report, don't fix
    verbose => true
);
```

Example output:
```
check_name        | status | details                        | fixed
------------------|--------|--------------------------------|-------
version_history   | error  | Object X has 2 current versions| false
orphaned_objects  | warning| Object Y no longer exists      | false
blob_integrity    | ok     | All blobs verified             | false
commit_trees      | ok     | All commits have valid trees   | false
```

#### Auto-fix Issues

```sql
-- Fix issues automatically where possible
SELECT * FROM pggit.verify_consistency(
    fix_issues => true,
    verbose => true
);
```

### Performance Monitoring

#### Performance Report

```sql
-- Get performance metrics for last 30 days
SELECT * FROM pggit.performance_report(days_back => 30);
```

Example output:
```
metric_name           | metric_value | metric_unit
----------------------|--------------|-------------
DDL operations tracked| 523          | operations
Storage used          | 156.3        | MB
Avg tracking time     | 12.5         | ms
Compression ratio     | 68.2         | %
Conflicts encountered | 7            | conflicts
```

#### Custom Performance Query

```sql
-- Tracking overhead by operation type
WITH operation_stats AS (
    SELECT 
        event_data->>'operation_type' as operation,
        AVG(EXTRACT(MILLISECONDS FROM 
            (event_data->>'duration')::interval)) as avg_ms,
        COUNT(*) as count
    FROM pggit.system_events
    WHERE event_type = 'tracking_complete'
      AND created_at > now() - interval '7 days'
    GROUP BY event_data->>'operation_type'
)
SELECT * FROM operation_stats
ORDER BY avg_ms DESC;
```

## System Operations

### Status Dashboard

```sql
-- Get current system status
SELECT * FROM pggit.status();
```

Example output:
```
component        | status   | details
-----------------|----------|----------------------------------------
Tracking         | enabled  | 2 triggers active
Deployment Mode  | inactive | No active deployment
Storage          | ok       | Using 156 MB across 2341 objects
Recent Activity  | info     | 23 changes in last hour
```

### Environment Comparison

#### Compare Local Branches

```sql
-- Compare production and staging branches
SELECT * FROM pggit.compare_environments('production', 'staging');
```

Example output:
```
object_type | object_name      | env1_status | env2_status | difference
------------|------------------|-------------|-------------|-------------
table       | users           | 1.2.0       | 1.1.0       | Version mismatch
table       | analytics_cache | missing     | 1.0.0       | Only in staging
function    | calculate_tax   | 2.0.0       | 2.0.0       | Same
```

#### Compare Remote Databases

```sql
-- Compare with remote database (requires dblink)
SELECT * FROM pggit.compare_environments(
    env1_name => 'production',
    env2_name => 'staging',
    connection_string1 => 'host=prod-db dbname=myapp',
    connection_string2 => 'host=staging-db dbname=myapp'
);
```

### Schema Export

#### Export Current Schema

```sql
-- Export specific schemas
SELECT pggit.export_schema_snapshot(
    schemas => ARRAY['public', 'api', 'reports']
);
```

#### Export to File

```sql
-- Export with file path (requires appropriate permissions)
SELECT pggit.export_schema_snapshot(
    path => '/backup/schema_20240120.sql',
    schemas => ARRAY['public', 'api']
);
```

Note: File export requires additional extensions or permissions. Use `psql \o` command as alternative:

```bash
psql -c "\o /tmp/schema.sql" -c "SELECT pggit.export_schema_snapshot();"
```

## Advanced Operations

### System Event Monitoring

```sql
-- View recent system events
SELECT 
    event_type,
    event_data->>'action' as action,
    event_data->>'user' as user,
    created_at
FROM pggit.system_events
WHERE created_at > now() - interval '1 hour'
ORDER BY created_at DESC;
```

### Bulk Conflict Resolution

```sql
-- Resolve all conflicts of a specific type
DO $$
DECLARE
    conf record;
BEGIN
    FOR conf IN 
        SELECT conflict_id 
        FROM pggit.list_conflicts('unresolved')
        WHERE conflict_type = 'version'
    LOOP
        -- Use current version for all version conflicts
        PERFORM pggit.resolve_conflict(
            conf.conflict_id, 
            'use_current',
            'Bulk resolution: keeping current versions'
        );
    END LOOP;
END $$;
```

### Maintenance Window Automation

```sql
-- Create maintenance window procedure
CREATE OR REPLACE PROCEDURE perform_maintenance()
LANGUAGE plpgsql AS $$
BEGIN
    -- Pause tracking
    PERFORM pggit.pause_tracking('2 hours'::interval);
    
    -- Run maintenance
    VACUUM ANALYZE;
    REINDEX DATABASE CONCURRENTLY current_database();
    
    -- Verify consistency
    PERFORM pggit.verify_consistency(fix_issues => true);
    
    -- Purge old data
    PERFORM pggit.purge_history(
        older_than => '6 months'::interval,
        keep_milestones => true,
        dry_run => false
    );
    
    -- Resume tracking
    PERFORM pggit.resume_tracking();
    
    -- Log completion
    RAISE NOTICE 'Maintenance completed successfully';
END;
$$;
```

## Operations Reference

### Conflict Resolution Functions

| Function | Description |
|----------|-------------|
| `pggit.register_conflict()` | Register a new conflict |
| `pggit.resolve_conflict()` | Resolve a conflict |
| `pggit.list_conflicts()` | List conflicts by status |
| `pggit.show_conflict_details()` | Show detailed conflict information |

### Emergency Functions

| Function | Description |
|----------|-------------|
| `pggit.emergency_disable()` | Emergency disable with timeout |
| `pggit.emergency_enable()` | Re-enable after emergency |
| `pggit.pause_tracking()` | Temporarily pause tracking |
| `pggit.resume_tracking()` | Resume tracking |

### Maintenance Functions

| Function | Description |
|----------|-------------|
| `pggit.purge_history()` | Remove old history |
| `pggit.verify_consistency()` | Check and fix consistency |
| `pggit.performance_report()` | Generate performance metrics |
| `pggit.status()` | System status dashboard |
| `pggit.compare_environments()` | Compare environments |
| `pggit.export_schema_snapshot()` | Export schema DDL |

### Tables

| Table | Description |
|-------|-------------|
| `pggit.conflict_registry` | Stores conflict information |
| `pggit.system_events` | System event audit log |
| `pggit.archived_objects` | Archived/orphaned objects |
| `pggit.archived_commits` | Archived historical commits |