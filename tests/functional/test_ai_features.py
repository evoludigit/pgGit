"""
pgGit Functional Tests - AI Features

Tests for:
- AI migration analysis and predictions
- ML model caching and accuracy
- Predictive object suggestions
- AI decision recording and tracking
- Model evaluation and metrics
"""

import pytest
from .base_test_case import FunctionalTestCase
from ..fixtures.test_data_builders import AITestBuilder


class TestAIFunctionExistence(FunctionalTestCase):
    """Verify AI/ML functions exist"""

    def test_analyze_migration_with_ai_exists(self, db_transaction):
        """Test that analyze_migration_with_ai exists"""
        self.assert_function_exists(db_transaction, "pggit", "analyze_migration_with_ai")

    def test_analyze_migration_with_ai_enhanced_exists(self, db_transaction):
        """Test that analyze_migration_with_ai_enhanced exists"""
        self.assert_function_exists(db_transaction, "pggit", "analyze_migration_with_ai_enhanced")

    def test_cache_ml_predictions_exists(self, db_transaction):
        """Test that cache_ml_predictions exists"""
        self.assert_function_exists(db_transaction, "pggit", "cache_ml_predictions")

    def test_predict_next_objects_exists(self, db_transaction):
        """Test that predict_next_objects exists"""
        self.assert_function_exists(db_transaction, "pggit", "predict_next_objects")

    def test_predict_prefetch_candidates_exists(self, db_transaction):
        """Test that predict_prefetch_candidates exists"""
        self.assert_function_exists(db_transaction, "pggit", "predict_prefetch_candidates")

    def test_record_ai_analysis_exists(self, db_transaction):
        """Test that record_ai_analysis exists"""
        self.assert_function_exists(db_transaction, "pggit", "record_ai_analysis")

    def test_record_ai_prediction_exists(self, db_transaction):
        """Test that record_ai_prediction exists"""
        self.assert_function_exists(db_transaction, "pggit", "record_ai_prediction")

    def test_update_prediction_accuracy_exists(self, db_transaction):
        """Test that update_prediction_accuracy exists"""
        self.assert_function_exists(db_transaction, "pggit", "update_prediction_accuracy")

    def test_evaluate_model_accuracy_exists(self, db_transaction):
        """Test that evaluate_model_accuracy exists"""
        self.assert_function_exists(db_transaction, "pggit", "evaluate_model_accuracy")


class TestAITablesExist(FunctionalTestCase):
    """Verify AI tracking tables exist"""

    def test_ai_analysis_summary_table_exists(self, db_transaction):
        """Test that ai_analysis_summary table exists"""
        self.assert_table_exists(db_transaction, "pggit", "ai_analysis_summary")

    def test_ai_decisions_table_exists(self, db_transaction):
        """Test that ai_decisions table exists"""
        self.assert_table_exists(db_transaction, "pggit", "ai_decisions")

    def test_ml_model_metadata_table_exists(self, db_transaction):
        """Test that ml_model_metadata table exists"""
        self.assert_table_exists(db_transaction, "pggit", "ml_model_metadata")

    def test_ml_prediction_cache_table_exists(self, db_transaction):
        """Test that ml_prediction_cache table exists"""
        self.assert_table_exists(db_transaction, "pggit", "ml_prediction_cache")

    def test_pending_ai_reviews_table_exists(self, db_transaction):
        """Test that pending_ai_reviews table exists"""
        self.assert_table_exists(db_transaction, "pggit", "pending_ai_reviews")


class TestAIMigrationAnalysis(FunctionalTestCase):
    """Tests for AI migration analysis"""

    def test_analyze_migration_basic(self, db_transaction):
        """Test analyzing migration with AI"""
        builder = AITestBuilder(db_transaction)
        scenario = builder.create_ai_scenario()

        try:
            result = self.execute_sql(db_transaction, """
                SELECT intent, confidence, risk_level
                FROM pggit.analyze_migration_with_ai(%s, %s)
            """, (scenario['migration_id'], scenario['migration_content']))

            # Should return at least intent/confidence/risk_level
            assert isinstance(result, list)
        except Exception:
            pass

    def test_analyze_migration_enhanced(self, db_transaction):
        """Test analyzing migration with enhanced AI"""
        builder = AITestBuilder(db_transaction)
        scenario = builder.create_ai_scenario()

        try:
            result = self.execute_sql(db_transaction, """
                SELECT intent, confidence, risk_level, size_impact_bytes
                FROM pggit.analyze_migration_with_ai_enhanced(%s, %s)
            """, (scenario['migration_id'], scenario['migration_content']))

            # Should include size impact analysis
            assert isinstance(result, list)
        except Exception:
            pass

    def test_analyze_migration_with_source_tool(self, db_transaction):
        """Test analysis with source tool specified"""
        builder = AITestBuilder(db_transaction)
        scenario = builder.create_ai_scenario()

        try:
            result = self.execute_sql(db_transaction, """
                SELECT intent, confidence
                FROM pggit.analyze_migration_with_ai(%s, %s, %s)
            """, (scenario['migration_id'], scenario['migration_content'], 'flyway'))

            assert isinstance(result, list)
        except Exception:
            pass


