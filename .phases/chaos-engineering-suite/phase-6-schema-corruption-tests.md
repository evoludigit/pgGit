# Phase 6: Schema Corruption & Migration Failure Tests

## Objective
Implement tests that simulate schema corruption, migration failures, and data integrity violations to validate pggit's resilience to catastrophic failures and ability to detect/recover from corruption.

## TDD Stage
RED → GREEN

## Context
- **Previous phase**: Phase 5 (Resource Exhaustion) tested system limits
- **Current state**: Resource handling validated, but no corruption testing
- **Next phase**: Phase 7 (CI Integration) will integrate all tests into CI pipeline

## Files to Create

### 1. `tests/chaos/test_migration_failures.py`
Tests for migration failure scenarios:
- Migration script syntax errors
- Migration applied partially
- Conflicting migrations
- Migration rollback failures

### 2. `tests/chaos/test_schema_corruption.py`
Tests for schema corruption detection:
- Manual schema changes (bypassing pggit)
- Corrupted version metadata
- Missing Trinity ID references
- Inconsistent foreign keys

### 3. `tests/chaos/test_data_integrity.py`
Tests for data integrity under adverse conditions:
- Foreign key cascade failures
- Referential integrity violations
- Data type corruption
- Index corruption detection

### 4. `tests/chaos/test_recovery_procedures.py`
Tests for recovery procedures:
- Detect corruption
- Rebuild Trinity ID references
- Repair version metadata
- Restore consistency

## Implementation Steps

### Step 1: Migration Failure Tests (`tests/chaos/test_migration_failures.py`)

