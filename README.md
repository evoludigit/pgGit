# pgGit: Git for PostgreSQL Databases 🚀

[![Build](https://github.com/evoludigit/pgGit/actions/workflows/build.yml/badge.svg)](https://github.com/evoludigit/pgGit/actions/workflows/build.yml)
[![Tests](https://github.com/evoludigit/pgGit/actions/workflows/test-with-fixes.yml/badge.svg)](https://github.com/evoludigit/pgGit/actions/workflows/test-with-fixes.yml)
[![PostgreSQL 15-17](https://img.shields.io/badge/PostgreSQL-15--17-blue.svg)](https://www.postgresql.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> [!CAUTION]
> **⚠️ EXPERIMENTAL PROJECT - NOT PRODUCTION READY ⚠️**
>
> This project is created by a self-taught database programmer experimenting with Claude AI and PostgreSQL internals. The code quality is waiting to be roasted by experienced developers. Please use this only for learning and experimentation - definitely NOT in production yet!
>
> Contributions, code reviews, and constructive criticism are very welcome! 🙏

**Git-like version control for PostgreSQL schemas. Track, branch, and manage database changes like code.**

---

## 🚀 Quick Start

```bash
# Install pgGit
git clone https://github.com/evoludigit/pgGit.git
cd pgGit
make && sudo make install

# Use it
psql -c "CREATE EXTENSION pggit"
psql -c "CREATE TABLE users (id SERIAL PRIMARY KEY, name TEXT)"
psql -c "SELECT * FROM pggit.get_version('users')"  # Version 1.0.0!
```

## 📚 Documentation

### 🎯 Get Started

- **New to pgGit?** → [Getting Started Guide](docs/getting-started/Getting_Started.md)
- **Want details?** → [Architecture Overview](docs/Architecture_Decision.md)
- **Module Structure** → [Module Architecture](docs/architecture/MODULES.md)

### 📖 Comprehensive Guides

- [Performance Guide](docs/guides/Performance.md) - Optimize for large databases
- [Security Guide](docs/guides/Security.md) - Secure your installation
- [Security Policy](SECURITY.md) - Report vulnerabilities
- [Operations Guide](docs/guides/Operations.md) - Production deployment
- [Module Architecture](docs/architecture/MODULES.md) - Core vs extensions

### 🔧 Reference

- [API Reference](docs/reference/README.md) - Complete function documentation
- [Contributing Guide](docs/contributing/README.md) - Help improve pgGit
- [Troubleshooting](docs/getting-started/Troubleshooting.md) - Fix common issues

## ⚡ Instant Demo

```bash
# Try pgGit instantly with Docker
docker-compose up -d
docker-compose exec pggit-demo psql -h postgres -U pggit_user -d pggit_demo
```

## What if your database could branch like your code?

You know that moment when you're staring at a production database after a deployment, wondering "What changed? Who changed it? And please tell me there's a way back?" We've all been there.

**pgGit solves this by bringing Git-like version control to PostgreSQL databases.**

---

## 🎯 What Makes This Revolutionary

### Not Just Schema Tracking - Actual Database Git

Everyone else tracks migrations. We've built **actual Git workflows inside PostgreSQL**:

- **🌿 Native Branching**: Create isolated database branches with real data
- **🔀 Three-Way Merging**: Intelligent conflict resolution for schema and data changes
- **💾 Efficient Storage**: PostgreSQL 17 compression enables practical data branching
- **⚡ High Performance**: Optimized for speed with minimal overhead
- **🔄 Copy-on-Write**: Branch data without exploding storage costs

### The "Finally!" Moment for Database DevOps

```sql
-- Monday: Create a feature branch with actual data
SELECT pggit.create_data_branch('feature/user-profiles', 'main', true);

-- Tuesday: Make breaking changes safely
ALTER TABLE users ADD COLUMN avatar_url TEXT;
INSERT INTO users (name, avatar_url) VALUES ('Test User', 'test.jpg');

-- Wednesday: Merge back to main with zero conflicts
SELECT pggit.merge_compressed_branches('feature/user-profiles', 'main');
-- Result: 'MERGE_SUCCESS' + automatic compression optimization
```

---

## 🚀 Everything Included (No Premium Gates)

### Database Branching (Finally Real)

- **Schema Branching**: Independent DDL changes per branch
- **Data Branching**: Copy-on-write data isolation using PostgreSQL inheritance
- **Branch Views**: Automatic query routing to branch-specific data
- **Storage Efficiency**: Compression technology reduces storage overhead

### Intelligent Merging

- **Three-Way Conflict Detection**: Compare base, source, and target branches
- **Automatic Resolution**: Smart defaults for non-conflicting changes
- **Manual Override**: Clean UI for resolving complex conflicts
- **Compression-Aware**: Optimize storage during merge operations

### PostgreSQL 17 Native Integration

- **LZ4/ZSTD Compression**: Native PostgreSQL 17 compression support
- **Event Triggers**: Real-time change capture with zero configuration
- **JSONB Optimization**: Column-level compression for efficient storage
- **Performance**: Optimized I/O with compressed storage

### AI-Powered Migration Analysis

- **PostgreSQL-Native AI**: Built-in heuristic analysis with pattern learning
- **Real-time Analysis**: Fast migration risk assessment
- **High Confidence**: Reliable accuracy for common migration patterns
- **Edge Case Detection**: Automatic flagging of high-risk operations
- **100% Privacy**: All analysis happens in your PostgreSQL instance
- **GPT-2 Ready**: Optional integration with local LLMs for enhanced analysis

---

## 📊 Key Features

### What pgGit Provides

| Feature | Traditional Tools | **pgGit** |
|---------|-------------------|-----------|
| Schema Tracking | ✅ | ✅ |
| Database Branching | Limited | **✅ Real Git-like** |
| Data Branching | Not Available | **✅ Copy-on-Write** |
| Storage Management | High overhead | **Optimized with compression** |
| Merge Conflicts | Manual resolution | **Automated 3-way detection** |
| PostgreSQL 17 Native | Basic support | **✅ Full integration** |
| **Selective Tracking** | ❌ | **✅ Configure what to track** |
| **CQRS Support** | ❌ | **✅ Built-in patterns** |
| **Function Overloading** | Limited | **✅ Full signature tracking** |
| **Migration Tools** | Separate | **✅ Integrated** |
| **Emergency Controls** | ❌ | **✅ Production-ready** |
| License | Commercial | **MIT (Free)** |

### Performance Monitoring

```sql
-- Monitor your pgGit installation
SELECT pggit.generate_contribution_metrics();
```

| Operation | Traditional Approach | pgGit Approach |
|-----------|---------------------|----------------|
| Branch Creation | Complex setup process | Streamlined branch creation |
| Change Management | Manual tracking | Automated event triggers |
| Storage Usage | Full database copies | Compressed, efficient storage |
| Conflict Resolution | Manual intervention | Automated detection and resolution |

---

## 🏢 Enterprise Features (New!)

### Configuration System
Control exactly what pgGit tracks with fine-grained configuration:

```sql
-- Configure for CQRS architecture
SELECT pggit.configure_tracking(
    track_schemas => ARRAY['command', 'domain'],
    ignore_schemas => ARRAY['query', 'read_model'],
    ignore_operations => ARRAY['REFRESH MATERIALIZED VIEW']
);

-- Use deployment mode for releases
SELECT pggit.begin_deployment('Release 2.1.0');
-- Make multiple changes...
SELECT pggit.end_deployment();
```

### CQRS Support
Built-in support for Command Query Responsibility Segregation:

```sql
-- Track coordinated changes across command and query sides
SELECT pggit.track_cqrs_change(
    ROW(
        ARRAY['ALTER TABLE command.orders ADD status text'],
        ARRAY['CREATE MATERIALIZED VIEW query.order_summary AS ...'],
        'Add order status tracking',
        '2.1.0'
    )::pggit.cqrs_change
);
```

### Enhanced Function Versioning
Full support for function overloading and metadata:

```sql
-- Track function with metadata
COMMENT ON FUNCTION api.process_order(jsonb) IS
'Process customer orders
@pggit-version: 3.1.0
@pggit-author: Order Team
@pggit-tags: orders, api, critical';

SELECT pggit.track_function('api.process_order(jsonb)');
```

### Migration Tool Integration
Works alongside Flyway, Liquibase, and other tools:

```sql
-- Enable Flyway integration
SELECT pggit.integrate_flyway('public');

-- Validate migration sequence
SELECT * FROM pggit.validate_migrations('flyway');
```

### Emergency Controls
Production-ready operational commands:

```sql
-- Emergency disable for maintenance
SELECT pggit.emergency_disable('30 minutes'::interval);

-- Check system status
SELECT * FROM pggit.status();

-- Resolve conflicts easily
SELECT pggit.resolve_conflict(conflict_id, 'use_current', 'Keep production version');
```

📚 **[Full Enterprise Documentation →](docs/new-features-index.md)**

---

## 🚀 Quick Start

### 1. Install pgGit (2 minutes)

```bash
# For PostgreSQL 17 (with compression support)
git clone https://github.com/evoludigit/pgGit.git
cd pgGit
sudo make install

# Create extension
psql -d your_database -c "CREATE EXTENSION pggit CASCADE;"
```

### 2. Your First Database Branch (30 seconds)

```sql
-- Initialize pgGit on your database
SELECT pggit.init();

-- Create your first branch
SELECT pggit.create_branch('feature/new-ui');

-- Make changes safely
ALTER TABLE users ADD COLUMN theme VARCHAR(50) DEFAULT 'dark';

-- See what changed
SELECT * FROM pggit.status();

-- Merge back when ready
SELECT pggit.merge('feature/new-ui', 'main');
```

### 3. Time Travel Through Your Database

```sql
-- See all database versions
SELECT * FROM pggit.log();

-- Checkout any point in time
SELECT pggit.checkout('3 hours ago');

-- Or checkout specific commit
SELECT pggit.checkout('abc123def');
```

---

## 💡 Why I'm Building This in Public

I'm building pgGit because database version control shouldn't be a luxury. Every PostgreSQL team deserves Git-like workflows.

**Solo Dev Philosophy**: Rather than perfecting in secret, I'm sharing the journey. This is v0.1 - functional but evolving. Your feedback shapes what this becomes.

## 🌟 Completely Free & Open Source

pgGit is 100% free and open source software:

- ⭐ Star this repository if you find it useful
- 🐛 Report bugs and request features
- 🔧 Submit pull requests to help improve it
- 📢 Share with your team and community

No sponsorship, donations, or premium features. Just great PostgreSQL tooling for everyone.

---

## 🛠️ Full Feature List

Since everything is free, here's what you get:

### Core Features

- ✅ Automatic DDL change tracking
- ✅ Git-style branching and merging
- ✅ Three-way conflict resolution
- ✅ Time-travel to any database state
- ✅ PostgreSQL 17 compression (efficient storage)
- ✅ Complete audit trail
- ✅ Dependency tracking

### Enterprise Features (Also Free!)

- ✅ **AI-Powered Migration Analysis** - High accuracy, pattern learning
- ✅ **Enterprise Impact Analysis** - Financial risk, SLA impact, stakeholder mapping
- ✅ **Zero-Downtime Deployment** - Shadow tables, blue-green, progressive rollout
- ✅ **Cost Optimization Dashboard** - Compression analysis and recommendations
- ✅ **CI/CD Integration** - Jenkins, GitLab, GitHub Actions configs
- ✅ **Authentication & RBAC** - LDAP, SAML SSO, API tokens, granular permissions
- ✅ **Compliance Reporting** - SOX, HIPAA, GDPR automated checks
- ✅ **Multi-Database Sync** - Cross-database migration analysis
- ✅ **Performance Monitoring** - Real-time metrics dashboard
- ✅ And everything else we build

---

## 📚 Documentation

### Core Documentation
- [Getting Started Guide](docs/Getting_Started.md)
- [Architecture Overview](docs/Architecture_Decision.md)
- [API Reference](docs/API_Reference.md)

### Enterprise Features (New!)
- [New Features Overview](docs/new-features-index.md)
- [Configuration System](docs/configuration-system.md)
- [CQRS Support](docs/cqrs-support.md)
- [Function Versioning](docs/function-versioning.md)
- [Migration Integration](docs/migration-integration.md)
- [Conflict Resolution & Operations](docs/conflict-resolution-and-operations.md)

---

## 🤝 Contributing

pgGit is 100% open source and we welcome contributions:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

MIT License - Use it however you want. No strings attached.

```
MIT License

Copyright (c) 2025 pgGit contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 🚀 What's Next?

- **GitHub**: [@evoludigit](https://github.com/evoludigit)
- **Code of Conduct**: [Community Guidelines](CODE_OF_CONDUCT.md)

---

*Built with ❤️ by a solo developer learning PostgreSQL internals and building in public*

