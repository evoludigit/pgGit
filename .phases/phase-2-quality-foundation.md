# Phase 2: Quality Foundation

**Quality Gain**: 7.5/10 → 8.5/10
**Prerequisites**: Phase 1 completed (all acceptance criteria met)

---

## Pre-Phase Checklist

Before starting Phase 2:

**Prerequisites**:
- [ ] Phase 1 PR merged to main
- [ ] All Phase 1 acceptance criteria verified
- [ ] Clean git status (no uncommitted changes)
- [ ] pgTAP tests passing from Phase 1
- [ ] Test coverage ≥50% from Phase 1

**Setup**:
```bash
# Sync with main
git checkout main
git pull origin main

# Create phase branch
git checkout -b phase-2-quality-foundation

# Verify Phase 1 completion
make test-pgtap     # Should pass
make test-coverage  # Should show ≥50%
test -f SECURITY.md && echo "✅ Phase 1 complete"

# Install additional tools
pip install sqlfluff pre-commit semgrep
```

**Focus**:
- Build quality systems, not features
- Automate what can be automated
- Document everything thoroughly

---

## Objective

Build robust quality infrastructure: linting, complete documentation, security review, and community templates. Establish processes that maintain quality as the project grows.

---

## Context

Phase 1 fixed critical issues. Phase 2 establishes quality systems:
- Automated code quality checks (linting, pre-commit)
- Complete and accurate API documentation
- Community security audit
- Contributor workflow templates
- Performance baseline

These create a foundation for sustainable development.

---

## Files to Create/Modify

### Quality Tools
- `.sqlfluff` - SQL linting configuration
- `.pre-commit-config.yaml` - Pre-commit hooks
- `.editorconfig` - Editor consistency
- `pyproject.toml` - Python tool configuration

### Documentation
- `docs/reference/API_COMPLETE.md` - Full function reference
- `docs/contributing/CODE_STYLE.md` - Style guide
- `docs/contributing/TESTING.md` - Test strategy
- `docs/benchmarks/BASELINE.md` - Performance metrics

### Community
- `.github/ISSUE_TEMPLATE/bug_report.md`
- `.github/ISSUE_TEMPLATE/feature_request.md`
- `.github/ISSUE_TEMPLATE/security_vulnerability.md`
- `.github/PULL_REQUEST_TEMPLATE.md`
- `CODE_OF_CONDUCT.md`

### Code
- `core/sql/*.sql` - Add inline comments
- `sql/*.sql` - Add function documentation
- Resolve all TODO/FIXME items

---

## Step Dependencies

Steps can be executed in this order:

```
Phase 2 Flow:
┌─────────────────────────────────────────────────┐
│ Step 1: SQL Linting [MEDIUM]                   │
│ Step 2: Pre-commit Hooks [LOW]  (parallel)     │
└──────────────┬──────────────────────────────────┘
               ↓
┌─────────────────────────────────────────────────┐
│ Step 3: API Documentation [HIGH]               │
└──────────────┬──────────────────────────────────┘
               ↓
┌─────────────────────────────────────────────────┐
│ Step 4: Security Audit [MEDIUM]                │
└──────────────┬──────────────────────────────────┘
               ↓
┌──────────────┴──────────────────────────────────┐
│ Step 5: Issue/PR Templates [LOW]               │
│ Step 6: Code of Conduct [LOW]  (parallel)      │
│ Step 7: Resolve TODOs [MEDIUM] (parallel)      │
└──────────────┬──────────────────────────────────┘
               ↓
┌─────────────────────────────────────────────────┐
│ Step 8: Performance Baseline [MEDIUM]          │
└─────────────────────────────────────────────────┘
```

**Parallel Execution Possible**:
- Steps 1 & 2 (both setup quality tools)
- Steps 5, 6, 7 (independent documentation tasks)

**Sequential Required**:
- Step 3 depends on Step 1 (linting should pass before documenting)
- Step 4 depends on Step 3 (audit needs complete documentation)
- Step 8 depends on Steps 1-7 (baseline after quality systems in place)