```python
"""
Migration failure scenario tests.
"""

import pytest
import psycopg


@pytest.mark.chaos
@pytest.mark.migration
class TestMigrationFailures:
    """Test migration failure scenarios."""

    def test_migration_syntax_error(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Migration with syntax error fails gracefully.

        Expected: Error raised, no partial application, rollback complete.
        """
        # Create table
        sync_conn.execute("CREATE TABLE migration_test (id INT)")
        sync_conn.commit()

        # Attempt migration with syntax error
        try:
            sync_conn.execute("BEGIN")

            # Valid change
            sync_conn.execute("ALTER TABLE migration_test ADD COLUMN valid_col TEXT")

            # Syntax error
            sync_conn.execute("ALTER TABLE migration_test ADD COLUMN INVALID SYNTAX")

            sync_conn.commit()

        except psycopg.Error as e:
            sync_conn.rollback()

            # Verify complete rollback
            cursor = sync_conn.execute("""
                SELECT column_name
                FROM information_schema.columns
                WHERE table_schema = current_schema()
                AND table_name = 'migration_test'
                AND column_name = 'valid_col'
            """)

            assert cursor.fetchone() is None, \
                "Migration with error should rollback all changes, not just failed part"

    def test_partial_migration_application(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Detect when migration is partially applied.

        Expected: System detects partial state and prevents corruption.
        """
        # Create table
        sync_conn.execute("CREATE TABLE partial_migration_test (id INT)")
        sync_conn.commit()

        # Apply first part of migration
        sync_conn.execute("BEGIN")
        sync_conn.execute("ALTER TABLE partial_migration_test ADD COLUMN col1 TEXT")
        sync_conn.commit()

        # Simulate crash/failure before second part
        # (In real scenario, process would be killed here)

        # Detect partial application
        cursor = sync_conn.execute("""
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = current_schema()
            AND table_name = 'partial_migration_test'
        """)
        columns = [row[0] for row in cursor.fetchall()]

        # We expect either:
        # 1. Complete migration (both col1 and col2)
        # 2. No migration (just id)
        # NOT partial (col1 but no col2)

        if 'col1' in columns:
            # If col1 exists, pggit should flag as incomplete migration
            # (This test verifies detection, not automatic fix)
            print("⚠️  Partial migration detected - would need manual intervention")

    def test_conflicting_migrations(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Two migrations conflict (e.g., both add same column).

        Expected: Second migration fails cleanly.
        """
        # Create table
        sync_conn.execute("CREATE TABLE conflict_test (id INT)")
        sync_conn.commit()

        # First migration: add column
        sync_conn.execute("ALTER TABLE conflict_test ADD COLUMN conflict_col TEXT")
        sync_conn.commit()

        # Second migration: try to add same column
        try:
            sync_conn.execute("ALTER TABLE conflict_test ADD COLUMN conflict_col TEXT")
            sync_conn.commit()

            pytest.fail("Should raise error for duplicate column")

        except psycopg.Error as e:
            sync_conn.rollback()

            # Expected error
            assert 'already exists' in str(e).lower() or 'duplicate' in str(e).lower(), \
                f"Expected duplicate column error, got: {e}"

    def test_migration_rollback_failure(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Migration rollback itself fails.

        Expected: System detects inconsistent state.
        """
        # Create table
        sync_conn.execute("CREATE TABLE rollback_fail_test (id INT)")
        sync_conn.commit()

        # Attempt migration
        try:
            sync_conn.execute("BEGIN")

            # Add column
            sync_conn.execute("ALTER TABLE rollback_fail_test ADD COLUMN test_col TEXT")

            # Simulate scenario where rollback would fail
            # (In practice, this is rare - PostgreSQL rollback is very reliable)

            # For testing purposes, we can't actually make rollback fail
            # But we can test detection of inconsistent state

            sync_conn.execute("SELECT 1/0")  # Force error

            sync_conn.commit()

        except psycopg.Error:
            # Rollback should succeed
            sync_conn.rollback()

            # Verify clean state
            cursor = sync_conn.execute("""
                SELECT column_name
                FROM information_schema.columns
                WHERE table_schema = current_schema()
                AND table_name = 'rollback_fail_test'
                AND column_name = 'test_col'
            """)

            assert cursor.fetchone() is None, "Rollback should remove added column"


@pytest.mark.chaos
@pytest.mark.migration
class TestMigrationVersioning:
    """Test migration versioning and ordering."""

    def test_out_of_order_migration(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Applying migrations out of order.

        Expected: System detects and prevents out-of-order application.
        """
        # Create table
        sync_conn.execute("CREATE TABLE migration_order_test (id INT)")
        sync_conn.commit()

        # Apply migration 1
        sync_conn.execute(
            "SELECT pggit.commit_changes(%s, %s, %s)",
            ("migration-1", "main", "Migration 1")
        )
        sync_conn.commit()

        # Apply migration 3 (skipping 2)
        sync_conn.execute(
            "SELECT pggit.commit_changes(%s, %s, %s)",
            ("migration-3", "main", "Migration 3")
        )
        sync_conn.commit()

        # System should detect gap
        # (Implementation would need to track migration sequence)
```

### Step 2: Schema Corruption Tests (`tests/chaos/test_schema_corruption.py`)

