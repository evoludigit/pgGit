# pgGit v2 Developer Training Course

**4-Hour Hands-On Workshop**

---

## Course Overview

### 🎯 Learning Objectives
By the end of this training, participants will be able to:
- Understand Git-like database version control concepts
- Create and manage branches for schema development
- Commit schema changes with proper messaging
- Compare branches and resolve schema conflicts
- Monitor system health and performance
- Follow best practices for collaborative database development

### 📋 Prerequisites
- Basic SQL knowledge
- Understanding of database schema concepts
- Familiarity with version control concepts (helpful but not required)

### 🕐 Course Structure
- **Session 1**: Core Concepts (60 minutes)
- **Session 2**: Practical Workflow (120 minutes)
- **Session 3**: Advanced Features (60 minutes)
- **Session 4**: Best Practices & Q&A (60 minutes)

---

## Session 1: Core Concepts (60 minutes)

### 1.1 Introduction to pgGit v2
**Duration**: 15 minutes

#### What is pgGit v2?
- Git-like version control for PostgreSQL databases
- Automatic schema change tracking
- Branch-based development workflows
- Enterprise-grade monitoring and compliance

#### Key Benefits
- **Collaboration**: Team-based schema development
- **Safety**: Rollback capabilities and conflict detection
- **Compliance**: Complete audit trails
- **Productivity**: Parallel development without interference

#### Real-World Use Cases
- Microservices database schema evolution
- Multi-tenant application updates
- Enterprise data warehouse changes
- CI/CD pipeline integration

### 1.2 Git Concepts Adapted for Databases
**Duration**: 20 minutes

#### Traditional Git vs pgGit v2
| Git | pgGit v2 | Purpose |
|-----|----------|---------|
| Files | Tables/Objects | What gets versioned |
| Commits | Schema snapshots | Version checkpoints |
| Branches | Schema branches | Parallel development |
| Diff | Schema comparison | Change visualization |
| Merge | Schema integration | Combining changes |

#### Core Objects
- **Commits**: Immutable schema snapshots with metadata
- **Branches**: Named pointers to commits
- **HEAD**: Current active commit/branch
- **Refs**: Branch and tag references

### 1.3 System Architecture
**Duration**: 15 minutes

#### Component Overview
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Application   │────│  pgGit v2 API   │────│ PostgreSQL DB   │
│   (DDL Changes) │    │  (Functions)    │    │  (Schema)       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │  Audit Trail    │
                       │  (Changes Log)  │
                       └─────────────────┘
```

#### Data Flow
1. DDL executed → pgGit triggers activated
2. Schema changes captured → Stored in pggit tables
3. Metadata indexed → Available via API functions
4. Analytics computed → Real-time monitoring available

---

## Session 2: Practical Workflow (120 minutes)

### 2.1 Environment Setup
**Duration**: 15 minutes

#### Lab Setup
```sql
-- Verify installation
SELECT pggit_v0.get_head_sha();

-- Check system health
SELECT * FROM pggit_v0.check_for_alerts();

-- View available functions
SELECT proname FROM pg_proc WHERE proname LIKE 'pggit_v0.%' LIMIT 5;
```

#### Initial Schema
```sql
-- Create training database
CREATE SCHEMA training;
CREATE TABLE training.customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE
);
```

### 2.2 Basic Operations Lab
**Duration**: 30 minutes

#### Exercise 1: First Commit
```sql
-- Create initial commit
SELECT pggit_v0.create_basic_commit('Initial customer table setup');

-- Verify commit created
SELECT * FROM pggit_v0.get_commit_history(1);
```

#### Exercise 2: Branch Management
```sql
-- Create feature branch
SELECT pggit_v0.create_branch('feature/customer-profiles', 'Add customer profile features');

-- List branches
SELECT * FROM pggit_v0.list_branches();

-- Switch context (conceptual - branches are global)
-- Add schema changes
ALTER TABLE training.customers ADD COLUMN phone VARCHAR(20);
ALTER TABLE training.customers ADD COLUMN address TEXT;

-- Commit changes
SELECT pggit_v0.create_basic_commit('Add contact information fields');
```

#### Exercise 3: Schema Comparison
```sql
-- Compare branches
SELECT * FROM pggit_v0.diff_branches('main', 'feature/customer-profiles');

-- View object history
SELECT * FROM pggit_v0.get_object_history('training', 'customers', 5);
```

#### Exercise 4: Branch Cleanup
```sql
-- Merge feature (simulated)
SELECT pggit_v0.create_basic_commit('Merge customer profiles feature');

-- Clean up branch
SELECT pggit_v0.delete_branch('feature/customer-profiles');