---

## Implementation Steps

### Step 1: Add SQL Linting with sqlfluff [EFFORT: MEDIUM]

**Goal**: Automated SQL code quality checks.

```ini
# .sqlfluff configuration
[sqlfluff]
dialect = postgres
templater = raw
max_line_length = 100
exclude_rules = L003,L009,L016

[sqlfluff:rules]
tab_space_size = 4
indent_unit = space

[sqlfluff:rules:L010]
# Keywords - use consistent style (not forced lowercase)
capitalisation_policy = consistent

[sqlfluff:rules:L014]
# Unquoted identifiers should be lowercase
capitalisation_policy = lower

[sqlfluff:rules:L030]
# Function names should be lowercase
capitalisation_policy = lower

[sqlfluff:rules:L042]
# Join clause should be on new line
forbid_subquery_in = join

[sqlfluff:rules:L052]
# Semi-colon formatting
multiline_newline = True

[sqlfluff:indentation]
indented_joins = True
indented_using_on = True
template_blocks_indent = True
```

**Add to Makefile**:
```makefile
# Linting targets
lint:
	@echo "Linting SQL files..."
	@sqlfluff lint core/sql sql tests

lint-fix:
	@echo "Auto-fixing SQL issues..."
	@sqlfluff fix core/sql sql tests

lint-ci:
	@echo "Linting for CI (no auto-fix)..."
	@sqlfluff lint --format github-annotation core/sql sql tests
```

**Add to CI**:
```yaml
- name: Lint SQL
  run: |
    pip install sqlfluff sqlfluff-templater-dbt
    make lint-ci
```

**Delegation Strategy**:

🤖 **Can Delegate to Local Model**:
- Running `sqlfluff fix` on files with auto-fixable issues
- Applying consistent formatting across multiple files
- Adding trailing commas, fixing indentation

❌ **Keep with Claude**:
- Deciding which linting rules to enable/disable
- Fixing complex SQL that sqlfluff can't auto-fix
- Resolving rule conflicts

**Verification**:
```bash
# Install sqlfluff
pip install sqlfluff

# Run linting
make lint

# ✅ PASS CRITERIA:
# - All files show PASS
# - Exit code 0
# - No violations reported

# ❌ FAIL CRITERIA:
# - Any file shows FAIL
# - Exit code non-zero
# - Violations found

# Should output:
# == [core/sql/001_schema.sql] PASS
# == [core/sql/002_event_triggers.sql] PASS
# ...
# All Passed!
```

**Rollback Strategy**:
```bash
# If linting config causes issues
git checkout HEAD -- .sqlfluff Makefile .github/workflows/

# If auto-fixes broke SQL
git checkout HEAD -- core/sql/ sql/
```

**Acceptance Criteria**:
- [ ] .sqlfluff configuration created with PostgreSQL-appropriate rules
- [ ] All SQL files pass linting (0 violations)
- [ ] CI runs sqlfluff on every commit
- [ ] Make targets for lint/lint-fix work
- [ ] Linting rule documentation in docs/contributing/CODE_STYLE.md

---

### Step 2: Pre-commit Hooks [EFFORT: LOW]

**Goal**: Catch issues before they're committed.

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
        args: ['--maxkb=500']
      - id: check-merge-conflict
      - id: check-case-conflict

  - repo: https://github.com/sqlfluff/sqlfluff
    rev: 2.3.5
    hooks:
      - id: sqlfluff-lint
        files: \.(sql)$
        args: ['--dialect', 'postgres']
      - id: sqlfluff-fix
        files: \.(sql)$
        args: ['--dialect', 'postgres']

  - repo: https://github.com/koalaman/shellcheck-precommit
    rev: v0.9.0
    hooks:
      - id: shellcheck
        args: ['--severity=warning']

  - repo: https://github.com/igorshubovych/markdownlint-cli
    rev: v0.37.0
    hooks:
      - id: markdownlint
        args: ['--fix']

  - repo: local
    hooks:
      - id: test-core
        name: Run core tests
        entry: make test-core
        language: system
        pass_filenames: false
        stages: [pre-push]
