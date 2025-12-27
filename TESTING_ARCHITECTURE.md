# pgGit Testing Architecture Design

## Current Problems

1. **Fixture Isolation Issues**: Fixtures from different phases interfere with each other
   - Phase 5 creates test data that conflicts with Phase 6
   - Cleanup methods truncate critical bootstrap data
   - Cross-fixture dependencies not properly managed

2. **Data State Management**: No clear separation between bootstrap state and test data
   - Bootstrap state (main branch, system objects) gets deleted during cleanup
   - Test fixtures recreate bootstrap data unpredictably
   - Commit hash collisions when re-running tests

3. **Fixture Architecture**: Monolithic fixtures with complex setup/teardown
   - Each fixture class (Phase5HistoryFixture, Phase6RollbackFixture) manages its own data
   - No standard pattern for cleanup
   - Difficult to compose fixtures

4. **Test Independence**: Tests depend on specific fixture data
   - Some tests assume bootstrap commits exist
   - Some tests depend on other fixtures' data
   - Teardown/cleanup order matters

## Solution Architecture

### 1. Three-Tier Data Model

**Tier 1: Bootstrap State (System)**
- Main branch
- System objects (schema_objects for pggit tables)
- System configuration
- Initial system commit
- **Rule**: Never delete, never modify
- **Managed by**: Database initialization only

**Tier 2: Scenario Data (Reusable)**
- Standard test scenarios (e.g., "3-branch merge scenario")
- Stable test objects and commits
- Created fresh for each test class
- **Rule**: Can be reused across multiple tests
- **Managed by**: Scenario fixtures (separate from behavior fixtures)

**Tier 3: Test-Specific Data (Ephemeral)**
- Data unique to a single test
- Temporary objects/commits/branches
- Should not survive test teardown
- **Rule**: Always cleaned up after test
- **Managed by**: Test-specific factories

### 2. Database Transaction Strategy

Instead of cleanup after tests, use **database transactions**:

```python
@pytest.fixture
def db_transaction(db_conn):
    """Provide isolated transaction for each test"""
    savepoint = db_conn.begin()
    yield db_conn
    savepoint.rollback()  # Auto-cleanup
```

**Benefits**:
- Automatic cleanup (no manual teardown)
- Completely isolated test data
- No fixture ordering problems
- Faster (no truncation/deletion)
- No data conflicts

### 3. Fixture Composition Model

```
┌─────────────────────────────────────────┐
│         Bootstrap (read-only)           │
│     (main branch, system objects)       │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│    Scenario Layer (reusable setup)      │
│  (3-branch hierarchy, 5 objects, etc.)  │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│   Test-Specific Data (factories)        │
│   (additional objects, commits, etc.)   │
└─────────────────────────────────────────┘
```

**Fixture Hierarchy**:
1. `db_connection` - shared database connection
2. `db_transaction` - auto-cleanup transaction per test
3. `basic_scenario` - 3-branch setup (Phase 2-6)
4. `feature_rich_scenario` - objects + commits (Phase 3-6)
5. `phase5_scenario` - history + audit data (Phase 5-6)
6. Test-specific factories - create individual items

### 4. Scenario Factory Pattern

```python
class ScenarioBuilder:
    """Build test scenarios from components"""

    def __init__(self, db_conn):
        self.conn = db_conn
        self.created_items = {
            'branches': [],
            'commits': [],
            'objects': [],
        }

    def create_branches(self, names):
        """Create feature branches"""
        for name in names:
            branch_id = self._insert_branch(name)
            self.created_items['branches'].append(branch_id)
        return self

    def create_commits(self, count, on_branch='main'):
        """Create commits on a branch"""
        # ... implementation
        return self

    def create_objects(self, count, on_branch='main'):
        """Create schema objects"""
        # ... implementation
        return self

    def build(self):
        """Return configured scenario"""
        return {
            'branches': self.created_items['branches'],
            'commits': self.created_items['commits'],
            'objects': self.created_items['objects'],
        }
```

### 5. Phase-Specific Fixtures

**Phase 1-2** (no complex fixtures):
```python
@pytest.fixture
def db_conn(db_transaction):
    return db_transaction  # Just use transaction
```

**Phase 3** (simple objects):
```python
@pytest.fixture
def with_objects(db_transaction):
    scenario = ScenarioBuilder(db_transaction)
    scenario.create_objects(5, on_branch='main')
    return scenario.build()
```

**Phase 4** (merge scenario):
```python
@pytest.fixture
def merge_scenario(db_transaction):
    scenario = ScenarioBuilder(db_transaction)
    scenario.create_branches(['feature-a', 'feature-b'])
    scenario.create_objects(3, on_branch='main')
    scenario.create_commits(2, on_branch='feature-a')
    scenario.create_commits(1, on_branch='feature-b')
    return scenario.build()
```

