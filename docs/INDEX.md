# pgGit Documentation Index

**Complete guide to finding documentation organized by role and feature**

---

## 📂 Documentation Structure (Visual Sitemap)

**Complete file tree of all 70+ documentation files** - Use this to quickly locate specific documents or understand the overall organization.

```
📁 pggit/
├── 📄 README.md                          # Project overview and quick start
├── 📄 CONTRIBUTING.md                    # How to contribute to pgGit
├── 📄 CODE_OF_CONDUCT.md                 # Community guidelines
├── 📄 SECURITY.md                        # Security policy and vulnerability disclosure
├── 📄 CHANGELOG.md                       # Version history and release notes
├── 📄 RELEASING.md                       # Release process documentation
├── 📄 SUPPORT.md                         # Getting help and support
│
├── 📁 docs/                              # Main documentation directory
│   ├── 📄 INDEX.md                       # ⭐ THIS FILE - Documentation sitemap
│   ├── 📄 README.md                      # Docs directory overview
│   ├── 📄 Getting_Started.md             # 5-minute installation and setup
│   ├── 📄 USER_GUIDE.md                  # Complete user manual
│   ├── 📄 API_Reference.md               # All 50+ functions documented
│   ├── 📄 GLOSSARY.md                    # Technical terms explained
│   │
│   ├── 📁 getting-started/               # Beginner-friendly guides
│   │   ├── 📄 README.md                  # Getting started overview
│   │   ├── 📄 Getting_Started.md         # Quick start guide
│   │   ├── 📄 PgGit_Explained_Like_Im_10.md  # Simple conceptual overview
│   │   └── 📄 Troubleshooting.md         # Common issues and fixes
│   │
│   ├── 📁 guides/                        # Task-oriented guides
│   │   ├── 📄 README.md                  # Guides overview
│   │   ├── 📄 DEVELOPMENT_WORKFLOW.md    # ⭐ Core development patterns
│   │   ├── 📄 PRODUCTION_CONSIDERATIONS.md # ⭐ When to use pgGit in production
│   │   ├── 📄 MIGRATION_INTEGRATION.md   # ⭐ Confiture, Flyway, Alembic integration
│   │   ├── 📄 AI_AGENT_WORKFLOWS.md      # ⭐ Multi-agent coordination
│   │   ├── 📄 IDE_SETUP.md               # VS Code, JetBrains, Vim, Emacs setup
│   │   ├── 📄 DEBUGGING.md               # Debug schema issues
│   │   ├── 📄 PERFORMANCE_TUNING.md      # ⭐ 538 lines - Optimize for 100GB+ DBs
│   │   ├── 📄 Performance.md             # Performance overview
│   │   ├── 📄 Operations.md              # Operations guide
│   │   └── 📄 Security.md                # 30+ security hardening checklist
│   │
│   ├── 📁 operations/                    # Production operations
│   │   ├── 📄 RUNBOOK.md                 # ⭐ Incident response (P1-P4)
│   │   ├── 📄 OPERATIONS_RUNBOOK.md      # Extended operations guide
│   │   ├── 📄 MONITORING.md              # Health checks, Prometheus integration
│   │   ├── 📄 SLO.md                     # 99.9% uptime targets
│   │   ├── 📄 DISASTER_RECOVERY.md       # Backup and recovery procedures
│   │   ├── 📄 BACKUP_RESTORE.md          # Detailed backup guide
│   │   ├── 📄 UPGRADE_GUIDE.md           # Version migration procedures
│   │   ├── 📄 RELEASE_CHECKLIST.md       # Pre-deployment verification
│   │   └── 📄 CHAOS_TESTING.md           # Chaos engineering overview
│   │
│   ├── 📁 security/                      # Security documentation
│   │   ├── 📄 HARDENING.md               # Security hardening guide
│   │   ├── 📄 SECURITY_AUDIT.md          # Security audit procedures
│   │   ├── 📄 SLSA.md                    # Supply chain security (SLSA provenance)
│   │   └── 📄 VULNERABILITY_DISCLOSURE.md # Vulnerability reporting
│   │
│   ├── 📁 compliance/                    # Regulatory compliance
│   │   ├── 📄 FIPS_COMPLIANCE.md         # ⭐ 278 lines - FIPS 140-2 checklist
│   │   └── 📄 SOC2_PREPARATION.md        # ⭐ 442 lines - SOC2 Type II prep
│   │
│   ├── 📁 testing/                       # Testing documentation
│   │   ├── 📄 CHAOS_ENGINEERING.md       # Chaos testing philosophy and guide
│   │   ├── 📄 PATTERNS.md                # Common test patterns
│   │   └── 📄 TROUBLESHOOTING.md         # Test troubleshooting
│   │
│   ├── 📁 e2e/                           # End-to-end testing
│   │   ├── 📄 README.md                  # E2E testing overview
│   │   ├── 📄 RUNNING_TESTS.md           # How to run E2E tests
│   │   └── 📄 branching.md               # Branching test scenarios
│   │
│   ├── 📁 architecture/                  # Architecture documentation
│   │   └── 📄 MODULES.md                 # Module structure and dependencies
│   │
│   ├── 📁 reference/                     # API reference
│   │   ├── 📄 README.md                  # Reference overview
│   │   └── 📄 API_COMPLETE.md            # Complete API documentation
│   │
│   ├── 📁 contributing/                  # Contributor guides
│   │   ├── 📄 README.md                  # Contributing overview
│   │   └── 📄 Claude.md                  # AI-assisted development guide
│   │
│   ├── 📁 benchmarks/                    # Performance benchmarks
│   │   └── 📄 BASELINE.md                # Baseline performance metrics
│   │
│   ├── 📄 Architecture_Decision.md       # Core design decisions
│   ├── 📄 Git_Branching_Architecture.md  # Branching design and strategy
│   ├── 📄 DDL_Hashing_Design.md          # Content-addressable versioning
│   ├── 📄 Hashing_Usage.md               # SHA-256 hashing explained
│   ├── 📄 Schema_Reconciliation.md       # Detecting schema drift
│   ├── 📄 Performance_Analysis.md        # Performance benchmarks
│   ├── 📄 Pattern_Examples.md            # Real-world patterns
│   ├── 📄 Onboarding_Guide.md            # Structured learning path
│   ├── 📄 INSTALLATION.md                # Installation guide (development-focused)
│   ├── 📄 CI_CD.md                       # CI/CD integration
│   ├── 📄 Enterprise_Features.md         # Advanced capabilities
│   ├── 📄 pggit_v0_integration_guide.md  # Integration workflow patterns
│   ├── 📄 configuration-system.md        # Configuration options
│   ├── 📄 conflict-resolution-and-operations.md  # Merge conflict handling
│   ├── 📄 cqrs-support.md                # CQRS pattern support
│   ├── 📄 function-versioning.md         # Function version tracking
│   ├── 📄 migration-integration.md       # Flyway/Liquibase integration
│   ├── 📄 new-features-index.md          # Planned features overview
│   ├── 📄 AI_Integration_Architecture.md # ⚠️ Planned v0.3.0 - AI features
│   ├── 📄 AI_Migration.md                # ⚠️ Planned v0.3.0 - AI migration
│   ├── 📄 Local_LLM_Quickstart.md        # ⚠️ Planned v0.3.0 - Local AI setup
│   ├── 📄 DEVELOPER_TRAINING_COURSE.md   # Developer training materials
│   ├── 📄 SPIKE_1_1_PGGIT_V2_ANALYSIS.md # Technical spike documentation
│   ├── 📄 SPIKE_1_2_DDL_EXTRACTION_ANALYSIS.md
│   ├── 📄 SPIKE_1_3_BACKFILL_ALGORITHM.md
│   └── 📄 SPIKE_1_4_GO_NO_GO_DECISION.md
│
├── 📁 tests/                             # Test suite
│   ├── 📁 chaos/                         # ⭐ Chaos engineering tests (22 modules, 133+ tests)
│   │   ├── 📄 README.md                  # Quick reference
│   │   ├── 📄 TESTING.md                 # Comprehensive testing guide
│   │   ├── 📄 TEST_STATUS.md             # ⭐ NEW - Known failures and progress
│   │   ├── 📄 pytest.ini                 # Pytest configuration
│   │   ├── 📄 conftest.py                # Test fixtures
│   │   ├── 📄 fixtures.py                # Reusable fixtures
│   │   ├── 📄 utils.py                   # Chaos utilities
│   │   ├── 📄 strategies.py              # Hypothesis strategies
│   │   ├── 📁 examples/                  # Learning examples
│   │   └── test_*.py                     # 22 test modules
│   │
│   ├── 📁 e2e/                           # End-to-end tests (22 modules, 78+ tests)
│   │   ├── 📄 README.md                  # E2E testing guide
│   │   └── test_*.py                     # E2E test modules
│   │
│   ├── 📁 integration/                   # Integration tests
│   ├── 📁 performance/                   # Performance benchmarks
│   └── 📁 pgtap/                         # pgTAP unit tests
│
└── 📁 .github/                           # CI/CD workflows
    └── 📁 workflows/                     # ⭐ 14 workflows (security, testing, packaging)
        ├── 📄 chaos-tests.yml            # Chaos testing workflow
        ├── 📄 chaos-weekly.yml           # Weekly chaos runs
        ├── 📄 e2e-tests.yml              # E2E testing workflow
        ├── 📄 tests.yml                  # Core test suite
        ├── 📄 security-scan.yml          # Daily Trivy scans
        ├── 📄 security-tests.yml         # SQL injection prevention
        ├── 📄 sbom.yml                   # SBOM generation
        ├── 📄 release.yml                # Release automation
        └── ... (6 more workflows)
```

