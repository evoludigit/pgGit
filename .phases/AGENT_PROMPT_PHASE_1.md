# Agent Prompt: Execute pgGit Phase 1 - Critical Fixes

## Context

You are tasked with executing Phase 1 of the pgGit quality improvement roadmap. This phase fixes critical issues that could damage credibility and prevent safe usage.

**Repository**: `/home/lionel/code/pggit`
**Current Quality**: 6.5/10
**Target Quality**: 7.5/10
**Focus**: Quality over speed - no hard deadlines

---

## Skills Available

For this phase, reference these skills as needed:

- **TDD Workflows**: Your CLAUDE.md describes RED → GREEN → REFACTOR → QA phases
- **Delegation Strategy**: Use local AI models (vLLM) for pattern-based tasks
- **Database Patterns**: SQL best practices and naming conventions

---

## Your Mission

Execute all 6 steps in `phase-1-critical-fixes.md` to bring pgGit from experimental to trustworthy:

1. **[HIGH] Audit and Fix Documentation** - Ensure all docs are accurate
2. **[LOW] Add SECURITY.md** - Vulnerability reporting process
3. **[HIGH] Integrate pgTAP Testing** - Structured test framework (use TDD workflow)
4. **[MEDIUM] Fix All CI Test Failures** - Green pipeline
5. **[MEDIUM] Add Test Coverage Tracking** - Visibility into tested functions
6. **[LOW] Document Module Architecture** - Clear core/ vs sql/ explanation

**Parallel Execution**: Steps 1 & 2 can run in parallel, as can Steps 5 & 6.

---

## Step-by-Step Instructions

### Before You Start

1. **Read the phase plan**:
   ```bash
   cat .phases/phase-1-critical-fixes.md
   ```

2. **Understand the current state**:
   - Read README.md
   - Check current git status
   - Review recent CI failures in GitHub Actions

3. **Create a tracking branch**:
   ```bash
   git checkout -b phase-1-critical-fixes
   ```

---

### Step 1: Audit and Fix Documentation (3 days)

**Goal**: Remove misleading claims from documentation, especially security features that don't exist.

**Actions**:

1. **Find all function references in docs**:
   ```bash
   # Extract all pggit.* function calls from markdown
   grep -rh "pggit\.[a-z_]*(" docs/ | \
     sed 's/.*pggit\.\([a-z_]*\)(.*/\1/' | \
     sort -u > /tmp/doc-functions.txt
   ```

2. **Find all actual implemented functions**:
   ```bash
   # Extract from SQL files
   grep -rh "CREATE OR REPLACE FUNCTION pggit\." core/sql sql/ | \
     sed 's/.*pggit\.\([a-z_]*\)(.*/\1/' | \
     sort -u > /tmp/impl-functions.txt
   ```

3. **Find mismatches**:
   ```bash
   comm -23 /tmp/doc-functions.txt /tmp/impl-functions.txt
   ```

4. **Fix docs/guides/Security.md**:
   - Read the file completely
   - For each function mentioned (like `configure_security`, `create_user`, `check_gdpr_compliance`):
     - Check if it exists in SQL files
     - If NOT exists: Either remove section OR add "🚧 PLANNED" badge
   - Add disclaimer at top: "⚠️ v0.1.x is experimental. Many features listed are planned for future releases."

5. **Add status badges to all features**:
   - ✅ Implemented and tested
   - 🧪 Experimental (implemented but not production-ready)
   - 🚧 Planned (designed but not implemented)
   - 📝 Design phase (idea only)

6. **Update README.md feature matrix** with accurate status

**Verification**:
```bash
# Ensure no undocumented claims
make verify-docs  # (you may need to create this target)
```

**Commit**:
```bash
git add docs/
git commit -m "docs: Fix misleading documentation and add feature status badges [Phase 1.1]"
```

---

### Step 2: Add SECURITY.md (1 day)

**Goal**: Provide clear vulnerability reporting process.

**Actions**:

1. **Create SECURITY.md** in repo root using the template from phase-1-critical-fixes.md

2. **Key sections to include**:
   - Supported versions table
   - How to report vulnerabilities (email, NOT public issues)
   - Response timeline (48h acknowledgment, 7d update, 90d disclosure)
   - Security best practices link
   - Known limitations section
   - Security features status table

3. **Update email contact** with your actual email

4. **Link from README.md**:
   ```markdown
   ## Security

   See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.
   ```

5. **Configure GitHub security tab**:
   - Go to repository Settings → Security
   - Enable security advisories
   - Add SECURITY.md location

**Verification**:
```bash
test -f SECURITY.md && echo "✅ Created" || echo "❌ Missing"
grep -q "SECURITY.md" README.md && echo "✅ Linked" || echo "❌ Not linked"
```

