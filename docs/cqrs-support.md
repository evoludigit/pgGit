# pgGit CQRS Support

pgGit's CQRS (Command Query Responsibility Segregation) support enables coordinated tracking of changes across command and query sides of your architecture, ensuring consistency while respecting the separation of concerns.

## Table of Contents

- [Overview](#overview)
- [Basic Usage](#basic-usage)
- [CQRS Change Tracking](#cqrs-change-tracking)
- [Query Side Management](#query-side-management)
- [Dependency Analysis](#dependency-analysis)
- [Integration Patterns](#integration-patterns)
- [Best Practices](#best-practices)

## Overview

CQRS architectures separate read and write operations into different models:
- **Command Side**: Handles writes, business logic, and domain events
- **Query Side**: Optimized read models, often using materialized views

pgGit's CQRS support provides:
- Coordinated change tracking across both sides
- Atomic changesets that span schemas
- Dependency analysis between command and query models
- Helpers for query side synchronization

## Basic Usage

### Define a CQRS Change

```sql
-- Track coordinated changes across command and query sides
SELECT pggit.track_cqrs_change(
    ROW(
        -- Command side operations
        ARRAY[
            'CREATE TABLE command.orders (id uuid PRIMARY KEY, user_id int, total decimal)',
            'CREATE TABLE command.order_items (id uuid PRIMARY KEY, order_id uuid, product_id int, quantity int)'
        ],
        -- Query side operations
        ARRAY[
            'CREATE MATERIALIZED VIEW query.order_summary AS 
             SELECT user_id, COUNT(*) as order_count, SUM(total) as total_spent 
             FROM command.orders GROUP BY user_id'
        ],
        -- Description
        'Add order management system',
        -- Version
        '1.0.0'
    )::pggit.cqrs_change
);
```

### Non-Atomic Execution

For manual control over execution:

```sql
-- Create changeset without executing
DECLARE
    changeset_id uuid;
BEGIN
    changeset_id := pggit.track_cqrs_change(
        change => ROW(...)::pggit.cqrs_change,
        atomic => false  -- Don't execute immediately
    );
    
    -- Execute when ready
    PERFORM pggit.execute_cqrs_changeset(changeset_id);
END;
```

## CQRS Change Tracking

### Complex CQRS Pattern

```sql
-- Implement event sourcing with CQRS
SELECT pggit.track_cqrs_change(
    ROW(
        -- Command side: Event store
        ARRAY[
            'CREATE TABLE command.events (
                event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
                aggregate_id uuid NOT NULL,
                event_type text NOT NULL,
                event_data jsonb NOT NULL,
                event_version int NOT NULL,
                created_at timestamptz DEFAULT now()
            )',
            'CREATE INDEX idx_events_aggregate ON command.events(aggregate_id)',
            'CREATE INDEX idx_events_created ON command.events(created_at)'
        ],
        -- Query side: Read models
        ARRAY[
            'CREATE MATERIALIZED VIEW query.user_profile AS 
             SELECT 
                 aggregate_id as user_id,
                 event_data->>''name'' as name,
                 event_data->>''email'' as email,
                 MAX(created_at) as last_updated
             FROM command.events
             WHERE event_type = ''UserUpdated''
             GROUP BY aggregate_id, event_data',
            'CREATE UNIQUE INDEX idx_user_profile_id ON query.user_profile(user_id)'
        ],
        'Implement event sourcing for user domain',
        '2.0.0'
    )::pggit.cqrs_change
);
```

### Changeset with Reference Data

```sql
-- Include shared reference data
SELECT pggit.track_cqrs_change(
    ROW(
        -- Command operations
        ARRAY[
            'CREATE TABLE reference.countries (code char(2) PRIMARY KEY, name text)',
            'INSERT INTO reference.countries VALUES (''US'', ''United States''), (''UK'', ''United Kingdom'')',
            'ALTER TABLE command.users ADD COLUMN country_code char(2) REFERENCES reference.countries(code)'
        ],
        -- Query operations
        ARRAY[
            'CREATE VIEW query.users_with_country AS 
             SELECT u.*, c.name as country_name 
             FROM command.users u 
             LEFT JOIN reference.countries c ON u.country_code = c.code'
        ],
        'Add country support to user system',
        '1.1.0'
    )::pggit.cqrs_change
);
```

## Query Side Management

### Refresh Materialized Views

```sql
-- Refresh without tracking (for regular maintenance)
SELECT pggit.refresh_query_side('query.order_summary', skip_tracking => true);

-- Refresh with tracking (for deployments)
SELECT pggit.refresh_query_side('query.order_summary', skip_tracking => false);
```

### Batch Query Updates

```sql
-- Update multiple query models together
DO $$
DECLARE
    views text[] := ARRAY[
        'query.user_summary',
        'query.order_summary', 
        'query.product_stats'
    ];
    view_name text;
BEGIN
    -- Start deployment for query refresh
    PERFORM pggit.begin_deployment('Query Model Refresh');
    
    FOREACH view_name IN ARRAY views
    LOOP
        PERFORM pggit.refresh_query_side(view_name, skip_tracking => true);
    END LOOP;
    
    PERFORM pggit.end_deployment('Refreshed all query models');
END $$;
```

## Dependency Analysis

### Analyze CQRS Dependencies

```sql
-- Find dependencies between command and query schemas
SELECT * FROM pggit.analyze_cqrs_dependencies('command', 'query');
```

Example output:
```
command_object     | query_object              | dependency_type | dependency_path
-------------------|---------------------------|-----------------|------------------
command.orders     | query.order_summary       | direct          | {command.orders, query.order_summary}
command.users      | query.user_order_stats    | indirect        | {command.users, command.orders, query.user_order_stats}
```

### Visualize Dependencies

```sql
-- Get dependency graph for documentation
WITH deps AS (
    SELECT * FROM pggit.analyze_cqrs_dependencies()
)
SELECT 
    command_object,
    string_agg(query_object, ', ') as dependent_views,
    COUNT(*) as dependency_count
FROM deps
GROUP BY command_object
ORDER BY dependency_count DESC;
```

## Integration Patterns

### Pattern 1: Event-Driven CQRS

```sql
-- Setup event-driven synchronization
SELECT pggit.track_cqrs_change(
    ROW(
        -- Command: Event publication
        ARRAY[
            'CREATE TABLE command.outbox (
                id serial PRIMARY KEY,
                aggregate_id uuid,
                event_type text,
                payload jsonb,
                published boolean DEFAULT false,
                created_at timestamptz DEFAULT now()
            )',
            'CREATE OR REPLACE FUNCTION command.publish_event(
                p_aggregate_id uuid,
                p_event_type text,
                p_payload jsonb
            ) RETURNS void AS $$
            BEGIN
                INSERT INTO command.outbox (aggregate_id, event_type, payload)
                VALUES (p_aggregate_id, p_event_type, p_payload);
            END;
            $$ LANGUAGE plpgsql'
        ],
        -- Query: Event consumption  
        ARRAY[
            'CREATE TABLE query.processed_events (
                event_id int PRIMARY KEY,
                processed_at timestamptz DEFAULT now()
            )',
            'CREATE OR REPLACE FUNCTION query.process_events()
            RETURNS void AS $$
            DECLARE
                event record;
            BEGIN
                FOR event IN 
                    SELECT o.* FROM command.outbox o
                    LEFT JOIN query.processed_events p ON o.id = p.event_id
                    WHERE p.event_id IS NULL AND o.published = true
                    ORDER BY o.id
                LOOP
                    -- Process event based on type
                    -- Update read models
                    INSERT INTO query.processed_events (event_id) VALUES (event.id);
                END LOOP;
            END;
            $$ LANGUAGE plpgsql'
        ],
        'Implement event-driven CQRS synchronization',
        '3.0.0'
    )::pggit.cqrs_change
);
```

### Pattern 2: Saga Pattern

```sql
-- Implement saga for complex workflows
SELECT pggit.track_cqrs_change(
    ROW(
        -- Command: Saga state
        ARRAY[
            'CREATE TABLE command.sagas (
                saga_id uuid PRIMARY KEY,
                saga_type text NOT NULL,
                state jsonb NOT NULL,
                version int NOT NULL DEFAULT 1,
                created_at timestamptz DEFAULT now(),
                updated_at timestamptz DEFAULT now()
            )',
            'CREATE TABLE command.saga_events (
                id serial PRIMARY KEY,
                saga_id uuid REFERENCES command.sagas(saga_id),
                event_type text NOT NULL,
                event_data jsonb,
                created_at timestamptz DEFAULT now()
            )'
        ],
        -- Query: Saga monitoring
        ARRAY[
            'CREATE MATERIALIZED VIEW query.saga_status AS
             SELECT 
                 saga_type,
                 state->>''status'' as status,
                 COUNT(*) as count,
                 MAX(updated_at) as last_update
             FROM command.sagas
             GROUP BY saga_type, state->>''status''',
            'CREATE VIEW query.active_sagas AS
             SELECT * FROM command.sagas
             WHERE state->>''status'' NOT IN (''completed'', ''failed'')'
        ],
        'Add saga pattern for workflow management',
        '3.1.0'
    )::pggit.cqrs_change
);
```

## Best Practices

### 1. Use Deployment Mode for CQRS Changes

```sql
-- Wrap CQRS changes in deployment mode
SELECT pggit.begin_deployment('CQRS Model Update');

-- Make coordinated changes
SELECT pggit.track_cqrs_change(...);

-- Refresh affected views
SELECT pggit.refresh_query_side('query.affected_view');

SELECT pggit.end_deployment('Updated CQRS models and refreshed views');
```

### 2. Version Your Changes

```sql
-- Use semantic versioning for CQRS changes
SELECT pggit.track_cqrs_change(
    ROW(
        command_operations,
        query_operations,
        'Breaking change: Restructure order system',
        '2.0.0'  -- Major version bump for breaking changes
    )::pggit.cqrs_change
);
```

### 3. Monitor Changeset History

```sql
-- View recent CQRS changes
SELECT 
    changeset_id,
    description,
    version,
    status,
    created_at,
    command_ops_count,
    query_ops_count
FROM pggit.cqrs_history
WHERE created_at > now() - interval '7 days'
ORDER BY created_at DESC;
```

### 4. Handle Failures Gracefully

```sql
-- Check for failed changesets
SELECT * FROM pggit.cqrs_changesets
WHERE status = 'failed'
ORDER BY created_at DESC;

-- Investigate failed operations
SELECT * FROM pggit.cqrs_operations
WHERE changeset_id = 'failed-changeset-id'
  AND success = false;
```

## CQRS Reference

### Types

| Type | Description |
|------|-------------|
| `pggit.cqrs_change` | Composite type for CQRS changes |

### Functions

| Function | Description |
|----------|-------------|
| `pggit.track_cqrs_change()` | Track coordinated CQRS changes |
| `pggit.execute_cqrs_changeset()` | Manually execute a changeset |
| `pggit.refresh_query_side()` | Refresh materialized views |
| `pggit.analyze_cqrs_dependencies()` | Analyze dependencies between schemas |

### Tables

| Table | Description |
|-------|-------------|
| `pggit.cqrs_changesets` | Stores CQRS changeset metadata |
| `pggit.cqrs_operations` | Individual operations within changesets |

### Views

| View | Description |
|------|-------------|
| `pggit.cqrs_history` | Comprehensive changeset history |