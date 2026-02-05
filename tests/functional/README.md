# pgGit Functional Tests

Comprehensive functional testing suite for pgGit, validating that each module's functionality works correctly under realistic database conditions.

## Overview

- **345+ tests** across 7 advanced pgGit modules
- **Transaction-based isolation** for clean test state
- **Automatic cleanup** via ROLLBACK
- **Reusable test builders** to prevent duplication
- **Phase-based implementation** starting with Configuration System

## Phase 1: Configuration System ✅

Tests for deployment mode lifecycle, tracking configuration, pause/resume functionality.

**Files:**
- `conftest.py` - Pytest fixtures and database configuration
- `base_test_case.py` - Base test class with helper methods
- `test_configuration_system.py` - 45+ tests for configuration module
- `fixtures/test_data_builders.py` - Reusable test data factories

**Test Count:** 45-50 tests (3 test classes)

## Running Tests

### Install Dependencies

```bash
pip install pytest psycopg[binary]
```

### Run All Functional Tests

```bash
pytest tests/functional/ -v
```

### Run Configuration System Tests Only

```bash
pytest tests/functional/test_configuration_system.py -v
```

### Run Specific Test Class

```bash
pytest tests/functional/test_configuration_system.py::TestConfigurationSystemBasic -v
```

### Run Specific Test

```bash
pytest tests/functional/test_configuration_system.py::TestConfigurationSystemBasic::test_begin_deployment_returns_uuid -v
```

### Show Test Output

```bash
pytest tests/functional/test_configuration_system.py -v -s
```

## Test Structure

### Transaction Management

Each test runs in its own transaction that's automatically rolled back:

```python
def test_something(db_transaction):
    # Test code here
    # Database changes are automatically rolled back after test
```

Benefits:
- **Isolation**: Tests don't affect each other
- **Speed**: No expensive DELETE/DROP operations
- **Cleanup**: Automatic, no manual teardown needed
- **Debugging**: Full transaction state available if test fails

### Using Test Builders

Test builders provide reusable factories for creating test data:

```python
def test_configuration(db_transaction):
    builder = ConfigurationTestBuilder(db_transaction)

    # Create test scenario
    scenario = builder.setup_deployment_scenario()

    # scenario contains:
    # - schema: test schema name
    # - table: full table name
    # - rows: list of inserted row IDs
```

### Custom Assertions

Base test class provides assertions:

```python
def test_something(db_transaction):
    test = FunctionalTestCase()

    # Assert table exists
    test.assert_table_exists(db_transaction, "public", "users")

    # Assert record count
    test.assert_record_count(db_transaction, "public.users", 100)

    # Assert value exists
    test.assert_value_exists(db_transaction, "public.users", "username", "alice")

    # Assert UUID valid
    test.assert_uuid_valid(some_uuid)
```

## Test Classes

### TestConfigurationSystemBasic
Tests core functionality:
- `begin_deployment` returns UUID
- `begin_deployment` creates records
- `in_deployment_mode` state transitions
- `end_deployment` closes deployment
- Error handling (begin twice, end without begin)

**8-10 tests**

### TestConfigurationSystemTracking
Tests tracking configuration:
- Single/multiple schema tracking
- Ignore schema lists
- Empty/non-existent schemas
- Configuration persistence
- Overwriting configuration

**8-10 tests**

### TestConfigurationSystemPauseResume
Tests pause/resume:
- `pause_tracking` stops logging
- `resume_tracking` resumes logging
- Multiple pause/resume cycles
- Duration-based pause

**6-8 tests**

### TestConfigurationSystemEdgeCases
Tests edge cases:
- NULL deployment names
- Very long names (500+ chars)
- Special characters in names
- Concurrent deployments (single connection)
- Timestamps recorded correctly

**8-10 tests**

### TestConfigurationSystemIntegration
Integration tests:
- Deployment with schema creation
- Full deployment lifecycle
- Multiple sequential deployments
- Complex workflows