**Legend**:
- ⭐ = Highlighted/recommended documents
- ⚠️ = Planned features (not yet implemented)
- 📊 = Data/metrics

**Key Statistics**:
- **70+ documentation files** covering all aspects of pgGit
- **538-line performance tuning guide** for 100GB+ databases
- **442-line SOC2 preparation guide** for compliance
- **278-line FIPS 140-2 compliance guide** for regulated industries
- **133+ chaos tests** across 22 test modules
- **78+ E2E tests** across 22 test modules
- **14 CI/CD workflows** for automation and security

---

## 🚀 Quick Start (5 Minutes)

New to pgGit? Start here:

- **[Getting Started](Getting_Started.md)** - Installation and your first database branch
- **[Troubleshooting](getting-started/Troubleshooting.md)** - Quick fixes for common problems

---

## 👤 Documentation by User Role

### 👨‍💻 For Developers

Building applications with pgGit:

| Need | Document | Description |
|------|----------|-------------|
| **Development Workflow** | [guides/DEVELOPMENT_WORKFLOW.md](guides/DEVELOPMENT_WORKFLOW.md) | ⭐ Core development patterns and best practices |
| **API Reference** | [API_Reference.md](API_Reference.md) | Complete function documentation (50+ functions) |
| **Getting Started** | [Getting_Started.md](Getting_Started.md) | 5-minute setup and first branch |
| **Migration Integration** | [guides/MIGRATION_INTEGRATION.md](guides/MIGRATION_INTEGRATION.md) | Generate migrations for Confiture, Flyway, Alembic |
| **AI Agent Workflows** | [guides/AI_AGENT_WORKFLOWS.md](guides/AI_AGENT_WORKFLOWS.md) | Multi-agent coordination patterns |
| **Integration Guide** | [pggit_v0_integration_guide.md](pggit_v0_integration_guide.md) | Real-world workflow patterns and examples |
| **Pattern Examples** | [Pattern_Examples.md](Pattern_Examples.md) | Common development patterns with code |
| **IDE Setup** | [guides/IDE_SETUP.md](guides/IDE_SETUP.md) | Configure VS Code, JetBrains, Vim, Emacs |

