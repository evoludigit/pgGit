# pgGit Greenfield Transformation: Master Phase Plan

**Target State**: pgGit as an exemplary PostgreSQL + Git integration library - a reference implementation demonstrating best practices in Python project structure, testing, documentation, and clean development.

**Vision**: Transform from accumulated "archeology layers" (phase markers, fix commits, experimental branches, technical debt) into a pristine, production-ready codebase with coherent commit history.

---

## Executive Summary

This master plan outlines an 8-phase transformation of pgGit from a project with development artifacts and phase markers to a greenfield, eternal-sunshine-of-the-spotless-code reference implementation.

**Key Metrics**:
- Current commit count: 137 total
- Phase-marker commits to consolidate: 6+ (likely more in full history)
- Target state: Coherent, clean commit history (~80-90 commits)
- Test coverage target: ≥80% core logic
- Type hint coverage: 100% public API
- Docstring coverage: 100% modules/classes/public functions
- Linting violations: 0
- New developer onboarding: <30 minutes

---

## Phase Execution Order

Each phase produces audit/plan documents first, followed by implementation with verification gates.

### Phase 1: Commit History Archaeology & Strategy
**Duration**: 2-3 hours (audit + planning)

#### Objective
Audit and plan rebasing strategy to eliminate phase markers and consolidate fix commits while preserving meaningful history.

#### Current State Assessment
- 137 total commits
- 6 identifiable phase-marker commits: `[COMPLETE]`, `[GREEN]`, `[PHASE]`
- Multiple `fix(...)` commits that should be squashed into feature commits
- Multiple `docs(chaos)` commits that can be consolidated
- Multiple `refactor` commits that may be consolidable

#### Tasks

1. **Commit Archaeology Analysis**
   - Generate complete commit list with message classification
   - Categorize: feature, fix, refactor, docs, chore, test
   - Identify: phase markers, fix commits, experimental, WIP, duplicates
   - Mark: commits to preserve vs. consolidate

2. **Rebase Strategy Design**
   - Define consolidation rules (e.g., "all fix(chaos) commits → related feat(chaos)")
   - Map which commits merge into which
   - Identify commits that establish new features/branches
   - Plan commit message rewrites for clarity
   - Design phase marker removal (preserve intent without "[PHASE]" notation)

3. **Preservation Decisions**
   - Core features: keep with clear messages
   - Test infrastructure: consolidate related commits
   - Documentation: consolidate release docs into feature commits
   - Performance work: preserve if meaningful separate work

#### Implementation Steps

1. Generate full commit audit:
   ```bash
   git log --oneline --all > commits_audit.txt
   git log --format="%h %s" --all | sort > commits_detailed.txt
   ```

2. Classify each commit by type and phase marker status

3. Create consolidation map:
   - Example: `fix(chaos): ... → feat(chaos): ...`
   - Example: `docs(chaos): Phase 3 report → feat(chaos): Phase 3`

4. Draft new commit messages (removing phase markers, preserving intent)

5. Plan interactive rebase sequence

#### Output Documents

1. **Commit Archaeology Report**
   - Current commit distribution by type
   - Phase-marker commit inventory
   - Fix/WIP/experimental commits identified
   - Consolidation strategy with specific commit pairs

2. **Rebase Strategy Document**
   - Consolidation map (commit hash → target commit)
   - New commit messages (cleaned, no phase markers)
   - Commits to preserve as-is
   - Commits to be squashed with timing/ordering

3. **Success Metrics**
   - Target commit count: 85-95 (from 137)
   - Commits to consolidate: 40-50
   - Commits to preserve: 85-95

#### Acceptance Criteria
- [ ] Complete commit archaeology audit (all 137 commits classified)
- [ ] Clear rebase strategy documented
- [ ] Commit consolidation map created (no ambiguity)
- [ ] New commit messages drafted and reviewed
- [ ] Team approval on consolidation approach before execution

#### Verification Command
```bash
# After completion, verify:
git log --oneline | wc -l  # Should be 85-95
git log --oneline | grep -E "\[(RED|GREEN|PHASE|COMPLETE)\]" | wc -l  # Should be 0
```

---

### Phase 2: Codebase Architecture Audit
**Duration**: 3-4 hours (audit)

#### Objective
Identify and plan elimination of experimental/legacy code paths, dead code, and incomplete features.

#### Tasks