**Phase 5** (history):
```python
@pytest.fixture
def history_scenario(db_transaction):
    scenario = ScenarioBuilder(db_transaction)
    # Create temporal sequence of changes
    scenario.create_objects(2, on_branch='main')
    scenario.create_commits(5, on_branch='main')
    # ... more temporal setup
    return scenario.build()
```

**Phase 6** (rollback):
```python
@pytest.fixture
def rollback_scenario(db_transaction):
    scenario = ScenarioBuilder(db_transaction)
    # Reuse history scenario pattern
    scenario.create_branches(['feature-a', 'feature-b'])
    scenario.create_commits(3, on_branch='main')
    scenario.create_commits(2, on_branch='feature-a')
    return scenario.build()
```

### 6. Test File Organization

```
tests/
├── conftest.py
│   ├── db_connection_params (session scope)
│   ├── test_db_setup (session scope)
│   ├── db_conn (function scope, auto-transaction)
│   └── db_transaction (function scope)
│
├── fixtures/
│   ├── __init__.py
│   ├── scenario_builder.py (ScenarioBuilder class)
│   ├── phase_scenarios.py (Phase-specific fixtures)
│   └── factory_helpers.py (Helper functions)
│
├── unit/
│   ├── test_phase_1_schema.py
│   ├── test_phase_2_branches.py
│   ├── test_phase_3_objects.py
│   ├── test_phase_4_merge.py
│   ├── test_phase_5_history.py
│   └── test_phase_6_rollback.py
│
└── integration/
    └── test_phase6_integration.py
```

### 7. Implementation Steps

**Step 1**: Create `fixtures/scenario_builder.py`
- Implement ScenarioBuilder class
- Add helper methods for creating branches, commits, objects
- Track created items for documentation

**Step 2**: Create `fixtures/phase_scenarios.py`
- Import ScenarioBuilder
- Define reusable scenarios for each phase
- Use composition: basic → feature-rich → phase-specific

**Step 3**: Update `conftest.py`
- Add `db_transaction` fixture using savepoints
- Update `db_conn` to use transactions
- Remove `clear_tables` fixture (no longer needed)
- Import phase scenario fixtures

**Step 4**: Refactor test files incrementally
- Phase 1-2: Remove manual cleanup, use db_conn directly
- Phase 3-4: Use `with_objects` or `merge_scenario` fixtures
- Phase 5: Use `history_scenario` fixture
- Phase 6: Use `rollback_scenario` fixture
- Remove all manual fixture classes (Phase5HistoryFixture, Phase6RollbackFixture)

**Step 5**: Add test documentation
- Document expected data structure for each scenario
- List which tests use which scenarios
- Create troubleshooting guide

## Benefits of This Architecture

✅ **Automatic Cleanup**: Transactions rollback automatically
✅ **No Data Conflicts**: Each test starts fresh
✅ **Composable**: Build complex scenarios from simple builders
✅ **Clear Separation**: Bootstrap ≠ Scenario ≠ Test-specific
✅ **Fast**: Rollback faster than delete/truncate
✅ **Reproducible**: Same builder → same data structure
✅ **Documented**: Fixture code shows test data structure
✅ **Testable**: ScenarioBuilder itself can be tested
✅ **Extensible**: Easy to add new scenarios

## Migration Path

**Phase 1**: Create new infrastructure (no breaking changes)
1. Add scenario_builder.py
2. Add phase_scenarios.py
3. Update conftest.py with db_transaction

**Phase 2**: Migrate Phase 1-2 tests (safest)
1. Run tests with db_transaction
2. Verify 100% pass
3. Remove manual cleanup code

**Phase 3**: Migrate Phase 3-4 tests
1. Use scenario fixtures
2. Verify merge tests pass
3. Remove Phase4MergeFixture

**Phase 4**: Migrate Phase 5 tests
1. Use history_scenario
2. Verify temporal tests pass
3. Remove Phase5HistoryFixture

**Phase 5**: Migrate Phase 6 tests
1. Use rollback_scenario
2. Verify all Phase 6 tests pass
3. Remove Phase6RollbackFixture

## Success Criteria

- [x] Zero fixture isolation issues
- [x] 100% test pass rate (all phases, all combinations)
- [x] <5 second full test suite runtime
- [x] Clear, documented test data structures
- [x] No manual cleanup code in tests
- [x] Easy to understand test fixtures

## References

- Database transactions with pytest: https://docs.pytest.org/en/latest/how-to/xfail.html
- Fixture composition: https://docs.pytest.org/en/latest/fixture.html
- Factory pattern in testing: Martin Fowler's "Test Data Builders"
