# pggit Troubleshooting Guide

*Solutions to common issues and error messages*

## Quick Diagnosis

Before diving into specific issues, run this diagnostic:

```sql
-- Check pggit health
SELECT * FROM pggit.diagnose_issues();
```

---

## 🚨 Installation Issues

### Extension Won't Install

**Error:** `ERROR: could not open extension control file "/usr/share/postgresql/17/extension/pggit.control": No such file or directory`

**Causes:**
1. Extension files not in PostgreSQL directory
2. Missing PostgreSQL development packages
3. Wrong PostgreSQL version

**Solutions:**

```bash
# 1. Verify PostgreSQL version
psql --version

# 2. Install development packages
# Ubuntu/Debian:
sudo apt-get install postgresql-server-dev-17

# RHEL/CentOS:
sudo dnf install postgresql17-devel

# macOS:
brew install postgresql@17

# 3. Rebuild and reinstall
cd /path/to/pggit
make clean
make
sudo make install

# 4. Verify installation
ls -la /usr/share/postgresql/17/extension/pggit*
```

### Permission Denied During Install

**Error:** `ERROR: permission denied to create extension "pggit"`

**Solution:**
```sql
-- Connect as superuser
sudo -u postgres psql -d your_database

-- Create extension
CREATE EXTENSION pggit;

-- Grant permissions to your user
GRANT USAGE ON SCHEMA pggit TO your_username;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pggit TO your_username;
```

### Incompatible PostgreSQL Version

**Error:** `ERROR: extension "pggit" requires PostgreSQL version 14 or higher`

**Solution:**
```bash
# Check your version
psql -c "SELECT version();"

# If < 14, upgrade PostgreSQL
# Or use pggit with limited features:
psql -c "CREATE EXTENSION pggit VERSION '1.0.0-compat';"
```

---

## 🌿 Branch Management Issues

### Cannot Create Branch

**Error:** `ERROR: Parent branch 'main' not found`

**Causes:**
1. No main branch exists
2. Typo in branch name
3. Branch was deleted

**Solutions:**
```sql
-- Check existing branches
SELECT * FROM pggit.list_branches();

-- Create main branch if missing
INSERT INTO pggit.branches (name, parent_branch_id, status) 
VALUES ('main', NULL, 'ACTIVE');

-- Create schema for main
CREATE SCHEMA IF NOT EXISTS main;
```

### Branch Creation Hangs

**Error:** Branch creation takes forever on large databases

**Causes:**
1. Creating data branch on huge tables
2. Insufficient memory
3. Lock conflicts

**Solutions:**
```sql
-- Option 1: Create schema-only branch
SELECT pggit.create_branch('feature/quick', 'main');  -- No data copy

-- Option 2: Create branch with specific tables
SELECT pggit.create_data_branch_selective(
    'feature/partial',
    'main',
    ARRAY['users', 'settings']  -- Only copy these tables
);

-- Option 3: Monitor progress
SELECT * FROM pggit.branch_creation_progress;

-- Option 4: Check for locks
SELECT * FROM pg_locks WHERE NOT granted;
```

### Cannot Switch Branches

**Error:** `ERROR: Cannot checkout branch with active transactions`

**Solution:**
```sql
-- Check for active transactions
SELECT * FROM pg_stat_activity 
WHERE state = 'active' AND pid != pg_backend_pid();

-- Rollback any pending transactions
ROLLBACK;

-- Then switch branch
SELECT pggit.checkout_branch('feature/mybranch');
```

---

## 💾 PostgreSQL 17 Compression Issues

### Compression Not Working

**Error:** Branches created but no compression benefit observed

**Causes:**
1. Not using PostgreSQL 17
2. Compression not enabled
3. Data not compressible

**Solutions:**
```sql
-- 1. Verify PostgreSQL version
SELECT version();
-- Should show: PostgreSQL 17.x

-- 2. Check compression settings
SHOW default_toast_compression;
-- Should show: lz4 or zstd

-- 3. Enable compression
ALTER SYSTEM SET default_toast_compression = 'lz4';
SELECT pg_reload_conf();

-- 4. Use compressed branch creation
SELECT pggit.create_compressed_data_branch('feature/compressed', 'main', true);

-- 5. Verify compression
SELECT * FROM pggit.get_compression_stats();
```

### Compression Performance Issues

