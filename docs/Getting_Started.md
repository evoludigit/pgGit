# Getting Started with pggit

Your complete guide to database branching with PostgreSQL 17

> **Recommended Usage**: pgGit is primarily designed for **development and staging databases**. For most production environments, use migration tools. However, if you have compliance requirements (ISO 27001, SOC 2, DORA, GDPR, NIS2, HIPAA, PCI-DSS, SOX), pgGit can provide automatic DDL audit trails in production. See [Production Considerations](guides/PRODUCTION_CONSIDERATIONS.md).

## Welcome to the Future of Database Development

You know that feeling when you push code changes to a feature branch, test
safely, then merge with confidence? **What if your development database could work the
same way?**

That's exactly what pggit does. Let's get you set up and branching databases
like a pro on your **local development environment**.

---

## ⚡ Quick Setup (5 Minutes)


### Prerequisites Check


First, let's make sure you have what you need:

```bash
# Check PostgreSQL version (17+ required for full compression)
psql --version
# Should show: psql (PostgreSQL) 17.x

# Check if you have build tools
which make gcc
# Should show paths to both
```

### Don't have PostgreSQL 17?

No worries:

```bash
# Option 1: Use our Podman container (easiest)
podman run --name pggit-db \
  -e POSTGRES_PASSWORD=yourpassword \
  -p 5432:5432 -d postgres:17

# Option 2: Install locally
# Ubuntu/Debian: sudo apt install postgresql-17 postgresql-server-dev-17
# macOS: brew install postgresql@17
# RHEL/CentOS: sudo dnf install postgresql17-server postgresql17-devel
```

### Install pggit


```bash
# Clone the revolutionary database technology
git clone https://github.com/evoludigit/pggit
cd pggit

# Build and install (takes ~30 seconds)
make clean && make && sudo make install

# Enable in your database
psql -d your_database -c "CREATE EXTENSION pggit;"
```

### Success looks like:

```
CREATE EXTENSION
NOTICE: 🚀 pggit extension installed successfully!
NOTICE: 💾 PostgreSQL 17 compression features activated
NOTICE: 🌿 Ready for database branching
```

---

## 🎬 Your First Database Branch (The Magic Moment)


Let's create your first branch with actual data. This is where it gets exciting:

### 1. Set Up Some Test Data


```sql
-- Connect to your database
psql -d your_database

-- Create a simple table
CREATE SCHEMA IF NOT EXISTS main;
CREATE TABLE main.users (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE,
    preferences JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add some data
INSERT INTO main.users (name, email, preferences) VALUES
('Alice Johnson', 'alice@example.com', '{"theme": "dark", "notifications": true}'),
('Bob Smith', 'bob@example.com', '{"theme": "light", "language": "es"}'),
('Carol Davis', 'carol@example.com', '{"theme": "dark", "timezone": "UTC"}');

-- Verify your data
SELECT COUNT(*) FROM main.users;
-- Should show: 3
```

### 2. Create Your First Branch (The Revolutionary Part)


```sql
-- 🌟 The moment of truth: create a branch with REAL DATA
SELECT pggit.create_data_branch('feature/user-profiles', 'main', true);

-- You'll see something like:
-- NOTICE: 🚀 Creating PostgreSQL 17 compressed data branch: feature/user-profiles
-- NOTICE: 💾 Creating compressed COW table: feature/user-profiles.users (size: 8192 bytes → compression optimized)
-- NOTICE: 📊 Compression achieved: 24 kB → 8192 bytes (66.67% reduction)
-- NOTICE: ✅ PostgreSQL 17 compressed branch feature/user-profiles created with ID 2 in 45ms
```

### What just happened?

You created an isolated copy of your entire database that:

- Shares unchanged data with the parent (copy-on-write)
- Uses PostgreSQL 17 compression (efficient storage)
- Allows independent changes without affecting main
- Can be merged back automatically

### 3. Switch to Your Branch and Make Changes


```sql
-- Switch to your new branch
SELECT pggit.checkout_branch('feature/user-profiles');

-- Now make changes fearlessly
ALTER TABLE users ADD COLUMN avatar_url TEXT;
INSERT INTO users (name, email, avatar_url, preferences) 
VALUES ('Diana Prince', 'diana@example.com', 'avatars/diana.jpg', 
        '{"theme": "dark", "role": "admin", "beta_features": true}');

-- Update existing users
UPDATE users 
SET preferences = preferences || '{"avatar_enabled": true}'::jsonb
WHERE id <= 2;

-- Check what you've got
SELECT id, name, avatar_url, preferences FROM users;
-- Shows 4 users total (3 original + 1 new)
```