1. **Feature Completeness Audit**
   - List all features/modules in pgGit
   - Classify: fully implemented & tested vs. partial vs. experimental
   - Identify: branching strategy (Git operations)
   - Identify: versioning system
   - Identify: chaos engineering test suite (scope, maturity)

2. **Dead Code & Technical Debt Inventory**
   - Unused imports, functions, classes
   - Disabled features (comments with TODO/FIXME)
   - Experimental code paths
   - Workarounds and technical debt

3. **Schema & Migration Audit**
   - Current schema version
   - Migration history (necessary vs. historical)
   - Schema design rationale
   - Any schema cleanup needed

4. **Test Architecture Analysis**
   - Test organization and naming
   - Coverage gaps
   - Redundant or overlapping tests
   - Test infrastructure (fixtures, factories, mocks)

5. **Dependency Audit**
   - Current dependencies in pyproject.toml
   - Each dependency justified and used?
   - Version pinning appropriate?
   - Unnecessary development dependencies?

#### Implementation Steps

1. Generate code metrics:
   ```bash
   find . -name "*.py" -type f | wc -l  # Total Python files
   ruff check . --statistics  # Lint violations
   coverage run -m pytest; coverage report  # Coverage
   ```

2. Analyze feature modules:
   - List all .py files in src/
   - Document purpose and status of each
   - Identify incomplete features

3. Search for dead code markers:
   ```bash
   grep -r "TODO\|FIXME\|XXX\|HACK" --include="*.py" .
   grep -r "# disabled\|# old\|# deprecated" --include="*.py" .
   ```

4. Review schema and migrations

5. Audit dependencies:
   ```bash
   pip show <package>  # For each dependency
   ```

#### Output Documents

1. **Architecture Audit Report**
   - Feature completeness matrix (feature → status)
   - Dead code inventory with files/functions
   - Technical debt by severity
   - Dependency justification list
   - Schema assessment

2. **Feature Status Document**
   - Fully implemented features (keep)
   - Experimental features (decide: complete, remove, or stabilize)
   - Partial implementations (plan completion or removal)
   - Configuration options (which are used vs. vestigial)

3. **Removal Strategy**
   - Code to delete (with rationale)
   - Features to complete
   - Dependencies to remove (if any)
   - Migrations to consolidate (if any)

#### Acceptance Criteria
- [ ] All modules/features classified
- [ ] Dead code identified and documented
- [ ] Technical debt prioritized
- [ ] Dependency justification complete
- [ ] Clear removal/completion strategy for experimental code

#### Verification Command
```bash
# After cleanup:
grep -r "TODO\|FIXME\|XXX\|HACK" --include="*.py" . | wc -l  # Should be minimal
python -m py_compile $(find . -name "*.py")  # All files compile
```

---

### Phase 3: Repository State Cleanup
**Duration**: 2-3 hours (cleanup + git history)

#### Objective
Remove transient files, artifacts, and ensure pristine repository state.

#### Tasks

1. **Remove Build Artifacts**
   - `.hypothesis/` directory
   - `__pycache__/` directories
   - `.pytest_cache/`
   - `.ruff_cache/`
   - `.venv/` (ensure in .gitignore)
   - `*.egg-info/` directories
   - Any `.pyc` files

2. **Audit & Clean .gitignore**
   - Remove unnecessary ignores
   - Add missing patterns
   - Ensure standard Python ignores present
   - Document ignores

3. **Directory Structure Review**
   - Any stray/orphaned test directories
   - Backup files or duplicates
   - Temporary development artifacts
   - Organize cleanly by feature/concern

4. **GitHub Workflows Audit**
   - Review `.github/workflows` (if present)
   - Ensure CI is configured appropriately
   - Remove obsolete workflows

5. **Git Configuration**
   - Review `.pre-commit-config.yaml`
   - Ensure hooks are appropriate
   - Clean up any obsolete hooks

6. **Documentation Files**
   - Review all `.md` files at root
   - Ensure essential docs present (README, CONTRIBUTING, etc.)
   - Remove obsolete docs

#### Implementation Steps

1. Remove files from git:
   ```bash
   git rm -r .hypothesis/ --cached
   git rm -r __pycache__/ --cached
   git rm -r .pytest_cache/ --cached
   git rm -r .ruff_cache/ --cached
   find . -name "*.pyc" -exec git rm {} --cached \;
   find . -name "__pycache__" -type d -exec git rm -r {} --cached \;
   ```

2. Update .gitignore with comprehensive patterns

