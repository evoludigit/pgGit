# Phase 1: Test Infrastructure & Framework Setup

## Objective
Set up the foundational testing infrastructure for chaos engineering, including pytest configuration, hypothesis integration, PostgreSQL test utilities, and the base framework for chaos injection.

## TDD Stage
GREENFIELD

## Context
- **Previous phase**: Phase 5 (Stabilization) completed with 9.8/10 quality, 100% CI pass rate
- **Current state**: Production-ready codebase with comprehensive test suite, but no chaos/property-based testing
- **Next phase**: Phase 2 (Property-Based Tests) will build on this infrastructure

## Files to Create

### 1. `tests/chaos/__init__.py`
Empty init file to make chaos tests a proper Python package.

### 2. `tests/chaos/conftest.py`
Pytest configuration and shared fixtures for chaos testing:
- Database connection pool fixtures
- Chaos injection utilities
- Performance monitoring helpers
- Test result tracking

### 3. `tests/chaos/fixtures.py`
Reusable test fixtures:
- Multi-connection pool setup
- Concurrent executor pools
- Timing injection utilities
- Database state snapshots

### 4. `tests/chaos/utils.py`
Utility functions:
- Random delay injection
- Transaction failure simulation
- Connection management
- Result validation helpers

### 5. `pyproject.toml` (modify existing)
Add chaos testing dependencies:
- `hypothesis` for property-based testing
- `pytest-asyncio` for async test support
- `pytest-timeout` for preventing hangs
- `pytest-xdist` for parallel test execution

### 6. `.github/workflows/chaos-tests.yml`
CI workflow for chaos tests (initially allowed to fail).

### 7. `tests/chaos/README.md`
Documentation for chaos testing framework and patterns.

## Implementation Steps

### Step 1: Install Dependencies

Add to `pyproject.toml` under `[project.optional-dependencies]`:

```toml
[project.optional-dependencies]
chaos = [
    "hypothesis>=6.100.0",
    "pytest-asyncio>=0.23.0",
    "pytest-timeout>=2.2.0",
    "pytest-xdist>=3.5.0",
    "psutil>=5.9.0",  # For resource monitoring
]
```

### Step 2: Create Base Configuration (`tests/chaos/conftest.py`)

```python
import pytest
import psycopg
from psycopg.rows import dict_row
from typing import Generator, AsyncGenerator
import asyncio
from contextlib import asynccontextmanager

# Pytest configuration
def pytest_configure(config):
    """Register custom markers for chaos tests."""
    config.addinivalue_line(
        "markers", "chaos: mark test as chaos engineering test"
    )
    config.addinivalue_line(
        "markers", "slow: mark test as slow (may take >30s)"
    )
    config.addinivalue_line(
        "markers", "concurrent: mark test as testing concurrency"
    )
    config.addinivalue_line(
        "markers", "destructive: mark test as potentially destructive"
    )


@pytest.fixture(scope="session")
def db_config() -> dict:
    """Database configuration for chaos tests."""
    return {
        "host": "localhost",
        "port": 5432,
        "dbname": "pggit_chaos_test",
        "user": "postgres",
        "password": None,
    }


@pytest.fixture(scope="session")
def db_connection_string(db_config: dict) -> str:
    """PostgreSQL connection string."""
    parts = [f"{k}={v}" for k, v in db_config.items() if v is not None]
    return " ".join(parts)


@pytest.fixture(scope="function")
def sync_conn(db_connection_string: str) -> Generator[psycopg.Connection, None, None]:
    """Synchronous database connection for a single test."""
    with psycopg.connect(db_connection_string, row_factory=dict_row) as conn:
        # Set up pggit extension
        conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")
        conn.commit()

        yield conn

        # Cleanup: rollback any uncommitted changes
        conn.rollback()


@pytest.fixture(scope="function")
async def async_conn(db_connection_string: str) -> AsyncGenerator[psycopg.AsyncConnection, None]:
    """Asynchronous database connection for a single test."""
    async with await psycopg.AsyncConnection.connect(
        db_connection_string,
        row_factory=dict_row
    ) as conn:
        # Set up pggit extension
        await conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")
        await conn.commit()

        yield conn

        # Cleanup
        await conn.rollback()


@pytest.fixture(scope="function")
def conn_pool(db_connection_string: str, request) -> Generator[list[psycopg.Connection], None, None]:
    """Pool of synchronous database connections for concurrent testing."""
    pool_size = getattr(request, "param", 10)  # Default 10 connections

    connections = []
    for _ in range(pool_size):
        conn = psycopg.connect(db_connection_string, row_factory=dict_row)
        conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")
        conn.commit()
        connections.append(conn)

    yield connections

    # Cleanup
    for conn in connections:
        conn.rollback()
        conn.close()


@pytest.fixture(scope="function")
def isolated_schema(sync_conn: psycopg.Connection) -> Generator[str, None, None]:
    """Create an isolated schema for a test, clean up afterward."""
    import uuid
    schema_name = f"chaos_test_{uuid.uuid4().hex[:8]}"

    sync_conn.execute(f"CREATE SCHEMA {schema_name}")
    sync_conn.execute(f"SET search_path TO {schema_name}, public")
    sync_conn.commit()

    try:
        yield schema_name
    finally:
        # Always cleanup, even if test fails
        try:
            sync_conn.execute("SET search_path TO public")
            sync_conn.execute(f"DROP SCHEMA IF EXISTS {schema_name} CASCADE")
            sync_conn.commit()
        except Exception as e:
            # Log cleanup failure but don't raise (cleanup is best-effort)
            print(f"Warning: Failed to cleanup schema {schema_name}: {e}")
```