**Most Popular**: Start with Development Workflow → Getting Started → Migration Integration

---

### 🗄️ For Database Administrators

Operating pgGit in development and production:

| Need | Document | Description |
|------|----------|-------------|
| **Production Considerations** | [guides/PRODUCTION_CONSIDERATIONS.md](guides/PRODUCTION_CONSIDERATIONS.md) | ⭐ When to use pgGit in production (compliance use cases) |
| **Operations Runbook** | [operations/RUNBOOK.md](operations/RUNBOOK.md) | Production procedures, incident response (P1-P4) |
| **Monitoring Guide** | [operations/MONITORING.md](operations/MONITORING.md) | Health checks, alerting, Prometheus integration |
| **Performance Tuning** | [guides/PERFORMANCE_TUNING.md](guides/PERFORMANCE_TUNING.md) | Optimization strategies for 100GB+ databases |
| **Disaster Recovery** | [operations/DISASTER_RECOVERY.md](operations/DISASTER_RECOVERY.md) | Backup procedures, recovery, point-in-time restore |
| **SLO Guide** | [operations/SLO.md](operations/SLO.md) | 99.9% uptime targets, availability metrics |
| **Release Checklist** | [operations/RELEASE_CHECKLIST.md](operations/RELEASE_CHECKLIST.md) | Pre-deployment verification procedures |
| **Upgrade Guide** | [operations/UPGRADE_GUIDE.md](operations/UPGRADE_GUIDE.md) | Version migration and upgrade procedures |

