# pggit Feature Requirements for PrintOptim Backend

**Issue Type**: Feature Request / Compatibility Enhancement  
**Priority**: High  
**PrintOptim Version**: 0.2.0  
**PostgreSQL Version**: 17  
**pggit Version**: Current (experiencing conflicts)  
**Date**: 2025-06-20

## Executive Summary

PrintOptim is a production-ready SaaS platform using PostgreSQL 17 with a CQRS architecture. We've experienced significant challenges integrating pggit into our workflow, requiring multiple workaround scripts. This document outlines specific requirements that would make pggit a viable solution for our database version control needs.

## Current Pain Points

### 1. PostgreSQL 17 Compatibility Issues
- Function conflicts with `pggit.ensure_object()` 
- Constraint violations (`check_version_consistency`)
- Event triggers interfering with new PG17 features (JSON_TABLE, optimizer improvements)
- Required workarounds disrupt our CI/CD pipeline

### 2. CQRS Architecture Conflicts
Our architecture separates concerns across multiple schemas:
```sql
-- Command Side
CREATE SCHEMA command;        -- Write operations
CREATE SCHEMA command_staging;-- ETL staging area

-- Query Side  
CREATE SCHEMA query;         -- Materialized views
CREATE SCHEMA query_cache;   -- Performance optimization

-- Shared
CREATE SCHEMA reference;     -- Lookup tables
```

**Issues encountered:**
- Event triggers fire across all schemas causing cascade effects
- Materialized view refreshes trigger unnecessary version bumps
- Cross-schema dependencies create circular tracking issues

### 3. SQL-First Development Friction
Our approach uses PostgreSQL functions for all business logic:
```sql
-- Example mutation function
CREATE FUNCTION app.create_machine_with_log(input jsonb)
RETURNS jsonb AS $$
BEGIN
    -- Complex business logic
    -- Returns standardized JSON result
END;
$$ LANGUAGE plpgsql;
```

**Problems:**
- Function replacements trigger multiple pggit events
- Overloaded functions cause version conflicts
- Type changes cascade through dependent functions

## Specific Requirements for pggit

### 1. Selective Schema Tracking
```sql
-- Allow configuration of tracked schemas
SELECT pggit.configure(
    track_schemas => ARRAY['command', 'reference'],
    ignore_schemas => ARRAY['query', 'query_cache', 'pg_temp%']
);

-- Or per-object opt-in/opt-out
COMMENT ON TABLE command.tb_machine IS '@pggit-track';
COMMENT ON MATERIALIZED VIEW query.mv_machine IS '@pggit-ignore';
```

### 2. Operation Filtering
```sql
-- Configure which operations to track
SELECT pggit.configure(
    track_operations => ARRAY['CREATE', 'ALTER', 'DROP'],
    ignore_operations => ARRAY['REFRESH MATERIALIZED VIEW', 'REINDEX']
);

-- Ignore specific patterns
SELECT pggit.add_ignore_pattern('REFRESH MATERIALIZED VIEW query.%');
SELECT pggit.add_ignore_pattern('CREATE TEMP TABLE %');
```

### 3. Deployment Mode
```sql
-- Temporarily batch operations without triggering individual events
SELECT pggit.begin_deployment('Release 2.1.0');

-- Make multiple schema changes
CREATE TABLE ...;
ALTER TABLE ...;
CREATE OR REPLACE FUNCTION ...;

-- Commit as single version
SELECT pggit.end_deployment();
```

### 4. CQRS-Aware Tracking
```sql
-- Track command and query sides separately
SELECT pggit.track_cqrs_change(
    command_sql => 'ALTER TABLE command.tb_machine ADD COLUMN status TEXT',
    query_sql => 'DROP MATERIALIZED VIEW query.mv_machine; CREATE MATERIALIZED VIEW query.mv_machine AS ...',
    version => '2.1.0',
    description => 'Add machine status field'
);
```

### 5. Function Versioning Strategy
```sql
-- Handle function overloading gracefully
CREATE OR REPLACE FUNCTION app.process_meter(
    meter_id UUID,
    readings JSONB,
    -- pggit metadata in comment
    /* @pggit-version: 1.2.3 */
) RETURNS jsonb AS $$ ... $$;

-- Track function signatures, not just names
SELECT pggit.get_function_version('app.process_meter(uuid, jsonb)');
```

