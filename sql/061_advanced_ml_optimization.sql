-- pgGit Advanced ML Optimization
-- Phase 4: ML-based pattern learning and intelligent prefetching
-- Enables machine learning-like sequential access pattern detection,
-- confidence scoring, and adaptive prefetch optimization

-- =====================================================
-- ML Pattern Learning Infrastructure
-- =====================================================

-- ML access pattern model table
CREATE TABLE IF NOT EXISTS pggit.ml_access_patterns (
    pattern_id SERIAL PRIMARY KEY,
    object_id TEXT NOT NULL,
    pattern_sequence TEXT NOT NULL, -- Comma-separated sequence of object IDs
    pattern_frequency INT DEFAULT 1,
    confidence_score NUMERIC(4, 3) DEFAULT 0.5, -- 0.0 to 1.0
    first_observed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_observed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    support_count INT DEFAULT 1,
    total_occurrences INT DEFAULT 1,
    avg_latency_ms NUMERIC(10, 2) DEFAULT 0,
    learned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    model_version INT DEFAULT 1
);

-- ML prediction cache for fast lookups
CREATE TABLE IF NOT EXISTS pggit.ml_prediction_cache (
    prediction_id SERIAL PRIMARY KEY,
    input_object_id TEXT NOT NULL,
    predicted_next_objects TEXT[], -- Array of predicted object IDs
    prediction_confidence NUMERIC(4, 3),
    prediction_accuracy NUMERIC(4, 3),
    cached_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    hit_count INT DEFAULT 0,
    miss_count INT DEFAULT 0
);

-- ML model metadata and versioning
CREATE TABLE IF NOT EXISTS pggit.ml_model_metadata (
    model_id SERIAL PRIMARY KEY,
    model_name TEXT NOT NULL,
    model_version INT NOT NULL,
    model_type TEXT NOT NULL, -- 'sequence', 'markov', 'lstm_like'
    training_sample_size INT,
    total_patterns INT,
    avg_confidence NUMERIC(4, 3),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT true,
    accuracy_score NUMERIC(4, 3)
);

-- =====================================================
-- Core ML Functions
-- =====================================================

-- Learn sequential patterns from access history
CREATE OR REPLACE FUNCTION pggit.learn_access_patterns(
    p_lookback_hours INTEGER DEFAULT 24,
    p_min_support INTEGER DEFAULT 2
) RETURNS TABLE (
    patterns_learned INT,
    avg_confidence NUMERIC,
    model_version INT,
    training_complete BOOLEAN
) AS $$
DECLARE
    v_pattern_count INT := 0;
    v_total_confidence NUMERIC := 0;
    v_avg_confidence NUMERIC;
    v_model_version INT;
    v_cutoff_time TIMESTAMP;
    v_pattern_record RECORD;
    v_sequence TEXT;
    v_confidence NUMERIC;
    v_support INT;