### Step 3: Create Chaos Utilities (`tests/chaos/utils.py`)

```python
import asyncio
import random
from typing import Callable, Any, Awaitable
from contextlib import contextmanager
import time
import psycopg

class ChaosInjector:
    """Utility class for injecting chaos into database operations."""

    @staticmethod
    async def random_delay(min_ms: int = 0, max_ms: int = 100) -> None:
        """Inject a random delay to simulate network latency (async version)."""
        delay = random.uniform(min_ms / 1000, max_ms / 1000)
        await asyncio.sleep(delay)

    @staticmethod
    def random_delay_sync(min_ms: int = 0, max_ms: int = 100) -> None:
        """Inject a random delay to simulate network latency (sync version)."""
        delay = random.uniform(min_ms / 1000, max_ms / 1000)
        time.sleep(delay)

    @staticmethod
    @contextmanager
    def simulate_connection_failure(probability: float = 0.1):
        """Context manager that randomly fails connections."""
        if random.random() < probability:
            raise psycopg.OperationalError("Simulated connection failure")
        yield

    @staticmethod
    async def with_retry(
        func: Callable[..., Awaitable[Any]],
        max_attempts: int = 3,
        backoff: float = 0.1,
        *args,
        **kwargs
    ) -> Any:
        """Retry a function with exponential backoff."""
        last_exception = None

        for attempt in range(max_attempts):
            try:
                return await func(*args, **kwargs)
            except Exception as e:
                last_exception = e
                if attempt < max_attempts - 1:
                    await asyncio.sleep(backoff * (2 ** attempt))

        raise last_exception


class DatabaseStateSnapshot:
    """Capture and compare database state for validation."""

    def __init__(self, conn: psycopg.Connection):
        self.conn = conn
        self.snapshots = {}

    def capture(self, name: str, query: str) -> None:
        """Capture a snapshot of query results."""
        cursor = self.conn.execute(query)
        self.snapshots[name] = cursor.fetchall()

    def compare(self, name: str, query: str) -> tuple[bool, str]:
        """Compare current state to a snapshot."""
        if name not in self.snapshots:
            return False, f"No snapshot named '{name}'"

        cursor = self.conn.execute(query)
        current = cursor.fetchall()
        expected = self.snapshots[name]

        if current == expected:
            return True, "States match"
        else:
            return False, f"Expected {expected}, got {current}"


def measure_performance(func: Callable) -> Callable:
    """Decorator to measure function execution time."""
    async def async_wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = await func(*args, **kwargs)
        elapsed = time.perf_counter() - start
        print(f"{func.__name__} took {elapsed:.4f}s")
        return result

    def sync_wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = func(*args, **kwargs)
        elapsed = time.perf_counter() - start
        print(f"{func.__name__} took {elapsed:.4f}s")
        return result

    if asyncio.iscoroutinefunction(func):
        return async_wrapper
    else:
        return sync_wrapper
```

