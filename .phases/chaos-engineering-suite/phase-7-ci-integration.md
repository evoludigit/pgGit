# Phase 7: CI Integration & Final Refinement

## Objective
Integrate chaos engineering tests into CI pipeline, establish pass/fail criteria, configure test scheduling, and refine test suite based on real-world findings.

## TDD Stage
GREENFIELD (CI/CD setup)

## Context
- **Previous phase**: Phase 6 (Schema Corruption) completed corruption/recovery tests
- **Current state**: Full chaos test suite exists, but not integrated into CI
- **Next phase**: Phase 8 (Documentation) will create comprehensive guide

## Files to Modify/Create

### 1. `.github/workflows/chaos-tests.yml` (created in Phase 1, now enhance)
Update CI workflow with:
- Test categorization (must-pass vs allowed-to-fail)
- Scheduled runs (weekly)
- Performance benchmarking
- Test result reporting

### 2. `pyproject.toml` (add test configuration)
Add pytest markers and chaos test configuration.

### 3. `tests/chaos/pytest.ini`
Pytest configuration specific to chaos tests.

### 4. `.github/workflows/chaos-weekly.yml`
Weekly comprehensive chaos testing workflow.

### 5. `tests/chaos/TESTING.md`
Testing guide for contributors.

## Implementation Steps

### Step 1: Update CI Workflow (`.github/workflows/chaos-tests.yml`)

```yaml
name: Chaos Engineering Tests

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  schedule:
    # Weekly on Sundays at 2 AM UTC
    - cron: '0 2 * * 0'
  workflow_dispatch:
    inputs:
      test_category:
        description: 'Test category to run'
        required: true
        default: 'all'
        type: choice
        options:
          - all
          - property
          - concurrent
          - transaction
          - resource
          - corruption

jobs:
  # Quick smoke test - must pass
  chaos-smoke:
    name: Chaos Smoke Tests (Must Pass)
    runs-on: ubuntu-latest
    continue-on-error: false  # Must pass

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

      - name: Run smoke tests
        env:
          PGHOST: localhost
          PGPORT: 5432
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: pggit_chaos_test
        run: |
          # Run only critical tests that MUST pass
          pytest tests/chaos/ -v \
            --tb=short \
            --timeout=60 \
            -m "chaos and not slow and not destructive" \
            --maxfail=5 \
            -k "not load and not crash and not disk" \
            --junit-xml=chaos-smoke-results-pg${{ matrix.postgres-version }}.xml

      - name: Upload smoke test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: chaos-smoke-results-pg${{ matrix.postgres-version }}
          path: chaos-smoke-results-pg${{ matrix.postgres-version }}.xml

  # Full chaos test suite - allowed to fail initially
  chaos-full:
    name: Full Chaos Test Suite (Can Fail)
    runs-on: ubuntu-latest
    continue-on-error: true  # Allowed to fail

    strategy:
      matrix:
        postgres-version: [15, 16, 17]
        test-category: [property, concurrent, transaction, resource, corruption]

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

      - name: Run chaos tests by category
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
            -m "${{ matrix.test-category }}" \
            --hypothesis-show-statistics \
            --maxfail=20 \
            --junit-xml=chaos-${{ matrix.test-category }}-pg${{ matrix.postgres-version }}.xml

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: chaos-${{ matrix.test-category }}-results-pg${{ matrix.postgres-version }}
          path: chaos-${{ matrix.test-category }}-pg${{ matrix.postgres-version }}.xml

  # Performance benchmarking
  chaos-performance:
    name: Performance Benchmarks
    runs-on: ubuntu-latest
    continue-on-error: true

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

      - name: Run performance tests
        env:
          PGHOST: localhost
          PGPORT: 5432
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: pggit_chaos_test
        run: |
          pytest tests/chaos/test_load_stress.py -v \
            --tb=short \
            --timeout=600 \
            --benchmark-only \
            --benchmark-json=chaos-benchmarks.json

      - name: Upload benchmark results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: chaos-performance-benchmarks
          path: chaos-benchmarks.json

  # Test result summary
  chaos-summary:
    name: Generate Test Summary
    runs-on: ubuntu-latest
    needs: [chaos-smoke, chaos-full, chaos-performance]
    if: always()

    steps:
      - uses: actions/checkout@v4

      - name: Download all test results
        uses: actions/download-artifact@v4
        with:
          path: test-results

      - name: Generate summary
        run: |
          echo "## Chaos Engineering Test Results" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY

          # Count test files
          find test-results -name "*.xml" -type f | wc -l | \
            xargs -I {} echo "📊 Total test result files: {}" >> $GITHUB_STEP_SUMMARY

          echo "" >> $GITHUB_STEP_SUMMARY
          echo "### Test Categories" >> $GITHUB_STEP_SUMMARY

          for category in property concurrent transaction resource corruption; do
            count=$(find test-results -name "*$category*.xml" -type f | wc -l)
            echo "- $category: $count result files" >> $GITHUB_STEP_SUMMARY
          done

          echo "" >> $GITHUB_STEP_SUMMARY
          echo "✅ Smoke tests must pass for PR merge" >> $GITHUB_STEP_SUMMARY
          echo "⚠️  Full chaos suite can fail (known issues being addressed)" >> $GITHUB_STEP_SUMMARY
```

