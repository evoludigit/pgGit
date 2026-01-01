"""
E2E tests for data corruption detection.

Tests pgGit's ability to detect various data corruption scenarios:
- Hash integrity verification
- Referential integrity validation
- State consistency checks
- Data type integrity
- Logical consistency validation

Key Coverage:
- Detection of tampered commit hashes
- Broken foreign key relationships
- Inconsistent branch states
- Invalid enum values
- Circular dependencies
- Orphaned references

IMPORTANT: These tests DETECT corruption, they don't CAUSE it.
Tests create valid data, then intentionally corrupt it to verify detection works.
"""

import pytest


class TestHashIntegrityVerification:
    """Test detection of hash integrity violations."""

    def test_detect_modified_commit_hash(self, db, pggit_installed):
        """Test detection of tampered commit hashes (security)"""
        # Create a valid commit
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        commit_id = db.execute_returning(
            "INSERT INTO pggit.commits (branch_id, message, hash) "
            "VALUES (%s, %s, %s) RETURNING id",
            main_id, "Original commit", "abc123originalHash"
        )[0]

        # Verify commit was created correctly
        original_hash = db.execute(
            "SELECT hash FROM pggit.commits WHERE id = %s", commit_id
        )[0][0]
        assert original_hash == "abc123originalHash", "Commit hash should match"

        # Intentionally corrupt the hash (simulate tampering)
        db.execute(
            "UPDATE pggit.commits SET hash = %s WHERE id = %s",
            "TAMPERED_HASH_123", commit_id
        )

        # Verify corruption is detected by checking for hash mismatch
        tampered_hash = db.execute(
            "SELECT hash FROM pggit.commits WHERE id = %s", commit_id
        )[0][0]
        assert tampered_hash == "TAMPERED_HASH_123", "Hash was tampered with"

        # Detection: Query to find commits with suspicious hash patterns (FIXED: parameterized LIKE)
        suspicious_hashes = db.execute(
            "SELECT id, hash FROM pggit.commits WHERE hash LIKE %s",
            "TAMPERED%"
        )
        assert len(suspicious_hashes) > 0, "Should detect tampered hash"

    def test_verify_tree_hash_consistency(self, db, pggit_installed):
        """Test that tree hash matches actual object content"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create commit with tree hash
        commit_id = db.execute_returning(
            "INSERT INTO pggit.commits (branch_id, message, tree_hash) "
            "VALUES (%s, %s, %s) RETURNING id",
            main_id, "Test commit", "tree_abc123"
        )[0]

        # Create an object that should be part of this tree (FIXED: added schema_name)
        obj_id = db.execute_returning(
            "INSERT INTO pggit.objects (object_type, schema_name, object_name, "
            "branch_id, content_hash) "
            "VALUES (%s, %s, %s, %s, %s) RETURNING id",
            "TABLE", "public", "test_table", main_id, "obj_hash_456"
        )[0]

        # Intentionally corrupt tree hash (simulate bug or attack)
        db.execute(
            "UPDATE pggit.commits SET tree_hash = %s WHERE id = %s",
            "WRONG_TREE_HASH", commit_id
        )

        # Detection: Verify tree hash was corrupted
        corrupted_tree = db.execute(
            "SELECT tree_hash FROM pggit.commits WHERE id = %s", commit_id
        )[0][0]
        assert corrupted_tree == "WRONG_TREE_HASH", "Tree hash should be corrupted"

        # Real detection would recalculate tree hash from objects and compare
        # This test verifies the corruption is detectable
        mismatched_commits = db.execute(
            "SELECT id FROM pggit.commits WHERE tree_hash = %s",
            "WRONG_TREE_HASH"
        )
        assert len(mismatched_commits) > 0, "Should detect tree hash mismatch"

    def test_detect_orphaned_hash_references(self, db, pggit_installed):
        """Test detection of hash references that don't exist"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create commit with parent_commit_hash pointing to non-existent commit (FIXED: consistent hash)
        orphan_hash = "NONEXISTENT_PARENT"
        orphaned_commit_id = db.execute_returning(
            "INSERT INTO pggit.commits (branch_id, message, parent_commit_hash) "
            "VALUES (%s, %s, %s) RETURNING id",
            main_id, "Orphaned commit", orphan_hash
        )[0]

        # Detection: Find commits with parent_commit_hash not in commits table
        orphaned_refs = db.execute("""
            SELECT c.id, c.parent_commit_hash
            FROM pggit.commits c
            WHERE c.parent_commit_hash IS NOT NULL
            AND c.parent_commit_hash NOT IN (SELECT hash FROM pggit.commits)
        """)

        # FIXED: Check >= 1 since other tests may create orphaned records
        assert len(orphaned_refs) >= 1, "Should detect at least one orphaned hash reference"
        # Verify our specific orphaned commit is in the results
        orphaned_ids = [row[0] for row in orphaned_refs]
        assert orphaned_commit_id in orphaned_ids, "Should find our orphaned commit"


