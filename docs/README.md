# pgGit Documentation 🐘🌿

> **Git Workflows for PostgreSQL Development** - Version control your database schema in development

Welcome to the complete guide for pgGit, the PostgreSQL extension that brings Git-style workflows to your database development.

> **Note**: pgGit is primarily designed for development and staging environments. For production use cases, see [Production Considerations](guides/PRODUCTION_CONSIDERATIONS.md) to determine if pgGit is appropriate for your compliance requirements.

## 🚀 Quick Start (Choose Your Path)

### New to pgGit? Start Here
- **[📚 Getting Started](Getting_Started.md)** - Complete setup guide with real examples
- **[🧒 Explained Like I'm 10](getting-started/PgGit_Explained_Like_Im_10.md)** - Technical concepts for curious minds
- **[🔄 Development Workflow](guides/DEVELOPMENT_WORKFLOW.md)** - Core development patterns

### Ready to Integrate?
- **[⚡ Quick Setup](getting-started/README.md)** - Installation in 5 minutes
- **[🔗 Migration Integration](guides/MIGRATION_INTEGRATION.md)** - Confiture, Flyway, Alembic integration
- **[🤖 AI Agent Workflows](guides/AI_AGENT_WORKFLOWS.md)** - Multi-agent coordination
- **[🔧 Troubleshooting](getting-started/Troubleshooting.md)** - Solutions to common issues

### Production Deployment?
- **[📋 Production Considerations](guides/PRODUCTION_CONSIDERATIONS.md)** - When pgGit makes sense in production
- **[🔐 Security Guide](guides/Security.md)** - Security hardening checklist

## 🧪 Test Suite: The Source of Truth

**pgGit's test suite is our documentation's foundation** - everything listed below is 100% tested and working:

- **[Core Tests](../tests/test-core.sql)** - Database versioning fundamentals (5s runtime)
- **[Enterprise Tests](../tests/test-enterprise.sql)** - Advanced branching & analytics (10s runtime)
- **[AI Tests](../tests/test-ai.sql)** - Machine learning integration (15s runtime)
- **[Full Test Runner](../tests/test-full.sh)** - Complete validation suite (30s total)

**Run the tests yourself:**
```bash
# Quick validation
make test-core

# Full enterprise feature validation
./tests/test-full.sh --podman
```

*If it's not tested, it's not documented here. Harper's promise.* ✅

## 📖 Core Documentation

### ✅ Production-Ready Features (100% Tested)
- **[🏗️ System Architecture](Git_Branching_Architecture.md)** - Core versioning system (test-core.sql ✅)
- **[🤖 AI Integration](AI_Integration_Architecture.md)** - Machine learning migration analysis (test-ai.sql ✅)
- **[🏢 Enterprise Features](Enterprise_Features.md)** - Branch management & analytics (test-enterprise.sql ✅)
- **[📋 API Reference](API_Reference.md)** - All tested functions with examples

### Architecture & Implementation
- **[🎯 Architecture Decisions](Architecture_Decision.md)** - Why we built it this way
- **[#️⃣ DDL Hashing Design](DDL_Hashing_Design.md)** - Schema change tracking architecture
- **[#️⃣ DDL Hashing Usage](Hashing_Usage.md)** - How to use hash-based change detection
- **[🔄 Schema Reconciliation](Schema_Reconciliation.md)** - Complex merge handling
- **[⚡ Performance Analysis](Performance_Analysis.md)** - Benchmarked optimization strategies

### Development & Integration Guides
- **[🔄 Development Workflow](guides/DEVELOPMENT_WORKFLOW.md)** - Core development patterns
- **[🔗 Migration Integration](guides/MIGRATION_INTEGRATION.md)** - Confiture, Flyway, Alembic
- **[🤖 AI Agent Workflows](guides/AI_AGENT_WORKFLOWS.md)** - Multi-agent coordination
- **[📋 Production Considerations](guides/PRODUCTION_CONSIDERATIONS.md)** - When to use in production

### Operational Guides
- **[🔐 Security Guide](guides/Security.md)** - RBAC, GDPR compliance (enterprise tested)
- **[📊 Operations Guide](guides/Operations.md)** - Production deployment patterns
- **[⚡ Performance Guide](guides/Performance.md)** - Monitoring and optimization
- **[🎯 Pattern Examples](Pattern_Examples.md)** - Real-world tested workflows
- **[🧪 Local LLM Setup](Local_LLM_Quickstart.md)** - AI-powered database assistance

## 📁 Documentation Structure

```
docs/
├── README.md                    # This navigation file
├── Getting_Started.md           # Complete tutorial with examples
├── API_Reference.md             # Function documentation
├── getting-started/             # Beginner-friendly guides
│   ├── README.md                # Quick setup
│   ├── PgGit_Explained_Like_Im_10.md
│   └── Troubleshooting.md
├── guides/                      # Task-oriented guides
│   ├── README.md                # Guides overview
│   ├── DEVELOPMENT_WORKFLOW.md  # ⭐ Core development patterns
│   ├── PRODUCTION_CONSIDERATIONS.md # ⭐ When to use in production
│   ├── MIGRATION_INTEGRATION.md # ⭐ Confiture, Flyway, Alembic
│   ├── AI_AGENT_WORKFLOWS.md    # ⭐ Multi-agent coordination
│   ├── Security.md
│   ├── Performance.md
│   └── Operations.md
├── contributing/                # For contributors
│   ├── README.md
│   └── Claude.md
└── reference/                   # Technical specs
    └── README.md
```

## 🤝 Contributing

Want to help improve pgGit? Check out our **[Contributing Guide](contributing/README.md)** for:
- Development setup instructions
- Build and test procedures
- Code style guidelines
- How to submit pull requests

## Design Principles

1. **Speed above all else** - Every millisecond counts
2. **No JavaScript** - HTML and CSS only
3. **System fonts** - No web font downloads
4. **Semantic HTML** - Accessible by default
5. **Mobile-first** - Works on any device
6. **Progressive enhancement** - Works without CSS too

## Team Credits

- **Yuki Tanaka-Roberts** - Web Design & Performance
- **Harper Quinn-Davidson** - Content & Documentation
- **The entire persona team** - Collaborative design

## Future Enhancements (Maybe)

- Service worker for offline (progressive enhancement)
- Search functionality (if we can do it in <5KB JS)
- Dark mode improvements
- Print stylesheet refinements

Remember: The best documentation site is one that loads instantly and lets developers find what they need without friction.