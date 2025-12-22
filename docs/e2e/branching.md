# Branching Operations Test Guide

## Overview

The branching capability area tests all branch-related operations including creation, hierarchy, consistency, and cleanup. These tests ensure that complex branching scenarios work correctly under various conditions.

## Test Modules

### test_branching_advanced_scenarios.py
5 tests covering complex branch hierarchies and operations:

- **test_nested_branch_creation** - Validates creating multi-level branch hierarchies
  - Creates parent, child, and grandchild branches
  - Verifies all branches exist with proper IDs
  - Tests hierarchical relationship tracking

- **test_parallel_branch_operations** - Tests independent operations on multiple branches
  - Creates two parallel branches
  - Executes independent operations on each
  - Verifies operations don't interfere with each other

- **test_branch_cleanup_cascade** - Validates cascade cleanup of branch data
  - Creates branch with commits
  - Tests data preservation and cleanup
  - Verifies referential integrity during deletion

- **test_branch_status_query** - Tests branch status tracking and queries
  - Creates branch with default status
  - Verifies status can be queried
  - Tests status transitions

- **test_branch_retrieval_integrity** - Tests data retrieval consistency
  - Creates multiple branches
  - Retrieves all branches with pattern matching
  - Verifies retrieval integrity

### test_branching_cross_consistency.py
2 tests validating consistency across branches:

- **test_version_compatibility_check** - Validates version compatibility across branches
  - Checks branch table existence
  - Verifies commits table schema
  - Tests schema introspection

- **test_backward_compatibility_queries** - Tests old query patterns still work
  - Simple SELECT on branches
  - JOIN queries between branches and commits
  - Verifies backward compatibility

## Common Test Patterns

### Branch Creation
```python
branch_id = db.execute_returning(
    "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
    "branch-name"
)[0]
```

### Verifying Branch Exists
```python
result = db.execute(
    "SELECT COUNT(*) FROM pggit.branches WHERE id = %s",
    branch_id
)
assert result[0][0] == 1, "Branch should exist"
```

### Querying Across Branches
```python
result = db.execute("""
    SELECT COUNT(*) FROM pggit.branches b
    LEFT JOIN pggit.commits c ON b.id = c.branch_id
    WHERE b.name = %s
""", branch_name)
```

## Running Branching Tests

### All branching tests
```bash
pytest tests/e2e/test_branching_*.py -v
```

### Specific capability
```bash
pytest tests/e2e/test_branching_advanced_scenarios.py -v
pytest tests/e2e/test_branching_cross_consistency.py -v
```

### With output
```bash
pytest tests/e2e/test_branching_*.py -vv --tb=short
```

## Test Isolation

All branching tests use transaction isolation:
1. Each test runs in isolated database transaction
2. Test data is automatically rolled back after test completes
3. Parallel tests don't interfere with each other
4. No cleanup code needed

## Expected Results

All branching tests should pass with:
- 100% test success rate
- No data corruption
- All hierarchical relationships preserved
- Backward compatibility maintained

## Common Issues

### Branch Not Found
If branch creation returns None:
- Verify pggit schema is installed
- Check sequences are initialized
- Verify INSERT permissions

### Commit Not Found
If commits aren't created:
- Verify branch exists before creating commit
- Check FK constraints allow NULL branch_id
- Verify RETURNING clause works

### Cascading Delete Failures
If cleanup fails:
- Verify ON DELETE CASCADE is set on FKs
- Check no additional references exist
- Verify transaction isolation is working

## Performance Characteristics

Expected timing for branching operations:
- Branch creation: ~5-10ms
- Branch retrieval: ~1-2ms per 100 branches
- Parallel operations (10 threads): ~50-100ms total
- Cleanup/cascade: ~10-20ms

## Adding New Branch Tests

When adding branch-related tests:
1. Use descriptive test names
2. Include docstrings explaining test purpose
3. Use the `db` fixture for database access
4. Clean up test data (uses transactions)
5. Test both success and failure cases
6. Verify hierarchical integrity

Example:
```python
def test_branch_example(db, pggit_installed):
    """Test branch creation with specific pattern."""
    # Create branch
    branch_id = db.execute_returning(
        "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
        "test-branch"
    )[0]

    # Verify creation
    result = db.execute(
        "SELECT COUNT(*) FROM pggit.branches WHERE id = %s",
        branch_id
    )
    assert result[0][0] == 1, "Branch should be created"
```

## Integration with Other Tests

Branching tests are independent but support other capability areas:
- **Data Integrity**: Uses branches to test data isolation
- **Deployment**: Uses branches to test schema evolution
- **Performance**: Creates branches for load testing

## Metrics

Branching test coverage:
- **Test Count**: 7 tests
- **Coverage**: Basic CRUD, hierarchies, consistency
- **Complexity**: Medium (multiple operations per test)
- **Runtime**: ~1-2 seconds per test