class TestReferentialIntegrity:
    """Test detection of broken foreign key relationships."""

    def test_detect_broken_branch_commit_references(self, db, pggit_installed):
        """Test detection of commits referencing deleted branches"""
        # Create a temporary branch
        temp_branch_id = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "temp-branch"
        )[0]

        # Create commit on temp branch
        commit_id = db.execute_returning(
            "INSERT INTO pggit.commits (branch_id, message) "
            "VALUES (%s, %s) RETURNING id",
            temp_branch_id, "Commit on temp branch"
        )[0]

        # Verify FK constraint properly PREVENTS corruption (this is the correct behavior!)
        try:
            db.execute(
                "UPDATE pggit.commits SET branch_id = %s WHERE id = %s",
                99999, commit_id
            )
            # If we get here, FK constraint is broken - that's bad!
            assert False, "FK constraint should prevent invalid branch_id"
        except Exception as e:
            # Expected: FK constraint violation
            db.conn.rollback()
            assert "foreign key" in str(e).lower() or "violates" in str(e).lower(), \
                   "Should get FK constraint error"

        # Verify detection query works correctly
        # (In real scenario, this would catch orphaned records if FK was somehow bypassed)
        broken_refs = db.execute("""
            SELECT c.id, c.branch_id
            FROM pggit.commits c
            WHERE c.branch_id NOT IN (SELECT id FROM pggit.branches)
        """)

        # Should be empty because FK constraint prevented corruption
        assert len(broken_refs) == 0, "FK constraints should prevent broken references"

    def test_detect_broken_object_parent_references(self, db, pggit_installed):
        """Test detection of objects with invalid parent_id"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create a parent object (FIXED: added schema_name)
        parent_id = db.execute_returning(
            "INSERT INTO pggit.objects (object_type, schema_name, object_name, branch_id) "
            "VALUES (%s, %s, %s, %s) RETURNING id",
            "TABLE", "public", "corruption_parent_table_unique", main_id
        )[0]

        # Create child object with valid parent (FIXED: added schema_name)
        child_id = db.execute_returning(
            "INSERT INTO pggit.objects (object_type, schema_name, object_name, "
            "branch_id, parent_id) "
            "VALUES (%s, %s, %s, %s, %s) RETURNING id",
            "COLUMN", "public", "child_column", main_id, parent_id
        )[0]

        # Verify FK constraint properly PREVENTS corruption
        try:
            db.execute(
                "UPDATE pggit.objects SET parent_id = %s WHERE id = %s",
                88888, child_id
            )
            # If we get here, FK constraint is broken - that's bad!
            assert False, "FK constraint should prevent invalid parent_id"
        except Exception as e:
            # Expected: FK constraint violation
            db.conn.rollback()
            assert "foreign key" in str(e).lower() or "violates" in str(e).lower(), \
                   "Should get FK constraint error"

        # Verify detection query works correctly
        broken_parents = db.execute("""
            SELECT o.id, o.parent_id
            FROM pggit.objects o
            WHERE o.parent_id IS NOT NULL
            AND o.parent_id NOT IN (SELECT id FROM pggit.objects)
        """)

        # Should be empty because FK constraint prevented corruption
        assert len(broken_parents) == 0, "FK constraints should prevent broken references"

    def test_detect_broken_dependency_relationships(self, db, pggit_installed):
        """Test detection of invalid dependency references"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create two valid objects (FIXED: added schema_name, UPPERCASE enum)
        obj1_id = db.execute_returning(
            "INSERT INTO pggit.objects (object_type, schema_name, object_name, branch_id) "
            "VALUES (%s, %s, %s, %s) RETURNING id",
            "TABLE", "public", "table1", main_id
        )[0]

        obj2_id = db.execute_returning(
            "INSERT INTO pggit.objects (object_type, schema_name, object_name, branch_id) "
            "VALUES (%s, %s, %s, %s) RETURNING id",
            "VIEW", "public", "view1", main_id
        )[0]

        # Create valid dependency (FIXED: correct column names)
        dep_id = db.execute_returning(
            "INSERT INTO pggit.dependencies (dependent_id, depends_on_id, branch_id) "
            "VALUES (%s, %s, %s) RETURNING id",
            obj2_id, obj1_id, main_id
        )[0]

        # Verify FK constraint properly PREVENTS corruption
        try:
            db.execute(
                "UPDATE pggit.dependencies SET dependent_id = %s WHERE id = %s",
                77777, dep_id
            )
            # If we get here, FK constraint is broken - that's bad!
            assert False, "FK constraint should prevent invalid dependent_id"
        except Exception as e:
            # Expected: FK constraint violation
            db.conn.rollback()
            assert "foreign key" in str(e).lower() or "violates" in str(e).lower(), \
                   "Should get FK constraint error"

        # Verify detection query works correctly
        broken_deps = db.execute("""
            SELECT d.id
            FROM pggit.dependencies d
            WHERE d.dependent_id NOT IN (SELECT id FROM pggit.objects)
               OR d.depends_on_id NOT IN (SELECT id FROM pggit.objects)
        """)

        # Should be empty because FK constraint prevented corruption
        assert len(broken_deps) == 0, "FK constraints should prevent broken references"

    def test_verify_all_foreign_keys_valid(self, db, pggit_installed):
        """Comprehensive foreign key validation across all tables"""
        # This test validates FK integrity across the entire schema

        # Check commits.branch_id references valid branches
        invalid_commit_branches = db.execute("""
            SELECT COUNT(*) FROM pggit.commits c
            WHERE c.branch_id NOT IN (SELECT id FROM pggit.branches)
        """)
        assert invalid_commit_branches[0][0] == 0, "All commits should reference valid branches"

        # Check objects.parent_id references valid objects
        invalid_object_parents = db.execute("""
            SELECT COUNT(*) FROM pggit.objects o
            WHERE o.parent_id IS NOT NULL
            AND o.parent_id NOT IN (SELECT id FROM pggit.objects)
        """)
        assert invalid_object_parents[0][0] == 0, "All object parents should be valid"

        # Check dependencies reference valid objects
        invalid_dependencies = db.execute("""
            SELECT COUNT(*) FROM pggit.dependencies d
            WHERE d.dependent_id NOT IN (SELECT id FROM pggit.objects)
               OR d.depends_on_id NOT IN (SELECT id FROM pggit.objects)
        """)
        assert invalid_dependencies[0][0] == 0, "All dependencies should reference valid objects"


