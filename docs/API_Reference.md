# pgGit API Reference

**Complete function reference for PostgreSQL database branching**

## ⚠️ Function Status Notice

Many functions documented below are **planned for future versions** and do not currently exist in pgGit v0.1.x. Functions are marked with status badges:

- ✅ **Implemented** - Available in current version
- 🚧 **Planned** - Designed but not yet implemented
- 🧪 **Experimental** - Implemented but may change

## Overview

pgGit provides a comprehensive SQL API for database version control. All
functions are available in the `pggit` schema and work directly within
PostgreSQL.

**Core Philosophy:** If you know Git, you know pgGit. The API mirrors Git
workflows with database-specific enhancements.

---

## 🌿 Branch Management

### `create_branch()`

Creates a new schema-only branch.

```sql
pggit.create_branch(
    p_branch_name TEXT,
    p_parent_branch TEXT DEFAULT 'main'
) RETURNS INTEGER
```

**Parameters:**

- `p_branch_name`: Name of the new branch (must be unique)
- `p_parent_branch`: Parent branch to branch from (default: 'main')

**Returns:** Branch ID

**Example:**

```sql
-- Create a feature branch from main
SELECT pggit.create_branch('feature/user-auth', 'main');
-- Returns: 5

-- Create a hotfix branch from production
SELECT pggit.create_branch('hotfix/login-bug', 'production');
-- Returns: 6
```

### `create_data_branch()`

Creates a branch with actual data isolation using copy-on-write.

```sql
pggit.create_data_branch(
    p_branch_name TEXT,
    p_parent_branch TEXT DEFAULT 'main',
    p_copy_data BOOLEAN DEFAULT true
) RETURNS INTEGER
```

**Parameters:**

- `p_branch_name`: Name of the new branch
- `p_parent_branch`: Parent branch to branch from
- `p_copy_data`: Whether to enable data copy-on-write (recommended: true)

**Returns:** Branch ID

**Example:**

```sql
-- Create branch with data isolation
SELECT pggit.create_data_branch('feature/profile-redesign', 'main', true);

-- Create schema-only branch (faster)
SELECT pggit.create_data_branch('ci/build-123', 'main', false);
```

### `create_compressed_data_branch()` ⭐

**PostgreSQL 17+ only** - Creates branch with advanced compression.

```sql
pggit.create_compressed_data_branch(
    p_branch_name TEXT,
    p_parent_branch TEXT DEFAULT 'main',
    p_copy_data BOOLEAN DEFAULT true
) RETURNS INTEGER
```

**Features:**

- LZ4/ZSTD compression (70% storage reduction)
- Column-level compression optimization
- Performance monitoring

**Example:**

```sql
-- Create compressed branch (PostgreSQL 17)
SELECT pggit.create_compressed_data_branch('feature/pg17-optimized', 'main', true);
-- NOTICE: 📊 Compression achieved: 1024 kB → 307 kB (70.02% reduction)
```

### `checkout_branch()`

Switches current session to specified branch.

```sql
pggit.checkout_branch(p_branch_name TEXT) RETURNS TEXT
```

**Parameters:**

- `p_branch_name`: Target branch name

**Returns:** Success message

**Example:**

```sql
-- Switch to feature branch
SELECT pggit.checkout_branch('feature/user-auth');
-- Returns: 'Switched to branch: feature/user-auth'

-- All subsequent operations now affect this branch
CREATE TABLE users (id SERIAL PRIMARY KEY, name TEXT);
```

### `get_current_branch()`

Returns the currently active branch.

```sql
pggit.get_current_branch() RETURNS TEXT
```

**Example:**

```sql
SELECT pggit.get_current_branch();
-- Returns: 'feature/user-auth'
```

### `list_branches()`

Lists all branches with metadata.

```sql
pggit.list_branches() RETURNS TABLE (
    branch_name TEXT,
    parent_branch TEXT,
    status TEXT,
    total_objects INTEGER,
    storage_efficiency DECIMAL,
    created_at TIMESTAMP
)
```