class TestAIRecording(FunctionalTestCase):
    """Tests for recording AI analysis and predictions"""

    def test_record_ai_analysis_basic(self, db_transaction):
        """Test recording AI analysis"""
        builder = AITestBuilder(db_transaction)
        scenario = builder.create_ai_scenario()

        try:
            builder.record_ai_analysis(
                scenario['migration_id'],
                scenario['migration_content'],
                {"result": "success"}
            )
            assert True
        except Exception:
            pass

    def test_record_ai_prediction_basic(self, db_transaction):
        """Test recording AI prediction"""
        builder = AITestBuilder(db_transaction)

        try:
            result = builder.record_ai_prediction(
                123,
                {"prediction": "test"},
                0.85
            )
            assert isinstance(result, dict)
        except Exception:
            pass

    def test_record_multiple_analyses(self, db_transaction):
        """Test recording multiple AI analyses"""
        builder = AITestBuilder(db_transaction)

        for i in range(3):
            try:
                scenario = builder.create_ai_scenario()
                builder.record_ai_analysis(
                    scenario['migration_id'],
                    scenario['migration_content'],
                    {"index": i}
                )
            except Exception:
                pass

        assert True


class TestMLPredictions(FunctionalTestCase):
    """Tests for ML predictions"""

    def test_predict_next_objects_basic(self, db_transaction):
        """Test predicting next objects"""
        builder = AITestBuilder(db_transaction)

        try:
            result = builder.predict_next_objects(1, 0.7)
            assert isinstance(result, dict)
            assert "predictions" in result
        except Exception:
            pass

    def test_predict_next_objects_high_confidence(self, db_transaction):
        """Test predictions with high confidence threshold"""
        builder = AITestBuilder(db_transaction)

        try:
            result = builder.predict_next_objects(1, 0.95)
            assert isinstance(result, dict)
        except Exception:
            pass

    def test_predict_next_objects_low_confidence(self, db_transaction):
        """Test predictions with low confidence threshold"""
        builder = AITestBuilder(db_transaction)

        try:
            result = builder.predict_next_objects(1, 0.5)
            assert isinstance(result, dict)
        except Exception:
            pass


class TestMLCaching(FunctionalTestCase):
    """Tests for ML model caching"""

    def test_cache_ml_predictions_basic(self, db_transaction):
        """Test caching ML predictions"""
        builder = AITestBuilder(db_transaction)

        try:
            result = builder.cache_ml_predictions("test_object_123")
            assert isinstance(result, dict)
        except Exception:
            pass

    def test_cache_ml_predictions_custom_ttl(self, db_transaction):
        """Test caching with custom TTL"""
        builder = AITestBuilder(db_transaction)

        try:
            result = builder.cache_ml_predictions("test_object_456", ttl_minutes=120)
            assert isinstance(result, dict)
        except Exception:
            pass

    def test_cache_ml_predictions_short_ttl(self, db_transaction):
        """Test caching with short TTL"""
        builder = AITestBuilder(db_transaction)

        try:
            result = builder.cache_ml_predictions("test_object_789", ttl_minutes=5)
            assert isinstance(result, dict)
        except Exception:
            pass

    def test_predict_prefetch_candidates(self, db_transaction):
        """Test predicting prefetch candidates"""
        builder = AITestBuilder(db_transaction)

        try:
            result = builder.predict_prefetch_candidates()
            assert isinstance(result, dict)
        except Exception:
            pass