### Step 4: Create Fixtures Module (`tests/chaos/fixtures.py`)

```python
import pytest
import asyncio
from concurrent.futures import ThreadPoolExecutor
import psycopg
from typing import Callable, Any

@pytest.fixture
def concurrent_executor():
    """Thread pool executor for running concurrent database operations."""
    with ThreadPoolExecutor(max_workers=20) as executor:
        yield executor


@pytest.fixture
def async_task_pool():
    """Helper for running many async tasks concurrently."""
    async def run_concurrent_tasks(tasks: list[Callable], max_concurrent: int = 10):
        """Run tasks with limited concurrency."""
        semaphore = asyncio.Semaphore(max_concurrent)

        async def bounded_task(task):
            async with semaphore:
                return await task()

        return await asyncio.gather(*[bounded_task(t) for t in tasks])

    return run_concurrent_tasks


@pytest.fixture
def pg_sleep_injector(sync_conn: psycopg.Connection):
    """Inject delays using PostgreSQL's pg_sleep for realistic testing."""
    def inject_delay(seconds: float, query: str) -> Any:
        """Execute query with delay injected via pg_sleep."""
        sync_conn.execute(f"SELECT pg_sleep({seconds})")
        return sync_conn.execute(query)

    return inject_delay


@pytest.fixture
def transaction_monitor(sync_conn: psycopg.Connection):
    """Monitor active transactions and locks."""
    def get_active_transactions():
        cursor = sync_conn.execute("""
            SELECT
                pid,
                state,
                query,
                wait_event_type,
                wait_event
            FROM pg_stat_activity
            WHERE datname = current_database()
            AND pid != pg_backend_pid()
        """)
        return cursor.fetchall()

    def get_locks():
        cursor = sync_conn.execute("""
            SELECT
                locktype,
                relation::regclass,
                mode,
                granted,
                pid
            FROM pg_locks
            WHERE pid != pg_backend_pid()
        """)
        return cursor.fetchall()

    return {
        "transactions": get_active_transactions,
        "locks": get_locks,
    }
```

### Step 5: Create README (`tests/chaos/README.md`)

```markdown
# Chaos Engineering Test Suite

## Overview

This directory contains chaos engineering tests for pggit. These tests validate the system's behavior under adverse conditions, including:

- **Concurrency**: Race conditions, deadlocks, serialization failures
- **Failures**: Transaction rollbacks, connection losses, crashes
- **Resource exhaustion**: Connection pool limits, memory pressure, disk space
- **Data corruption**: Schema migration failures, partial commits

## Test Organization

```
tests/chaos/
├── conftest.py              # Pytest configuration and base fixtures
├── fixtures.py              # Reusable test fixtures
├── utils.py                 # Chaos injection utilities
├── test_concurrent_*.py     # Concurrency tests (Phase 3)
├── test_transaction_*.py    # Transaction failure tests (Phase 4)
├── test_resource_*.py       # Resource exhaustion tests (Phase 5)
└── test_corruption_*.py     # Schema corruption tests (Phase 6)
```

## Running Chaos Tests

### Run all chaos tests
```bash
pytest tests/chaos/ -v -m chaos
```

### Run specific test category
```bash
pytest tests/chaos/ -v -m concurrent
pytest tests/chaos/ -v -m destructive
```

### Run with parallelization
```bash
pytest tests/chaos/ -v -n 4  # 4 parallel workers
```

### Skip slow tests
```bash
pytest tests/chaos/ -v -m "not slow"
```

## Test Markers

- `@pytest.mark.chaos`: All chaos tests
- `@pytest.mark.slow`: Tests taking >30 seconds
- `@pytest.mark.concurrent`: Concurrency/race condition tests
- `@pytest.mark.destructive`: Tests that may leave artifacts

## Writing Chaos Tests

### Example: Property-based concurrency test

```python
import pytest
from hypothesis import given, strategies as st

