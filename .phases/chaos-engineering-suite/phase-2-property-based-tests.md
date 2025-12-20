# Phase 2: Property-Based Tests with Hypothesis

## Objective
Implement property-based tests using Hypothesis to validate pggit's behavior across a wide range of inputs and scenarios, catching edge cases that example-based tests miss.

## TDD Stage
RED → GREEN

## Context
- **Previous phase**: Phase 1 (Infrastructure Setup) created test framework, fixtures, and utilities
- **Current state**: Test infrastructure ready, no actual chaos tests yet
- **Next phase**: Phase 3 (Concurrency Tests) will test race conditions and deadlocks

## Files to Create

### 1. `tests/chaos/test_property_based_core.py`
Core pggit operations with property-based testing:
- Table versioning with arbitrary table structures
- Trinity ID generation properties
- Commit message validation
- Branch name validation

### 2. `tests/chaos/test_property_based_migrations.py`
Migration operations with generated schemas:
- Schema diff generation
- Migration application idempotency
- Rollback correctness

### 3. `tests/chaos/test_property_based_data.py`
Data operations with generated data:
- Data branching (copy-on-write)
- Merge operations
- Data integrity across versions

### 4. `tests/chaos/strategies.py`
Custom Hypothesis strategies for pggit domain objects:
- Valid PostgreSQL identifiers
- Table definitions
- Schema objects
- Git-like commit graphs

## Implementation Steps

### Step 0: Add API Existence Checks to conftest.py

First, extend `tests/chaos/conftest.py` with helpers to check if pggit functions exist:

```python
# Add to tests/chaos/conftest.py

import psycopg
import pytest

def pggit_function_exists(conn: psycopg.Connection, function_name: str) -> bool:
    """Check if a pggit function exists."""
    cursor = conn.execute("""
        SELECT EXISTS (
            SELECT 1
            FROM pg_proc p
            JOIN pg_namespace n ON p.pronamespace = n.oid
            WHERE n.nspname = 'pggit'
            AND p.proname = %s
        )
    """, (function_name,))
    return cursor.fetchone()[0]


@pytest.fixture(scope="session")
def pggit_api_check(db_connection_string: str) -> dict[str, bool]:
    """Check which pggit API functions exist (run once per session)."""
    conn = psycopg.connect(db_connection_string)
    conn.execute("CREATE EXTENSION IF NOT EXISTS pggit")

    functions_to_check = [
        'get_version',
        'commit_changes',
        'increment_version',
        'calculate_schema_hash',
        'create_data_branch',
    ]

    api_availability = {}
    for func_name in functions_to_check:
        api_availability[func_name] = pggit_function_exists(conn, func_name)

    conn.close()
    return api_availability


def skip_if_function_missing(function_name: str):
    """Decorator to skip test if pggit function doesn't exist."""
    return pytest.mark.skipif(
        not pggit_function_exists(psycopg.connect("dbname=pggit_chaos_test"), function_name),
        reason=f"pggit.{function_name}() not implemented yet"
    )
```

### Step 1: Create Custom Hypothesis Strategies (`tests/chaos/strategies.py`)

