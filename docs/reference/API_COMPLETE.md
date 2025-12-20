# pgGit API Reference

Complete reference for all pgGit functions.

## Overview

pgGit provides a comprehensive SQL API for database version control. All functions are available in the `pggit` schema and work directly within PostgreSQL.

### Function Categories

- **Core Functions**: Basic versioning and tracking operations
- **Migration Functions**: Schema change generation and management
- **Utility Functions**: Helper and maintenance functions
- **Analysis Functions**: Migration analysis and impact assessment

### Total Functions: 10
- Core Functions: 7
- Analysis Functions: 3

---

## Core Functions

### `pggit.ensure_object(object_type, schema_name, object_name)`

**Purpose**: Register or get existing object ID in pgGit tracking.

**Signature**:
```sql
pggit.ensure_object(
    object_type pggit.object_type,
    schema_name TEXT,
    object_name TEXT
) RETURNS INTEGER
```

**Parameters**:
- `object_type`: Type of database object (TABLE, VIEW, FUNCTION, etc.)
- `schema_name`: Schema containing the object
- `object_name`: Name of the database object

**Returns**: `INTEGER` - The object ID for tracking

**Example**:
```sql
SELECT pggit.ensure_object('TABLE'::pggit.object_type, 'public', 'users');
-- Returns: 1
```

---

### `pggit.get_version(object_name)`

**Purpose**: Get the semantic version for a tracked database object.

**Signature**:
```sql
pggit.get_version(object_name TEXT) RETURNS TABLE (
    object_name TEXT,
    object_type pggit.object_type,
    version TEXT,
    version_number INTEGER,
    is_active BOOLEAN
)
```

**Parameters**:
- `object_name`: Name of the database object

**Returns**: Table with version information

**Example**:
```sql
SELECT * FROM pggit.get_version('users');
-- object_name | object_type | version | version_number | is_active
-- users       | TABLE       | 1.0.0   | 100           | true
```

---

### `pggit.get_history(object_name)`

**Purpose**: View the change history for a database object.

**Signature**:
```sql
pggit.get_history(object_name TEXT) RETURNS TABLE (
    object_id INTEGER,
    change_type pggit.change_type,
    change_description TEXT,
    created_at TIMESTAMP,
    created_by TEXT
)
```

**Parameters**:
- `object_name`: Name of the database object

**Returns**: Table with change history

**Example**:
```sql
SELECT * FROM pggit.get_history('users')
ORDER BY created_at DESC
LIMIT 5;
```

---

### `pggit.generate_migration(description, schema_name)`

**Purpose**: Generate a migration script from detected schema changes.

**Signature**:
```sql
pggit.generate_migration(
    description TEXT DEFAULT NULL,
    schema_name TEXT DEFAULT 'public'
) RETURNS TEXT
```

**Parameters**:
- `description`: Optional description for the migration
- `schema_name`: Schema to analyze for changes

**Returns**: `TEXT` - Complete SQL migration script

**Example**:
```sql
SELECT pggit.generate_migration('Add user profiles', 'public');
-- Returns full migration SQL
```

---

### `pggit.determine_severity(command_tag, object_type)`

**Purpose**: Classify the severity of a database change operation.

**Signature**:
```sql
pggit.determine_severity(
    command_tag TEXT,
    object_type TEXT
) RETURNS pggit.change_severity
```

**Parameters**:
- `command_tag`: SQL command type (CREATE, ALTER, DROP)
- `object_type`: Type of database object

**Returns**: `pggit.change_severity` - BREAKING, MAJOR, MINOR, or PATCH

**Example**:
```sql
SELECT pggit.determine_severity('DROP TABLE', 'TABLE');
-- Returns: MAJOR
```

---

### `pggit.handle_ddl_command()`

**Purpose**: Event trigger function that processes DDL commands for tracking.

**Signature**:
```sql
pggit.handle_ddl_command() RETURNS event_trigger
```