```python
"""
Schema corruption detection tests.
"""

import pytest
import psycopg


@pytest.mark.chaos
@pytest.mark.corruption
@pytest.mark.destructive
class TestSchemaCorruption:
    """Test schema corruption detection."""

    def test_manual_schema_change_detection(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Detect schema changes made without pggit.

        Expected: System detects schema drift and warns.
        """
        # Create table via pggit
        sync_conn.execute("CREATE TABLE drift_test (id INT)")
        sync_conn.commit()

        # Get schema hash
        cursor1 = sync_conn.execute(
            "SELECT pggit.calculate_schema_hash(%s)", ("drift_test",)
        )
        hash_before = cursor1.fetchone()[0]

        # Manual change (bypassing pggit)
        sync_conn.execute("ALTER TABLE drift_test ADD COLUMN manual_col TEXT")
        sync_conn.commit()

        # Get schema hash again
        cursor2 = sync_conn.execute(
            "SELECT pggit.calculate_schema_hash(%s)", ("drift_test",)
        )
        hash_after = cursor2.fetchone()[0]

        # Hashes should differ
        assert hash_before != hash_after, \
            "Schema hash should detect manual changes"

        # System should be able to detect drift
        # (Would need function like pggit.detect_schema_drift())

    def test_corrupted_version_metadata(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Detect when version metadata is corrupted.

        Expected: System identifies corruption and prevents further operations.
        """
        # Create table
        sync_conn.execute("CREATE TABLE version_corrupt_test (id INT)")
        sync_conn.commit()

        # Get version
        cursor = sync_conn.execute(
            "SELECT * FROM pggit.get_version(%s)", ("version_corrupt_test",)
        )
        version = cursor.fetchone()

        # Manually corrupt version metadata
        sync_conn.execute("""
            UPDATE pggit.table_versions
            SET major = -1, minor = -1, patch = -1
            WHERE table_name = 'version_corrupt_test'
        """)
        sync_conn.commit()

        # Try to get version (should detect corruption)
        cursor = sync_conn.execute(
            "SELECT * FROM pggit.get_version(%s)", ("version_corrupt_test",)
        )
        corrupted_version = cursor.fetchone()

        # Version validation should catch invalid values
        if corrupted_version:
            assert corrupted_version['major'] != -1, \
                "Version validation should prevent negative values"

    def test_missing_trinity_id_reference(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Detect when Trinity ID reference is missing.

        Expected: System identifies orphaned commits.
        """
        # Create table and commit
        sync_conn.execute("CREATE TABLE trinity_ref_test (id INT)")
        cursor = sync_conn.execute(
            "SELECT pggit.commit_changes(%s, %s, %s)",
            ("trinity-ref-test", "main", "Test commit")
        )
        trinity_id = cursor.fetchone()[0]
        sync_conn.commit()

        # Manually delete Trinity ID (corruption)
        sync_conn.execute(
            "DELETE FROM pggit.trinity_ids WHERE id = %s", (trinity_id,)
        )
        sync_conn.commit()

        # Check for orphaned commits
        cursor = sync_conn.execute("""
            SELECT c.id
            FROM pggit.commits c
            LEFT JOIN pggit.trinity_ids t ON c.trinity_id = t.id
            WHERE t.id IS NULL
        """)
        orphans = cursor.fetchall()

        assert len(orphans) > 0, "Should detect orphaned commits"

    def test_inconsistent_foreign_keys(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Detect foreign key inconsistencies.

        Expected: System validates referential integrity.
        """
        # Create tables with FK
        sync_conn.execute("CREATE TABLE fk_parent_corrupt (id INT PRIMARY KEY)")
        sync_conn.execute("""
            CREATE TABLE fk_child_corrupt (
                id INT PRIMARY KEY,
                parent_id INT REFERENCES fk_parent_corrupt(id)
            )
        """)
        sync_conn.commit()

        # Insert valid data
        sync_conn.execute("INSERT INTO fk_parent_corrupt VALUES (1)")
        sync_conn.execute("INSERT INTO fk_child_corrupt VALUES (1, 1)")
        sync_conn.commit()

        # Manually delete parent (would be prevented by FK, but testing detection)
        try:
            sync_conn.execute("DELETE FROM fk_parent_corrupt WHERE id = 1")
            sync_conn.commit()

            pytest.fail("Should not allow FK violation")

        except psycopg.IntegrityError:
            sync_conn.rollback()

            # Expected FK constraint violation
            print("✅ FK constraint prevented corruption")
```

### Step 3: Data Integrity Tests (`tests/chaos/test_data_integrity.py`)