```

**Setup instructions** (add to CONTRIBUTING.md):
```markdown
## Setting Up Pre-commit Hooks

1. Install pre-commit:
   ```bash
   pip install pre-commit
   ```

2. Install the hooks:
   ```bash
   cd pggit
   pre-commit install
   pre-commit install --hook-type pre-push
   ```

3. Test the hooks:
   ```bash
   pre-commit run --all-files
   ```

Now hooks run automatically on `git commit` and `git push`.
```

**Verification**:
```bash
# Install and test
pre-commit install
pre-commit run --all-files

# Should check:
# - Trailing whitespace
# - SQL linting
# - Shell script errors
# - Markdown formatting
```

**Acceptance Criteria**:
- [ ] .pre-commit-config.yaml created
- [ ] Setup instructions in CONTRIBUTING.md
- [ ] Hooks catch common issues
- [ ] CI enforces same checks

---

### Step 3: Complete API Reference [EFFORT: HIGH]

**Goal**: Document every public function with examples.

```sql
-- Generate API reference from function signatures
-- File: scripts/generate-api-docs.sql

\o /tmp/api-reference.md

SELECT format(E'# pgGit API Reference\n\nComplete reference for all pgGit functions.\n\n');

-- For each function, generate documentation
SELECT format(
    E'## %s.%s\n\n'
    E'**Signature**: `%s`\n\n'
    E'**Description**: %s\n\n'
    E'**Parameters**:\n%s\n\n'
    E'**Returns**: `%s`\n\n'
    E'**Example**:\n```sql\n%s\n```\n\n'
    E'---\n\n',
    n.nspname,
    p.proname,
    pg_get_functiondef(p.oid),
    COALESCE(d.description, '_No description available_'),
    -- Parameter list
    (
        SELECT string_agg(
            format('- `%s` (%s): %s',
                param_name,
                param_type,
                COALESCE(param_desc, '_No description_')
            ),
            E'\n'
        )
        FROM unnest(p.proargnames, p.proargtypes::regtype[])
        AS t(param_name, param_type)
    ),
    pg_get_function_result(p.oid),
    -- Example (from comments or placeholder)
    format('SELECT %s.%s();', n.nspname, p.proname)
)
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
LEFT JOIN pg_description d ON p.oid = d.objoid
WHERE n.nspname = 'pggit'
ORDER BY p.proname;

\o
```

**Add COMMENT ON statements**:
```sql
-- Example: Documenting functions in core/sql/006_git_implementation.sql

COMMENT ON FUNCTION pggit.create_branch(TEXT) IS
'Creates a new Git-style branch for schema versioning.

Parameters:
  - branch_name: Name of the branch (must be unique)

Returns: branch_id (integer)

Example:
  SELECT pggit.create_branch(''feature/user-auth'');

See also: pggit.checkout(), pggit.merge()';

COMMENT ON FUNCTION pggit.checkout(TEXT) IS
'Switches to a different branch or commit.

Parameters:
  - ref_name: Branch name, tag, or commit hash

Returns: void

Side effects:
  - Changes current HEAD
  - May restore previous schema state

Example:
  SELECT pggit.checkout(''main'');
  SELECT pggit.checkout(''v1.0.0'');
  SELECT pggit.checkout(''abc123'');

Warnings:
  - Uncommitted changes may be lost
  - Use pggit.status() before checkout';
```

**Process**:
1. Add COMMENT ON for all 650+ functions
2. Run generation script
3. Manual review and enhancement
4. Add usage examples from tests
5. Cross-reference related functions

**Verification**:
```bash
# Generate API docs
psql -f scripts/generate-api-docs.sql

# Check completeness
TOTAL_FUNCS=$(psql -tA -c "SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = 'pggit'")
DOCUMENTED=$(psql -tA -c "SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid LEFT JOIN pg_description d ON p.oid = d.objoid WHERE n.nspname = 'pggit' AND d.description IS NOT NULL")