```python
"""
Custom Hypothesis strategies for generating pggit domain objects.
"""

from hypothesis import strategies as st
from typing import Any
import string

# Valid PostgreSQL identifier characters
PG_IDENTIFIER_START = string.ascii_lowercase + '_'
PG_IDENTIFIER_CHARS = string.ascii_lowercase + string.digits + '_'


@st.composite
def pg_identifier(draw, max_length: int = 63, allow_reserved: bool = False):
    """Generate valid PostgreSQL identifier."""
    # First character must be letter or underscore
    first_char = draw(st.sampled_from(PG_IDENTIFIER_START))

    # Remaining characters
    remaining_length = draw(st.integers(min_value=0, max_value=max_length - 1))
    remaining = draw(st.text(
        alphabet=PG_IDENTIFIER_CHARS,
        min_size=remaining_length,
        max_size=remaining_length
    ))

    identifier = first_char + remaining

    # Avoid PostgreSQL reserved words if requested
    if not allow_reserved:
        reserved_words = {
            'select', 'from', 'where', 'table', 'create', 'drop',
            'alter', 'user', 'group', 'order', 'index', 'primary'
        }
        if identifier in reserved_words:
            identifier = f"{identifier}_"

    return identifier


@st.composite
def table_name(draw):
    """Generate valid table name."""
    return draw(pg_identifier(max_length=63))


@st.composite
def column_definition(draw):
    """Generate column definition (name, type)."""
    col_name = draw(pg_identifier(max_length=63))

    col_types = [
        'INTEGER', 'BIGINT', 'TEXT', 'VARCHAR(255)',
        'BOOLEAN', 'TIMESTAMP', 'DATE', 'NUMERIC',
        'UUID', 'JSONB'
    ]
    col_type = draw(st.sampled_from(col_types))

    constraints = draw(st.sampled_from([
        '',  # No constraint (40% probability)
        'NOT NULL',
        'DEFAULT 0',
        'DEFAULT CURRENT_TIMESTAMP',
    ]))

    return f"{col_name} {col_type} {constraints}".strip()


@st.composite
def table_definition(draw):
    """Generate complete table definition."""
    tbl_name = draw(table_name())

    # Generate 1-10 columns
    num_cols = draw(st.integers(min_value=1, max_value=10))
    columns = [draw(column_definition()) for _ in range(num_cols)]

    # Add primary key (optional)
    if draw(st.booleans()):
        pk_name = draw(pg_identifier(max_length=20))
        columns.insert(0, f"{pk_name} SERIAL PRIMARY KEY")

    return {
        'name': tbl_name,
        'columns': columns,
        'create_sql': f"CREATE TABLE {tbl_name} ({', '.join(columns)})"
    }


@st.composite
def git_branch_name(draw):
    """Generate valid Git-like branch name."""
    # Branch names can't start with -, ., or /
    # Generate valid parts (no leading special chars)
    parts = draw(st.lists(
        st.text(
            alphabet=string.ascii_lowercase + string.digits + '-_',
            min_size=1,
            max_size=20
        ).filter(lambda s: s[0] not in '-_'),  # Can't start with - or _
        min_size=1,
        max_size=3
    ))

    # Join with / for hierarchical branches
    branch = '/'.join(parts)

    # Common branch patterns
    if draw(st.booleans()):
        prefix = draw(st.sampled_from(['feature', 'bugfix', 'hotfix', 'release']))
        branch = f"{prefix}/{branch}"

    # Validation: ensure no double slashes, no leading/trailing slashes
    branch = branch.strip('/')
    while '//' in branch:
        branch = branch.replace('//', '/')

    return branch


@st.composite
def commit_message(draw):
    """Generate valid commit message."""
    # First line (subject) - ensure it's not empty after strip
    subject = draw(st.text(
        alphabet=string.ascii_letters + string.digits + ' _-.',
        min_size=10,
        max_size=72
    )).strip()

    # Ensure subject is not empty
    if not subject:
        subject = "Default commit message"

    # Body (optional)
    if draw(st.booleans()):
        body = draw(st.text(
            alphabet=string.ascii_letters + string.digits + ' \n_-.',
            min_size=0,
            max_size=500
        )).strip()

        # Only add body if it's not empty
        if body:
            return f"{subject}\n\n{body}"

    # Ensure no null bytes (PostgreSQL doesn't like them)
    return subject.replace('\x00', '')


@st.composite
def data_row(draw, columns: list[str]):
    """Generate data row matching column definitions."""
    row = {}

    for col_def in columns:
        col_name = col_def.split()[0]
        col_type = col_def.split()[1].upper()

        if 'INTEGER' in col_type or 'SERIAL' in col_type:
            row[col_name] = draw(st.integers(min_value=1, max_value=1_000_000))
        elif 'TEXT' in col_type or 'VARCHAR' in col_type:
            row[col_name] = draw(st.text(max_size=255))
        elif 'BOOLEAN' in col_type:
            row[col_name] = draw(st.booleans())
        elif 'TIMESTAMP' in col_type or 'DATE' in col_type:
            row[col_name] = 'CURRENT_TIMESTAMP'
        elif 'NUMERIC' in col_type:
            row[col_name] = draw(st.floats(
                min_value=-1e6,
                max_value=1e6,
                allow_nan=False,
                allow_infinity=False
            ))
        else:
            # Default to text for unknown types
            row[col_name] = draw(st.text(max_size=100))

    return row
```