**Commit**:
```bash
git add SECURITY.md README.md
git commit -m "security: Add vulnerability reporting process [Phase 1.2]"
```

---

### Step 3: Integrate pgTAP Testing (4 days)

**Goal**: Replace manual tests with structured pgTAP framework.

**Actions**:

1. **Install pgTAP** (if not already available):
   ```bash
   # Check if available
   psql -c "CREATE EXTENSION IF NOT EXISTS pgtap" || {
     echo "pgTAP not installed. Installing..."
     # Installation depends on your OS
     # Ubuntu: sudo apt-get install postgresql-15-pgtap
     # From source: git clone https://github.com/theory/pgtap && make install
   }
   ```

2. **Create pgTAP test directory**:
   ```bash
   mkdir -p tests/pgtap
   ```

3. **Convert existing tests to pgTAP format**:

   **Example - tests/pgtap/test-core.sql**:
   ```sql
   BEGIN;
   SELECT plan(10);

   -- Test 1: Schema exists
   SELECT has_schema('pggit', 'pggit schema should exist');

   -- Test 2: Core tables exist
   SELECT has_table('pggit', 'objects', 'pggit.objects table exists');
   SELECT has_table('pggit', 'history', 'pggit.history table exists');
   SELECT has_table('pggit', 'branches', 'pggit.branches table exists');

   -- Test 3: Event triggers exist
   SELECT has_trigger('pggit_ddl_trigger', 'DDL trigger exists');
   SELECT has_trigger('pggit_drop_trigger', 'DROP trigger exists');

   -- Test 4: Core functions exist
   SELECT has_function('pggit', 'ensure_object', 'ensure_object function exists');
   SELECT has_function('pggit', 'increment_version', 'increment_version function exists');

   -- Test 5: Functional test - version tracking
   CREATE TABLE test_versioning (id SERIAL PRIMARY KEY);
   SELECT lives_ok(
       $$SELECT pggit.get_version('test_versioning')$$,
       'get_version works on new table'
   );

   -- Test 6: Version format validation
   SELECT matches(
       (SELECT pggit.get_version('test_versioning')::text),
       '^\d+\.\d+\.\d+$',
       'Version is in semver format (X.Y.Z)'
   );

   DROP TABLE test_versioning CASCADE;

   SELECT * FROM finish();
   ROLLBACK;
   ```

4. **Convert at least 3 test files**:
   - `tests/pgtap/test-core.sql` - Core functionality
   - `tests/pgtap/test-git.sql` - Git operations (branches, commits)
   - `tests/pgtap/test-configuration.sql` - Configuration system

5. **Create test runner script**:
   ```bash
   #!/bin/bash
   # File: tests/run-pgtap.sh

   set -e

   DB_NAME=${1:-postgres}

   echo "Running pgTAP tests on $DB_NAME..."

   # Install pgGit first
   psql -d $DB_NAME -f sql/install.sql > /dev/null

   # Run tests with pg_prove
   pg_prove -d $DB_NAME tests/pgtap/*.sql

   echo "✅ All tests passed"
   ```

6. **Update Makefile**:
   ```makefile
   test-pgtap:
       @echo "Running pgTAP tests..."
       @bash tests/run-pgtap.sh

   test: test-pgtap
   ```

7. **Add to CI** (.github/workflows/test-with-fixes.yml):
   ```yaml
   - name: Install pgTAP
     run: |
       sudo apt-get update
       sudo apt-get install -y postgresql-15-pgtap

   - name: Run pgTAP tests
     env:
       PGPASSWORD: postgres
     run: |
       pg_prove -h localhost -U postgres -d test_db tests/pgtap/*.sql
   ```

**Verification**:
```bash
# Run tests locally
make test-pgtap

# Should output:
# tests/pgtap/test-core.sql .. ok
# tests/pgtap/test-git.sql ... ok
# All tests successful.
```

**Commit**:
```bash
git add tests/pgtap/ tests/run-pgtap.sh Makefile .github/workflows/
git commit -m "test: Integrate pgTAP testing framework [Phase 1.3]"
```

---

### Step 4: Fix All CI Test Failures (3 days)

**Goal**: Green CI pipeline with all tests passing.

**Actions**:

1. **Review recent CI failures**:
   ```bash
   gh run list --workflow=test-with-fixes.yml --limit 10
   gh run view <run-id>  # Get details on failures
   ```

2. **Common issues to fix**:
   - Module loading order (load core before extensions)
   - Missing dependencies (pgcrypto not created)
   - Table/function conflicts (objects already exist)
   - Temporary table permission issues

3. **Fix test isolation**:
   - Each test should clean up after itself
   - Use transactions: BEGIN ... ROLLBACK
   - Drop test tables/schemas