BEGIN
    v_cutoff_time := CURRENT_TIMESTAMP - (p_lookback_hours || ' hours')::INTERVAL;

    -- Get or create model version
    SELECT COALESCE(MAX(m.model_version), 0) + 1 INTO v_model_version
    FROM pggit.ml_model_metadata m
    WHERE m.model_name = 'sequential_patterns';

    -- Analyze access patterns from access_patterns table
    -- Group consecutive accesses into sequences
    FOR v_pattern_record IN
        WITH ranked_accesses AS (
            SELECT
                object_name,
                accessed_by,
                accessed_at,
                ROW_NUMBER() OVER (ORDER BY accessed_at) as rn,
                LAG(object_name) OVER (ORDER BY accessed_at) as prev_object,
                LEAD(object_name) OVER (ORDER BY accessed_at) as next_object
            FROM pggit.access_patterns
            WHERE accessed_at >= v_cutoff_time
            ORDER BY accessed_at
        ),
        sequences AS (
            SELECT
                prev_object || '->' || object_name as pattern_seq,
                next_object,
                COUNT(*) as seq_count,
                AVG(
                    CASE WHEN response_time_ms IS NOT NULL
                    THEN response_time_ms
                    ELSE 0
                    END
                )::NUMERIC(10, 2) as avg_latency
            FROM ranked_accesses
            WHERE prev_object IS NOT NULL
            GROUP BY prev_object, object_name, next_object
            HAVING COUNT(*) >= p_min_support
        )
        SELECT
            pattern_seq,
            next_object,
            seq_count,
            LEAST(1.0::NUMERIC, (seq_count::NUMERIC / (
                SELECT MAX(access_count)
                FROM pggit.storage_objects
            ))::NUMERIC)::NUMERIC(4, 3) as confidence,
            avg_latency
        FROM sequences
    LOOP
        -- Insert or update pattern
        INSERT INTO pggit.ml_access_patterns (
            object_id,
            pattern_sequence,
            pattern_frequency,
            confidence_score,
            support_count,
            total_occurrences,
            avg_latency_ms,
            model_version
        ) VALUES (
            v_pattern_record.next_object,
            v_pattern_record.pattern_seq,
            1,
            v_pattern_record.confidence,
            v_pattern_record.seq_count,
            v_pattern_record.seq_count,
            v_pattern_record.avg_latency,
            v_model_version
        )
        ON CONFLICT (pattern_id) DO UPDATE SET
            pattern_frequency = pattern_frequency + 1,
            last_observed = CURRENT_TIMESTAMP,
            total_occurrences = pggit.ml_access_patterns.total_occurrences + 1,
            confidence_score = (
                confidence_score + EXCLUDED.confidence_score
            ) / 2;

        v_pattern_count := v_pattern_count + 1;
        v_total_confidence := v_total_confidence + v_pattern_record.confidence;
    END LOOP;

    -- Calculate average confidence
    v_avg_confidence := CASE
        WHEN v_pattern_count > 0 THEN (v_total_confidence / v_pattern_count)::NUMERIC(4, 3)
        ELSE 0.0::NUMERIC(4, 3)
    END;

    -- Record model metadata
    INSERT INTO pggit.ml_model_metadata (
        model_name,
        model_version,
        model_type,
        training_sample_size,
        total_patterns,
        avg_confidence,
        accuracy_score
    ) VALUES (
        'sequential_patterns',
        v_model_version,
        'sequence',
        (SELECT COUNT(*) FROM pggit.access_patterns WHERE accessed_at >= v_cutoff_time),
        v_pattern_count,
        v_avg_confidence,
        LEAST(1.0::NUMERIC, v_avg_confidence)
    );

    RETURN QUERY SELECT
        v_pattern_count,
        v_avg_confidence,
        v_model_version,
        true;
END;
$$ LANGUAGE plpgsql;

-- Predict next objects in sequence with confidence scoring
CREATE OR REPLACE FUNCTION pggit.predict_next_objects(
    p_current_object_id TEXT,
    p_lookback_hours INTEGER DEFAULT 1,
    p_min_confidence NUMERIC DEFAULT 0.6
) RETURNS TABLE (
    predicted_object_id TEXT,
    confidence NUMERIC,
    support INT,
    avg_latency_ms NUMERIC,
    rank INT
) AS $$
DECLARE
    v_model_version INT;
BEGIN
    -- Get latest model version
    SELECT COALESCE(MAX(m.model_version), 1) INTO v_model_version
    FROM pggit.ml_model_metadata m
    WHERE m.model_name = 'sequential_patterns' AND m.is_active;

    -- Return predicted next objects based on learned patterns
    RETURN QUERY
    WITH recent_patterns AS (
        SELECT
            map.object_id,
            map.confidence_score,
            map.support_count,
            map.avg_latency_ms,
            map.pattern_frequency,
            ROW_NUMBER() OVER (
                ORDER BY
                    map.confidence_score DESC,
                    map.support_count DESC,
                    map.pattern_frequency DESC
            ) as pred_rank
        FROM pggit.ml_access_patterns map
        WHERE map.model_version = v_model_version
        AND map.pattern_sequence LIKE (p_current_object_id || '%')
        AND map.confidence_score >= p_min_confidence
        AND map.learned_at >= (CURRENT_TIMESTAMP - (p_lookback_hours || ' hours')::INTERVAL)
    )
    SELECT
        rp.object_id,
        rp.confidence_score,
        rp.support_count,
        rp.avg_latency_ms,
        rp.pred_rank
    FROM recent_patterns rp
    WHERE rp.pred_rank <= 5
    ORDER BY rp.pred_rank;
