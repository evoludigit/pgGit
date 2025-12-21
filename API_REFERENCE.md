# pgGit API Reference

**Version**: 0.x (Core System)
**Generated**: December 22, 2025
**Status**: Active Development

---

## Table of Contents

### [Core Functions](#core-functions)
- [get_version()](#get_version)
- [get_history()](#get_history)
- [get_dependency_order()](#get_dependency_order)

### [Branching Functions](#branching-functions)
- [create_branch()](#create_branch)
- [list_branches()](#list_branches)
- [delete_branch()](#delete_branch)
- [merge_branches()](#merge_branches)
- [checkout_branch()](#checkout_branch)

### [Size Management Functions](#size-management-functions)
- [find_unreferenced_blobs()](#find_unreferenced_blobs)
- [calculate_branch_size()](#calculate_branch_size)
- [generate_pruning_recommendations()](#generate_pruning_recommendations)

### [Migration Functions](#migration-functions)
- [generate_migration()](#generate_migration)
- [apply_migration()](#apply_migration)
- [detect_schema_changes()](#detect_schema_changes)

### [Diff Functions](#diff-functions)
- [diff_schemas()](#diff_schemas)
- [diff_table_structure()](#diff_table_structure)

### [Monitoring Functions](#monitoring-functions)
- [health_check()](#health_check)
- [performance_report()](#performance_report)
- [status()](#status)

### [Views](#views)
- [database_size_overview](#database_size_overview)
- [recent_changes](#recent_changes)
- [object_versions](#object_versions)

---

## Core Functions

### get_version()

**Purpose**: Get the current version of an object

**Signature**:
```sql
pggit.get_version(object_name TEXT) RETURNS INTEGER
```

**Parameters**:
- `object_name`: Name of the object to check

**Returns**: Current version number of the object

**Example**:
```sql
SELECT pggit.get_version('users');
-- Returns: 5
```

---

### get_history()

**Purpose**: Get the complete history of an object

**Signature**:
```sql
pggit.get_history(object_name TEXT) RETURNS TABLE (
    version INTEGER,
    ddl TEXT,
    created_at TIMESTAMP,
    author TEXT
)
```

**Parameters**:
- `object_name`: Name of the object

**Returns**: Version history with DDL changes

**Example**:
```sql
SELECT * FROM pggit.get_history('users') ORDER BY version DESC LIMIT 3;
-- version | ddl | created_at | author
-- --------+-----+------------+--------
--       5 | ... | 2025-12-22 | lionel
```

---

### get_dependency_order()

**Purpose**: Get the dependency order for schema objects

**Signature**:
```sql
pggit.get_dependency_order() RETURNS TABLE (
    object_name TEXT,
    dependency_level INTEGER
)
```

**Returns**: Objects ordered by dependency relationships

**Example**:
```sql
SELECT * FROM pggit.get_dependency_order();
-- object_name | dependency_level
-- ------------+-----------------
-- users       | 0
-- orders      | 1
```

---

## Branching Functions

### create_branch()

**Purpose**: Create a new database branch

**Signature**:
```sql
pggit.create_branch(branch_name TEXT) RETURNS TEXT
```

**Parameters**:
- `branch_name`: Name of the new branch

**Returns**: Success confirmation message

**Example**:
```sql
SELECT pggit.create_branch('feature/user-auth');
-- Returns: Branch 'feature/user-auth' created successfully
```

---

### list_branches()

**Purpose**: List all available branches

**Signature**:
```sql
pggit.list_branches() RETURNS TABLE (
    branch_name TEXT,
    created_at TIMESTAMP,
    object_count BIGINT
)
```

**Returns**: All branches with metadata

**Example**:
```sql
SELECT * FROM pggit.list_branches();
-- branch_name     | created_at | object_count
-- ----------------+------------+--------------
-- main           | 2025-12-01 | 15
-- feature/auth   | 2025-12-15 | 8
```

---

### delete_branch()

**Purpose**: Delete a branch and associated data

**Signature**:
```sql
pggit.delete_branch(branch_name TEXT) RETURNS TEXT
```

**Parameters**:
- `branch_name`: Name of branch to delete

**Returns**: Deletion confirmation message

**Example**:
```sql
SELECT pggit.delete_branch('feature/old-feature');
-- Returns: Branch 'feature/old-feature' deleted successfully
```

---

### merge_branches()

**Purpose**: Merge one branch into another

**Signature**:
```sql
pggit.merge_branches(source_branch TEXT, target_branch TEXT) RETURNS TEXT
```

**Parameters**:
- `source_branch`: Branch to merge from
- `target_branch`: Branch to merge into

**Returns**: Merge result message

**Example**:
```sql
SELECT pggit.merge_branches('feature/auth', 'main');
-- Returns: Successfully merged 3 objects from feature/auth to main
```

---

### checkout_branch()

**Purpose**: Switch to a different branch

**Signature**:
```sql
pggit.checkout_branch(branch_name TEXT) RETURNS TEXT
```

**Parameters**:
- `branch_name`: Branch to switch to

**Returns**: Checkout confirmation

**Example**:
```sql
SELECT pggit.checkout_branch('feature/new-ui');
-- Returns: Switched to branch 'feature/new-ui'
```

---

## Size Management Functions

### find_unreferenced_blobs()

**Purpose**: Find blob data that is no longer referenced

**Signature**:
```sql
pggit.find_unreferenced_blobs() RETURNS TABLE (
    blob_id TEXT,
    size_bytes BIGINT,
    created_at TIMESTAMP
)
```

**Returns**: Unreferenced blob data that can be cleaned up

**Example**:
```sql
SELECT COUNT(*), SUM(size_bytes) FROM pggit.find_unreferenced_blobs();
-- count | sum
-- ------+------
--    12 | 45000
```

---

### calculate_branch_size()

**Purpose**: Calculate the storage size of a branch

**Signature**:
```sql
pggit.calculate_branch_size(branch_name TEXT) RETURNS TABLE (
    total_objects BIGINT,
    total_size_bytes BIGINT,
    last_updated TIMESTAMP
)
```

**Parameters**:
- `branch_name`: Name of branch to analyze

**Returns**: Size metrics for the branch

**Example**:
```sql
SELECT * FROM pggit.calculate_branch_size('main');
-- total_objects | total_size_bytes | last_updated
-- --------------+-----------------+--------------
--           25 |           125000 | 2025-12-22
```

---

### generate_pruning_recommendations()

**Purpose**: Generate recommendations for cleaning up old data

**Signature**:
```sql
pggit.generate_pruning_recommendations() RETURNS TABLE (
    recommendation_type TEXT,
    target_object TEXT,
    estimated_savings_bytes BIGINT,
    priority TEXT
)
```

**Returns**: Pruning recommendations with estimated space savings

**Example**:
```sql
SELECT * FROM pggit.generate_pruning_recommendations() LIMIT 3;
-- recommendation_type | target_object | estimated_savings | priority
-- -------------------+---------------+-------------------+----------
-- old_branch         | feature/v1    |            50000 | HIGH
```

---

## Migration Functions

### generate_migration()

**Purpose**: Generate migration scripts between schema versions

**Signature**:
```sql
pggit.generate_migration(from_version INTEGER, to_version INTEGER) RETURNS TEXT
```

**Parameters**:
- `from_version`: Starting version
- `to_version`: Target version

**Returns**: SQL migration script

**Example**:
```sql
SELECT pggit.generate_migration(1, 3);
-- Returns: Complete SQL migration script
```

---

### apply_migration()

**Purpose**: Apply a migration to the current schema

**Signature**:
```sql
pggit.apply_migration(migration_sql TEXT) RETURNS TEXT
```

**Parameters**:
- `migration_sql`: Migration SQL to execute

**Returns**: Migration result message

**Example**:
```sql
SELECT pggit.apply_migration('ALTER TABLE users ADD COLUMN email TEXT;');
-- Returns: Migration applied successfully
```

---

### detect_schema_changes()

**Purpose**: Detect changes between current schema and a target schema

**Signature**:
```sql
pggit.detect_schema_changes(target_schema TEXT) RETURNS TABLE (
    change_type TEXT,
    object_name TEXT,
    details TEXT
)
```

**Parameters**:
- `target_schema`: Target schema to compare against

**Returns**: Detected schema changes

**Example**:
```sql
SELECT * FROM pggit.detect_schema_changes('production');
-- change_type | object_name | details
-- ------------+-------------+---------
-- NEW_TABLE   | audit_log   | Table added
```

---

## Diff Functions

### diff_schemas()

**Purpose**: Compare two schema states

**Signature**:
```sql
pggit.diff_schemas(schema1 TEXT, schema2 TEXT) RETURNS TABLE (
    object_name TEXT,
    change_type TEXT,
    details TEXT
)
```

**Parameters**:
- `schema1`: First schema to compare
- `schema2`: Second schema to compare

**Returns**: Schema differences

**Example**:
```sql
SELECT * FROM pggit.diff_schemas('dev', 'staging');
-- object_name | change_type | details
-- ------------+-------------+---------
-- users       | MODIFIED    | Column added: phone
```

---

### diff_table_structure()

**Purpose**: Compare table structures between versions

**Signature**:
```sql
pggit.diff_table_structure(table_name TEXT, version1 INTEGER, version2 INTEGER) RETURNS TEXT
```

**Parameters**:
- `table_name`: Table to compare
- `version1`: First version
- `version2`: Second version

**Returns**: Detailed structure differences

**Example**:
```sql
SELECT pggit.diff_table_structure('users', 1, 3);
-- Returns: Detailed column/index differences
```

---

## Monitoring Functions

### health_check()

**Purpose**: Perform a comprehensive system health check

**Signature**:
```sql
pggit.health_check() RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT
)
```

**Returns**: Health check results for all components

**Example**:
```sql
SELECT * FROM pggit.health_check();
-- check_name    | status | details
-- --------------+--------+---------
-- schema_sync   | OK     | All objects in sync
-- triggers      | OK     | All triggers active
```

---

### performance_report()

**Purpose**: Generate a performance report

**Signature**:
```sql
pggit.performance_report() RETURNS TABLE (
    metric_name TEXT,
    current_value TEXT,
    threshold TEXT,
    status TEXT
)
```

**Returns**: Performance metrics and thresholds

**Example**:
```sql
SELECT * FROM pggit.performance_report();
-- metric_name    | current_value | threshold | status
-- ---------------+---------------+-----------+--------
-- ddl_triggers   | 45ms         | 100ms    | OK
```

---

### status()

**Purpose**: Get overall system status

**Signature**:
```sql
pggit.status() RETURNS TABLE (
    component TEXT,
    status TEXT,
    last_check TIMESTAMP,
    details TEXT
)
```

**Returns**: Status of all system components

**Example**:
```sql
SELECT * FROM pggit.status();
-- component | status | last_check | details
-- ----------+--------+------------+---------
-- triggers  | ACTIVE | 2025-12-22 | 5 triggers running
```

---

## Views

### database_size_overview

**Purpose**: Overview of database size by component

**Schema**:
```sql
SELECT * FROM pggit.database_size_overview;
-- component    | size_mb | percentage
-- -------------+---------+-----------
-- objects      | 125.5  | 45.2
-- history      | 89.3   | 32.1
-- branches     | 62.1   | 22.3
```

### recent_changes

**Purpose**: Recently changed objects

**Schema**:
```sql
SELECT * FROM pggit.recent_changes;
-- object_name | change_type | changed_at | author
-- ------------+-------------+------------+--------
-- users       | MODIFIED    | 2025-12-22 | lionel
```

### object_versions

**Purpose**: Current versions of all objects

**Schema**:
```sql
SELECT * FROM pggit.object_versions;
-- object_name | current_version | last_changed
-- ------------+-----------------+--------------
-- users       | 5               | 2025-12-22
```

---

## Error Handling

All functions include comprehensive error handling:

### Common Error Messages
- `Branch already exists`: Attempted to create duplicate branch
- `Branch not found`: Referenced non-existent branch
- `Circular dependency detected`: Invalid dependency relationships
- `Migration failed`: Migration execution error

### Error Response Format
```sql
-- Example error
ERROR:  Branch 'feature/auth' already exists
CONTEXT:  PL/pgSQL function pggit.create_branch(text) line 15
```

## Performance Characteristics

### Response Times (Typical)
- **Fast (< 10ms)**: get_version, basic status checks
- **Medium (< 100ms)**: diff operations, size calculations
- **Slow (< 1000ms)**: Complex migrations, full schema comparisons

### Resource Usage
- **Memory**: Moderate (depends on schema complexity)
- **Storage**: Additional ~10-20% for versioning data
- **CPU**: Light for normal operations, heavier for analysis

## Best Practices

### Usage Guidelines
1. **Regular Health Checks**: Run `health_check()` daily
2. **Size Monitoring**: Use `database_size_overview` to track growth
3. **Branch Cleanup**: Regularly prune old branches with `generate_pruning_recommendations()`
4. **Migration Testing**: Always test migrations in staging first

### Maintenance
1. **Weekly**: Review `performance_report()` for optimization opportunities
2. **Monthly**: Run `generate_pruning_recommendations()` and clean up
3. **Quarterly**: Full schema audit and dependency analysis

---

**Version**: 0.x
**Last Updated**: December 22, 2025
**Documentation**: Work in progress
**Support**: GitHub Issues