**Error:** Queries slower on compressed branches

**Solutions:**
```sql
-- 1. Check compression ratios
SELECT * FROM pggit.get_branch_storage_stats();

-- 2. Analyze tables
ANALYZE;

-- 3. Adjust compression settings
ALTER TABLE your_table SET (toast_compression = 'lz4');  -- Faster
-- OR
ALTER TABLE your_table SET (toast_compression = 'zstd'); -- Better compression

-- 4. Monitor query performance
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM your_table;
```

---

## 🔀 Merge Conflicts

### Merge Fails with Conflicts

**Error:** `CONFLICTS_DETECTED:merge_abc123`

**Solutions:**
```sql
-- 1. Analyze conflicts
SELECT * FROM pggit.analyze_merge_conflicts('merge_abc123');

-- 2. Auto-resolve with strategy
SELECT pggit.auto_resolve_compressed_conflicts(
    'merge_abc123',
    'COMPRESSION_OPTIMIZED'  -- or 'TAKE_SOURCE' or 'TAKE_TARGET'
);

-- 3. Manual resolution
SELECT * FROM pggit.show_conflict_diff('merge_abc123', 1);
-- Then resolve each conflict manually

-- 4. Retry merge
SELECT pggit.retry_merge('merge_abc123');
```

### Merge Corrupts Data

**Error:** Data inconsistent after merge

**Emergency Recovery:**
```sql
-- 1. Immediately rollback the merge
SELECT pggit.rollback_merge('merge_abc123');

-- 2. Restore from branch backup
SELECT pggit.restore_branch_backup('main', 'before_merge_abc123');

-- 3. Validate data integrity
SELECT * FROM pggit.validate_branch_integrity('main');
```

---

## 🎭 Performance Issues

### Slow Branch Operations

**Symptoms:**
- Branch creation takes > 5 minutes
- Switching branches is slow
- Queries perform poorly

**Diagnosis:**
```sql
-- Check branch statistics
SELECT 
    branch_name,
    table_count,
    total_size,
    compression_ratio,
    age(created_at) as branch_age
FROM pggit.get_branch_storage_stats()
ORDER BY total_size DESC;

-- Find large tables
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE schemaname = 'your_branch'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
```

**Solutions:**
```sql
-- 1. Use schema-only branches for CI/CD
SELECT pggit.create_branch('ci/fast-branch', 'main');  -- No data

-- 2. Optimize storage
SELECT pggit.optimize_storage();

-- 3. Clean up old branches
SELECT pggit.cleanup_merged_branches(false);

-- 4. Increase memory
ALTER SYSTEM SET work_mem = '256MB';
ALTER SYSTEM SET maintenance_work_mem = '1GB';
SELECT pg_reload_conf();
```

### Out of Disk Space

**Error:** `ERROR: could not extend file: No space left on device`

**Solutions:**
```sql
-- 1. Check space usage
SELECT * FROM pggit.get_branch_storage_stats();

-- 2. Find large branches
SELECT 
    branch_name,
    pg_size_pretty(SUM(pg_total_relation_size(table_schema||'.'||table_name))) as total_size
FROM pggit.data_branches
GROUP BY branch_name
ORDER BY SUM(pg_total_relation_size(table_schema||'.'||table_name)) DESC;

-- 3. Clean up merged branches
SELECT pggit.cleanup_merged_branches(false);

-- 4. Drop old test branches
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT name FROM pggit.branches 
        WHERE name LIKE 'ci/%' 
        AND created_at < CURRENT_TIMESTAMP - INTERVAL '7 days'
    LOOP
        EXECUTE format('DROP SCHEMA %I CASCADE', r.name);
        DELETE FROM pggit.branches WHERE name = r.name;
    END LOOP;
END $$;
```

---

## 🔧 Common Error Messages

### `ERROR: schema "branch_name" already exists`

**Cause:** Branch name conflicts with existing schema

**Solution:**
```sql
-- Use a different branch name
SELECT pggit.create_branch('feature/unique-name', 'main');

-- Or clean up the existing schema
DROP SCHEMA branch_name CASCADE;
```

### `ERROR: could not serialize access due to concurrent update`

**Cause:** Concurrent modifications to same branch

**Solution:**
```sql
-- Use advisory locks
SELECT pg_advisory_lock(hashtext('pggit_branch_' || 'branch_name'));
-- Do your operations
SELECT pg_advisory_unlock(hashtext('pggit_branch_' || 'branch_name'));
```

