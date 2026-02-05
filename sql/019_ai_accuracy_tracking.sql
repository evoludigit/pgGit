-- pgGit AI Accuracy Tracking System
-- Measure and improve AI migration analysis accuracy
-- Track the mythical 91.7% accuracy claim

-- =====================================================
-- AI Accuracy Tracking Tables
-- =====================================================

CREATE TABLE IF NOT EXISTS pggit.ai_predictions (
    prediction_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    migration_id TEXT NOT NULL,
    prediction_type TEXT NOT NULL, -- 'intent', 'risk', 'impact', 'success'
    predicted_value TEXT NOT NULL,
    confidence_score DECIMAL(5,4) NOT NULL,
    model_version TEXT NOT NULL,
    features_used JSONB,
    prediction_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    inference_time_ms INT
);

CREATE TABLE IF NOT EXISTS pggit.ai_ground_truth (
    truth_id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    prediction_id UUID REFERENCES pggit.ai_predictions(prediction_id),
    migration_id TEXT NOT NULL,
    actual_value TEXT NOT NULL,
    verified_by TEXT DEFAULT current_user,
    verified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    verification_method TEXT, -- 'manual', 'automated', 'production_result'
    notes TEXT
);

CREATE TABLE IF NOT EXISTS pggit.ai_accuracy_metrics (
    metric_id SERIAL PRIMARY KEY,
    model_version TEXT NOT NULL,
    prediction_type TEXT NOT NULL,
    time_period TSRANGE NOT NULL,
    total_predictions INT NOT NULL,
    correct_predictions INT NOT NULL,
    accuracy_percentage DECIMAL(5,2) NOT NULL,
    precision_score DECIMAL(5,4),
    recall_score DECIMAL(5,4),
    f1_score DECIMAL(5,4),
    confidence_calibration DECIMAL(5,4),
    calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(model_version, prediction_type, time_period)
);

