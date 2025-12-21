# pgGit Greenfield Phase 1: Rebase Strategy Document

## Consolidation Rules

### Rule 1: Chaos Engineering Implementation Consolidation
**Pattern:** All `fix(chaos)` and `feat(chaos)` commits → Consolidated feature commits
**Rationale:** These represent incremental development of chaos engineering features that should be presented as coherent feature additions.

### Rule 2: GREEN Phase Validation Consolidation
**Pattern:** All `fix(GREEN)` and `test(GREEN)` commits → Consolidated validation commits
**Rationale:** These are validation/test fixes that should be consolidated into feature validation commits.

### Rule 3: CI/Test Infrastructure Consolidation
**Pattern:** Repetitive CI test fixes → Single infrastructure stabilization commit
**Rationale:** Multiple similar fixes indicate iterative stabilization that can be consolidated.

### Rule 4: Phase Documentation Consolidation
**Pattern:** Minor documentation updates → Consolidated with major phase deliverables
**Rationale:** Phase reports and updates should be consolidated with the actual phase completion commits.

### Rule 5: Phase Marker Removal
**Pattern:** Remove `[COMPLETE]`, `[GREEN]`, `[GREENFIELD]` from all commit messages
**Rationale:** Phase markers are development artifacts that don't belong in final commit history.

## Consolidation Mapping

### 1. Chaos Engineering Core Functions (24 commits → 3 consolidated)

**Target Commit 1: "feat: Implement core pgGit functions for chaos engineering"**
- Consolidates: pggit function implementations and basic fixes
```
0431913 feat(chaos): implement pggit.commit_changes function
b5b9f38 feat(chaos): implement pggit.create_data_branch function
5d99859 fix(chaos): implement pggit.calculate_schema_hash function
f582590 feat(chaos): implement pggit.delete_branch_simple function
b502a3a feat(chaos): implement pggit.get_version function
d403180 feat(chaos): implement pggit.increment_version function
0554c91 fix(chaos): fix dict access for pggit function results
0914bbf fix(chaos): fix dict access issues in concurrent versioning tests
c6a45e5 fix(chaos): fix commit_message strategy to exclude null bytes
a2f54a5 fix(chaos): ensure test isolation with UUID-based identifiers
```

**Target Commit 2: "feat: Implement chaos engineering concurrency and transaction handling"**
- Consolidates: Concurrency and transaction-related chaos features
```
97a5ef6 feat(chaos): implement Trinity ID collision handling for concurrency
a1623f3 feat(chaos): implement transaction isolation improvements
8202343 feat(chaos): complete Phase 3-GREEN - all concurrency issues resolved
9afb45e feat(chaos): enhance pggit functions with performance and reliability improvements
b34faab feat(chaos): final code quality and performance improvements
f3a9b86 test(chaos): add edge case and performance tests
6a917e9 feat(chaos): update GREEN phase plan - Trinity ID collisions resolved
daff991 feat(chaos): update GREEN phase plan - create_data_branch completed
f7b9c47 feat(chaos): update GREEN phase plan - calculate_schema_hash completed
2b80591 feat(chaos): update GREEN phase plan - commit_changes completed
b0ea373 feat(chaos): complete Phase 2-GREEN - all core functions implemented
a3fab88 fix(chaos): complete pre-GREEN phase infrastructure improvements
```

**Target Commit 3: "feat: Complete chaos engineering test suite implementation"**
- Consolidates: Chaos test suite completion and final fixes
```
84355a4 feat: Implement comprehensive chaos engineering test suite
38eabed feat(chaos): create GREEN phase plan for chaos engineering implementation
f476790 fix(chaos): resolve critical issues in chaos engineering test suite
d7f35fb feat: Implement Phase 3 - Concurrency & Race Condition Tests
c7f7378 feat(chaos): Complete Phases 7-8 - CI Integration & Comprehensive Documentation [COMPLETE]
c1e4d85 feat(chaos): Complete Phase 6 - Schema Corruption & Migration Failure Tests [GREEN]
4ea3faa feat(chaos): Complete Phase 5 - Resource Exhaustion & Load Tests [GREEN]
c1fdc6c feat(chaos): Complete Phase 4 - Transaction Failure & Recovery Tests
cb8b91b fix(tests): Complete chaos engineering test suite fixes - Achieve 90% pass rate [GREEN]
```

### 2. GREEN Phase Validation (16 commits → 2 consolidated)

**Target Commit 1: "feat: Complete chaos engineering test validation"**
- Consolidates: Core GREEN phase test fixes and validation
```
3866544 feat(GREEN): advanced load testing and performance validation
3ce19aa test(GREEN): fix concurrency and property-based tests
d839082 fix(GREEN): complete property-based core tests
180a76c fix(GREEN): comprehensive test infrastructure improvements
2d8b596 fix(GREEN): final concurrent branching test
c3aa3dd fix(GREEN): remaining migration tests
33f7d46 fix(GREEN): migration idempotency tests
a3c2c98 fix(GREEN): data branching tests improvements
5b88297 fix(GREEN): additional data branching test
69b7fdf fix(GREEN): data branching tests
a737b53 fix(GREEN): deadlock scenario tests
a56fa1b fix(GREEN): async concurrent commit tests
024afe9 fix(GREEN): address critical QA issues
```