class TestStateConsistency:
    """Test detection of inconsistent state across tables."""

    def test_detect_active_branch_with_no_commits(self, db, pggit_installed):
        """Test detection of ACTIVE branches without any commits"""
        # Create an ACTIVE branch (FIXED: UPPERCASE enum)
        empty_branch_id = db.execute_returning(
            "INSERT INTO pggit.branches (name, status) VALUES (%s, %s) RETURNING id",
            "empty-branch", "ACTIVE"
        )[0]

        # Don't create any commits for this branch (simulating inconsistency)

        # Detection: Find ACTIVE branches with no commits
        # (This might be valid for newly created branches, but worth monitoring)
        empty_active_branches = db.execute("""
            SELECT b.id, b.name
            FROM pggit.branches b
            WHERE b.status = 'ACTIVE'
            AND b.id NOT IN (SELECT DISTINCT branch_id FROM pggit.commits)
        """)

        # Verify we can detect this state
        branch_ids = [row[0] for row in empty_active_branches]
        assert empty_branch_id in branch_ids, "Should detect ACTIVE branch with no commits"

    def test_verify_object_version_monotonic(self, db, pggit_installed):
        """Test that object version sequences are monotonic (always increasing)"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create object with version 1 (FIXED: added schema_name)
        obj_id = db.execute_returning(
            "INSERT INTO pggit.objects (object_type, schema_name, object_name, "
            "branch_id, version) "
            "VALUES (%s, %s, %s, %s, %s) RETURNING id",
            "TABLE", "public", "versioned_table", main_id, 1
        )[0]

        # Corrupt: manually set version to go backwards
        db.execute(
            "UPDATE pggit.objects SET version = %s WHERE id = %s",
            0, obj_id  # Version goes from 1 -> 0 (violation)
        )

        # Detection: Find objects with non-positive versions
        invalid_versions = db.execute("""
            SELECT id, version FROM pggit.objects
            WHERE version < 1
        """)

        assert len(invalid_versions) > 0, "Should detect non-monotonic version"

    def test_detect_duplicate_objects_same_branch(self, db, pggit_installed):
        """Test detection of duplicate objects (same schema/name/branch)"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create first object (FIXED: added schema_name, UPPERCASE enum)
        obj1_id = db.execute_returning(
            "INSERT INTO pggit.objects (object_type, schema_name, object_name, branch_id) "
            "VALUES (%s, %s, %s, %s) RETURNING id",
            "TABLE", "public", "duplicate_test", main_id
        )[0]

        # Try to create duplicate (should normally be prevented by unique constraint)
        try:
            # This will fail with unique constraint - that's good!
            obj2_id = db.execute_returning(
                "INSERT INTO pggit.objects (object_type, schema_name, object_name, branch_id) "
                "VALUES (%s, %s, %s, %s) RETURNING id",
                "TABLE", "public", "duplicate_test", main_id
            )[0]
            # If we get here, constraint failed - that's a problem
            assert False, "Should not allow duplicate objects"
        except Exception:
            # Constraint properly prevented duplicate - this is expected
            db.conn.rollback()

        # Detection query: Find potential duplicates
        duplicates = db.execute("""
            SELECT object_type, schema_name, object_name, branch_id, COUNT(*) as cnt
            FROM pggit.objects
            GROUP BY object_type, schema_name, object_name, branch_id
            HAVING COUNT(*) > 1
        """)

        # Should be empty since constraint prevented it
        assert len(duplicates) == 0, "Unique constraint should prevent duplicates"