**8-10 tests**

## Database Setup

Tests assume:
1. PostgreSQL running locally (configurable via env vars)
2. `pggit` extension installed via `sql/install.sql`
3. User with access to create schemas/tables

### Environment Variables

```bash
PGHOST=localhost       # PostgreSQL host
PGPORT=5432          # PostgreSQL port
PGUSER=postgres      # PostgreSQL user
PGPASSWORD=          # PostgreSQL password (optional)
PGDATABASE=postgres  # Default database
```

### Setup Example

```bash
# Install pggit extension
cd /home/lionel/code/pggit
psql -f sql/install.sql

# Run functional tests
pytest tests/functional/ -v
```

## Architecture

### conftest.py
- Database connection fixtures
- Transaction management
- Custom assertions (execute_sql, assert_table_exists, etc.)
- Test database setup/cleanup

### base_test_case.py
- `FunctionalTestCase` base class
- Helper methods for SQL execution
- Custom assertions (assert_value_exists, assert_uuid_valid, etc.)
- Table creation helpers
- Record value retrieval

### test_data_builders.py
- `BaseTestBuilder` - Common operations
- `ConfigurationTestBuilder` - Configuration-specific helpers
- Future: CQRS, FunctionVersioning, Migration builders

### test_configuration_system.py
- 4-5 test classes
- 45-50 tests total
- Complete coverage of configuration module

## Extending Tests

### Add New Test Class

```python
class TestConfigurationSystemNewFeature(FunctionalTestCase):
    """Tests for new feature"""

    def test_new_functionality(self, db_transaction):
        builder = ConfigurationTestBuilder(db_transaction)

        # Use helpers
        schema = builder.create_schema("test_schema")

        # Make assertions
        self.assert_table_exists(db_transaction, "public", "some_table")
```

### Add to Test Builder

```python
class ConfigurationTestBuilder(BaseTestBuilder):

    def new_helper_method(self) -> dict:
        """Create test scenario for new feature"""
        # Implementation
        return {"schema": schema, ...}
```

## Troubleshooting

### Connection Refused
```
Error: psycopg: cannot connect to server
```
Ensure PostgreSQL is running:
```bash
psql -c "SELECT 1"
```

### pggit Schema Not Found
```
Error: pggit schema not found
```
Install extension:
```bash
cd /home/lionel/code/pggit
psql -f sql/install.sql
```

### Permission Denied
```
Error: permission denied for schema public
```
Ensure user has proper permissions:
```bash
psql -c "GRANT ALL PRIVILEGES ON DATABASE postgres TO postgres"
```

### Test Hangs
If a test hangs (likely from locks):
- Statement timeout set to 30 seconds (see conftest.py)
- Check for long-running operations
- Verify pggit functions don't have infinite loops

## Future Phases

- **Phase 2**: CQRS Support (40-45 tests)
- **Phase 3**: Function Versioning (45-50 tests)
- **Phase 4**: Migration Integration (50-55 tests)
- **Phase 5**: Conflict Resolution (40-45 tests)
- **Phase 6**: Advanced AI Features (45-50 tests)
- **Phase 7**: Zero-Downtime Deployment (60-65 tests)

## Performance

- **Phase 1 Run Time**: ~10-30 seconds (45-50 tests)
- **Full Suite Run Time**: ~5-10 minutes (345+ tests)

Slow tests can be excluded:
```bash
pytest tests/functional/ -v -m "not slow"
```

## Contributing

When adding tests:
1. Inherit from `FunctionalTestCase`
2. Use test builders for common setup
3. One assertion per test preferred (simple & clear)
4. Document edge cases thoroughly
5. Keep tests independent (no setup from other tests)

## References

- pytest: https://docs.pytest.org/
- psycopg3: https://www.psycopg.org/psycopg3/docs/
- pgGit: https://github.com/anthropics/pggit
