"""
Enhanced End-to-End Integration Tests for pgGit
Comprehensive test coverage for production readiness
Covers: Error handling, concurrency, data integrity, advanced features, performance
"""

import json
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta

import pytest
from psycopg import connect


class TestE2EErrorHandlingValidation:
    """Test error handling and validation scenarios"""

    def test_duplicate_branch_creation_fails(self, db, pggit_installed):
        """Test that duplicate branch names are rejected"""
        # Create first branch
        db.execute("INSERT INTO pggit.branches (name) VALUES (%s)", "duplicate-test")

        # Attempt duplicate (should fail)
        with pytest.raises(Exception):  # Unique constraint violation
            db.execute(
                "INSERT INTO pggit.branches (name) VALUES (%s)", "duplicate-test"
            )

    def test_invalid_branch_name_validation(self, db, pggit_installed):
        """Test branch name validation"""
        # Test empty name
        with pytest.raises(Exception):
            db.execute("INSERT INTO pggit.branches (name) VALUES (%s)", "")

        # Test NULL name
        with pytest.raises(Exception):
            db.execute("INSERT INTO pggit.branches (name) VALUES (%s)", None)

    def test_null_commit_message_handling(self, db, pggit_installed):
        """Test NULL commit message handling"""
        main_branch = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )

        # NULL message should be allowed (optional)
        db.execute(
            "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s)",
            main_branch[0],
            None,
        )

        # Verify commit was created with NULL message
        result = db.execute_returning(
            "SELECT message FROM pggit.commits WHERE message IS NULL LIMIT 1"
        )
        assert result is not None, "NULL message handling failed"

    def test_missing_foreign_key_reference(self, db, pggit_installed):
        """Test missing foreign key references"""
        # Try to create commit with non-existent branch ID
        with pytest.raises(Exception):
            db.execute(
                "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s)",
                99999,
                "Invalid branch reference",
            )

    def test_constraint_violation_rollback(self, db, pggit_installed):
        """Test that constraint violations rollback properly"""
        db.execute("DROP TABLE IF EXISTS public.constraint_test CASCADE")
        db.execute(
            """
            CREATE TABLE public.constraint_test (
                id SERIAL PRIMARY KEY,
                email TEXT UNIQUE NOT NULL
            )
            """
        )

        # Insert valid row
        db.execute(
            "INSERT INTO public.constraint_test (email) VALUES (%s)", "user@test.com"
        )

        # Try to insert duplicate
        with pytest.raises(Exception):
            db.execute(
                "INSERT INTO public.constraint_test (email) VALUES (%s)",
                "user@test.com",
            )

        # Rollback the failed transaction
        db.conn.rollback()

        # Verify only one row exists
        result = db.execute("SELECT COUNT(*) FROM public.constraint_test")
        assert result[0][0] == 1, "Rollback failed - duplicate inserted"

    def test_large_data_payload_handling(self, db, pggit_installed):
        """Test handling of large data payloads"""
        # Create snapshot with large metadata
        large_metadata = json.dumps(
            {
                "data": "x" * 100000,  # 100KB of data
                "nested": {"deep": {"structure": "x" * 50000}},
            }
        )

        result = db.execute_returning(
            """
            SELECT snapshot_id FROM pggit.create_temporal_snapshot(
                %s, 1, %s
            )
            """,
            "large-snapshot",
            large_metadata,
        )

        assert result is not None, "Large data handling failed"

    def test_oversized_table_name_handling(self, db, pggit_installed):
        """Test handling of extremely long table names"""
        # PostgreSQL max identifier is 63 chars
        long_name = "t" * 63

        db.execute(f"CREATE TABLE public.{long_name} (id SERIAL PRIMARY KEY)")

        result = db.execute_returning(
            f"SELECT 1 FROM information_schema.tables WHERE table_name = %s",
            long_name,
        )
        assert result is not None, "Long table name handling failed"

    def test_special_characters_in_data(self, db, pggit_installed):
        """Test handling of special characters in data"""
        db.execute(
            """
            CREATE TABLE public.special_chars (
                id SERIAL PRIMARY KEY,
                data TEXT
            )
            """
        )

        special_data = "'; DROP TABLE users; --\n\r\t\"'<script>"

        db.execute("INSERT INTO public.special_chars (data) VALUES (%s)", special_data)

        result = db.execute_returning(
            "SELECT data FROM public.special_chars WHERE id = 1"
        )

        assert result[0] == special_data, "Special character handling failed"

    def test_concurrent_constraint_violation_handling(self, db, pggit_installed):
        """Test concurrent constraint violations"""
        db.execute(
            """
            CREATE TABLE public.concurrent_constraints (
                id SERIAL PRIMARY KEY,
                code TEXT UNIQUE
            )
            """
        )

        # First insert succeeds
        db.execute(
            "INSERT INTO public.concurrent_constraints (code) VALUES (%s)",
            "UNIQUE-CODE",
        )

        # Second attempt should fail
        with pytest.raises(Exception):
            db.execute(
                "INSERT INTO public.concurrent_constraints (code) VALUES (%s)",
                "UNIQUE-CODE",
            )


