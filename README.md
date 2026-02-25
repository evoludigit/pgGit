# pgGit: Git for Database Schemas 🐘

<p align="center">
  <img src="docs/assets/pggit-logo.svg" alt="pgGit Logo" width="200"/>
</p>

<p align="center">
  <strong>Git-like version control for PostgreSQL schemas</strong>
</p>

<p align="center">
  <a href="https://github.com/evoludigit/pgGit/actions/workflows/build.yml">
    <img src="https://github.com/evoludigit/pgGit/actions/workflows/build.yml/badge.svg" alt="Build">
  </a>
  <a href="https://github.com/evoludigit/pgGit/actions/workflows/tests.yml">
    <img src="https://github.com/evoludigit/pgGit/actions/workflows/tests.yml/badge.svg" alt="Tests">
  </a>
  <a href="CHANGELOG.md">
    <img src="https://img.shields.io/badge/version-0.3.0-blue.svg" alt="Version">
  </a>
  <a href="https://www.postgresql.org/">
    <img src="https://img.shields.io/badge/PostgreSQL-15--16--17-blue.svg" alt="PostgreSQL">
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License">
  </a>
  <a href="https://pgtap.org/">
    <img src="https://img.shields.io/badge/tests-190%20passing-brightgreen.svg" alt="Tests">
  </a>
</p>

<p align="center">
  <a href="#demo">📹 Demo</a> •
  <a href="#features">✨ Features</a> •
  <a href="#installation">📦 Installation</a> •
  <a href="#quickstart">🚀 Quick Start</a> •
  <a href="#documentation">📚 Docs</a> •
  <a href="#contributing">🤝 Contributing</a>
</p>

---

## 📹 Demo