3. Verify directory structure is clean and logical

4. Clean up any temporary files

5. Commit: "chore: remove build artifacts and clean repository"

#### Output Documents

1. **Repository Cleanup Report**
   - Files removed from git
   - Updated .gitignore
   - Directory structure diagram
   - Artifacts cleaned

2. **Repository Health Summary**
   - Tracked file count (before/after)
   - Repository size (before/after)
   - Clean artifacts verified

#### Acceptance Criteria
- [ ] No `__pycache__`, `.pytest_cache`, `.hypothesis`, `.ruff_cache` in git
- [ ] .gitignore is clean and comprehensive
- [ ] Repository contains only essential files
- [ ] No stray temporary files
- [ ] Directory structure is logical and clean

#### Verification Command
```bash
git status --short  # Should show minimal changes
git ls-files | grep -E "\.pyc|__pycache__|\.hypothesis|\.pytest_cache" | wc -l  # Should be 0
du -sh .  # Repository size
```

---

### Phase 4: Code Quality Standardization
**Duration**: 4-6 hours (audit + fixes)

#### Objective
Enforce Python project standards: type hints, linting, imports, docstrings, psycopg3 verification.

#### Standards to Enforce

**Type Hints** (Python 3.10+ syntax):
- All public functions: complete type hints
- All module-level code: type hints
- Use `X | None` not `Optional[X]`
- Use `list[T]`, `dict[K, V]` not `List[T]`, `Dict[K, V]`

**Docstrings**:
- All modules: docstring at top
- All public classes: docstring
- All public functions: docstring
- Format: Google-style docstrings

**Imports**:
- Organized: stdlib, third-party, local (isort style)
- No unused imports
- Explicit imports (not `from module import *`)

**Linting** (ruff):
- Zero violations
- All applicable checks enabled
- Code passes all ruff rules

**PostgreSQL Driver**:
- psycopg3 (psycopg) exclusively
- No psycopg2 imports
- Modern async patterns only

#### Tasks

1. **Type Hint Audit**
   - Identify all functions without type hints
   - Classify by scope (public vs. internal)
   - Plan type hint additions
   - Handle complex types (generics, unions, etc.)

2. **Linting Analysis**
   ```bash
   ruff check . --statistics
   ```
   - Identify all violations
   - Categorize by type
   - Plan fixes

3. **Docstring Audit**
   - Identify modules without docstrings
   - Identify public classes without docstrings
   - Identify public functions without docstrings
   - Plan additions

4. **Import Reorganization**
   - Check import organization
   - Identify unused imports
   - Verify explicit imports

5. **psycopg Version Verification**
   - Grep for psycopg2 imports
   - Grep for async patterns
   - Verify psycopg3 usage

6. **Python Version Consistency**
   - Verify Python 3.10+ syntax throughout
   - Check for old-style type hints
   - Update pyproject.toml python-version

#### Implementation Steps

1. Run comprehensive audit:
   ```bash
   ruff check . --statistics > linting_audit.txt
   python -m pytest --collect-only > tests_collected.txt
   ```

2. Generate type hint report:
   - Scan all .py files for functions without type hints
   - Document what's missing

3. Generate docstring report:
   - Scan all modules, classes, public functions

4. Import audit:
   - Check for unused imports
   - Verify organization

5. Fix violations systematically (may involve local model for boilerplate)

#### Output Documents

1. **Type Hint Audit Report**
   - Functions without type hints (location)
   - Complex types needing handling
   - Plan for adding type hints

2. **Linting Violations Report**
   - All violations categorized
   - Severity and impact
   - Fix plan

3. **Docstring Gaps Report**
   - Modules, classes, functions missing docstrings
   - Priority for additions

4. **Import Organization Report**
   - Unused imports
   - Import grouping issues
   - Fix plan

5. **Code Quality Summary**
   - Before/after metrics
   - Standards compliance checklist

#### Acceptance Criteria
- [ ] All public functions have complete type hints
- [ ] Python 3.10+ syntax used throughout (no Optional, List, Dict from typing)
- [ ] Zero ruff violations
- [ ] All modules/classes/public functions have docstrings
- [ ] No unused imports
- [ ] psycopg3 exclusively (no psycopg2)
- [ ] Imports properly organized