**Example:**

```sql
SELECT * FROM pggit.list_branches();
-- branch_name        | parent_branch | status | total_objects | storage_efficiency | created_at
-- main               | NULL          | ACTIVE | 15           | 100.00            | 2024-01-01 10:00:00
-- feature/user-auth  | main          | ACTIVE | 18           | 67.85             | 2024-01-02 14:30:00
```

---

## 🔀 Merge Operations

### `merge_branches()`

Merges schema changes between branches.

```sql
pggit.merge_branches(
    p_source_branch TEXT,
    p_target_branch TEXT
) RETURNS TEXT
```

**Parameters:**

- `p_source_branch`: Branch to merge from
- `p_target_branch`: Branch to merge into

**Returns:** Merge result ('MERGE_SUCCESS' or 'CONFLICTS_DETECTED')

**Example:**

```sql
-- Merge feature branch to main
SELECT pggit.merge_branches('feature/user-auth', 'main');
-- Returns: 'MERGE_SUCCESS:commit_hash_here'

-- Merge with conflicts
SELECT pggit.merge_branches('feature/conflicting', 'main');
-- Returns: 'CONFLICTS_DETECTED:merge_id_abc123'
```

### `merge_compressed_branches()` ⭐

**PostgreSQL 17+ only** - Advanced merge with compression optimization.

```sql
pggit.merge_compressed_branches(
    p_source_branch TEXT,
    p_target_branch TEXT
) RETURNS TEXT
```

**Features:**

- Compression-aware conflict resolution
- Storage optimization during merge
- Performance monitoring

**Example:**

```sql
SELECT pggit.merge_compressed_branches('feature/pg17-branch', 'main');
-- NOTICE: 🔀 Merging with compression optimization
-- NOTICE: 📊 Storage optimized: 1.2GB → 360MB (70% efficiency maintained)
-- Returns: 'MERGE_SUCCESS:abcd1234...'
```

### `auto_resolve_compressed_conflicts()`

Automatically resolves merge conflicts using compression heuristics.

```sql
pggit.auto_resolve_compressed_conflicts(
    p_merge_id TEXT,
    p_strategy TEXT DEFAULT 'COMPRESSION_OPTIMIZED'
) RETURNS TEXT
```

**Strategies:**

- `COMPRESSION_OPTIMIZED`: Choose version with better compression
- `TAKE_SOURCE`: Always take source branch version
- `TAKE_TARGET`: Always take target branch version

**Example:**

```sql
-- Auto-resolve using compression optimization
SELECT pggit.auto_resolve_compressed_conflicts(
    'merge_abc123',
    'COMPRESSION_OPTIMIZED'
);
-- Returns: 'CONFLICTS_RESOLVED:5_auto_3_manual'
```

---

## 📊 Monitoring & Statistics

### `get_branch_storage_stats()`

Returns storage statistics for branches.

```sql
pggit.get_branch_storage_stats(
    p_branch_name TEXT DEFAULT NULL
) RETURNS TABLE (
    branch_name TEXT,
    table_count INTEGER,
    total_size TEXT,
    compressed_size TEXT,
    compression_ratio DECIMAL,
    space_saved TEXT
)
```

**Example:**

```sql
-- All branches
SELECT * FROM pggit.get_branch_storage_stats();

-- Specific branch
SELECT * FROM pggit.get_branch_storage_stats('feature/user-auth');
-- branch_name: feature/user-auth
-- table_count: 3
-- total_size: 1024 kB
-- compressed_size: 307 kB
-- compression_ratio: 70.02%
-- space_saved: 717 kB
```

### `get_compression_stats()`

Returns detailed compression statistics.

```sql
pggit.get_compression_stats() RETURNS TABLE (
    table_name TEXT,
    branch_name TEXT,
    original_size TEXT,
    compressed_size TEXT,
    compression_ratio DECIMAL,
    space_saved TEXT
)
```