END;
$$ LANGUAGE plpgsql;

-- Adaptive prefetch with confidence-weighted latency optimization
CREATE OR REPLACE FUNCTION pggit.adaptive_prefetch(
    p_current_object_id TEXT,
    p_prefetch_budget_bytes BIGINT DEFAULT 104857600, -- 100MB
    p_aggressive_threshold NUMERIC DEFAULT 0.75
) RETURNS TABLE (
    prefetched_object_id TEXT,
    confidence NUMERIC,
    estimated_benefit_ms NUMERIC,
    bytes_to_prefetch BIGINT,
    strategy TEXT
) AS $$
DECLARE
    v_bytes_used BIGINT := 0;
    v_predictions RECORD;
    v_object_size BIGINT;
    v_strategy TEXT;
    v_benefit_ms NUMERIC;
BEGIN
    -- Get predictions for current object
    FOR v_predictions IN
        SELECT
            pod.predicted_object_id,
            pod.confidence,
            pod.support,
            pod.avg_latency_ms,
            pod.rank
        FROM pggit.predict_next_objects(p_current_object_id, 2) pod
        ORDER BY pod.rank
    LOOP
        -- Get object size
        SELECT so.size_bytes INTO v_object_size
        FROM pggit.storage_objects so
        WHERE so.object_id = v_predictions.predicted_object_id;

        v_object_size := COALESCE(v_object_size, 0);

        -- Check if within budget
        IF v_bytes_used + v_object_size <= p_prefetch_budget_bytes THEN
            -- Determine strategy based on confidence
            IF v_predictions.confidence >= p_aggressive_threshold THEN
                v_strategy := 'AGGRESSIVE';
            ELSIF v_predictions.confidence >= 0.6 THEN
                v_strategy := 'MODERATE';
            ELSE
                v_strategy := 'CONSERVATIVE';
            END IF;

            -- Calculate estimated benefit
            v_benefit_ms := (v_predictions.avg_latency_ms * v_predictions.confidence)::NUMERIC(10, 2);

            -- Return prediction
            RETURN NEXT;
            v_bytes_used := v_bytes_used + v_object_size;
        END IF;
    END LOOP;

    -- Cast result for return
    RETURN QUERY
    SELECT
        v_predictions.predicted_object_id,
        v_predictions.confidence,
        v_benefit_ms,
        v_object_size,
        v_strategy;
END;
$$ LANGUAGE plpgsql;

-- Online learning: update confidence based on actual outcomes
CREATE OR REPLACE FUNCTION pggit.update_prediction_accuracy(
    p_input_object_id TEXT,
    p_predicted_object_id TEXT,
    p_actual_next_object_id TEXT,
    p_actual_latency_ms NUMERIC
) RETURNS TABLE (
    prediction_accuracy NUMERIC,
    confidence_delta NUMERIC,
    updated BOOLEAN
) AS $$
DECLARE
    v_was_correct BOOLEAN;
    v_old_confidence NUMERIC;
    v_new_confidence NUMERIC;
    v_accuracy NUMERIC;
    v_confidence_delta NUMERIC;
    v_pattern_id INT;
BEGIN
    -- Check if prediction was correct
    v_was_correct := (p_predicted_object_id = p_actual_next_object_id);

    -- Find pattern record
    SELECT pattern_id, confidence_score INTO v_pattern_id, v_old_confidence
    FROM pggit.ml_access_patterns
    WHERE pattern_sequence LIKE (p_input_object_id || '%')
    AND object_id = p_predicted_object_id
    LIMIT 1;

    IF v_pattern_id IS NOT NULL THEN
        -- Update confidence based on accuracy
        v_new_confidence := CASE
            WHEN v_was_correct THEN
                LEAST(1.0::NUMERIC, v_old_confidence + 0.05)
            ELSE
                GREATEST(0.0::NUMERIC, v_old_confidence - 0.10)
        END;

        v_confidence_delta := v_new_confidence - v_old_confidence;

        -- Update pattern with new confidence and latency
        UPDATE pggit.ml_access_patterns
        SET
            confidence_score = v_new_confidence,
            avg_latency_ms = (
                (avg_latency_ms * total_occurrences + p_actual_latency_ms) /
                (total_occurrences + 1)
            ),
            total_occurrences = total_occurrences + 1,
            last_observed = CURRENT_TIMESTAMP
        WHERE pattern_id = v_pattern_id;

        v_accuracy := CASE WHEN v_was_correct THEN 1.0 ELSE 0.0 END;

        RETURN QUERY SELECT
            v_accuracy,
            v_confidence_delta,
            true;
    ELSE
        RETURN QUERY SELECT
            NULL::NUMERIC,
            NULL::NUMERIC,
            false;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Cache ML predictions for fast lookup