### Step 2: Create Core Property-Based Tests (`tests/chaos/test_property_based_core.py`)

```python
"""
Property-based tests for core pggit functionality.
"""

import pytest
from hypothesis import given, strategies as st, assume, settings, HealthCheck
from hypothesis import Phase
import psycopg

from tests.chaos.strategies import (
    table_name, table_definition, git_branch_name, commit_message
)


@pytest.mark.chaos
@pytest.mark.property
class TestTableVersioningProperties:
    """Property-based tests for table versioning."""

    @given(tbl_def=table_definition())
    @settings(
        max_examples=50,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture]
    )
    def test_create_table_always_gets_version(
        self, sync_conn: psycopg.Connection, tbl_def: dict
    ):
        """Property: Creating any valid table assigns a version."""
        # Create table
        sync_conn.execute(tbl_def['create_sql'])
        sync_conn.commit()

        # Check version assigned
        cursor = sync_conn.execute(
            "SELECT * FROM pggit.get_version(%s)",
            (tbl_def['name'],)
        )
        version = cursor.fetchone()

        assert version is not None, f"Table {tbl_def['name']} should have version"
        assert version['major'] == 1, "Initial version should be 1.0.0"
        assert version['minor'] == 0
        assert version['patch'] == 0

    @given(
        tbl_def=table_definition(),
        branch1=git_branch_name(),
        branch2=git_branch_name()
    )
    @settings(
        max_examples=30,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture]
    )
    def test_trinity_id_unique_across_branches(
        self, sync_conn: psycopg.Connection, isolated_schema: str,
        tbl_def: dict, branch1: str, branch2: str
    ):
        """Property: Trinity IDs are unique across different branches."""
        assume(branch1 != branch2)  # Ensure different branches

        # Create table (in isolated schema for automatic cleanup)
        sync_conn.execute(tbl_def['create_sql'])
        sync_conn.commit()

        # Create commit on branch1
        cursor1 = sync_conn.execute(
            "SELECT pggit.commit_changes(%s, %s, %s)",
            (f"commit-{branch1}", branch1, "Initial commit")
        )
        trinity_id_1 = cursor1.fetchone()[0]

        # Create commit on branch2
        cursor2 = sync_conn.execute(
            "SELECT pggit.commit_changes(%s, %s, %s)",
            (f"commit-{branch2}", branch2, "Initial commit")
        )
        trinity_id_2 = cursor2.fetchone()[0]

        # Property: Trinity IDs must be unique
        assert trinity_id_1 != trinity_id_2, \
            f"Trinity IDs should be unique: {trinity_id_1} vs {trinity_id_2}"

    @given(msg=commit_message())
    @settings(max_examples=100, deadline=None)
    def test_commit_message_preserved(
        self, sync_conn: psycopg.Connection, isolated_schema: str, msg: str
    ):
        """Property: Commit messages are preserved exactly as written."""
        # Create a simple table
        sync_conn.execute("CREATE TABLE test_table (id SERIAL PRIMARY KEY)")
        sync_conn.commit()

        # Make commit with generated message
        cursor = sync_conn.execute(
            "SELECT pggit.commit_changes(%s, %s, %s)",
            ("test-commit", "main", msg)
        )
        commit_id = cursor.fetchone()[0]

        # Retrieve commit message
        cursor = sync_conn.execute(
            "SELECT message FROM pggit.commits WHERE id = %s",
            (commit_id,)
        )
        stored_msg = cursor.fetchone()['message']

        # Property: Message should be identical
        assert stored_msg == msg, "Commit message should be preserved exactly"


@pytest.mark.chaos
@pytest.mark.property
class TestVersionIncrementProperties:
    """Property-based tests for version increment logic.

    Note: These tests require pggit.increment_version() function.
    They will be skipped if the function doesn't exist yet.
    """

    @pytest.mark.skipif(
        not pggit_function_exists(psycopg.connect("dbname=pggit_chaos_test"), "increment_version"),
        reason="pggit.increment_version() not implemented yet"
    )
    @given(
        major=st.integers(min_value=0, max_value=100),
        minor=st.integers(min_value=0, max_value=100),
        patch=st.integers(min_value=0, max_value=100)
    )
    @settings(
        max_examples=50,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture]
    )
    def test_patch_increment_properties(
        self, sync_conn: psycopg.Connection, major: int, minor: int, patch: int
    ):
        """Property: Patch increment preserves major.minor."""
        cursor = sync_conn.execute(
            "SELECT pggit.increment_version(%s, %s, %s, 'patch')",
            (major, minor, patch)
        )
        new_version = cursor.fetchone()[0]

        # Parse version string
        new_major, new_minor, new_patch = map(int, new_version.split('.'))

        # Properties
        assert new_major == major, "Major version should not change"
        assert new_minor == minor, "Minor version should not change"
        assert new_patch == patch + 1, "Patch should increment by 1"

    @given(
        major=st.integers(min_value=0, max_value=100),
        minor=st.integers(min_value=0, max_value=100),
        patch=st.integers(min_value=0, max_value=100)
    )
    @settings(max_examples=50, deadline=None)
    def test_minor_increment_resets_patch(
        self, sync_conn: psycopg.Connection, major: int, minor: int, patch: int
    ):
        """Property: Minor increment resets patch to 0."""
        cursor = sync_conn.execute(
            "SELECT pggit.increment_version(%s, %s, %s, 'minor')",
            (major, minor, patch)
        )
        new_version = cursor.fetchone()[0]

        new_major, new_minor, new_patch = map(int, new_version.split('.'))

        # Properties
        assert new_major == major, "Major version should not change"
        assert new_minor == minor + 1, "Minor should increment by 1"
        assert new_patch == 0, "Patch should reset to 0"

    @given(
        major=st.integers(min_value=0, max_value=100),
        minor=st.integers(min_value=0, max_value=100),
        patch=st.integers(min_value=0, max_value=100)
    )
    @settings(max_examples=50, deadline=None)
    def test_major_increment_resets_minor_and_patch(
        self, sync_conn: psycopg.Connection, major: int, minor: int, patch: int
    ):
        """Property: Major increment resets minor and patch to 0."""
        cursor = sync_conn.execute(
            "SELECT pggit.increment_version(%s, %s, %s, 'major')",
            (major, minor, patch)
        )
        new_version = cursor.fetchone()[0]

        new_major, new_minor, new_patch = map(int, new_version.split('.'))

        # Properties
        assert new_major == major + 1, "Major should increment by 1"
        assert new_minor == 0, "Minor should reset to 0"
        assert new_patch == 0, "Patch should reset to 0"


@pytest.mark.chaos
@pytest.mark.property
class TestBranchNamingProperties:
    """Property-based tests for branch naming constraints."""

    @given(branch=git_branch_name())
    @settings(max_examples=100, deadline=None)
    def test_valid_branch_names_accepted(
        self, sync_conn: psycopg.Connection, branch: str
    ):
        """Property: All valid Git-style branch names should be accepted."""
        # Attempt to create branch via commit
        try:
            sync_conn.execute("CREATE TABLE test_tbl (id INT)")
            cursor = sync_conn.execute(
                "SELECT pggit.commit_changes(%s, %s, %s)",
                (f"commit-{branch[:30]}", branch, "Test commit")
            )
            result = cursor.fetchone()

            # Should succeed without error
            assert result is not None, f"Branch '{branch}' should be valid"

        except psycopg.Error as e:
            # If it fails, it should be due to a real constraint, not a crash
            assert "branch" in str(e).lower() or "invalid" in str(e).lower(), \
                f"Unexpected error for branch '{branch}': {e}"

        finally:
            sync_conn.rollback()  # Cleanup
```

