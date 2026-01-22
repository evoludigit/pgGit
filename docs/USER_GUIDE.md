# pgGit User Guide

**Database Version Control for PostgreSQL Development**

---

## Welcome to pgGit

pgGit is a PostgreSQL extension that brings version control to your **development** database schema. Unlike traditional Git which versions files, pgGit versions database objects like tables, views, and functions.

> **Recommended Usage**: pgGit is primarily designed for development and staging databases. For most production environments, use migration tools. However, if you have compliance requirements (ISO 27001, SOC 2, DORA, GDPR, NIS2, HIPAA, PCI-DSS, SOX), pgGit can provide automatic DDL audit trails in production. See [Production Considerations](guides/PRODUCTION_CONSIDERATIONS.md).

---

## Appropriate Usage

pgGit is a development coordination tool. Install it on:

- **Local development databases** - Branch and experiment freely
- **CI/CD test databases** - Validate schema changes automatically
- **Staging/QA databases** - Test merge workflows before production

**Consider carefully for:**

- **Production (standard)** - Migration tools are typically sufficient
- **High-throughput DDL systems** - Event triggers add small overhead

**Consider pgGit in production for:**

- **Compliance requirements** - Automatic DDL audit trails (ISO 27001, SOC 2, DORA, GDPR, NIS2, HIPAA, PCI-DSS, SOX)
- **Security monitoring** - Detect unauthorized schema changes
- **Forensic analysis** - Detailed history for incident response

For standard production deployment, generate migrations from pgGit and apply them using your migration tool (Confiture, Flyway, Alembic, etc.).

See [Development Workflow Guide](guides/DEVELOPMENT_WORKFLOW.md) for detailed patterns.

---

## Quick Start (5 minutes)

### 1. Installation Check
```sql
-- Verify pggit is installed
SELECT * FROM pggit.health_check() LIMIT 3;
-- Should show system status
```

### 2. Create Your First Objects
```sql
-- Create a simple table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Check that it's versioned
SELECT pggit.get_version('users');
```

### 3. Explore Version History
```sql
-- See recent changes
SELECT * FROM pggit.recent_changes LIMIT 5;

-- View object versions
SELECT * FROM pggit.object_versions LIMIT 5;
```

### 4. Branch Management
```sql
-- Create a feature branch
SELECT pggit.create_branch('feature/user-profiles');

-- List all branches
SELECT * FROM pggit.list_branches();
```

---

## Core Concepts

### How pgGit Works

pgGit automatically tracks DDL changes through:
- **Event Triggers**: Capture all CREATE, ALTER, DROP statements
- **Version History**: Maintain complete change log for each object
- **Dependency Tracking**: Understand object relationships
- **Branch Isolation**: Separate development lines

### Key Differences from Git

| Git | pgGit | Purpose |
|-----|-------|---------|
| Files | Database Objects | What gets versioned |
| Commits | DDL Changes | Version checkpoints |
| Branches | Schema Branches | Parallel development |
| Diff | Schema Comparison | Change visualization |
| Clone | Branch Checkout | Environment setup |

---

## Daily Development Workflow

### Morning: Check System Status
```sql
-- Health overview
SELECT * FROM pggit.health_check();

-- Recent activity
SELECT * FROM pggit.recent_changes ORDER BY changed_at DESC LIMIT 10;

-- Size monitoring
SELECT * FROM pggit.database_size_overview;
```

### Development: Schema Changes
```sql
-- Make changes (automatically tracked)
ALTER TABLE users ADD COLUMN first_name VARCHAR(100);
ALTER TABLE users ADD COLUMN last_name VARCHAR(100);

-- Verify tracking
SELECT * FROM pggit.get_history('users') ORDER BY version DESC LIMIT 3;
```

### Review: Impact Analysis
```sql
-- Check dependencies
SELECT * FROM pggit.get_dependency_order();

-- Performance impact
SELECT * FROM pggit.performance_report();
```

### Cleanup: Branch Management
```sql
-- Remove old branches
SELECT * FROM pggit.generate_pruning_recommendations();

-- Clean up if needed
SELECT pggit.delete_branch('old-branch-name');
```

---

## Branching and Merging

