# User Journey E2E Test Suite

**Validates that the Getting Started guide actually works for new users**

## 🎯 Purpose

This test suite addresses a critical question: **"Does the documentation work in a clean environment?"**

Traditional tests validate internal APIs and logic. These tests validate **the user experience** by:

1. **Starting from a clean Ubuntu environment** (no local state, dependencies, or configuration)
2. **Following the Getting Started guide step-by-step** (exactly as a new user would)
3. **Running all documented code examples** (CREATE TABLE, ALTER TABLE, API calls, etc.)
4. **Verifying expected outcomes** (version tracking works, history is recorded, dependencies detected)

## 🚨 Why This Matters

**The Problem**: In the past, the project hit an issue where "I cannot build" - the documented installation steps didn't work for new users.

**The Solution**: These tests catch:
- ❌ Documentation drift (guide says "run X" but X doesn't exist)
- ❌ Missing installation dependencies
- ❌ Broken code examples in documentation
- ❌ API changes that weren't reflected in docs
- ❌ "Works on my machine" problems

**The Result**: Confidence that new users can actually follow the guide and have a working setup.

---

## 📖 Test Coverage

Each test corresponds to a chapter in the Getting Started guide:

| Test Class | Chapter | What It Tests |
|------------|---------|---------------|
| `TestChapter2Installation` | Chapter 2: The Five-Minute Setup | Extension installation, event triggers, core functions |
| `TestChapter3FirstTracking` | Chapter 3: Your First Automatic Tracking | CREATE TABLE tracking, version assignment |
| `TestChapter4SchemaEvolution` | Chapter 4: Watching Changes Evolve | ALTER TABLE tracking, version incrementing, history |
| `TestChapter5ImpactAnalysis` | Chapter 5: The Safety Net | Dependency detection (foreign keys, views) |
| `TestChapter6MigrationGeneration` | Chapter 6: Migration Magic | Migration script generation |
| `TestChapter9CompleteAPI` | Chapter 9: Quick Reference | All documented API functions |

---

## 🚀 Running the Tests

### Option 1: Docker Compose (Recommended)

**Fully isolated, clean environment - mirrors what CI/CD does:**

```bash
# From repository root
cd tests/user-journey

# Run the complete test suite
docker-compose up --build --abort-on-container-exit

# View results
docker-compose logs test-runner
```

**What happens:**
1. Builds a clean Ubuntu 22.04 container
2. Installs PostgreSQL 17 dev tools
3. Builds pgGit from source (`make && make install`)
4. Runs all 6 test scenarios
5. Reports results

### Option 2: Local Testing (Faster for development)

**Requires:**
- PostgreSQL 17 server running locally
- PostgreSQL 17 dev tools installed
- Python 3.11+

```bash
# Install test dependencies
pip install pytest psycopg[binary] pyyaml

# Build and install pgGit
make clean && make
sudo make install

# Set up test database
createdb pggit_user_journey

# Run tests
export PGDATABASE=pggit_user_journey
python -m pytest tests/user-journey/test_user_journey.py -v
```

### Option 3: GitHub Actions (Automatic)

Tests run automatically on:
- ✅ Every push to `main` or `develop`
- ✅ Every pull request
- ✅ Daily at 6 AM UTC (catches regressions)
- ✅ Manual trigger via workflow dispatch

See: `.github/workflows/user-journey-tests.yml`

---

## 📂 Test Structure

```
tests/user-journey/
├── Dockerfile.clean-install          # Clean Ubuntu environment for testing
├── docker-compose.yml                # PostgreSQL + test runner orchestration
├── test_user_journey.py              # Main pytest test suite
├── scenarios/                        # SQL test scenarios
│   ├── 01_installation.sql           # Chapter 2: Installation
│   ├── 02_first_tracking.sql         # Chapter 3: First table tracking
│   ├── 03_schema_evolution.sql       # Chapter 4: ALTER tracking
│   ├── 04_impact_analysis.sql        # Chapter 5: Dependency detection
│   ├── 05_migration_generation.sql   # Chapter 6: Migrations
│   └── 06_all_api_functions.sql      # Chapter 9: Complete API
└── README.md                         # This file
```

### How It Works

1. **Python test runner** (`test_user_journey.py`):
   - Connects to PostgreSQL
   - Executes SQL scenario files
   - Validates results using assertions
   - Reports pass/fail for each chapter

2. **SQL scenario files**:
   - Contain exact SQL from the Getting Started guide
   - Include verification queries (e.g., `SELECT version IS NOT NULL`)
   - Return result sets with boolean checks
   - Match documented examples precisely

3. **Docker environment**:
   - Starts with clean Ubuntu 22.04
   - Installs only documented dependencies
   - Builds pgGit from source
   - Simulates fresh user experience

---

## 🧪 Example Test Scenario

**From `02_first_tracking.sql` (Chapter 3):**

```sql
-- Create the users table (from the guide)
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Verify version was assigned
SELECT
    version >= 1 AS has_version,
    version_string ~ '^\d+\.\d+\.\d+$' AS version_format_valid
FROM pggit.get_version('public.users');
```

**Test validates:**
- ✅ Table created successfully
- ✅ Version assigned automatically
- ✅ Version string follows semver format (e.g., 1.0.0)
- ✅ History entry recorded

---

## 📊 Interpreting Results

### ✅ All Tests Pass

**Meaning**: The Getting Started guide works correctly. New users can follow the documentation and have a working setup.

**Action**: None required. Documentation is accurate and code works as documented.

### ❌ Tests Fail

**Meaning**: There's a mismatch between documentation and implementation.

**Possible causes:**
1. **API changed** but documentation wasn't updated
2. **Installation instructions** missing dependencies
3. **Code examples** in guide are outdated or incorrect
4. **Breaking change** introduced without updating guide

**Action Required:**
1. Review the failing test scenario
2. Compare with the corresponding chapter in Getting Started guide
3. Either:
   - Fix the code to match documentation (if docs are correct)
   - Update documentation to match code (if code is correct)
   - Update both if there's a design change

---

## 🔧 Adding New Tests

When adding new features to pgGit:

### 1. Update Getting Started Guide

Add examples to `docs/getting-started/Getting_Started.md`:

```markdown
## Chapter 10: New Feature

Here's how to use the new feature:

```sql
SELECT pggit.new_feature('example');
```
```

### 2. Create SQL Scenario

Create `scenarios/07_new_feature.sql`:

```sql
-- Test the new feature
SELECT pggit.new_feature('example') AS result;

-- Verify result
SELECT
    result IS NOT NULL AS feature_works,
    result = 'expected_value' AS correct_output
FROM (SELECT pggit.new_feature('example') AS result) t;
```

### 3. Add Test Class

In `test_user_journey.py`:

```python
class TestChapter10NewFeature:
    """Chapter 10: New Feature - Description."""

    def test_new_feature(self, db):
        """Test new feature works as documented."""
        scenario_file = Path(__file__).parent / "scenarios" / "07_new_feature.sql"
        results = db.execute_sql_file(scenario_file)

        assert any(r.get("feature_works") for r in results), "New feature not working"
        assert any(r.get("correct_output") for r in results), "Wrong output"

        print("✅ Chapter 10: New Feature - All checks passed")
```

### 4. Run Tests

```bash
docker-compose up --build
```

---

## 🎯 Best Practices

### For Test Writers

1. **Mirror the guide exactly**: Use the same SQL, same table names, same workflow
2. **Test outcomes, not implementation**: Verify "version was assigned", not "specific function called"
3. **Be explicit about failures**: Clear assertion messages help identify issues
4. **Keep scenarios independent**: Each scenario should set up its own test data
5. **Clean up after tests**: Use `DROP TABLE IF EXISTS ... CASCADE` at the start

### For Documentation Writers

1. **Test first**: Add the test scenario before or while writing docs
2. **Use realistic examples**: Real-world scenarios are easier to test
3. **Be specific**: "Run `make && make install`" is testable; "install pgGit" is vague
4. **Show expected output**: Makes it easy to write assertions
5. **Update tests with docs**: When docs change, update corresponding test scenario

---

## 📈 Continuous Improvement

### Metrics Tracked

- **Test execution time**: Should stay under 5 minutes
- **Pass rate**: Should be 100% on main branch
- **Coverage**: All Getting Started chapters should have tests

### When Tests Fail in CI

1. **Check recent commits**: What changed?
2. **Review failure details**: Which chapter/scenario failed?
3. **Compare with docs**: Is there a mismatch?
4. **Fix immediately**: Don't let failures persist (documentation drift compounds)

### Maintenance Schedule

- **Weekly**: Review test execution times (optimize slow scenarios)
- **Monthly**: Audit test coverage (are new features documented and tested?)
- **Per release**: Manually verify one full user journey end-to-end

---

## 🐛 Troubleshooting

### "Database connection failed"

**Problem**: PostgreSQL not ready yet.

**Solution**: The test suite includes retry logic. If it still fails:
```bash
# Check PostgreSQL is running
docker-compose ps

# View PostgreSQL logs
docker-compose logs postgres
```

### "Extension installation failed"

**Problem**: Build errors or missing dependencies.

**Solution**: Check build logs:
```bash
docker-compose logs test-runner | grep -A 10 "Building pgGit"
```

Common causes:
- Missing `postgresql-server-dev-17`
- Build error in C code
- Permissions issue with `make install`

### "Test scenario failed"

**Problem**: SQL scenario returned unexpected results.

**Solution**:
1. Run the scenario manually:
   ```bash
   psql -d pggit_user_journey -f scenarios/XX_scenario.sql
   ```
2. Check actual vs expected output
3. Update scenario or fix code

### "Docker build is slow"

**Problem**: Rebuilding the entire container takes time.

**Solution**: Use local testing for development:
```bash
# Build once
make clean && make && sudo make install

# Run tests repeatedly (fast)
pytest tests/user-journey/test_user_journey.py -v
```

---

## 📚 Related Documentation

- **Getting Started Guide**: `docs/getting-started/Getting_Started.md` (what we're testing)
- **API Reference**: `docs/API_Reference.md` (function signatures)
- **E2E Test Guide**: `docs/testing/E2E_TESTING.md` (internal API tests)
- **Troubleshooting**: `docs/getting-started/Troubleshooting.md` (user help)

---

## 🎉 Success Criteria

**These tests are successful when:**

1. ✅ Every code example in Getting Started guide has a corresponding test
2. ✅ Tests run in <5 minutes in CI/CD
3. ✅ 100% pass rate on main branch
4. ✅ New features include updated documentation + tests
5. ✅ Failures are caught before merging (CI gates)
6. ✅ New contributors can follow the guide and have a working setup

**The ultimate goal**: A new user can read the Getting Started guide, follow the examples, and **everything just works** - because we test that exact experience automatically.

---

**Last Updated**: 2025-12-31
**Maintained By**: pgGit Development Team
**Questions?**: Open an issue or check [Troubleshooting](../../docs/getting-started/Troubleshooting.md)