echo "Documented: $DOCUMENTED / $TOTAL_FUNCS"
```

**Acceptance Criteria**:
- [ ] All public functions have COMMENT ON
- [ ] API reference generated automatically
- [ ] Each function has example usage
- [ ] Related functions cross-referenced
- [ ] 100% documentation coverage

---

### Step 4: Security Audit (Community Review) [EFFORT: MEDIUM]

**Goal**: Third-party review of security-critical code.

**Audit Scope**:
1. SQL injection vulnerabilities
2. Event trigger privilege escalation
3. Data exposure in audit trail
4. Permission handling in DDL capture
5. Input validation

**Create audit checklist**:
```markdown
# Security Audit Checklist

## SQL Injection
- [ ] All dynamic SQL uses quote_ident() or quote_literal()
- [ ] No string concatenation for SQL generation
- [ ] format() used with %I and %L specifiers

## Privilege Escalation
- [ ] Event triggers don't bypass permissions
- [ ] No SECURITY DEFINER without explicit checks
- [ ] Temporary object exclusion prevents temp table attacks

## Data Exposure
- [ ] Audit trail doesn't leak sensitive data
- [ ] Query text sanitized before storage
- [ ] User-supplied content escaped

## Input Validation
- [ ] Branch names validated (no SQL injection)
- [ ] Object names checked against catalog
- [ ] No command execution from user input

## Access Control
- [ ] Schema permissions documented
- [ ] Function permissions appropriate
- [ ] Row-level security considerations documented
```

**Invite community review**:
```markdown
# GitHub Issue: Security Audit Request

**Title**: 🔒 Request for Security Audit - v0.1.0

We're seeking community security review before marking v0.2.0 as beta.

**Scope**:
- Core event triggers (core/sql/002_event_triggers.sql)
- Git implementation (core/sql/006_git_implementation.sql)
- DDL parsing (core/sql/007_ddl_parser.sql)

**Focus Areas**:
- SQL injection vulnerabilities
- Privilege escalation risks
- Data leakage in audit logs

**How to Participate**:
1. Review code in `core/sql/`
2. Report findings to SECURITY.md email
3. Optional: Public disclosure after fix

**Recognition**:
- Credit in SECURITY.md
- Listed in release notes
- Optional GitHub sponsor link

**Timeline**: 2 weeks for review, 2 weeks for fixes

---

Also posted on:
- r/PostgreSQL
- PostgreSQL mailing list
- Twitter/X
```

**Verification**:
```bash
# Run automated security checks
semgrep --config=p/sql-injection core/sql/ sql/

# Check for common patterns
grep -rn "EXECUTE.*||" core/sql/ sql/  # String concatenation
grep -rn "SECURITY DEFINER" core/sql/ sql/  # Elevated privileges
```

**Acceptance Criteria**:
- [ ] Security audit request published
- [ ] At least 2 external reviewers
- [ ] All findings addressed or documented
- [ ] semgrep checks added to CI
- [ ] Security review summary in docs

---

### Step 5: Issue and PR Templates [EFFORT: LOW]

**Goal**: Standardized contribution workflow.

```markdown
# .github/ISSUE_TEMPLATE/bug_report.md
---
name: Bug Report
about: Report a bug in pgGit
title: '[BUG] '
labels: bug
assignees: ''
---

## Bug Description
<!-- Clear and concise description -->

## Environment
- pgGit version: <!-- e.g., 0.1.0 -->
- PostgreSQL version: <!-- e.g., 15.4 -->
- OS: <!-- e.g., Ubuntu 22.04 -->

## Steps to Reproduce
1.
2.
3.

## Expected Behavior
<!-- What should happen -->

## Actual Behavior
<!-- What actually happens -->

## SQL to Reproduce
```sql
-- Paste minimal SQL to reproduce
```

## Error Messages
```
Paste full error message here
```

## Additional Context
<!-- Any other relevant information -->