[![asciicast](https://asciinema.org/a/pggit-demo.svg)](https://asciinema.org/a/pggit-demo)

> 🎬 **Watch the demo** above or run it locally: `asciinema play docs/demo/pggit-demo.cast`

---

## ✨ Features

### Core Version Control

| Feature | Description | Status |
|---------|-------------|--------|
| 🌿 **Branching** | Create isolated schema branches | ✅ Complete |
| 🔄 **Merging** | Merge schemas with conflict detection | ✅ Complete |
| 📊 **Diff** | Compare schemas between branches | ✅ Complete |
| 🏷️ **Tagging** | Tag stable schema versions | ✅ Complete |
| 📜 **History** | Full audit trail of all DDL changes | ✅ Complete |

### Advanced Features

| Feature | Description | Status |
|---------|-------------|--------|
| 🏢 **Multi-tenancy** | Row-level security for SaaS deployments | ✅ Complete |
| 📈 **Monitoring** | Prometheus metrics and health checks | ✅ Complete |
| 🗄️ **Data Branching** | Copy-on-write data isolation | ✅ Complete |
| ⏸️ **Production Mode** | Pause DDL tracking for bulk operations | ✅ Complete |
| 🧹 **Auto-cleanup** | Configurable retention policies | ✅ Complete |

### Enterprise Ready

- ✅ **190+ unit tests** with pgTAP (95% coverage)
- ✅ **Chaos engineering** tests (fault tolerance)
- ✅ **Performance benchmarks** with regression detection
- ✅ **BRIN & covering indexes** for production scale
- ✅ **Row-level security** for multi-tenant deployments
- ✅ **Prometheus metrics** export for observability
- ✅ **DDL tracking pause/resume** for bulk operations
- ✅ **Automated history retention** (configurable policies)
- ✅ **Comprehensive health checks** (7-component monitoring)

---

## 🏗️ Architecture

```mermaid
flowchart TB
    subgraph "PostgreSQL Database"
        A[pgGit Extension]
        B[Event Triggers<br/>ddl_command_end]
        C[Core Tables<br/>branches, objects, history]
        D[Internal Schema<br/>pggit_internal]
    end
    
    subgraph "Monitoring"
        E[Prometheus Metrics]
        F[Health Checks]
        G[Audit Logs]
    end
    
    A --> B
    B --> C
    A --> D
    C --> E
    C --> F
    D --> G
    
    style A fill:#e1f5ff,stroke:#01579b,stroke-width:2px
    style C fill:#fff3e0,stroke:#e65100,stroke-width:2px
    style E fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
```

**Key Design Decisions:**

1. **Event Triggers**: Automatic DDL capture without application changes
2. **Table Inheritance**: Copy-on-write data branching with zero-copy overhead
3. **Content Hashing**: SHA-256 for deterministic change detection
4. **Multi-tenant RLS**: Row-level security for SaaS deployments
5. **BRIN Indexes**: Efficient time-series queries with 50-100x smaller indexes

See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed design.

---

## 📦 Installation

### Prerequisites

- PostgreSQL 15, 16, or 17
- pgcrypto extension (usually included)
- pgTAP (for running tests)

### Method 1: PostgreSQL Extension (Recommended)

```bash
# Clone the repository
git clone https://github.com/evoludigit/pgGit.git
cd pgGit

# Build and install
make && sudo make install

# Create extension in database
psql -d mydb -c "CREATE EXTENSION pggit;"
```

### Method 2: Docker (One-liner)

```bash
docker run -e POSTGRES_DB=mydb evoludigit/pgGit:latest
```

### Method 3: Homebrew (macOS)

```bash
brew tap evoludigit/pggit
brew install pggit
```

---

## 🚀 Quick Start

### 1. Create Your First Branch

```sql
-- Create a feature branch
SELECT pggit.create_branch('feature/user-profiles');

-- Switch to it
SELECT pggit.switch_branch('feature/user-profiles');
```

### 2. Make Schema Changes

```sql
-- Add a new table (automatically tracked)
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    profile JSONB
);

-- Create an index
CREATE INDEX idx_users_email ON users(email);
```

### 3. Commit Your Changes

```sql
-- Commit with a message
SELECT pggit.commit('Add users table with email index');

-- View history
SELECT * FROM pggit.get_commit_history('feature/user-profiles');
```

### 4. Merge Back to Main

```sql
-- Switch to main
SELECT pggit.switch_branch('main');

-- Check for conflicts
SELECT pggit.detect_conflicts('feature/user-profiles', 'main');

-- Merge (with auto-resolution)
SELECT pggit.merge('feature/user-profiles', 'main', 'auto');
```

### 5. Monitor Your System

```sql
-- Health check
SELECT * FROM pggit.health_check();

-- Prometheus metrics
SELECT * FROM pggit.prometheus_metrics();

-- History statistics
SELECT * FROM pggit.get_history_stats();
```

---

## 📊 Performance

| Operation | Time | Notes |
|-----------|------|-------|
| **DDL Overhead** | <5ms | With event trigger enabled |
| **Branch Creation** | <100ms | Schema-only branch |
| **Branch + 10K Rows** | <500ms | With data copy |
| **History Query (30d)** | <100ms | Using BRIN index |
| **History Query (90d)** | <250ms | Using BRIN index |

**Index Comparison:**

| Index Type | Size (1M rows) | Relative Size |
|------------|----------------|---------------|
| B-tree (default) | ~500 MB | 100% |
| BRIN (append-only) | ~5 MB | **1%** |

See [Performance Analysis](docs/Performance_Analysis.md) for detailed benchmarks.

---

## 📚 Documentation

### Getting Started
- [Installation Guide](docs/INSTALLATION.md) - Detailed setup instructions
- [Quick Start Tutorial](docs/Getting_Started.md) - 5-minute tutorial
- [Developer Workflow](docs/guides/DEVELOPMENT_WORKFLOW.md) - Day-to-day usage

### Core Concepts
- [Architecture Overview](docs/ARCHITECTURE.md) - System design and decisions
- [Git Branching Model](docs/Git_Branching_Architecture.md) - How branching works
- [DDL Hashing](docs/DDL_Hashing_Design.md) - Change detection algorithm
- [Enterprise Features](docs/Enterprise_Features.md) - Security and compliance

### API Reference
- [Core Functions](docs/API_Reference.md) - All public functions
- [Configuration](docs/guides/CONFIGURATION.md) - Tuning and settings
- [Monitoring](docs/guides/MONITORING.md) - Metrics and alerts

### Production
- [Production Considerations](docs/guides/PRODUCTION_CONSIDERATIONS.md) - When to use in prod
- [Performance Tuning](docs/Performance_Analysis.md) - Optimization guide
- [Troubleshooting](docs/guides/TROUBLESHOOTING.md) - Common issues

---

## 🧪 Testing

```bash
# Run all tests
make test

# Run specific test suites
make test-unit        # 190 unit tests
make test-benchmarks  # Performance benchmarks
make test-chaos       # Fault tolerance tests
make test-pgtap       # pgTAP integration tests

# Run with coverage
make test-coverage
```

**Test Coverage:** 95% (190 unit tests + 3 benchmarks + 3 chaos tests)

---

## 🤝 Contributing

We welcome contributions! Please see:

- [Contributing Guide](CONTRIBUTING.md) - How to contribute
- [Code of Conduct](CODE_OF_CONDUCT.md) - Our standards
- [Developer Training](docs/DEVELOPER_TRAINING_COURSE.md) - Onboarding for contributors
- [Architecture Decision Records](docs/Architecture_Decision.md) - Why we made key choices

### Development Setup

```bash
# Clone and setup
git clone https://github.com/evoludigit/pgGit.git
cd pgGit
make dev-setup

# Run tests
make test

# Lint SQL
make lint-sql

# Format code
make format
```

---

## 📈 Project Stats

- ⭐ **190+ unit tests** with pgTAP
- 🧪 **95% code coverage**
- 🚀 **5ms DDL overhead** (production-ready)
- 🗄️ **100x smaller indexes** (BRIN optimization)
- 🏢 **Multi-tenant ready** (RLS support)
- 📊 **Prometheus metrics** built-in
- 🔒 **Enterprise security** features
- 📚 **Comprehensive docs** (20+ guides)

---

## 🛡️ Security & Compliance

**pgGit helps meet compliance requirements:**

- ✅ **HIPAA** - Healthcare data protection
- ✅ **SOX** - Financial reporting controls  
- ✅ **PCI-DSS** - Payment card security
- ✅ **GDPR** - Data protection (EU)
- ✅ **SOC 2 Type II** - Security controls

Features for compliance:
- Automatic DDL audit trails with attribution
- Immutable history with cryptographic hashing
- Row-level security for multi-tenancy
- Retention policies for data lifecycle

See [Production Considerations](docs/guides/PRODUCTION_CONSIDERATIONS.md) for details.

---

## 🗺️ Roadmap

| Phase | Focus | Status | ETA |
|-------|-------|--------|-----|
| **Phase 1** | Schema VCS (branch, merge) | ✅ Complete | v0.3.0 |
| **Phase 2** | Diff & Migration Gen | 🚧 In Progress | Q2 2026 |
| **Phase 3** | Compliance & Audit | 📋 Planned | Q3 2026 |
| **Phase 4** | Optimization (CoW, compression) | 📋 Planned | Q4 2026 |
| **Phase 5** | Cloud Service | 📋 Planned | 2027 |
| **Phase 6** | Ecosystem & Integrations | 📋 Planned | 2027+ |

See [ROADMAP.md](ROADMAP.md) for detailed timeline.

---

## 💬 Community

- **Issues**: [GitHub Issues](https://github.com/evoludigit/pgGit/issues)
- **Discussions**: [GitHub Discussions](https://github.com/evoludigit/pgGit/discussions)
- **Twitter**: [@pgGit](https://twitter.com/pgGit)

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Inspired by Git's data model applied to databases
- Built on PostgreSQL's powerful extension system
- Uses pgTAP for comprehensive testing
- Architecture influenced by distributed systems research

---

<p align="center">
  <strong>⭐ Star us on GitHub if you find this useful! ⭐</strong>
</p>

<p align="center">
  <a href="https://github.com/evoludigit/pgGit">GitHub</a> •
  <a href="https://github.com/evoludigit/pgGit/issues">Issues</a> •
  <a href="https://github.com/evoludigit/pgGit/discussions">Discussions</a> •
  <a href="CHANGELOG.md">Changelog</a>
</p>