4. **Fix PostgreSQL version compatibility**:
   - Test on PostgreSQL 15, 16, 17
   - Handle version-specific features (compression in PG17)

5. **Update CI workflow** to test all versions:
   ```yaml
   strategy:
     matrix:
       pg-version: [15, 16, 17]

   services:
     postgres:
       image: postgres:${{ matrix.pg-version }}
   ```

6. **Run tests locally for each PG version**:
   ```bash
   # Using Docker
   docker run -e POSTGRES_PASSWORD=postgres -d -p 5432:5432 postgres:15
   make test-pgtap
   docker stop <container-id>

   # Repeat for 16, 17
   ```

**Verification**:
```bash
# All workflows should pass
gh run list --workflow=test-with-fixes.yml --limit 1

# Local tests pass
make test-pgtap
```

**Commit**:
```bash
git add .github/workflows/ core/sql/ sql/ tests/
git commit -m "ci: Fix all test failures and add multi-version testing [Phase 1.4]"
```

---

### Step 5: Add Test Coverage Tracking (2 days)

**Goal**: Visibility into which functions are tested.

**Actions**:

1. **Create coverage report SQL**:
   ```sql
   -- File: tests/coverage-report.sql

   \echo '========================================'
   \echo 'pgGit Test Coverage Report'
   \echo '========================================'

   -- Total functions
   SELECT COUNT(*) as total_functions
   FROM information_schema.routines
   WHERE routine_schema = 'pggit';

   -- Functions with tests (heuristic: mentioned in test files)
   -- This is a simple approach; more sophisticated tracking needs pgTAP integration

   -- List untested functions
   \echo ''
   \echo 'Potentially Untested Functions:'
   \echo '================================'

   SELECT routine_name
   FROM information_schema.routines
   WHERE routine_schema = 'pggit'
     AND routine_name NOT IN (
       -- Functions we know are tested
       -- Parse from pgTAP test descriptions
       'ensure_object',
       'increment_version',
       'get_version',
       'create_branch',
       'checkout',
       'commit'
       -- Add more as you convert tests
     )
   ORDER BY routine_name;
   ```

2. **Add coverage to Makefile**:
   ```makefile
   test-coverage:
       @echo "Generating test coverage report..."
       @psql -f tests/coverage-report.sql
   ```

3. **Add to CI**:
   ```yaml
   - name: Test coverage report
     env:
       PGPASSWORD: postgres
     run: |
       psql -h localhost -U postgres -d test_db -f tests/coverage-report.sql
   ```

4. **Set baseline target**: Document current coverage and set >50% target

5. **Create GitHub badge** (optional):
   - Use shields.io or similar
   - Add to README: `![Coverage](https://img.shields.io/badge/coverage-XX%25-green)`

**Verification**:
```bash
make test-coverage

# Should output something like:
# Total Functions: 47
# Tested Functions: 28
# Coverage: 59.57%
```

**Commit**:
```bash
git add tests/coverage-report.sql Makefile .github/workflows/
git commit -m "test: Add test coverage tracking and reporting [Phase 1.5]"
```

---

### Step 6: Document Module Architecture (2 days)

**Goal**: Clear explanation of core/ vs sql/ and module dependencies.

**Actions**:

1. **Create architecture doc**:
   ```bash
   mkdir -p docs/architecture
   ```

2. **Write docs/architecture/MODULES.md** using template from phase-1-critical-fixes.md

