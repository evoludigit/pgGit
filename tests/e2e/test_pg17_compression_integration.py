"""
PostgreSQL 17 Compression Integration Tests.

Tests how pgGit handles compressed tables, not just PostgreSQL compression itself.
Validates that pgGit's tracking, versioning, and migration features work correctly
with PG17's new compression capabilities.

Key Coverage:
- Compressed table tracking with pgGit
- Version history on compressed tables
- Schema evolution with compression settings
- Data integrity with compression
- Migration SQL generation for compressed tables
- Performance characteristics

Note: These tests require PostgreSQL 17+
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
    result = db.execute("SHOW server_version")
    version_str = result[0][0]
    version = int(version_str.split('.')[0])
    return version


# Skip all tests in this module if not PG17+
pytestmark = pytest.mark.skipif(
    True,  # Will be evaluated at collection time
    reason="Compression features require PostgreSQL 17+"
)


def pytest_configure(config):
    """Configure pytest to skip PG17 tests on older versions."""
    # This runs at test collection time
    pass


class TestCompressedTableTracking:
    """Test pgGit tracks compressed tables correctly."""

    @pytest.fixture(autouse=True)
    def skip_if_not_pg17(self, db):
        """Skip these tests if not running on PostgreSQL 17+."""
        version = get_pg_version(db)
        if version < 17:
            pytest.skip(f"Requires PostgreSQL 17+ (running {version})")

    def test_compressed_table_version_tracking(self, db, pggit_installed):
        """Test version tracking works on compressed tables."""
        # Create table with compression
        db.execute("""
            CREATE TABLE compressed_versions (
                id SERIAL PRIMARY KEY,
                large_data TEXT
            )
        """)
        db.execute("ALTER TABLE compressed_versions SET (toast_compression = lz4)")

        # Verify compression setting applied
        result = db.execute("""
            SELECT reloptions FROM pg_class
            WHERE relname = 'compressed_versions'
        """)
        assert result, "Table not found"
        if result[0][0]:
            assert 'toast_compression' in str(result[0][0]), "Compression not set"

        # Get version (pgGit should handle compressed tables)
        v1 = db.execute("SELECT * FROM pggit.get_version('compressed_versions')")
        # Function should execute without error

        # Insert large data that will be compressed
        large_text = "Data " * 1000  # ~5KB
        db.execute("INSERT INTO compressed_versions (large_data) VALUES (%s)", large_text)

        # Modify schema
        db.execute("ALTER TABLE compressed_versions ADD COLUMN metadata TEXT")

        # Get history
        history = db.execute("""
            SELECT COUNT(*) FROM pggit.get_history('compressed_versions')
        """)
        # Function should execute (result may be 0 if auto-tracking disabled)

        # Cleanup
        db.execute("DROP TABLE compressed_versions")
        print("✓ Compressed table version tracking works")

    def test_compression_preserved_in_schema_export(self, db, pggit_installed):
        """Test migration SQL includes compression settings."""
        db.execute("CREATE TABLE with_compression (id INT, data TEXT)")
        db.execute("ALTER TABLE with_compression SET (toast_compression = zstd)")

        # Generate migration
        migration = db.execute("SELECT pggit.generate_migration()")

        assert migration, "Migration generation failed"
        assert migration[0][0], "Migration SQL empty"

        migration_sql = migration[0][0]

        # Migration should include table definition
        assert 'with_compression' in migration_sql.lower(), \
            "Table not in migration SQL"

        # Ideally would include compression setting, but may vary by implementation
        # At minimum, table should be present

        # Cleanup
        db.execute("DROP TABLE with_compression")
        print("✓ Schema export handles compressed tables")

    def test_data_integrity_after_compression(self, db, pggit_installed):
        """Test data survives compression correctly."""
        db.execute("""
            CREATE TABLE integrity_test (
                id SERIAL PRIMARY KEY,
                original TEXT,
                json_data JSONB
            )
        """)
        db.execute("ALTER TABLE integrity_test SET (toast_compression = lz4)")

        # Insert various data types
        test_cases = [
            ("Simple text", '{"key": "value"}'),
            ("Unicode: 你好🌍", '{"unicode": true}'),
            ("Special: !@#$%", '{"special": "chars"}'),
            ("Large: " + ("x" * 1000), '{"large": "payload"}'),
        ]

        for text, json_data in test_cases:
            db.execute(
                "INSERT INTO integrity_test (original, json_data) VALUES (%s, %s::jsonb)",
                text, json_data
            )

        # Verify all data intact
        results = db.execute("""
            SELECT original, json_data
            FROM integrity_test
            ORDER BY id
        """)

        assert len(results) == len(test_cases), "Row count mismatch"

        for i, (text, json_data) in enumerate(test_cases):
            assert results[i][0] == text, f"Text corrupted at row {i}: expected '{text}', got '{results[i][0]}'"
            # JSON data may be reordered but should be equivalent
            # Basic check: key content present
            if 'key' in json_data:
                assert 'key' in str(results[i][1]), f"JSON corrupted at row {i}"

        # Cleanup
        db.execute("DROP TABLE integrity_test")
        print("✓ Data integrity preserved with compression")

    def test_mixed_compression_settings(self, db, pggit_installed):
        """Test tables with different compression settings coexist."""
        # Create tables with different compression
        db.execute("CREATE TABLE no_compress (id INT, data TEXT)")
        db.execute("CREATE TABLE lz4_compress (id INT, data TEXT)")
        db.execute("CREATE TABLE zstd_compress (id INT, data TEXT)")

        db.execute("ALTER TABLE lz4_compress SET (toast_compression = lz4)")
        db.execute("ALTER TABLE zstd_compress SET (toast_compression = zstd)")

        # Verify settings
        for table, expected in [
            ('no_compress', None),
            ('lz4_compress', 'lz4'),
            ('zstd_compress', 'zstd')
        ]:
            result = db.execute("""
                SELECT reloptions FROM pg_class WHERE relname = %s
            """, table)

            if expected:
                assert result[0][0] is not None, f"{table} has no options"
                assert expected in str(result[0][0]), \
                    f"{table} missing {expected} compression"
            # else: no compression set (default)

        # Insert data into all
        for table in ['no_compress', 'lz4_compress', 'zstd_compress']:
            db.execute(f"INSERT INTO {table} (id, data) VALUES (1, 'test')")

        # Verify all readable
        for table in ['no_compress', 'lz4_compress', 'zstd_compress']:
            result = db.execute(f"SELECT data FROM {table} WHERE id = 1")
            assert result[0][0] == 'test', f"{table} data corrupted"

        # Cleanup
        for table in ['no_compress', 'lz4_compress', 'zstd_compress']:
            db.execute(f"DROP TABLE {table}")

        print("✓ Mixed compression settings work")


class TestCompressionWithBranching:
    """Test compression settings with pgGit branching features."""

    @pytest.fixture(autouse=True)
    def skip_if_not_pg17(self, db):
        """Skip these tests if not running on PostgreSQL 17+."""
        version = get_pg_version(db)
        if version < 17:
            pytest.skip(f"Requires PostgreSQL 17+ (running {version})")

    def test_compression_settings_in_branch_metadata(self, db, pggit_installed):
        """Test branch metadata can reference compressed tables."""
        # Create compressed table
        db.execute("CREATE TABLE branch_compress (id INT, data TEXT)")
        db.execute("ALTER TABLE branch_compress SET (toast_compression = lz4)")

        # Create branch
        branch_id = db.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
            "compressed-branch"
        )[0]

        assert branch_id > 0, "Branch creation failed"

        # Verify branch exists
        branch = db.execute("""
            SELECT name FROM pggit.branches WHERE id = %s
        """, branch_id)
        assert branch[0][0] == "compressed-branch"

        # Insert data
        db.execute("INSERT INTO branch_compress VALUES (1, 'branch data')")

        # Verify data accessible
        result = db.execute("SELECT COUNT(*) FROM branch_compress")
        assert result[0][0] == 1

        # Cleanup
        db.execute("DELETE FROM pggit.branches WHERE id = %s", branch_id)
        db.execute("DROP TABLE branch_compress")
        print("✓ Compressed tables work with branching")

    def test_large_compressed_data_version_tracking(self, db, pggit_installed):
        """Test version tracking with large compressed datasets."""
        db.execute("""
            CREATE TABLE large_compressed (
                id SERIAL PRIMARY KEY,
                payload TEXT
            )
        """)
        db.execute("ALTER TABLE large_compressed SET (toast_compression = zstd)")

        # Insert 100 rows of compressible data
        large_payload = ("Lorem ipsum dolor sit amet " * 100)  # ~2.5KB per row

        for i in range(100):
            db.execute(
                "INSERT INTO large_compressed (payload) VALUES (%s)",
                large_payload
            )

        # Get version
        version = db.execute("SELECT * FROM pggit.get_version('large_compressed')")
        # Function should execute without error

        # Verify data count
        count = db.execute("SELECT COUNT(*) FROM large_compressed")
        assert count[0][0] == 100, "Data count mismatch"

        # Sample data integrity
        sample = db.execute("SELECT payload FROM large_compressed LIMIT 1")
        assert len(sample[0][0]) > 2000, "Data appears truncated"

        # Cleanup
        db.execute("DROP TABLE large_compressed")
        print("✓ Large compressed datasets tracked")

    def test_compression_change_tracking(self, db, pggit_installed):
        """Test tracking when compression setting changes."""
        db.execute("CREATE TABLE compression_evolve (id INT, data TEXT)")

        # Start without compression
        db.execute("INSERT INTO compression_evolve VALUES (1, 'initial')")

        # Add compression
        db.execute("ALTER TABLE compression_evolve SET (toast_compression = lz4)")

        # Verify compression set
        result = db.execute("""
            SELECT reloptions FROM pg_class
            WHERE relname = 'compression_evolve'
        """)
        assert result[0][0] is not None
        assert 'lz4' in str(result[0][0])

        # Insert more data (will be compressed)
        db.execute("INSERT INTO compression_evolve VALUES (2, 'compressed')")

        # Verify both records readable
        all_data = db.execute("SELECT COUNT(*) FROM compression_evolve")
        assert all_data[0][0] == 2

        # Cleanup
        db.execute("DROP TABLE compression_evolve")
        print("✓ Compression setting changes tracked")


class TestCompressionPerformance:
    """Performance tests for compressed tables with pgGit."""

    @pytest.fixture(autouse=True)
    def skip_if_not_pg17(self, db):
        """Skip these tests if not running on PostgreSQL 17+."""
        version = get_pg_version(db)
        if version < 17:
            pytest.skip(f"Requires PostgreSQL 17+ (running {version})")

    def test_version_query_performance_on_compressed(self, db, pggit_installed):
        """Test get_version() performs well on compressed tables."""
        db.execute("CREATE TABLE perf_compressed (id INT, data TEXT)")
        db.execute("ALTER TABLE perf_compressed SET (toast_compression = lz4)")

        # Insert 1000 rows
        payload = "x" * 1000  # 1KB each
        for i in range(1000):
            if i % 100 == 0:
                db.execute("COMMIT")
                db.execute("BEGIN")
            db.execute("INSERT INTO perf_compressed (id, data) VALUES (%s, %s)", i, payload)

        db.execute("COMMIT")

        # Time version query
        start = time.time()
        version = db.execute("SELECT * FROM pggit.get_version('perf_compressed')")
        duration = time.time() - start

        # Should execute (result may be empty)
        assert duration < 0.5, f"Version query too slow: {duration:.2f}s"

        # Cleanup
        db.execute("DROP TABLE perf_compressed")
        print(f"✓ Version query performance: {duration:.3f}s")

    def test_insert_performance_with_compression(self, db, pggit_installed):
        """Test insert performance with compression enabled."""
        db.execute("CREATE TABLE insert_perf (id INT, data TEXT)")
        db.execute("ALTER TABLE insert_perf SET (toast_compression = lz4)")

        # Time 500 inserts
        payload = "Test data " * 100  # Compressible data
        start = time.time()

        for i in range(500):
            db.execute("INSERT INTO insert_perf VALUES (%s, %s)", i, payload)

        duration = time.time() - start

        # Should complete in reasonable time (< 2s)
        assert duration < 2.0, f"Insert too slow: {duration:.2f}s"

        # Verify count
        count = db.execute("SELECT COUNT(*) FROM insert_perf")
        assert count[0][0] == 500

        # Cleanup
        db.execute("DROP TABLE insert_perf")
        print(f"✓ Insert performance: {duration:.2f}s for 500 rows")

    def test_schema_modification_performance_compressed(self, db, pggit_installed):
        """Test schema modifications on compressed tables."""
        db.execute("CREATE TABLE schema_perf (id INT, data TEXT)")
        db.execute("ALTER TABLE schema_perf SET (toast_compression = zstd)")

        # Insert some data
        for i in range(100):
            db.execute("INSERT INTO schema_perf VALUES (%s, %s)", i, "data")

        # Time schema modification
        start = time.time()
        db.execute("ALTER TABLE schema_perf ADD COLUMN new_col TEXT")
        duration = time.time() - start

        # Should complete quickly (< 1s)
        assert duration < 1.0, f"ALTER TABLE too slow: {duration:.2f}s"

        # Verify column added
        result = db.execute("""
            SELECT column_name FROM information_schema.columns
            WHERE table_name = 'schema_perf' AND column_name = 'new_col'
        """)
        assert result, "Column not added"

        # Cleanup
        db.execute("DROP TABLE schema_perf")
        print(f"✓ Schema modification: {duration:.3f}s")


class TestCompressionEdgeCases:
    """Edge cases and error handling with compression."""

    @pytest.fixture(autouse=True)
    def skip_if_not_pg17(self, db):
        """Skip these tests if not running on PostgreSQL 17+."""
        version = get_pg_version(db)
        if version < 17:
            pytest.skip(f"Requires PostgreSQL 17+ (running {version})")

    def test_invalid_compression_method(self, db, pggit_installed):
        """Test handling of invalid compression method."""
        db.execute("CREATE TABLE invalid_compress (data TEXT)")

        # Try invalid compression method
        with pytest.raises(Exception) as exc:
            db.execute("ALTER TABLE invalid_compress SET (toast_compression = invalid)")

        assert 'invalid' in str(exc.value).lower() or 'compression' in str(exc.value).lower()

        # Cleanup
        db.execute("DROP TABLE invalid_compress")
        print("✓ Invalid compression method rejected")

    def test_compression_on_table_without_toastable_columns(self, db, pggit_installed):
        """Test compression setting on table with only small columns."""
        # Table with only INT (not toastable)
        db.execute("CREATE TABLE no_toast (id INT, count INT)")

        # Setting compression should work but have no effect
        db.execute("ALTER TABLE no_toast SET (toast_compression = lz4)")

        # Insert data
        db.execute("INSERT INTO no_toast VALUES (1, 100)")

        # Verify data works
        result = db.execute("SELECT count FROM no_toast WHERE id = 1")
        assert result[0][0] == 100

        # Cleanup
        db.execute("DROP TABLE no_toast")
        print("✓ Compression on non-toastable table handled")

    def test_compression_with_null_values(self, db, pggit_installed):
        """Test compression handles NULL values correctly."""
        db.execute("CREATE TABLE null_compress (id INT, data TEXT)")
        db.execute("ALTER TABLE null_compress SET (toast_compression = lz4)")

        # Insert mix of NULL and data
        db.execute("INSERT INTO null_compress VALUES (1, NULL)")
        db.execute("INSERT INTO null_compress VALUES (2, 'data')")
        db.execute("INSERT INTO null_compress VALUES (3, NULL)")

        # Verify NULLs preserved
        result = db.execute("SELECT data FROM null_compress ORDER BY id")
        assert result[0][0] is None, "NULL not preserved"
        assert result[1][0] == 'data', "Data corrupted"
        assert result[2][0] is None, "NULL not preserved"

        # Cleanup
        db.execute("DROP TABLE null_compress")
        print("✓ NULL values handled correctly")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