-- Verify cleanup
SELECT * FROM pggit_v0.list_branches();
```

### 2.3 Advanced Workflow Lab
**Duration**: 45 minutes

#### Exercise 5: Multi-Branch Development
```sql
-- Create multiple feature branches
SELECT pggit_v0.create_branch('feature/api-endpoints', 'REST API endpoints');
SELECT pggit_v0.create_branch('feature/data-validation', 'Input validation');

-- Add different changes to each branch
-- API branch
CREATE TABLE training.api_logs (
    id SERIAL PRIMARY KEY,
    endpoint VARCHAR(255),
    method VARCHAR(10),
    response_time INTEGER
);

-- Validation branch
ALTER TABLE training.customers ADD CONSTRAINT email_format
    CHECK (email LIKE '%@%');

-- Commit both features
SELECT pggit_v0.create_basic_commit('Add API logging capabilities');
SELECT pggit_v0.create_basic_commit('Add email format validation');
```

#### Exercise 6: Conflict Detection
```sql
-- Attempt conflicting changes (simulated)
-- Both branches modify same table differently
ALTER TABLE training.customers ADD COLUMN status VARCHAR(20) DEFAULT 'active'; -- Branch 1
ALTER TABLE training.customers ADD COLUMN account_type VARCHAR(20) DEFAULT 'standard'; -- Branch 2

-- Compare branches to see differences
SELECT * FROM pggit_v0.diff_branches('feature/api-endpoints', 'feature/data-validation');
```

#### Exercise 7: Release Management
```sql
-- Create release branch
SELECT pggit_v0.create_branch('release/v1.0.0', 'Production release v1.0.0');

-- Final stabilization
COMMENT ON TABLE training.api_logs IS 'Tracks API endpoint usage for analytics';
COMMENT ON TABLE training.customers IS 'Customer master data with validation';

-- Release commit
SELECT pggit_v0.create_basic_commit('Release v1.0.0 - production ready');
```

### 2.4 Monitoring and Analytics Lab
**Duration**: 30 minutes

#### Exercise 8: System Monitoring
```sql
-- Health check
SELECT * FROM pggit_v0.check_for_alerts();

-- Dashboard overview
SELECT * FROM pggit_v0.get_dashboard_summary();

-- Performance analysis
SELECT * FROM pggit_v0.analyze_query_performance();
```

#### Exercise 9: Analytics Deep Dive
```sql
-- Storage analysis
SELECT * FROM pggit_v0.analyze_storage_usage();

-- Object size distribution
SELECT * FROM pggit_v0.get_object_size_distribution();

-- Growth projections
SELECT * FROM pggit_v0.estimate_storage_growth();
```

#### Exercise 10: Data Integrity
```sql
-- Integrity validation
SELECT * FROM pggit_v0.validate_data_integrity();

-- Anomaly detection
SELECT * FROM pggit_v0.detect_anomalies();

-- Optimization recommendations
SELECT * FROM pggit_v0.get_recommendations();
```

---

## Session 3: Advanced Features (60 minutes)

### 3.1 Schema Introspection
**Duration**: 20 minutes

#### Object Metadata
```sql
-- Get DDL definitions
SELECT pggit_v0.get_object_definition('training', 'customers');

-- Object metadata
SELECT * FROM pggit_v0.get_object_metadata('training', 'customers');

-- Current schema overview
SELECT * FROM pggit_v0.get_current_schema();
```

#### Change Tracking
```sql
-- Detailed object history
SELECT * FROM pggit_v0.get_object_history('training', 'customers', 10);

-- Commit details
SELECT * FROM pggit_v0.get_commit_history(20);
```

### 3.2 Integration Patterns
**Duration**: 20 minutes

#### CI/CD Integration
```bash
#!/bin/bash
# Pre-deployment checks
psql -c "SELECT * FROM pggit_v0.validate_data_integrity()" > validation.txt

# Schema diff for migration
psql -c "SELECT * FROM pggit_v0.diff_branches('staging', 'production')" > migration.sql

# Post-deployment verification
psql -c "SELECT * FROM pggit_v0.check_for_alerts()" > health_check.txt
```

#### Application Integration
```python
def schema_health_check():
    # Check for schema issues before app startup
    alerts = query("SELECT * FROM pggit_v0.check_for_alerts()")
    if alerts:
        logger.warning(f"Schema alerts: {alerts}")
        # Handle alerts appropriately

    # Get current schema state
    schema = query("SELECT * FROM pggit_v0.get_current_schema()")
    return schema
```

### 3.3 Performance Optimization
**Duration**: 20 minutes

#### Query Optimization
```sql
-- Identify slow operations
SELECT * FROM pggit_v0.analyze_query_performance()
WHERE avg_duration > INTERVAL '100 ms';