3. **Key sections**:
   - Directory structure diagram
   - Module dependency graph
   - Loading order (001, 002, 003...)
   - Core vs. Extensions distinction
   - Installation options (full, core-only, selective)
   - Feature matrix (what's in which module)

4. **Create visual dependency graph** (optional):
   ```bash
   # Using graphviz
   cat > docs/architecture/modules.dot <<EOF
   digraph modules {
     "001_schema" -> "002_event_triggers"
     "002_event_triggers" -> "003_migration_functions"
     "003_migration_functions" -> "006_git_implementation"
     "006_git_implementation" -> "pggit_configuration"
     "006_git_implementation" -> "pggit_cqrs_support"
   }
   EOF

   dot -Tpng docs/architecture/modules.dot -o docs/architecture/modules.png
   ```

5. **Link from main README**:
   ```markdown
   ## Architecture

   - [Module Architecture](docs/architecture/MODULES.md) - Core vs. extensions
   - [Architecture Decisions](docs/Architecture_Decision.md) - Design rationale
   ```

**Verification**:
```bash
test -f docs/architecture/MODULES.md && echo "✅ Created" || echo "❌ Missing"
grep -q "Module Architecture" README.md && echo "✅ Linked" || echo "❌ Not linked"
```

**Commit**:
```bash
git add docs/architecture/ README.md
git commit -m "docs: Document module architecture and dependencies [Phase 1.6]"
```

---

## Final Phase 1 Verification

After completing all 6 steps:

```bash
# 1. Documentation accuracy
# Manually review docs/guides/Security.md - no misleading claims?

# 2. Security policy
test -f SECURITY.md && echo "✅" || echo "❌"

# 3. Tests passing
make test-pgtap

# 4. CI green
gh run list --workflow=test-with-fixes.yml --limit 1
# Should show ✅ green checkmark

# 5. Coverage tracked
make test-coverage
# Should show >50% coverage

# 6. Architecture documented
test -f docs/architecture/MODULES.md && echo "✅" || echo "❌"

# 7. All commits clean
git log --oneline | head -10
# Should see 6 phase-1 commits
```

---

## Create Pull Request

Once all steps complete and verified:

```bash
# Push branch
git push origin phase-1-critical-fixes

# Create PR
gh pr create \
  --title "Phase 1: Critical Fixes - Documentation, Testing, Security" \
  --body "$(cat <<EOF
## Phase 1 Completion

This PR implements all 6 steps of Phase 1 from the quality roadmap.

### Changes

- ✅ Fixed misleading documentation (especially Security.md)
- ✅ Added SECURITY.md with vulnerability reporting process
- ✅ Integrated pgTAP testing framework
- ✅ Fixed all CI test failures
- ✅ Added test coverage tracking (current: XX%)
- ✅ Documented module architecture

### Quality Improvement

- Before: 6.5/10
- After: 7.5/10

### Testing

All tests passing:
- pgTAP tests: XX tests in 3 files
- CI workflows: All green ✅
- PostgreSQL versions: 15, 16, 17

### Verification

\`\`\`bash
make test-pgtap
make test-coverage
\`\`\`

### Next Steps

Ready for Phase 2: Quality Foundation
- SQL linting
- Complete API reference
- Security audit

---

Closes #(issue-number-if-exists)
EOF
)"
```

---

## Important Guidelines

### DO

✅ **Follow the phase plan exactly** - It's been carefully designed
✅ **Test after each step** - Don't wait until the end
✅ **Commit frequently** - One commit per step
✅ **Update documentation** as you go
✅ **Ask questions** if requirements are unclear
✅ **Verify everything** using the provided commands

### DO NOT

❌ **Add new features** - Phase 1 is fixes only
❌ **Refactor working code** - Don't break what works
❌ **Skip verification steps** - They catch issues early
❌ **Change public API** - Maintain backward compatibility
❌ **Rush** - Quality over speed

---

## Success Criteria

Phase 1 is complete when:

- [ ] All documentation is accurate (no misleading claims)
- [ ] SECURITY.md exists and is linked from README
- [ ] pgTAP tests are running (minimum 3 test files)
- [ ] All CI workflows are green (100% pass rate)
- [ ] Test coverage is tracked and >50%
- [ ] Module architecture is documented
- [ ] Pull request is created and reviewed
- [ ] Quality has improved from 6.5/10 to 7.5/10

---

## Effort Levels

| Step | Effort | Why |
|------|--------|-----|
| 1. Documentation audit | HIGH | Requires careful analysis of all docs vs implementation |
| 2. SECURITY.md | LOW | Template-based document creation |
| 3. pgTAP integration | HIGH | Design tests, convert format, integrate CI - use TDD |
| 4. Fix CI failures | MEDIUM | Debug and fix test issues across PG versions |
| 5. Coverage tracking | MEDIUM | Create tracking SQL and integrate reporting |
| 6. Module docs | LOW | Document existing architecture |

**Note**: Focus on quality, not speed. No hard deadlines.

---

## Getting Help

If stuck on any step:

1. **Read the detailed phase plan**: `.phases/phase-1-critical-fixes.md`
2. **Check existing code**: Look for similar patterns in the codebase
3. **Review test examples**: See how other PostgreSQL extensions do it
4. **Ask the user**: Clarify requirements before proceeding

---

## Tools You'll Need

- `psql` - PostgreSQL client
- `pg_prove` - pgTAP test runner
- `gh` - GitHub CLI
- `git` - Version control
- Text editor with SQL syntax highlighting

---

## Context Files to Read First

Before starting, familiarize yourself with:

1. `.phases/phase-1-critical-fixes.md` - Full detailed plan
2. `README.md` - Project overview
3. `core/sql/001_schema.sql` - Base schema
4. `tests/test-core.sql` - Current test examples
5. `.github/workflows/test-with-fixes.yml` - Current CI setup

---

## Final Notes

**This is critical work**. Phase 1 fixes issues that could damage the project's credibility. Take your time, test thoroughly, and ensure accuracy over speed.

After Phase 1, pgGit will be ready for marketing and early adopters. The foundation will be solid for building Phases 2 and 3.

**Good luck! 🚀**