### Step 2: Create Weekly Comprehensive Test Workflow (`.github/workflows/chaos-weekly.yml`)

```yaml
name: Weekly Chaos Engineering Tests

on:
  schedule:
    # Every Sunday at 3 AM UTC
    - cron: '0 3 * * 0'
  workflow_dispatch:

jobs:
  comprehensive-chaos:
    name: Comprehensive Chaos Tests
    runs-on: ubuntu-latest
    timeout-minutes: 120

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

      - name: Run ALL chaos tests (no limits)
        env:
          PGHOST: localhost
          PGPORT: 5432
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: pggit_chaos_test
        run: |
          pytest tests/chaos/ -v \
            --tb=long \
            --timeout=600 \
            -m chaos \
            --hypothesis-show-statistics \
            --hypothesis-seed=random \
            --maxfail=100 \
            --junit-xml=weekly-chaos-results-pg${{ matrix.postgres-version }}.xml \
            --html=weekly-chaos-report-pg${{ matrix.postgres-version }}.html \
            --self-contained-html

      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: weekly-chaos-pg${{ matrix.postgres-version }}
          path: |
            weekly-chaos-results-pg${{ matrix.postgres-version }}.xml
            weekly-chaos-report-pg${{ matrix.postgres-version }}.html

      - name: Create GitHub Issue if tests fail
        if: failure()
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `Weekly Chaos Tests Failed (PostgreSQL ${{ matrix.postgres-version }})`,
              body: `Weekly chaos engineering tests failed on PostgreSQL ${{ matrix.postgres-version }}.

              See [workflow run](${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}) for details.

              **Action Required**: Review failures and create issues for any new bugs discovered.`,
              labels: ['chaos-testing', 'test-failure', 'needs-triage']
            })
```

### Step 3: Add Pytest Configuration (`tests/chaos/pytest.ini`)

```ini
[pytest]
# Pytest configuration for chaos tests

# Markers
markers =
    chaos: mark test as chaos engineering test
    property: mark test as property-based test
    concurrent: mark test as concurrency test
    transaction: mark test as transaction test
    resource: mark test as resource exhaustion test
    corruption: mark test as corruption test
    recovery: mark test as recovery procedure test
    load: mark test as load/stress test
    migration: mark test as migration test
    slow: mark test as slow (>30s)
    destructive: mark test as potentially destructive
    skip: skip this test

# Test discovery
python_files = test_*.py
python_classes = Test*
python_functions = test_*

# Output
console_output_style = progress
log_cli = true
log_cli_level = INFO
log_cli_format = %(asctime)s [%(levelname)8s] %(message)s
log_cli_date_format = %Y-%m-%d %H:%M:%S

# Warnings
filterwarnings =
    error
    ignore::DeprecationWarning
    ignore::PendingDeprecationWarning

# Coverage (optional)
# addopts = --cov=pggit --cov-report=html --cov-report=term

# Timeouts
timeout = 300
timeout_method = thread

# Hypothesis
hypothesis_profile = default

[hypothesis:profiles]
default =
    max_examples = 50
    deadline = None
    print_blob = True

thorough =
    max_examples = 200
    deadline = None

quick =
    max_examples = 10
    deadline = 5000
```

### Step 4: Update pyproject.toml

```toml
# Add to existing pyproject.toml

[project.optional-dependencies]
chaos = [
    "hypothesis>=6.100.0",
    "pytest>=8.0.0",
    "pytest-asyncio>=0.23.0",
    "pytest-timeout>=2.2.0",
    "pytest-xdist>=3.5.0",
    "pytest-html>=4.1.0",  # For HTML reports
    "psutil>=5.9.0",
    "psycopg[binary,pool]>=3.1.0",
]

[tool.pytest.ini_options]
testpaths = ["tests"]
markers = [
    "chaos: chaos engineering tests",
    "property: property-based tests",
    "concurrent: concurrency tests",
    "transaction: transaction tests",
    "resource: resource exhaustion tests",
    "corruption: corruption tests",
    "recovery: recovery procedure tests",
    "load: load/stress tests",
    "migration: migration tests",
    "slow: slow tests (>30s)",
    "destructive: potentially destructive tests",
]
```