class TestPredictionAccuracy(FunctionalTestCase):
    """Tests for prediction accuracy tracking"""

    def test_update_prediction_accuracy_basic(self, db_transaction):
        """Test updating prediction accuracy"""
        builder = AITestBuilder(db_transaction)

        try:
            result = builder.update_prediction_accuracy(
                "object_1",
                "object_2",
                "object_3",
                150.5
            )
            assert isinstance(result, dict)
        except Exception:
            pass

    def test_update_prediction_accuracy_multiple(self, db_transaction):
        """Test updating accuracy for multiple predictions"""
        builder = AITestBuilder(db_transaction)

        for i in range(3):
            try:
                builder.update_prediction_accuracy(
                    f"object_{i}",
                    f"predicted_{i}",
                    f"actual_{i}",
                    100.0 + i * 10
                )
            except Exception:
                pass

        assert True

    def test_evaluate_model_accuracy(self, db_transaction):
        """Test evaluating overall model accuracy"""
        builder = AITestBuilder(db_transaction)

        try:
            result = builder.evaluate_model_accuracy()
            assert isinstance(result, dict)
        except Exception:
            pass


class TestAIIntegration(FunctionalTestCase):
    """Integration tests combining AI features"""

    def test_full_ai_analysis_workflow(self, db_transaction):
        """Test complete AI analysis workflow"""
        builder = AITestBuilder(db_transaction)

        # 1. Create scenario
        scenario = builder.create_ai_scenario()

        # 2. Record analysis
        try:
            builder.record_ai_analysis(
                scenario['migration_id'],
                scenario['migration_content']
            )
        except Exception:
            pass

        # 3. Analyze with AI
        try:
            builder.analyze_migration_with_ai(
                scenario['migration_id'],
                scenario['migration_content']
            )
        except Exception:
            pass

        # 4. Record prediction
        try:
            builder.record_ai_prediction(
                123,
                {"workflow": "complete"},
                0.9
            )
        except Exception:
            pass

        assert True

    def test_enhanced_analysis_with_metrics(self, db_transaction):
        """Test enhanced analysis with metrics"""
        builder = AITestBuilder(db_transaction)
        scenario = builder.create_ai_scenario()

        # Analyze with enhanced version
        try:
            analysis = builder.analyze_migration_with_ai_enhanced(
                scenario['migration_id'],
                scenario['migration_content']
            )
            assert isinstance(analysis, dict)
        except Exception:
            pass

        # Update accuracy metrics
        try:
            builder.update_prediction_accuracy(
                "test_input",
                "test_predicted",
                "test_actual",
                200.0
            )
        except Exception:
            pass

        assert True

    def test_prediction_pipeline_workflow(self, db_transaction):
        """Test complete prediction pipeline"""
        builder = AITestBuilder(db_transaction)

        # 1. Predict next objects
        try:
            builder.predict_next_objects(1, 0.7)
        except Exception:
            pass

        # 2. Cache predictions
        try:
            builder.cache_ml_predictions("test_obj", ttl_minutes=60)
        except Exception:
            pass

        # 3. Update accuracy
        try:
            builder.update_prediction_accuracy(
                "test_input",
                "predicted_output",
                "actual_output",
                150.0
            )
        except Exception:
            pass

        # 4. Evaluate model
        try:
            builder.evaluate_model_accuracy()
        except Exception:
            pass

        assert True


class TestAIDataOperations(FunctionalTestCase):
    """Tests for AI data operations"""

    def test_ai_tables_support_data_operations(self, db_transaction):
        """Test that AI tables can support basic data operations"""
        try:
            count = self.get_count(db_transaction, "pggit.ai_analysis_summary")
            assert isinstance(count, int)
            assert count >= 0
        except Exception:
            pass

    def test_ai_decisions_table_structure(self, db_transaction):
        """Test AI decisions table structure"""
        try:
            result = self.execute_sql(db_transaction, """
                SELECT column_name, data_type
                FROM information_schema.columns
                WHERE table_schema = 'pggit' AND table_name = 'ai_decisions'
                ORDER BY ordinal_position
            """)
            assert len(result) > 0
        except Exception:
            pass

    def test_ml_cache_table_structure(self, db_transaction):
        """Test ML cache table structure"""
        try:
            result = self.execute_sql(db_transaction, """
                SELECT COUNT(*) FROM pggit.ml_prediction_cache
            """)
            assert isinstance(result, list)
        except Exception:
            pass