### Step 3: Create Migration Property Tests (`tests/chaos/test_property_based_migrations.py`)

```python
"""
Property-based tests for migration operations.
"""

import pytest
from hypothesis import given, strategies as st, assume, settings, HealthCheck
import psycopg

from tests.chaos.strategies import table_definition


@pytest.mark.chaos
@pytest.mark.property
class TestMigrationIdempotency:
    """Property-based tests for migration idempotency."""

    @given(tbl_def=table_definition())
    @settings(
        max_examples=30,
        deadline=None,
        suppress_health_check=[HealthCheck.function_scoped_fixture]
    )
    def test_apply_migration_twice_is_safe(
        self, sync_conn: psycopg.Connection, tbl_def: dict
    ):
        """Property: Applying the same migration twice should be idempotent."""
        # Create initial table
        sync_conn.execute(tbl_def['create_sql'])
        sync_conn.commit()

        # Generate migration SQL (e.g., adding a column)
        migration_sql = f"ALTER TABLE {tbl_def['name']} ADD COLUMN IF NOT EXISTS new_col TEXT"

        # Apply migration first time
        sync_conn.execute(migration_sql)
        sync_conn.commit()

        # Get column count
        cursor1 = sync_conn.execute(f"""
            SELECT COUNT(*)
            FROM information_schema.columns
            WHERE table_name = %s
        """, (tbl_def['name'],))
        count1 = cursor1.fetchone()[0]

        # Apply migration second time (should be idempotent)
        sync_conn.execute(migration_sql)
        sync_conn.commit()

        # Get column count again
        cursor2 = sync_conn.execute(f"""
            SELECT COUNT(*)
            FROM information_schema.columns
            WHERE table_name = %s
        """, (tbl_def['name'],))
        count2 = cursor2.fetchone()[0]

        # Property: Column count should be identical
        assert count1 == count2, "Idempotent migration should not change schema"

    @given(tbl_def=table_definition())
    @settings(max_examples=20, deadline=None)
    def test_schema_hash_changes_on_modification(
        self, sync_conn: psycopg.Connection, tbl_def: dict
    ):
        """Property: Schema hash changes when table is modified."""
        # Create table
        sync_conn.execute(tbl_def['create_sql'])
        sync_conn.commit()

        # Get initial schema hash
        cursor1 = sync_conn.execute(
            "SELECT pggit.calculate_schema_hash(%s)",
            (tbl_def['name'],)
        )
        hash1 = cursor1.fetchone()[0]

        # Modify table
        sync_conn.execute(
            f"ALTER TABLE {tbl_def['name']} ADD COLUMN new_col_property TEXT"
        )
        sync_conn.commit()

        # Get new schema hash
        cursor2 = sync_conn.execute(
            "SELECT pggit.calculate_schema_hash(%s)",
            (tbl_def['name'],)
        )
        hash2 = cursor2.fetchone()[0]

        # Property: Hashes should differ
        assert hash1 != hash2, "Schema hash should change after modification"
```