#### Verification Command
```bash
ruff check .  # Zero violations
python -m pytest --collect-only -q  # All tests collect
python -c "import ast; [ast.parse(open(f).read()) for f in $(find . -name '*.py')]"  # All files parse
grep -r "from typing import Optional\|from typing import List\|from typing import Dict" --include="*.py" .  # Should be none
grep -r "import psycopg2" --include="*.py" .  # Should be none
```

---

### Phase 5: Test Suite Modernization
**Duration**: 3-4 hours (audit + reorganization)

#### Objective
Create a focused, effective test suite with ≥80% coverage of core logic, organized by feature/component.

#### Current Test State
- Chaos engineering test suite present (recent, comprehensive)
- Property-based tests using Hypothesis
- Test infrastructure with fixtures and conftest

#### Tasks

1. **Test Coverage Analysis**
   - Generate coverage report: `coverage run -m pytest && coverage report`
   - Identify gaps in core logic
   - Identify overly tested areas (diminishing returns)

2. **Test Organization Review**
   - Current directory structure (tests/chaos/, etc.)
   - Naming conventions
   - Test feature/component mapping
   - Fixture and factory usage

3. **Redundancy & Duplication Audit**
   - Identify overlapping test scenarios
   - Identify duplicated test cases
   - Identify skipped tests (document why)

4. **Test Infrastructure Assessment**
   - Fixture design and reusability
   - Mock and factory patterns
   - conftest.py organization
   - Parametrization patterns

5. **Coverage Gap Analysis**
   - Modules with <80% coverage
   - Critical paths not tested
   - Edge cases missing

#### Implementation Steps

1. Generate coverage:
   ```bash
   coverage run -m pytest --cov=src --cov-report=html --cov-report=term
   ```

2. Analyze coverage by module:
   - Identify gaps
   - Prioritize additions

3. Review test organization:
   - Group tests by feature
   - Ensure clear naming
   - Remove redundancy

4. Update conftest.py for clarity

5. Add missing tests for critical paths

6. Verify all tests pass:
   ```bash
   pytest -v --tb=short
   ```

#### Output Documents

1. **Test Coverage Report**
   - Coverage by module (with gaps)
   - Current coverage %
   - Target coverage % (80%+)
   - Missing test categories

2. **Test Organization Plan**
   - Directory structure (tests/unit/, tests/integration/, etc.)
   - Test naming conventions
   - Feature-to-test mapping

3. **Redundancy Report**
   - Duplicated tests identified
   - Overlapping scenarios
   - Consolidation plan

4. **Test Infrastructure Assessment**
   - Fixture reusability review
   - Mock/factory patterns
   - Improvements needed

#### Acceptance Criteria
- [ ] All tests pass
- [ ] No skipped tests (or documented reason)
- [ ] ≥80% coverage of core pgGit logic
- [ ] Tests organized by feature/component
- [ ] Clear, descriptive test names
- [ ] No redundant/overlapping tests
- [ ] Shared fixtures in conftest.py
- [ ] Coverage gaps documented and planned

#### Verification Command
```bash
pytest -v --tb=short  # All pass
coverage run -m pytest --cov=src && coverage report | grep "TOTAL"  # Coverage ≥80%
pytest --collect-only -q | grep "test_" | wc -l  # Test count
```

---

### Phase 6: Documentation Completeness
**Duration**: 3-4 hours (writing)

#### Objective
Create exemplary project documentation enabling new developers to contribute within 30 minutes.

#### Documentation Scope

**Essential Documents**:
1. README.md - Project overview, quick start, key features
2. ARCHITECTURE.md - Design decisions, module structure, key concepts
3. CONTRIBUTING.md - Development workflow, standards, PR process
4. API_REFERENCE.md - Public API documentation
5. INSTALLATION.md - Setup and environment configuration

#### Tasks

1. **Current Documentation Audit**
   - Review existing README.md
   - Review CONTRIBUTING.md
   - Review any existing docs
   - Identify gaps and unclear sections

2. **New Developer Path Design**
   - What must a new dev understand in 30 min?
   - What are the key concepts?
   - What is the getting-started workflow?
   - What examples are most helpful?

3. **Architecture Documentation**
   - Core pgGit concepts (branching, versioning, Git integration)
   - Module structure and responsibilities
   - Key classes and functions
   - Design patterns used
   - Trade-offs and decisions

4. **API Documentation**
   - Public API reference
   - Function signatures with examples
   - Common use cases
   - Error handling

5. **Contributing Guide**
   - Development environment setup
   - Running tests
   - Code standards (type hints, docstrings, etc.)
   - PR process
   - Commit message format