### `get_performance_stats()`

Returns overall system performance metrics.

```sql
pggit.get_performance_stats() RETURNS TABLE (
    metric_name TEXT,
    metric_value TEXT,
    description TEXT
)
```

**Example:**

```sql
SELECT * FROM pggit.get_performance_stats();
-- metric_name: total_branches | metric_value: 12 | description: Active branches
-- metric_name: avg_compression | metric_value: 68.5% | description: Average compression ratio
-- metric_name: storage_saved | metric_value: 15.2 GB | description: Total space saved
```

---

## 📋 Object Tracking

### `get_version()`

Gets current version of a database object.

```sql
pggit.get_version(p_object_name TEXT) RETURNS TEXT
```

**Example:**

```sql
SELECT pggit.get_version('users');
-- Returns: '2.1.3'

SELECT pggit.get_version('user_profiles');
-- Returns: '1.0.0'
```

### `get_history()`

Returns complete change history for an object.

```sql
pggit.get_history(p_object_name TEXT) RETURNS TABLE (
    version TEXT,
    change_type TEXT,
    change_description TEXT,
    author TEXT,
    timestamp TIMESTAMP
)
```

**Example:**

```sql
SELECT * FROM pggit.get_history('users');
-- version | change_type | change_description           | author | timestamp
-- 1.0.0   | CREATE      | Initial table creation       | alice  | 2024-01-01 10:00:00
-- 2.0.0   | ALTER       | Added email column (NOT NULL)| bob    | 2024-01-02 14:00:00
-- 2.1.0   | ALTER       | Added preferences JSONB      | carol  | 2024-01-03 09:30:00
```

### `get_impact_analysis()`

Analyzes dependencies before making changes.

```sql
pggit.get_impact_analysis(p_object_name TEXT) RETURNS TABLE (
    dependent_object TEXT,
    dependency_type TEXT,
    impact_level TEXT,
    suggested_action TEXT
)
```

**Example:**

```sql
SELECT * FROM pggit.get_impact_analysis('users');
-- dependent_object | dependency_type | impact_level | suggested_action
-- user_profiles    | FOREIGN_KEY     | HIGH        | Update FK constraint
-- user_sessions    | VIEW           | MEDIUM      | Recreate view
-- user_index       | INDEX          | LOW         | Automatic rebuild
```

---

## 🤖 AI-Powered Migration Analysis

### `analyze_migration_with_llm()` ⭐

**NEW:** Analyzes SQL migrations using real GPT-2 neural network.

```sql
pggit.analyze_migration_with_llm(
    p_migration_content TEXT,
    p_source_tool TEXT DEFAULT 'manual',
    p_migration_name TEXT DEFAULT 'migration.sql'
) RETURNS TABLE (
    intent TEXT,
    pattern_type TEXT,
    confidence DECIMAL(3,2),
    pggit_template TEXT,
    semantic_meaning TEXT,
    ai_insight TEXT,
    risk_assessment TEXT
)
```

**Parameters:**

- `p_migration_content`: SQL migration content to analyze
- `p_source_tool`: Source tool ('flyway', 'liquibase', 'rails', 'manual')
- `p_migration_name`: Migration filename for reference

**Returns:** Comprehensive AI analysis with neural network insights

**Example:**

```sql
-- Analyze a CREATE TABLE migration
SELECT * FROM pggit.analyze_migration_with_llm(
    'CREATE TABLE products (id SERIAL PRIMARY KEY, name VARCHAR(255), price DECIMAL(10,2));',
    'flyway',
    'V1__create_products.sql'
);

-- Results:
-- intent: Create new table (AI: create new table for storing product)
-- pattern_type: CREATE_TABLE
-- confidence: 0.90
-- pggit_template: CREATE TABLE {{schema}}.{{table}} ({{columns}})
-- semantic_meaning: Standard table creation pattern
-- ai_insight: create new table for storing product information with pricing
-- risk_assessment: LOW
```

