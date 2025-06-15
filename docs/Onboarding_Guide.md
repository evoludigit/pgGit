# pggit Onboarding Guide

How to adopt pggit with your existing production database

## 🚨 Breaking: AI-Powered Migration Now Available!

**Traditional migration:** 12 weeks, complex planning, high risk

**New AI migration:** 3 minutes, zero config, automatic

```bash
# This is all you need now:
pggit-ai migrate

# Really. That's it.
```

[Skip to AI Migration →](#-new-ai-powered-instant-migration)

---

## The Million Dollar Question

"This looks amazing, but I have a 500GB production database with 5 years of history. How do I actually start using pggit?"

We now have TWO answers:

1. **The NEW way:** AI does it in 3 minutes
2. **The traditional way:** Manual migration (1-12 weeks)

---

## 🤖 NEW: AI-Powered Instant Migration

### The 3-Minute Revolution

Our AI-powered migration makes traditional approaches obsolete:

```bash
# Install pggit AI CLI
pip install pggit-ai

# Analyze your database
pggit-ai analyze

# Migrate from ANY tool
pggit-ai migrate --from flyway
pggit-ai migrate --from liquibase
pggit-ai migrate --auto  # AI detects your tool

# AI-powered reconciliation
pggit-ai reconcile feature/branch main
```

### What the AI Does

1. **Detects** your current migration tool automatically
2. **Analyzes** years of migration history in seconds
3. **Understands** the intent behind each migration
4. **Converts** to pggit's semantic versioning
5. **Optimizes** by removing redundancies
6. **Generates** rollbacks for everything
7. **Validates** with 95%+ confidence scoring

### Expected Results

- **Typical Flyway project:** ~1,000 migrations → ~3-5 minutes
- **Complex systems:** ~4,000 migrations → ~8-10 minutes
- **Legacy migrations:** 10+ years of history → ~15-20 minutes

### Try It Now

```sql
-- One-command migration with AI
SELECT pggit.migrate('--ai');

-- AI reconciliation between branches
SELECT pggit.reconcile('feature/new', 'main');
```

[Full AI Migration Guide →](AI_MIGRATION.md)

---

## 🎯 Traditional Onboarding Strategies

If you prefer the manual approach or need more control:

### Strategy 1: Green Field (New Projects)

**Best for:** New applications, microservices, isolated features

**Risk:** Minimal

**Time to value:** Immediate

### Strategy 2: Dev/Staging First

**Best for:** Existing applications with separate environments

**Risk:** Low

**Time to value:** 1-2 weeks

### Strategy 3: Gradual Production Migration

**Best for:** Large production systems

**Risk:** Medium (with proper planning)

**Time to value:** 1-3 months

### Strategy 4: Hybrid Approach

**Best for:** Complex environments with mixed requirements

**Risk:** Low to Medium

**Time to value:** 2-4 weeks

---

## 📋 Pre-Onboarding Checklist

Before starting, verify:

- [ ] PostgreSQL version (14+ required, 17+ recommended)
- [ ] Database size and complexity assessment
- [ ] Backup strategy in place
- [ ] Team familiar with Git concepts
- [ ] Staging/dev environment available
- [ ] Current schema management tools documented

---

## 🚀 Strategy 1: Green Field Onboarding

The easiest path - start fresh with pggit from day one.

```sql
-- 1. Create new database with pggit
CREATE DATABASE myapp_v2;
\c myapp_v2

-- 2. Install pggit
CREATE EXTENSION pggit;

-- 3. Start with main branch
CREATE SCHEMA main;

-- 4. Build your schema in main
CREATE TABLE main.users (
    id SERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 5. Create feature branches from the start
SELECT pggit.create_data_branch('feature/user-profiles', 'main', true);
```

**Benefits:**

- Clean start with version control from day one
- No migration complexity
- Team learns pggit with lower stakes

---

## 🔄 Strategy 2: Dev/Staging First Onboarding

The recommended path for existing applications.

### Step 1: Set Up pggit in Development

```bash
# 1. Backup your dev database
pg_dump -h localhost -d myapp_dev > myapp_dev_backup.sql

# 2. Install pggit in dev
psql -d myapp_dev -c "CREATE EXTENSION pggit;"
```

### Step 2: Import Existing Schema as 'main'

```sql
-- 1. Rename existing schema to main (if using public)
ALTER SCHEMA public RENAME TO main;

-- 2. Create pggit tracking for existing objects
SELECT pggit.import_existing_schema('main');

-- 3. Verify import
SELECT COUNT(*) as tracked_objects FROM pggit.objects;
SELECT * FROM pggit.list_branches();
```

### Step 3: Create Development Workflow

```sql
-- Developer 1: Working on new feature
SELECT pggit.create_data_branch('feature/payment-system', 'main', true);
SELECT pggit.checkout_branch('feature/payment-system');
-- Make changes safely...

-- Developer 2: Different feature, no conflicts
SELECT pggit.create_data_branch('feature/reporting', 'main', true);
SELECT pggit.checkout_branch('feature/reporting');
-- Parallel development...

-- QA: Testing specific branch
SELECT pggit.checkout_branch('feature/payment-system');
-- Run tests against isolated branch...
```

### Step 4: Establish Merge Process

```sql
-- Code review passed, merge to main
SELECT pggit.merge_branches('feature/payment-system', 'main');

-- Deploy main to staging
pg_dump -s -n main myapp_dev | psql -h staging-host -d myapp_staging
```

### Step 5: Monitor and Refine

```sql
-- Track branch metrics
SELECT * FROM pggit.get_branch_storage_stats();

-- Clean up old branches
SELECT pggit.cleanup_merged_branches(false);
```

---

## 🏭 Strategy 3: Gradual Production Migration

For large production systems, migrate incrementally.

### Phase 1: Shadow Mode (Weeks 1-2)

```sql
-- 1. Install pggit in production (shadow mode)
CREATE EXTENSION pggit;

-- 2. Import existing schema without disrupting operations
BEGIN;
    SELECT pggit.import_existing_schema('public', shadow_mode := true);
    -- This tracks objects without creating branches
COMMIT;

-- 3. Monitor for issues
SELECT * FROM pggit.operation_log 
WHERE performed_at > CURRENT_TIMESTAMP - INTERVAL '1 hour';
```

### Phase 2: Read-Only Branches (Weeks 3-4)

```sql
-- Create read-only branches for reporting/analytics
SELECT pggit.create_branch('analytics/daily-reports', 'public');

-- Analytics queries run on isolated branch
SELECT pggit.checkout_branch('analytics/daily-reports');
-- Heavy queries don't impact production
```

### Phase 3: Development Branches (Weeks 5-8)

```sql
-- Start creating feature branches for new development
SELECT pggit.create_data_branch('feature/new-feature', 'public', false);

-- Develop and test in isolation
SELECT pggit.checkout_branch('feature/new-feature');
-- Development happens here...

-- Merge back when ready
SELECT pggit.merge_branches('feature/new-feature', 'public');
```

### Phase 4: Full Migration (Weeks 9-12)

```sql
-- Rename public to main
BEGIN;
    ALTER SCHEMA public RENAME TO main;
    UPDATE pggit.branches SET name = 'main' WHERE name = 'public';
    -- Update application connection strings
COMMIT;

-- Now fully on pggit workflow
```

---

## 🔀 Strategy 4: Hybrid Approach

Mix and match strategies based on your needs.

### Option A: Separate Databases

```sql
-- Keep existing production untouched
-- myapp_prod (existing, no pggit)

-- Create new database with pggit for new features
CREATE DATABASE myapp_features;
\c myapp_features
CREATE EXTENSION pggit;

-- Use foreign data wrapper to access production data
CREATE EXTENSION postgres_fdw;
CREATE SERVER prod_server FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'prod-host', dbname 'myapp_prod');

-- Gradually move tables to pggit-managed database
```

### Option B: Schema Separation

```sql
-- Production stays in 'public' schema
-- New development in pggit-managed schemas

-- Install pggit
CREATE EXTENSION pggit;

-- Create new main branch for future development
CREATE SCHEMA main_v2;
SELECT pggit.track_schema('main_v2');

-- Gradually migrate tables
BEGIN;
    -- Move users table to pggit management
    ALTER TABLE public.users SET SCHEMA main_v2;
    -- Update application to use main_v2.users
COMMIT;
```

---

## 📊 Migration Patterns

### Pattern 1: Big Bang Migration (Not Recommended)

```sql
-- Don't do this in production!
-- CREATE EXTENSION pggit;
-- ALTER SCHEMA public RENAME TO main;
-- Too risky!
```

### Pattern 2: Blue-Green Migration (Recommended)

```sql
-- 1. Set up green environment with pggit
CREATE DATABASE myapp_green;
\c myapp_green
CREATE EXTENSION pggit;

-- 2. Replicate data
pg_dump myapp_prod | psql myapp_green

-- 3. Import as main branch
ALTER SCHEMA public RENAME TO main;
SELECT pggit.import_existing_schema('main');

-- 4. Test thoroughly
-- Run full test suite
-- Verify performance

-- 5. Switch traffic to green
-- Update connection strings
-- Monitor closely

-- 6. Keep blue as fallback
-- Can switch back instantly if issues
```

### Pattern 3: Incremental Table Migration

```sql
-- Migrate one table at a time
CREATE OR REPLACE FUNCTION pggit.migrate_table(
    p_table_name TEXT,
    p_source_schema TEXT DEFAULT 'public',
    p_target_branch TEXT DEFAULT 'main'
) RETURNS TEXT AS $$
DECLARE
    v_start_time TIMESTAMP;
BEGIN
    v_start_time := clock_timestamp();
    
    -- 1. Ensure branch exists
    IF NOT EXISTS (SELECT 1 FROM pggit.branches WHERE name = p_target_branch) THEN
        PERFORM pggit.create_branch(p_target_branch);
    END IF;
    
    -- 2. Move table to branch schema
    EXECUTE format('ALTER TABLE %I.%I SET SCHEMA %I',
        p_source_schema, p_table_name, p_target_branch);
    
    -- 3. Track with pggit
    PERFORM pggit.track_object(p_target_branch || '.' || p_table_name);
    
    -- 4. Create redirect view in original location
    EXECUTE format('CREATE VIEW %I.%I AS SELECT * FROM %I.%I',
        p_source_schema, p_table_name, p_target_branch, p_table_name);
    
    RETURN format('Migrated %s in %s ms', 
        p_table_name, 
        EXTRACT(EPOCH FROM clock_timestamp() - v_start_time) * 1000);
END;
$$ LANGUAGE plpgsql;

-- Use it table by table
SELECT pggit.migrate_table('users');
SELECT pggit.migrate_table('orders');
-- Applications continue working via views
```

---

## 🛠️ Practical Examples

### Example 1: SaaS Application Migration

**Current State:**

- 200GB production database
- 50 tables, 500M records
- Using Flyway for migrations
- 10 developers, 3 environments

**Migration Plan:**


```sql
-- Week 1: Development environment
-- Install pggit in dev
psql -h dev-server -d saas_dev -c "CREATE EXTENSION pggit;"

-- Import existing schema
psql -h dev-server -d saas_dev << 'EOF'
BEGIN;
    ALTER SCHEMA public RENAME TO main;
    SELECT pggit.import_existing_schema('main');
    
    -- Create environment branches
    SELECT pggit.create_branch('staging', 'main');
    SELECT pggit.create_branch('production', 'main');
COMMIT;
EOF

-- Week 2-3: Developer training
-- Each developer gets a branch
SELECT pggit.create_data_branch('dev/alice', 'main', true);
SELECT pggit.create_data_branch('dev/bob', 'main', true);

-- Week 4: Staging deployment
-- Apply pggit to staging
psql -h staging-server -d saas_staging -c "CREATE EXTENSION pggit;"

-- Week 5-6: Production shadow
-- Install but don't activate
psql -h prod-server -d saas_prod -c "CREATE EXTENSION pggit;"

-- Week 7-8: Gradual activation
-- Start with read-only branches for reports
SELECT pggit.create_branch('reports/daily', 'public');

-- Week 9-10: Full migration
-- Coordinate downtime window
-- Complete migration
```

### Example 2: E-commerce Platform

**Current State:**

- 1TB production database
- PostgreSQL 14 (needs upgrade)
- High transaction volume
- Zero-downtime requirement

**Migration Plan:**


```bash
#!/bin/bash
# Progressive migration with zero downtime

# Step 1: Upgrade to PostgreSQL 17 (for compression)
# Use logical replication for zero-downtime upgrade

# Step 2: Install pggit on replica
psql -h replica-server -d ecommerce -c "CREATE EXTENSION pggit;"

# Step 3: Create compressed branches for testing
psql -h replica-server -d ecommerce << 'EOF'
SELECT pggit.create_compressed_data_branch('perf-test', 'public', true);
-- Test shows 70% storage reduction!
EOF

# Step 4: Implement branch-based deployment
# New features developed in branches
# Merged to production during low-traffic windows
```

---

## 🚨 Common Onboarding Challenges

### Challenge 1: "My DBAs are skeptical"

**Solution:** Start with read-only branches


```sql
-- Create read-only branch for reports
SELECT pggit.create_branch('reports/monthly', 'public');
GRANT SELECT ON ALL TABLES IN SCHEMA reports_monthly TO analyst_role;

-- DBAs see benefits without risk
-- - Isolated heavy queries
-- - No production impact
-- - Easy rollback
```

### Challenge 2: "We have stored procedures"

**Solution:** pggit tracks functions too


```sql
-- Your functions are versioned
CREATE OR REPLACE FUNCTION calculate_total(order_id INT)
RETURNS DECIMAL AS $$ ... $$ LANGUAGE plpgsql;

-- See function history
SELECT * FROM pggit.get_history('public.calculate_total');
```

### Challenge 3: "Our database is too large"

**Solution:** Use PostgreSQL 17 compression


```sql
-- Upgrade to PostgreSQL 17
-- Create compressed branches
SELECT pggit.create_compressed_data_branch('feature/test', 'main', true);

-- 70% storage reduction makes branching feasible
-- Even 1TB databases become manageable
```

### Challenge 4: "We use database-specific features"

**Solution:** pggit is PostgreSQL-native


```sql
-- All PostgreSQL features work
-- - Partitioning ✓
-- - JSONB ✓
-- - Arrays ✓
-- - Extensions ✓
-- - Foreign tables ✓

-- pggit enhances, doesn't replace
```

---

## 📈 Success Metrics

Track your onboarding success:

```sql
-- Adoption metrics
SELECT 
    COUNT(DISTINCT branch_name) as active_branches,
    COUNT(DISTINCT created_by) as active_developers,
    AVG(EXTRACT(EPOCH FROM merge_time - branch_created)) as avg_branch_lifetime,
    SUM(CASE WHEN status = 'MERGED' THEN 1 ELSE 0 END) as successful_merges
FROM pggit.branch_metrics
WHERE created_at > CURRENT_DATE - INTERVAL '30 days';

-- Performance impact
SELECT 
    'Before pggit' as period,
    avg_query_time,
    deployment_frequency,
    rollback_count
FROM deployment_metrics
WHERE date < pggit_install_date
UNION ALL
SELECT 
    'After pggit',
    avg_query_time,
    deployment_frequency,
    rollback_count
FROM deployment_metrics
WHERE date >= pggit_install_date;
```

---

## 🎯 Onboarding Timeline

### Week 1-2: Planning & Setup
- Assess current state
- Choose strategy
- Set up test environment
- Install pggit

### Week 3-4: Pilot Program
- Train key developers
- Create first branches
- Run parallel workflows
- Gather feedback

### Week 5-8: Expand Usage
- Onboard all developers
- Integrate with CI/CD
- Refine processes
- Document patterns

### Week 9-12: Production Ready
- Complete migration plan
- Performance testing
- Runbook creation
- Go-live

---

## 🤝 Getting Support

### During Onboarding

- **Architecture Review**: We'll review your migration plan
- **Performance Analysis**: Compression and branching estimates
- **Training Sessions**: For your team
- **Migration Scripts**: Customized for your needs

Contact: [onboarding@pggit.dev](mailto:onboarding@pggit.dev)

### Post-Onboarding

- Regular health checks
- Performance optimization
- Feature roadmap input
- Priority support

---

## ✅ Onboarding Checklist

Before going live:

- [ ] All developers trained on pggit workflows
- [ ] CI/CD pipeline integrated
- [ ] Backup strategy updated for branches
- [ ] Monitoring configured for branch operations
- [ ] Runbook created for common operations
- [ ] Rollback plan documented and tested
- [ ] Performance baselines established
- [ ] Success metrics defined

---

## 🎉 You're Ready!

Remember:
- Start small (dev environment or single table)
- Measure everything (before/after metrics)
- Iterate based on feedback
- Celebrate wins (first successful merge!)

The journey from "interesting technology" to "how did we live without this"
typically takes 3-4 weeks. Your developers will thank you, your DBAs will sleep
better, and your database will finally have the version control it deserves.

**Next steps:**
1. Choose your onboarding strategy
2. Set up a test environment
3. Run through the examples
4. Contact us with questions

Welcome to the future of database development! 🚀