@pytest.mark.chaos
@pytest.mark.concurrent
@given(num_workers=st.integers(min_value=2, max_value=20))
async def test_concurrent_commits(conn_pool, num_workers: int):
    """Test concurrent commits to same branch."""
    # Test implementation
    pass
```

### Example: Transaction failure test

```python
@pytest.mark.chaos
async def test_rollback_on_error(async_conn):
    """Test that errors trigger complete rollback."""
    # Setup
    await async_conn.execute("BEGIN")

    # Inject failure
    with pytest.raises(psycopg.Error):
        await async_conn.execute("INVALID SQL")

    # Verify rollback
    await async_conn.rollback()
    # Assertions
```

## CI Integration

Chaos tests run in a separate CI job that is allowed to fail initially:

```yaml
# .github/workflows/chaos-tests.yml
test-chaos:
  continue-on-error: true  # Initially allowed to fail
```

As bugs are fixed, tests are moved from "allowed to fail" to "must pass".
```

### Step 6: Create CI Workflow (`.github/workflows/chaos-tests.yml`)

```yaml
name: Chaos Engineering Tests

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  schedule:
    # Run chaos tests weekly on Sundays at 2 AM
    - cron: '0 2 * * 0'
  workflow_dispatch:  # Allow manual trigger

jobs:
  # Quick smoke tests - MUST pass for PR merge
  chaos-smoke:
    name: Chaos Smoke Tests (Must Pass)
    runs-on: ubuntu-latest
    continue-on-error: false  # MUST pass

    services:
      postgres:
        image: postgres:17
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: pggit_chaos_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install uv
          uv pip install --system -e ".[chaos]"

      - name: Install pggit extension
        run: |
          sudo apt-get update
          sudo apt-get install -y postgresql-server-dev-17
          make
          sudo make install

      - name: Run smoke tests
        env:
          PGHOST: localhost
          PGPORT: 5432
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: pggit_chaos_test
        run: |
          # Only run fast, non-destructive tests
          pytest tests/chaos/ -v \
            --tb=short \
            --timeout=60 \
            -m "chaos and not slow and not destructive" \
            --maxfail=5 \
            --junit-xml=chaos-smoke-results.xml

      - name: Upload smoke test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: chaos-smoke-results
          path: chaos-smoke-results.xml

  # Full chaos test suite - allowed to fail initially
  chaos-full:
    name: Full Chaos Tests (Can Fail)
    runs-on: ubuntu-latest
    continue-on-error: true  # Initially allowed to fail
    needs: chaos-smoke  # Only run if smoke tests pass

    strategy:
      matrix:
        postgres-version: [15, 16, 17]

    services:
      postgres:
        image: postgres:${{ matrix.postgres-version }}
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: pggit_chaos_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install uv
          uv pip install --system -e ".[chaos]"

      - name: Install pggit extension
        run: |
          sudo apt-get update
          sudo apt-get install -y postgresql-server-dev-${{ matrix.postgres-version }}
          make
          sudo make install

      - name: Run chaos tests
        env:
          PGHOST: localhost
          PGPORT: 5432
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: pggit_chaos_test
        run: |
          pytest tests/chaos/ -v \
            --tb=short \
            --timeout=300 \
            -m chaos \
            --maxfail=10 \
            --junit-xml=chaos-test-results-pg${{ matrix.postgres-version }}.xml

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: chaos-test-results-pg${{ matrix.postgres-version }}
          path: chaos-test-results-pg${{ matrix.postgres-version }}.xml

      - name: Generate test report
        if: always()
        run: |
          echo "## Chaos Test Results (PostgreSQL ${{ matrix.postgres-version }})" >> $GITHUB_STEP_SUMMARY
          pytest tests/chaos/ --collect-only -q -m chaos >> $GITHUB_STEP_SUMMARY || true
```