### `ai_migrate_batch()` 🚧 PLANNED

Batch processes multiple migrations with AI analysis.

```sql
pggit.ai_migrate_batch(
    p_migrations JSONB,
    p_source_tool TEXT DEFAULT 'manual'
) RETURNS TABLE (
    migration_name TEXT,
    status TEXT,
    confidence DECIMAL(3,2),
    risk_level TEXT,
    processing_time_ms INTEGER
)
```

**Parameters:**

- `p_migrations`: JSON array of migration objects with 'name' and 'content'
- `p_source_tool`: Source migration tool

**Example:**

```sql
-- Batch analyze multiple migrations
SELECT * FROM pggit.ai_migrate_batch(
    '[
        {"name": "V1__create_users.sql", "content": "CREATE TABLE users (id SERIAL PRIMARY KEY);"},
        {"name": "V2__add_email.sql", "content": "ALTER TABLE users ADD COLUMN email VARCHAR(255);"},
        {"name": "V3__risky_drop.sql", "content": "DROP TABLE old_users;"}
    ]'::jsonb,
    'flyway'
);

-- Results show individual analysis for each migration:
-- migration_name: V1__create_users.sql | status: SUCCESS | confidence: 0.90 | risk_level: LOW
-- migration_name: V2__add_email.sql   | status: SUCCESS | confidence: 0.80 | risk_level: LOW
-- migration_name: V3__risky_drop.sql  | status: REVIEW_NEEDED | confidence: 0.60 | risk_level: HIGH
```

### `run_edge_case_tests()`

Runs comprehensive AI edge case detection tests.

```sql
pggit.run_edge_case_tests() RETURNS TABLE (
    test_name TEXT,
    migration_name TEXT,
    confidence DECIMAL(3,2),
    risk_level TEXT,
    processing_time_ms INTEGER,
    expected_outcome TEXT,
    actual_outcome TEXT,
    passed BOOLEAN,
    notes TEXT
)
```

**Example:**

```sql
-- Run all edge case tests
SELECT * FROM pggit.run_edge_case_tests();

-- Sample results:
-- test_name: SQL Injection Detection
-- migration_name: malicious_update.sql
-- confidence: 0.45
-- risk_level: HIGH
-- expected_outcome: HIGH_RISK_DETECTED
-- actual_outcome: HIGH_RISK_DETECTED
-- passed: true
-- notes: Correctly flagged potential SQL injection pattern
```

---

## 📊 AI Performance Monitoring

### AI Decision History

```sql
-- View recent AI analyses
SELECT
    migration_id,
    confidence,
    model_version,
    inference_time_ms,
    created_at
FROM pggit.ai_decisions
ORDER BY created_at DESC
LIMIT 10;
```

### AI Edge Cases

```sql
-- View detected edge cases and risks
SELECT
    migration_id,
    case_type,
    risk_level,
    confidence,
    created_at
FROM pggit.ai_edge_cases
WHERE created_at > NOW() - INTERVAL '24 hours'
ORDER BY risk_level DESC;
```

### AI Performance Stats

```sql
-- Get AI performance metrics
SELECT
    COUNT(*) as total_analyses,
    ROUND(AVG(confidence * 100), 1) as avg_confidence_pct,
    ROUND(AVG(inference_time_ms), 0) as avg_time_ms,
    COUNT(*) FILTER (WHERE confidence >= 0.8) as high_confidence_count,
    COUNT(*) FILTER (WHERE confidence < 0.8) as needs_review_count
FROM pggit.ai_decisions
WHERE created_at > NOW() - INTERVAL '1 hour';
```

---

## 🔄 Migration Functions

### `generate_migration()`

Generates migration scripts between versions.