-- Storage optimization
SELECT * FROM pggit_v0.get_recommendations()
WHERE priority IN ('HIGH', 'CRITICAL');
```

#### Monitoring Setup
```sql
-- Create monitoring views
CREATE VIEW schema_health AS
SELECT
    (SELECT COUNT(*) FROM pggit_v0.check_for_alerts() WHERE severity = 'OK') as healthy_checks,
    (SELECT COUNT(*) FROM pggit_v0.commit_graph) as total_commits,
    (SELECT COUNT(*) FROM pggit_v0.refs WHERE type = 'branch') as active_branches
;

-- Automated cleanup
SELECT pggit_v0.delete_branch(name)
FROM pggit_v0.list_branches()
WHERE branch_name LIKE 'feature/%'
  AND last_commit < CURRENT_TIMESTAMP - INTERVAL '90 days';
```

---

## Session 4: Best Practices & Q&A (60 minutes)

### 4.1 Best Practices
**Duration**: 20 minutes

#### Commit Practices
```sql
-- Good commit messages
SELECT pggit_v0.create_basic_commit('Add user authentication with JWT token validation');

-- Bad commit messages
SELECT pggit_v0.create_basic_commit('Fixes'); -- Too vague
SELECT pggit_v0.create_basic_commit('Changes to database'); -- Not specific
```

#### Branch Strategy
```sql
-- Recommended branch patterns
'feature/user-registration'     -- New features
'bugfix/login-validation'       -- Bug fixes
'hotfix/security-patch'         -- Emergency fixes
'release/v2.1.0'               -- Release preparation

-- Branch lifecycle
CREATE BRANCH → DEVELOP → COMMIT → REVIEW → MERGE → DELETE
```

#### Collaboration Workflow
```sql
-- Team development workflow
1. Create feature branch
2. Make schema changes
3. Commit with clear messages
4. Run validation checks
5. Request schema review
6. Merge when approved
7. Clean up branch
```

### 4.2 Troubleshooting
**Duration**: 15 minutes

#### Common Issues & Solutions
```sql
-- Issue: Branch already exists
SELECT pggit_v0.create_branch('feature/new-name', 'Updated description');

-- Issue: No commits found
SELECT pggit_v0.create_basic_commit('Initial schema baseline');

-- Issue: Performance problems
SELECT * FROM pggit_v0.analyze_query_performance();
SELECT * FROM pggit_v0.get_recommendations();
```

#### Health Checks
```sql
-- Daily health check routine
SELECT * FROM pggit_v0.check_for_alerts();
SELECT * FROM pggit_v0.validate_data_integrity();
SELECT * FROM pggit_v0.get_dashboard_summary();
```

### 4.3 Q&A Session
**Duration**: 25 minutes

#### Open Discussion Topics
- Integration with existing workflows
- Migration from other tools
- Enterprise requirements
- Advanced use cases
- Future roadmap questions

---

## Training Materials

### 📚 **Provided Materials**
- **API Reference**: Complete function documentation
- **User Guide**: Step-by-step workflows
- **Lab Scripts**: Hands-on exercises
- **Best Practices**: Guidelines and patterns
- **Troubleshooting**: Common issues and solutions

### 🛠️ **Tools & Resources**
- **Sandbox Environment**: Practice database instance
- **Sample Scripts**: Ready-to-use SQL examples
- **Video Recordings**: Session recordings for review
- **Community Support**: Forums and documentation

### 📊 **Assessment & Certification**
- **Knowledge Check**: Multiple-choice quiz (80% passing)
- **Practical Exam**: Schema development scenario
- **Certificate**: pgGit v2 Developer certification

---

## Post-Training Support

### 📞 **Ongoing Support**
- **Documentation Portal**: 24/7 access to guides
- **Community Forums**: Peer support and discussions
- **Professional Services**: Enterprise consulting available
- **Training Refreshers**: Quarterly advanced sessions

### 🎯 **Success Metrics**
- **Adoption Rate**: 80% of trained developers actively using pgGit v2
- **Error Reduction**: 60% decrease in schema-related incidents
- **Development Speed**: 40% faster schema deployment cycles
- **User Satisfaction**: 4.5+ star training rating

---

## Course Evaluation

### **Session Feedback**
Please rate each session (1-5 scale):
- Content quality and relevance
- Instructor knowledge and delivery
- Hands-on exercises value
- Materials usefulness
- Overall learning experience

### **Skill Assessment**
Post-training quiz covering:
- Core pgGit v2 concepts
- Branch management workflows
- Schema comparison techniques
- Monitoring and analytics usage
- Best practices application

### **Follow-up Support**
- 30-day post-training support period
- Advanced topics office hours
- Individual coaching sessions
- Implementation assistance

---

*This training course transforms database developers into pgGit v2 experts, enabling Git-like collaboration and version control for PostgreSQL schema development.*

**Training Version**: 1.0
**Last Updated**: December 22, 2025
**Duration**: 4 hours
**Audience**: Database developers, architects, DevOps engineers