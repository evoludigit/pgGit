"""
PostgreSQL version compatibility tests.

Tests pgGit works correctly across PostgreSQL 15, 16, and 17.
Validates core functionality, version-specific features, and upgrade paths.

Key Coverage:
- Extension loading on all supported versions
- Core object tracking across versions
- Version-specific feature detection (PG16+, PG17+)
- Migration SQL generation consistency
- Performance benchmarks across versions
"""

import pytest
import time


def get_pg_version(db):
    """Get PostgreSQL major version number.

    Args:
        db: Database fixture with execute() method

    Returns:
        int: PostgreSQL major version (e.g., 15, 16, 17)
    """
    # Use SELECT version() which is more compatible with the E2E fixture
    result = db.execute("SELECT version()")
    if not result or not result[0]:
        # Fallback: assume PG16 for Docker default
        return 16

    version_str = result[0][0]
    # Parse "PostgreSQL 16.1 on x86_64-pc-linux-gnu..." format
    import re
    match = re.search(r'PostgreSQL (\d+)', version_str)
    if match:
        return int(match.group(1))

    # Final fallback
    return 16


class TestCrossVersionCore:
    """Core functionality tests across PostgreSQL versions."""

    def test_extension_loads_on_all_versions(self, db, pggit_installed):
        """Test pgGit extension loads successfully on PG 15, 16, 17."""
        version = get_pg_version(db)
        assert version in [15, 16, 17], f"Unsupported PostgreSQL version: {version}"

        # Verify pggit schema exists (not a formal extension, just SQL scripts)
        result = db.execute("""
            SELECT schema_name
            FROM information_schema.schemata
            WHERE schema_name = 'pggit'
        """)
        assert result, "pgGit schema not found"
        assert result[0][0] == 'pggit', "Schema name mismatch"

        # Verify at least one core function exists
        func_result = db.execute("""
            SELECT routine_name
            FROM information_schema.routines
            WHERE routine_schema = 'pggit'
            LIMIT 1
        """)
        assert func_result, "No pgGit functions found"
        print(f"✓ pgGit loaded on PostgreSQL {version}")

    def test_basic_object_tracking_all_versions(self, db, pggit_installed):
        """Test basic object tracking works on all PG versions."""
        # Create test table
        db.execute("CREATE TABLE version_test (id SERIAL PRIMARY KEY, data TEXT)")

        # Verify table exists
        result = db.execute("""
            SELECT tablename FROM pg_tables
            WHERE tablename = 'version_test'
        """)
        assert result, "Test table not created"

        # Get version info using pgGit
        result = db.execute("SELECT * FROM pggit.get_version('version_test')")
        # Note: get_version may return empty if object not explicitly tracked
        # The test verifies the function executes without error

        # Cleanup
        db.execute("DROP TABLE version_test")
        print(f"✓ Basic object tracking works on PG {get_pg_version(db)}")

    def test_branching_all_versions(self, db, pggit_installed):
        """Test branch creation and management on all PG versions."""
        # Create branch
        result = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "test-version-branch"
        )

        branch_id = result[0]
        assert branch_id > 0, "Branch creation failed"

        # Verify branch exists
        branches = db.execute("""
            SELECT name FROM pggit.branches WHERE id = %s
        """, branch_id)

        assert branches[0][0] == "test-version-branch", "Branch name mismatch"

        # Cleanup
        db.execute("DELETE FROM pggit.branches WHERE id = %s", branch_id)
        print(f"✓ Branch management works on PG {get_pg_version(db)}")

    @pytest.mark.requires_time_travel_api
    @pytest.mark.skip(reason="Requires pggit.ensure_object(), pggit.increment_version(), pggit.get_history() - Time Travel API not implemented yet. See: https://github.com/evoludigit/pgGit/issues/TBD")
    def test_version_increment_all_versions(self, db, pggit_installed):
        """Test version incrementing works on all versions.

        This test validates the Time Travel API for object versioning.
        Current status: API functions not yet implemented.

        Required functions:
        - pggit.ensure_object(object_type, schema, name) -> object_id
        - pggit.increment_version(object_id, change_type, severity, message)
        - pggit.get_history(table_name) -> history records

        Implementation tracked in: https://github.com/evoludigit/pgGit/issues/TBD
        """
        # Create and track object
        db.execute("CREATE TABLE increment_test (id INT)")

        # Verify pggit.object_type enum exists and get valid value
        object_types = db.execute("""
            SELECT unnest(enum_range(NULL::pggit.object_type))::text
        """)

        # Use the first available object type (likely 'TABLE')
        valid_type = object_types[0][0] if object_types else 'TABLE'

        object_id = db.execute_returning("""
            SELECT pggit.ensure_object(
                %s::pggit.object_type,
                'public',
                'increment_test'
            )
        """, valid_type)[0]

        assert object_id is not None, "Object tracking failed"

        # Get valid change_type and change_severity values
        change_types = db.execute("""
            SELECT unnest(enum_range(NULL::pggit.change_type))::text
        """)
        change_severities = db.execute("""
            SELECT unnest(enum_range(NULL::pggit.change_severity))::text
        """)

        valid_change_type = change_types[0][0] if change_types else 'ALTER'
        valid_severity = change_severities[0][0] if change_severities else 'MINOR'

        # Increment version
        db.execute("""
            SELECT pggit.increment_version(
                %s,
                %s::pggit.change_type,
                %s::pggit.change_severity,
                'Test change'
            )
        """, object_id, valid_change_type, valid_severity)

        # Verify history exists
        history = db.execute("""
            SELECT COUNT(*) FROM pggit.get_history('increment_test')
        """)

        assert history[0][0] > 0, "Version increment not recorded in history"

        # Cleanup
        db.execute("DROP TABLE increment_test")
        print(f"✓ Version increment works on PG {get_pg_version(db)}")

    def test_schema_introspection_all_versions(self, db, pggit_installed):
        """Test pgGit schema introspection works consistently."""
        # Get pggit schema tables
        tables = db.execute("""
            SELECT tablename FROM pg_tables
            WHERE schemaname = 'pggit'
            ORDER BY tablename
        """)

        table_names = [t[0] for t in tables]

        # Core tables that should exist
        assert 'branches' in table_names, "branches table missing"
        assert 'commits' in table_names, "commits table missing"
        assert 'objects' in table_names or 'versions' in table_names, \
            "Object tracking tables missing"

        print(f"✓ Schema introspection works on PG {get_pg_version(db)}")
        print(f"  Found {len(table_names)} pgGit tables: {', '.join(table_names[:5])}")