**Most Popular**: Start with Production Considerations → Operations Runbook → Monitoring Guide

---

### 🔐 For Security & Compliance Teams

Ensuring pgGit meets regulatory requirements:

| Need | Document | Description |
|------|----------|-------------|
| **Production Considerations** | [guides/PRODUCTION_CONSIDERATIONS.md](guides/PRODUCTION_CONSIDERATIONS.md) | ⭐ 24 compliance frameworks (GDPR, HIPAA, SOX, etc.) |
| **Security Guide** | [guides/Security.md](guides/Security.md) | 30+ security hardening checklist items |
| **FIPS 140-2 Compliance** | [compliance/FIPS_COMPLIANCE.md](compliance/FIPS_COMPLIANCE.md) | Regulated industry compliance checklist |
| **SOC2 Type II** | [compliance/SOC2_PREPARATION.md](compliance/SOC2_PREPARATION.md) | Trust Service Criteria mapping |
| **SLSA Provenance** | [security/SLSA.md](security/SLSA.md) | Supply chain security (provenance attestation) |
| **Vulnerability Policy** | [../SECURITY.md](../SECURITY.md) | Security disclosure and reporting |

**Most Popular**: Start with Production Considerations → Security Guide → SOC2_PREPARATION

---

### 🛠️ For DevOps & Infrastructure Teams

Deploying and automating pgGit:

| Need | Document | Description |
|------|----------|-------------|
| **Migration Integration** | [guides/MIGRATION_INTEGRATION.md](guides/MIGRATION_INTEGRATION.md) | ⭐ CI/CD integration with Confiture, Flyway, Alembic |
| **AI Agent Workflows** | [guides/AI_AGENT_WORKFLOWS.md](guides/AI_AGENT_WORKFLOWS.md) | Multi-agent automation patterns |
| **Release Checklist** | [operations/RELEASE_CHECKLIST.md](operations/RELEASE_CHECKLIST.md) | Pre-deployment verification |
| **Upgrade Guide** | [operations/UPGRADE_GUIDE.md](operations/UPGRADE_GUIDE.md) | Version migration procedures |
| **SLO Guide** | [operations/SLO.md](operations/SLO.md) | Availability targets and measurement |
| **Getting Started** | [Getting_Started.md](Getting_Started.md) | Installation options (Docker, manual, package) |

**Infrastructure-as-Code** (coming in v0.2.0):
- Terraform for automated installation
- Ansible playbook for deployment
- Kubernetes manifests for container orchestration

---

### 📚 For Onboarding & Training

Teaching teams to use pgGit:

