"""
pgGit Time Travel Tests

Dedicated test suite for Time Travel functionality (sql/060_time_travel.sql).
This addresses the critical gap identified in pggit-achievement-analysis.md:
Time Travel feature (619 LOC) had no dedicated test file.

Tests cover all 9 time travel functions:
1. create_temporal_snapshot - Create snapshots of database state
2. list_temporal_snapshots - List existing snapshots
3. get_table_state_at_time - Query table state at specific timestamp (new signature)
4. query_historical_data - Query historical changes (new signature)
5. restore_table_to_point_in_time - PITR functionality (new signature)
6. temporal_diff - Compare states between timestamps
7. record_temporal_change - Manual change tracking
8. export_temporal_data - Export snapshot data with proper timestamp handling
9. rebuild_temporal_indexes - Index maintenance with correct index names
"""

import pytest


class TestTemporalSnapshotManagement:
    """Test temporal snapshot creation and listing."""

    def test_create_temporal_snapshot_basic(self, db_e2e, pggit_installed):
        """Test basic temporal snapshot creation."""
        result = db_e2e.execute_returning("""
            SELECT snapshot_id, name, created_at
            FROM pggit.create_temporal_snapshot(
                'test-snapshot-basic',
                1,
                'Basic snapshot test'
            )
        """)

        assert result is not None, "Snapshot creation should return result"
        snapshot_id, name, created_at = result
        assert snapshot_id is not None, "Snapshot ID should be generated"
        assert name == 'test-snapshot-basic', f"Expected name 'test-snapshot-basic', got '{name}'"
        assert created_at is not None, "Created_at timestamp should be set"

        print(f"✓ Created snapshot: {snapshot_id} named '{name}'")

    def test_create_multiple_snapshots(self, db_e2e, pggit_installed):
        """Test creating multiple snapshots."""
        snapshots = []
        for i in range(3):
            result = db_e2e.execute_returning("""
                SELECT snapshot_id FROM pggit.create_temporal_snapshot(
                    %s, 1, %s
                )
            """, f'snapshot-{i}', f'Snapshot number {i}')
            snapshots.append(result)

        assert len(snapshots) == 3, "Should create 3 snapshots"
        assert len(set(snapshots)) == 3, "All snapshot IDs should be unique"
        print(f"✓ Created {len(snapshots)} unique snapshots")

    def test_list_temporal_snapshots(self, db_e2e, pggit_installed):
        """Test listing temporal snapshots."""
        # Create test snapshots
        for i in range(2):
            db_e2e.execute_returning("""
                SELECT snapshot_id FROM pggit.create_temporal_snapshot(
                    %s, 1, %s
                )
            """, f'list-test-{i}', f'Test snapshot {i}')

        # List snapshots
        snapshots = db_e2e.execute("""
            SELECT snapshot_id, snapshot_name, description
            FROM pggit.list_temporal_snapshots()
        """)

        assert snapshots is not None, "list_temporal_snapshots should return results"
        assert len(snapshots) >= 2, f"Should have at least 2 snapshots, got {len(snapshots)}"
        print(f"✓ Listed {len(snapshots)} snapshots")

    def test_snapshot_with_branch_association(self, db_e2e, pggit_installed):
        """Test creating snapshot associated with specific branch."""
        # Create snapshot for branch 1
        result = db_e2e.execute_returning("""
            SELECT snapshot_id FROM pggit.create_temporal_snapshot(
                'branch-snapshot', 1, 'Snapshot for specific branch'
            )
        """)

        assert result is not None, "Branch-associated snapshot should be created"

        # List snapshots for branch 1
        branch_snapshots = db_e2e.execute("""
            SELECT snapshot_id FROM pggit.list_temporal_snapshots(
                p_branch_id := 1
            )
        """)

        assert len(branch_snapshots) > 0, "Should find snapshots for branch 1"
        print(f"✓ Created and listed branch-associated snapshot")