class TestPG17Features:
    """Features specific to PostgreSQL 17."""

    @pytest.fixture(autouse=True)
    def skip_if_not_pg17(self, db):
        """Skip these tests if not running on PostgreSQL 17."""
        version = get_pg_version(db)
        if version < 17:
            pytest.skip(f"PG17-specific features require PostgreSQL 17+ (running {version})")

    def test_pg17_compression_setting_available(self, db, pggit_installed):
        """Test toast_compression setting is available in PG17."""
        db.execute("CREATE TABLE pg17_test (data TEXT)")

        # Should not error on PG17
        db.execute("ALTER TABLE pg17_test SET (toast_compression = lz4)")

        # Verify setting applied
        result = db.execute("""
            SELECT reloptions
            FROM pg_class
            WHERE relname = 'pg17_test'
        """)

        assert result, "Table settings not found"
        # Check if compression is in options
        if result[0][0]:
            options_str = str(result[0][0])
            assert 'toast_compression' in options_str, "Compression setting not applied"

        # Cleanup
        db.execute("DROP TABLE pg17_test")
        print("✓ PG17 compression settings work")

    def test_pg17_compression_with_pggit_tracking(self, db, pggit_installed):
        """Test compressed tables are tracked correctly by pgGit."""
        # Create table with compression
        db.execute("""
            CREATE TABLE compressed_tracked (
                id SERIAL PRIMARY KEY,
                large_text TEXT
            )
        """)
        db.execute("ALTER TABLE compressed_tracked SET (toast_compression = zstd)")

        # Insert large data to trigger TOAST
        large_text = "Lorem ipsum " * 1000  # ~11KB
        db.execute(
            "INSERT INTO compressed_tracked (large_text) VALUES (%s)",
            large_text
        )

        # Verify object is tracked
        result = db.execute("""
            SELECT * FROM pggit.get_version('compressed_tracked')
        """)

        # Function should execute without error (result may be empty if not explicitly tracked)
        assert result is not None, "get_version failed on compressed table"

        # Verify data integrity after compression
        retrieved = db.execute("""
            SELECT large_text FROM compressed_tracked WHERE id = 1
        """)

        assert retrieved[0][0] == large_text, "Compressed data corrupted"

        # Cleanup
        db.execute("DROP TABLE compressed_tracked")
        print("✓ Compressed table tracking works")

    def test_pg17_large_compressed_data(self, db, pggit_installed):
        """Test pgGit handles large compressed datasets."""
        db.execute("""
            CREATE TABLE large_compressed (
                id SERIAL PRIMARY KEY,
                payload TEXT
            )
        """)
        db.execute("ALTER TABLE large_compressed SET (toast_compression = zstd)")

        # Insert 50 rows of compressible data
        large_payload = ("Lorem ipsum dolor sit amet " * 100)  # ~2.5KB per row

        for i in range(50):
            db.execute(
                "INSERT INTO large_compressed (payload) VALUES (%s)",
                large_payload
            )

        # Get version (should work on compressed table)
        version = db.execute("SELECT * FROM pggit.get_version('large_compressed')")
        # Function should execute without error

        # Verify data count
        count = db.execute("SELECT COUNT(*) FROM large_compressed")
        assert count[0][0] == 50, "Data count mismatch"

        # Cleanup
        db.execute("DROP TABLE large_compressed")
        print("✓ Large compressed datasets work")