CREATE TABLE IF NOT EXISTS pggit.ai_model_performance (
    performance_id SERIAL PRIMARY KEY,
    model_version TEXT NOT NULL,
    deployment_date TIMESTAMP NOT NULL,
    total_migrations_analyzed BIGINT DEFAULT 0,
    average_accuracy DECIMAL(5,2),
    average_confidence DECIMAL(5,4),
    average_inference_time_ms DECIMAL(10,2),
    false_positive_rate DECIMAL(5,4),
    false_negative_rate DECIMAL(5,4),
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pggit.ai_feature_importance (
    feature_id SERIAL PRIMARY KEY,
    model_version TEXT NOT NULL,
    feature_name TEXT NOT NULL,
    importance_score DECIMAL(5,4),
    correlation_with_accuracy DECIMAL(5,4),
    usage_count BIGINT DEFAULT 0,
    last_calculated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(model_version, feature_name)
);

-- =====================================================
-- AI Accuracy Tracking Functions
-- =====================================================

-- Record AI prediction
CREATE OR REPLACE FUNCTION pggit.record_ai_prediction(
    p_migration_id TEXT,
    p_prediction_type TEXT,
    p_predicted_value TEXT,
    p_confidence DECIMAL,
    p_model_version TEXT,
    p_features JSONB DEFAULT NULL,
    p_inference_time_ms INT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_prediction_id UUID;
BEGIN
    INSERT INTO pggit.ai_predictions (
        migration_id,
        prediction_type,
        predicted_value,
        confidence_score,
        model_version,
        features_used,
        inference_time_ms
    ) VALUES (
        p_migration_id,
        p_prediction_type,
        p_predicted_value,
        p_confidence,
        p_model_version,
        p_features,
        p_inference_time_ms
    ) RETURNING prediction_id INTO v_prediction_id;
    
    -- Update model performance stats
    INSERT INTO pggit.ai_model_performance (
        model_version,
        deployment_date,
        total_migrations_analyzed,
        average_confidence,
        average_inference_time_ms
    ) VALUES (
        p_model_version,
        now(),
        1,
        p_confidence,
        p_inference_time_ms
    )
    ON CONFLICT (model_version, deployment_date) DO UPDATE
    SET total_migrations_analyzed = ai_model_performance.total_migrations_analyzed + 1,
        average_confidence = (
            (ai_model_performance.average_confidence * ai_model_performance.total_migrations_analyzed + p_confidence) /
            (ai_model_performance.total_migrations_analyzed + 1)
        ),
        average_inference_time_ms = CASE 
            WHEN p_inference_time_ms IS NOT NULL THEN
                (ai_model_performance.average_inference_time_ms * ai_model_performance.total_migrations_analyzed + p_inference_time_ms) /
                (ai_model_performance.total_migrations_analyzed + 1)
            ELSE ai_model_performance.average_inference_time_ms
        END,
        last_updated = now();
    
    RETURN v_prediction_id;
END;
$$ LANGUAGE plpgsql;

-- Record ground truth
CREATE OR REPLACE FUNCTION pggit.record_ground_truth(
    p_prediction_id UUID,
    p_actual_value TEXT,
    p_verification_method TEXT DEFAULT 'manual',
    p_notes TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_truth_id UUID;
    v_migration_id TEXT;
BEGIN
    -- Get migration ID from prediction
    SELECT migration_id INTO v_migration_id
    FROM pggit.ai_predictions
    WHERE prediction_id = p_prediction_id;
    
    -- Record ground truth
    INSERT INTO pggit.ai_ground_truth (
        prediction_id,
        migration_id,
        actual_value,
        verification_method,
        notes
    ) VALUES (
        p_prediction_id,
        v_migration_id,
        p_actual_value,
        p_verification_method,
        p_notes
    ) RETURNING truth_id INTO v_truth_id;
    
    -- Trigger accuracy calculation
    PERFORM pggit.update_accuracy_metrics();
    
    RETURN v_truth_id;
END;
$$ LANGUAGE plpgsql;

-- Calculate accuracy metrics
CREATE OR REPLACE FUNCTION pggit.calculate_accuracy_metrics(
    p_model_version TEXT DEFAULT NULL,
    p_time_period TSRANGE DEFAULT NULL
) RETURNS TABLE (
    model_version TEXT,
    prediction_type TEXT,
    accuracy DECIMAL,
    precision_val DECIMAL,
    recall DECIMAL,
    f1 DECIMAL,
    sample_size INT
) AS $$
BEGIN
    RETURN QUERY
    WITH predictions_with_truth AS (
        SELECT 
            p.model_version,
            p.prediction_type,
            p.predicted_value,
            p.confidence_score,
            gt.actual_value,
            p.predicted_value = gt.actual_value as is_correct
        FROM pggit.ai_predictions p
        JOIN pggit.ai_ground_truth gt ON p.prediction_id = gt.prediction_id
        WHERE (p_model_version IS NULL OR p.model_version = p_model_version)
        AND (p_time_period IS NULL OR p.prediction_time <@ p_time_period)
    ),
    accuracy_stats AS (
        SELECT 
            model_version,
            prediction_type,
            COUNT(*) as total,
            SUM(CASE WHEN is_correct THEN 1 ELSE 0 END) as correct,
            -- For binary classification metrics
            SUM(CASE WHEN is_correct AND predicted_value = 'true' THEN 1 ELSE 0 END) as true_positives,
            SUM(CASE WHEN NOT is_correct AND predicted_value = 'true' THEN 1 ELSE 0 END) as false_positives,
            SUM(CASE WHEN is_correct AND predicted_value = 'false' THEN 1 ELSE 0 END) as true_negatives,
            SUM(CASE WHEN NOT is_correct AND predicted_value = 'false' THEN 1 ELSE 0 END) as false_negatives
        FROM predictions_with_truth
        GROUP BY model_version, prediction_type
    )
    SELECT 
        s.model_version,
        s.prediction_type,
        ROUND((s.correct::DECIMAL / s.total) * 100, 2) as accuracy,
        CASE 
            WHEN s.true_positives + s.false_positives > 0 THEN
                ROUND(s.true_positives::DECIMAL / (s.true_positives + s.false_positives), 4)
            ELSE NULL
        END as precision_val,
        CASE 
            WHEN s.true_positives + s.false_negatives > 0 THEN
                ROUND(s.true_positives::DECIMAL / (s.true_positives + s.false_negatives), 4)
            ELSE NULL
        END as recall,
        CASE 
            WHEN s.true_positives > 0 THEN
                ROUND(2 * (
                    (s.true_positives::DECIMAL / (s.true_positives + s.false_positives)) *
                    (s.true_positives::DECIMAL / (s.true_positives + s.false_negatives))
                ) / (
                    (s.true_positives::DECIMAL / (s.true_positives + s.false_positives)) +
                    (s.true_positives::DECIMAL / (s.true_positives + s.false_negatives))
                ), 4)
            ELSE NULL
        END as f1,
        s.total::INT as sample_size
    FROM accuracy_stats s;
END;
$$ LANGUAGE plpgsql;

-- Update accuracy metrics
CREATE OR REPLACE FUNCTION pggit.update_accuracy_metrics()
RETURNS VOID AS $$
DECLARE
    v_metric RECORD;
BEGIN
    -- Calculate metrics for each model version and prediction type
    FOR v_metric IN
        SELECT * FROM pggit.calculate_accuracy_metrics()
    LOOP
        INSERT INTO pggit.ai_accuracy_metrics (
            model_version,
            prediction_type,
            time_period,
            total_predictions,
            correct_predictions,
            accuracy_percentage,
            precision_score,
            recall_score,
            f1_score
        ) VALUES (
            v_metric.model_version,
            v_metric.prediction_type,
            tsrange(now() - interval '24 hours', now()),
            v_metric.sample_size,
            (v_metric.accuracy * v_metric.sample_size / 100)::INT,
            v_metric.accuracy,
            v_metric.precision_val,
            v_metric.recall,
            v_metric.f1
        )
        ON CONFLICT ON CONSTRAINT ai_accuracy_metrics_model_version_prediction_type_time_peri_excl
        DO UPDATE SET
            total_predictions = EXCLUDED.total_predictions,
            correct_predictions = EXCLUDED.correct_predictions,
            accuracy_percentage = EXCLUDED.accuracy_percentage,
            precision_score = EXCLUDED.precision_score,
            recall_score = EXCLUDED.recall_score,
            f1_score = EXCLUDED.f1_score,
            calculated_at = now();
    END LOOP;
    
    -- Update model performance
    UPDATE pggit.ai_model_performance mp
    SET average_accuracy = (
        SELECT AVG(accuracy_percentage)
        FROM pggit.ai_accuracy_metrics am
        WHERE am.model_version = mp.model_version
        AND am.calculated_at >= now() - interval '7 days'
    ),
    false_positive_rate = (
        SELECT AVG(1 - precision_score)
        FROM pggit.ai_accuracy_metrics am
        WHERE am.model_version = mp.model_version
        AND am.calculated_at >= now() - interval '7 days'
        AND precision_score IS NOT NULL
    ),
    false_negative_rate = (
        SELECT AVG(1 - recall_score)
        FROM pggit.ai_accuracy_metrics am
        WHERE am.model_version = mp.model_version
        AND am.calculated_at >= now() - interval '7 days'
        AND recall_score IS NOT NULL
    ),
    last_updated = now();
END;
$$ LANGUAGE plpgsql;

-- Get AI accuracy report
CREATE OR REPLACE FUNCTION pggit.get_ai_accuracy_report(
    p_model_version TEXT DEFAULT NULL
) RETURNS TABLE (
    report_section TEXT,
    metrics JSONB
) AS $$
BEGIN
    -- Overall accuracy (the mythical 91.7%)
    RETURN QUERY
    SELECT 
        'overall_accuracy',
        jsonb_build_object(
            'current_accuracy', COALESCE(AVG(accuracy_percentage), 0),
            'target_accuracy', 91.7,
            'gap', 91.7 - COALESCE(AVG(accuracy_percentage), 0),
            'trend', CASE 
                WHEN AVG(accuracy_percentage) > 90 THEN 'on_track'
                WHEN AVG(accuracy_percentage) > 85 THEN 'improving'
                ELSE 'needs_work'
            END
        )
    FROM pggit.ai_accuracy_metrics
    WHERE (p_model_version IS NULL OR model_version = p_model_version)
    AND calculated_at >= now() - interval '7 days';
    
    -- Accuracy by prediction type
    RETURN QUERY
    SELECT 
        'accuracy_by_type',
        jsonb_object_agg(
            prediction_type,
            jsonb_build_object(
                'accuracy', accuracy_percentage,
                'precision', precision_score,
                'recall', recall_score,
                'f1', f1_score,
                'samples', total_predictions
            )
        )
    FROM pggit.ai_accuracy_metrics
    WHERE (p_model_version IS NULL OR model_version = p_model_version)
    AND calculated_at >= now() - interval '24 hours'
    GROUP BY model_version;
    
    -- Model comparison
    RETURN QUERY
    SELECT 
        'model_comparison',
        jsonb_object_agg(
            model_version,
            jsonb_build_object(
                'avg_accuracy', average_accuracy,
                'total_analyzed', total_migrations_analyzed,
                'avg_inference_time_ms', average_inference_time_ms,
                'deployment_date', deployment_date
            )
        )
    FROM pggit.ai_model_performance
    WHERE last_updated >= now() - interval '30 days';
    
    -- Confidence calibration
    RETURN QUERY
    WITH confidence_buckets AS (
        SELECT 
            WIDTH_BUCKET(p.confidence_score, 0, 1, 10) as confidence_bucket,
            COUNT(*) as total,
            SUM(CASE WHEN p.predicted_value = gt.actual_value THEN 1 ELSE 0 END) as correct
        FROM pggit.ai_predictions p
        JOIN pggit.ai_ground_truth gt ON p.prediction_id = gt.prediction_id
        WHERE (p_model_version IS NULL OR p.model_version = p_model_version)
        GROUP BY confidence_bucket
    )
    SELECT 
        'confidence_calibration',
        jsonb_agg(
            jsonb_build_object(
                'confidence_range', 
                format('[%s-%s]', 
                    (confidence_bucket - 1) * 0.1,
                    confidence_bucket * 0.1
                ),
                'expected_accuracy', (confidence_bucket - 0.5) * 0.1,
                'actual_accuracy', ROUND(correct::DECIMAL / total, 4),
                'calibration_error', ABS((confidence_bucket - 0.5) * 0.1 - correct::DECIMAL / total)
            ) ORDER BY confidence_bucket
        )
    FROM confidence_buckets;
END;
$$ LANGUAGE plpgsql;

-- Analyze feature importance
CREATE OR REPLACE FUNCTION pggit.analyze_feature_importance(
    p_model_version TEXT
) RETURNS VOID AS $$
DECLARE
    v_feature RECORD;
BEGIN
    -- Analyze which features correlate with accurate predictions
    FOR v_feature IN
        WITH feature_accuracy AS (
            SELECT 
                jsonb_object_keys(p.features_used) as feature_name,
                p.predicted_value = gt.actual_value as is_correct
            FROM pggit.ai_predictions p
            JOIN pggit.ai_ground_truth gt ON p.prediction_id = gt.prediction_id
            WHERE p.model_version = p_model_version
            AND p.features_used IS NOT NULL
        )
        SELECT 
            feature_name,
            COUNT(*) as usage_count,
            AVG(CASE WHEN is_correct THEN 1.0 ELSE 0.0 END) as accuracy_rate
        FROM feature_accuracy
        GROUP BY feature_name
    LOOP
        INSERT INTO pggit.ai_feature_importance (
            model_version,
            feature_name,
            importance_score,
            correlation_with_accuracy,
            usage_count
        ) VALUES (
            p_model_version,
            v_feature.feature_name,
            v_feature.accuracy_rate,
            v_feature.accuracy_rate - 0.5, -- Simple correlation
            v_feature.usage_count
        )
        ON CONFLICT (model_version, feature_name) DO UPDATE
        SET importance_score = EXCLUDED.importance_score,
            correlation_with_accuracy = EXCLUDED.correlation_with_accuracy,
            usage_count = EXCLUDED.usage_count,
            last_calculated = now();
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Simulate achieving 91.7% accuracy
CREATE OR REPLACE FUNCTION pggit.simulate_accuracy_improvement(
    p_target_accuracy DECIMAL DEFAULT 91.7
) RETURNS TABLE (
    week INT,
    simulated_accuracy DECIMAL,
    improvement_rate DECIMAL
) AS $$
BEGIN
    -- Show path to 91.7% accuracy
    RETURN QUERY
    WITH RECURSIVE accuracy_simulation AS (
        -- Start from current accuracy
        SELECT 
            0 as week,
            COALESCE(AVG(accuracy_percentage), 75.0) as accuracy,
            5.0 as improvement_rate
        FROM pggit.ai_accuracy_metrics
        WHERE calculated_at >= now() - interval '7 days'
        
        UNION ALL
        
        -- Simulate weekly improvements
        SELECT 
            week + 1,
            LEAST(
                accuracy + (improvement_rate * (1 - (accuracy / 100))), -- Diminishing returns
                p_target_accuracy
            ),
            improvement_rate * 0.9 -- Decreasing improvement rate
        FROM accuracy_simulation
        WHERE week < 20 AND accuracy < p_target_accuracy
    )
    SELECT 
        week,
        ROUND(accuracy, 2),
        ROUND(improvement_rate, 2)
    FROM accuracy_simulation;
END;
$$ LANGUAGE plpgsql;

-- Create accuracy tracking views
CREATE OR REPLACE VIEW pggit.ai_accuracy_dashboard AS
SELECT 
    am.model_version,
    ROUND(AVG(am.accuracy_percentage), 2) as overall_accuracy,
    ROUND(AVG(am.accuracy_percentage), 2) || '%' as accuracy_display,
    CASE 
        WHEN AVG(am.accuracy_percentage) >= 91.7 THEN '🎯 Target Achieved!'
        WHEN AVG(am.accuracy_percentage) >= 90 THEN '📈 Almost There!'
        WHEN AVG(am.accuracy_percentage) >= 85 THEN '👍 Good Progress'
        ELSE '🔧 Keep Improving'
    END as status,
    COUNT(DISTINCT am.prediction_type) as prediction_types,
    SUM(am.total_predictions) as total_predictions,
    MIN(am.calculated_at) as first_measurement,
    MAX(am.calculated_at) as last_measurement
FROM pggit.ai_accuracy_metrics am
WHERE am.calculated_at >= now() - interval '30 days'
GROUP BY am.model_version;

CREATE OR REPLACE VIEW pggit.ai_prediction_audit AS
SELECT 
    p.prediction_id,
    p.migration_id,
    p.prediction_type,
    p.predicted_value,
    p.confidence_score,
    gt.actual_value,
    p.predicted_value = gt.actual_value as is_correct,
    p.model_version,
    p.prediction_time,
    gt.verified_at,
    gt.verification_method
FROM pggit.ai_predictions p
LEFT JOIN pggit.ai_ground_truth gt ON p.prediction_id = gt.prediction_id
ORDER BY p.prediction_time DESC;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_predictions_model_time 
ON pggit.ai_predictions(model_version, prediction_time DESC);

CREATE INDEX IF NOT EXISTS idx_predictions_type 
ON pggit.ai_predictions(prediction_type);

CREATE INDEX IF NOT EXISTS idx_ground_truth_prediction 
ON pggit.ai_ground_truth(prediction_id);

CREATE INDEX IF NOT EXISTS idx_accuracy_metrics_model 
ON pggit.ai_accuracy_metrics(model_version, calculated_at DESC);

-- Grant permissions
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA pggit TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pggit TO PUBLIC;