| Need | Document | Description |
|------|----------|-------------|
| **Onboarding Guide** | [Onboarding_Guide.md](Onboarding_Guide.md) | Structured learning path with exercises |
| **Getting Started** | [Getting_Started.md](Getting_Started.md) | Friendly introduction to pgGit concepts |
| **Explained Like I'm 10** | [getting-started/PgGit_Explained_Like_Im_10.md](getting-started/PgGit_Explained_Like_Im_10.md) | Simple conceptual overview |
| **Troubleshooting** | [getting-started/Troubleshooting.md](getting-started/Troubleshooting.md) | Common issues and solutions |
| **Pattern Examples** | [Pattern_Examples.md](Pattern_Examples.md) | Real-world use cases |

---

## 📚 Documentation by Feature

### Schema Versioning & Version Control

Understanding pgGit's core version control system:

- [Git Branching Architecture](Git_Branching_Architecture.md) - How branching works, design decisions
- [DDL Hashing Design](DDL_Hashing_Design.md) - Content-addressable schema versioning
- [Schema Reconciliation](Schema_Reconciliation.md) - Detecting and resolving schema drift
- [Hashing Usage](Hashing_Usage.md) - SHA-256 content hashing explained
- [Architecture Overview](Architecture_Decision.md) - Core design decisions

---

### Change Tracking & Audit

Auditing schema changes and compliance:

- [Integration Guide - Audit Section](pggit_v0_integration_guide.md#audit--compliance) - Audit query examples
- [Function Versioning](function-versioning.md) - Tracking function changes
- [Configuration System](configuration-system.md) - Audit settings and options

---

### Branching & Merging

Managing parallel schema development:

- [API Reference - Branch Management](API_Reference.md#-branch-management) - All branching functions
- [Git Branching Architecture](Git_Branching_Architecture.md) - Design and strategy
- [Conflict Resolution Guide](conflict-resolution-and-operations.md) - Handling merge conflicts
- [Integration Guide - Workflow Patterns](pggit_v0_integration_guide.md#workflow-patterns) - Common patterns

---

### Performance & Optimization

Optimizing pgGit for large databases:

- [Performance Analysis](Performance_Analysis.md) - Benchmarks and metrics
- [Performance Tuning Guide](guides/PERFORMANCE_TUNING.md) - Advanced optimization (100GB+ databases)
- [API Reference - Analytics](API_Reference.md#-analytics--monitoring) - Analytics functions

---

### Integration & Automation

Integrating pgGit with other tools:

- [Migration Integration Guide](guides/MIGRATION_INTEGRATION.md) - ⭐ Confiture, Flyway, Liquibase, Alembic integration
- [AI Agent Workflows](guides/AI_AGENT_WORKFLOWS.md) - ⭐ Multi-agent coordination patterns
- [Integration Guide - App Integration](pggit_v0_integration_guide.md#integration-with-apps) - Application integration patterns
- [Migration Integration (legacy)](migration-integration.md) - Flyway, Liquibase overview
- [CQRS Support](cqrs-support.md) - Command Query Responsibility Segregation patterns

---

### Enterprise Features

Advanced pgGit capabilities:

- [Enterprise Features](Enterprise_Features.md) - Zero-downtime, cost optimization, advanced compliance
- [AI Integration Architecture](AI_Integration_Architecture.md) ⚠️ **Planned for v0.3.0** - AI-powered migration analysis
- [Local LLM Quickstart](Local_LLM_Quickstart.md) ⚠️ **Planned for v0.3.0** - AI features setup

---

## 🔍 Complete Function Reference

All pgGit functions documented with examples:

### Branch & Version Management
- [Branch Management Functions](API_Reference.md#-branch-management) - create_branch, create_data_branch, checkout_branch, delete_branch, etc.

### Deployment & Workflow
- [Deployment Functions](API_Reference.md#-deployment) - begin_deployment, end_deployment, get_deployment_status

### Merge & Conflict Resolution
- [Merge Functions](API_Reference.md#-merge--conflict) - merge_branch, detect_merge_conflicts, resolve_conflict, rebase_branch

### Analytics & Monitoring
- [Analytics Functions](API_Reference.md#-analytics--monitoring) - analyze_storage_usage, benchmark_extraction_functions, validate_data_integrity

**Full API Reference**: [API_Reference.md](API_Reference.md)

---

## ❓ Troubleshooting & Help

### Common Problems

- [Troubleshooting Guide](getting-started/Troubleshooting.md) - Diagnose and fix issues
- [DEBUGGING Guide](guides/DEBUGGING.md) - Debug schema issues

### Learning Materials

- **FAQ** (coming in v0.2.0) - Frequently asked questions
- **Common Mistakes** (coming in v0.2.0) - Avoid these pitfalls
- [GLOSSARY](GLOSSARY.md) - Technical terms explained

---

## 🎓 Learning Paths

### Complete Beginner (2-4 hours)

Want to understand pgGit from scratch?

1. **Watch**: [Explained Like I'm 10](getting-started/PgGit_Explained_Like_Im_10.md) (10 min)
   - Simple conceptual overview
   - No technical knowledge required

2. **Do**: [Getting Started](Getting_Started.md) (30 min)
   - Install pgGit
   - Create your first branch
   - Run basic operations

3. **Learn**: [Development Workflow](guides/DEVELOPMENT_WORKFLOW.md) (30 min)
   - Core development patterns
   - Solo and team workflows
   - Best practices

4. **Practice**: [Integration Guide - Basic Operations](pggit_v0_integration_guide.md#basic-operations) (1 hour)
   - List objects, view definitions
   - Create branches and switches
   - Make changes independently

5. **Learn**: [Pattern Examples](Pattern_Examples.md) (1-2 hours)
   - Common real-world scenarios
   - Workflow patterns

**Result**: Ready to use pgGit in development

---

### Developer (4-6 hours)

Building applications with pgGit:

1. **Setup**: [Getting Started](Getting_Started.md) (30 min)
2. **Workflow**: [Development Workflow](guides/DEVELOPMENT_WORKFLOW.md) (30 min) - Core patterns
3. **API**: [API Reference](API_Reference.md) (2 hours) - Understand all available functions
4. **Integration**: [Integration Guide](pggit_v0_integration_guide.md) (1 hour)
   - Application integration patterns
   - Version checking and validation
5. **Migrations**: [Migration Integration](guides/MIGRATION_INTEGRATION.md) (30 min)
   - Generate production migrations
   - CI/CD integration
6. **Troubleshooting**: [Troubleshooting Guide](getting-started/Troubleshooting.md) (30 min)
7. **IDE Setup**: [IDE_SETUP.md](guides/IDE_SETUP.md) (30 min) - Configure your editor

**Result**: Build pgGit-aware applications with production migration workflows

---

### Database Administrator (6-8 hours)

Operating pgGit in development and production:

1. **Production Fit**: [Production Considerations](guides/PRODUCTION_CONSIDERATIONS.md) (30 min)
   - When to use pgGit in production
   - Compliance use cases

2. **Operations**: [Operations Runbook](operations/RUNBOOK.md) (1.5 hours)
   - Incident response procedures
   - Maintenance tasks

3. **Monitoring**: [Monitoring Guide](operations/MONITORING.md) (1 hour)
   - Health checks
   - Alerting setup

4. **Performance**: [Performance Tuning](guides/PERFORMANCE_TUNING.md) (2 hours)
   - Optimization strategies
   - Benchmarking

5. **Disaster Recovery**: [Disaster Recovery Guide](operations/DISASTER_RECOVERY.md) (1.5 hours)
   - Backup strategies
   - Recovery procedures

6. **SLOs**: [SLO Guide](operations/SLO.md) (1 hour)
   - Availability targets
   - Measurement procedures

**Result**: Operate pgGit reliably in development and for compliance requirements

---

### Compliance/Security (6-8 hours)

Meeting regulatory requirements:

1. **Production Assessment**: [Production Considerations](guides/PRODUCTION_CONSIDERATIONS.md) (1 hour)
   - 24 compliance frameworks supported
   - Decision framework for production use

2. **Security**: [Security Hardening Guide](guides/Security.md) (2 hours)
   - 30+ security checklist items
   - Implementation guidance

3. **FIPS 140-2**: [FIPS Compliance Guide](compliance/FIPS_COMPLIANCE.md) (2 hours)
   - If handling regulated data
   - Compliance verification

4. **SOC2**: [SOC2 Preparation](compliance/SOC2_PREPARATION.md) (1.5 hours)
   - Trust Service Criteria mapping
   - Audit preparation

5. **Supply Chain**: [SLSA Provenance](security/SLSA.md) (1.5 hours)
   - Build supply chain security
   - Provenance attestation

**Result**: pgGit deployment meets compliance requirements for 24 regulatory frameworks

---

## 🛠️ Contributing & Development

Improving pgGit:

| Need | Document | Description |
|------|----------|-------------|
| **Contributing Guide** | [../CONTRIBUTING.md](../CONTRIBUTING.md) | How to contribute to pgGit |
| **Testing Guide** | [contributing/TESTING_GUIDE.md](contributing/TESTING_GUIDE.md) (coming in v0.2.0) | Write and run tests |
| **Architecture** | [architecture/MODULES.md](architecture/MODULES.md) | Module structure and design |
| **Design Decisions** | [Architecture_Decision.md](Architecture_Decision.md) | Why certain choices were made |

---

## 📊 Related Docs

### Release & Deployment

- **Release Notes**: [../CHANGELOG.md](../CHANGELOG.md) - Version history and release notes
- **Release Checklist**: [operations/RELEASE_CHECKLIST.md](operations/RELEASE_CHECKLIST.md) - Pre-release verification

### Planning & Strategy

- **New Features Index**: [new-features-index.md](new-features-index.md) - Planned features overview
- **Enterprise Features**: [Enterprise_Features.md](Enterprise_Features.md) - Advanced capabilities

---

## 📌 Version & Status

| Item | Value |
|------|-------|
| **Current Version** | pgGit v0.1.2 |
| **Documentation Updated** | December 31, 2025 |
| **Status** | Production Ready ✅ |
| **Test Coverage** | 191 tests, 100% pass rate ✅ |

### Feature Status Legend

- ✅ **Implemented** - Available in v0.1.2, production-ready
- 🚧 **Planned** - In design/development, coming in v0.3.0+
- 🧪 **Experimental** - Available but may change significantly
- ⚠️ **Partially Experimental** - Some features implemented, others planned

---

## 🔗 Quick Links

### External Resources

- **GitHub Repository**: https://github.com/evoludigit/pgGit
- **PostgreSQL Documentation**: https://www.postgresql.org/docs/
- **Git Documentation**: https://git-scm.com/doc

### In-Project Links

- **Code of Conduct**: [../CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md)
- **Security Policy**: [../SECURITY.md](../SECURITY.md)
- **README**: [../README.md](../README.md)

---

## 💡 Tips for Finding Information

**I want to...**

| Goal | Start Here |
|------|-----------|
| Get pgGit running | [Getting Started](Getting_Started.md) |
| Understand development workflow | [Development Workflow](guides/DEVELOPMENT_WORKFLOW.md) |
| Use pgGit in my app | [Integration Guide](pggit_v0_integration_guide.md) |
| Generate migrations for production | [Migration Integration](guides/MIGRATION_INTEGRATION.md) |
| Coordinate AI agents | [AI Agent Workflows](guides/AI_AGENT_WORKFLOWS.md) |
| Understand all functions | [API Reference](API_Reference.md) |
| Decide if pgGit fits production | [Production Considerations](guides/PRODUCTION_CONSIDERATIONS.md) |
| Operate pgGit in production | [Operations Runbook](operations/RUNBOOK.md) |
| Optimize performance | [Performance Tuning Guide](guides/PERFORMANCE_TUNING.md) |
| Meet compliance requirements | [Production Considerations](guides/PRODUCTION_CONSIDERATIONS.md) |
| Learn how pgGit works | [Architecture Decision](Architecture_Decision.md) |
| Contribute to pgGit | [Contributing Guide](../CONTRIBUTING.md) |
| Fix a problem | [Troubleshooting Guide](getting-started/Troubleshooting.md) |
| Understand technical terms | [GLOSSARY](GLOSSARY.md) |

---

**Last Updated**: December 21, 2025
**Maintained By**: pgGit Documentation Team
**Issues or Questions**: [GitHub Issues](https://github.com/evoludigit/pgGit/issues)