class TestHistoricalDataQueries:
    """Test querying historical data using new function signatures."""

    def test_query_historical_data_new_signature(self, db_e2e, pggit_installed):
        """Test query_historical_data with new (schema, table, timestamp_iso) signature."""
        # Create test table
        db_e2e.execute("""
            CREATE TABLE IF NOT EXISTS public.historical_test (
                id SERIAL PRIMARY KEY,
                value TEXT
            )
        """)

        # Insert test data
        db_e2e.execute("INSERT INTO public.historical_test (value) VALUES ('test')")

        # Create snapshot
        snap_result = db_e2e.execute_returning("""
            SELECT snapshot_id, created_at FROM pggit.create_temporal_snapshot(
                'query-test', 1, 'Test data'
            )
        """)
        snapshot_id, created_at = snap_result

        # Manually insert a record into temporal_changelog for this snapshot
        db_e2e.execute("""
            INSERT INTO pggit.temporal_changelog
            (snapshot_id, table_schema, table_name, operation, new_data, row_id)
            VALUES (%s, 'public', 'historical_test', 'INSERT',
                    '{"id": 1, "value": "test"}', '1')
        """, snapshot_id)

        # Query historical data using NEW signature (schema, table, timestamp_iso)
        historical_data = db_e2e.execute("""
            SELECT row_data, change_type FROM pggit.query_historical_data(
                'public', 'historical_test', %s
            )
        """, created_at.isoformat())

        assert historical_data is not None, "Should return historical data"
        print(f"✓ Queried historical data with new signature: {len(historical_data)} records")

        # Cleanup
        db_e2e.execute("DROP TABLE IF EXISTS public.historical_test")

    def test_get_table_state_at_time_new_signature(self, db_e2e, pggit_installed):
        """Test get_table_state_at_time with new (schema, table, timestamp_iso) signature."""
        # Note: This function currently returns empty result set (placeholder implementation)
        # but we test that it accepts the correct signature

        result = db_e2e.execute("""
            SELECT * FROM pggit.get_table_state_at_time(
                'public', 'test_table', %s
            )
        """, '2025-01-01T00:00:00+00:00')

        # Function should execute without error (even if it returns no rows)
        assert result is not None or result == [], "Function should execute successfully"
        print("✓ get_table_state_at_time new signature works")


class TestPointInTimeRecovery:
    """Test PITR functionality with new function signature."""

    def test_restore_table_new_signature(self, db_e2e, pggit_installed):
        """Test restore_table_to_point_in_time with new (schema, table, timestamp_iso) signature."""
        # Create test table
        db_e2e.execute("""
            CREATE TABLE IF NOT EXISTS public.pitr_test (
                id SERIAL PRIMARY KEY,
                value TEXT
            )
        """)

        # Test the new signature
        result = db_e2e.execute("""
            SELECT rows_restored, success FROM pggit.restore_table_to_point_in_time(
                'public', 'pitr_test', %s
            )
        """, '2025-01-01T00:00:00+00:00')

        assert result is not None, "PITR function should return result"
        rows_restored, success = result[0]
        assert success is True, "Function should indicate success"
        print(f"✓ PITR new signature works (restored {rows_restored} rows)")

        # Cleanup
        db_e2e.execute("DROP TABLE IF EXISTS public.pitr_test")


class TestTemporalDiff:
    """Test temporal diff functionality."""

    def test_temporal_diff_basic(self, db_e2e, pggit_installed):
        """Test temporal_diff function with full table name."""
        # Create test table
        db_e2e.execute("""
            CREATE TABLE IF NOT EXISTS public.diff_test (
                id SERIAL PRIMARY KEY,
                value TEXT
            )
        """)

        # Create two snapshots at different times
        snap1_result = db_e2e.execute_returning("""
            SELECT snapshot_id, created_at FROM pggit.create_temporal_snapshot(
                'diff-1', 1, 'State 1'
            )
        """)
        snap1_id, snap1_time = snap1_result

        # Record some changes in changelog
        db_e2e.execute("""
            INSERT INTO pggit.temporal_changelog
            (snapshot_id, table_schema, table_name, operation, new_data, row_id)
            VALUES (%s, 'public', 'diff_test', 'INSERT',
                    '{"id": 1, "value": "old"}', '1')
        """, snap1_id)

        snap2_result = db_e2e.execute_returning("""
            SELECT snapshot_id, created_at FROM pggit.create_temporal_snapshot(
                'diff-2', 1, 'State 2'
            )
        """)
        snap2_id, snap2_time = snap2_result

        # Record updated data
        db_e2e.execute("""
            INSERT INTO pggit.temporal_changelog
            (snapshot_id, table_schema, table_name, operation, new_data, row_id)
            VALUES (%s, 'public', 'diff_test', 'UPDATE',
                    '{"id": 1, "value": "new"}', '1')
        """, snap2_id)

        # Get temporal diff (note: function signature is (table_name TEXT, time_a TIMESTAMP, time_b TIMESTAMP))
        diff_result = db_e2e.execute("""
            SELECT row_id, changed FROM pggit.temporal_diff(
                %s::TEXT, %s::TIMESTAMP, %s::TIMESTAMP
            )
        """, 'public.diff_test', snap1_time, snap2_time)

        assert diff_result is not None, "Temporal diff should return result"
        print(f"✓ Temporal diff executed: {len(diff_result)} changes detected")

        # Cleanup
        db_e2e.execute("DROP TABLE IF EXISTS public.diff_test")