### Step 5: Create Testing Guide (`tests/chaos/TESTING.md`)

```markdown
# Chaos Engineering Testing Guide

## Quick Start

### Run all chaos tests
```bash
pytest tests/chaos/ -v -m chaos
```

### Run by category
```bash
pytest tests/chaos/ -v -m property        # Property-based tests
pytest tests/chaos/ -v -m concurrent      # Concurrency tests
pytest tests/chaos/ -v -m transaction     # Transaction tests
pytest tests/chaos/ -v -m resource        # Resource exhaustion
pytest tests/chaos/ -v -m corruption      # Corruption detection
```

### Run smoke tests (fast, must pass)
```bash
pytest tests/chaos/ -v -m "chaos and not slow and not destructive"
```

## Test Categories

### Must-Pass Tests (Smoke)
These tests MUST pass for PR approval:
- Basic property tests (non-slow)
- Simple concurrency tests (< 10 workers)
- Transaction rollback tests
- Basic resource tests

Run: `pytest tests/chaos/ -v -m "chaos and not slow and not destructive"`

### Can-Fail Tests (Full Suite)
These tests may fail while bugs are being fixed:
- High-concurrency tests (50+ workers)
- Load tests (100+ connections)
- Crash recovery tests
- Corruption tests

Run: `pytest tests/chaos/ -v -m chaos`

## Test Markers

| Marker | Description | Must Pass? |
|--------|-------------|------------|
| `chaos` | All chaos tests | No |
| `property` | Property-based with Hypothesis | Yes (simple ones) |
| `concurrent` | Concurrency/race conditions | Partially |
| `transaction` | Transaction failures | Yes |
| `resource` | Resource exhaustion | Partially |
| `corruption` | Corruption detection | No |
| `slow` | Takes >30 seconds | No |
| `destructive` | May require special setup | No |

## Running Tests Locally

### Prerequisites
```bash
# Install chaos dependencies
uv pip install -e ".[chaos]"

# Start PostgreSQL (if not running)
# Default connection: postgresql://postgres@localhost/pggit_chaos_test
```

### Basic run
```bash
pytest tests/chaos/ -v
```

### With Hypothesis statistics
```bash
pytest tests/chaos/ -v --hypothesis-show-statistics
```

### Parallel execution
```bash
pytest tests/chaos/ -v -n 4  # 4 workers
```

### Specific test file
```bash
pytest tests/chaos/test_concurrent_commits.py -v
```

### Specific test function
```bash
pytest tests/chaos/test_concurrent_commits.py::TestConcurrentCommits::test_concurrent_commits_same_branch -v
```

## CI Integration

### Automatic Runs
- **On PR**: Smoke tests only (fast, must pass)
- **On main push**: Full suite (can fail)
- **Weekly**: Comprehensive chaos tests + performance benchmarks

### Manual Trigger
```bash
# Via GitHub Actions UI: Actions → Chaos Engineering Tests → Run workflow
```

### View Results
- GitHub Actions → Workflow run → Artifacts
- Download test results (XML) and reports (HTML)

## Writing New Chaos Tests

### Example: Property-based test
```python
import pytest
from hypothesis import given, strategies as st

@pytest.mark.chaos
@pytest.mark.property
@given(value=st.integers(min_value=0, max_value=1000))
def test_property_example(sync_conn, value: int):
    # Test implementation
    assert value >= 0
```

### Example: Concurrency test
```python
import pytest
from concurrent.futures import ThreadPoolExecutor

@pytest.mark.chaos
@pytest.mark.concurrent
@pytest.mark.slow
def test_concurrent_example(db_connection_string):
    def worker(worker_id):
        # Worker implementation
        pass

    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = [executor.submit(worker, i) for i in range(10)]
        results = [f.result() for f in futures]

    # Assertions
```

### Example: Transaction test
```python
import pytest

@pytest.mark.chaos
@pytest.mark.transaction
def test_transaction_example(sync_conn, isolated_schema):
    try:
        sync_conn.execute("BEGIN")
        # Operations
        sync_conn.execute("INVALID SQL")  # Force error
        sync_conn.commit()
    except:
        sync_conn.rollback()

    # Verify complete rollback