6. **Installation & Setup**
   - Python version requirements
   - Dependency installation (uv)
   - Database setup
   - Environment variables
   - Verification steps

#### Implementation Steps

1. Outline each documentation section

2. Review existing docs and identify what's good/needs updating

3. Write each document:
   - README.md (2 hours)
   - ARCHITECTURE.md (1.5 hours)
   - CONTRIBUTING.md (1 hour)
   - API_REFERENCE.md (1 hour)
   - INSTALLATION.md (0.5 hours)

4. Cross-review for clarity and consistency

5. Get feedback from team

#### Output Documents

1. **Documentation Audit Report**
   - Current docs assessment
   - Gaps and improvements
   - Clarity assessment

2. **New Documentation**
   - Updated README.md
   - ARCHITECTURE.md
   - Updated CONTRIBUTING.md
   - API_REFERENCE.md
   - INSTALLATION.md

3. **Documentation Index**
   - Links to all documentation
   - Guide for finding information
   - Contribution guidelines for docs

#### Acceptance Criteria
- [ ] README clearly explains purpose and key features
- [ ] New developer can set up environment in <10 min
- [ ] New developer understands architecture in <20 min
- [ ] All public APIs documented with examples
- [ ] CONTRIBUTING guide reflects current standards
- [ ] INSTALLATION guide is complete and accurate
- [ ] No documentation is outdated or contradictory
- [ ] Examples are correct and runnable

#### Verification
```bash
# New developer experience test:
# 1. Clone repo
# 2. Follow README (time: <5 min)
# 3. Follow INSTALLATION (time: <5 min)
# 4. Run tests (all pass)
# 5. Review ARCHITECTURE (time: <15 min, understand core concepts)
# 6. Review API_REFERENCE (time: <5 min, understand public API)
```

---

### Phase 7: Configuration & Build Standardization
**Duration**: 2 hours (audit + cleanup)

#### Objective
Ensure clean, modern build and runtime configuration following Python best practices.

#### Tasks

1. **pyproject.toml Audit**
   - Review all dependencies (necessary?)
   - Version pinning appropriate?
   - Metadata (name, description, version) up-to-date?
   - Build system configuration correct?
   - Python version requirement correct (3.10+)?

2. **uv Configuration**
   - uv.lock present and up-to-date?
   - uv.toml or pyproject.toml config appropriate?
   - No deprecated uv config?

3. **ruff Configuration**
   - All applicable checks enabled?
   - Any disabled checks justified?
   - Line length appropriate?
   - Configuration in pyproject.toml?

4. **pytest Configuration**
   - pytest.ini vs. pyproject.toml (consolidate to pyproject.toml)
   - Test discovery patterns correct?
   - Useful pytest options configured (verbose, etc.)?

5. **Legacy Config Files Audit**
   - Any .flake8, setup.py, tox.ini, etc.?
   - Remove or document reason for keeping

6. **Environment Variables**
   - Document all required env vars
   - Example .env file
   - Defaults for development

#### Implementation Steps

1. Audit pyproject.toml:
   ```toml
   [project]
   name = "pggit"
   description = "..."
   requires-python = ">=3.10"
   dependencies = [...]  # Verify each necessary

   [tool.ruff]
   line-length = 100
   # All checks enabled

   [tool.pytest.ini_options]
   # Proper configuration
   ```

2. Verify dependencies:
   ```bash
   pip list  # Verify each is used
   ```

3. Consolidate config to pyproject.toml

4. Create example .env if needed

5. Document all environment variables

#### Output Documents

1. **Configuration Audit Report**
   - Dependencies verified
   - Version pinning reviewed
   - Config consolidation plan

2. **Updated Configuration Files**
   - Clean pyproject.toml
   - Remove legacy config files
   - Environment variable documentation

3. **Setup Verification**
   - List of all configuration requirements
   - Environment variable reference
   - Example .env file

#### Acceptance Criteria
- [ ] pyproject.toml is single source of truth
- [ ] No legacy config files (.flake8, setup.py, tox.ini)
- [ ] All environment variables documented
- [ ] Dependencies minimal and justified
- [ ] Version pinning appropriate
- [ ] Python version requirement: >=3.10
- [ ] Build system configuration correct
- [ ] All tools configured in pyproject.toml (not separate files)