### Step 4: Create Data Operation Property Tests (`tests/chaos/test_property_based_data.py`)

```python
"""
Property-based tests for data operations (branching, merging).
"""

import pytest
from hypothesis import given, strategies as st, assume, settings, HealthCheck
import psycopg

from tests.chaos.strategies import table_definition, data_row, git_branch_name


@pytest.mark.chaos
@pytest.mark.property
@pytest.mark.slow
class TestDataBranchingProperties:
    """Property-based tests for data branching (COW)."""

    @given(
        tbl_def=table_definition(),
        branch_name=git_branch_name()
    )
    @settings(max_examples=20, deadline=None)
    def test_branched_data_independent(
        self, sync_conn: psycopg.Connection, tbl_def: dict, branch_name: str
    ):
        """Property: Changes in branched data don't affect main branch."""
        assume(len(tbl_def['columns']) > 0)  # Need at least one column

        # Create table and insert row on main
        sync_conn.execute(tbl_def['create_sql'])

        # Get first column name for insert
        first_col = tbl_def['columns'][0].split()[0]
        sync_conn.execute(
            f"INSERT INTO {tbl_def['name']} ({first_col}) VALUES (%s)",
            ('main_value',)
        )
        sync_conn.commit()

        # Count rows on main
        cursor1 = sync_conn.execute(f"SELECT COUNT(*) FROM {tbl_def['name']}")
        main_count_before = cursor1.fetchone()[0]

        # Create branch (simulate data branching)
        sync_conn.execute(
            "SELECT pggit.create_data_branch(%s, %s, %s)",
            (tbl_def['name'], 'main', branch_name)
        )
        sync_conn.commit()

        # Insert row on branch
        sync_conn.execute(
            f"INSERT INTO {tbl_def['name']}__{branch_name} ({first_col}) VALUES (%s)",
            ('branch_value',)
        )
        sync_conn.commit()

        # Count rows on main again
        cursor2 = sync_conn.execute(f"SELECT COUNT(*) FROM {tbl_def['name']}")
        main_count_after = cursor2.fetchone()[0]

        # Property: Main branch row count unchanged
        assert main_count_before == main_count_after, \
            "Main branch should be unaffected by branch changes"
```

