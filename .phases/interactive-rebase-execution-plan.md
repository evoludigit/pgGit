# pgGit Greenfield Phase 1: Interactive Rebase Execution Plan

## Pre-Rebase Preparation

### 1. Create Backup Branch
```bash
# Create backup before any changes
git branch backup-greenfield-pre-phase1
git push origin backup-greenfield-pre-phase1
```

### 2. Verify Current State
```bash
# Confirm we're starting from correct state
git status  # Should be clean
git log --oneline | wc -l  # Should be 140
git log --oneline | grep -E "\[(RED|GREEN|PHASE|COMPLETE)\]" | wc -l  # Should be 7
```

### 3. Test Build Before Changes
```bash
# Ensure everything works before we start
pytest -v --tb=short | head -20  # Quick test run
python -c "import pggit"  # Basic import test
```

## Rebase Execution Strategy

### Strategy Overview
- Use `--rebase-merges` to preserve merge commits where valuable
- Execute consolidation in phases to minimize risk
- Test after each major consolidation
- Use `git rebase --edit-todo` for complex reordering

### Phase 1: Chaos Engineering Consolidation (24 commits → 3)

**Target:** Consolidate all chaos-related commits into 3 coherent feature commits

```bash
# Start interactive rebase from beginning
git rebase -i --rebase-merges HEAD~140

# In the interactive editor, mark commits for squashing:
# - Pick the first commit in each group as 'pick'
# - Mark all subsequent commits in group as 'squash'
# - Edit commit messages according to rewrite document

# Chaos Group 1 (core functions) - 10 commits:
pick 0431913 feat(chaos): implement pggit.commit_changes function
squash b5b9f38 feat(chaos): implement pggit.create_data_branch function
squash 5d99859 fix(chaos): implement pggit.calculate_schema_hash function
squash f582590 feat(chaos): implement pggit.delete_branch_simple function
squash b502a3a feat(chaos): implement pggit.get_version function
squash d403180 feat(chaos): implement pggit.increment_version function
squash 0554c91 fix(chaos): fix dict access for pggit function results
squash 0914bbf fix(chaos): fix dict access issues in concurrent versioning tests
squash c6a45e5 fix(chaos): fix commit_message strategy to exclude null bytes
squash a2f54a5 fix(chaos): ensure test isolation with UUID-based identifiers

# Chaos Group 2 (concurrency) - 12 commits:
pick 97a5ef6 feat(chaos): implement Trinity ID collision handling for concurrency
squash a1623f3 feat(chaos): implement transaction isolation improvements
squash 8202343 feat(chaos): complete Phase 3-GREEN - all concurrency issues resolved
squash 9afb45e feat(chaos): enhance pggit functions with performance and reliability improvements
squash b34faab feat(chaos): final code quality and performance improvements
squash f3a9b86 test(chaos): add edge case and performance tests
squash 6a917e9 feat(chaos): update GREEN phase plan - Trinity ID collisions resolved
squash daff991 feat(chaos): update GREEN phase plan - create_data_branch completed
squash f7b9c47 feat(chaos): update GREEN phase plan - calculate_schema_hash completed
squash 2b80591 feat(chaos): update GREEN phase plan - commit_changes completed
squash b0ea373 feat(chaos): complete Phase 2-GREEN - all core functions implemented
squash a3fab88 fix(chaos): complete pre-GREEN phase infrastructure improvements

# Chaos Group 3 (test suite) - 9 commits:
pick 84355a4 feat: Implement comprehensive chaos engineering test suite
squash 38eabed feat(chaos): create GREEN phase plan for chaos engineering implementation
squash f476790 fix(chaos): resolve critical issues in chaos engineering test suite
squash d7f35fb feat: Implement Phase 3 - Concurrency & Race Condition Tests
squash c7f7378 feat(chaos): Complete Phases 7-8 - CI Integration & Comprehensive Documentation [COMPLETE]
squash c1e4d85 feat(chaos): Complete Phase 6 - Schema Corruption & Migration Failure Tests [GREEN]
squash 4ea3faa feat(chaos): Complete Phase 5 - Resource Exhaustion & Load Tests [GREEN]
squash c1fdc6c feat(chaos): Complete Phase 4 - Transaction Failure & Recovery Tests
squash cb8b91b fix(tests): Complete chaos engineering test suite fixes - Achieve 90% pass rate [GREEN]
```

**Expected Result:** 24 commits consolidated into 3

### Phase 2: GREEN Validation Consolidation (16 commits → 2)

**Continue rebase for GREEN commits:**

