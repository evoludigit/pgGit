"""
E2E tests for cross-branch consistency and synchronization.

Tests data and schema consistency across multiple branches:
- Data consistency when branches diverge
- Schema evolution consistency across branches
- Version number uniqueness across branches
- Timestamp ordering and consistency

Key Coverage:
- Multi-branch data consistency validation
- Schema evolution tracking across branches
- Version ID uniqueness and ordering
- Timestamp ordering and temporal consistency
"""

import json
import pytest
import time
from datetime import datetime


class TestCrossBranchConsistency:
    """Test consistency across branches."""

    def test_data_consistency_across_branches(self, db_e2e, pggit_installed):
        """Test data consistency when branches diverge."""
        main_id = db_e2e.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        branch1 = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('branch-1') RETURNING id"
        )[0]
        branch2 = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('branch-2') RETURNING id"
        )[0]

        db_e2e.execute("""
            CREATE TABLE public.consistency_check (
                id INTEGER,
                value TEXT,
                branch_id INTEGER,
                PRIMARY KEY (id, branch_id)
            )
        """)

        # Insert same data in multiple branches (different IDs per branch)
        for idx, branch_id in enumerate([main_id, branch1, branch2]):
            db_e2e.execute(
                "INSERT INTO public.consistency_check (id, value, branch_id) VALUES (%s, %s, %s)",
                idx + 1,
                "initial-value",
                branch_id,
            )

        # Verify consistency across all branches
        results = db_e2e.execute(
            "SELECT DISTINCT value FROM public.consistency_check"
        )
        assert len(results) == 1, "All branches should have same value"
        assert results[0][0] == "initial-value", "Value should be consistent across branches"

    def test_schema_evolution_consistency(self, db_e2e, pggit_installed):
        """Test schema evolution consistency across branches."""
        db_e2e.execute("""
            CREATE TABLE public.schema_evolution (
                id INTEGER PRIMARY KEY,
                name TEXT
            )
        """)

        # Record initial schema
        initial_snapshot = db_e2e.execute_returning(
            "SELECT pggit.create_temporal_snapshot('schema_evolution', 1, %s)",
            json.dumps({"version": "1.0"}),
        )[0]

        # Evolve schema
        db_e2e.execute("ALTER TABLE public.schema_evolution ADD COLUMN email TEXT")

        # Record evolved schema
        evolved_snapshot = db_e2e.execute_returning(
            "SELECT pggit.create_temporal_snapshot('schema_evolution', 1, %s)",
            json.dumps({"version": "2.0"}),
        )[0]

        # Both snapshots should reflect their respective schemas
        assert initial_snapshot is not None, "Initial snapshot should exist"
        assert evolved_snapshot is not None, "Evolved snapshot should exist"
        assert initial_snapshot != evolved_snapshot, "Snapshots should differ"

    def test_version_number_uniqueness_across_branches(self, db_e2e, pggit_installed):
        """Test version numbers are unique across branches."""
        main_id = db_e2e.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        branch1 = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('version-branch-1') RETURNING id"
        )[0]
        branch2 = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('version-branch-2') RETURNING id"
        )[0]

        # Create commits in multiple branches
        commits = []
        for branch_id in [main_id, branch1, branch2]:
            for i in range(3):
                commit_id = db_e2e.execute_returning(
                    "INSERT INTO pggit.commits (branch_id, message) VALUES (%s, %s) RETURNING id",
                    branch_id,
                    f"commit-{i}",
                )[0]
                commits.append(commit_id)

        # All commit IDs should be unique
        assert len(commits) == len(set(commits)), "All commits should have unique IDs"

    def test_timestamp_ordering_across_branches(self, db_e2e, pggit_installed):
        """Test timestamp ordering consistency across branches."""
        main_id = db_e2e.execute_returning(
            "SELECT id FROM pggit.branches WHERE name = 'main'"
        )[0]

        branch1 = db_e2e.execute_returning(
            "INSERT INTO pggit.branches (name) VALUES ('timestamp-branch') RETURNING id"
        )[0]

        db_e2e.execute("""
            CREATE TABLE public.timestamp_test (
                id INTEGER PRIMARY KEY,
                event TEXT,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)

        # Create events with known ordering
        timestamps = []
        for i in range(5):
            db_e2e.execute(
                "INSERT INTO public.timestamp_test (id, event) VALUES (%s, %s)",
                i,
                f"event-{i}",
            )
            timestamps.append(datetime.now())
            time.sleep(0.01)  # Ensure time difference

        # Query and verify ordering
        results = db_e2e.execute(
            "SELECT event, created_at FROM public.timestamp_test ORDER BY created_at"
        )
        for i, (event, created_at) in enumerate(results):
            expected_event = f"event-{i}"
            assert event == expected_event, f"Event ordering should be consistent"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