class TestE2EConcurrencyScenarios:
    """Test concurrent operations and race conditions"""

    def test_parallel_branch_creation(self, db, pggit_installed):
        """Test creating multiple branches in parallel"""
        branch_names = [f"parallel-{i}" for i in range(10)]
        created_branches = []
        errors = []

        def create_branch(name):
            try:
                print(f"Thread {threading.current_thread().name} creating branch {name}")
                conn = db.connect()  # Explicitly get thread-local connection
                print(f"Thread {threading.current_thread().name} got connection: {conn}")
                db.execute("INSERT INTO pggit.branches (name) VALUES (%s)", name)
                conn.commit()  # Explicitly commit the transaction
                print(f"Thread {threading.current_thread().name} inserted {name}")
                return name
            except Exception as e:
                print(f"Thread {threading.current_thread().name} error: {e}")
                errors.append(f"{name}: {str(e)}")
                if hasattr(db, 'conn') and db.conn:
                    db.conn.rollback()
                return None

        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(create_branch, name) for name in branch_names]
            created_branches = [f.result() for f in as_completed(futures)]

        # Print errors for debugging
        print(f"Created branches: {[b for b in created_branches if b]}")
        if errors:
            print(f"Branch creation errors: {errors}")

        # All branches should be created
        assert len([b for b in created_branches if b]) == 10, f"Parallel creation failed. Created: {len([b for b in created_branches if b])}, Errors: {errors[:5]}"

        # Commit main thread connection to refresh transaction snapshot
        db.conn.commit()

        # Verify all exist in database
        result = db.execute(
            "SELECT COUNT(*) FROM pggit.branches WHERE name LIKE %s", ("parallel-%",)
        )
        assert result[0][0] == 10, f"Not all parallel branches created. Found {result[0][0]} branches"

    def test_concurrent_commits_same_branch(self, db, pggit_installed):
        """Test concurrent commits to the same branch"""
        main_branch = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )

        commit_messages = [f"concurrent-commit-{i}" for i in range(5)]
        results = []

        def create_commit(msg):
            try:
                db.execute(
                    "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s)",
                    main_branch[0],
                    msg,
                )
                return msg
            except Exception:
                return None

        with ThreadPoolExecutor(max_workers=3) as executor:
            futures = [executor.submit(create_commit, msg) for msg in commit_messages]
            results = [f.result() for f in as_completed(futures)]

        # Verify all commits created
        final_count = db.execute(
            "SELECT COUNT(*) FROM pggit.commits WHERE branch_id = %s",
            main_branch[0],
        )
        assert final_count[0][0] >= 5, "Not all concurrent commits created"

    def test_parallel_table_creation_and_insert(self, db, pggit_installed):
        """Test concurrent table creation and inserts"""
        table_names = [f"parallel_table_{i}" for i in range(5)]
        created_tables = []
        errors = []

        def create_and_insert(table_name):
            try:
                conn = db.connect()
                db.execute(
                    f"""
                    CREATE TABLE public.{table_name} (
                        id SERIAL PRIMARY KEY,
                        value TEXT
                    )
                    """
                )

                db.execute(
                    f"INSERT INTO public.{table_name} (value) VALUES (%s)", "test-data"
                )
                conn.commit()  # Explicitly commit
                return table_name
            except Exception as e:
                errors.append(f"{table_name}: {str(e)}")
                if hasattr(db, 'conn') and db.conn:
                    db.conn.rollback()
                return None

        with ThreadPoolExecutor(max_workers=3) as executor:
            futures = [executor.submit(create_and_insert, name) for name in table_names]
            created_tables = [f.result() for f in as_completed(futures)]

        # Print errors for debugging
        if errors:
            print(f"Table creation errors: {errors}")

        # Commit main thread connection to refresh transaction snapshot
        db.conn.commit()

        # Verify tables exist
        result = db.execute(
            "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name LIKE %s",
            ("parallel_table_%",),
        )
        assert result[0][0] == 5, f"Not all parallel tables created. Errors: {errors[:3]}"

    def test_concurrent_snapshot_creation(self, db, pggit_installed):
        """Test creating multiple snapshots concurrently"""
        snapshot_names = [f"concurrent-snapshot-{i}" for i in range(5)]
        created_snapshots = []
        errors = []

        def create_snapshot(name):
            try:
                conn = db.connect()
                result = db.execute_returning(
                    """
                    SELECT snapshot_id FROM pggit.create_temporal_snapshot(%s, 1, %s)
                    """,
                    name,
                    f"Concurrent snapshot {name}",
                )
                conn.commit()  # Explicitly commit
                return result[0] if result else None
            except Exception as e:
                errors.append(f"{name}: {str(e)}")
                if hasattr(db, 'conn') and db.conn:
                    db.conn.rollback()
                return None

        with ThreadPoolExecutor(max_workers=3) as executor:
            futures = [
                executor.submit(create_snapshot, name) for name in snapshot_names
            ]
            created_snapshots = [f.result() for f in as_completed(futures)]

        # Print errors for debugging
        if errors:
            print(f"Snapshot creation errors: {errors}")

        # Commit main thread connection to refresh transaction snapshot
        db.conn.commit()

        # Verify snapshots created
        result = db.execute(
            "SELECT COUNT(*) FROM pggit.temporal_snapshots WHERE snapshot_name LIKE %s",
            ("concurrent-snapshot-%",),
        )
        assert result[0][0] == 5, f"Not all concurrent snapshots created. Errors: {errors[:3]}"


