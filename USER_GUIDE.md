# pgGit v2 User Guide

**Getting Started with Database Version Control**

---

## Welcome to pgGit v2

pgGit v2 brings Git-like version control to PostgreSQL databases. This guide will help you get started with branching, committing, and collaborating on database schema changes.

---

## Quick Start (5 minutes)

### 1. Installation Check
```sql
-- Verify pggit_v0 is installed
SELECT pggit_v0.get_head_sha() as status;
-- Should return a SHA or empty string (no commits yet)
```

### 2. Create Your First Commit
```sql
-- Create initial schema
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Commit the changes
SELECT pggit_v0.create_basic_commit('Add users table');
```

### 3. Start Branching
```sql
-- Create a feature branch
SELECT pggit_v0.create_branch('feature/user-profiles', 'Add user profile features');

-- Add more schema changes
ALTER TABLE users ADD COLUMN first_name VARCHAR(100);
ALTER TABLE users ADD COLUMN last_name VARCHAR(100);

-- Commit feature changes
SELECT pggit_v0.create_basic_commit('Add user profile fields');
```

### 4. Check Your Work
```sql
-- View all branches
SELECT * FROM pggit_v0.list_branches();

-- View commit history
SELECT commit_sha, author, message FROM pggit_v0.get_commit_history(5);

-- Get system health
SELECT * FROM pggit_v0.get_dashboard_summary();
```

---

## Core Concepts

### Git-like Workflow
pgGit v2 follows Git principles adapted for databases:

- **Commits**: Snapshots of schema state with messages
- **Branches**: Parallel development lines
- **HEAD**: Points to current commit
- **History**: Complete audit trail of changes

### Key Differences from Git
- **Automatic Tracking**: DDL changes are tracked automatically
- **Schema Focus**: Tracks table structures, not data
- **Live System**: Works on active databases
- **No Staging**: Changes commit immediately

---

## Daily Development Workflow

### Morning: Check System Status
```sql
-- Quick health check
SELECT * FROM pggit_v0.check_for_alerts();

-- View recent activity
SELECT * FROM pggit_v0.get_dashboard_summary();
```

### Development: Feature Branches
```sql
-- 1. Create feature branch
SELECT pggit_v0.create_branch('feature/new-api-endpoint', 'Add REST API for orders');

-- 2. Make schema changes
CREATE TABLE api_logs (
    id SERIAL PRIMARY KEY,
    endpoint VARCHAR(255),
    method VARCHAR(10),
    response_time INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Commit with descriptive message
SELECT pggit_v0.create_basic_commit('Add API logging table for performance monitoring');

-- 4. Continue development
ALTER TABLE api_logs ADD COLUMN user_id INTEGER REFERENCES users(id);
SELECT pggit_v0.create_basic_commit('Link API logs to users for audit trail');
```

### Review: Branch Comparison
```sql
-- Compare your branch with main
SELECT * FROM pggit_v0.diff_branches('main', 'feature/new-api-endpoint');

-- View detailed commit history
SELECT * FROM pggit_v0.get_commit_history(10);
```

### Merge: Feature Complete
```sql
-- Merge back to main (simulated)
SELECT pggit_v0.create_basic_commit('Merge feature/new-api-endpoint - API logging system');

-- Clean up branch
SELECT pggit_v0.delete_branch('feature/new-api-endpoint');
```

---

## Advanced Usage Patterns

### Schema Evolution Tracking
```sql
-- Track object history
SELECT * FROM pggit_v0.get_object_history('public', 'users', 10);

-- Get current DDL
SELECT pggit_v0.get_object_definition('public', 'users');

-- View metadata
SELECT * FROM pggit_v0.get_object_metadata('public', 'users');
```

### Performance Monitoring
```sql
-- System performance analysis
SELECT * FROM pggit_v0.analyze_query_performance();

-- Storage optimization insights
SELECT * FROM pggit_v0.estimate_storage_growth();

-- Size distribution analysis
SELECT * FROM pggit_v0.get_object_size_distribution();
```

### Data Integrity Assurance
```sql
-- Regular integrity checks
SELECT * FROM pggit_v0.validate_data_integrity();

-- Anomaly detection
SELECT * FROM pggit_v0.detect_anomalies();

-- Comprehensive monitoring report
SELECT * FROM pggit_v0.generate_monitoring_report();
```