### Creating Branches
```sql
-- Create feature branch
SELECT pggit.create_branch('feature/new-api');

-- Create release branch
SELECT pggit.create_branch('release/v1.2.0');

-- Create hotfix branch
SELECT pggit.create_branch('hotfix/security-patch');
```

### Working with Branches
```sql
-- Switch to branch
SELECT pggit.checkout_branch('feature/new-api');

-- Check current branch status
SELECT * FROM pggit.status();

-- List available branches
SELECT * FROM pggit.list_branches();
```

### Merging Branches
```sql
-- Merge feature into main
SELECT pggit.merge_branches('feature/new-api', 'main');

-- Check merge results
SELECT * FROM pggit.recent_changes ORDER BY changed_at DESC LIMIT 5;
```

---

## Schema Analysis and Diffing

### Comparing Schemas
```sql
-- Compare two schema states
SELECT * FROM pggit.diff_schemas('dev', 'staging');

-- Compare table structures
SELECT pggit.diff_table_structure('users', 1, 3);
```

### Change Detection
```sql
-- Find schema changes
SELECT * FROM pggit.detect_schema_changes('production');

-- View object history
SELECT * FROM pggit.get_history('users');
```

---

## Size Management and Optimization

### Monitoring Database Size
```sql
-- Overall size breakdown
SELECT * FROM pggit.database_size_overview;

-- Branch-specific sizes
SELECT * FROM pggit.calculate_branch_size('main');

-- Top space consumers
SELECT * FROM pggit.top_space_consumers LIMIT 10;
```

### Cleanup and Optimization
```sql
-- Find unused data
SELECT * FROM pggit.find_unreferenced_blobs();

-- Get cleanup recommendations
SELECT * FROM pggit.generate_pruning_recommendations();

-- Run automated cleanup
SELECT pggit.run_size_maintenance();
```

---

## Migration and Deployment

### Generating Migrations
```sql
-- Create migration between versions
SELECT pggit.generate_migration(1, 5);

-- Apply migration
SELECT pggit.apply_migration('ALTER TABLE users ADD COLUMN phone TEXT;');
```

### Migration Integration
```sql
-- Check pending migrations
SELECT * FROM pggit.pending_migrations;

-- Validate migration impact
SELECT * FROM pggit.analyze_migration_impact('migration_id', 'SQL');
```

---

## Monitoring and Health Checks

### System Health
```sql
-- Comprehensive health check
SELECT * FROM pggit.health_check();

-- Performance metrics
SELECT * FROM pggit.performance_report();

-- System status
SELECT * FROM pggit.status();
```

### Automated Monitoring
```sql
-- Set up monitoring view
CREATE VIEW system_health AS
SELECT
    'pggit_system' as service,
    (SELECT COUNT(*) FROM pggit.health_check() WHERE status = 'OK') as healthy_components,
    (SELECT COUNT(*) FROM pggit.recent_changes WHERE changed_at > NOW() - INTERVAL '1 day') as daily_changes,
    NOW() as last_check
;
```

---

## Best Practices

### Development Workflow
1. **Create Feature Branches**: Always work on feature branches
2. **Regular Commits**: Make schema changes incrementally
3. **Test Migrations**: Always test migrations before production
4. **Monitor Performance**: Keep an eye on system performance
5. **Regular Cleanup**: Clean up old branches and unused data

### Branch Naming Conventions
```sql
-- Feature branches
'feature/user-authentication'
'feature/payment-integration'

-- Release branches
'release/v1.2.0'
'release/v2.0.0-beta'

-- Hotfix branches
'hotfix/security-patch'
'hotfix/critical-bug'
```

### Performance Guidelines
- **Monitor Size Growth**: Use `database_size_overview` weekly
- **Clean Regularly**: Run pruning recommendations monthly
- **Optimize Queries**: Review performance reports regularly
- **Archive Old Data**: Implement retention policies

---

## Troubleshooting

### Common Issues

#### Schema Changes Not Tracking
```sql
-- Check if triggers are active
SELECT * FROM pggit.status() WHERE component = 'triggers';

-- Verify trigger installation
SELECT * FROM pg_trigger WHERE tgname LIKE 'pggit%';
```