## Verification Commands

```bash
# Install chaos dependencies (if not already done)
uv pip install -e ".[chaos]"

# Run property-based tests
pytest tests/chaos/test_property_based_*.py -v -m property

# Run with more examples (thorough testing)
pytest tests/chaos/test_property_based_*.py -v \
  --hypothesis-show-statistics \
  --hypothesis-seed=12345

# Run specific property test class
pytest tests/chaos/test_property_based_core.py::TestTableVersioningProperties -v

# Check Hypothesis statistics
pytest tests/chaos/ -v --hypothesis-show-statistics
```

## Expected Outcome

### Tests Should:
- ✅ **FAIL initially** (RED phase) - Tests discover real edge cases
- ✅ Generate diverse test inputs (50-100 examples per property)
- ✅ Show Hypothesis statistics (shrinking, examples tried)
- ✅ Catch edge cases that manual tests miss
- ✅ Run within reasonable time (< 5 minutes total)

### Code Should:
- ✅ Use custom strategies for pggit domain objects
- ✅ Test universal properties, not specific examples
- ✅ Include shrinking to find minimal failing cases
- ✅ Have clear assertion messages

### Properties to Validate:
1. **Uniqueness**: Trinity IDs, versions, hashes
2. **Preservation**: Commit messages, data integrity
3. **Idempotency**: Migrations, version increments
4. **Isolation**: Branch independence, schema changes
5. **Correctness**: Version arithmetic, hash consistency

## Acceptance Criteria

- [ ] 4 test files created with 15+ property tests total
- [ ] Custom strategies for: tables, branches, commits, data
- [ ] Tests use `@given` decorator correctly
- [ ] Tests include `assume()` for preconditions
- [ ] Hypothesis settings configured (max_examples, deadline)
- [ ] All tests marked with `@pytest.mark.property`
- [ ] Tests fail initially, revealing real bugs (RED phase)
- [ ] Clear documentation of what properties are tested

## DO NOT

- ❌ Write example-based tests (use `@given` not hardcoded values)
- ❌ Test implementation details (test observable properties)
- ❌ Make property tests too slow (> 1 minute per test)
- ❌ Skip `assume()` for filtering invalid inputs
- ❌ Ignore Hypothesis shrinking output (shows minimal failing case)
- ❌ Use `typing.Optional` (use `X | None`)

## Notes

**Why Property-Based Testing?**

Traditional example-based tests might check:
- "Create table 'users' with 3 columns"
- "Commit message 'Initial commit' is preserved"

Property-based tests check:
- "Create ANY valid table with ANY valid columns"
- "ANY valid commit message is preserved"

This catches edge cases like:
- Table names with max length (63 chars)
- Commit messages with unicode, newlines, special chars
- Version numbers at boundary values (0, max int)

**Hypothesis Strategies**:
- Use `@st.composite` for complex domain objects
- Combine primitives (`st.integers`, `st.text`) for custom types
- `assume()` filters out invalid combinations
- Shrinking automatically finds minimal failing input

**Expected Bugs to Find**:
1. Trinity ID collisions with certain branch names
2. Commit message encoding issues (unicode)
3. Version increment edge cases (integer overflow)
4. Schema hash collisions
5. Branch name validation gaps

**Next Steps (GREEN Phase)**:
After tests fail (RED), Phase 3-6 will implement fixes to make property tests pass (GREEN). This may require:
- Refining Trinity ID generation algorithm
- Adding input validation
- Fixing edge cases in version arithmetic
- Improving schema hashing