---

## Branching Strategies

### Feature Branches (Recommended)
```sql
-- For new features
SELECT pggit_v0.create_branch('feature/user-authentication');
-- Develop feature
-- Commit changes
-- Merge when complete
SELECT pggit_v0.delete_branch('feature/user-authentication');
```

### Release Branches
```sql
-- For production releases
SELECT pggit_v0.create_branch('release/v2.1.0');
-- Final testing and stabilization
-- Tag for production
SELECT pggit_v0.create_basic_commit('Release v2.1.0 - production ready');
```

### Hotfix Branches
```sql
-- For urgent production fixes
SELECT pggit_v0.create_branch('hotfix/security-patch');
-- Implement fix
SELECT pggit_v0.create_basic_commit('Fix critical security vulnerability');
-- Deploy immediately
```

---

## Best Practices

### Commit Messages
```sql
-- Good: Descriptive and actionable
SELECT pggit_v0.create_basic_commit('Add user authentication with JWT tokens');

-- Bad: Vague or unhelpful
SELECT pggit_v0.create_basic_commit('Changes');
```

### Branch Naming
```sql
-- Good: Descriptive and categorized
'feature/user-registration'
'bugfix/login-validation'
'release/v2.1.0'
'hotfix/security-patch'

-- Bad: Unclear or inconsistent
'my-branch'
'fix'
'new-stuff'
```

### Regular Maintenance
```sql
-- Daily: Check system health
SELECT * FROM pggit_v0.check_for_alerts();

-- Weekly: Review old branches
SELECT name FROM pggit_v0.list_branches()
WHERE name LIKE 'feature/%'
  AND last_commit < CURRENT_TIMESTAMP - INTERVAL '30 days';

-- Monthly: Performance review
SELECT * FROM pggit_v0.analyze_query_performance();
```

---

## Troubleshooting

### Common Issues

#### "No commits found" Error
```sql
-- Solution: Create initial commit first
SELECT pggit_v0.create_basic_commit('Initial schema setup');
```

#### Branch Already Exists
```sql
-- Solution: Use unique branch names
SELECT pggit_v0.create_branch('feature/new-feature-v2');
```

#### Cannot Delete Main Branch
```sql
-- Solution: Main branch is protected
-- Create other branches for development
```

### Performance Issues
```sql
-- Check query performance
SELECT * FROM pggit_v0.analyze_query_performance();

-- Review system recommendations
SELECT * FROM pggit_v0.get_recommendations();
```

### Data Integrity Problems
```sql
-- Run integrity validation
SELECT * FROM pggit_v0.validate_data_integrity();

-- Check for anomalies
SELECT * FROM pggit_v0.detect_anomalies();
```

---

## Integration Examples

### CI/CD Pipeline Integration
```bash
#!/bin/bash
# Pre-deployment validation
psql -c "SELECT * FROM pggit_v0.validate_data_integrity()" > integrity_check.txt

# Schema diff for migration
psql -c "SELECT * FROM pggit_v0.diff_branches('staging', 'production')" > schema_diff.sql

# Generate deployment report
psql -c "SELECT * FROM pggit_v0.generate_monitoring_report()" > deployment_report.txt
```

### Application Integration
```python
import psycopg2

def check_schema_health():
    with psycopg2.connect(database="mydb") as conn:
        with conn.cursor() as cur:
            # Check for alerts
            cur.execute("SELECT * FROM pggit_v0.check_for_alerts()")
            alerts = cur.fetchall()

            # Get dashboard summary
            cur.execute("SELECT * FROM pggit_v0.get_dashboard_summary()")
            dashboard = cur.fetchall()

            return {"alerts": alerts, "dashboard": dashboard}
```

### Monitoring Dashboard
```sql
-- Create monitoring view for Grafana/monitoring
CREATE VIEW system_health AS
SELECT
    'pggit_system' as service,
    (SELECT COUNT(*) FROM pggit_v0.check_for_alerts() WHERE severity = 'OK') as healthy_checks,
    (SELECT COUNT(*) FROM pggit_v0.commit_graph) as total_commits,
    (SELECT COUNT(*) FROM pggit_v0.refs WHERE type = 'branch') as active_branches,
    CURRENT_TIMESTAMP as checked_at
FROM pggit_v0.get_dashboard_summary()
LIMIT 1;
```

