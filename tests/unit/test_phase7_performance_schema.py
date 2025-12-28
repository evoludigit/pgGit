"""
Tests for Phase 7: Performance Monitoring Schema
Tests table structure, constraints, indexes, and views
"""



class TestPhase7PerformanceSchema:
    """Test Phase 7 performance schema structure"""

    def test_performance_metrics_table_exists(self, db_connection):
        """Verify performance_metrics table exists with correct columns"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT column_name, data_type, is_nullable
                FROM information_schema.columns
                WHERE table_schema = 'pggit' AND table_name = 'performance_metrics'
                ORDER BY ordinal_position
            """)
            columns = {row[0]: (row[1], row[2]) for row in cur.fetchall()}

        # Core columns
        assert 'metric_id' in columns
        assert columns['metric_id'][0] == 'bigint'
        assert 'operation_type' in columns
        assert columns['operation_type'][1] == 'NO'  # NOT NULL
        assert 'duration_microseconds' in columns
        assert columns['duration_microseconds'][0] == 'bigint'

        # Context columns
        assert 'branch_id' in columns
        assert 'user_name' in columns
        assert columns['user_name'][1] == 'NO'  # NOT NULL

        # Metadata
        assert 'operation_metadata' in columns
        assert columns['operation_metadata'][0] == 'jsonb'

    def test_performance_metrics_constraints(self, db_connection):
        """Verify performance_metrics has correct constraints"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT constraint_name, constraint_type
                FROM information_schema.table_constraints
                WHERE table_schema = 'pggit' AND table_name = 'performance_metrics'
            """)
            constraints = {row[0]: row[1] for row in cur.fetchall()}

        # Should have primary key and check constraints
        assert any(c.startswith('performance_metrics_pkey') for c in constraints)
        check_constraints = [c for c in constraints if constraints[c] == 'CHECK']
        assert len(check_constraints) >= 3  # duration, time_order, user_name

    def test_performance_metrics_indexes(self, db_connection):
        """Verify all performance_metrics indexes exist"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT indexname FROM pg_indexes
                WHERE tablename = 'performance_metrics'
                ORDER BY indexname
            """)
            indexes = [row[0] for row in cur.fetchall()]

        # Strategic indexes should exist
        assert any('operation_type' in idx for idx in indexes)
        assert any('recorded_at' in idx for idx in indexes)
        assert any('period_start' in idx for idx in indexes)
        assert any('user_name' in idx for idx in indexes)
        assert any('composite' in idx for idx in indexes)

    def test_operation_traces_table_exists(self, db_connection):
        """Verify operation_traces table structure"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT COUNT(*) FROM information_schema.columns
                WHERE table_schema = 'pggit' AND table_name = 'operation_traces'
            """)
            column_count = cur.fetchone()[0]

        assert column_count > 0

    def test_operation_traces_parent_child_relationship(self, db_connection):
        """Verify parent-child span relationships are enforced"""
        with db_connection.cursor() as cur:
            # Should have self-referential FK
            cur.execute("""
                SELECT constraint_name FROM information_schema.referential_constraints
                WHERE table_schema = 'pggit' AND table_name = 'operation_traces'
            """)
            constraints = [row[0] for row in cur.fetchall()]

        assert len(constraints) > 0

    def test_performance_baselines_percentiles_constraint(self, db_connection):
        """Verify percentile ordering constraints"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT constraint_name
                FROM information_schema.table_constraints
                WHERE table_schema = 'pggit' AND table_name = 'performance_baselines'
                AND constraint_name LIKE '%percentile%'
            """)
            constraints = [row[0] for row in cur.fetchall()]

        assert len(constraints) > 0

    def test_performance_alerts_status_enum(self, db_connection):
        """Verify alert types and severity are restricted"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT constraint_name
                FROM information_schema.table_constraints
                WHERE table_schema = 'pggit' AND table_name = 'performance_alerts'
                AND constraint_type = 'CHECK'
            """)
            check_constraints = [row[0] for row in cur.fetchall()]

        # Should have type and severity checks
        assert any('alert_type' in c for c in check_constraints)
        assert any('severity' in c for c in check_constraints)

    def test_merge_performance_metrics_status_enum(self, db_connection):
        """Verify merge status values are restricted"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT constraint_name
                FROM information_schema.table_constraints
                WHERE table_schema = 'pggit' AND table_name = 'merge_performance_metrics'
                AND constraint_type = 'CHECK'
            """)
            check_constraints = [row[0] for row in cur.fetchall()]

        assert any('merge_status' in c for c in check_constraints)

    def test_performance_operation_types_bootstrap_data(self, db_connection):
        """Verify bootstrap operation types are populated"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT COUNT(*) FROM pggit.performance_operation_types
            """)
            count = cur.fetchone()[0]

        assert count >= 11  # At least 11 standard operation types

    def test_bootstrap_operation_types_have_required_fields(self, db_connection):
        """Verify bootstrap operations have all required metadata"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT operation_type, description, category, is_tracked
                FROM pggit.performance_operation_types
                WHERE operation_type = 'commit'
            """)
            row = cur.fetchone()

        assert row is not None
        assert row[0] == 'commit'
        assert row[1] is not None
        assert row[2] in ['READ', 'WRITE', 'ADMIN', 'WORKFLOW']
        assert row[3] is True

    def test_dashboard_views_exist(self, db_connection):
        """Verify all dashboard views are created"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT table_name FROM information_schema.tables
                WHERE table_schema = 'pggit' AND table_type = 'VIEW'
                AND table_name LIKE 'v_%'
                ORDER BY table_name
            """)
            views = [row[0] for row in cur.fetchall()]

        # Should have multiple dashboard views
        assert len(views) >= 10
        assert 'v_performance_dashboard_summary' in views
        assert 'v_operation_performance_summary' in views
        assert 'v_performance_alerts_recent' in views

    def test_performance_metrics_foreign_key_to_branches(self, db_connection):
        """Verify FK relationship to branches table"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT constraint_name FROM information_schema.referential_constraints
                WHERE table_schema = 'pggit'
                AND table_name = 'performance_metrics'
                AND referenced_table_name = 'branches'
            """)
            constraints = [row[0] for row in cur.fetchall()]

        assert len(constraints) > 0

    def test_baseline_active_index(self, db_connection):
        """Verify unique index on active baselines"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT indexname FROM pg_indexes
                WHERE tablename = 'performance_baselines'
                AND indexname LIKE '%active%'
            """)
            indexes = [row[0] for row in cur.fetchall()]

        assert len(indexes) > 0

    def test_alert_acknowledgment_columns(self, db_connection):
        """Verify alert acknowledgment tracking columns"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT column_name FROM information_schema.columns
                WHERE table_schema = 'pggit' AND table_name = 'performance_alerts'
                AND column_name IN ('is_acknowledged', 'acknowledged_at', 'acknowledged_by')
            """)
            columns = [row[0] for row in cur.fetchall()]

        assert len(columns) == 3

    def test_trace_cascade_delete(self, db_connection):
        """Verify cascading delete from parent spans"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT constraint_name FROM information_schema.referential_constraints
                WHERE table_schema = 'pggit'
                AND table_name = 'operation_traces'
                AND delete_rule = 'CASCADE'
            """)
            constraints = [row[0] for row in cur.fetchall()]

        assert len(constraints) > 0

    def test_merge_performance_foreign_keys(self, db_connection):
        """Verify merge_performance_metrics foreign keys"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT COUNT(*) FROM information_schema.referential_constraints
                WHERE table_schema = 'pggit' AND table_name = 'merge_performance_metrics'
            """)
            count = cur.fetchone()[0]

        # Should have FK to source and target branches
        assert count >= 2

    def test_period_start_date_truncation(self, db_connection):
        """Verify period_start is stored for partitioning"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT column_name, data_type FROM information_schema.columns
                WHERE table_schema = 'pggit' AND table_name = 'performance_metrics'
                AND column_name = 'period_start'
            """)
            row = cur.fetchone()

        assert row is not None
        assert row[1] == 'timestamp without time zone'

    def test_duration_precision_options(self, db_connection):
        """Verify both microseconds and milliseconds are stored"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT column_name FROM information_schema.columns
                WHERE table_schema = 'pggit' AND table_name = 'performance_metrics'
                AND column_name IN ('duration_microseconds', 'duration_ms')
            """)
            columns = [row[0] for row in cur.fetchall()]

        assert 'duration_microseconds' in columns
        assert 'duration_ms' in columns

    def test_jsonb_metadata_columns(self, db_connection):
        """Verify JSONB columns for flexible metadata"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT COUNT(*) FROM information_schema.columns
                WHERE table_schema = 'pggit'
                AND data_type = 'jsonb'
                AND table_name IN (
                    'performance_metrics',
                    'operation_traces',
                    'performance_alerts',
                    'merge_performance_metrics'
                )
            """)
            jsonb_columns = cur.fetchone()[0]

        assert jsonb_columns >= 3  # At least 3 JSONB columns for metadata

    def test_trace_status_values(self, db_connection):
        """Verify trace status constraint allows valid values"""
        with db_connection.cursor() as cur:
            # This tests that the constraint exists via CHECK clause
            cur.execute("""
                SELECT pg_get_constraintdef(oid)
                FROM pg_constraint
                WHERE conname LIKE 'chk_trace_status'
                LIMIT 1
            """)
            constraint = cur.fetchone()

        assert constraint is not None
        assert 'PENDING' in constraint[0] or 'RUNNING' in constraint[0]

    def test_performance_baselines_multiple_percentiles(self, db_connection):
        """Verify all percentile columns exist"""
        percentiles = ['p50', 'p75', 'p90', 'p95', 'p99']
        with db_connection.cursor() as cur:
            for p in percentiles:
                cur.execute(f"""
                    SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'pggit'
                    AND table_name = 'performance_baselines'
                    AND column_name = '{p}_microseconds'
                """)
                assert cur.fetchone() is not None

    def test_session_id_correlation(self, db_connection):
        """Verify session_id for trace correlation"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT COUNT(*) FROM information_schema.columns
                WHERE table_schema = 'pggit'
                AND column_name = 'session_id'
                AND table_name IN ('operation_traces', 'performance_metrics')
            """)
            count = cur.fetchone()[0]

        assert count >= 2  # Both tables should have session_id

    def test_timestamp_columns_default_current(self, db_connection):
        """Verify timestamp columns have CURRENT_TIMESTAMP defaults"""
        with db_connection.cursor() as cur:
            cur.execute("""
                SELECT column_name, column_default
                FROM information_schema.columns
                WHERE table_schema = 'pggit'
                AND table_name = 'performance_metrics'
                AND column_name = 'recorded_at'
            """)
            row = cur.fetchone()

        assert row is not None
        assert 'CURRENT_TIMESTAMP' in row[1] or 'current_timestamp' in row[1]