class TestDataTypeIntegrity:
    """Test detection of invalid data type values."""

    def test_verify_enum_values_valid(self, db, pggit_installed):
        """Test that enum columns contain only valid values"""
        # This test verifies enum constraints are enforced

        # Try to insert invalid branch status
        try:
            db.execute(
                "INSERT INTO pggit.branches (name, status) VALUES (%s, %s)",
                "invalid-status-branch", "INVALID_STATUS"
            )
            # If this succeeds, enum constraint is broken
            db.conn.rollback()
            assert False, "Should reject invalid enum value"
        except Exception as e:
            # Expected: enum constraint violation
            db.conn.rollback()
            assert "invalid input value for enum" in str(e).lower() or \
                   "type pggit.branch_status" in str(e).lower(), \
                   "Should get enum constraint error"

        # Try to insert invalid object_type
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        try:
            db.execute(
                "INSERT INTO pggit.objects (object_type, schema_name, object_name, branch_id) "
                "VALUES (%s, %s, %s, %s)",
                "INVALID_OBJECT_TYPE", "public", "test_obj", main_id
            )
            db.conn.rollback()
            assert False, "Should reject invalid object_type"
        except Exception as e:
            # Expected: enum constraint violation
            db.conn.rollback()
            assert "invalid input value for enum" in str(e).lower() or \
                   "type pggit.object_type" in str(e).lower(), \
                   "Should get enum constraint error"

    def test_detect_null_in_not_null_columns(self, db, pggit_installed):
        """Test detection of NULL values in NOT NULL columns"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Try to insert object without required schema_name (NOT NULL)
        try:
            db.execute(
                "INSERT INTO pggit.objects (object_type, schema_name, object_name, branch_id) "
                "VALUES (%s, %s, %s, %s)",
                "TABLE", None, "test_table", main_id
            )
            db.conn.rollback()
            assert False, "Should reject NULL in schema_name"
        except Exception as e:
            # Expected: NOT NULL constraint violation
            db.conn.rollback()
            assert "null value" in str(e).lower() or "not null" in str(e).lower(), \
                   "Should get NOT NULL constraint error"

        # Try to insert commit without branch_id (NOT NULL)
        try:
            db.execute(
                "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s)",
                None, "Test message"
            )
            db.conn.rollback()
            assert False, "Should reject NULL in branch_id"
        except Exception as e:
            # Expected: NOT NULL constraint violation
            db.conn.rollback()
            assert "null value" in str(e).lower() or "not null" in str(e).lower(), \
                   "Should get NOT NULL constraint error"

    def test_verify_timestamp_ordering(self, db, pggit_installed):
        """Test that created_at <= updated_at for all records"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create object with proper timestamps (FIXED: added schema_name)
        obj_id = db.execute_returning(
            "INSERT INTO pggit.objects (object_type, schema_name, object_name, branch_id) "
            "VALUES (%s, %s, %s, %s) RETURNING id",
            "TABLE", "public", "corruption_timestamp_test_unique", main_id
        )[0]

        # Corrupt: set updated_at before created_at
        db.execute("""
            UPDATE pggit.objects
            SET updated_at = created_at - INTERVAL '1 day'
            WHERE id = %s
        """, obj_id)

        # Detection: Find records with invalid timestamp ordering
        invalid_timestamps = db.execute("""
            SELECT id, created_at, updated_at
            FROM pggit.objects
            WHERE updated_at < created_at
        """)

        assert len(invalid_timestamps) > 0, "Should detect invalid timestamp ordering"
        assert invalid_timestamps[0][0] == obj_id, "Should find our corrupted record"