## Checklist
- [ ] I've searched existing issues
- [ ] I've tested on a clean database
- [ ] I can reproduce consistently
- [ ] I've included all relevant information
```

```markdown
# .github/ISSUE_TEMPLATE/feature_request.md
---
name: Feature Request
about: Suggest a feature for pgGit
title: '[FEATURE] '
labels: enhancement
assignees: ''
---

## Feature Description
<!-- Clear description of the feature -->

## Use Case
<!-- Why is this feature needed? -->

## Proposed Solution
<!-- How should this work? -->

## Example Usage
```sql
-- Show how the feature would be used
```

## Alternatives Considered
<!-- Other ways to solve this problem -->

## Additional Context
<!-- Any other relevant information -->

## Checklist
- [ ] I've searched existing features/issues
- [ ] This fits pgGit's scope
- [ ] I'm willing to help implement
```

```markdown
# .github/PULL_REQUEST_TEMPLATE.md

## Description
<!-- Describe your changes -->

## Related Issue
Fixes #<!-- issue number -->

## Type of Change
- [ ] Bug fix (non-breaking change)
- [ ] New feature (non-breaking change)
- [ ] Breaking change (fix or feature)
- [ ] Documentation update

## Testing
<!-- How was this tested? -->

### Test Environment
- PostgreSQL version:
- OS:

### Test Results
```
Paste test output here
```

## Checklist
- [ ] My code follows the style guide
- [ ] I've run `make lint`
- [ ] I've added tests for my changes
- [ ] All tests pass (`make test`)
- [ ] I've updated documentation
- [ ] I've added COMMENT ON for new functions
- [ ] I've updated CHANGELOG.md
- [ ] No new TODO/FIXME without issue

## Breaking Changes
<!-- List any breaking changes -->

## Documentation
<!-- Link to updated docs or N/A -->

## Screenshots (if applicable)
<!-- Add screenshots for UI changes -->
```

**Verification**:
```bash
# Check templates exist
ls .github/ISSUE_TEMPLATE/
# Should show: bug_report.md, feature_request.md, security_vulnerability.md

test -f .github/PULL_REQUEST_TEMPLATE.md && echo "✅ PR template" || echo "❌ Missing"
```

**Acceptance Criteria**:
- [ ] Bug report template created
- [ ] Feature request template created
- [ ] Security vulnerability template created
- [ ] PR template created
- [ ] Templates tested with dummy issues
- [ ] CONTRIBUTING.md references templates

---

### Step 6: CODE_OF_CONDUCT.md [EFFORT: LOW]

**Goal**: Inclusive community guidelines.

```markdown
# Contributor Covenant Code of Conduct

## Our Pledge

We as members, contributors, and leaders pledge to make participation in our
community a harassment-free experience for everyone, regardless of age, body
size, visible or invisible disability, ethnicity, sex characteristics, gender
identity and expression, level of experience, education, socio-economic status,
nationality, personal appearance, race, religion, or sexual identity
and orientation.

## Our Standards

Examples of behavior that contributes to a positive environment:

* Using welcoming and inclusive language
* Being respectful of differing viewpoints and experiences
* Gracefully accepting constructive criticism
* Focusing on what is best for the community
* Showing empathy towards other community members

Examples of unacceptable behavior:

* The use of sexualized language or imagery
* Trolling, insulting or derogatory comments, and personal or political attacks
* Public or private harassment
* Publishing others' private information without explicit permission
* Other conduct which could reasonably be considered inappropriate

## Enforcement Responsibilities

Community leaders are responsible for clarifying and enforcing our standards of
acceptable behavior and will take appropriate and fair corrective action in
response to any behavior that they deem inappropriate, threatening, offensive,
or harmful.

## Scope

This Code of Conduct applies within all community spaces, and also applies when
an individual is officially representing the community in public spaces.

## Enforcement

Instances of abusive, harassing, or otherwise unacceptable behavior may be
reported to the community leaders responsible for enforcement at
[YOUR-EMAIL]@[DOMAIN].

All complaints will be reviewed and investigated promptly and fairly.