### `ERROR: function pggit.create_compressed_data_branch does not exist`

**Cause:** Using PostgreSQL < 17 or old pggit version

**Solution:**
```sql
-- Use standard branch creation
SELECT pggit.create_data_branch('feature/standard', 'main', true);

-- Or upgrade PostgreSQL to 17
-- Then reinstall pggit
```

---

## 📊 Monitoring & Diagnostics

### Health Check Query

```sql
-- Comprehensive pggit health check
WITH health_checks AS (
    SELECT 'PostgreSQL Version' as check_name,
           CASE WHEN current_setting('server_version_num')::int >= 170000 
                THEN 'PASS' ELSE 'WARN' END as status,
           'Version: ' || version() as details
    UNION ALL
    SELECT 'pggit Schema', 
           CASE WHEN EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'pggit')
                THEN 'PASS' ELSE 'FAIL' END,
           'Schema exists: ' || EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'pggit')::text
    UNION ALL
    SELECT 'Compression Enabled',
           CASE WHEN current_setting('default_toast_compression') IN ('lz4', 'zstd')
                THEN 'PASS' ELSE 'WARN' END,
           'Setting: ' || current_setting('default_toast_compression')
    UNION ALL
    SELECT 'Active Branches',
           CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'WARN' END,
           'Count: ' || COUNT(*)::text
    FROM pggit.branches WHERE status = 'ACTIVE'
)
SELECT * FROM health_checks;
```

### Performance Monitoring

```sql
-- Monitor branch operation performance
CREATE OR REPLACE VIEW pggit.performance_monitor AS
SELECT 
    operation_type,
    branch_name,
    duration_ms,
    objects_affected,
    storage_change_mb,
    performed_at
FROM pggit.operation_log
WHERE performed_at > CURRENT_TIMESTAMP - INTERVAL '24 hours'
ORDER BY performed_at DESC;
```

---

## 🆘 Getting Help

### Before Asking for Help

1. Run the diagnostic query above
2. Check PostgreSQL logs: `tail -f /var/log/postgresql/postgresql-17-main.log`
3. Verify pggit version: `SELECT * FROM pg_extension WHERE extname = 'pggit';`
4. Document the exact error message and steps to reproduce

### Where to Get Help

- **GitHub Issues**: [github.com/evoludigit/pggit/issues](https://github.com/evoludigit/pggit/issues)
- **Discussions**: [github.com/evoludigit/pggit/discussions](https://github.com/evoludigit/pggit/discussions)
- **Email Support**: [support@pggit.dev](mailto:support@pggit.dev)

### Reporting Bugs

Include:
1. PostgreSQL version
2. pggit version
3. Operating system
4. Complete error message
5. Steps to reproduce
6. Output of diagnostic query

---

## 🔄 Recovery Procedures

### Emergency Branch Recovery

```sql
-- If a branch is corrupted
BEGIN;
    -- 1. Mark branch as inactive
    UPDATE pggit.branches SET status = 'CORRUPTED' WHERE name = 'problem_branch';
    
    -- 2. Create recovery branch from last known good state
    SELECT pggit.create_branch('recovery/problem_branch', 'main');
    
    -- 3. Restore data from backup if available
    -- psql -f branch_backup.sql
    
    -- 4. Validate recovery
    SELECT * FROM pggit.validate_branch_integrity('recovery/problem_branch');
COMMIT;
```

### Full System Reset (Last Resort)

```sql
-- WARNING: This will remove all pggit data!
BEGIN;
    DROP EXTENSION pggit CASCADE;
    DROP SCHEMA IF EXISTS pggit CASCADE;
    
    -- Drop all branch schemas
    DO $$
    DECLARE
        r RECORD;
    BEGIN
        FOR r IN SELECT nspname FROM pg_namespace 
                 WHERE nspname LIKE 'feature/%' OR nspname LIKE 'ci/%'
        LOOP
            EXECUTE format('DROP SCHEMA %I CASCADE', r.nspname);
        END LOOP;
    END $$;
    
    -- Reinstall
    CREATE EXTENSION pggit;
COMMIT;
```

---

*Remember: Most issues can be prevented with regular maintenance and following best practices. When in doubt, create a backup before attempting fixes.*