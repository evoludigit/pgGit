# Mutation Testing Guide

**Validate test quality with mutation testing**

## What is Mutation Testing?

Mutation testing validates the effectiveness of your tests by:

1. **Creating mutations**: Intentionally introducing bugs into code
2. **Running tests**: Seeing if tests catch the mutations
3. **Scoring**: % of mutations caught = test quality score

**Example**:
```python
# Original code
if x > 0:
    return True

# Mutant 1: Change operator
if x >= 0:  # Mutation!
    return True

# Mutant 2: Change constant
if x > 1:  # Mutation!
    return True
```

If your tests pass with mutants, you have a **test gap**.

## Why Mutation Testing?

**Code coverage isn't enough!**

```python
# Code with 100% coverage but weak tests
def divide(a, b):
    return a / b  # 100% covered

# Weak test (doesn't catch division by zero)
def test_divide():
    assert divide(10, 2) == 5  # ✅ Passes

# Mutation: Change / to *
def divide_mutant(a, b):
    return a * b  # Mutation!

# Weak test still passes! ❌
def test_divide():
    assert divide_mutant(10, 2) == 5  # Still passes: 10 * 2 != 5
    # Wait, this should fail but I made an error in my example
```

**Better test**:
```python
def test_divide_comprehensive():
    assert divide(10, 2) == 5
    assert divide(7, 2) == 3.5  # Catches * mutation
    with pytest.raises(ZeroDivisionError):
        divide(1, 0)  # Catches missing error handling
```

## Running Mutation Tests

### Locally

```bash
# Install mutmut
pip install mutmut

# Run mutation testing on E2E tests
mutmut run \
    --paths-to-mutate tests/e2e/ \
    --tests-dir tests/ \
    --runner "pytest -x --tb=short"

# View results
mutmut results

# Generate HTML report
mutmut html
open html/index.html
```

### Specific Test File

```bash
# Mutate only one file
mutmut run \
    --paths-to-mutate tests/e2e/test_branching.py \
    --tests-dir tests/e2e/ \
    --runner "pytest tests/e2e/test_branching.py -x"
```

### CI/CD

Mutation testing runs automatically:

- **Schedule**: Weekly on Sundays at 4 AM UTC
- **Trigger**: Manual workflow dispatch
- **Workflow**: `.github/workflows/mutation-testing.yml`

```bash
# Trigger manually via GitHub CLI
gh workflow run mutation-testing.yml \
    -f test_subset=e2e
```

## Interpreting Results

### Mutation Outcomes

| Outcome | Meaning | Good/Bad |
|---------|---------|----------|
| **Killed** | Test failed (caught mutation) | ✅ Good |
| **Survived** | Test passed (missed mutation) | ❌ Bad |
| **Timeout** | Test ran too long (infinite loop) | ⚠️  Check |
| **Suspicious** | Unusual behavior | ⚠️  Investigate |

### Mutation Score

```
Mutation Score = (Killed / Total) × 100%
```

| Score | Quality | Action |
|-------|---------|--------|
| ≥80% | Excellent | Maintain quality |
| 60-79% | Good | Review survivors |
| 40-59% | Needs work | Add tests |
| <40% | Poor | Significant gaps |

### Example Output

```
Mutation testing results:
- Killed: 45 (75%)
- Survived: 10 (17%)
- Timeout: 5 (8%)
- Total: 60

Mutation score: 75% (Good)
```

## Handling Surviving Mutations

### 1. Review the Mutation

```bash
# Show details of a surviving mutation
mutmut show 15

# Example output:
# --- tests/e2e/test_branching.py
# +++ tests/e2e/test_branching.py
# @@ -42,7 +42,7 @@
#      def test_create_branch(self):
# -        if branch_name is None:
# +        if branch_name is not None:  # MUTATION
#              raise ValueError("Branch name required")
```

### 2. Determine if Test Gap

Ask:
- Should this mutation be caught?
- Is the mutation changing meaningful logic?
- Would this bug manifest in production?

**If YES** → Add test to kill it

### 3. Add Test

```python
# Before: Weak test (survives mutation)
def test_create_branch():
    create_branch("feature")
    assert branch_exists("feature")

# After: Strong test (kills mutation)
def test_create_branch():
    # Happy path
    create_branch("feature")
    assert branch_exists("feature")

    # Edge case: None input
    with pytest.raises(ValueError, match="Branch name required"):
        create_branch(None)  # Kills the mutation!
```

### 4. Verify Fix

```bash
# Re-run mutmut on that specific mutation
mutmut run --mutation-id 15

# Should now show "killed"
mutmut results
```

## Common Mutation Patterns