```

## Debugging Failed Tests

### Get detailed output
```bash
pytest tests/chaos/test_name.py -v --tb=long --log-cli-level=DEBUG
```

### Run with PDB on failure
```bash
pytest tests/chaos/test_name.py -v --pdb
```

### Isolate failing test
```bash
pytest tests/chaos/test_name.py::TestClass::test_method -v
```

### Check Hypothesis shrinking
```bash
# Hypothesis automatically shrinks failing inputs
# Look for "Falsifying example" in output
```

## Performance Benchmarks

### Run benchmarks
```bash
pytest tests/chaos/test_load_stress.py -v --benchmark-only
```

### Save benchmark results
```bash
pytest tests/chaos/test_load_stress.py --benchmark-save=baseline
```

### Compare to baseline
```bash
pytest tests/chaos/test_load_stress.py --benchmark-compare=baseline
```

## Troubleshooting

### Tests hang
- Check timeout settings (default: 300s)
- Use `pytest --timeout=60` to reduce
- Look for deadlocks in PostgreSQL logs

### Connection errors
- Verify PostgreSQL is running
- Check connection string: `postgresql://postgres@localhost/pggit_chaos_test`
- Ensure pggit extension is installed

### Hypothesis fails
- Check Hypothesis version >= 6.100.0
- Review failed example in output
- Use `--hypothesis-seed=X` to reproduce

## Contributing

When adding chaos tests:
1. Use appropriate markers (`@pytest.mark.chaos`, etc.)
2. Include docstrings explaining what's tested
3. Add to appropriate category file
4. Update this guide if adding new patterns
5. Test locally before PR

## Resources

- [Hypothesis Documentation](https://hypothesis.readthedocs.io/)
- [Pytest Documentation](https://docs.pytest.org/)
- [PostgreSQL Concurrency](https://www.postgresql.org/docs/current/mvcc.html)
```

## Verification Commands

```bash
# Validate CI workflows
yamllint .github/workflows/chaos-*.yml

# Test pytest configuration
pytest tests/chaos/ --collect-only

# Run smoke tests locally
pytest tests/chaos/ -v -m "chaos and not slow and not destructive"

# Verify all markers work
pytest tests/chaos/ -v --markers
```

## Expected Outcome

### CI Should:
- ✅ Run smoke tests on every PR (must pass)
- ✅ Run full suite on main branch (can fail)
- ✅ Run weekly comprehensive tests
- ✅ Generate test reports and summaries
- ✅ Create GitHub issues on weekly failures

### Tests Should:
- ✅ Be categorized correctly (markers)
- ✅ Have clear pass/fail criteria
- ✅ Produce actionable results
- ✅ Run efficiently (timeouts, parallelization)

## Acceptance Criteria

- [ ] CI workflows updated with test categorization
- [ ] Weekly chaos test workflow created
- [ ] Pytest configuration added
- [ ] pyproject.toml updated with chaos dependencies
- [ ] Testing guide created (TESTING.md)
- [ ] All workflows pass YAML validation
- [ ] Smoke tests identified and pass locally
- [ ] Full suite runs (some failures expected)

## DO NOT

- ❌ Make all tests must-pass (gradual improvement)
- ❌ Skip CI integration (defeats purpose)
- ❌ Ignore test categorization (needed for phased rollout)
- ❌ Run destructive tests in CI (use skip markers)
- ❌ Forget timeout configuration (prevent hangs)

## Notes

**Gradual Improvement Strategy**:

1. **Week 1-2**: Smoke tests must pass (30% of chaos suite)
2. **Week 3-4**: Add transaction tests to must-pass (50%)
3. **Week 5-6**: Add simple concurrency tests (70%)
4. **Week 7-8**: Add resource tests (85%)
5. **Week 9+**: All non-destructive tests must pass (95%)

**Test Stability**:
- Property tests: Most stable (deterministic after fix)
- Transaction tests: Very stable (ACID guarantees)
- Concurrency tests: Moderate (timing-dependent)
- Resource tests: Less stable (environment-dependent)
- Corruption tests: Least stable (detection logic evolving)

**CI Performance**:
- Smoke tests: ~5 minutes
- Full suite (single category): ~15 minutes
- All categories: ~60 minutes
- Weekly comprehensive: ~120 minutes

**Next Steps**:
Phase 8 will create comprehensive documentation including chaos testing patterns, examples, and best practices.