```bash
# After Phase 1 completes, continue with:
git rebase --edit-todo

# GREEN Group 1 (test validation) - 13 commits:
pick 3866544 feat(GREEN): advanced load testing and performance validation
squash 3ce19aa test(GREEN): fix concurrency and property-based tests
squash d839082 fix(GREEN): complete property-based core tests
squash 180a76c fix(GREEN): comprehensive test infrastructure improvements
squash 2d8b596 fix(GREEN): final concurrent branching test
squash c3aa3dd fix(GREEN): remaining migration tests
squash 33f7d46 fix(GREEN): migration idempotency tests
squash a3c2c98 fix(GREEN): data branching tests improvements
squash 5b88297 fix(GREEN): additional data branching test
squash 69b7fdf fix(GREEN): data branching tests
squash a737b53 fix(GREEN): deadlock scenario tests
squash a56fa1b fix(GREEN): async concurrent commit tests
squash 024afe9 fix(GREEN): address critical QA issues

# GREEN Group 2 (completion) - 2 commits:
pick 3d2d391 feat: Complete Phase 5 - Add weekly security tests workflow [GREENFIELD]
squash ab17560 docs(chaos): add comprehensive QA reports for complete chaos engineering implementation
```

**Expected Result:** 16 commits consolidated into 2

### Phase 3: CI Infrastructure Consolidation (18 commits → 1)

**Continue rebase for CI commits:**

```bash
# Continue with edit-todo
git rebase --edit-todo

# CI Infrastructure Group - 18 commits:
pick 3608304 ci: Add GitHub Actions workflows and badges
squash b5a01a1 fix: Update test workflow to use correct install.sql path
squash 3615d85 fix: Install correct pgTAP version for PostgreSQL 15
squash 2d2653b fix: CI pgTAP installation issue
squash f9bc9b2 fix: Add fallback for pgTAP installation in CI
squash 395bb10 fix: Clean up test runner script syntax
squash 22e9bed fix: Update tests.yml workflow schema to match actual pgGit schema
squash e6e514c fix: Change SELECT to PERFORM for end_deployment call
squash 55e8f71 fix: Update badge to point to working test workflow
squash ff5ae74 fix: Make tests more robust for CI environment
squash 5eb4014 fix: Resolve PostgreSQL compatibility issues in tests
squash e70f149 fix: CI tests - Make tests resilient to missing optional features
squash c17839c fix: CI tests - Simplify optional feature tests to skip gracefully
squash 99d1268 fix: Zero downtime test - Simplify to skip gracefully when features not loaded
squash 20bcc51 fix: CI tests - Truncate optional feature tests to prevent execution after skip
squash bb32ac9 fix: Final CI test cleanup - Properly truncate remaining test files
squash b0923d fix: CI tests - Achieve 100% pass rate
squash f3077fc feat: Update CI workflow to use uv environments for isolated testing
```

**Expected Result:** 18 commits consolidated into 1

### Phase 4: General Fixes Consolidation (5 commits → 2)

**Continue rebase for general fixes:**

```bash
# Continue with edit-todo
git rebase --edit-todo

# General Fixes Group 1 - 3 commits:
pick 9cd30d0 fix: exclude temporary tables from DDL event tracking
squash 7cb0e6b Apply ruff unsafe fixes
squash 63e3442 fix: Resolve all TODO/FIXME items in codebase

# General Fixes Group 2 - 2 commits:
pick 5a6d687 fix: Resolve all test errors in pgGit test suite
squash 9b1f5db fix: Complete Phase 5 QA Report gaps - Achieve 100% CI pass rate
```

**Expected Result:** 5 commits consolidated into 2

### Phase 5: Documentation Consolidation

**Strategy:** Squash minor documentation updates into preserved major reports

```bash
# Identify and squash remaining documentation commits into the 8 preserved ones
# This will be done in the final rebase pass
```

## Post-Rebase Verification

### 1. Commit Count Verification
```bash
# Should be 85-95 commits
git log --oneline | wc -l

# Should be 0 phase markers
git log --oneline | grep -E "\[(RED|GREEN|PHASE|COMPLETE)\]" | wc -l
```

### 2. Build and Test Verification
```bash
# Run tests to ensure functionality preserved
pytest -v --tb=short

# Check for any import issues
python -c "import pggit"

# Run linting
ruff check .
```

### 3. History Review
```bash
# Review final commit history
git log --oneline | head -20

# Check that consolidated commits have proper messages
git log --oneline | grep "feat:\|fix:\|docs:"
```

## Rollback Plan

### If Issues Discovered
```bash
# Reset to backup branch
git reset --hard backup-greenfield-pre-phase1

# Or reset to specific commit if partial success
git reset --hard <last-good-commit>
```

### Partial Success Recovery
- If some consolidations succeed but others fail, can re-run specific phases
- Each consolidation group is independent
- Can use `git cherry-pick` to recover specific commits if needed

## Execution Timeline

**Estimated Time:** 2-3 hours total
- Phase 1 (Chaos): 45 minutes
- Phase 2 (GREEN): 30 minutes
- Phase 3 (CI): 30 minutes
- Phase 4 (General): 15 minutes
- Phase 5 (Docs): 20 minutes
- Verification: 20 minutes

## Success Criteria

- ✅ Commit count: 85-95 (down from 140)
- ✅ Phase markers: 0 remaining
- ✅ Tests pass: All functionality preserved
- ✅ Build works: No breaking changes
- ✅ History coherent: Logical progression of features

---

*Rebase Execution Plan Version: 1.0*
*Created: 2025-12-21*
*Risk Level: Medium (reversible with backup)*