### 6. Conflict Resolution API
```sql
-- Provide clear conflict resolution
SELECT pggit.resolve_conflict(
    conflict_id => 'uuid-here',
    resolution => 'use_current',  -- or 'use_tracked', 'merge'
    reason => 'Production hotfix override'
);

-- Force consistency check
SELECT pggit.verify_consistency(
    fix_issues => true,
    verbose => true
);
```

### 7. Migration Integration
```sql
-- Work alongside traditional migration tools
CREATE TABLE pggit.migration_tracking (
    migration_id BIGINT,
    pggit_version_start UUID,
    pggit_version_end UUID,
    applied_at TIMESTAMPTZ
);

-- Link migrations to pggit versions
SELECT pggit.link_migration(
    migration_id => 20250620001,
    description => 'Add ETL staging tables'
);
```

### 8. Performance Optimizations
- **Async tracking**: Don't block DDL operations
- **Batch processing**: Group related changes
- **Conditional tracking**: Skip in test/CI environments
- **Lightweight mode**: Minimal overhead option

### 9. PostgreSQL 17 Specific Support
- JSON_TABLE compatibility
- New optimizer features support
- MERGE statement tracking
- Improved partition management tracking

### 10. Operational Commands
```sql
-- Emergency escape hatches
SELECT pggit.emergency_disable(duration => '1 hour');
SELECT pggit.purge_history(older_than => '6 months');
SELECT pggit.export_schema_snapshot(path => '/backup/schema.sql');
SELECT pggit.compare_environments('production', 'staging');
```

## Use Case Example

Here's how we'd like pggit to work in our workflow:

```sql
-- 1. Start deployment
SELECT pggit.begin_deployment('v2.1.0-add-meter-validation');

-- 2. Apply command side changes
ALTER TABLE command.tb_meter 
ADD CONSTRAINT check_reading_positive CHECK (reading_value > 0);

-- 3. Update functions
CREATE OR REPLACE FUNCTION app.validate_meter_with_log(input jsonb)
RETURNS jsonb AS $$ ... $$ LANGUAGE plpgsql;

-- 4. Rebuild query side
DROP MATERIALIZED VIEW IF EXISTS query.mv_meter_summary;
CREATE MATERIALIZED VIEW query.mv_meter_summary AS
SELECT ... FROM command.tb_meter ...;

-- 5. Complete deployment
SELECT pggit.end_deployment(
    commit_message => 'Add positive value validation to meter readings',
    tags => ARRAY['validation', 'meter']
);
```

## Success Criteria

pggit would be production-ready for PrintOptim when:

1. ✅ Zero conflicts during normal deployments
2. ✅ PostgreSQL 17 features fully supported
3. ✅ CQRS architecture patterns recognized
4. ✅ Performance overhead < 1% for DDL operations
5. ✅ Clear separation between development and production tracking
6. ✅ Integration with existing migration tools
7. ✅ Ability to disable/enable without breaking deployments
8. ✅ Comprehensive conflict resolution tools

## Current Workarounds We Want to Eliminate

```bash
# scripts/db/manage_pggit.sh
- disable_pggit_temporarily.sql
- enable_pggit_temporarily.sql  
- fix_pggit_function_conflicts.sql
- fix_pggit_constraints.sql
```

## Proposed Timeline

If the pggit team can implement these features, we would:
1. **Immediately**: Beta test new features in development
2. **Week 2-3**: Validate in staging environment
3. **Week 4**: Deploy to production with monitoring
4. **Ongoing**: Provide feedback and co-develop features

## Contact Information

**PrintOptim Technical Team**:
- Architecture: Viktor (Senior Developer)
- Database: Elena (DBA)
- DevOps: Sarah (DevOps Engineer)
- Project: Lionel Hamayon (lionel.hamayon@evolution-digitale.fr)

We're committed to making pggit work for complex architectures like ours and happy to collaborate on design and testing.

---

**Note**: We're currently evaluating alternatives but would strongly prefer to use pggit if these requirements can be met. The automatic tracking and git-like semantics align perfectly with our development philosophy - we just need it to work reliably with our architecture.