```sql
pggit.generate_migration(
    p_from_version TEXT,
    p_to_version TEXT,
    p_object_name TEXT DEFAULT NULL
) RETURNS TEXT
```

**Parameters:**

- `p_from_version`: Source version or branch
- `p_to_version`: Target version or branch
- `p_object_name`: Specific object (NULL for all objects)

**Example:**

```sql
-- Generate migration from v1.0 to v2.0
SELECT pggit.generate_migration('1.0.0', '2.0.0', 'users');
-- Returns:
-- -- Migration: users 1.0.0 → 2.0.0
-- ALTER TABLE users ADD COLUMN email TEXT NOT NULL;
-- CREATE INDEX idx_users_email ON users(email);

-- Generate migration between branches
SELECT pggit.generate_migration('main', 'feature/user-auth');
```

### `apply_migration()`

Applies a generated migration safely.

```sql
pggit.apply_migration(
    p_migration_sql TEXT,
    p_dry_run BOOLEAN DEFAULT true
) RETURNS TEXT
```

**Example:**

```sql
-- Dry run first (recommended)
SELECT pggit.apply_migration('ALTER TABLE users ADD COLUMN email TEXT;', true);
-- Returns: 'DRY_RUN_SUCCESS: Migration validated, 0 conflicts detected'

-- Apply for real
SELECT pggit.apply_migration('ALTER TABLE users ADD COLUMN email TEXT;', false);
-- Returns: 'MIGRATION_APPLIED: 1 statement executed successfully'
```

---

## 🧪 Testing & Validation

### `validate_branch_integrity()`

Validates branch consistency and data integrity.

```sql
pggit.validate_branch_integrity(p_branch_name TEXT) RETURNS TABLE (
    check_type TEXT,
    status TEXT,
    details TEXT
)
```

**Example:**

```sql
SELECT * FROM pggit.validate_branch_integrity('feature/user-auth');
-- check_type: SCHEMA_CONSISTENCY | status: PASS | details: All objects valid
-- check_type: DATA_INTEGRITY     | status: PASS | details: 0 orphaned rows
-- check_type: COMPRESSION        | status: PASS | details: 68.5% efficiency
```

### `benchmark_compression_performance()`

Benchmarks compression performance with test data.

```sql
pggit.benchmark_compression_performance(
    p_dataset_size TEXT DEFAULT 'MEDIUM'
) RETURNS TABLE (
    metric TEXT,
    without_compression TEXT,
    with_compression TEXT,
    improvement TEXT
)
```

**Dataset sizes:** 'SMALL' (1K), 'MEDIUM' (10K), 'LARGE' (100K), 'ENTERPRISE' (1M+)

**Example:**

```sql
SELECT * FROM pggit.benchmark_compression_performance('LARGE');
-- metric: Storage Space | without_compression: 180 MB | with_compression: 54 MB | improvement: 70% reduction
-- metric: Query Speed   | without_compression: 245 ms | with_compression: 187 ms | improvement: 24% faster
-- metric: Backup Time   | without_compression: 12 sec | with_compression: 4 sec  | improvement: 67% faster
```

### `generate_test_dataset()`

Generates realistic test data for benchmarking.

```sql
pggit.generate_test_dataset(p_size TEXT DEFAULT 'MEDIUM') RETURNS TEXT
```

**Example:**

```sql
-- Generate test data
SELECT pggit.generate_test_dataset('LARGE');
-- Returns: 'Generated 100,000 test records across 5 tables. Total size: 180 MB'

-- Create branch with test data
SELECT pggit.create_compressed_data_branch('test/benchmark', 'main', true);
```

---

## 🔐 Security & Permissions

### `grant_branch_access()`

Grants user access to specific branches.

```sql
pggit.grant_branch_access(
    p_username TEXT,
    p_branch_name TEXT,
    p_permissions TEXT DEFAULT 'READ'
) RETURNS TEXT
```

**Permissions:** 'READ', 'WRITE', 'ADMIN'