## Attribution

This Code of Conduct is adapted from the [Contributor Covenant][homepage],
version 2.0, available at
https://www.contributor-covenant.org/version/2/0/code_of_conduct.html.

[homepage]: https://www.contributor-covenant.org
```

**Acceptance Criteria**:
- [ ] CODE_OF_CONDUCT.md created
- [ ] Linked from README and CONTRIBUTING
- [ ] Enforcement email configured
- [ ] Referenced in PR template

---

### Step 7: Resolve All TODO/FIXME Items [EFFORT: MEDIUM]

**Delegation Strategy**:

🤖 **Can Delegate to Local Model**:
- Finding all TODO/FIXME comments with grep
- Converting simple TODO comments to GitHub issues
- Removing completed TODO markers

❌ **Keep with Claude**:
- Deciding whether to implement or create issue
- Writing complex implementations for TODOs
- Prioritizing which TODOs to address

### Original Step 7: Resolve All TODO/FIXME Items

**Goal**: Clean up technical debt markers.

**Current TODOs** (from Phase 1 audit):
```bash
# Find all TODOs
grep -rn "TODO\|FIXME\|XXX\|HACK" core/sql sql --include="*.sql"

# Results:
# core/sql/010_transaction_safety.sql:123:-- TODO: Implement operation recovery logic
# core/sql/003_migration_functions.sql:456:-- TODO: Recreate dropped objects
# sql/003_migration_functions.sql:456:-- TODO: Recreate dropped objects
```

**Resolution Process**:

**TODO 1**: Operation recovery logic
```sql
-- Before (core/sql/010_transaction_safety.sql:123)
-- TODO: Implement operation recovery logic

-- After: Implement or create issue
CREATE OR REPLACE FUNCTION pggit.recover_failed_operation(
    operation_id UUID
) RETURNS BOOLEAN AS $$
DECLARE
    v_operation RECORD;
    v_success BOOLEAN;
BEGIN
    -- Get operation details
    SELECT * INTO v_operation
    FROM pggit.operations
    WHERE id = operation_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Operation % not found', operation_id;
    END IF;

    -- Attempt recovery based on operation type
    CASE v_operation.operation_type
        WHEN 'MERGE' THEN
            v_success := pggit.recover_merge(operation_id);
        WHEN 'CHECKOUT' THEN
            v_success := pggit.recover_checkout(operation_id);
        ELSE
            RAISE NOTICE 'No recovery available for %', v_operation.operation_type;
            v_success := FALSE;
    END CASE;

    RETURN v_success;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.recover_failed_operation(UUID) IS
'Attempts to recover from a failed operation.
Only supports MERGE and CHECKOUT operations.
Returns TRUE if recovery successful, FALSE otherwise.';
```

**TODO 2**: Recreate dropped objects
```sql
-- Before: format('-- TODO: Recreate %s %s', v_changes.object_type, v_changes.object_name)

-- After: Generate actual SQL
format(
    'CREATE %s %s AS %s',
    v_changes.object_type,
    quote_ident(v_changes.schema_name) || '.' || quote_ident(v_changes.object_name),
    v_changes.definition
)
```

**Verification**:
```bash
# After fixes, should return nothing
grep -rn "TODO\|FIXME" core/sql sql --include="*.sql"
```

**Acceptance Criteria**:
- [ ] All TODOs resolved (implemented or converted to issues)
- [ ] No FIXME in production code
- [ ] New TODO policy documented (must link to issue)

---

### Step 8: Performance Baseline [EFFORT: MEDIUM]

**Goal**: Measure and document current performance.

```sql
-- Create benchmark suite
-- File: tests/benchmarks/baseline.sql

\timing on

-- Benchmark 1: DDL tracking overhead
BEGIN;
CREATE TABLE benchmark_tracking (id SERIAL PRIMARY KEY);
\echo '=== Benchmark: DDL Tracking ==='
\timing

-- Create 1000 tables
DO $$
BEGIN
    FOR i IN 1..1000 LOOP
        EXECUTE format('CREATE TABLE bench_table_%s (id SERIAL, data TEXT)', i);
    END LOOP;