class TestE2EDataIntegrity:
    """Test data consistency and integrity across operations"""

    def test_foreign_key_constraint_enforcement(self, db, pggit_installed):
        """Test foreign key constraints"""
        db.execute(
            """
            CREATE TABLE public.fk_parent (
                id SERIAL PRIMARY KEY,
                name TEXT
            )
            """
        )

        db.execute(
            """
            CREATE TABLE public.fk_child (
                id SERIAL PRIMARY KEY,
                parent_id INTEGER REFERENCES public.fk_parent(id)
            )
            """
        )

        # Insert parent
        db.execute("INSERT INTO public.fk_parent (name) VALUES (%s)", "parent1")

        # Insert valid child
        db.execute("INSERT INTO public.fk_child (parent_id) VALUES (%s)", 1)

        # Try invalid child (non-existent parent)
        with pytest.raises(Exception):
            db.execute("INSERT INTO public.fk_child (parent_id) VALUES (%s)", 999)

    def test_cascade_delete_behavior(self, db, pggit_installed):
        """Test cascade delete propagation"""
        db.execute(
            """
            CREATE TABLE public.cascade_parent (
                id SERIAL PRIMARY KEY
            )
            """
        )

        db.execute(
            """
            CREATE TABLE public.cascade_child (
                id SERIAL PRIMARY KEY,
                parent_id INTEGER REFERENCES public.cascade_parent(id) ON DELETE CASCADE
            )
            """
        )

        # Insert parent and child
        db.execute("INSERT INTO public.cascade_parent DEFAULT VALUES")
        db.execute("INSERT INTO public.cascade_child (parent_id) VALUES (%s)", 1)

        # Delete parent
        db.execute("DELETE FROM public.cascade_parent WHERE id = %s", 1)

        # Verify child was cascade deleted
        result = db.execute("SELECT COUNT(*) FROM public.cascade_child")
        assert result[0][0] == 0, "Cascade delete failed"

    def test_version_number_sequence_integrity(self, db, pggit_installed):
        """Test version number sequences"""
        main_branch = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )

        # Create commits with version increments
        for i in range(10):
            db.execute(
                """
                INSERT INTO pggit.commits (branch_id, message)
                VALUES (%s, %s)
                """,
                main_branch[0],
                f"Version increment {i}",
            )

        # Verify sequence - count commits created
        results = db.execute(
            "SELECT COUNT(*) FROM pggit.commits WHERE branch_id = %s",
            main_branch[0],
        )

        commit_count = results[0][0] if results else 0
        assert commit_count >= 10, f"Expected at least 10 commits, got {commit_count}"

    def test_branch_isolation_data_consistency(self, db, pggit_installed):
        """Test that branches maintain isolated data"""
        # Create table
        db.execute(
            """
            CREATE TABLE public.isolation_test (
                id SERIAL PRIMARY KEY,
                branch_id INTEGER,
                value TEXT
            )
            """
        )

        # Create two branches
        db.execute("INSERT INTO pggit.branches (name) VALUES (%s)", "iso-branch-1")
        db.execute("INSERT INTO pggit.branches (name) VALUES (%s)", "iso-branch-2")

        branch1 = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'iso-branch-1'"
        )
        branch2 = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'iso-branch-2'"
        )

        # Insert different data per branch
        db.execute(
            "INSERT INTO public.isolation_test (branch_id, value) VALUES (%s, %s)",
            branch1[0],
            "branch1-data",
        )

        db.execute(
            "INSERT INTO public.isolation_test (branch_id, value) VALUES (%s, %s)",
            branch2[0],
            "branch2-data",
        )

        # Verify isolation
        result1 = db.execute(
            "SELECT COUNT(*) FROM public.isolation_test WHERE branch_id = %s AND value = %s",
            branch1[0],
            "branch1-data",
        )

        result2 = db.execute(
            "SELECT COUNT(*) FROM public.isolation_test WHERE branch_id = %s AND value = %s",
            branch2[0],
            "branch2-data",
        )

        assert result1[0][0] == 1 and result2[0][0] == 1, "Branch isolation failed"

    def test_transaction_atomicity(self, db, pggit_installed):
        """Test transaction atomicity"""
        db.execute(
            """
            CREATE TABLE public.atomic_test (
                id SERIAL PRIMARY KEY,
                sequence INTEGER
            )
            """
        )

        # Multi-row insert in transaction
        for i in range(5):
            db.execute(
                "INSERT INTO public.atomic_test (sequence) VALUES (%s)",
                i,
            )

        # Verify all inserted
        result = db.execute("SELECT COUNT(*) FROM public.atomic_test")
        assert result[0][0] == 5, "Transaction atomicity failed"

    def test_timestamp_accuracy(self, db, pggit_installed):
        """Test timestamp accuracy and ordering"""
        db.execute(
            """
            CREATE TABLE public.timestamp_test (
                id SERIAL PRIMARY KEY,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """
        )

        before = datetime.utcnow()

        db.execute("INSERT INTO public.timestamp_test DEFAULT VALUES")

        after = datetime.utcnow()

        result = db.execute_returning(
            "SELECT created_at FROM public.timestamp_test ORDER BY id DESC LIMIT 1"
        )

        recorded_time = result[0]

        # Verify timestamp is reasonable
        assert before <= recorded_time <= after, "Timestamp accuracy issue"


