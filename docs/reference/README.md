# pgGit API Reference

Complete reference documentation for all pgGit functions, tables, and types.

## 📋 Quick Reference

### Core Functions
- [`get_version(object_name)`](#get_version) - Get current version of an object
- [`get_history(object_name)`](#get_history) - View complete change history
- [`generate_migration()`](#generate_migration) - Create migration scripts
- [`ensure_object(type, schema, name)`](#ensure_object) - Ensure object is tracked

### AI Functions
- [`analyze_migration_with_ai(name, sql, source)`](#analyze_migration_with_ai) - AI-powered migration analysis
- [`assess_migration_risk(sql)`](#assess_migration_risk) - Risk assessment for changes

### Enterprise Functions
- [`enterprise_migration_analysis(sql, config)`](#enterprise_migration_analysis) - Business impact analysis
- [`zero_downtime_strategy(from_branch, to_branch)`](#zero_downtime_strategy) - Zero-downtime deployment
- [`generate_cost_optimization_report()`](#generate_cost_optimization_report) - Cost optimization insights

### Metrics & Monitoring
- [`generate_contribution_metrics()`](#generate_contribution_metrics) - Performance metrics collection

## 📊 Data Types

### Enums

#### `pggit.object_type`
```sql
CREATE TYPE pggit.object_type AS ENUM (
    'SCHEMA', 'TABLE', 'COLUMN', 'INDEX', 'CONSTRAINT', 
    'VIEW', 'MATERIALIZED_VIEW', 'FUNCTION', 'PROCEDURE', 
    'TRIGGER', 'TYPE', 'SEQUENCE'
);
```

#### `pggit.change_type`
```sql
CREATE TYPE pggit.change_type AS ENUM (
    'CREATE', 'ALTER', 'DROP', 'RENAME', 'COMMENT'
);
```

#### `pggit.change_severity`
```sql
CREATE TYPE pggit.change_severity AS ENUM (
    'MAJOR',    -- Breaking changes
    'MINOR',    -- New features  
    'PATCH'     -- Bug fixes
);
```

## 🗄️ Core Tables

### `pggit.objects`
Tracks all database objects and their current versions.

| Column | Type | Description |
|--------|------|-------------|
| `id` | SERIAL | Primary key |
| `object_type` | `pggit.object_type` | Type of database object |
| `schema_name` | TEXT | Schema containing the object |
| `object_name` | TEXT | Name of the object |
| `full_name` | TEXT | Generated full name (schema.object) |
| `current_version` | TEXT | Current semantic version (e.g., "1.2.3") |
| `current_hash` | TEXT | SHA-256 hash of current definition |
| `created_at` | TIMESTAMP | When object was first tracked |
| `updated_at` | TIMESTAMP | Last modification timestamp |

### `pggit.history`
Complete change history for all tracked objects.

| Column | Type | Description |
|--------|------|-------------|
| `id` | SERIAL | Primary key |
| `object_id` | INTEGER | Reference to `pggit.objects.id` |
| `version` | TEXT | Version at time of change |
| `change_type` | `pggit.change_type` | Type of change made |
| `change_severity` | `pggit.change_severity` | Impact level of change |
| `definition_hash` | TEXT | Hash of object definition |
| `change_description` | TEXT | Human-readable description |
| `sql_command` | TEXT | Original SQL command |
| `changed_by` | TEXT | User who made the change |
| `change_timestamp` | TIMESTAMP | When change occurred |

### `pggit.dependencies`
Tracks relationships between database objects.

| Column | Type | Description |
|--------|------|-------------|
| `id` | SERIAL | Primary key |
| `dependent_object` | TEXT | Object that depends on another |
| `dependency_object` | TEXT | Object being depended upon |
| `dependency_type` | TEXT | Type of dependency (FK, view, etc.) |
| `created_at` | TIMESTAMP | When dependency was discovered |

## 🔧 Core Functions

### `get_version(object_name)`

Get the current version of a tracked object.

**Parameters:**

- `object_name` (TEXT) - Name of the object to query

**Returns:** 

- TABLE with object details and current version

**Example:**
```sql
SELECT * FROM pggit.get_version('users');
-- Returns: object_name, current_version, last_changed, etc.
```

### `get_history(object_name)`

Retrieve complete change history for an object.

**Parameters:**

- `object_name` (TEXT) - Name of the object

**Returns:**

- TABLE with chronological change history

**Example:**
```sql
SELECT * FROM pggit.get_history('users') ORDER BY change_timestamp DESC;
```

### `generate_migration()`

Generate migration script for tracked changes.

**Parameters:** None

**Returns:**

- TEXT containing SQL migration script

**Example:**
```sql
SELECT pggit.generate_migration();
-- Returns: Complete SQL script for all pending changes
```

### `ensure_object(type, schema, name)`

Ensure an object is being tracked by pggit.

**Parameters:**

- `type` (`pggit.object_type`) - Type of object
- `schema` (TEXT) - Schema name
- `name` (TEXT) - Object name

**Returns:**

- INTEGER (object ID)

**Example:**
```sql
SELECT pggit.ensure_object('TABLE'::pggit.object_type, 'public', 'users');
```

## 🤖 AI Functions

### `analyze_migration_with_ai(name, sql, source)`

Analyze migration using AI for risk assessment and optimization.

**Parameters:**

- `name` (TEXT) - Migration name/identifier
- `sql` (TEXT) - SQL statements to analyze
- `source` (TEXT) - Source of migration (manual, flyway, etc.)

**Returns:**

- Composite type with analysis results

**Example:**
```sql
SELECT pggit.analyze_migration_with_ai(
    'add_user_email', 
    'ALTER TABLE users ADD COLUMN email TEXT', 
    'manual'
);
-- Returns: confidence, risk_assessment, recommendations, etc.
```

### `assess_migration_risk(sql)`

Quick risk assessment for SQL statements.

**Parameters:**

- `sql` (TEXT) - SQL to assess

**Returns:**

- Composite type with risk metrics

**Example:**
```sql
SELECT pggit.assess_migration_risk('DROP TABLE important_data');
-- Returns: risk_score (0-100), risk_factors, recommendations
```

## 🏢 Enterprise Functions

### `enterprise_migration_analysis(sql, config)`

Comprehensive business impact analysis for enterprise environments.

**Parameters:**

- `sql` (TEXT) - Migration SQL
- `config` (JSONB) - Configuration including cost parameters

**Returns:**

- Composite type with business impact metrics

**Example:**
```sql
SELECT pggit.enterprise_migration_analysis(
    'CREATE INDEX CONCURRENTLY idx_user_email ON users(email)',
    '{"cost_per_minute_usd": 1000}'::jsonb
);
```

### `zero_downtime_strategy(from_branch, to_branch)`

Determine optimal zero-downtime deployment strategy.

**Parameters:**

- `from_branch` (TEXT) - Source branch/version
- `to_branch` (TEXT) - Target branch/version

**Returns:**

- Composite type with deployment strategy

**Example:**
```sql
SELECT pggit.zero_downtime_strategy('main', 'feature-new-columns');
-- Returns: strategy, estimated_time, steps, etc.
```

### `generate_cost_optimization_report()`

Generate comprehensive cost optimization report.

**Parameters:** None

**Returns:**

- TABLE with optimization opportunities

**Example:**
```sql
SELECT * FROM pggit.generate_cost_optimization_report();
-- Returns: compression savings, index optimizations, etc.
```

## 📊 Monitoring Functions

### `generate_contribution_metrics()`

Generate anonymous performance metrics for community contribution.

**Parameters:** None

**Returns:**

- JSONB with comprehensive metrics

**Example:**
```sql
SELECT pggit.generate_contribution_metrics();
-- Returns: Anonymous performance and usage metrics
```

**Sample Output:**
```json
{
  "timestamp": "2024-06-15T10:30:00Z",
  "pggit_version": "0.1.0",
  "database_objects": {
    "tables": 245,
    "indexes": 1032,
    "functions": 89
  },
  "pggit_metrics": {
    "tracked_objects": 245,
    "history_records": 1834,
    "storage_overhead_percent": 2.1
  },
  "performance_benchmarks": {
    "ai_analysis_time_ms": 23,
    "migration_generation_ms": 89
  }
}
```

## 🔧 Utility Functions

### Configuration Functions
- `configure_tracking(schemas, options)` - Configure which objects to track
- `configure_monitoring(thresholds)` - Set up performance monitoring
- `configure_security(policies)` - Configure security settings

### Maintenance Functions  
- `verify_database_integrity()` - Check pgGit data consistency
- `cleanup_old_history(days)` - Remove old history records
- `rebuild_dependencies()` - Refresh dependency tracking

### Import/Export Functions
- `export_migration_patterns()` - Export learned patterns
- `import_legacy_migrations(source)` - Import from other tools
- `generate_documentation()` - Generate schema documentation

## 📋 Views

### `pggit.current_status`
Real-time view of all tracked objects and their current state.

### `pggit.recent_changes`
View of recent changes across all objects.

### `pggit.dependency_graph`
Hierarchical view of object dependencies.

## 🚨 Error Codes

| Code | Description | Resolution |
|------|-------------|------------|
| `PGGIT001` | Object not tracked | Use `ensure_object()` first |
| `PGGIT002` | Invalid migration SQL | Check syntax and permissions |
| `PGGIT003` | AI analysis failed | Check AI service availability |
| `PGGIT004` | Dependency conflict | Resolve dependencies first |
| `PGGIT005` | Permission denied | Check user roles and permissions |

## 📚 Usage Examples

### Basic Workflow
```sql
-- 1. Create extension
CREATE EXTENSION pggit;

-- 2. Make a change
CREATE TABLE users (id SERIAL PRIMARY KEY, name TEXT);

-- 3. Check version
SELECT * FROM pggit.get_version('users');

-- 4. View history  
SELECT * FROM pggit.get_history('users');

-- 5. Generate migration
SELECT pggit.generate_migration();
```

### Enterprise Workflow
```sql
-- 1. Analyze migration with AI
SELECT pggit.analyze_migration_with_ai(
    'add_user_index',
    'CREATE INDEX CONCURRENTLY idx_users_email ON users(email)',
    'manual'
);

-- 2. Check business impact
SELECT pggit.enterprise_migration_analysis(
    'CREATE INDEX CONCURRENTLY idx_users_email ON users(email)',
    '{"cost_per_minute_usd": 500}'::jsonb
);

-- 3. Plan zero-downtime deployment
SELECT pggit.zero_downtime_strategy('v1.0', 'v1.1');

-- 4. Execute with monitoring
-- (Apply changes)

-- 5. Generate optimization report
SELECT * FROM pggit.generate_cost_optimization_report();
```

---

## 📞 API Support

- **Documentation Issues**: contact@pggit.dev
- **Function Bugs**: [GitHub Issues](https://github.com/evoludigit/pggit/issues)
- **Feature Requests**: [GitHub Discussions](https://github.com/evoludigit/pggit/discussions)

---

*This reference covers pgGit 0.1.0. Functions and behavior may change in future versions.*