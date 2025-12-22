# Running E2E Tests - Complete Guide

## Quick Start

### Run All E2E Tests
```bash
cd /home/lionel/code/pggit
pytest tests/e2e/ -v
```

### Run Specific Category
```bash
# Branching tests
pytest tests/e2e/test_branching_*.py -v

# Data integrity tests
pytest tests/e2e/test_data_*.py tests/e2e/test_consistency_*.py -v

# Performance tests
pytest tests/e2e/test_performance_*.py tests/e2e/test_load_*.py -v
```

## Test Execution Levels

### Smoke Test (Fast, ~30 seconds)
```bash
pytest tests/e2e/ -k "not stress and not load" -v
```
Tests basic functionality without stress testing

### Full Test Suite (Standard, ~5-10 minutes)
```bash
pytest tests/e2e/ -v
```
Complete E2E test coverage including load tests

### With Coverage Report (~10-15 minutes)
```bash
pytest tests/e2e/ --cov=src/pggit --cov-report=html -v
```
Full coverage analysis with HTML report in `htmlcov/index.html`

### Extended Suite with Chaos Tests (~15-20 minutes)
```bash
pytest tests/e2e/ tests/chaos/ -v
```
E2E tests plus core functionality chaos tests

## Test Organization Commands

### By Capability Area

**Branching Operations**
```bash
pytest tests/e2e/test_branching_*.py -v
```

**Data Management**
```bash
pytest tests/e2e/test_data_*.py tests/e2e/test_consistency_*.py -v
```

**Deployment & Schema**
```bash
pytest tests/e2e/test_deployment_*.py tests/e2e/test_schema_*.py -v
```

**Performance & Load**
```bash
pytest tests/e2e/test_performance_*.py tests/e2e/test_load_*.py -v
```

**Reliability & Compatibility**
```bash
pytest tests/e2e/test_reliability_*.py tests/e2e/test_compatibility_*.py -v
```

**Advanced Features**
```bash
pytest tests/e2e/test_conflict_*.py tests/e2e/test_timing_*.py tests/e2e/test_transactions_*.py -v
```

### By Test File
```bash
pytest tests/e2e/test_branching_advanced_scenarios.py -v
pytest tests/e2e/test_deployment_strategies.py -v
pytest tests/e2e/test_performance_regression_detection.py -v
```

## Output and Verbosity Options

### Standard Output (Default)
```bash
pytest tests/e2e/ -v
```
Shows test name, pass/fail, execution time

### Detailed Output
```bash
pytest tests/e2e/ -vv
```
Includes assertion details and full tracebacks

### Very Detailed with Local Variables
```bash
pytest tests/e2e/ -vv --tb=long
```
Full traceback with local variable values

### Short Traceback (Less Verbose)
```bash
pytest tests/e2e/ -v --tb=short
```
Single-line traceback, good for many tests

### No Traceback (Pass/Fail Only)
```bash
pytest tests/e2e/ -q
```
Minimal output, just counts and summary

## Filtering and Selection

### Run Single Test
```bash
pytest tests/e2e/test_branching_advanced_scenarios.py::TestE2EAdvancedBranching::test_nested_branch_creation -v
```

### Run Tests Matching Pattern
```bash
# All tests with "branch" in name
pytest tests/e2e/ -k "branch" -v

# All tests with "performance" in name
pytest tests/e2e/ -k "performance" -v

# All tests NOT containing "stress"
pytest tests/e2e/ -k "not stress" -v
```

### Run Tests with Specific Marker
```bash
pytest tests/e2e/ -m "not slow" -v
```

## Parallel Execution

### Run Tests in Parallel (4 workers)
```bash
pytest tests/e2e/ -n 4 -v
```
Requires: `pip install pytest-xdist`

### Run Tests in Parallel (Auto-detect cores)
```bash
pytest tests/e2e/ -n auto -v
```

## Output Formats

### JSON Report
```bash
pytest tests/e2e/ -v --json-report --json-report-file=report.json
```

### JUnit XML (for CI systems)
```bash
pytest tests/e2e/ -v --junit-xml=results.xml
```

### HTML Report
```bash
pytest tests/e2e/ -v --html=report.html --self-contained-html
```

## Debugging Options