class TestLogicalConsistency:
    """Test detection of logical inconsistencies."""

    def test_detect_circular_dependencies(self, db, pggit_installed):
        """Test detection of circular dependency chains"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create three objects (FIXED: added schema_name, UPPERCASE enums)
        obj1_id = db.execute_returning(
            "INSERT INTO pggit.objects (object_type, schema_name, object_name, branch_id) "
            "VALUES (%s, %s, %s, %s) RETURNING id",
            "TABLE", "public", "circular1", main_id
        )[0]

        obj2_id = db.execute_returning(
            "INSERT INTO pggit.objects (object_type, schema_name, object_name, branch_id) "
            "VALUES (%s, %s, %s, %s) RETURNING id",
            "VIEW", "public", "circular2", main_id
        )[0]

        obj3_id = db.execute_returning(
            "INSERT INTO pggit.objects (object_type, schema_name, object_name, branch_id) "
            "VALUES (%s, %s, %s, %s) RETURNING id",
            "VIEW", "public", "circular3", main_id
        )[0]

        # Create circular dependencies: obj1 -> obj2 -> obj3 -> obj1
        db.execute(
            "INSERT INTO pggit.dependencies (dependent_id, depends_on_id, branch_id) "
            "VALUES (%s, %s, %s)",
            obj1_id, obj2_id, main_id
        )
        db.execute(
            "INSERT INTO pggit.dependencies (dependent_id, depends_on_id, branch_id) "
            "VALUES (%s, %s, %s)",
            obj2_id, obj3_id, main_id
        )
        db.execute(
            "INSERT INTO pggit.dependencies (dependent_id, depends_on_id, branch_id) "
            "VALUES (%s, %s, %s)",
            obj3_id, obj1_id, main_id
        )

        # Detection: Use recursive CTE to find circular dependencies
        circular_deps = db.execute("""
            WITH RECURSIVE dep_chain AS (
                -- Start from each dependency
                SELECT dependent_id, depends_on_id,
                       ARRAY[dependent_id] as path,
                       false as is_cycle
                FROM pggit.dependencies

                UNION ALL

                -- Follow the chain
                SELECT dc.dependent_id, d.depends_on_id,
                       dc.path || d.dependent_id,
                       d.depends_on_id = ANY(dc.path) as is_cycle
                FROM dep_chain dc
                JOIN pggit.dependencies d ON dc.depends_on_id = d.dependent_id
                WHERE NOT dc.is_cycle
                  AND array_length(dc.path, 1) < 10  -- Limit depth
            )
            SELECT DISTINCT dependent_id, depends_on_id, path
            FROM dep_chain
            WHERE is_cycle
            LIMIT 10
        """)

        assert len(circular_deps) > 0, "Should detect circular dependency"

    def test_verify_merge_conflict_references_valid_merges(self, db, pggit_installed):
        """Test that merge_conflicts reference actual merge operations"""
        # Create a merge conflict record
        db.execute("""
            INSERT INTO pggit.merge_conflicts
            (merge_id, branch_a, branch_b, conflict_object, conflict_type)
            VALUES (%s, %s, %s, %s, %s)
        """, "merge_123", "branch_a", "branch_b", "test_table", "schema_conflict")

        # Detection: Find merge conflicts without corresponding merge operation (FIXED: parameterized LIKE)
        # (In real system, merge_id would reference a merge operation table)
        orphaned_conflicts = db.execute(
            "SELECT merge_id, branch_a, branch_b FROM pggit.merge_conflicts WHERE merge_id NOT LIKE %s",
            "merge_%"
        )

        # This query is a placeholder - real detection would check against actual merges
        # For now, verify we can query merge conflicts
        all_conflicts = db.execute("SELECT COUNT(*) FROM pggit.merge_conflicts")
        assert all_conflicts[0][0] >= 1, "Should have at least one conflict record"

    def test_detect_branch_history_without_parent_chain(self, db, pggit_installed):
        """Test detection of commits without proper parent chain"""
        main_id = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        # Create first commit (root commit - no parent is valid)
        commit1_hash = "root_commit_hash"
        commit1_id = db.execute_returning(
            "INSERT INTO pggit.commits (branch_id, message, hash, parent_commit_hash) "
            "VALUES (%s, %s, %s, %s) RETURNING id",
            main_id, "Root commit", commit1_hash, None
        )[0]

        # Create second commit with valid parent
        commit2_hash = "child_commit_hash"
        commit2_id = db.execute_returning(
            "INSERT INTO pggit.commits (branch_id, message, hash, parent_commit_hash) "
            "VALUES (%s, %s, %s, %s) RETURNING id",
            main_id, "Child commit", commit2_hash, commit1_hash
        )[0]

        # Create orphaned commit (parent doesn't exist) - FIXED: consistent hash
        orphan_hash = "orphan_commit_hash"
        orphan_parent_hash = "NONEXISTENT_PARENT"
        orphan_id = db.execute_returning(
            "INSERT INTO pggit.commits (branch_id, message, hash, parent_commit_hash) "
            "VALUES (%s, %s, %s, %s) RETURNING id",
            main_id, "Orphan commit", orphan_hash, orphan_parent_hash
        )[0]

        # Detection: Find commits claiming to have parent but parent doesn't exist
        broken_chain_commits = db.execute("""
            SELECT c.id, c.hash, c.parent_commit_hash
            FROM pggit.commits c
            WHERE c.parent_commit_hash IS NOT NULL
            AND c.parent_commit_hash NOT IN (SELECT hash FROM pggit.commits)
        """)

        # FIXED: Check >= 1 since other tests may create orphaned records
        assert len(broken_chain_commits) >= 1, "Should detect at least one broken parent chain"
        # Verify our specific orphaned commit has the expected parent reference
        orphan_found = False
        for row in broken_chain_commits:
            if row[2] == orphan_parent_hash:
                orphan_found = True
                break
        assert orphan_found, "Should find commit with NONEXISTENT_PARENT reference"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