---

## Migration from Legacy Systems

### From Manual Schema Tracking
```sql
-- 1. Install pggit_v0
-- 2. Create baseline commit
SELECT pggit_v0.create_basic_commit('Baseline schema - migrating from manual tracking');

-- 3. Enable automatic tracking (already active)
-- 4. Train team on new workflow
```

### From Other Version Control Tools
```sql
-- 1. Export current schema state
-- 2. Create initial pggit_v0 commit
SELECT pggit_v0.create_basic_commit('Migrated from [old_tool] - initial schema state');

-- 3. Import existing change history (if available)
-- 4. Update CI/CD pipelines
```

---

## Team Collaboration

### Code Reviews for Schema Changes
```sql
-- Reviewer workflow
-- 1. Check branch diff
SELECT * FROM pggit_v0.diff_branches('main', 'feature/new-table');

-- 2. Review commit messages
SELECT * FROM pggit_v0.get_commit_history(10);

-- 3. Validate schema integrity
SELECT * FROM pggit_v0.validate_data_integrity();
```

### Branch Protection Rules
```sql
-- Implement branch protection in application code
CREATE OR REPLACE FUNCTION check_branch_protection()
RETURNS TRIGGER AS $$
BEGIN
    -- Prevent direct commits to main
    IF NEW.name = 'main' AND NEW.type = 'branch' THEN
        -- Require pull request approval
        RAISE EXCEPTION 'Direct commits to main not allowed';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER protect_main_branch
    BEFORE UPDATE ON pggit_v0.refs
    FOR EACH ROW EXECUTE FUNCTION check_branch_protection();
```

---

## Advanced Features

### Custom Analytics
```sql
-- Create team-specific monitoring views
CREATE VIEW team_schema_changes AS
SELECT
    author,
    COUNT(*) as changes_today,
    MAX(committed_at) as last_change
FROM pggit_v0.commit_graph
WHERE committed_at >= CURRENT_DATE
GROUP BY author
ORDER BY changes_today DESC;
```

### Automated Cleanup
```sql
-- Clean up old feature branches
DO $$
DECLARE
    old_branch RECORD;
BEGIN
    FOR old_branch IN
        SELECT name FROM pggit_v0.list_branches()
        WHERE branch_name LIKE 'feature/%'
        AND last_commit < CURRENT_TIMESTAMP - INTERVAL '90 days'
    LOOP
        PERFORM pggit_v0.delete_branch(old_branch.name);
        RAISE NOTICE 'Deleted old branch: %', old_branch.name;
    END LOOP;
END $$;
```

---

## Support and Resources

### Getting Help
- **API Reference**: Complete function documentation
- **Troubleshooting Guide**: Common issues and solutions
- **Community Forum**: Share experiences and ask questions
- **Professional Services**: Enterprise support available

### Training Resources
- **Quick Start Guide**: This document
- **Video Tutorials**: Step-by-step walkthroughs
- **Interactive Labs**: Hands-on practice environments
- **Certification Program**: Advanced user certification

### Performance Tuning
- **Query Optimization**: Index recommendations
- **Storage Management**: Cleanup and archiving strategies
- **Monitoring Setup**: Alert configuration guides
- **Scalability Guide**: Large database optimization

---

## Success Metrics

Track these KPIs to measure pgGit v2 success:

### Development Velocity
- **Schema Changes**: Time to deploy schema changes
- **Branch Lifetime**: Average time from branch creation to merge
- **Rollback Frequency**: How often rollbacks are needed

### System Reliability
- **Uptime**: System availability percentage
- **Alert Response**: Time to resolve system alerts
- **Data Integrity**: Percentage of successful integrity checks

### Team Adoption
- **Training Completion**: Percentage of team trained
- **Usage Frequency**: Daily active users of pgGit functions
- **Error Reduction**: Decrease in schema-related incidents

---

*Remember: pgGit v2 is your database's version control system. Use it consistently, commit often, and branch strategically for successful database development workflows.*

**Happy versioning! 🚀**