### Stop on First Failure
```bash
pytest tests/e2e/ -x
```
Useful for debugging failing tests

### Stop After N Failures
```bash
pytest tests/e2e/ --maxfail=3
```
Stop after 3 failures

### Run Last Failed Tests
```bash
pytest tests/e2e/ --lf
```
Reruns tests that failed in the last run

### Run Last Failed Tests Recursively
```bash
pytest tests/e2e/ --ff
```
Run last failed first, then other tests

### Drop into Debugger on Failure
```bash
pytest tests/e2e/ --pdb
```
Opens Python debugger on test failure

### Show Print Statements
```bash
pytest tests/e2e/ -v -s
```
Shows output from print() calls in tests

## Performance and Timing

### Show Slowest Tests
```bash
pytest tests/e2e/ -v --durations=10
```
Shows 10 slowest tests and their timing

### Fail if Slower Than Threshold
```bash
pytest tests/e2e/ --timeout=30
```
Requires: `pip install pytest-timeout`

### Measure Coverage and Performance
```bash
pytest tests/e2e/ --cov=src/pggit --cov-report=term-missing --durations=5
```

## Environment Variables

### Set Pytest Options via Environment
```bash
export PYTEST_ADDOPTS="-v --tb=short"
pytest tests/e2e/
```

### Database Connection
```bash
export DATABASE_URL="postgresql://user:pass@localhost/pggit"
pytest tests/e2e/ -v
```

### Custom Test Configuration
```bash
export PGGIT_TEST_TIMEOUT=60
export PGGIT_TEST_WORKERS=4
pytest tests/e2e/ -v
```

## Common Workflows

### Development (Fast Feedback)
```bash
pytest tests/e2e/ -x -v -s
```
Run until first failure, with output and verbose

### Pre-Commit (Quick Check)
```bash
pytest tests/e2e/ -k "not stress and not load" -q
```
Quick smoke test without stress tests

### Full CI Build
```bash
pytest tests/e2e/ tests/chaos/ --cov=src/pggit --junit-xml=results.xml -v
```
Complete test with coverage and CI reporting

### Performance Regression Check
```bash
pytest tests/e2e/test_performance_*.py -v --durations=10
```
Monitor performance regression

### Load Testing
```bash
pytest tests/e2e/test_load_*.py -v -s
```
Run load tests with output

## Troubleshooting

### Database Connection Errors
```bash
# Verify database is running
psql -d postgres -c "SELECT 1"

# Check pggit schema exists
psql -d postgres -c "\dt pggit.*"

# Run single test to see error
pytest tests/e2e/test_branching_advanced_scenarios.py::TestE2EAdvancedBranching::test_nested_branch_creation -vv
```

### Import Errors
```bash
# Verify pytest installation
pytest --version

# Check Python path
python -c "import sys; print(sys.path)"

# Reinstall requirements
pip install -r requirements-dev.txt
```

### Timeout Issues
```bash
# Increase timeout to 300 seconds
pytest tests/e2e/ --timeout=300 -v

# Disable timeout
pytest tests/e2e/ -p no:timeout -v
```

### Flaky Tests
```bash
# Run test multiple times
pytest tests/e2e/test_name.py --count=5 -v

# Run with retry on failure
pytest tests/e2e/ --reruns=3 --reruns-delay=1 -v
```

## CI/CD Integration

### GitHub Actions Example
```yaml
- name: Run E2E Tests
  run: |
    pytest tests/e2e/ \
      --junit-xml=results.xml \
      --cov=src/pggit \
      --cov-report=xml \
      -v
```

### GitLab CI Example
```yaml
e2e_tests:
  script:
    - pytest tests/e2e/ --junit-xml=results.xml -v
  artifacts:
    reports:
      junit: results.xml
```

## Performance Tips

1. **Use `--no-header`** to skip pytest header
2. **Use `-q`** for quiet mode in CI
3. **Use `-n auto`** for parallel execution
4. **Cache results** with `--cache-clear` to force fresh run
5. **Skip slow tests** with `-k "not slow"`

## References

- Pytest Documentation: https://docs.pytest.org/
- E2E Test Documentation: [README.md](./README.md)
- Capability Guides:
  - [Branching Operations](./branching.md)
  - [Data Management](./data.md)
  - [Performance & Load](./performance.md)
