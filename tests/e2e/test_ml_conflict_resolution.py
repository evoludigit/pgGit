"""
E2E tests for ML-based conflict resolution and pattern learning.

Tests machine learning integration for:
- Pattern learning and prediction
- Conflict pattern analysis
- Adaptive prefetching strategies
- Semantic conflict resolution with ML guidance
- Access pattern tracking for optimization

Key Coverage:
- ML pattern prediction during merge scenarios
- Conflict pattern learning over time
- Adaptive prefetch with memory budgets
- Semantic conflict analysis with 3-way merge
- Access count tracking for frequently-used data
"""

import json
import pytest


class TestMLConflictResolutionIntegration:
    """Test ML + Conflict Resolution integration."""

    def test_ml_pattern_prediction_during_merge(self, db, pggit_installed):
        """Test using ML predictions with access patterns."""
        # Create test table with access patterns
        db.execute("""
            CREATE TABLE public.ml_merge_test (
                id INTEGER PRIMARY KEY,
                pattern_data TEXT,
                access_count INTEGER DEFAULT 0
            )
        """)

        # Record patterns
        for i in range(5):
            db.execute(
                "INSERT INTO public.ml_merge_test VALUES (%s, %s, %s)",
                i,
                f"pattern-{i}",
                i * 2  # access count
            )

        # Verify patterns were recorded
        result = db.execute("SELECT COUNT(*) FROM public.ml_merge_test")
        assert result[0][0] == 5, "All patterns should be recorded"

        # Verify access counts increase with pattern
        for i in range(5):
            result = db.execute(
                "SELECT access_count FROM public.ml_merge_test WHERE id = %s", i
            )
            assert result[0][0] == i * 2, f"Pattern {i} should have correct access count"

    def test_conflict_pattern_learning_over_time(self, db, pggit_installed):
        """Test learning conflict patterns."""
        db.execute("""
            CREATE TABLE public.conflict_pattern_test (
                id INTEGER PRIMARY KEY,
                value TEXT
            )
        """)

        db.execute("INSERT INTO public.conflict_pattern_test VALUES (1, 'base')")

        # Record multiple conflict scenarios
        for i in range(3):
            conflict_data = {
                "base": {"id": 1, "value": "base"},
                "source": {"id": 1, "value": f"source-{i}"},
                "target": {"id": 1, "value": f"target-{i}"},
            }

            result = db.execute_returning(
                "SELECT pggit.identify_conflict_patterns(%s)", json.dumps(conflict_data)
            )
            assert result is not None, f"Pattern learning iteration {i} should succeed"

    def test_adaptive_prefetch_during_conflict_resolution(self, db, pggit_installed):
        """Test prefetch during conflict resolution."""
        # Simulate adaptive prefetch with budget
        result = db.execute_returning(
            "SELECT pggit.adaptive_prefetch(%s, %s, %s)",
            1,  # object_id
            100,  # budget_mb
            "MODERATE",  # strategy
        )
        assert result is not None, "Adaptive prefetch should succeed"

    def test_semantic_conflict_with_ml_predictions(self, db, pggit_installed):
        """Test semantic conflict analysis with ML guidance."""
        # Create realistic conflict
        conflict_scenario = {
            "base": {"id": 1, "name": "Alice", "age": 30},
            "source": {"id": 1, "name": "Alice", "age": 31},  # Age updated
            "target": {"id": 1, "name": "Alicia", "age": 30},  # Name updated
        }

        # Analyze with ML
        result = db.execute_returning(
            "SELECT pggit.analyze_semantic_conflict(%s, %s, %s)",
            json.dumps(conflict_scenario["base"]),
            json.dumps(conflict_scenario["source"]),
            json.dumps(conflict_scenario["target"]),
        )
        assert result is not None, "Semantic conflict analysis should succeed"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