### 4. See the Magic in Action


```sql
-- Check storage efficiency
SELECT * FROM pggit.get_branch_storage_stats();
-- Shows compression ratios and space saved

-- Verify branch isolation (switch back to main)
SELECT pggit.checkout_branch('main');
SELECT COUNT(*) FROM users;
-- Still shows 3 (your changes are isolated!)
```

### 5. Merge Your Changes Back


```sql
-- Merge your feature branch back to main
SELECT pggit.merge_compressed_branches('feature/user-profiles', 'main');

-- Results will show one of:
-- ✅ 'MERGE_SUCCESS:abcd1234...' - Clean merge completed
-- ⚠️ 'CONFLICTS_DETECTED:abcd1234...' - Manual resolution needed

-- Verify the merge worked
SELECT pggit.checkout_branch('main');
SELECT COUNT(*) FROM users;
-- Should now show 4 users!
```

---

## 🎯 Core Concepts (What You Just Learned)


### Branches Are Real Database Isolation

Unlike traditional migration tools that just track schema changes, pggit
branches create **actual isolated environments**:

- **Schema Isolation**: Each branch has its own PostgreSQL schema
- **Data Inheritance**: Copy-on-write using PostgreSQL table inheritance
- **Compression**: Efficient storage with PostgreSQL 17
- **Performance**: Branch operations complete in seconds, not minutes

### Copy-on-Write = Storage Efficiency

When you create a branch:

1. **Unchanged data** is shared between branches (zero duplication)
2. **New data** is stored only in the branch that created it
3. **PostgreSQL 17 compression** provides efficient storage
4. **Merging** combines changes intelligently

### Three-Way Merging

When merging branches, pggit uses Git-style three-way merge:

- **Base**: Common ancestor state
- **Source**: Your branch changes
- **Target**: Destination branch changes
- **Result**: Automatic merge or conflict detection

---

## 📊 Understanding Performance


### Storage Efficiency Demo

```sql
-- Generate larger test dataset
SELECT pggit.generate_compression_test_data();
-- Creates 10,000 records with JSONB data

-- Create compressed branch
SELECT pggit.create_compressed_data_branch('feature/performance-test', 'main', true);

-- Check the results
SELECT * FROM pggit.get_branch_storage_stats();
-- Typical results:
-- branch_name: feature/performance-test
-- table_count: 1
-- total_size: 2048 kB
-- compressed_size: 656 kB
-- compression_ratio: 67.97%
-- space_saved: 1392 kB
```

### Compression Comparison

```sql
-- See what PostgreSQL 17 gives you
SELECT * FROM pggit.demo_postgresql17_compression();

-- Results:
-- Native Compression: Basic TOAST → Advanced LZ4/ZSTD
--   (much more efficient)
-- Column-level Compression: Table-level → Per-column control
--   (Granular optimization)
-- Data Branching: Not possible → Copy-on-write with compression
--   (Revolutionary)
-- Storage Efficiency: 100% baseline → Significantly reduced with
--   compression
```

---

## 🚨 Common Gotchas (And How to Avoid Them)


### PostgreSQL Version Compatibility

**Problem:** Trying to use advanced compression on PostgreSQL < 17

```sql
-- This might not work on older versions:
SELECT pggit.create_compressed_data_branch('test', 'main', true);
-- ERROR: unrecognized configuration parameter "toast_compression"
```

**Solution:** Either upgrade to PostgreSQL 17 or use basic branching:

```sql
-- Works on all PostgreSQL versions:
SELECT pggit.create_data_branch('test', 'main', false);  -- Schema only
```

### Large Dataset Performance

**Problem:** Creating branches with massive tables takes forever

```sql
-- This might be slow with 100GB+ tables:
SELECT pggit.create_data_branch('feature/huge', 'main', true);
```

**Solution:** Use schema-only branches for CI/CD, data branches for
development:

```sql
-- Fast for CI/CD (schema only):
SELECT pggit.create_data_branch('ci/build-123', 'main', false);

-- Slower but complete for development:
SELECT pggit.create_data_branch('feature/new-feature', 'main', true);
```

### Merge Conflicts

**Problem:** Automatic merge fails due to conflicts