END $$;

SELECT COUNT(*) as tracked_objects FROM pggit.objects;
ROLLBACK;

-- Benchmark 2: Version retrieval
\echo '=== Benchmark: Version Retrieval ==='
SELECT pggit.get_version('benchmark_tracking') FROM generate_series(1, 10000);

-- Benchmark 3: History queries
\echo '=== Benchmark: History Query ==='
SELECT COUNT(*) FROM pggit.history WHERE created_at > NOW() - INTERVAL '1 day';

-- Benchmark 4: Branch creation
\echo '=== Benchmark: Branch Creation ==='
SELECT pggit.create_branch(format('bench_branch_%s', generate_series))
FROM generate_series(1, 100);

-- Benchmark 5: Commit overhead
\echo '=== Benchmark: Commit Operation ==='
\timing
SELECT pggit.commit('Benchmark commit');
\timing

-- Report results
\o /tmp/benchmark-results.md
SELECT format(
    E'# pgGit Performance Baseline\n\n'
    E'**Date**: %s\n'
    E'**PostgreSQL**: %s\n'
    E'**pgGit**: 0.1.0\n\n'
    E'## Results\n\n'
    E'| Metric | Value | Notes |\n'
    E'|--------|-------|-------|\n'
    E'| DDL Tracking Overhead | %s ms | 1000 table creates |\n'
    E'| Version Retrieval | %s ms | 10K lookups |\n'
    E'| History Query | %s ms | 1 day window |\n'
    E'| Branch Creation | %s ms | 100 branches |\n'
    E'| Commit Operation | %s ms | Single commit |\n',
    NOW(),
    version(),
    -- Results from timing
    '...', '...', '...', '...', '...'
);
\o
```

**Run benchmarks**:
```bash
# Execute benchmark suite
psql -f tests/benchmarks/baseline.sql > benchmarks/run-$(date +%Y%m%d).log

# Generate report
cat /tmp/benchmark-results.md
```

**Document in docs/benchmarks/BASELINE.md**:
```markdown
# Performance Baseline

## Environment
- PostgreSQL 17.0
- pgGit 0.1.0
- Ubuntu 22.04, 16GB RAM, SSD

## Baseline Metrics (2024-01-15)

| Operation | Throughput | Latency | Notes |
|-----------|-----------|---------|-------|
| DDL Capture | 1000/sec | 1ms avg | Event trigger overhead |
| Version Lookup | 50K/sec | 0.02ms | Indexed query |
| History Query | 10K/sec | 0.1ms | Last 1000 changes |
| Branch Create | 100/sec | 10ms | Includes snapshot |
| Commit | 10/sec | 100ms | Full tree hash |

## Scalability

| Database Size | Objects | Overhead |
|--------------|---------|----------|
| Small | <1K | <1% |
| Medium | 1K-10K | 2-5% |
| Large | 10K-100K | 5-10% |
| X-Large | >100K | TBD |

## Performance Tracking

We track performance regressions in CI. Any PR that increases overhead >10% requires justification.

See: `.github/workflows/performance.yml`
```

**Acceptance Criteria**:
- [ ] Benchmark suite created
- [ ] Baseline metrics documented
- [ ] Performance tracked in CI (warning on regression)
- [ ] Scalability limits documented

---

## Phase-Wide Rollback Strategy

If Phase 2 needs to be completely rolled back:

```bash
# Return to Phase 1 state
git checkout main
git branch -D phase-2-quality-foundation

# If changes were already merged
git revert <merge-commit-sha>

# Remove installed tools
pip uninstall sqlfluff pre-commit semgrep -y
```

**Safe Checkpoints** (tag these as you go):
```bash
git tag phase-2-step-1-complete  # After linting setup
git tag phase-2-step-3-complete  # After API docs
git tag phase-2-step-4-complete  # After security audit
git tag phase-2-complete         # After all steps
```

---

## Verification Commands

```bash
# 1. Linting passes
# ✅ PASS: Exit code 0, all files pass
# ❌ FAIL: Exit code non-zero, violations found
make lint