#### Performance Problems
```sql
-- Check performance metrics
SELECT * FROM pggit.performance_report();

-- Review recent changes
SELECT * FROM pggit.recent_changes ORDER BY changed_at DESC LIMIT 10;

-- Analyze query plans
EXPLAIN ANALYZE SELECT * FROM pggit.object_versions;
```

#### Branch Conflicts
```sql
-- Detect conflicts before merging
SELECT * FROM pggit.detect_data_conflicts('source_branch', 'target_branch');

-- Resolve conflicts
SELECT pggit.resolve_conflict('conflict_id', 'resolution_strategy');
```

#### Storage Issues
```sql
-- Check size breakdown
SELECT * FROM pggit.database_size_overview;

-- Find cleanup opportunities
SELECT * FROM pggit.generate_pruning_recommendations();

-- Run cleanup
SELECT pggit.run_size_maintenance();
```

---

## Integration Examples

### CI/CD Pipeline
```bash
#!/bin/bash
# Schema validation in CI/CD
psql -c "SELECT * FROM pggit.health_check()" > health_report.txt

# Migration testing
psql -c "SELECT pggit.generate_migration(1, CURRENT_VERSION)" > migration.sql

# Size monitoring
psql -c "SELECT * FROM pggit.database_size_overview" > size_report.txt
```

### Application Monitoring
```python
def check_database_health():
    # Health check before app operations
    health = query("SELECT * FROM pggit.health_check()")
    if not all(row['status'] == 'OK' for row in health):
        alert_admin("Database health issues detected")

    # Monitor recent changes
    changes = query("SELECT COUNT(*) FROM pggit.recent_changes WHERE changed_at > NOW() - INTERVAL '1 hour'")
    if changes[0]['count'] > 10:
        log_info(f"High change volume: {changes[0]['count']} changes in last hour")
```

### Dashboard Creation
```sql
-- Executive dashboard
CREATE VIEW schema_dashboard AS
SELECT
    (SELECT COUNT(*) FROM pggit.object_versions) as total_objects,
    (SELECT COUNT(*) FROM pggit.list_branches()) as active_branches,
    (SELECT SUM(size_mb) FROM pggit.database_size_overview) as total_size_mb,
    (SELECT COUNT(*) FROM pggit.recent_changes WHERE changed_at > CURRENT_DATE) as changes_today,
    (SELECT COUNT(*) FROM pggit.health_check() WHERE status = 'OK') as healthy_components,
    CURRENT_TIMESTAMP as last_updated
;
```

---

## Advanced Features

### AI-Powered Analysis
```sql
-- AI migration analysis
SELECT * FROM pggit.analyze_migration_with_ai_enhanced('migration_id', 'SQL');

-- AI accuracy tracking
SELECT * FROM pggit.ai_accuracy_dashboard;
```

### CQRS Support
```sql
-- CQRS event tracking
SELECT * FROM pggit.cqrs_history;

-- Command-query separation
SELECT * FROM pggit.cqrs_command_log;
```

### Conflict Resolution
```sql
-- Advanced conflict detection
SELECT * FROM pggit.detect_data_conflicts('branch_a', 'branch_b');

-- Automated resolution
SELECT pggit.apply_data_merge('conflict_id', 'merge_strategy');
```

---

## Community and Support

### Getting Help
- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: General questions and troubleshooting
- **Documentation**: Self-service guides and tutorials
- **Stack Overflow**: Community-driven Q&A (tag: pggit)

### Contributing
- **Pull Requests**: Code contributions welcome
- **Documentation**: Help improve guides and tutorials
- **Testing**: Report bugs and edge cases
- **Feedback**: Share your experience and suggestions

---

## Migration from Other Tools

### From Manual Tracking
```sql
-- Install pgGit
psql -f install.sql

-- Verify installation
SELECT * FROM pggit.health_check();

-- Start using immediately - existing DDL is automatically tracked
```

### From Other Version Control
```sql
-- Export current schema
pg_dump --schema-only > current_schema.sql

-- Install pgGit
psql -f install.sql

-- Create baseline
-- (pgGit automatically starts tracking from this point)
```

---

*pgGit brings the power of version control to your database schema. Use it consistently to maintain clean, versioned, and collaborative database development.*

**Happy versioning! 🎉**