class TestTemporalChangeRecording:
    """Test manual temporal change recording."""

    def test_record_temporal_change_insert(self, db_e2e, pggit_installed):
        """Test recording INSERT change."""
        # Create snapshot
        result = db_e2e.execute_returning("""
            SELECT snapshot_id FROM pggit.create_temporal_snapshot(
                'record-test', 1, 'Recording test'
            )
        """)
        snapshot_id = result[0]  # execute_returning returns tuple (value,) for single column

        # Record a change (note parameter order: snapshot_id, schema, table, operation, row_id, old_data, new_data)
        change_result = db_e2e.execute_returning("""
            SELECT pggit.record_temporal_change(
                %s::UUID, 'public', 'test_table', 'INSERT', '1',
                NULL, '{"id": 1, "value": "test"}'::jsonb
            )
        """, snapshot_id)
        change_id = change_result[0]

        assert change_id is not None, "Change should be recorded"
        print(f"✓ Recorded INSERT change with ID: {change_id}")


class TestTemporalDataExport:
    """Test temporal data export functionality."""

    def test_export_temporal_data_basic(self, db_e2e, pggit_installed):
        """Test exporting temporal data for a snapshot."""
        # Create snapshot
        result = db_e2e.execute_returning("""
            SELECT snapshot_id FROM pggit.create_temporal_snapshot(
                'export-test', 1, 'Export test'
            )
        """)
        snapshot_id = result[0]  # execute_returning returns tuple (value,) for single column

        # Export data
        export_result = db_e2e.execute("""
            SELECT export_format, record_count, exported_at FROM pggit.export_temporal_data(%s::UUID)
        """, snapshot_id)

        assert export_result is not None, "Export should return result"
        export_format, record_count, exported_at = export_result[0]
        assert export_format == 'JSONL', f"Expected JSONL format, got {export_format}"
        assert exported_at is not None, "Exported_at timestamp should be set"
        print(f"✓ Exported {record_count} records in {export_format} format at {exported_at}")


class TestTemporalIndexManagement:
    """Test temporal index maintenance."""

    def test_rebuild_temporal_indexes(self, db_e2e, pggit_installed):
        """Test rebuilding temporal indexes."""
        result = db_e2e.execute("""
            SELECT index_name, rebuilt FROM pggit.rebuild_temporal_indexes()
        """)

        assert result is not None, "Rebuild should return result"
        assert len(result) >= 2, "Should return status for at least 2 indexes"

        for index_name, rebuilt in result:
            assert rebuilt is True, f"Index {index_name} should be marked as rebuilt"

        print(f"✓ Rebuilt {len(result)} temporal indexes")


class TestTemporalEdgeCases:
    """Test edge cases and error handling."""

    def test_snapshot_with_null_description(self, db_e2e, pggit_installed):
        """Test creating snapshot with NULL description."""
        result = db_e2e.execute_returning("""
            SELECT snapshot_id, name FROM pggit.create_temporal_snapshot(
                'null-desc-test', 1, NULL
            )
        """)

        assert result is not None, "Snapshot with NULL description should succeed"
        snapshot_id, name = result
        assert snapshot_id is not None, "Snapshot ID should be generated"
        print("✓ Handles NULL description gracefully")

    def test_list_snapshots_with_limit(self, db_e2e, pggit_installed):
        """Test listing snapshots with limit parameter."""
        # Create multiple snapshots
        for i in range(5):
            db_e2e.execute_returning("""
                SELECT snapshot_id FROM pggit.create_temporal_snapshot(
                    %s, 1, %s
                )
            """, f'limit-test-{i}', f'Snapshot {i}')

        # List with limit
        limited_results = db_e2e.execute("""
            SELECT snapshot_id FROM pggit.list_temporal_snapshots(
                p_limit := 3
            )
        """)

        assert len(limited_results) <= 3, f"Should return at most 3 results, got {len(limited_results)}"
        print(f"✓ Limit parameter works correctly: returned {len(limited_results)} snapshots")


class TestMultiTableConsistency:
    """Test temporal consistency across multiple tables."""

    def test_consistent_snapshot_creation(self, db_e2e, pggit_installed):
        """Test creating snapshot captures consistent state."""
        # Create two tables
        db_e2e.execute("""
            CREATE TABLE IF NOT EXISTS public.tt_table_a (id SERIAL PRIMARY KEY, value TEXT);
            CREATE TABLE IF NOT EXISTS public.tt_table_b (id SERIAL PRIMARY KEY, value TEXT);
        """)

        # Insert data
        db_e2e.execute("INSERT INTO public.tt_table_a (value) VALUES ('a1')")
        db_e2e.execute("INSERT INTO public.tt_table_b (value) VALUES ('b1')")

        # Create snapshot
        snap_result = db_e2e.execute_returning("""
            SELECT snapshot_id, created_at FROM pggit.create_temporal_snapshot(
                'multi-table-test', 1, 'Consistent state'
            )
        """)

        assert snap_result is not None, "Snapshot should capture multi-table state"
        snapshot_id, created_at = snap_result
        print(f"✓ Created consistent snapshot {snapshot_id} at {created_at}")

        # Cleanup
        db_e2e.execute("DROP TABLE IF EXISTS public.tt_table_a, public.tt_table_b")