### 1. Operator Mutations

```python
# Original
if x > 0:

# Mutations
if x >= 0:   # Boundary
if x < 0:    # Inversion
if x != 0:   # Equality
```

**Kill with**: Boundary tests (`x=0`, `x=1`, `x=-1`)

### 2. Constant Mutations

```python
# Original
return value + 1

# Mutations
return value + 0  # Remove increment
return value + 2  # Change constant
return value - 1  # Invert
```

**Kill with**: Specific value assertions

### 3. Logical Mutations

```python
# Original
if a and b:

# Mutations
if a or b:   # Change operator
if a:        # Remove condition
if b:        # Remove condition
```

**Kill with**: Test all logical branches

### 4. Return Mutations

```python
# Original
return True

# Mutations
return False
return None
# (remove return statement)
```

**Kill with**: Assert specific return values

## Best Practices

### 1. Start Small

```bash
# Don't mutate everything at once
mutmut run --paths-to-mutate tests/e2e/test_one_file.py
```

### 2. Focus on Critical Code

Prioritize mutation testing for:
- Core business logic
- Security-critical functions
- Complex algorithms
- High-risk code paths

### 3. Ignore Equivalent Mutations

Some mutations don't change behavior:

```python
# Original
x = x + 1

# Equivalent mutation (same result)
x += 1
```

Mark as equivalent:
```bash
mutmut results
# Find ID of equivalent mutation
mutmut mark-equivalent 23
```

### 4. Use Timeouts

```bash
# Prevent infinite loops
mutmut run --runner "pytest -x --timeout=30"
```

### 5. Incremental Improvement

Don't aim for 100% immediately:

1. **Week 1**: Run mutation testing, establish baseline
2. **Week 2**: Fix high-priority survivors
3. **Week 3**: Improve to 60% score
4. **Month 2**: Improve to 80% score
5. **Ongoing**: Maintain 80%+ score

## Configuration

### `.mutmut_config.py`

```python
def pre_mutation(context):
    """Skip certain files."""
    # Don't mutate test utilities
    if 'conftest' in context.filename:
        context.skip = True

    # Don't mutate fixtures
    if 'fixtures' in context.filename:
        context.skip = True
```

### `pyproject.toml`

```toml
[tool.mutmut]
paths_to_mutate = "tests/e2e/"
backup = false
runner = "pytest -x --tb=short"
use_coverage = true
```

## Troubleshooting

### Mutmut Hangs

```bash
# Use timeout
mutmut run --runner "pytest -x --timeout=30"

# Or kill specific mutation
mutmut run --mutation-id 15 --timeout 10
```

### Too Many Mutations

```bash
# Use coverage to reduce
mutmut run --use-coverage

# This only mutates lines covered by tests
```

### False Positives

Some mutations survive legitimately:

- **Logging statements**: Won't fail tests
- **Performance optimizations**: Functionally equivalent
- **Error messages**: String changes don't affect logic

Mark these as equivalent:
```bash
mutmut mark-equivalent 42
```

## CI/CD Integration

### Workflow Triggers

```yaml
# .github/workflows/mutation-testing.yml
on:
  schedule:
    - cron: '0 4 * * 0'  # Weekly
  workflow_dispatch:     # Manual trigger
```

### Automated Issues

If mutations survive, CI creates GitHub issues automatically:

**Example Issue**:
```
Title: [Mutation Testing] 10 surviving mutations detected

Body:
🧬 Mutation Testing Alert

10 mutations survived the test suite.

Action Required:
1. Download the mutation report
2. Review surviving mutations
3. Add tests to kill these mutations

Test Subset: e2e
Run: 12345
```

## Resources

- **Mutmut Documentation**: https://mutmut.readthedocs.io/
- **Mutation Testing Explained**: https://en.wikipedia.org/wiki/Mutation_testing
- **Testing Best Practices**: [PATTERNS.md](PATTERNS.md)

## FAQ

**Q: How long does mutation testing take?**
A: Depends on test suite size. For pgGit E2E tests: ~30-60 minutes.

**Q: Should I run mutation testing on every commit?**
A: No, too slow. Weekly or on-demand is recommended.

**Q: What's a good mutation score target?**
A: 80% is excellent. 60-80% is good. <60% needs improvement.

**Q: Do I need 100% mutation score?**
A: No. Some mutations are equivalent or not worth testing (e.g., log messages).

**Q: How do I improve my score?**
A: Focus on surviving mutations. Add tests that would catch those specific bugs.

**Q: Can mutation testing replace code coverage?**
A: No, they're complementary. Use coverage for breadth, mutation testing for depth.