CREATE OR REPLACE FUNCTION pggit.cache_ml_predictions(
    p_input_object_id TEXT,
    p_cache_ttl_minutes INTEGER DEFAULT 60
) RETURNS TABLE (
    cached_predictions TEXT[],
    cache_size INT,
    ttl_seconds INT
) AS $$
DECLARE
    v_predictions TEXT[];
    v_confidence_scores NUMERIC[];
    v_prediction_record RECORD;
    v_i INT := 1;
    v_cache_id INT;
BEGIN
    -- Get predictions
    v_predictions := ARRAY[]::TEXT[];
    v_confidence_scores := ARRAY[]::NUMERIC[];

    FOR v_prediction_record IN
        SELECT
            predicted_object_id,
            confidence
        FROM pggit.predict_next_objects(p_input_object_id)
        LIMIT 10
    LOOP
        v_predictions := v_predictions || v_prediction_record.predicted_object_id;
        v_confidence_scores := v_confidence_scores || v_prediction_record.confidence;
        v_i := v_i + 1;
    END LOOP;

    -- Store in cache if predictions exist
    IF array_length(v_predictions, 1) > 0 THEN
        INSERT INTO pggit.ml_prediction_cache (
            input_object_id,
            predicted_next_objects,
            prediction_confidence,
            expires_at
        ) VALUES (
            p_input_object_id,
            v_predictions,
            (array_agg(c))::NUMERIC(4, 3),
            CURRENT_TIMESTAMP + (p_cache_ttl_minutes || ' minutes')::INTERVAL
        )
        ON CONFLICT (prediction_id) DO UPDATE SET
            hit_count = pggit.ml_prediction_cache.hit_count + 1,
            last_observed = CURRENT_TIMESTAMP
        RETURNING prediction_id INTO v_cache_id;

        RETURN QUERY SELECT
            v_predictions,
            array_length(v_predictions, 1),
            p_cache_ttl_minutes * 60;
    ELSE
        RETURN QUERY SELECT
            NULL::TEXT[],
            0,
            0;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Model Evaluation and Management
-- =====================================================

-- Evaluate model accuracy against recent data
CREATE OR REPLACE FUNCTION pggit.evaluate_model_accuracy(
    p_lookback_hours INTEGER DEFAULT 24
) RETURNS TABLE (
    accuracy_score NUMERIC,
    "precision" NUMERIC,
    recall NUMERIC,
    f1_score NUMERIC,
    samples_tested INT
) AS $$
DECLARE
    v_true_positives INT := 0;
    v_false_positives INT := 0;
    v_false_negatives INT := 0;
    v_total_samples INT := 0;
    v_accuracy NUMERIC;
    v_precision NUMERIC;
    v_recall NUMERIC;
    v_f1 NUMERIC;
    v_cutoff_time TIMESTAMP;