```sql
SELECT pggit.merge_compressed_branches('feature/a', 'main');
-- Returns: 'CONFLICTS_DETECTED:merge_abc123'
```

**Solution:** Resolve conflicts systematically:

```sql
-- Option 1: Auto-resolve using compression optimization
SELECT pggit.auto_resolve_compressed_conflicts(
    'merge_abc123', 
    'COMPRESSION_OPTIMIZED'
);

-- Option 2: Resolve manually
SELECT pggit.resolve_conflict('merge_abc123', conflict_id, 'TAKE_SOURCE');
```

---

## 🔥 Advanced Workflows


### CI/CD Integration

```sql
-- In your CI pipeline:
-- 1. Create test branch
SELECT pggit.create_branch('ci/build-' || $BUILD_ID, 'main', false);

-- 2. Run your tests against the branch
-- 3. Merge on success, discard on failure
SELECT CASE 
    WHEN $TESTS_PASSED THEN pggit.merge_branches('ci/build-' || $BUILD_ID, 'main')
    ELSE 'Tests failed - branch discarded'
END;
```

### Feature Development with Data

```sql
-- Long-running feature development
SELECT pggit.create_data_branch('feature/new-architecture', 'main', true);

-- Months of development...
-- Add tables, modify schemas, insert test data

-- When ready to merge:
SELECT pggit.merge_compressed_branches('feature/new-architecture', 'main');
```

### Emergency Hotfixes

```sql
-- Production issue? Branch and fix safely
SELECT pggit.create_branch('hotfix/critical-bug', 'production', false);
-- Apply minimal schema fix
-- Fast-track merge
SELECT pggit.merge_branches('hotfix/critical-bug', 'production');
```

---

## 🔍 Troubleshooting


### Extension Won't Install

**Error:** `could not open extension control file`

```bash
# Check if PostgreSQL dev packages are installed
# Ubuntu/Debian:
sudo apt install postgresql-server-dev-17

# CentOS/RHEL:
sudo dnf install postgresql17-devel

# Then rebuild:
make clean && make && sudo make install
```

### Permission Denied

**Error:** `permission denied to create extension`

```sql
-- Connect as superuser:
sudo -u postgres psql -d your_database
CREATE EXTENSION pggit;
-- Then grant usage:
GRANT USAGE ON SCHEMA pggit TO your_username;
```

### Compression Not Working

**Error:** Branches created but no compression benefits

```sql
-- Check PostgreSQL version:
SELECT version();
-- If < 17, compression features are limited

-- Check compression settings:
SHOW default_toast_compression;
-- Should show 'lz4' or 'zstd'
```

### Performance Issues

**Slow branch creation:**

- Start with schema-only branches (`copy_data = false`)
- Use JSONB data types for better compression
- Ensure adequate disk space (compression requires temp space)

---

## 🎓 Next Steps


Congratulations! You've successfully:

- ✅ Installed pggit with PostgreSQL 17
- ✅ Created your first data branch with compression
- ✅ Made isolated changes safely
- ✅ Merged changes back automatically
- ✅ Understood core concepts and performance benefits

### Ready for More?

- **[Onboarding Guide →](Onboarding_Guide.md)** - Migrate existing databases to pggit
- **[API Reference →](API_Reference.md)** - Complete function documentation
- **[Examples →](../examples/)** - Real-world use cases and patterns
- **[Troubleshooting →](getting-started/Troubleshooting.md)** - Solutions to common issues
- **[Architecture →](Git_Branching_Architecture.md)** - How it works under the hood

### Have an Existing Database?

If you're looking to adopt pggit with an existing production database, check
out our comprehensive **[Onboarding Guide](Onboarding_Guide.md)**. It covers:

- Multiple migration strategies (dev-first, shadow mode, hybrid)
- Step-by-step migration plans
- Automated onboarding script
- Real-world examples
- Zero-downtime migration options

### Join the Community

- **💬 Discussions**: [GitHub Discussions](https://github.com/evoludigit/pggit/discussions)
- **🐛 Issues**: [Report bugs](https://github.com/evoludigit/pggit/issues)
- **📧 Direct Contact**: [info@pggit.dev](mailto:info@pggit.dev)

---

**Ready to revolutionize your database workflows?** You've got the foundation.
Now go branch with confidence! 🚀

*Built with ❤️ for PostgreSQL developers who want their databases to be as
sophisticated as their applications.*