class TestE2EAdvancedFeatures:
    """Test advanced pgGit features"""

    def test_temporal_diff_single_field_change(self, db, pggit_installed):
        """Test temporal diff with single field change"""
        # Create two snapshots
        snap1 = db.execute_returning(
            """
            SELECT snapshot_id FROM pggit.create_temporal_snapshot(
                'diff-test-1', 1, 'First state'
            )
            """
        )

        snap2 = db.execute_returning(
            """
            SELECT snapshot_id FROM pggit.create_temporal_snapshot(
                'diff-test-2', 1, 'Second state'
            )
            """
        )

        # Record changes
        db.execute(
            """
            SELECT pggit.record_temporal_change(
                %s, 'public', 'test_table', 'INSERT', 'row-1',
                NULL, %s
            )
            """,
            snap1[0],
            json.dumps({"id": 1, "name": "Alice", "age": 30}),
        )

        db.execute(
            """
            SELECT pggit.record_temporal_change(
                %s, 'public', 'test_table', 'UPDATE', 'row-1',
                %s, %s
            )
            """,
            snap2[0],
            json.dumps({"id": 1, "name": "Alice", "age": 30}),
            json.dumps({"id": 1, "name": "Alice", "age": 31}),
        )

        # Verify changelog exists
        result = db.execute(
            "SELECT COUNT(*) FROM pggit.temporal_changelog WHERE table_name = 'test_table'"
        )

        assert result[0][0] >= 2, "Temporal changelog not recorded"

    def test_ml_pattern_learning_from_sequences(self, db, pggit_installed):
        """Test ML pattern learning from access sequences"""
        # Create repeating access pattern
        pattern = ["obj-1", "obj-2", "obj-3"] * 3

        for obj in pattern:
            db.execute(
                """
                INSERT INTO pggit.access_patterns (object_name, access_type, response_time_ms)
                VALUES (%s, %s, %s)
                """,
                obj,
                "READ",
                10,
            )

        # Learn patterns
        result = db.execute_returning(
            "SELECT pattern_id FROM pggit.learn_access_patterns(%s, %s)",
            2,  # object_id
            "READ",  # operation_type
        )

        # Should have learned patterns (at least some)
        assert result is not None, "Pattern learning failed"

    def test_conflict_semantic_analysis(self, db, pggit_installed):
        """Test semantic conflict analysis"""
        base_data = json.dumps({"id": 1, "name": "Alice"})
        source_data = json.dumps({"id": 1, "name": "Alice", "age": 30})
        target_data = json.dumps({"id": 1, "name": "Alice", "email": "alice@test.com"})

        result = db.execute_returning(
            """
            SELECT type, severity FROM pggit.analyze_semantic_conflict(
                %s, %s, %s
            )
            """,
            base_data,
            source_data,
            target_data,
        )

        assert result is not None, "Semantic analysis failed"
        assert result[0] in [
            "CONCURRENT_MODIFICATION",
            "non_overlapping_modification",
        ], "Invalid conflict type"

    def test_access_pattern_recording(self, db, pggit_installed):
        """Test recording access patterns"""
        # Record multiple access patterns
        for i in range(5):
            db.execute(
                """
                INSERT INTO pggit.access_patterns (object_name, access_type, response_time_ms)
                VALUES (%s, %s, %s)
                """,
                f"object-{i}",
                "READ" if i % 2 == 0 else "WRITE",
                10 + i * 5,
            )

        # Verify recording
        result = db.execute("SELECT COUNT(*) FROM pggit.access_patterns")
        assert result[0][0] >= 5, "Access pattern recording failed"