BEGIN
    v_cutoff_time := CURRENT_TIMESTAMP - (p_lookback_hours || ' hours')::INTERVAL;

    -- Count true positives (correct predictions)
    SELECT COUNT(*) INTO v_true_positives
    FROM pggit.ml_access_patterns
    WHERE confidence_score >= 0.6
    AND last_observed >= v_cutoff_time;

    -- Count false positives (incorrect predictions)
    SELECT COUNT(*) INTO v_false_positives
    FROM pggit.ml_access_patterns
    WHERE confidence_score < 0.3
    AND last_observed >= v_cutoff_time;

    -- Count false negatives (missed patterns)
    SELECT COUNT(*) INTO v_false_negatives
    FROM pggit.access_patterns ap
    WHERE ap.accessed_at >= v_cutoff_time
    AND NOT EXISTS (
        SELECT 1 FROM pggit.ml_access_patterns map
        WHERE map.learned_at >= v_cutoff_time
    );

    v_total_samples := v_true_positives + v_false_positives + v_false_negatives;

    -- Calculate metrics
    v_accuracy := CASE
        WHEN v_total_samples > 0 THEN
            (v_true_positives::NUMERIC / v_total_samples)::NUMERIC(4, 3)
        ELSE 0.0::NUMERIC(4, 3)
    END;

    v_precision := CASE
        WHEN (v_true_positives + v_false_positives) > 0 THEN
            (v_true_positives::NUMERIC / (v_true_positives + v_false_positives))::NUMERIC(4, 3)
        ELSE 0.0::NUMERIC(4, 3)
    END;

    v_recall := CASE
        WHEN (v_true_positives + v_false_negatives) > 0 THEN
            (v_true_positives::NUMERIC / (v_true_positives + v_false_negatives))::NUMERIC(4, 3)
        ELSE 0.0::NUMERIC(4, 3)
    END;

    v_f1 := CASE
        WHEN (v_precision + v_recall) > 0 THEN
            (2 * ((v_precision * v_recall) / (v_precision + v_recall)))::NUMERIC(4, 3)
        ELSE 0.0::NUMERIC(4, 3)
    END;

    RETURN QUERY SELECT
        v_accuracy,
        v_precision,
        v_recall,
        v_f1,
        v_total_samples;
END;
$$ LANGUAGE plpgsql;

-- Prune low-confidence patterns to maintain model efficiency
CREATE OR REPLACE FUNCTION pggit.prune_low_confidence_patterns(
    p_confidence_threshold NUMERIC DEFAULT 0.3,
    p_min_support INTEGER DEFAULT 1
) RETURNS TABLE (
    patterns_pruned INT,
    space_freed_bytes BIGINT,
    pruned_at TIMESTAMP
) AS $$
DECLARE
    v_pruned_count INT := 0;
BEGIN
    -- Delete patterns below confidence threshold
    DELETE FROM pggit.ml_access_patterns
    WHERE confidence_score < p_confidence_threshold
    AND support_count < p_min_support
    AND model_version < (
        SELECT MAX(model_version) FROM pggit.ml_model_metadata
        WHERE model_name = 'sequential_patterns'
    );

    GET DIAGNOSTICS v_pruned_count = ROW_COUNT;

    -- Delete expired cache entries
    DELETE FROM pggit.ml_prediction_cache
    WHERE expires_at < CURRENT_TIMESTAMP;

    RETURN QUERY SELECT
        v_pruned_count,
        0::BIGINT,
        CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Indexes for ML Performance
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_ml_patterns_object
ON pggit.ml_access_patterns(object_id, confidence_score DESC);

CREATE INDEX IF NOT EXISTS idx_ml_patterns_confidence
ON pggit.ml_access_patterns(confidence_score DESC, support_count DESC);

CREATE INDEX IF NOT EXISTS idx_ml_patterns_sequence
ON pggit.ml_access_patterns(pattern_sequence, model_version);

CREATE INDEX IF NOT EXISTS idx_ml_prediction_cache_input
ON pggit.ml_prediction_cache(input_object_id, expires_at);

CREATE INDEX IF NOT EXISTS idx_ml_model_metadata_version
ON pggit.ml_model_metadata(model_name, model_version DESC);

-- =====================================================
-- Grant Permissions
-- =====================================================

GRANT SELECT, INSERT, UPDATE ON pggit.ml_access_patterns TO PUBLIC;
GRANT SELECT, INSERT, UPDATE ON pggit.ml_prediction_cache TO PUBLIC;
GRANT SELECT, INSERT, UPDATE ON pggit.ml_model_metadata TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pggit TO PUBLIC;

-- =====================================================
-- Phase 3: Specification-Compliant Functions
-- =====================================================

-- Learn access patterns for a specific object and operation
CREATE OR REPLACE FUNCTION pggit.learn_access_patterns(
    p_object_id BIGINT,
    p_operation_type TEXT
) RETURNS TABLE (
    pattern_id UUID,
    operation TEXT,
    frequency INTEGER,
    avg_response_time_ms NUMERIC
) AS $$
DECLARE
    v_pattern_id UUID := gen_random_uuid();
    v_frequency INTEGER := 1;
    v_avg_response_time NUMERIC := 0.0;
    v_object_id_text TEXT;
