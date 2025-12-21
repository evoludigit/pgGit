# pgGit v2 API Reference

**Version**: 2.0.0
**Generated**: December 22, 2025
**Status**: Production Ready

---

## Table of Contents

### [Analytics Functions](#analytics-functions)
- [analyze_storage_usage()](#analyze_storage_usage)
- [get_object_size_distribution()](#get_object_size_distribution)
- [analyze_query_performance()](#analyze_query_performance)
- [validate_data_integrity()](#validate_data_integrity)
- [detect_anomalies()](#detect_anomalies)
- [estimate_storage_growth()](#estimate_storage_growth)
- [benchmark_extraction_functions()](#benchmark_extraction_functions)

### [Monitoring Functions](#monitoring-functions)
- [check_for_alerts()](#check_for_alerts)
- [get_recommendations()](#get_recommendations)
- [get_dashboard_summary()](#get_dashboard_summary)
- [generate_monitoring_report()](#generate_monitoring_report)

### [Developer Functions](#developer-functions)
- [get_current_schema()](#get_current_schema)
- [list_objects()](#list_objects)
- [create_branch()](#create_branch)
- [list_branches()](#list_branches)
- [delete_branch()](#delete_branch)
- [get_commit_history()](#get_commit_history)
- [get_object_history()](#get_object_history)
- [diff_commits()](#diff_commits)
- [diff_branches()](#diff_branches)
- [get_object_definition()](#get_object_definition)
- [get_object_metadata()](#get_object_metadata)
- [get_head_sha()](#get_head_sha)

---

## Analytics Functions

### analyze_storage_usage()

**Purpose**: Comprehensive storage analysis and usage metrics

**Signature**:
```sql
pggit_v2.analyze_storage_usage() RETURNS TABLE (
    total_commits BIGINT,
    total_objects BIGINT,
    total_size BIGINT,
    avg_object_size BIGINT,
    largest_object_size BIGINT,
    deduplication_ratio NUMERIC
)
```

**Returns**: Storage statistics for the entire pggit_v2 system

**Example**:
```sql
SELECT * FROM pggit_v2.analyze_storage_usage();
-- total_commits | total_objects | total_size | avg_object_size | largest_object_size | deduplication_ratio
-- --------------+---------------+------------+-----------------+---------------------+--------------------
--            4 |             8 |        237 |              30 |                  65 |                1.0
```

**Performance**: < 10ms

---

### get_object_size_distribution()

**Purpose**: Analyze object size distribution for optimization insights

**Signature**:
```sql
pggit_v2.get_object_size_distribution() RETURNS TABLE (
    size_bucket TEXT,
    count BIGINT,
    total_size BIGINT
)
```

**Returns**: Objects grouped by size buckets

**Example**:
```sql
SELECT * FROM pggit_v2.get_object_size_distribution();
-- size_bucket | count | total_size
-- ------------+-------+------------
-- < 1 KB      |     8 |        237
```

**Performance**: < 5ms

---

### analyze_query_performance()

**Purpose**: Performance metrics for common pggit_v2 operations

**Signature**:
```sql
pggit_v2.analyze_query_performance() RETURNS TABLE (
    operation TEXT,
    avg_duration INTERVAL,
    min_duration INTERVAL,
    max_duration INTERVAL,
    sample_count BIGINT
)
```

**Returns**: Estimated performance characteristics

**Example**:
```sql
SELECT * FROM pggit_v2.analyze_query_performance();
-- operation      | avg_duration | min_duration  | max_duration | sample_count
-- ----------------+--------------+---------------+--------------+--------------
-- list_branches   | 00:00:00.001 | 00:00:00.0005 | 00:00:00.002 |          100
```

**Performance**: < 5ms

---

### validate_data_integrity()

**Purpose**: Comprehensive data integrity validation

**Signature**:
```sql
pggit_v2.validate_data_integrity() RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT
)
```

**Returns**: Integrity check results for all pggit_v2 data

**Example**:
```sql
SELECT * FROM pggit_v2.validate_data_integrity();
-- check_name           | status |                    details
-- ---------------------+--------+-----------------------------------------------
-- TREE_ENTRIES_REFERENCE_OBJECTS | OK     | All tree entries reference existing objects
```

**Performance**: < 20ms

---

### detect_anomalies()

**Purpose**: Detect data anomalies and potential issues

**Signature**:
```sql
pggit_v2.detect_anomalies() RETURNS TABLE (
    anomaly_type TEXT,
    severity TEXT,
    details TEXT
)
```

**Returns**: Detected anomalies in the system

**Example**:
```sql
SELECT * FROM pggit_v2.detect_anomalies();
-- anomaly_type | severity | details
-- -------------+----------+---------------------------
```

**Performance**: < 15ms

---

### estimate_storage_growth()

**Purpose**: Project future storage requirements based on usage patterns

**Signature**:
```sql
pggit_v2.estimate_storage_growth() RETURNS TABLE (
    period TEXT,
    projected_size_gb NUMERIC,
    estimated_object_count BIGINT,
    growth_trend TEXT
)
```

**Returns**: Storage growth projections

**Example**:
```sql
SELECT * FROM pggit_v2.estimate_storage_growth();
-- period  | projected_size_gb | estimated_object_count | growth_trend
-- --------+-------------------+------------------------+--------------
```

**Performance**: < 10ms

---

### benchmark_extraction_functions()

**Purpose**: Performance benchmarks for schema extraction operations

**Signature**:
```sql
pggit_v2.benchmark_extraction_functions() RETURNS TABLE (
    function_name TEXT,
    avg_runtime INTERVAL,
    sample_count BIGINT,
    status TEXT
)
```

**Returns**: Performance metrics for extraction functions

**Example**:
```sql
SELECT * FROM pggit_v2.benchmark_extraction_functions();
-- function_name          |  avg_runtime  | sample_count |  status
-- ------------------------+---------------+--------------+-----------
-- diff_trees              | 00:00:00.01   |           50 | OPTIMIZED
```

**Performance**: < 5ms

---

## Monitoring Functions

### check_for_alerts()

**Purpose**: Check for system alerts and issues requiring attention

**Signature**:
```sql
pggit_v2.check_for_alerts() RETURNS TABLE (
    severity TEXT,
    alert_type TEXT,
    message TEXT
)
```

**Returns**: Active system alerts

**Example**:
```sql
SELECT * FROM pggit_v2.check_for_alerts();
-- severity | alert_type |      message
-- ----------+------------+-------------------
-- OK       | NO_ALERTS  | System is healthy
```

**Performance**: < 10ms

---

### get_recommendations()

**Purpose**: Provide optimization recommendations based on current state

**Signature**:
```sql
pggit_v2.get_recommendations() RETURNS TABLE (
    priority TEXT,
    recommendation TEXT,
    rationale TEXT
)
```

**Returns**: System optimization suggestions

**Example**:
```sql
SELECT * FROM pggit_v2.get_recommendations();
-- priority |      recommendation       |          rationale
-- ----------+---------------------------+-----------------------------
-- INFO     | System is well-maintained | Continue regular monitoring
```

**Performance**: < 5ms

---

### get_dashboard_summary()

**Purpose**: Executive dashboard with key system metrics

**Signature**:
```sql
pggit_v2.get_dashboard_summary() RETURNS TABLE (
    category TEXT,
    metric TEXT,
    value TEXT,
    status TEXT
)
```

**Returns**: Key performance indicators and system health metrics

**Example**:
```sql
SELECT * FROM pggit_v2.get_dashboard_summary();
-- category |     metric      |   value   | status
-- ----------+-----------------+-----------+--------
-- System   | Total Objects   | 8         | OK
-- System   | Active Branches | 4         | OK
-- System   | Storage Used    | 237 bytes | OK
```

**Performance**: < 5ms

---

### generate_monitoring_report()

**Purpose**: Generate comprehensive system monitoring report

**Signature**:
```sql
pggit_v2.generate_monitoring_report() RETURNS TEXT
```

**Returns**: Formatted text report with alerts and recommendations

**Example**:
```sql
SELECT * FROM pggit_v2.generate_monitoring_report();
-- generate_monitoring_report
-- ----------------------------------------------------------------------------------------------------------
-- pgGit v2 System Report
-- Generated: 2025-12-22 10:30:00.000000+01
--
-- ALERTS:
-- No active alerts
--
-- RECOMMENDATIONS:
-- System is well-optimized
```

**Performance**: < 15ms

---

## Developer Functions

### get_current_schema()

**Purpose**: Get current schema objects at HEAD

**Signature**:
```sql
pggit_v2.get_current_schema() RETURNS TABLE (
    object_schema TEXT,
    object_name TEXT,
    object_type TEXT,
    created_at TIMESTAMPTZ,
    author TEXT
)
```

**Returns**: Objects in the current schema state

**Example**:
```sql
SELECT * FROM pggit_v2.get_current_schema();
-- object_schema | object_name | object_type | created_at | author
-- --------------+-------------+-------------+------------+--------
```

**Performance**: < 10ms

---

### list_objects()

**Purpose**: List objects at a specific commit

**Signature**:
```sql
pggit_v2.list_objects(p_commit_sha TEXT) RETURNS TABLE (
    object_path TEXT,
    object_type TEXT,
    size_bytes BIGINT
)
```

**Parameters**:
- `p_commit_sha`: Commit SHA to list objects for

**Returns**: Objects in the specified commit

**Example**:
```sql
SELECT * FROM pggit_v2.list_objects(pggit_v2.get_head_sha());
-- object_path | object_type | size_bytes
-- ------------+-------------+------------
```

**Performance**: < 10ms

---

### create_branch()

**Purpose**: Create a new branch from current HEAD

**Signature**:
```sql
pggit_v2.create_branch(
    p_branch_name TEXT,
    p_description TEXT DEFAULT ''
) RETURNS TEXT
```

**Parameters**:
- `p_branch_name`: Name of the new branch
- `p_description`: Optional description

**Returns**: Success message with branch creation details

**Example**:
```sql
SELECT pggit_v2.create_branch('feature/new-api', 'Add REST API endpoints');
-- create_branch
-- ------------------------------------------------------------------------------------------
-- feature/new-api created at abc123def456...
```

**Performance**: < 5ms

---

### list_branches()

**Purpose**: List all branches with their current commits

**Signature**:
```sql
pggit_v2.list_branches() RETURNS TABLE (
    branch_name TEXT,
    commit_sha TEXT,
    last_commit TIMESTAMPTZ
)
```

**Returns**: All branches with their head commits

**Example**:
```sql
SELECT * FROM pggit_v2.list_branches();
-- branch_name |                commit_sha                |          last_commit
-- ------------+------------------------------------------+-------------------------------
-- main        | abc123def456789012345678901234567890abc | 2025-12-22 10:30:00.000000+01
-- feature/api | def456789012345678901234567890123456def | 2025-12-22 10:25:00.000000+01
```

**Performance**: < 5ms

---

### delete_branch()

**Purpose**: Delete a branch (cannot delete main or master)

**Signature**:
```sql
pggit_v2.delete_branch(p_branch_name TEXT) RETURNS BOOLEAN
```

**Parameters**:
- `p_branch_name`: Name of branch to delete

**Returns**: TRUE if successful

**Example**:
```sql
SELECT pggit_v2.delete_branch('feature/old-feature');
-- delete_branch
-- --------------
-- t
```

**Performance**: < 5ms

---

### get_commit_history()

**Purpose**: Get paginated commit history (Git log equivalent)

**Signature**:
```sql
pggit_v2.get_commit_history(
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0
) RETURNS TABLE (
    commit_sha TEXT,
    author TEXT,
    message TEXT,
    committed_at TIMESTAMPTZ,
    parent_shas TEXT[]
)
```

**Parameters**:
- `p_limit`: Maximum commits to return (default 20)
- `p_offset`: Pagination offset (default 0)

**Returns**: Commit history with parent relationships

**Example**:
```sql
SELECT commit_sha, author, message FROM pggit_v2.get_commit_history(5);
--                commit_sha                | author |                              message
-- ------------------------------------------+--------+-------------------------------------------------------------------
-- abc123def456789012345678901234567890abc | lionel | Add user authentication system
-- def456789012345678901234567890123456def | lionel | Initial schema setup
```

**Performance**: < 10ms

---

### get_object_history()

**Purpose**: Get change history for a specific object

**Signature**:
```sql
pggit_v2.get_object_history(
    p_schema_name TEXT,
    p_object_name TEXT,
    p_limit INTEGER DEFAULT 10
) RETURNS TABLE (
    commit_sha TEXT,
    change_type TEXT,
    author TEXT,
    committed_at TIMESTAMPTZ,
    message TEXT
)
```

**Parameters**:
- `p_schema_name`: Schema containing the object
- `p_object_name`: Name of the object
- `p_limit`: Maximum changes to return

**Returns**: Change history for the specified object

**Example**:
```sql
SELECT * FROM pggit_v2.get_object_history('public', 'users', 5);
-- commit_sha | change_type | author | committed_at | message
-- -----------+-------------+--------+------------------------
```

**Performance**: < 15ms

---

### diff_commits()

**Purpose**: Show differences between two commits

**Signature**:
```sql
pggit_v2.diff_commits(
    p_old_commit_sha TEXT,
    p_new_commit_sha TEXT
) RETURNS TABLE (
    object_path TEXT,
    change_type TEXT,
    old_definition TEXT,
    new_definition TEXT
)
```

**Parameters**:
- `p_old_commit_sha`: Base commit SHA
- `p_new_commit_sha`: Target commit SHA

**Returns**: Objects that changed between commits

**Example**:
```sql
SELECT * FROM pggit_v2.diff_commits('abc123...', 'def456...');
-- object_path | change_type | old_definition | new_definition
-- ------------+-------------+----------------+----------------
```

**Performance**: < 20ms

---

### diff_branches()

**Purpose**: Compare two branches and show differences

**Signature**:
```sql
pggit_v2.diff_branches(
    p_branch_name1 TEXT,
    p_branch_name2 TEXT
) RETURNS TABLE (
    object_path TEXT,
    change_type TEXT,
    branch1_definition TEXT,
    branch2_definition TEXT
)
```

**Parameters**:
- `p_branch_name1`: First branch to compare
- `p_branch_name2`: Second branch to compare

**Returns**: Differences between the two branches

**Example**:
```sql
SELECT * FROM pggit_v2.diff_branches('main', 'feature/api');
-- object_path | change_type | branch1_definition | branch2_definition
-- ------------+-------------+--------------------+-------------------
```

**Performance**: < 20ms

---

### get_object_definition()

**Purpose**: Get DDL definition of an object

**Signature**:
```sql
pggit_v2.get_object_definition(
    p_schema_name TEXT,
    p_object_name TEXT,
    p_commit_sha TEXT DEFAULT NULL
) RETURNS TEXT
```

**Parameters**:
- `p_schema_name`: Schema containing the object
- `p_object_name`: Name of the object
- `p_commit_sha`: Optional commit SHA (defaults to HEAD)

**Returns**: Complete CREATE statement for the object

**Example**:
```sql
SELECT pggit_v2.get_object_definition('public', 'users');
-- get_object_definition
-- ---------------------------------------------------------------------------------------
-- CREATE TABLE public.users (id SERIAL PRIMARY KEY, name TEXT, email TEXT);
```

**Performance**: < 10ms

---

### get_object_metadata()

**Purpose**: Get metadata about an object

**Signature**:
```sql
pggit_v2.get_object_metadata(
    p_schema_name TEXT,
    p_object_name TEXT,
    p_commit_sha TEXT DEFAULT NULL
) RETURNS TABLE (
    object_type TEXT,
    size_bytes BIGINT,
    last_modified TIMESTAMPTZ,
    modified_by TEXT
)
```

**Parameters**:
- `p_schema_name`: Schema containing the object
- `p_object_name`: Name of the object
- `p_commit_sha`: Optional commit SHA (defaults to HEAD)

**Returns**: Object metadata and statistics

**Example**:
```sql
SELECT * FROM pggit_v2.get_object_metadata('public', 'users');
-- object_type | size_bytes | last_modified | modified_by
-- ------------+------------+---------------+-------------
-- TABLE       |       1024 | 2025-12-22... | lionel
```

**Performance**: < 5ms

---

### get_head_sha()

**Purpose**: Get the current HEAD commit SHA

**Signature**:
```sql
pggit_v2.get_head_sha() RETURNS TEXT
```

**Returns**: SHA of the current HEAD commit

**Example**:
```sql
SELECT pggit_v2.get_head_sha();
-- get_head_sha
-- ----------------------------------
-- abc123def456789012345678901234567890abc
```

**Performance**: < 1ms

---

## Error Handling

All functions include comprehensive error handling:

### Common Error Codes
- `Branch already exists`: Attempted to create duplicate branch
- `Branch not found`: Referenced non-existent branch
- `No commits found`: System has no commits yet
- `Cannot delete main branch`: Protected branch deletion attempt

### Error Response Format
```sql
-- Example error response
ERROR: Branch feature/api already exists
CONTEXT: PL/pgSQL function pggit_v2.create_branch(text,text) line 52 at RAISE
```

## Performance Characteristics

### Response Times (Typical)
- **Fast (< 5ms)**: get_head_sha, list_branches, get_dashboard_summary
- **Medium (< 15ms)**: Most analytics and monitoring functions
- **Slow (< 50ms)**: Complex diff operations and history queries

### Resource Usage
- **Memory**: Minimal (< 1MB per operation)
- **Disk I/O**: Read-heavy for history operations
- **CPU**: Light processing for most functions

## Best Practices

### Usage Guidelines
1. **Batch Operations**: Use single transactions for multiple related calls
2. **Pagination**: Use LIMIT/OFFSET for large result sets
3. **Error Handling**: Always check return values and handle errors
4. **Performance**: Cache frequently accessed data when possible

### Maintenance
1. **Regular Validation**: Run `validate_data_integrity()` daily
2. **Monitor Alerts**: Check `check_for_alerts()` regularly
3. **Performance Tuning**: Review `analyze_query_performance()` monthly

---

**Document Version**: 2.0.0
**Last Updated**: December 22, 2025
**Generated By**: pgGit v2 Documentation System