#### Verification Command
```bash
# Verify configuration
python -m pip install -e .  # Install from current config
pytest --version  # Uses configured pytest
ruff check . --version  # Uses configured ruff

# Verify no legacy configs
ls -la | grep -E "setup.py|tox.ini|.flake8|setup.cfg"  # Should be none
```

---

### Phase 8: Final Greenfield Verification
**Duration**: 2-3 hours (comprehensive audit)

#### Objective
Verify transformation is complete and exemplary across all dimensions.

#### Tasks

1. **Full Test Suite Run**
   ```bash
   pytest -v --tb=short
   ```
   - All tests pass ✓
   - No skipped tests (or documented) ✓
   - No warnings ✓

2. **Complete Linting Verification**
   ```bash
   ruff check .
   ```
   - Zero violations ✓
   - All applicable checks enabled ✓

3. **Coverage Report Generation**
   ```bash
   coverage run -m pytest --cov=src --cov-report=html
   coverage report
   ```
   - ≥80% coverage ✓
   - Core logic well-covered ✓
   - Gaps documented ✓

4. **Code Quality Spot-Check**
   - Sample code review (10-15 files)
   - Verify: type hints, docstrings, style
   - No TODOs/FIXMEs ✓

5. **Commit History Review**
   - Verify: no phase markers remaining ✓
   - Verify: coherent, clear commit messages ✓
   - Verify: commits tell logical story ✓
   - Count: 85-95 commits ✓

6. **Documentation Walkthrough**
   - New developer follows README (success?)
   - Architecture makes sense (understandable?)
   - API reference complete (accurate?)
   - Contributing guide sufficient (clear?)

7. **Repository Health Check**
   - No tracked build artifacts ✓
   - Directory structure clean ✓
   - .gitignore appropriate ✓
   - No temporary files ✓

8. **Configuration Verification**
   - pyproject.toml clean ✓
   - All tools configured ✓
   - Environment variables documented ✓

#### Implementation Steps

1. Run comprehensive test suite:
   ```bash
   pytest -v --tb=short 2>&1 | tee verification_tests.txt
   ```

2. Run full linting:
   ```bash
   ruff check . 2>&1 | tee verification_linting.txt
   ```

3. Generate coverage:
   ```bash
   coverage run -m pytest --cov=src --cov-report=term --cov-report=html
   coverage report > verification_coverage.txt
   ```

4. Spot-check code:
   - Sample 10-15 Python files
   - Verify standards compliance

5. Review commit history:
   ```bash
   git log --oneline > verification_commits.txt
   git log --oneline | grep -E "\[(RED|GREEN|PHASE|COMPLETE)\]"  # Should be none
   ```

6. Documentation review:
   - Read each document for clarity
   - Follow setup instructions
   - Verify API reference accuracy

7. Repository health:
   ```bash
   git status  # Should be clean
   git ls-files | grep -E "\.pyc|__pycache__|\.hypothesis"  # Should be none
   du -sh .  # Repository size
   ```

#### Output Documents

1. **Greenfield Verification Checklist**
   - All items checked and passed
   - Any exceptions documented and justified

2. **Final Code Metrics Report**
   - Test count: X tests
   - Test coverage: Y% (target: ≥80%)
   - Type hint coverage: 100% public API
   - Docstring coverage: 100% modules/classes/public
   - Linting violations: 0
   - Cyclomatic complexity: [acceptable]
   - Lines of code: X (core), Y (tests)
   - Commit count: Z (from 137)
   - Time to onboard new developer: <30 min

3. **Greenfield Status Report**
   - Go/no-go decision
   - Any remaining issues
   - Recommendations for future work
   - Highlights of achieved standards

#### Acceptance Criteria
- [ ] All tests pass (pytest -v shows green)
- [ ] Zero linting violations (ruff check passes)
- [ ] Coverage ≥80% of core pgGit logic
- [ ] 100% of public code has type hints
- [ ] 100% of modules/classes/public functions documented
- [ ] No phase markers in commit history
- [ ] Commit history coherent and clean (85-95 commits)
- [ ] Documentation complete and clear
- [ ] Repository state pristine (no artifacts)
- [ ] Configuration clean and modern
- [ ] New developer can onboard in <30 minutes