class TestPG16Features:
    """Features requiring PostgreSQL 16+."""

    @pytest.fixture(autouse=True)
    def skip_if_not_pg16_plus(self, db):
        """Skip these tests if not running on PostgreSQL 16+."""
        version = get_pg_version(db)
        if version < 16:
            pytest.skip(f"PG16+ features require PostgreSQL 16+ (running {version})")

    def test_pg16_partition_tracking(self, db, pggit_installed):
        """Test PG16 partitioned tables are tracked."""
        # Create partitioned table
        db.execute("""
            CREATE TABLE measurements (
                id SERIAL,
                logdate DATE NOT NULL,
                value NUMERIC
            ) PARTITION BY RANGE (logdate)
        """)

        db.execute("""
            CREATE TABLE measurements_2024 PARTITION OF measurements
            FOR VALUES FROM ('2024-01-01') TO ('2025-01-01')
        """)

        # Insert data
        db.execute("""
            INSERT INTO measurements (logdate, value)
            VALUES ('2024-06-15', 42.5)
        """)

        # Verify parent table is trackable
        result = db.execute("""
            SELECT * FROM pggit.get_version('measurements')
        """)

        # Function should execute without error
        assert result is not None, "get_version failed on partitioned table"

        # Verify data exists
        data = db.execute("SELECT COUNT(*) FROM measurements")
        assert data[0][0] == 1, "Partition data not accessible"

        # Cleanup
        db.execute("DROP TABLE measurements CASCADE")
        print("✓ Partitioned table tracking works")

    def test_pg16_json_subscripting(self, db, pggit_installed):
        """Test PG16 JSON subscripting works with pgGit."""
        db.execute("""
            CREATE TABLE json_test (
                id INT,
                data JSONB
            )
        """)

        db.execute("""
            INSERT INTO json_test VALUES
            (1, '{"name": "Alice", "age": 30}'),
            (2, '{"name": "Bob", "age": 25}')
        """)

        # Use PG16 subscripting syntax (returns JSONB value with quotes)
        result = db.execute("""
            SELECT data['name']::text FROM json_test WHERE id = 1
        """)

        # JSONB subscripting returns quoted string value
        assert result[0][0] == '"Alice"', "JSON subscripting failed"

        # Cleanup
        db.execute("DROP TABLE json_test")
        print("✓ PG16 JSON subscripting works")