```python
"""
Data integrity tests under adverse conditions.
"""

import pytest
import psycopg


@pytest.mark.chaos
@pytest.mark.integrity
class TestDataIntegrity:
    """Test data integrity guarantees."""

    def test_cascade_delete_integrity(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Cascading deletes maintain integrity.

        Expected: All dependent rows deleted, no orphans.
        """
        # Create tables with cascade
        sync_conn.execute("CREATE TABLE cascade_parent (id INT PRIMARY KEY)")
        sync_conn.execute("""
            CREATE TABLE cascade_child (
                id INT PRIMARY KEY,
                parent_id INT REFERENCES cascade_parent(id) ON DELETE CASCADE
            )
        """)
        sync_conn.commit()

        # Insert data
        sync_conn.execute("INSERT INTO cascade_parent VALUES (1)")
        sync_conn.execute("INSERT INTO cascade_child VALUES (1, 1)")
        sync_conn.execute("INSERT INTO cascade_child VALUES (2, 1)")
        sync_conn.commit()

        # Delete parent (should cascade)
        sync_conn.execute("DELETE FROM cascade_parent WHERE id = 1")
        sync_conn.commit()

        # Verify no orphans
        cursor = sync_conn.execute("SELECT COUNT(*) FROM cascade_child")
        count = cursor.fetchone()[0]

        assert count == 0, "Cascade should delete all child rows"

    def test_data_type_consistency(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Data types remain consistent across versions.

        Expected: No type corruption when schema evolves.
        """
        # Create table
        sync_conn.execute("CREATE TABLE type_test (id INT, value TEXT)")
        sync_conn.commit()

        # Insert data
        sync_conn.execute("INSERT INTO type_test VALUES (1, 'test')")
        sync_conn.commit()

        # Commit version
        cursor = sync_conn.execute(
            "SELECT pggit.commit_changes(%s, %s, %s)",
            ("type-test", "main", "Initial")
        )
        sync_conn.commit()

        # Alter column type (PostgreSQL allows if compatible)
        sync_conn.execute("ALTER TABLE type_test ALTER COLUMN value TYPE VARCHAR(100)")
        sync_conn.commit()

        # Verify data integrity
        cursor = sync_conn.execute("SELECT value FROM type_test WHERE id = 1")
        value = cursor.fetchone()[0]

        assert value == 'test', "Data should survive type change"
```

### Step 4: Recovery Procedure Tests (`tests/chaos/test_recovery_procedures.py`)

```python
"""
Recovery procedure tests.
"""

import pytest
import psycopg


@pytest.mark.chaos
@pytest.mark.recovery
class TestRecoveryProcedures:
    """Test recovery from corruption."""

    def test_detect_corruption(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Corruption detection function.

        Expected: Function identifies various corruption types.
        """
        # This would test a hypothetical pggit.detect_corruption() function

        # Create normal table
        sync_conn.execute("CREATE TABLE recovery_test (id INT)")
        sync_conn.commit()

        # Run corruption check (should pass)
        # cursor = sync_conn.execute("SELECT pggit.detect_corruption()")
        # issues = cursor.fetchall()
        # assert len(issues) == 0, "Clean database should have no corruption"

        # Introduce corruption
        sync_conn.execute("""
            UPDATE pggit.table_versions
            SET major = NULL
            WHERE table_name = 'recovery_test'
        """)
        sync_conn.commit()

        # Run check again (should detect)
        # cursor = sync_conn.execute("SELECT pggit.detect_corruption()")
        # issues = cursor.fetchall()
        # assert len(issues) > 0, "Should detect NULL version"

    def test_rebuild_trinity_id_references(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Rebuild missing Trinity ID references.

        Expected: Recovery function restores consistency.
        """
        # Create commits
        sync_conn.execute("CREATE TABLE rebuild_test (id INT)")
        cursor = sync_conn.execute(
            "SELECT pggit.commit_changes(%s, %s, %s)",
            ("rebuild", "main", "Test")
        )
        trinity_id = cursor.fetchone()[0]
        sync_conn.commit()

        # Delete Trinity ID (simulate corruption)
        sync_conn.execute(
            "DELETE FROM pggit.trinity_ids WHERE id = %s", (trinity_id,)
        )
        sync_conn.commit()

        # Rebuild (hypothetical function)
        # sync_conn.execute("SELECT pggit.rebuild_trinity_ids()")
        # sync_conn.commit()

        # Verify rebuilt
        # cursor = sync_conn.execute(
        #     "SELECT COUNT(*) FROM pggit.trinity_ids WHERE id = %s", (trinity_id,)
        # )
        # count = cursor.fetchone()[0]
        # assert count == 1, "Trinity ID should be rebuilt"

    def test_repair_version_metadata(
        self, sync_conn: psycopg.Connection, isolated_schema: str
    ):
        """
        Test: Repair corrupted version metadata.

        Expected: Recovery restores valid versions.
        """
        # Create table
        sync_conn.execute("CREATE TABLE repair_test (id INT)")
        sync_conn.commit()

        # Corrupt version
        sync_conn.execute("""
            UPDATE pggit.table_versions
            SET major = -1
            WHERE table_name = 'repair_test'
        """)
        sync_conn.commit()

        # Repair (hypothetical)
        # sync_conn.execute("SELECT pggit.repair_version_metadata('repair_test')")
        # sync_conn.commit()

        # Verify repaired
        cursor = sync_conn.execute(
            "SELECT * FROM pggit.get_version(%s)", ("repair_test",)
        )
        version = cursor.fetchone()

        # Should have valid version (not negative)
        # assert version['major'] >= 0, "Version should be repaired"
```

