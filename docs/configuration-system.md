# pgGit Configuration System

The pgGit Configuration System provides fine-grained control over what database objects and operations are tracked, enabling selective versioning that fits your specific workflow.

## Table of Contents

- [Overview](#overview)
- [Selective Schema Tracking](#selective-schema-tracking)
- [Operation Filtering](#operation-filtering)
- [Deployment Mode](#deployment-mode)
- [Comment-Based Directives](#comment-based-directives)
- [Emergency Controls](#emergency-controls)
- [Examples](#examples)

## Overview

By default, pgGit tracks all DDL operations across all schemas. The Configuration System allows you to:

- Track only specific schemas while ignoring others
- Filter out certain operation types (e.g., `REFRESH MATERIALIZED VIEW`)
- Batch multiple changes in deployment mode
- Use comments to control tracking per object
- Temporarily pause tracking for maintenance

## Selective Schema Tracking

### Basic Configuration

```sql
-- Track only specific schemas
SELECT pggit.configure_tracking(
    track_schemas => ARRAY['public', 'app', 'api'],
    ignore_schemas => ARRAY['temp', 'staging', 'pg_temp%']
);
```

### Schema Patterns

You can use SQL LIKE patterns for schema names:

```sql
-- Ignore all temporary schemas
SELECT pggit.configure_tracking(
    ignore_schemas => ARRAY['pg_temp%', 'tmp_%']
);
```

### Priority Rules

When both track and ignore rules exist:
1. Comment directives have highest priority
2. Track rules override ignore rules
3. Patterns are evaluated in order

## Operation Filtering

### Filter Specific Operations

```sql
-- Don't track certain operations
SELECT pggit.configure_tracking(
    ignore_operations => ARRAY['REFRESH MATERIALIZED VIEW', 'REINDEX']
);
```

### Common Use Cases

```sql
-- CQRS setup: ignore query-side refreshes
SELECT pggit.configure_tracking(
    track_schemas => ARRAY['command', 'domain'],
    ignore_schemas => ARRAY['query', 'read_model'],
    ignore_operations => ARRAY['REFRESH MATERIALIZED VIEW']
);
```

### Add Ignore Patterns

```sql
-- Ignore specific operation patterns
SELECT pggit.add_ignore_pattern('REFRESH MATERIALIZED VIEW query.%');
SELECT pggit.add_ignore_pattern('CREATE TEMP TABLE %');
SELECT pggit.add_ignore_pattern('CREATE UNLOGGED TABLE %');
```

## Deployment Mode

Deployment mode allows you to batch multiple DDL operations without creating individual versions for each change.

### Starting a Deployment

```sql
-- Begin deployment mode
SELECT pggit.begin_deployment(
    deployment_name => 'Release 2.1.0',
    auto_commit => true  -- Automatically create commit when deployment ends
);
```

### Making Changes

While in deployment mode, all DDL operations are counted but not individually tracked:

```sql
-- All these changes will be part of one commit
CREATE TABLE users (id serial PRIMARY KEY, name text);
CREATE TABLE posts (id serial PRIMARY KEY, user_id int, content text);
ALTER TABLE posts ADD CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users(id);
CREATE INDEX idx_posts_user ON posts(user_id);
```

### Ending a Deployment

```sql
-- Complete the deployment
SELECT pggit.end_deployment(
    message => 'Added user and post tables with relationships',
    tags => ARRAY['feature', 'users', 'posts']
);
```

### Checking Deployment Status

```sql
-- Check if currently in deployment mode
SELECT pggit.in_deployment_mode();

-- View active deployment
SELECT * FROM pggit.deployment_mode WHERE status = 'active';
```

## Comment-Based Directives

Control tracking behavior using special comments on database objects.

### Ignore Specific Objects

```sql
-- This table will not be tracked
CREATE TABLE temp_data (id int);
COMMENT ON TABLE temp_data IS 'Temporary data for migration @pggit:ignore';
```

### Force Tracking

```sql
-- Force tracking even in ignored schema
CREATE TABLE ignored_schema.important_table (id int);
COMMENT ON TABLE ignored_schema.important_table IS 
    'Critical audit table @pggit:track';
```

### Function Metadata

```sql
CREATE OR REPLACE FUNCTION process_orders(order_date date)
RETURNS TABLE (order_id int, total decimal) AS $$
    -- Function implementation
$$ LANGUAGE sql;

COMMENT ON FUNCTION process_orders(date) IS 
'Process daily orders
@pggit-version: 2.3.1
@pggit-author: Data Team
@pggit-tags: orders, reporting, daily';
```

## Emergency Controls

### Pause Tracking

Temporarily disable pgGit tracking:

```sql
-- Pause for 1 hour
SELECT pggit.pause_tracking('1 hour'::interval);

-- Pause for 30 minutes
SELECT pggit.pause_tracking('30 minutes'::interval);
```

### Resume Tracking

```sql
-- Resume tracking before scheduled time
SELECT pggit.resume_tracking();
```

### Emergency Disable

For critical situations:

```sql
-- Emergency disable for 2 hours
SELECT pggit.emergency_disable('2 hours'::interval);

-- Re-enable when safe
SELECT pggit.emergency_enable();
```

## Examples

### Example 1: Microservices Architecture

```sql
-- Each service has its own schema
SELECT pggit.configure_tracking(
    track_schemas => ARRAY['user_service', 'order_service', 'inventory_service'],
    ignore_schemas => ARRAY['public', 'monitoring', 'logs']
);
```

### Example 2: Development vs Production

```sql
-- Ignore development schemas
SELECT pggit.configure_tracking(
    ignore_schemas => ARRAY['dev_%', 'test_%', 'sandbox_%']
);
```

### Example 3: Data Warehouse

```sql
-- Track only ETL and schema changes
SELECT pggit.configure_tracking(
    track_schemas => ARRAY['staging', 'warehouse'],
    ignore_schemas => ARRAY['temp', 'work'],
    ignore_operations => ARRAY['TRUNCATE', 'REFRESH MATERIALIZED VIEW']
);
```

### Example 4: Complex Deployment

```sql
-- Start deployment
SELECT pggit.begin_deployment('Q4 2024 Feature Release');

-- Make schema changes
CREATE SCHEMA feature_flags;
CREATE TABLE feature_flags.flags (
    flag_name text PRIMARY KEY,
    enabled boolean DEFAULT false,
    created_at timestamptz DEFAULT now()
);

-- Update existing tables
ALTER TABLE users ADD COLUMN preferences jsonb;
ALTER TABLE orders ADD COLUMN metadata jsonb;

-- Create new indexes
CREATE INDEX idx_users_preferences ON users USING gin(preferences);
CREATE INDEX idx_orders_metadata ON orders USING gin(metadata);

-- End deployment with description
SELECT pggit.end_deployment(
    message => 'Q4 2024: Added feature flags system and JSON metadata to core tables',
    tags => ARRAY['release', 'q4-2024', 'feature-flags', 'jsonb']
);
```

## Configuration Reference

### Functions

| Function | Description |
|----------|-------------|
| `pggit.configure_tracking()` | Set tracking configuration |
| `pggit.add_ignore_pattern()` | Add pattern to ignore list |
| `pggit.should_track_object()` | Check if object should be tracked |
| `pggit.begin_deployment()` | Start deployment mode |
| `pggit.end_deployment()` | End deployment mode |
| `pggit.in_deployment_mode()` | Check deployment status |
| `pggit.pause_tracking()` | Temporarily pause tracking |
| `pggit.resume_tracking()` | Resume tracking |

### Tables

| Table | Description |
|-------|-------------|
| `pggit.tracking_config` | Stores tracking configuration |
| `pggit.deployment_mode` | Active deployments |
| `pggit.deployment_state` | Global deployment state |
| `pggit.system_events` | Audit log for system events |

### Comment Directives

| Directive | Description |
|-----------|-------------|
| `@pggit:ignore` | Don't track this object |
| `@pggit:track` | Force tracking of this object |
| `@pggit-version:` | Specify version for functions |
| `@pggit-author:` | Specify author for functions |
| `@pggit-tags:` | Add tags to functions |