**Example:**

```sql
-- Grant read access
SELECT pggit.grant_branch_access('developer_user', 'feature/user-auth', 'READ');

-- Grant write access for feature development
SELECT pggit.grant_branch_access('senior_dev', 'feature/user-auth', 'WRITE');
```

### `audit_branch_changes()`

Returns audit log of branch modifications.

```sql
pggit.audit_branch_changes(
    p_branch_name TEXT DEFAULT NULL,
    p_since TIMESTAMP DEFAULT NULL
) RETURNS TABLE (
    username TEXT,
    action TEXT,
    object_name TEXT,
    timestamp TIMESTAMP,
    details JSONB
)
```

---

## 🛠️ Utility Functions

### `cleanup_merged_branches()`

Cleans up branches that have been successfully merged.

```sql
pggit.cleanup_merged_branches(p_dry_run BOOLEAN DEFAULT true) RETURNS TEXT
```

**Example:**

```sql
-- See what would be cleaned up
SELECT pggit.cleanup_merged_branches(true);
-- Returns: 'DRY_RUN: Would remove 3 merged branches (saving 2.1 GB)'

-- Actually clean up
SELECT pggit.cleanup_merged_branches(false);
-- Returns: 'CLEANUP_COMPLETE: Removed 3 branches, freed 2.1 GB storage'
```

### `optimize_storage()`

Optimizes storage across all branches.

```sql
pggit.optimize_storage() RETURNS TEXT
```

**Example:**

```sql
SELECT pggit.optimize_storage();
-- Returns: 'OPTIMIZATION_COMPLETE: Reclaimed 890 MB across 7 branches'
```

### `export_branch_config()`

Exports branch configuration for backup/restore.

```sql
pggit.export_branch_config(p_branch_name TEXT) RETURNS JSONB
```

### `import_branch_config()`

Imports branch configuration from backup.

```sql
pggit.import_branch_config(p_config JSONB) RETURNS TEXT
```

---

## 📈 Demo Functions

### `demo_compression_efficiency()`

Demonstrates compression capabilities.

```sql
pggit.demo_compression_efficiency() RETURNS TABLE (
    feature TEXT,
    without_compression TEXT,
    with_zstd_compression TEXT,
    improvement TEXT
)
```

### `demo_postgresql17_compression()`

**PostgreSQL 17+ only** - Shows advanced compression features.

```sql
pggit.demo_postgresql17_compression() RETURNS TABLE (
    feature TEXT,
    postgresql_16_and_below TEXT,
    postgresql_17_with_pggit TEXT,
    improvement TEXT
)
```

---

## 🚨 Error Handling

### Common Return Codes

| Code | Meaning | Action |
|------|---------|--------|
| `MERGE_SUCCESS:hash` | Clean merge completed | Continue normally |
| `CONFLICTS_DETECTED:merge_id` | Manual resolution needed | Use conflict resolution functions |
| `BRANCH_NOT_FOUND` | Invalid branch name | Check branch name with `list_branches()` |
| `COMPRESSION_UNAVAILABLE` | PostgreSQL < 17 | Upgrade or use basic functions |
| `PERMISSION_DENIED` | Insufficient privileges | Check user permissions |

### Error Examples

```sql
-- Branch doesn't exist
SELECT pggit.checkout_branch('nonexistent');
-- ERROR: BRANCH_NOT_FOUND: Branch 'nonexistent' does not exist

-- Compression not available
SELECT pggit.create_compressed_data_branch('test', 'main', true);
-- ERROR: COMPRESSION_UNAVAILABLE: PostgreSQL 17+ required for advanced compression

-- Merge conflicts
SELECT pggit.merge_branches('conflicting-branch', 'main');
-- Returns: 'CONFLICTS_DETECTED:merge_abc123' (use auto_resolve_conflicts)
```

---

## 🎯 Best Practices

### Function Usage Patterns

