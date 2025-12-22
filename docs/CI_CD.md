# CI/CD Workflows Documentation

## Overview

The pggit project uses GitHub Actions for continuous integration and deployment. The CI/CD pipeline is organized into multiple focused workflows that test different aspects of the system:

1. **Core Tests** (`tests.yml`) - PostgreSQL core functionality and feature modules
2. **E2E Tests** (`e2e-tests.yml`) - End-to-end test suite with multi-level execution
3. **Chaos Tests** (`chaos-tests.yml`) - Chaos engineering and regression testing
4. **Weekly Chaos** (`chaos-weekly.yml`) - Extended weekly chaos testing
5. **Security** (`security-tests.yml`, `security-scan.yml`) - Security scanning
6. **Build & Release** (`build.yml`, `release.yml`, `packages.yml`) - Build and deployment
7. **Validation** (`validate-workflows.yml`, `version-check.yml`) - Pipeline validation

## E2E Test Workflow

The E2E test workflow provides flexible testing at multiple levels, organized by capability area.

### Trigger Conditions

The workflow runs on:

**Automatic triggers:**
- Push to `main` or `develop` branches when E2E files change
- Pull requests to `main` when E2E files change
- Scheduled runs (via `workflow_dispatch`)

**File paths monitored:**
- `tests/e2e/**` - E2E test files
- `docs/e2e/**` - E2E documentation
- `sql/**` - Database code (affects test setup)
- `.github/workflows/e2e-tests.yml` - Workflow definition

### Test Levels

The workflow supports three test execution levels:

#### 1. Smoke Tests (Fast Validation)
- **Duration**: ~5-10 minutes
- **PostgreSQL**: Version 15
- **Scope**: Basic functionality without stress tests
- **Command**: `pytest tests/e2e/ -k "not stress and not load" -v`
- **Use case**: Pre-commit validation, quick feedback

#### 2. Full Tests (Standard Coverage)
- **Duration**: ~10-20 minutes
- **PostgreSQL**: Version 16
- **Scope**: Complete E2E test suite (78 tests)
- **Command**: `pytest tests/e2e/ -v`
- **Use case**: PR validation, merge gates

#### 3. Extended Tests (Comprehensive)
- **Duration**: ~15-30 minutes
- **PostgreSQL**: Version 17
- **Scope**: Full E2E + chaos tests (78 + 120 tests)
- **Command**: `pytest tests/e2e/ tests/chaos/ -v`
- **Use case**: Pre-release, main branch validation

### Test Organization

Tests are organized into 6 capability areas across 15 domain-specific modules:

**Branching Operations (2 modules, 9 tests)**
- Advanced branch hierarchies and operations
- Cross-branch consistency and isolation

**Data Management (3 modules, 19 tests)**
- Data integrity and constraint validation
- Edge cases and boundary conditions
- Multi-table consistency

**Deployment & Schema (2 modules, 8 tests)**
- Blue-green deployments and canary releases
- Schema evolution and rollback procedures

**System Resilience (2 modules, 9 tests)**
- Backup and recovery operations
- Cross-version compatibility

**Performance & Load (3 modules, 12 tests)**
- Performance regression detection
- Concurrent stress testing
- Resource utilization

**Advanced Features (3 modules, 14 tests)**
- ML-based conflict resolution
- Timeout and timing handling
- Multi-table transactions

### Matrix Strategy

The workflow uses a matrix build strategy to test across multiple configurations:

| Level | PostgreSQL | Purpose |
|---|---|---|
| Smoke | 15 | Fast feedback for every change |
| Full | 16 | Standard validation |
| Extended | 17 | Comprehensive testing with chaos |

### Running E2E Tests Locally

Run the same tests locally before pushing:

```bash
# Smoke tests (fast)
pytest tests/e2e/ -k "not stress and not load" -v

# Full suite
pytest tests/e2e/ -v

# Extended with chaos
pytest tests/e2e/ tests/chaos/ -v

# Specific capability area
pytest tests/e2e/test_branching_*.py -v

# With coverage
pytest tests/e2e/ --cov=src/pggit --cov-report=html -v
```

## Core Test Workflow

The core test workflow validates pgGit installation and feature modules across PostgreSQL versions 15, 16, and 17.

### Steps

1. **Environment Setup**
   - Checkout code
   - Start PostgreSQL service
   - Install PostgreSQL client

2. **pgGit Installation**
   - Install core schema from `sql/install.sql`
   - Install required feature modules
   - Install optional feature modules (with fallback)
   - Create test helper tables and functions