#### Verification Command - Complete Audit
```bash
#!/bin/bash
# Run complete verification suite

echo "=== TEST SUITE ==="
pytest -v --tb=short
TEST_PASS=$?

echo -e "\n=== LINTING ==="
ruff check .
LINT_PASS=$?

echo -e "\n=== COVERAGE ==="
coverage run -m pytest --cov=src --cov-report=term
coverage report | grep "TOTAL"
COVERAGE_PASS=$?

echo -e "\n=== COMMIT HISTORY ==="
echo "Total commits: $(git log --oneline | wc -l)"
echo "Phase markers remaining: $(git log --oneline | grep -E '\[(RED|GREEN|PHASE|COMPLETE)\]' | wc -l)"

echo -e "\n=== REPOSITORY STATE ==="
echo "Git status:"
git status --short
echo "Tracked artifacts: $(git ls-files | grep -E '\.pyc|__pycache__|\.hypothesis' | wc -l)"

echo -e "\n=== SUMMARY ==="
[ $TEST_PASS -eq 0 ] && echo "✓ Tests passing" || echo "✗ Tests failing"
[ $LINT_PASS -eq 0 ] && echo "✓ Linting clean" || echo "✗ Linting violations"
[ $COVERAGE_PASS -eq 0 ] && echo "✓ Coverage measured" || echo "✗ Coverage failed"
```

---

## Master Timeline

**Total Duration**: 20-28 hours (spread across 2-3 weeks)

| Phase | Audit | Implementation | Verification | Total |
|-------|-------|-----------------|--------------|-------|
| 1. Commit Archaeology | 2-3 hrs | 1-2 hrs | 0.5 hr | 3.5-5.5 hrs |
| 2. Architecture Audit | 3-4 hrs | 0 hrs | 0.5 hr | 3.5-4.5 hrs |
| 3. Repository Cleanup | 1 hr | 1-2 hrs | 0.5 hr | 2.5-3.5 hrs |
| 4. Code Quality | 2 hrs | 2-4 hrs | 0.5 hr | 4.5-6.5 hrs |
| 5. Test Suite | 2-3 hrs | 1-2 hrs | 0.5 hr | 3.5-5.5 hrs |
| 6. Documentation | 1 hr | 3-4 hrs | 0.5 hr | 4.5-5.5 hrs |
| 7. Configuration | 1 hr | 1 hr | 0.5 hr | 2.5 hrs |
| 8. Final Verification | 1 hr | 0 hrs | 2-3 hrs | 3-4 hrs |
| **TOTAL** | **13-15 hrs** | **9-17 hrs** | **5-6 hrs** | **27-38 hrs** |

**Recommended Approach**:
- 1-2 hours per session, 3-4 sessions per week
- Complete phases sequentially
- Verification gates before moving to next phase
- Team review/approval before rebase/major changes

---

## Success Criteria - Final State

### Code Quality
- ✅ Type hint coverage: 100% (public API)
- ✅ Docstring coverage: 100% (modules, classes, public functions)
- ✅ Linting violations: 0
- ✅ Test coverage: ≥80% core logic
- ✅ All tests passing
- ✅ No TODOs/FIXMEs/XXXs in code
- ✅ Python 3.10+ syntax throughout
- ✅ psycopg3 exclusively

### Commit History
- ✅ Phase markers removed ([RED], [GREEN], [PHASE], etc.)
- ✅ Fix commits consolidated into feature commits
- ✅ Commit count: 85-95 (from 137)
- ✅ Each commit has clear, coherent message
- ✅ History tells logical story of development

### Repository
- ✅ No build artifacts (.pytest_cache, __pycache__, .hypothesis, etc.)
- ✅ .gitignore clean and comprehensive
- ✅ Directory structure logical and clean
- ✅ No temporary files or stray branches

### Documentation
- ✅ README complete and clear
- ✅ Architecture document explains design
- ✅ Contributing guide reflects standards
- ✅ API reference complete with examples
- ✅ Installation guide accurate
- ✅ New developer onboarding: <30 minutes

### Configuration
- ✅ pyproject.toml is single source of truth
- ✅ No legacy config files
- ✅ All environment variables documented
- ✅ Build system modern and clean

### Overall
- ✅ pgGit is reference implementation
- ✅ Exemplary Python project structure
- ✅ Production-ready codebase
- ✅ "Eternal sunshine of the spotless code"

---

## Non-Goals & Constraints

**Do NOT**:
- ❌ Rewrite working functionality
- ❌ Change architectural decisions that work
- ❌ Sacrifice test coverage for fewer commits
- ❌ Remove necessary schema migrations
- ❌ Break any working features
- ❌ Change stable public APIs without strong reason