**Branch Creation:**

```sql
-- Development: Use data branches
SELECT pggit.create_data_branch('feature/new-feature', 'main', true);

-- CI/CD: Use schema-only for speed
SELECT pggit.create_branch('ci/build-123', 'main');

-- PostgreSQL 17: Use compressed branches
SELECT pggit.create_compressed_data_branch('feature/pg17', 'main', true);
```

**Merge Workflow:**

```sql
-- 1. Always validate before merging
SELECT * FROM pggit.validate_branch_integrity('feature/ready-to-merge');

-- 2. Merge with appropriate function
SELECT pggit.merge_compressed_branches('feature/ready-to-merge', 'main');

-- 3. Handle conflicts if needed
SELECT pggit.auto_resolve_compressed_conflicts('merge_id', 'COMPRESSION_OPTIMIZED');
```

**AI-Powered Analysis:**

```sql
-- Analyze migrations before applying
SELECT * FROM pggit.analyze_migration_with_llm(
    'ALTER TABLE users ADD COLUMN email VARCHAR(255);',
    'flyway',
    'V2__add_email.sql'
);

-- Batch analyze multiple migrations
SELECT * FROM pggit.ai_migrate_batch(migration_batch_json, 'flyway');

-- Run edge case detection tests
SELECT * FROM pggit.run_edge_case_tests();
```

**Performance Monitoring:**

```sql
-- Regular monitoring (including AI performance)
SELECT * FROM pggit.get_performance_stats();
SELECT * FROM pggit.get_branch_storage_stats();

-- Monitor AI analysis performance
SELECT
    COUNT(*) as analyses_last_hour,
    ROUND(AVG(confidence * 100), 1) as avg_confidence,
    ROUND(AVG(inference_time_ms), 0) as avg_ai_time_ms
FROM pggit.ai_decisions
WHERE created_at > NOW() - INTERVAL '1 hour';

-- Periodic cleanup
SELECT pggit.cleanup_merged_branches(false);
SELECT pggit.optimize_storage();
```

---

## 🔗 Integration Examples

### CI/CD Pipeline Integration

```bash
#!/bin/bash
# In your CI pipeline

# Create test branch
psql -c "SELECT pggit.create_branch('ci/build-${BUILD_ID}', 'main');"

# Run migrations
psql -f migrations.sql

# Run tests
./run_tests.sh

# Merge on success, cleanup on failure
if [ $? -eq 0 ]; then
    psql -c "SELECT pggit.merge_branches('ci/build-${BUILD_ID}', 'main');"
else
    psql -c "SELECT pggit.cleanup_merged_branches(false);"
fi
```

### Application Integration

```python
# Python example
import psycopg2

def deploy_feature(feature_name, migration_sql):
    conn = psycopg2.connect("postgresql://...")
    cur = conn.cursor()

    try:
        # Create feature branch
        cur.execute("SELECT pggit.create_data_branch(%s, 'main', true)", (feature_name,))

        # Apply migrations
        cur.execute("SELECT pggit.apply_migration(%s, false)", (migration_sql,))

        # Validate
        cur.execute("SELECT * FROM pggit.validate_branch_integrity(%s)", (feature_name,))

        # Merge to main
        cur.execute("SELECT pggit.merge_branches(%s, 'main')", (feature_name,))

        conn.commit()
        return "SUCCESS"

    except Exception as e:
        conn.rollback()
        return f"ERROR: {e}"
```

---

## 📚 See Also

- **[Getting Started Guide →](Getting_Started.md)** - Step-by-step setup
- **[Examples →](../examples/)** - Real-world usage patterns
- **[Architecture →](Git_Branching_Architecture.md)** - How it works
- **[Troubleshooting →](getting-started/Troubleshooting.md)** - Common issues

---

*This API reference covers pgGit v0.1.0+. For the latest updates, see our
[GitHub repository](https://github.com/evoludigit/pggit).*