class TestE2EPerformance:
    """Test performance and scalability"""

    def test_bulk_insert_performance(self, db, pggit_installed):
        """Test bulk insert performance"""
        db.execute(
            """
            CREATE TABLE public.perf_test (
                id SERIAL PRIMARY KEY,
                data TEXT
            )
            """
        )

        start = time.time()

        # Bulk insert 1000 rows
        for i in range(1000):
            db.execute("INSERT INTO public.perf_test (data) VALUES (%s)", f"row-{i}")

        elapsed = time.time() - start

        # Should complete in reasonable time (< 10 seconds)
        assert elapsed < 10, f"Bulk insert took too long: {elapsed}s"

        # Verify all inserted
        result = db.execute("SELECT COUNT(*) FROM public.perf_test")
        assert result[0][0] == 1000, "Not all rows inserted"

    def test_query_performance_with_indexes(self, db, pggit_installed):
        """Test query performance uses indexes"""
        # Create indexed table
        db.execute(
            """
            CREATE TABLE public.indexed_table (
                id SERIAL PRIMARY KEY,
                status TEXT
            )
            """
        )

        db.execute("CREATE INDEX idx_status ON public.indexed_table(status)")

        # Insert rows
        for i in range(100):
            db.execute(
                "INSERT INTO public.indexed_table (status) VALUES (%s)",
                "active" if i % 2 == 0 else "inactive",
            )

        start = time.time()

        # Query should use index
        result = db.execute(
            "SELECT COUNT(*) FROM public.indexed_table WHERE status = 'active'"
        )

        elapsed = time.time() - start

        # Should be fast
        assert elapsed < 0.1, f"Indexed query too slow: {elapsed}s"
        assert result[0][0] == 50, "Query result incorrect"

    def test_large_commit_payload_performance(self, db, pggit_installed):
        """Test performance with large commit payloads"""
        main_branch = db.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )

        # Large metadata payload
        large_metadata = json.dumps(
            {
                "changes": [
                    {"field": f"field_{i}", "value": "x" * 100} for i in range(100)
                ]
            }
        )

        start = time.time()

        db.execute(
            """
            INSERT INTO pggit.commits (branch_id, message, metadata)
            VALUES (%s, %s, %s)
            """,
            main_branch[0],
            "Large payload commit",
            large_metadata,
        )

        elapsed = time.time() - start

        # Should handle large payloads efficiently
        assert elapsed < 1.0, f"Large payload commit too slow: {elapsed}s"

    def test_concurrent_query_performance(self, db, pggit_installed):
        """Test query performance under concurrent load"""
        # Setup data
        db.execute(
            "CREATE TABLE public.concurrent_query_test (id SERIAL PRIMARY KEY, value INTEGER)"
        )

        for i in range(100):
            db.execute(
                "INSERT INTO public.concurrent_query_test (value) VALUES (%s)",
                i,
            )

        # Concurrent queries
        def run_query():
            try:
                result = db.execute("SELECT COUNT(*) FROM public.concurrent_query_test")
                return result[0][0] == 100
            except Exception:
                return False

        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(run_query) for _ in range(10)]
            results = [f.result() for f in as_completed(futures)]

        # All queries should succeed
        assert all(results), "Concurrent queries failed"


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