3. **Feature Testing**
   - Test configuration system
   - Test CQRS support
   - Test function versioning
   - Test migration integration
   - Test conflict resolution
   - Test deployment mode
   - Test emergency controls

4. **Test Summary**
   - Report results
   - Document tested features

## Chaos Test Workflow

The chaos test workflow validates system behavior under adverse conditions.

### Weekly Chaos Testing

Extended chaos testing runs weekly:

```
Schedule: Weekly on Mondays at 02:00 UTC
Scope: Full chaos test suite (120+ tests)
PostgreSQL: 16
Duration: 20-30 minutes
```

## Running Workflows Manually

Trigger any workflow manually:

```bash
# Using GitHub CLI
gh workflow run e2e-tests.yml \
  -f test_level=full

gh workflow run chaos-tests.yml

gh workflow run tests.yml
```

Or via GitHub web interface:
1. Navigate to Actions tab
2. Select workflow
3. Click "Run workflow"
4. Configure inputs if available
5. Click "Run workflow" button

## Monitoring Workflow Status

### GitHub Interface
- **Actions tab**: View all workflow runs
- **Commit status**: Check status badge on commits
- **PR checks**: See workflow results on pull requests

### CLI
```bash
# List recent workflow runs
gh run list --workflow e2e-tests.yml

# Watch workflow progress
gh run watch <RUN_ID>

# Get workflow logs
gh run view <RUN_ID> --log
```

### Badges
Add status badges to README:

```markdown
![E2E Tests](https://github.com/user/repo/workflows/E2E%20Tests/badge.svg)
![Tests](https://github.com/user/repo/workflows/pgGit%20Tests/badge.svg)
![Chaos Tests](https://github.com/user/repo/workflows/Chaos%20Tests/badge.svg)
```

## Troubleshooting

### Common Issues

**PostgreSQL connection timeout**
- Check if PostgreSQL service started
- Verify port 5432 is available
- Check PostgreSQL logs for errors

**Test failures**
- Review test output in workflow logs
- Run test locally with same parameters
- Check for environment-specific issues

**Workflow not triggering**
- Verify file paths match path filters
- Check branch configuration
- Ensure workflow file is valid YAML

### Debug Mode

Enable debug logging:

```yaml
env:
  DEBUG: true
  VERBOSE: true
```

Or set in workflow dispatch:
- Check "Enable debug logging" option

## Performance

### Expected Runtimes

| Workflow | Version | Duration |
|---|---|---|
| E2E Smoke | pg15 | 5-10m |
| E2E Full | pg16 | 10-20m |
| E2E Extended | pg17 | 15-30m |
| Core Tests | pg15-17 | 20-30m |
| Chaos Tests | pg16 | 20-30m |

### Optimization

- Use `path-filters` to run workflows only when relevant files change
- Matrix builds provide parallel testing across versions
- Smoke tests provide quick feedback without long-running stress tests

## Adding New Tests

When adding tests to the E2E suite:

1. **Create test file** in `tests/e2e/` following capability naming:
   - `test_<capability>_<description>.py`
   - Example: `test_branching_new_feature.py`

2. **Update documentation**:
   - Add test description to relevant capability doc in `docs/e2e/`
   - Update test count in overview

3. **Verify locally**:
   ```bash
   pytest tests/e2e/test_<capability>_<description>.py -v
   ```

4. **Commit and push**:
   - Workflow will automatically run
   - Monitor results in Actions tab

## Maintenance

### Quarterly Reviews

- **Update PostgreSQL versions** as new versions are released
- **Review test coverage** for any gaps
- **Optimize test execution** times
- **Update documentation** with any changes

### Health Checks

Regular checks to ensure CI/CD health:

```bash
# Verify all workflows are enabled
gh workflow list

# Check recent workflow runs
gh run list --limit 10

# Review workflow execution time trends
# (In GitHub interface: Actions > Workflows > Click workflow > Analytics)
```

## Documentation References

- [E2E Test Suite Overview](e2e/README.md)
- [E2E Running Tests Guide](e2e/RUNNING_TESTS.md)
- [Branching Operations Tests](e2e/branching.md)
- [Capability Area Guides](e2e/) - Individual guides for each capability

## Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [GitHub CLI Documentation](https://cli.github.com/manual)
- [Pytest Documentation](https://docs.pytest.org/)
- [PostgreSQL Service in Actions](https://docs.github.com/en/actions/using-containerized-services/creating-postgresql-service-containers)