# 2. Pre-commit hooks installed
# ✅ PASS: All hooks pass
# ❌ FAIL: Any hook fails
pre-commit run --all-files

# 3. API documentation complete
# ✅ PASS: No "No description" found
# ❌ FAIL: Undocumented functions exist
psql -f scripts/generate-api-docs.sql
grep "No description" docs/reference/API_COMPLETE.md && echo "❌ Incomplete" || echo "✅ Complete"

# 4. Security audit requested
# ✅ PASS: Issue exists with label
# ❌ FAIL: No issue found
gh issue list --label "security-audit" | grep -q "Security Audit" && echo "✅" || echo "❌"

# 5. Templates exist
# ✅ PASS: All templates present
# ❌ FAIL: Any template missing
test -f .github/ISSUE_TEMPLATE/bug_report.md && \
test -f .github/ISSUE_TEMPLATE/feature_request.md && \
test -f .github/PULL_REQUEST_TEMPLATE.md && \
echo "✅ All templates exist" || echo "❌ Missing templates"

# 6. No TODOs in code
# ✅ PASS: No TODO/FIXME found
# ❌ FAIL: TODO/FIXME comments remain
! grep -rq "TODO\|FIXME" core/sql sql && echo "✅ Clean" || echo "❌ TODOs remain"

# 7. Performance baseline
# ✅ PASS: File exists and complete
# ❌ FAIL: Missing or incomplete
test -f docs/benchmarks/BASELINE.md && echo "✅ Baseline documented"

# 8. Code of Conduct
# ✅ PASS: File exists and linked
# ❌ FAIL: Missing or not linked
test -f CODE_OF_CONDUCT.md && \
grep -q "CODE_OF_CONDUCT" README.md && \
echo "✅ CoC complete" || echo "❌ CoC incomplete"
```

---

## Acceptance Criteria

### Code Quality
- [ ] sqlfluff linting configured and passing
- [ ] Pre-commit hooks installed and documented
- [ ] All SQL code passes linting
- [ ] No TODO/FIXME without linked issues
- [ ] Code style guide published

### Documentation
- [ ] 100% API documentation coverage
- [ ] All functions have examples
- [ ] Performance baseline documented
- [ ] Testing strategy documented
- [ ] Contributing guide complete

### Security
- [ ] Community security audit requested
- [ ] At least 2 external reviews
- [ ] All findings addressed
- [ ] semgrep checks in CI
- [ ] Security summary published

### Community
- [ ] Issue templates (bug, feature, security)
- [ ] PR template
- [ ] Code of Conduct
- [ ] Templates tested and working
- [ ] Recognition for contributors

### Performance
- [ ] Benchmark suite created
- [ ] Baseline metrics measured
- [ ] Scalability limits documented
- [ ] Performance CI checks

---

## DO NOT

- ❌ Add new features during this phase
- ❌ Refactor without tests
- ❌ Skip linting fixes
- ❌ Ignore security findings
- ❌ Rush community review

**Focus**: Quality systems and processes, not features.

---

## Success Metrics

| Metric | Current | Target | How to Verify | Achieved |
|--------|---------|--------|---------------|----------|
| Code style compliance | 70% | 100% | `make lint` passes | [ ] |
| API documentation | 13% | 100% | 0 undocumented functions | [ ] |
| Security review | ❌ | ✅ | Audit issue closed | [ ] |
| Community templates | ❌ | ✅ | All templates exist | [ ] |
| Performance baseline | ❌ | ✅ | BASELINE.md complete | [ ] |
| Technical debt | High | Low | 0 TODO/FIXME comments | [ ] |
| Overall quality | 7.5/10 | 8.5/10 | All above metrics met | [ ] |

---

## Next Phase

After Phase 2 → **Phase 3: Production Polish**
- Upgrade migration scripts
- Package building
- Monitoring/metrics
- Release automation
