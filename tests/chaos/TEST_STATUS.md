# Chaos Test Status & Known Issues

## Overview

This document tracks the status of chaos engineering tests for pgGit. Chaos tests are **designed to find edge cases and failures** - many failures are expected and intentional during development.

**Last Updated**: 2025-12-31

---

## Test Classification

### ✅ MUST PASS - Smoke Tests

These tests **MUST pass** for PR merge. They validate core functionality under light chaos conditions.

**Filter**: `pytest -m "chaos and not slow and not destructive"`

**Status**: 61 smoke tests selected
- **Pass Rate Target**: 100% (enforced in CI)
- **Current Status**: ✅ Passing (as of 2025-12-31)
- **CI Enforcement**: `continue-on-error: false` in `.github/workflows/chaos-tests.yml`

**Categories**:
- Basic property tests (commit message preservation, Trinity ID uniqueness)
- Simple concurrency tests (5-20 workers)
- Transaction rollback correctness
- Constraint violation handling
- Connection recovery (small scale)

### ⚠️ CAN FAIL - Full Chaos Suite

These tests **can fail** during development. They explore extreme conditions and edge cases.

**Filter**: `pytest -m chaos` (all tests)

**Status**: 75 total tests collected
- **Pass Rate Target**: Progressive improvement (currently 88% per health assessment)
- **Current Status**: ⚠️ 16 tests failing (expected during development)
- **CI Enforcement**: `continue-on-error: true` in `.github/workflows/chaos-tests.yml`

**Categories**:
- Property-based tests with wide input ranges
- High concurrency tests (50+ workers)
- Resource exhaustion tests
- Corruption detection tests
- Migration failure scenarios

---

## Known Test Failures

### Property-Based Tests

**Status**: Partial failures expected

| Test | Status | Reason | Priority | Issue |
|------|--------|--------|----------|-------|
| TBD | 🔍 Needs Investigation | - | - | - |

**Common Reasons**:
- Hypothesis finding edge cases (e.g., unicode edge cases, max length strings)
- Performance degradation at scale
- PostgreSQL version-specific behavior differences

**Next Steps**:
- Run full suite and capture specific failing test names
- Classify each failure as: bug, performance limit, or acceptable edge case
- Create GitHub issues for bugs
- Document acceptable failures

### Concurrency Tests

**Status**: High concurrency scenarios may fail

| Test | Status | Reason | Priority | Issue |
|------|--------|--------|----------|-------|
| TBD | 🔍 Needs Investigation | - | - | - |

**Common Reasons**:
- Deadlock detection (may be acceptable for extreme concurrency)
- Serialization failures (expected under high contention)
- Connection pool exhaustion (resource limit)

**Next Steps**:
- Determine acceptable concurrency limits
- Document expected behavior under extreme load
- Add retry logic where appropriate

### Transaction & Rollback Tests

**Status**: Should all pass

| Test | Status | Reason | Priority | Issue |
|------|--------|--------|----------|-------|
| All tests | ✅ Expected to pass | ACID guarantees | High | - |

**Note**: If any transaction tests fail, these are **critical bugs** and should be fixed immediately.

### Resource Exhaustion Tests

**Status**: Many expected to fail (by design)

| Test | Status | Reason | Priority | Issue |
|------|--------|--------|----------|-------|
| Connection pool exhaustion | ⚠️ Expected to fail | Tests limit behavior | Low | - |
| Memory pressure | ⚠️ Expected to fail | Tests degradation | Low | - |
| Disk space limits | ⚠️ Expected to fail | Tests error handling | Low | - |

**Purpose**: These tests verify **graceful degradation** under extreme resource constraints. Failures indicate correct error handling.

**Next Steps**:
- Verify failures produce appropriate error messages
- Ensure no data corruption occurs
- Document resource limits in operations guide

### Corruption Detection Tests

**Status**: Should detect corruption (failures = bugs not found)

| Test | Status | Reason | Priority | Issue |
|------|--------|--------|----------|-------|
| TBD | 🔍 Needs Investigation | - | - | - |

**Purpose**: These tests intentionally corrupt data to verify detection mechanisms.

