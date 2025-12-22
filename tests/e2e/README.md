# End-to-End Integration Tests

## Overview

This directory contains end-to-end integration tests that validate pgGit functionality against a fresh PostgreSQL database running in Docker.

## Prerequisites

- Docker installed and running
- Python 3.10+
- `docker` Python package: `pip install docker`
- `psycopg` Python package: `pip install psycopg[binary]`
- PostgreSQL client tools (`psql`) installed locally

## Test Coverage

### Test Classes

1. **TestE2EBasicOperations**
   - Schema creation verification
   - Table existence checks
   - Initial branch creation

2. **TestE2EBranchOperations**
   - Creating new branches
   - Multiple branch management
   - Branch listing

3. **TestE2ETableVersioning**
   - Table creation and version tracking
   - Data insertion with version tracking
   - Multi-table operations

4. **TestE2ECommitOperations**
   - Commit creation
   - Version numbering (major.minor.patch)
   - Commit messages and metadata

5. **TestE2EDataBranching**
   - Data branch creation
   - Branch isolation
   - Copy-on-write semantics

6. **TestE2ETemporalOperations**
   - Temporal snapshot creation
   - Snapshot listing
   - Changelog recording
   - Time-travel functionality

7. **TestE2EMLOperations**
   - ML pattern table verification
   - Access pattern learning
   - ML optimization infrastructure

8. **TestE2EConflictResolution**
   - Conflict resolution table verification
   - Semantic conflict analysis
   - Conflict detection

9. **TestE2EFullWorkflow**
   - Complete branch creation workflow
   - Concurrent operations simulation
   - Data integrity verification

## Running Tests

### Run All E2E Tests

```bash
pytest tests/e2e/test_e2e_docker_integration.py -v
```

### Run Specific Test Class

```bash
pytest tests/e2e/test_e2e_docker_integration.py::TestE2EBranchOperations -v
```

### Run Specific Test

```bash
pytest tests/e2e/test_e2e_docker_integration.py::TestE2EBranchOperations::test_create_branch -v
```

### Run with Output

```bash
pytest tests/e2e/test_e2e_docker_integration.py -v -s
```

## How It Works

### Docker Container Lifecycle

1. **Setup Phase**:
   - Session-scoped fixture starts a PostgreSQL 16 container
   - Container maps port 5432 → 5433 locally
   - Waits for PostgreSQL to be ready (max 30 seconds)

2. **Installation Phase**:
   - Executes `sql/install.sql` to install pgGit extension
   - All functions, tables, indexes are created
   - Ready for test execution

3. **Test Execution**:
   - Each test gets a fresh database connection
   - Tests can create tables, insert data, run queries
   - Connection is closed after each test

4. **Teardown Phase**:
   - Container is removed after all tests complete
   - No cleanup needed on host system

### Connection Details

- **Host**: localhost
- **Port**: 5433 (mapped from container 5432)
- **Username**: postgres
- **Password**: postgres
- **Database**: pggit_test
- **Connection String**: `postgresql://postgres:postgres@localhost:5433/pggit_test`

## Test Data

Tests create their own tables and data:

- `public.test_data` - Basic versioning test
- `public.users` - User insertion test
- `public.products` - Product catalog
- `public.orders` - Order management
- `public.branch_test` - Data branching
- `public.isolated_table` - Branch isolation
- `public.workflow_test` - Full workflow
- `public.concurrent_test` - Concurrent operations
- `public.integrity_test` - Data integrity

All test tables are in the `public` schema and are isolated per test.

## Troubleshooting

### Docker Connection Issues

```bash
# Check if Docker daemon is running
docker ps

# Check container logs
docker logs pggit-e2e-test

# Manually connect to container
psql -h localhost -p 5433 -U postgres -d pggit_test
```

### PostgreSQL Connection Timeouts

- Increase retry count in `DockerPostgresSetup.start_container()`
- Check if port 5433 is already in use: `lsof -i :5433`
- Wait longer between container start and connection: `time.sleep(2)`

### psql Not Found

```bash
# Install PostgreSQL client tools
# macOS
brew install libpq

# Ubuntu/Debian
sudo apt-get install postgresql-client

# Add to PATH if needed
export PATH="/usr/local/opt/libpq/bin:$PATH"
```

### Docker Image Not Found

```bash
# Pull PostgreSQL image
docker pull postgres:16-alpine
```

## Test Statistics

- **Total Tests**: 25+
- **Test Classes**: 9
- **Fixtures**: 3 (session, installation, connection)
- **Estimated Runtime**: 30-60 seconds

## Continuous Integration

For CI/CD pipelines, ensure:

1. Docker is available in the CI environment
2. Port 5433 is not blocked by firewall
3. PostgreSQL image is pre-pulled: `docker pull postgres:16-alpine`
4. Set timeout for test execution to 2-3 minutes

Example CI configuration:

```yaml
# GitHub Actions
- name: Run E2E Tests
  run: |
    docker pull postgres:16-alpine
    pytest tests/e2e/ -v --tb=short --timeout=180
```

## Extending Tests

To add new E2E tests:

1. Add a new test method to an existing class or create a new class
2. Use the `db` fixture for database operations
3. Follow naming convention: `test_<operation>_<scenario>`
4. Include docstring explaining what is tested

Example:

```python
class TestE2ENewFeature:
    """Test new feature operations"""

    def test_new_feature_works(self, db, pggit_installed):
        """Test that new feature works end-to-end"""
        # Setup
        db.execute("CREATE TABLE public.new_feature (...)")

        # Execute
        result = db.execute_returning("SELECT ...")

        # Verify
        assert result is not None, "Feature failed"
```

## Cleanup

Tests automatically clean up containers:

- Docker container is removed after test session completes
- Test tables are isolated (can recreate same table in different tests)
- No manual cleanup required

Force cleanup if tests exit unexpectedly:

```bash
docker rm -f pggit-e2e-test
```

## Performance Notes

- **Container startup**: ~5 seconds
- **Installation**: ~3 seconds
- **Per-test connection**: ~100ms
- **Average test execution**: ~200-500ms

## Future Enhancements

- [ ] Docker Compose setup for multi-database testing
- [ ] Test against multiple PostgreSQL versions
- [ ] Performance benchmarking against large datasets
- [ ] Chaos engineering tests in Docker
- [ ] Multi-container test scenarios (replication, failover)
- [ ] Integration with monitoring/observability tools