**Parameters**: None (called by PostgreSQL event system)

**Returns**: `event_trigger`

**Example**:
```sql
-- Called automatically by PostgreSQL event triggers
-- No manual invocation needed
```

---

### `pggit.increment_version(object_id, change_type, severity)`

**Purpose**: Increment the version number for a tracked object.

**Signature**:
```sql
pggit.increment_version(
    object_id INTEGER,
    change_type pggit.change_type,
    severity pggit.change_severity
) RETURNS INTEGER
```

**Parameters**:
- `object_id`: ID of the object to version
- `change_type`: Type of change (CREATE, ALTER, DROP)
- `severity`: Severity of the change

**Returns**: `INTEGER` - New version number

**Example**:
```sql
SELECT pggit.increment_version(1, 'ALTER', 'MINOR');
-- Returns: 101 (version 1.0.1)
```

---

## Analysis Functions

### `pggit.analyze_migration_with_llm(migration_sql, analysis_type)`

**Purpose**: Analyze migration SQL using LLM for risk assessment.

**Signature**:
```sql
pggit.analyze_migration_with_llm(
    migration_sql TEXT,
    analysis_type TEXT DEFAULT 'comprehensive'
) RETURNS TABLE (
    risk_level TEXT,
    confidence DECIMAL,
    recommendations TEXT[],
    concerns TEXT[]
)
```

**Parameters**:
- `migration_sql`: SQL migration script to analyze
- `analysis_type`: Type of analysis (comprehensive, quick, detailed)

**Returns**: Analysis results with risk assessment

**Example**:
```sql
SELECT * FROM pggit.analyze_migration_with_llm(
    'ALTER TABLE users ADD COLUMN email TEXT;'
);
```

---

### `pggit.run_edge_case_tests()`

**Purpose**: Run comprehensive tests for edge cases in pgGit functionality.

**Signature**:
```sql
pggit.run_edge_case_tests() RETURNS TABLE (
    test_name TEXT,
    passed BOOLEAN,
    details TEXT
)
```

**Parameters**: None

**Returns**: Test results for edge cases

**Example**:
```sql
SELECT * FROM pggit.run_edge_case_tests()
WHERE passed = false;
```

---

### `pggit.get_impact_analysis(object_name)`

**Purpose**: Analyze the impact of changes to a database object.

**Signature**:
```sql
pggit.get_impact_analysis(object_name TEXT) RETURNS TABLE (
    dependency_type TEXT,
    dependent_object TEXT,
    impact_level TEXT,
    risk_assessment TEXT
)
```

**Parameters**:
- `object_name`: Name of the object to analyze

**Returns**: Impact analysis for dependent objects

**Example**:
```sql
SELECT * FROM pggit.get_impact_analysis('users');
```

---

## Usage Patterns

### Basic Version Tracking
```sql
-- Track a table
CREATE TABLE users (id SERIAL PRIMARY KEY, name TEXT);

-- Check version
SELECT * FROM pggit.get_version('users');

-- View history
SELECT * FROM pggit.get_history('users');
```

### Migration Workflow
```sql
-- Make schema changes
ALTER TABLE users ADD COLUMN email TEXT;

-- Generate migration
SELECT pggit.generate_migration('Add email column');

-- Analyze impact
SELECT * FROM pggit.get_impact_analysis('users');
```

### Advanced Analysis
```sql
-- LLM-powered analysis
SELECT * FROM pggit.analyze_migration_with_llm(
    'ALTER TABLE users DROP COLUMN old_field;'
);

-- Run edge case tests
SELECT * FROM pggit.run_edge_case_tests();
```

---

## Auto-Generated Documentation

For the complete auto-generated API reference with all function signatures, run:
```bash
psql -f scripts/generate-api-docs.sql
cat /tmp/api-reference.md
```

This generates detailed documentation for all pgGit functions with current signatures and examples.