**Next Steps**:
- Run full suite
- Verify all corruption scenarios are detected
- Add recovery procedures for detected corruption

---

## Test Execution Guide

### Quick Smoke Test (Local Development)

```bash
# Fast validation before PR
pytest tests/chaos/ -v -m "chaos and not slow and not destructive"

# Expected: 100% pass rate
# Duration: ~2-5 minutes
```

### Full Chaos Suite (Comprehensive Testing)

```bash
# Run all chaos tests
pytest tests/chaos/ -v -m chaos

# Expected: 85-95% pass rate (improving)
# Duration: ~60 minutes
```

### Category-Specific Testing

```bash
# Property-based tests
pytest tests/chaos/ -v -m property

# Concurrency tests
pytest tests/chaos/ -v -m concurrent

# Transaction tests (must all pass)
pytest tests/chaos/ -v -m transaction

# Resource exhaustion (many expected to fail)
pytest tests/chaos/ -v -m resource

# Corruption detection
pytest tests/chaos/ -v -m corruption
```

### With Hypothesis Statistics

```bash
# See detailed Hypothesis shrinking and example generation
pytest tests/chaos/ -v -m property --hypothesis-show-statistics
```

---

## CI/CD Integration

### Pull Request Gate

**Workflow**: `.github/workflows/chaos-tests.yml` → `chaos-smoke` job

```yaml
continue-on-error: false  # MUST pass for PR merge
```

**Tests**: Smoke tests only (`-m "chaos and not slow and not destructive"`)

**Action on Failure**: PR cannot merge until fixed

### Main Branch Testing

**Workflow**: `.github/workflows/chaos-tests.yml` → `chaos-full` job

```yaml
continue-on-error: true  # Can fail (known issues)
```

**Tests**: Full chaos suite (5 categories × 3 PostgreSQL versions = 15 jobs)

**Action on Failure**: No blocking, but creates visibility

### Weekly Comprehensive Run

**Workflow**: `.github/workflows/chaos-weekly.yml`

**Schedule**: Sunday 2 AM UTC

**Tests**: Complete suite across all PostgreSQL versions (15, 16, 17)

**Action on Failure**: Create GitHub issue for new regressions

---

## Progress Tracking

### Conversion: Failing → Passing

As bugs are fixed, move tests from "allowed to fail" to "must pass":

#### Phase 1: Foundation (Current)
- ✅ Smoke tests: 100% pass rate
- ⚠️ Full suite: 88% pass rate (16 failures)

#### Phase 2: Transaction Guarantees
- **Goal**: All transaction tests pass (100%)
- **Timeline**: Q1 2026
- **Tests**: `pytest -m transaction`

#### Phase 3: Concurrency Hardening
- **Goal**: All concurrency tests pass up to 50 workers
- **Timeline**: Q2 2026
- **Tests**: `pytest -m concurrent`

#### Phase 4: Resource Limits
- **Goal**: Graceful degradation documented and tested
- **Timeline**: Q3 2026
- **Tests**: `pytest -m resource`

#### Phase 5: Corruption Detection
- **Goal**: All corruption scenarios detected
- **Timeline**: Q4 2026
- **Tests**: `pytest -m corruption`

---

## Investigation Tasks

### Immediate (This Week)

- [ ] Run full chaos suite and capture all failing test names
- [ ] Classify each failure:
  - 🐛 Bug (needs fix)
  - 📊 Performance limit (document threshold)
  - ✅ Acceptable edge case (update test or mark as expected)
- [ ] Create GitHub issues for all bugs
- [ ] Update this document with specific failing tests

### Short-Term (This Month)

- [ ] Fix all critical transaction test failures
- [ ] Document acceptable concurrency limits
- [ ] Add retry logic for known-flaky tests
- [ ] Set up failure trend tracking (% pass rate over time)

### Long-Term (This Quarter)

- [ ] Achieve 95% pass rate on full suite
- [ ] Move resource tests to "must pass" category (with documented limits)
- [ ] Add new chaos scenarios based on production incidents
- [ ] Create chaos test dashboard (Grafana/Prometheus)

---

## Hypothesis Shrinking Examples

When Hypothesis finds a failure, it shrinks to minimal example:

```python
# Example output:
Falsifying example: test_commit_message_preserved(msg='\\x00')
# Found: Null byte in commit message causes corruption

Falsifying example: test_concurrent_commits(num_workers=37)
# Found: Deadlock at exactly 37 concurrent workers
```

**Action Items**:
1. Reproduce with seed: `pytest --hypothesis-seed=12345`
2. Debug minimal failing case
3. Fix bug or document limit
4. Re-run to verify fix

---

## Metrics & Trends

Track chaos test effectiveness over time:

| Metric | Target | Current | Trend |
|--------|--------|---------|-------|
| Smoke test pass rate | 100% | 100% | ✅ Stable |
| Full suite pass rate | 95% | 88% | 📈 Improving |
| Bugs found per 100 tests | 5+ | TBD | - |
| Avg. Hypothesis shrink iterations | <20 | TBD | - |
| Time to run full suite | <60 min | ~60 min | ✅ On target |

**Measurement Frequency**: Weekly (automated via chaos-weekly workflow)

---

## Contributing

### When Adding New Chaos Tests

1. **Choose category**: property, concurrent, transaction, resource, or corruption
2. **Add to appropriate file**: `test_<category>_<scenario>.py`
3. **Mark appropriately**:
   ```python
   @pytest.mark.chaos
   @pytest.mark.property  # or concurrent, transaction, etc.
   @pytest.mark.slow     # if >30 seconds
   @pytest.mark.destructive  # if needs special setup
   ```
4. **Document expected behavior** in docstring
5. **Test locally** before PR
6. **Update this document** if adding new failure categories

### When Fixing Chaos Test Failures

1. **Reproduce locally**: Use `--hypothesis-seed` for property tests
2. **Classify failure**: Bug vs. acceptable edge case
3. **Fix or document**: Either fix bug or update test to expect behavior
4. **Verify fix**: Run test 10+ times to ensure stability
5. **Update this document**: Move from "failing" to "passing" section
6. **Consider moving to smoke tests**: If critical, add to smoke suite

---

## Troubleshooting

### "Test failed with Hypothesis health check"

**Cause**: Function-scoped fixtures creating/destroying resources repeatedly

**Solution**: Use `@settings(suppress_health_check=[HealthCheck.function_scoped_fixture])`

### "Test timeout after 300 seconds"

**Cause**: Deadlock or infinite loop in test

**Solution**: Check `pg_stat_activity` and `pg_locks` for blocking queries

### "Connection pool exhausted"

**Cause**: Test not cleaning up connections properly

**Solution**: Use `conn_pool` fixture with proper cleanup, or reduce `max_workers`

### "Flaky test (sometimes passes, sometimes fails)"

**Cause**: Race condition or timing dependency

**Solution**:
- Add explicit synchronization (locks, barriers)
- Use `--hypothesis-seed` to reproduce
- Report as bug (flaky tests mask real issues)

---

## Related Documentation

- **CHAOS_ENGINEERING.md**: High-level overview and philosophy
- **TESTING.md**: Comprehensive testing guide
- **README.md**: Quick reference and examples
- **PATTERNS.md**: Common test patterns (TODO: create this)
- **TROUBLESHOOTING.md**: Common issues and solutions

---

## Notes

### Intentional Failures

Some tests are **designed to fail** to verify error handling:

- Resource exhaustion tests (should gracefully error)
- Corruption detection tests (should detect and report corruption)
- Constraint violation tests (should rollback cleanly)

These are **not bugs** - they verify that pgGit handles failures correctly.

### Acceptable Edge Cases

Some failures at extreme values may be acceptable:

- Concurrency limits (e.g., >100 workers may deadlock - document limit)
- String length limits (e.g., >1MB commit messages may fail - enforce limit)
- Unicode edge cases (e.g., surrogate pairs may need special handling)

**Decision**: For each edge case, choose:
1. **Fix**: Handle edge case correctly
2. **Limit**: Enforce limit and document in user guide
3. **Accept**: Mark test as expected failure with explanation

---

## Next Review Date

**Next Update**: 2026-01-07 (weekly review)

**Trigger for Update**:
- After fixing any chaos test bug
- After adding new chaos tests
- After weekly chaos run
- Before each release
