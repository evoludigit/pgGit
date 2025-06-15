# Contributing to pgGit

Thank you for your interest in contributing to pgGit! This guide will help you get started.

## 🚀 Quick Start

1. **Fork the repository**
2. **Clone your fork**: `git clone https://github.com/[your-username]/pggit.git`
3. **Build and test**: `make && sudo make install`
4. **Run tests**: `make test`

## 📋 Development Setup

### Prerequisites

- PostgreSQL 17+
- Make and PGXS
- Podman or Docker (for containerized testing)
- Python 3.8+ (for AI features)

### Build Commands

```bash
# Build the extension
make

# Install to PostgreSQL
sudo make install

# Clean build artifacts
make clean

# Complete rebuild and reinstall
make clean && make && sudo make install
```

### Test Commands

```bash
# Create the extension
psql -c "CREATE EXTENSION pggit"

# Or use makefile targets
make test-core      # Core functionality
make test-ai        # AI features
make test-enterprise # Enterprise features
make test-all       # All tests

# Run comprehensive tests
make test

# Run specific tests
psql -f sql/007_pgtap_examples.sql
```

## 🎯 How to Contribute

### 1. Bug Reports
- Use GitHub Issues
- Include reproduction steps
- Add your system info: PostgreSQL version, OS, etc.
- **Include performance metrics** (see below)

### 2. Feature Requests
- Check existing issues first
- Describe the use case clearly
- Consider implementation complexity

### 3. Code Contributions
- Follow existing code style
- Add tests for new functionality
- Update documentation
- Include performance impact assessment

## 📊 Voluntary Performance Metrics

Help improve pgGit by sharing anonymous performance data!

### Metrics Collection Function

We've created a voluntary metrics collection function that you can run to help us understand pgGit's performance across different environments:

```sql
-- Generate performance metrics for contribution
SELECT pggit.generate_contribution_metrics();
```

### What Gets Collected

The function collects **only** anonymous technical data:

- **Database scale**: Number of tables, indexes, functions
- **pgGit usage**: Number of tracked objects, history records
- **Performance timings**: How long key operations take
- **System info**: CPU cores, available memory, PostgreSQL version
- **No sensitive data**: No table names, schema details, or business data

### Example Output
```json
{
  "timestamp": "2024-06-15T10:30:00Z",
  "database_objects": {
    "tables": 245,
    "indexes": 1032,
    "functions": 89,
    "triggers": 12
  },
  "pggit_metrics": {
    "tracked_objects": 245,
    "history_records": 1834,
    "avg_analysis_time_ms": 23,
    "storage_overhead_percent": 2.1
  },
  "system_info": {
    "postgresql_version": "17.0",
    "cpu_cores": 8,
    "memory_gb": 32,
    "os": "linux"
  },
  "performance_benchmarks": {
    "event_trigger_overhead_us": 156,
    "ai_analysis_time_ms": 23,
    "migration_generation_ms": 89
  }
}
```

### How to Share Metrics

1. **Run the function**: `SELECT pggit.generate_contribution_metrics();`
2. **Copy the JSON output**
3. **Share via**:
   - GitHub Issue with tag `[metrics]`
   - Create a GitHub issue with metrics data
   - Anonymous paste service with link in GitHub Discussions

### Privacy Guarantee

- **No business data**: Table names, column names, or data values
- **No connection info**: Server addresses, credentials, or network details
- **Purely technical**: Only performance and scale metrics
- **Completely voluntary**: You control what to share and when

## 🔧 Development Guidelines

### Code Style

- Follow existing PostgreSQL extension patterns
- Use consistent naming conventions
- Comment complex logic
- Keep functions focused and small

### Testing

- Add pgTAP tests for new features
- Ensure all tests pass (make test)
- Test with different PostgreSQL versions
- Consider performance impact

### Documentation

- Update relevant guides in `/docs/`
- Add examples for new features
- Keep CLAUDE.md updated for development instructions

## 🎯 Contribution Areas

### High Priority

- **Performance optimizations**: Event trigger efficiency
- **AI improvements**: Better migration analysis
- **Cross-platform support**: Windows, macOS testing
- **Documentation**: User guides and examples

### Medium Priority

- **Enterprise features**: Advanced monitoring, reporting
- **Integration**: CI/CD platform support
- **Visualization**: Web dashboard, migration flowcharts
- **Testing**: More edge cases, stress testing

### Nice to Have

- **Multi-database support**: MySQL, SQL Server adapters
- **Cloud integrations**: AWS RDS, Google Cloud SQL
- **Advanced AI**: GPT-4 integration, custom models
- **Mobile apps**: iOS/Android management apps

## 📈 Performance Contributions

When contributing performance improvements:

1. **Benchmark before/after**: Use the metrics function
2. **Document methodology**: How you measured improvement
3. **Share test environment**: System specs, data size
4. **Include edge cases**: Large databases, high frequency changes

### Example Performance PR

```markdown
## Performance Improvement: Event Trigger Optimization

### Problem
Event triggers taking 500μs on large schemas

### Solution
Optimized object lookup with better indexing

### Results
- Before: 500μs average
- After: 156μs average
- Improvement: 69% faster

### Test Environment
- PostgreSQL 17.0
- 8 CPU cores, 32GB RAM
- 245 tables, 1032 indexes
- Test data: [link to metrics output]
```

## 🤝 Community

### Communication

- **GitHub Discussions**: General questions, ideas
- **GitHub Issues**: Bug reports, feature requests
- **Email**: contact@pggit.dev (for sensitive issues)

### Code of Conduct

- Be respectful and inclusive
- Help others learn and contribute
- Focus on technical merit
- Share knowledge and resources

## 🏆 Recognition

Contributors are recognized in:
- `CONTRIBUTORS.md` file
- Release notes for significant contributions
- GitHub contributor graphs and stats

Major contributors may be invited to:
- Maintainer team
- Design decision discussions
- Beta testing of new features

---

## 🚀 Ready to Contribute?

1. **Star the repository** ⭐
2. **Run the metrics function** and share results
3. **Pick an issue** with `good-first-issue` label
4. **Submit your first PR**

Questions? Open a GitHub Discussion or issue.

---

*Every contribution makes pgGit better for the entire PostgreSQL community!*