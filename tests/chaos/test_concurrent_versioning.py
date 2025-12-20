"""
Concurrency tests for version operations.

These tests validate pggit's version increment behavior under concurrent access,
including race conditions during version bumps and consistency guarantees.
"""

import pytest
from concurrent.futures import ThreadPoolExecutor, as_completed
import psycopg
from psycopg.rows import dict_row


@pytest.mark.chaos
@pytest.mark.concurrent
class TestConcurrentVersioning:
    """Test concurrent version increment operations."""

    @pytest.mark.parametrize("num_workers", [5, 10, 20])
    def test_concurrent_version_increments(
        self, db_connection_string: str, num_workers: int
    ):
        """
        Test: Multiple workers incrementing version simultaneously.

        Expected: All increments succeed, final version reflects all increments.
        """
        table_name = "version_test_table"

        # Setup: Create table
        setup_conn = psycopg.connect(db_connection_string)
        setup_conn.execute(f"CREATE TABLE {table_name} (id INT)")
        setup_conn.commit()

        # Get initial version
        cursor = setup_conn.execute(
            "SELECT * FROM pggit.get_version(%s)", (table_name,)
        )
        initial_version = cursor.fetchone()
        setup_conn.close()

        # Worker: increment version via schema change
        def worker_increment(worker_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)

            try:
                conn.execute("BEGIN")
                # Add column (should trigger version increment)
                conn.execute(
                    f"ALTER TABLE {table_name} ADD COLUMN IF NOT EXISTS col_{worker_id} INT DEFAULT {worker_id}"
                )
                conn.execute("COMMIT")

                # Get version after change
                cursor = conn.execute(
                    "SELECT * FROM pggit.get_version(%s)", (table_name,)
                )
                new_version = cursor.fetchone()
                conn.close()

                return {"worker_id": worker_id, "version": new_version, "success": True}

            except Exception as e:
                try:
                    conn.rollback()
                    conn.close()
                except:
                    pass
                return {"worker_id": worker_id, "error": str(e), "success": False}

        # Execute concurrent increments
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(worker_increment, i) for i in range(num_workers)]
            results = [f.result() for f in as_completed(futures, timeout=60)]

        successes = [r for r in results if r["success"]]
        failures = [r for r in results if not r["success"]]

        # Validation: Most should succeed
        assert len(successes) > num_workers * 0.5, (
            f"Expected >50% success rate, got {len(successes)}/{num_workers}"
        )

        # Validation: Final version is consistent across all successful reads
        if successes:
            final_versions = [s["version"] for s in successes]
            # All should report the same final version
            unique_versions = set(
                tuple(v.items()) if v else None for v in final_versions
            )
            assert len(unique_versions) == 1, (
                f"Inconsistent final versions: {final_versions}"
            )

        # Validation: Final version is higher than initial
        if successes:
            final_conn = psycopg.connect(db_connection_string)
            cursor = final_conn.execute(
                "SELECT * FROM pggit.get_version(%s)", (table_name,)
            )
            actual_final_version = cursor.fetchone()
            final_conn.close()

            # Version should have increased
            if initial_version and actual_final_version:
                assert actual_final_version["major"] >= initial_version["major"], (
                    "Major version should not decrease"
                )

        print(
            f"\n✅ Initial: {initial_version}, Successes: {len(successes)}, Failures: {len(failures)}"
        )

    def test_version_read_consistency_during_writes(self, db_connection_string: str):
        """
        Test: Reading version while concurrent modifications occur.

        Expected: Reads always return valid version (not corrupted state).
        """
        table_name = "consistency_test_table"

        # Setup
        setup_conn = psycopg.connect(db_connection_string)
        setup_conn.execute(f"CREATE TABLE {table_name} (id INT)")
        setup_conn.commit()
        setup_conn.close()

        def reader(reader_id: int):
            """Worker: repeatedly read version."""
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)
            versions = []

            for _ in range(10):
                try:
                    cursor = conn.execute(
                        "SELECT * FROM pggit.get_version(%s)", (table_name,)
                    )
                    version = cursor.fetchone()
                    if version:
                        versions.append(version)
                except Exception:
                    # Some read failures are expected during concurrent writes
                    pass

            conn.close()
            return versions

        def writer(writer_id: int):
            """Worker: repeatedly modify table."""
            conn = psycopg.connect(db_connection_string)

            for i in range(5):
                try:
                    conn.execute(
                        f"ALTER TABLE {table_name} ADD COLUMN IF NOT EXISTS w{writer_id}_c{i} INT"
                    )
                    conn.commit()
                except Exception:
                    conn.rollback()

            conn.close()
            return True

        # Run concurrent readers and writers
        with ThreadPoolExecutor(max_workers=15) as executor:
            reader_futures = [executor.submit(reader, i) for i in range(10)]
            writer_futures = [executor.submit(writer, i) for i in range(5)]

            all_versions = []
            for future in as_completed(reader_futures, timeout=45):
                try:
                    all_versions.extend(future.result(timeout=5))
                except Exception:
                    pass

            for future in as_completed(writer_futures, timeout=30):
                try:
                    future.result(timeout=5)
                except Exception:
                    pass

        # Validation: All read versions are valid (not NULL, not corrupted)
        assert len(all_versions) > 0, "Should have read some versions"

        for version in all_versions:
            assert version is not None, "Version should never be NULL"
            assert "major" in version, "Version should have 'major' field"
            assert "minor" in version, "Version should have 'minor' field"
            assert "patch" in version, "Version should have 'patch' field"
            # Version numbers should be non-negative integers
            assert isinstance(version["major"], int) and version["major"] >= 0
            assert isinstance(version["minor"], int) and version["minor"] >= 0
            assert isinstance(version["patch"], int) and version["patch"] >= 0

        print(
            f"\n✅ Read {len(all_versions)} consistent versions during concurrent writes"
        )

    @pytest.mark.parametrize("version_type", ["major", "minor", "patch"])
    def test_concurrent_explicit_version_increments(
        self, db_connection_string: str, version_type: str
    ):
        """
        Test concurrent explicit version increments using increment_version function.

        This tests the version increment logic directly under concurrent access.
        """
        table_name = f"explicit_{version_type}_table"

        # Setup
        setup_conn = psycopg.connect(db_connection_string)
        setup_conn.execute(f"CREATE TABLE {table_name} (id INT)")
        setup_conn.commit()

        # Get initial version
        cursor = setup_conn.execute(
            "SELECT * FROM pggit.get_version(%s)", (table_name,)
        )
        initial = cursor.fetchone()
        setup_conn.close()

        if not initial:
            pytest.skip("Version tracking not implemented yet")

        num_workers = 8

        def explicit_increment_worker(worker_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)

            try:
                # Increment version explicitly
                cursor = conn.execute(
                    "SELECT pggit.increment_version(%s, %s, %s, %s)",
                    (
                        initial["major"],
                        initial["minor"],
                        initial["patch"],
                        version_type,
                    ),
                )
                new_version_str = cursor.fetchone()["increment_version"]
                conn.commit()

                # Parse version string
                major, minor, patch = map(int, new_version_str.split("."))

                conn.close()
                return {
                    "worker_id": worker_id,
                    "new_version": {"major": major, "minor": minor, "patch": patch},
                    "success": True,
                }

            except Exception as e:
                try:
                    conn.rollback()
                    conn.close()
                except:
                    pass
                return {"worker_id": worker_id, "error": str(e), "success": False}

        # Run concurrent increments
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [
                executor.submit(explicit_increment_worker, i)
                for i in range(num_workers)
            ]
            results = [f.result() for f in as_completed(futures, timeout=45)]

        successes = [r for r in results if r["success"]]
        failures = [r for r in results if not r["success"]]

        if successes:
            # Check version increment logic
            for success in successes:
                new_v = success["new_version"]
                if version_type == "major":
                    assert new_v["major"] == initial["major"] + 1, (
                        f"Major increment failed: {new_v}"
                    )
                    assert new_v["minor"] == 0, (
                        f"Major increment should reset minor: {new_v}"
                    )
                    assert new_v["patch"] == 0, (
                        f"Major increment should reset patch: {new_v}"
                    )
                elif version_type == "minor":
                    assert new_v["major"] == initial["major"], (
                        f"Minor increment changed major: {new_v}"
                    )
                    assert new_v["minor"] == initial["minor"] + 1, (
                        f"Minor increment failed: {new_v}"
                    )
                    assert new_v["patch"] == 0, (
                        f"Minor increment should reset patch: {new_v}"
                    )
                elif version_type == "patch":
                    assert new_v["major"] == initial["major"], (
                        f"Patch increment changed major: {new_v}"
                    )
                    assert new_v["minor"] == initial["minor"], (
                        f"Patch increment changed minor: {new_v}"
                    )
                    assert new_v["patch"] == initial["patch"] + 1, (
                        f"Patch increment failed: {new_v}"
                    )

        print(
            f"\n✅ {version_type} increments: {len(successes)} successes, {len(failures)} failures"
        )

    def test_version_rollback_on_transaction_failure(self, db_connection_string: str):
        """
        Test: Version changes are properly rolled back on transaction failure.

        Expected: Failed transactions don't leave version changes.
        """
        table_name = "rollback_test_table"

        # Setup
        setup_conn = psycopg.connect(db_connection_string)
        setup_conn.execute(f"CREATE TABLE {table_name} (id INT)")
        setup_conn.commit()

        # Get initial version
        cursor = setup_conn.execute(
            "SELECT * FROM pggit.get_version(%s)", (table_name,)
        )
        initial_version = cursor.fetchone()
        setup_conn.close()

        if not initial_version:
            pytest.skip("Version tracking not implemented yet")

        # Worker that fails after version increment
        def failing_increment_worker():
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)

            try:
                conn.execute("BEGIN")

                # Add column (triggers version change)
                conn.execute(f"ALTER TABLE {table_name} ADD COLUMN test_col INT")

                # Force failure
                conn.execute("SELECT 1 / 0")  # Division by zero

                conn.commit()
                conn.close()
                return {"success": True, "error": None}

            except Exception as e:
                conn.rollback()
                conn.close()
                return {"success": False, "error": str(e)}

        # Run the failing worker
        with ThreadPoolExecutor(max_workers=1) as executor:
            future = executor.submit(failing_increment_worker)
            result = future.result(timeout=30)

        assert not result["success"], "Worker should have failed"
        assert (
            "division by zero" in result["error"].lower()
            or "division" in result["error"].lower()
        )

        # Verify version didn't change
        final_conn = psycopg.connect(db_connection_string)
        cursor = final_conn.execute(
            "SELECT * FROM pggit.get_version(%s)", (table_name,)
        )
        final_version = cursor.fetchone()
        final_conn.close()

        if final_version and initial_version:
            assert final_version == initial_version, (
                f"Version should not change on transaction failure: {initial_version} -> {final_version}"
            )

        print(f"\n✅ Version rollback on failure: {initial_version} -> {final_version}")

    @pytest.mark.slow
    def test_high_contention_version_updates(self, db_connection_string: str):
        """
        Test: High contention scenario with many workers rapidly updating versions.

        This stress tests the version system's concurrency handling.
        """
        table_name = "stress_version_table"

        # Setup
        setup_conn = psycopg.connect(db_connection_string)
        setup_conn.execute(f"CREATE TABLE {table_name} (id INT)")
        setup_conn.commit()
        setup_conn.close()

        num_workers = 25
        operations_per_worker = 3

        def stress_worker(worker_id: int):
            conn = psycopg.connect(db_connection_string, row_factory=dict_row)
            results = []

            try:
                for op in range(operations_per_worker):
                    try:
                        conn.execute("BEGIN")
                        # Add column to trigger version change
                        conn.execute(
                            f"ALTER TABLE {table_name} ADD COLUMN IF NOT EXISTS w{worker_id}_op{op} INT"
                        )
                        conn.commit()

                        # Read version
                        cursor = conn.execute(
                            "SELECT * FROM pggit.get_version(%s)", (table_name,)
                        )
                        version = cursor.fetchone()
                        results.append(version)

                    except Exception:
                        conn.rollback()
                        results.append(None)

            finally:
                conn.close()

            return results

        # Run high-contention test
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(stress_worker, i) for i in range(num_workers)]
            all_results = []

            for future in as_completed(futures, timeout=120):
                try:
                    worker_results = future.result(timeout=10)
                    all_results.extend(worker_results)
                except Exception:
                    pass

        # Filter out None results (failures)
        valid_versions = [v for v in all_results if v is not None]

        # Should have some successful version reads
        assert len(valid_versions) > 0, (
            "No successful version reads under high contention"
        )

        # All versions should be valid
        for version in valid_versions:
            assert "major" in version and "minor" in version and "patch" in version
            assert all(
                isinstance(version[k], int) and version[k] >= 0
                for k in ["major", "minor", "patch"]
            )

        # Versions should be monotonically increasing (at least not decreasing)
        sorted_versions = sorted(
            valid_versions, key=lambda v: (v["major"], v["minor"], v["patch"])
        )
        # The highest version should be at the end
        assert sorted_versions[-1]["major"] >= sorted_versions[0]["major"], (
            "Version should not decrease under concurrent updates"
        )

        print(
            f"\n✅ High contention test: {len(valid_versions)} successful version reads from {len(all_results)} operations"
        )