**Preserve**:
- ✅ Core pgGit functionality (branching, versioning)
- ✅ Chaos engineering test suite (it's excellent)
- ✅ Property-based testing with Hypothesis
- ✅ Database integration and schema

---

## Decision Points & Approvals

Before executing each phase, confirm:

1. **Phase 1** (Commit Archaeology):
   - Review commit consolidation map
   - Approve rebase strategy
   - Confirm new commit messages

2. **Phase 2** (Architecture Audit):
   - Review features to keep/remove
   - Confirm technical debt priorities
   - Approve dead code removal list

3. **Phase 3** (Repository Cleanup):
   - Verify directory structure
   - Review .gitignore changes
   - Approve artifact removal

4. **Phase 4** (Code Quality):
   - Spot-check type hint additions
   - Review linting fixes
   - Confirm docstring format

5. **Phase 5** (Test Suite):
   - Review test reorganization
   - Confirm coverage targets
   - Validate test removals

6. **Phase 6** (Documentation):
   - Review documentation accuracy
   - Confirm new developer walkthrough
   - Approve documentation structure

7. **Phase 7** (Configuration):
   - Review pyproject.toml
   - Confirm dependency list
   - Approve config consolidation

8. **Phase 8** (Verification):
   - Final greenfield checklist review
   - Go/no-go decision
   - Approval for merging

---

## Integration Points

**Dependency between phases**:

```
Phase 1 (Archaeology) ──→ Phase 3 (Cleanup) ─┐
                                              ├─→ Phase 8 (Verification)
Phase 2 (Architecture) ──→ Phase 4 (Quality) ┤
                                              ├─→ Phase 8 (Verification)
                    Phase 5 (Tests) ─────────┤
                                              ├─→ Phase 8 (Verification)
                    Phase 6 (Docs) ──────────┤
                                              ├─→ Phase 8 (Verification)
                    Phase 7 (Config) ────────┘
```

**Recommended Execution**:
- Phase 1 (audit only, 2-3 hrs)
- Phase 2 (audit only, 3-4 hrs)
- Phase 3 (cleanup, 2.5-3.5 hrs) - can start after Phase 1 approved
- Phase 4 (quality, 4.5-6.5 hrs) - can start after Phase 2 approved
- Phase 5 (tests, 3.5-5.5 hrs) - can overlap with Phase 4
- Phase 6 (docs, 4.5-5.5 hrs) - can overlap with Phase 4-5
- Phase 7 (config, 2.5 hrs) - can overlap with Phase 4-6
- Phase 8 (verification, 3-4 hrs) - after all others complete

**Suggested Weekly Breakdown** (3 weeks):

**Week 1**:
- Phase 1 audit (Tue): 2.5 hrs
- Phase 1 implementation (Wed): 1.5 hrs
- Phase 2 audit (Thu): 3 hrs
- Phase 3 cleanup (Fri): 2.5 hrs

**Week 2**:
- Phase 4 code quality (Mon-Wed): 5-6 hrs
- Phase 5 test modernization (Thu-Fri): 4 hrs

**Week 3**:
- Phase 6 documentation (Mon-Tue): 4.5 hrs
- Phase 7 configuration (Wed): 2.5 hrs
- Phase 8 verification (Thu-Fri): 3-4 hrs

---

## Rollback & Recovery Plan

**If a phase fails**:

1. **Commit history changes** (Phase 1):
   - Can be rolled back with force push (if coordinated)
   - Keep backups of rebase plan before executing

2. **Code changes** (Phases 3-7):
   - Each phase is a separate commit
   - Can revert individual phase commits if issues found
   - Git makes recovery straightforward

3. **Testing failures**:
   - Run tests frequently during implementation
   - Fix issues incrementally, don't batch fixes
   - Revert problematic changes immediately

**Best Practices**:
- Commit frequently (after each task)
- Test frequently (after each phase)
- Verify before moving forward
- Document issues as they occur

---

## Next Steps

1. **Review & Approve** this master plan
2. **Clarify any questions** or adjustments
3. **Start Phase 1** with commit archaeology audit
4. **Execute phases sequentially** with approval gates
5. **Document results** in final Greenfield Report

Once approved, Phase 1 (Commit History Archaeology) will begin with a detailed commit audit and rebase strategy design.

---

**Document Version**: 1.0
**Created**: 2025-12-21
**Target Completion**: End of Week 3 (2025-01-09)
**pgGit Status**: Pre-greenfield transformation