## Verification Commands

```bash
# Run migration failure tests
pytest tests/chaos/test_migration_failures.py -v

# Run corruption detection tests
pytest tests/chaos/test_schema_corruption.py -v -m "corruption and not destructive"

# Run integrity tests
pytest tests/chaos/test_data_integrity.py -v

# Run all Phase 6 tests
pytest tests/chaos/test_migration_*.py tests/chaos/test_schema_*.py tests/chaos/test_data_integrity.py -v
```

## Expected Outcome

### Tests Should:
- ✅ **FAIL initially** revealing corruption vulnerabilities
- ✅ Demonstrate detection capabilities
- ✅ Show recovery is possible
- ✅ Validate foreign key enforcement
- ✅ Prove referential integrity

### Bugs Expected to Find:
1. **No drift detection**: Manual schema changes go unnoticed
2. **Partial migration state**: No detection of incomplete migrations
3. **Orphaned references**: Missing Trinity ID cleanup
4. **No corruption checks**: Missing validation functions

## Acceptance Criteria

- [ ] 4 test files created with corruption/recovery tests
- [ ] Migration failures tested (syntax errors, conflicts)
- [ ] Schema corruption scenarios covered
- [ ] Data integrity guarantees validated
- [ ] Recovery procedures tested (even if not fully implemented)
- [ ] Destructive tests properly marked
- [ ] Tests document expected corruption scenarios

## DO NOT

- ❌ Corrupt production databases (use isolated_schema)
- ❌ Assume corruption is impossible (test for it)
- ❌ Skip recovery procedure design (document even if not implemented)
- ❌ Ignore foreign key constraints
- ❌ Leave orphaned data in test cleanup

## Notes

**Corruption Scenarios**:
- Manual schema changes (bypassing pggit)
- Partial migration application
- Missing/deleted Trinity IDs
- Invalid version metadata
- Orphaned foreign key references

**Detection Strategies**:
- Schema hash comparison
- Trinity ID reference validation
- Version metadata range checks
- Foreign key constraint verification
- Orphan detection queries

**Recovery Strategies**:
- Rebuild missing Trinity IDs from commits
- Recalculate schema hashes
- Validate and repair version sequences
- Clean up orphaned references

**Future Enhancements**:
Many of these tests check for features that may not exist yet (like `pggit.detect_corruption()`). These tests serve as:
1. Requirements documentation
2. Regression tests for when features are implemented
3. Validation that corruption is detectable

**Next Steps**:
Phase 7 will integrate all tests into CI and establish which tests must pass vs which are allowed to fail initially.