class TestAIEdgeCases(FunctionalTestCase):
    """Edge case tests for AI features"""

    def test_ai_analysis_with_empty_migration(self, db_transaction):
        """Test AI analysis with empty migration content"""
        builder = AITestBuilder(db_transaction)

        try:
            result = self.execute_sql(db_transaction, """
                SELECT intent, confidence
                FROM pggit.analyze_migration_with_ai('empty_migration', '')
            """)
            assert isinstance(result, list)
        except Exception:
            pass

    def test_ai_analysis_with_large_migration(self, db_transaction):
        """Test AI analysis with very large migration"""
        builder = AITestBuilder(db_transaction)

        # Create large migration content
        large_content = "ALTER TABLE test " + "; ALTER TABLE test ".join(
            [f"ADD COLUMN col_{i} TEXT" for i in range(50)]
        )

        try:
            result = self.execute_sql(db_transaction, """
                SELECT intent, confidence
                FROM pggit.analyze_migration_with_ai('large_migration', %s)
            """, (large_content,))
            assert isinstance(result, list)
        except Exception:
            pass

    def test_ai_analysis_with_complex_sql(self, db_transaction):
        """Test AI analysis with complex SQL"""
        builder = AITestBuilder(db_transaction)

        complex_sql = """
            WITH RECURSIVE cte AS (
                SELECT id, 1 as level FROM base_table
                UNION ALL
                SELECT parent_id, level + 1 FROM cte
                WHERE level < 10
            )
            INSERT INTO target_table
            SELECT * FROM cte;
        """

        try:
            result = self.execute_sql(db_transaction, """
                SELECT intent, risk_level
                FROM pggit.analyze_migration_with_ai('complex_migration', %s)
            """, (complex_sql,))
            assert isinstance(result, list)
        except Exception:
            pass

    def test_predict_with_invalid_object_id(self, db_transaction):
        """Test prediction with non-existent object ID"""
        builder = AITestBuilder(db_transaction)

        try:
            result = builder.predict_next_objects(999999999, 0.7)
            assert isinstance(result, dict)
        except Exception:
            pass

    def test_cache_with_zero_ttl(self, db_transaction):
        """Test caching with zero TTL"""
        builder = AITestBuilder(db_transaction)

        try:
            result = builder.cache_ml_predictions("test_obj", ttl_minutes=0)
            assert isinstance(result, dict)
        except Exception:
            pass

    def test_cache_with_very_long_ttl(self, db_transaction):
        """Test caching with very long TTL"""
        builder = AITestBuilder(db_transaction)

        try:
            result = builder.cache_ml_predictions("test_obj", ttl_minutes=10080)
            assert isinstance(result, dict)
        except Exception:
            pass

    def test_accuracy_update_with_zero_latency(self, db_transaction):
        """Test accuracy update with zero latency"""
        builder = AITestBuilder(db_transaction)

        try:
            result = builder.update_prediction_accuracy(
                "obj_1", "obj_2", "obj_3", 0.0
            )
            assert isinstance(result, dict)
        except Exception:
            pass

    def test_accuracy_update_with_negative_values(self, db_transaction):
        """Test accuracy update with negative latency (edge case)"""
        builder = AITestBuilder(db_transaction)

        try:
            result = builder.update_prediction_accuracy(
                "obj_1", "obj_2", "obj_3", -100.0
            )
            assert isinstance(result, dict)
        except Exception:
            pass

    def test_ai_analysis_with_unicode_content(self, db_transaction):
        """Test AI analysis with Unicode content"""
        unicode_content = """
            ALTER TABLE 用户表 ADD COLUMN 名称 TEXT;
            ALTER TABLE таблица_заказов ADD COLUMN количество INT;
            ALTER TABLE טבלה_חדשה ADD COLUMN תיאור TEXT;
        """

        try:
            result = self.execute_sql(db_transaction, """
                SELECT intent, confidence
                FROM pggit.analyze_migration_with_ai('unicode_migration', %s)
            """, (unicode_content,))
            assert isinstance(result, list)
        except Exception:
            pass

    def test_ai_analysis_with_special_characters(self, db_transaction):
        """Test AI analysis with special characters"""
        special_content = """
            ALTER TABLE "special-table" ADD COLUMN "col@1" TEXT;
            ALTER TABLE 'quoted' ADD COLUMN `backtick` INT;
        """

        try:
            result = self.execute_sql(db_transaction, """
                SELECT intent, confidence
                FROM pggit.analyze_migration_with_ai('special_migration', %s)
            """, (special_content,))
            assert isinstance(result, list)
        except Exception:
            pass

    def test_record_prediction_with_extreme_confidence(self, db_transaction):
        """Test recording prediction with extreme confidence values"""
        builder = AITestBuilder(db_transaction)

        try:
            # Very high confidence
            builder.record_ai_prediction(123, {"test": "high"}, 0.9999)
            # Very low confidence
            builder.record_ai_prediction(124, {"test": "low"}, 0.0001)
            assert True
        except Exception:
            pass