**Target Commit 2: "feat: Achieve GREEN phase quality standards"**
- Consolidates: GREEN phase completion and final documentation
```
3d2d391 feat: Complete Phase 5 - Add weekly security tests workflow [GREENFIELD]
ab17560 docs(chaos): add comprehensive QA reports for complete chaos engineering implementation
```

### 3. CI/Test Infrastructure (15 commits → 1 consolidated)

**Target Commit: "fix: Stabilize CI test infrastructure and PostgreSQL compatibility"**
- Consolidates: All repetitive CI test fixes and PostgreSQL compatibility issues
```
3608304 ci: Add GitHub Actions workflows and badges
b5a01a1 fix: Update test workflow to use correct install.sql path
3615d85 fix: Install correct pgTAP version for PostgreSQL 15
2d2653b fix: CI pgTAP installation issue
f9bc9b2 fix: Add fallback for pgTAP installation in CI
395bb10 fix: Clean up test runner script syntax
22e9bed fix: Update tests.yml workflow schema to match actual pgGit schema
e6e514c fix: Change SELECT to PERFORM for end_deployment call
55e8f71 fix: Update badge to point to working test workflow
ff5ae74 fix: Make tests more robust for CI environment
5eb4014 fix: Resolve PostgreSQL compatibility issues in tests
e70f149 fix: CI tests - Make tests resilient to missing optional features
c17839c fix: CI tests - Simplify optional feature tests to skip gracefully
99d1268 fix: Zero downtime test - Simplify to skip gracefully when features not loaded
20bcc51 fix: CI tests - Truncate optional feature tests to prevent execution after skip
bb32ac9 fix: Final CI test cleanup - Properly truncate remaining test files
b0923d fix: CI tests - Achieve 100% pass rate
f3077fc feat: Update CI workflow to use uv environments for isolated testing
```

### 4. Phase Documentation Consolidation (34 docs commits → 8 preserved)

**Preserve Major Reports:**
```
8129550 docs: Create comprehensive CHANGELOG for all 4 phases
55b0429 docs: Add Phase 4 QA report - Excellence achieved (9.5/10)
53761c2 docs(chaos): Add Phase 3 Final Report - 100% quality achieved [COMPLETE]
4c7637c docs(chaos): Add Phase 4 Completion Report - Transaction Safety Validated
920ad13 docs(chaos): Add Phase 3 completion report - 90% pass rate achieved
1490c87 docs: Add comprehensive Phase 3 completion status report
b53449b docs: Add missing Phase 2 deliverable and update QA documentation
5f2a7fb docs: Add Phase 5 plan QA report (9.7/10 quality)
```

**Consolidate Minor Updates:**
- Status updates, QA reports, and minor documentation fixes consolidated into preserved major reports

### 5. General Fixes (5 commits → 2 consolidated)

**Target Commit 1: "fix: Resolve core functionality issues"**
```
9cd30d0 fix: exclude temporary tables from DDL event tracking
7cb0e6b Apply ruff unsafe fixes
63e3442 fix: Resolve all TODO/FIXME items in codebase
```

**Target Commit 2: "fix: Complete test suite stabilization"**
```
5a6d687 fix: Resolve all test errors in pgGit test suite
9b1f5db fix: Complete Phase 5 QA Report gaps - Achieve 100% CI pass rate
```

## Commit Message Rewrites

### Clean Message Guidelines
1. Remove all phase markers (`[COMPLETE]`, `[GREEN]`, etc.)
2. Use conventional commit format: `type(scope): description`
3. Make descriptions specific and meaningful
4. Preserve technical intent without development artifacts

### Example Rewrites
- `feat(chaos): Complete Phase 6 - Schema Corruption & Migration Failure Tests [GREEN]` → `feat: Implement schema corruption and migration failure tests`
- `fix(GREEN): address critical QA issues` → `fix: Address critical quality assurance issues`
- `docs(chaos): Add Phase 3 Final Report - 100% quality achieved [COMPLETE]` → `docs: Add Phase 3 final quality report`

## Interactive Rebase Sequence

### Phase 1: Squash chaos engineering commits (24 → 3)
```
git rebase -i --rebase-merges HEAD~140
# Squash the 24 chaos-related commits into 3 consolidated commits
```

### Phase 2: Squash GREEN validation commits (16 → 2)
```
# Follow with next rebase for GREEN commits
```

### Phase 3: Squash CI infrastructure commits (15 → 1)
```
# Follow with next rebase for CI commits
```

### Phase 4: Squash documentation commits (26 → 0, consolidate into preserved)
```
# Consolidate remaining docs into preserved major reports
```

## Success Metrics

- **Target commit count:** 85-95 (current: 140)
- **Consolidation ratio:** 45-52 commits removed (32-37%)
- **Phase markers:** 0 remaining
- **Meaningful history:** Preserved with clear, coherent messages

## Risk Mitigation

- **Backup strategy:** Create backup branch before rebase
- **Verification:** Test build and basic functionality after each consolidation phase
- **Rollback:** Ability to reset to original state if issues discovered

---

*Strategy Document Version: 1.0*
*Created: 2025-12-21*
*Target consolidation: 45-52 commits*