## Verification Commands

```bash
# Step 1: Create test database
createdb pggit_chaos_test
psql pggit_chaos_test -c "CREATE EXTENSION IF NOT EXISTS pggit"

# Step 2: Create uv environment and install dependencies
uv venv /tmp/chaos-test-env
source /tmp/chaos-test-env/bin/activate
uv pip install -e ".[chaos]"

# Step 3: Verify pytest can discover chaos tests
pytest tests/chaos/ --collect-only

# Step 4: Test fixture imports
python -c "from tests.chaos.conftest import db_config; print('✅ Fixtures importable')"

# Step 5: Test database connection
python -c "
import psycopg
conn = psycopg.connect('dbname=pggit_chaos_test')
conn.execute('SELECT 1')
print('✅ Database connection works')
"

# Step 6: Verify CI workflow syntax
yamllint .github/workflows/chaos-tests.yml

# Step 7: Run a simple test to verify infrastructure
pytest tests/chaos/conftest.py --doctest-modules -v
```

### Example: Using conn_pool with parametrization

```python
# In your test file
import pytest

@pytest.mark.parametrize("conn_pool", [5, 10, 20], indirect=True)
def test_with_custom_pool_size(conn_pool):
    """Test with different connection pool sizes."""
    assert len(conn_pool) in [5, 10, 20]

    # Use connections
    for conn in conn_pool:
        cursor = conn.execute("SELECT 1")
        assert cursor.fetchone()[0] == 1

# Default pool size (10 connections)
def test_with_default_pool(conn_pool):
    """Test with default pool size."""
    assert len(conn_pool) == 10
```

## Expected Outcome

### Directory Structure Should Be:
```
tests/chaos/
├── __init__.py           # Empty package marker
├── conftest.py          # Pytest config (280 lines)
├── fixtures.py          # Test fixtures (90 lines)
├── utils.py             # Chaos utilities (120 lines)
└── README.md            # Documentation (150 lines)

.github/workflows/
└── chaos-tests.yml      # CI workflow (70 lines)
```

### Tests Should:
- ✅ pytest can discover the chaos test package
- ✅ Fixtures are available to tests
- ✅ Database connections work in test environment
- ✅ CI workflow is valid YAML
- ✅ No actual chaos tests yet (that's Phase 2+)

### Code Should:
- ✅ Follow Python 3.10+ type annotations (`X | None` not `Optional[X]`)
- ✅ Use `psycopg` (psycopg3) not psycopg2
- ✅ Be well-documented with docstrings
- ✅ Include type hints for all public functions

## Acceptance Criteria

- [ ] All files created in correct locations
- [ ] Dependencies added to `pyproject.toml`
- [ ] Pytest can collect (but not run) chaos tests: `pytest tests/chaos/ --collect-only`
- [ ] Fixtures can be imported: `from tests.chaos.conftest import db_config`
- [ ] CI workflow passes YAML validation
- [ ] README is comprehensive and clear
- [ ] All code uses modern Python type hints

## DO NOT

- ❌ Write actual chaos tests yet (save for Phase 2+)
- ❌ Use `typing.Optional` or `typing.List` (use `X | None` and `list[X]`)
- ❌ Use psycopg2 (must use psycopg3)
- ❌ Create database fixtures that don't clean up
- ❌ Add dependencies without specifying minimum versions
- ❌ Skip docstrings or type hints

## Notes

**Testing Database Setup**: The chaos tests use a dedicated database (`pggit_chaos_test`) to avoid interfering with development or production databases. Each test gets isolated schema or fresh connections to ensure test independence.

**Fixture Scope Strategy**:
- `session`: Database config (immutable)
- `function`: Connections and schemas (isolated per test)
- Each test is independent with automatic cleanup

**Why `psycopg` (psycopg3)?**:
- Modern async/await support
- Better performance
- Active development
- Required by project standards

**CI Strategy**: The chaos-tests workflow initially runs with `continue-on-error: true` to allow gradual bug fixing. As we gain confidence, this will be changed to `continue-on-error: false`.