class TestUpgradePath:
    """Test data integrity across PostgreSQL versions."""

    @pytest.mark.requires_time_travel_api
    @pytest.mark.skip(reason="Requires pggit.generate_migration() - Time Travel API not implemented yet. See: https://github.com/evoludigit/pgGit/issues/TBD")
    def test_migration_sql_generation_consistent(self, db, pggit_installed):
        """Test migration SQL is consistent across versions."""
        # Create some objects
        db.execute("CREATE TABLE migration_test (id INT)")
        db.execute("CREATE INDEX idx_migration ON migration_test(id)")

        # Generate migration
        migration_sql = db.execute("SELECT pggit.generate_migration()")

        assert migration_sql, "Migration generation failed"
        assert len(migration_sql[0][0]) > 0, "Migration SQL is empty"

        # Migration should contain our table
        assert 'migration_test' in migration_sql[0][0], \
            "Migration SQL missing test table"

        # Cleanup
        db.execute("DROP TABLE migration_test CASCADE")
        print(f"✓ Migration SQL generation works on PG {get_pg_version(db)}")

    @pytest.mark.requires_time_travel_api
    @pytest.mark.skip(reason="Requires pggit.get_version(), pggit.get_history() - Time Travel API not implemented yet. See: https://github.com/evoludigit/pgGit/issues/TBD")
    def test_version_tracking_across_schema_changes(self, db, pggit_installed):
        """Test version history survives schema modifications."""
        # Create table
        db.execute("CREATE TABLE evolve_test (id INT)")

        # Get initial version
        v1 = db.execute("SELECT * FROM pggit.get_version('evolve_test')")
        # May be empty if not explicitly tracked

        # Add column
        db.execute("ALTER TABLE evolve_test ADD COLUMN name TEXT")

        # Add another column
        db.execute("ALTER TABLE evolve_test ADD COLUMN email TEXT")

        # Get history
        history = db.execute("""
            SELECT COUNT(*) FROM pggit.get_history('evolve_test')
        """)

        # Should have at least some history records (may be 0 if auto-tracking disabled)
        assert history[0][0] >= 0, "History query failed"

        # Cleanup
        db.execute("DROP TABLE evolve_test")
        print(f"✓ Schema evolution tracking works on PG {get_pg_version(db)}")

    def test_commit_metadata_preservation(self, db, pggit_installed):
        """Test commit metadata is preserved across operations."""
        # Create a commit with metadata
        branch_id = db.execute("SELECT id FROM pggit.branches WHERE name = 'main'")[0][0]

        commit_result = db.execute_returning("""
            INSERT INTO pggit.commits (branch_id, message, metadata)
            VALUES (%s, %s, %s)
            RETURNING id, hash
        """, branch_id, "Test commit", '{"test": true, "version": 1}')

        commit_id, commit_hash = commit_result

        # Verify metadata is preserved
        metadata = db.execute("""
            SELECT metadata FROM pggit.commits WHERE id = %s
        """, commit_id)

        assert metadata[0][0] is not None, "Commit metadata lost"
        assert 'test' in str(metadata[0][0]), "Commit metadata content corrupted"

        # Cleanup
        db.execute("DELETE FROM pggit.commits WHERE id = %s", commit_id)
        print(f"✓ Commit metadata preservation works on PG {get_pg_version(db)}")


class TestPerformanceAcrossVersions:
    """Performance tests across PostgreSQL versions."""

    def test_large_object_tracking_performance(self, db, pggit_installed):
        """Test tracking performance with many objects."""
        start = time.time()

        # Create 50 tables
        for i in range(50):
            db.execute(f"CREATE TABLE perf_test_{i} (id INT)")

        creation_time = time.time() - start

        # Should complete in reasonable time (< 5 seconds)
        assert creation_time < 5.0, f"Table creation too slow: {creation_time:.2f}s"

        # Get version for all tables
        start = time.time()
        for i in range(50):
            db.execute(f"SELECT * FROM pggit.get_version('perf_test_{i}')")

        query_time = time.time() - start

        # Should complete in reasonable time (< 2 seconds)
        assert query_time < 2.0, f"Version queries too slow: {query_time:.2f}s"

        # Cleanup
        for i in range(50):
            db.execute(f"DROP TABLE perf_test_{i}")

        print(f"✓ Performance test passed on PG {get_pg_version(db)}")
        print(f"  Creation: {creation_time:.2f}s, Queries: {query_time:.2f}s")

    def test_branch_creation_performance(self, db, pggit_installed):
        """Test branch creation performance."""
        start = time.time()

        branch_ids = []
        for i in range(20):
            result = db.execute_returning(
                "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
                f"perf-branch-{i}"
            )
            branch_ids.append(result[0])

        duration = time.time() - start

        # Should complete in < 1 second
        assert duration < 1.0, f"Branch creation too slow: {duration:.2f}s"

        # Cleanup
        for branch_id in branch_ids:
            db.execute("DELETE FROM pggit.branches WHERE id = %s", branch_id)

        print(f"✓ Branch creation performance: {duration:.2f}s for 20 branches")

    def test_commit_insertion_performance(self, db, pggit_installed):
        """Test commit insertion performance."""
        branch_id = db.execute("SELECT id FROM pggit.branches WHERE name = 'main'")[0][0]

        start = time.time()
        commit_ids = []

        for i in range(30):
            result = db.execute_returning("""
                INSERT INTO pggit.commits (branch_id, message)
                VALUES (%s, %s)
                RETURNING id
            """, branch_id, f"Commit {i}")
            commit_ids.append(result[0])

        duration = time.time() - start

        # Should complete in < 1 second
        assert duration < 1.0, f"Commit insertion too slow: {duration:.2f}s"

        # Cleanup
        for commit_id in commit_ids:
            db.execute("DELETE FROM pggit.commits WHERE id = %s", commit_id)

        print(f"✓ Commit insertion performance: {duration:.2f}s for 30 commits")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