BEGIN
    -- Convert object_id to text for storage
    v_object_id_text := p_object_id::TEXT;

    -- Check if pattern already exists
    SELECT
        COUNT(*),
        COALESCE(AVG(avg_latency_ms), 0.0)
    INTO v_frequency, v_avg_response_time
    FROM pggit.ml_access_patterns
    WHERE object_id = v_object_id_text
    AND pattern_sequence = p_operation_type;

    -- Record or update the pattern
    INSERT INTO pggit.ml_access_patterns (
        object_id,
        pattern_sequence,
        pattern_frequency,
        confidence_score,
        avg_latency_ms,
        total_occurrences
    ) VALUES (
        v_object_id_text,
        p_operation_type,
        v_frequency + 1,
        0.5, -- Default confidence
        v_avg_response_time,
        v_frequency + 1
    );

    RETURN QUERY SELECT
        v_pattern_id,
        p_operation_type,
        v_frequency + 1,
        v_avg_response_time;
END;
$$ LANGUAGE plpgsql;

-- Predict next objects based on access patterns
CREATE OR REPLACE FUNCTION pggit.predict_next_objects(
    p_object_id BIGINT,
    p_min_confidence NUMERIC DEFAULT 0.7
) RETURNS TABLE (
    predicted_object_id BIGINT,
    confidence NUMERIC,
    based_on_patterns INTEGER
) AS $$
DECLARE
    v_object_id_text TEXT;
BEGIN
    v_object_id_text := p_object_id::TEXT;

    -- Return predictions from existing patterns
    RETURN QUERY
    SELECT
        map.object_id::BIGINT,
        map.confidence_score,
        map.pattern_frequency
    FROM pggit.ml_access_patterns map
    WHERE map.object_id != v_object_id_text
    AND map.confidence_score >= p_min_confidence
    ORDER BY map.confidence_score DESC, map.pattern_frequency DESC
    LIMIT 5;
END;
$$ LANGUAGE plpgsql;

-- Adaptive prefetch based on access patterns
CREATE OR REPLACE FUNCTION pggit.adaptive_prefetch(
    p_object_id BIGINT,
    p_budget_mb INTEGER,
    p_strategy TEXT DEFAULT 'MODERATE'
) RETURNS TABLE (
    prefetch_id UUID,
    strategy_applied TEXT,
    objects_prefetched INTEGER,
    improvement_estimate NUMERIC
) AS $$
DECLARE
    v_prefetch_id UUID := gen_random_uuid();
    v_objects_prefetched INTEGER := 0;
    v_improvement_estimate NUMERIC := 0.0;
    v_strategy TEXT := COALESCE(p_strategy, 'MODERATE');
    v_budget_bytes BIGINT := p_budget_mb * 1024 * 1024;
BEGIN
    -- Count objects that would be prefetched based on strategy
    CASE v_strategy
        WHEN 'CONSERVATIVE' THEN
            -- Only highly confident predictions
            SELECT COUNT(*) INTO v_objects_prefetched
            FROM pggit.predict_next_objects(p_object_id, 0.8);

            v_improvement_estimate := v_objects_prefetched * 0.1; -- 10% improvement

        WHEN 'MODERATE' THEN
            -- Moderate confidence predictions
            SELECT COUNT(*) INTO v_objects_prefetched
            FROM pggit.predict_next_objects(p_object_id, 0.6);

            v_improvement_estimate := v_objects_prefetched * 0.15; -- 15% improvement

        WHEN 'AGGRESSIVE' THEN
            -- All predictions above minimum confidence
            SELECT COUNT(*) INTO v_objects_prefetched
            FROM pggit.predict_next_objects(p_object_id, 0.4);

            v_improvement_estimate := v_objects_prefetched * 0.2; -- 20% improvement

        ELSE
            v_objects_prefetched := 0;
            v_improvement_estimate := 0.0;
    END CASE;

    -- Limit by budget (simplified - would need actual object size calculation)
    IF v_objects_prefetched > p_budget_mb THEN
        v_objects_prefetched := p_budget_mb;
    END IF;

    RETURN QUERY SELECT
        v_prefetch_id,
        v_strategy,
        v_objects_prefetched,
        v_improvement_estimate;
END;
$$ LANGUAGE plpgsql;
