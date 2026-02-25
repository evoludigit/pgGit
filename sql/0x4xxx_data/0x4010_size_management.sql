-- pggit Database Size Management & Branch Pruning
-- AI-powered recommendations for maintaining reasonable database capacities
-- 100% MIT Licensed - No premium gates

-- =====================================================
-- Size Management Tables
-- =====================================================

-- Find unreferenced blobs (defined early as it's used by other functions)
CREATE OR REPLACE FUNCTION pggit.find_unreferenced_blobs()
RETURNS TABLE (
    blob_hash TEXT,
    object_name TEXT,
    size_bytes INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        b.blob_hash,
        b.object_name,
        LENGTH(b.object_definition::text)
    FROM pggit.blobs b
    WHERE NOT EXISTS (
        SELECT 1
        FROM pggit.commits c
        WHERE c.tree_hash = b.blob_hash
    )
    AND b.created_at < CURRENT_TIMESTAMP - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;

-- Track size metrics for branches
CREATE TABLE IF NOT EXISTS pggit.branch_size_metrics (
    id SERIAL PRIMARY KEY,
    branch_name TEXT NOT NULL,
    branch_status pggit.branch_status,
    object_count INTEGER NOT NULL DEFAULT 0,
    total_size_bytes BIGINT NOT NULL DEFAULT 0,
    data_size_bytes BIGINT NOT NULL DEFAULT 0,
    index_size_bytes BIGINT NOT NULL DEFAULT 0,
    blob_count INTEGER NOT NULL DEFAULT 0,
    blob_size_bytes BIGINT NOT NULL DEFAULT 0,
    commit_count INTEGER NOT NULL DEFAULT 0,
    last_commit_date TIMESTAMP,
    last_accessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Track database growth over time
CREATE TABLE IF NOT EXISTS pggit.size_history (
    id SERIAL PRIMARY KEY,
    total_size_bytes BIGINT NOT NULL,
    branch_count INTEGER NOT NULL,
    active_branch_count INTEGER NOT NULL,
    blob_count INTEGER NOT NULL,
    commit_count INTEGER NOT NULL,
    unreferenced_blob_count INTEGER NOT NULL DEFAULT 0,
    measured_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Pruning recommendations from AI
CREATE TABLE IF NOT EXISTS pggit.pruning_recommendations (
    id SERIAL PRIMARY KEY,
    branch_name TEXT NOT NULL,
    recommendation_type TEXT NOT NULL, -- 'DELETE', 'ARCHIVE', 'COMPRESS', 'KEEP'
    reason TEXT NOT NULL,
    confidence DECIMAL NOT NULL DEFAULT 0.8,
    space_savings_bytes BIGINT,
    risk_level TEXT DEFAULT 'LOW', -- 'LOW', 'MEDIUM', 'HIGH'
    priority INTEGER DEFAULT 5, -- 1-10, 10 being highest priority
    status TEXT DEFAULT 'PENDING', -- 'PENDING', 'APPLIED', 'REJECTED', 'DEFERRED'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    applied_at TIMESTAMP,
    rejected_reason TEXT
);

-- =====================================================
-- Size Analysis Functions
-- =====================================================

-- Calculate branch size metrics
CREATE OR REPLACE FUNCTION pggit.calculate_branch_size(
    p_branch_name TEXT
) RETURNS TABLE (
    object_count INTEGER,
    total_size_bytes BIGINT,
    data_size_bytes BIGINT,
    blob_count INTEGER,
    blob_size_bytes BIGINT,
    commit_count INTEGER,
    last_commit_date TIMESTAMP
) AS $$
DECLARE
    v_branch_id INTEGER;
    v_object_count INTEGER := 0;
    v_data_size BIGINT := 0;
    v_blob_count INTEGER := 0;
    v_blob_size BIGINT := 0;
    v_commit_count INTEGER := 0;
    v_last_commit TIMESTAMP;
BEGIN
    -- Get branch ID
    SELECT id INTO v_branch_id
    FROM pggit.branches
    WHERE name = p_branch_name;
    
    IF v_branch_id IS NULL THEN
        RAISE EXCEPTION 'Branch % not found', p_branch_name;
    END IF;
    
    -- Count commits
    SELECT COUNT(*), MAX(commit_date)
    INTO v_commit_count, v_last_commit
    FROM pggit.commits
    WHERE branch_id = v_branch_id;
    
    -- Calculate blob sizes
    SELECT COUNT(DISTINCT b.id), COALESCE(SUM(LENGTH(b.content::text)), 0)
    INTO v_blob_count, v_blob_size
    FROM pggit.commits c
    JOIN pggit.trees t ON c.tree_id = t.id
    JOIN pggit.blobs b ON b.tree_id = t.id
    WHERE c.branch_id = v_branch_id;
    
    -- Calculate data branch sizes
    SELECT COALESCE(SUM(pg_total_relation_size(table_schema || '.' || table_name)), 0)
    INTO v_data_size
    FROM pggit.data_branches db
    JOIN pggit.branches b ON db.branch_id = b.id
    WHERE b.name = p_branch_name;
    
    -- Count total objects
    v_object_count := v_commit_count + v_blob_count;
    
    RETURN QUERY SELECT 
        v_object_count,
        v_blob_size + v_data_size,
        v_data_size,
        v_blob_count,
        v_blob_size,
        v_commit_count,
        v_last_commit;
END;
$$ LANGUAGE plpgsql;

-- Update all branch size metrics
CREATE OR REPLACE FUNCTION pggit.update_branch_metrics()
RETURNS TABLE (
    branch_name TEXT,
    size_bytes BIGINT,
    object_count INTEGER
) AS $$
BEGIN
    -- Clear old metrics
    TRUNCATE pggit.branch_size_metrics;
    
    -- Insert updated metrics
    INSERT INTO pggit.branch_size_metrics (
        branch_name,
        branch_status,
        object_count,
        total_size_bytes,
        data_size_bytes,
        blob_count,
        blob_size_bytes,
        commit_count,
        last_commit_date
    )
    SELECT 
        b.name,
        b.status,
        metrics.object_count,
        metrics.total_size_bytes,
        metrics.data_size_bytes,
        metrics.blob_count,
        metrics.blob_size_bytes,
        metrics.commit_count,
        metrics.last_commit_date
    FROM pggit.branches b
    CROSS JOIN LATERAL pggit.calculate_branch_size(b.name) metrics;
    
    -- Record history
    INSERT INTO pggit.size_history (
        total_size_bytes,
        branch_count,
        active_branch_count,
        blob_count,
        commit_count,
        unreferenced_blob_count
    )
    SELECT 
        SUM(total_size_bytes),
        COUNT(*),
        COUNT(*) FILTER (WHERE branch_status = 'ACTIVE'),
        SUM(blob_count),
        SUM(commit_count),
        (SELECT COUNT(*) FROM pggit.find_unreferenced_blobs())
    FROM pggit.branch_size_metrics;
    
    -- Return summary
    RETURN QUERY 
    SELECT 
        bsm.branch_name,
        bsm.total_size_bytes,
        bsm.object_count
    FROM pggit.branch_size_metrics bsm
    ORDER BY bsm.total_size_bytes DESC;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- AI-Powered Pruning Analysis
-- =====================================================

-- Analyze branch for pruning recommendations
CREATE OR REPLACE FUNCTION pggit.analyze_branch_for_pruning(
    p_branch_name TEXT
) RETURNS TABLE (
    recommendation TEXT,
    reason TEXT,
    confidence DECIMAL,
    space_savings_bytes BIGINT,
    risk_level TEXT,
    priority INTEGER
) AS $$
DECLARE
    v_metrics RECORD;
    v_branch RECORD;
    v_recommendation TEXT;
    v_reason TEXT;
    v_confidence DECIMAL := 0.8;
    v_savings BIGINT := 0;
    v_risk TEXT := 'LOW';
    v_priority INTEGER := 5;
    v_days_inactive INTEGER;
    v_has_unmerged_changes BOOLEAN;
BEGIN
    -- Get branch info
    SELECT * INTO v_branch
    FROM pggit.branches
    WHERE name = p_branch_name;
    
    IF v_branch IS NULL THEN
        RAISE EXCEPTION 'Branch % not found', p_branch_name;
    END IF;
    
    -- Get metrics
    SELECT * INTO v_metrics
    FROM pggit.branch_size_metrics
    WHERE branch_name = p_branch_name;
    
    -- Calculate days inactive
    v_days_inactive := EXTRACT(DAY FROM CURRENT_TIMESTAMP - v_metrics.last_commit_date);
    
    -- Check for unmerged changes
    v_has_unmerged_changes := EXISTS (
        SELECT 1 
        FROM pggit.commits c 
        WHERE c.branch_id = v_branch.id 
        AND NOT EXISTS (
            SELECT 1 
            FROM pggit.commits main_c 
            WHERE main_c.branch_id = (SELECT id FROM pggit.branches WHERE name = 'main')
            AND main_c.tree_id = c.tree_id
        )
    );
    
    -- Decision logic
    IF v_branch.status = 'MERGED' THEN
        v_recommendation := 'DELETE';
        v_reason := format('Branch has been merged and is consuming %s MB', 
                          (v_metrics.total_size_bytes / 1024 / 1024)::TEXT);
        v_confidence := 0.95;
        v_savings := v_metrics.total_size_bytes;
        v_priority := 8;
        
    ELSIF v_branch.status = 'DELETED' THEN
        v_recommendation := 'DELETE';
        v_reason := 'Branch is marked as deleted but still has data';
        v_confidence := 0.99;
        v_savings := v_metrics.total_size_bytes;
        v_priority := 10;
        
    ELSIF v_days_inactive > 180 AND NOT v_has_unmerged_changes THEN
        v_recommendation := 'ARCHIVE';
        v_reason := format('Branch inactive for %s days with no unmerged changes', v_days_inactive);
        v_confidence := 0.85;
        v_savings := v_metrics.total_size_bytes * 0.7; -- Assume 70% savings from archival
        v_priority := 6;
        
    ELSIF v_days_inactive > 90 AND v_metrics.total_size_bytes > 100 * 1024 * 1024 THEN -- 100MB
        v_recommendation := 'COMPRESS';
        v_reason := format('Large branch (%s MB) inactive for %s days', 
                          (v_metrics.total_size_bytes / 1024 / 1024)::TEXT, v_days_inactive);
        v_confidence := 0.75;
        v_savings := v_metrics.total_size_bytes * 0.5; -- Assume 50% compression
        v_priority := 7;
        v_risk := 'MEDIUM';
        
    ELSIF v_branch.status = 'CONFLICTED' AND v_days_inactive > 30 THEN
        v_recommendation := 'ARCHIVE';
        v_reason := format('Conflicted branch inactive for %s days', v_days_inactive);
        v_confidence := 0.7;
        v_savings := v_metrics.total_size_bytes * 0.7;
        v_priority := 5;
        v_risk := 'MEDIUM';
        
    ELSE
        v_recommendation := 'KEEP';
        v_reason := 'Branch is active or has recent changes';
        v_confidence := 0.9;
        v_savings := 0;
        v_priority := 1;
    END IF;
    
    -- Adjust risk based on branch importance
    IF p_branch_name IN ('main', 'master', 'production', 'develop') THEN
        v_risk := 'HIGH';
        v_priority := GREATEST(v_priority - 3, 1);
        v_confidence := v_confidence * 0.7;
    END IF;
    
    RETURN QUERY SELECT 
        v_recommendation,
        v_reason,
        v_confidence,
        v_savings,
        v_risk,
        v_priority;
END;
$$ LANGUAGE plpgsql;

-- Generate pruning recommendations for all branches
CREATE OR REPLACE FUNCTION pggit.generate_pruning_recommendations(
    p_size_threshold_mb INTEGER DEFAULT 50,
    p_inactive_days INTEGER DEFAULT 90
) RETURNS TABLE (
    branch_name TEXT,
    recommendation TEXT,
    reason TEXT,
    space_savings_mb DECIMAL,
    priority INTEGER
) AS $$
BEGIN
    -- Clear old recommendations
    DELETE FROM pggit.pruning_recommendations 
    WHERE status = 'PENDING' 
    AND created_at < CURRENT_TIMESTAMP - INTERVAL '7 days';
    
    -- Update metrics first
    PERFORM pggit.update_branch_metrics();
    
    -- Generate new recommendations
    INSERT INTO pggit.pruning_recommendations (
        branch_name,
        recommendation_type,
        reason,
        confidence,
        space_savings_bytes,
        risk_level,
        priority
    )
    SELECT 
        b.name,
        analysis.recommendation,
        analysis.reason,
        analysis.confidence,
        analysis.space_savings_bytes,
        analysis.risk_level,
        analysis.priority
    FROM pggit.branches b
    CROSS JOIN LATERAL pggit.analyze_branch_for_pruning(b.name) analysis
    WHERE analysis.recommendation != 'KEEP'
    AND (
        (analysis.space_savings_bytes > p_size_threshold_mb * 1024 * 1024) OR
        (b.name IN (
            SELECT bsm.branch_name 
            FROM pggit.branch_size_metrics bsm
            WHERE EXTRACT(DAY FROM CURRENT_TIMESTAMP - bsm.last_commit_date) > p_inactive_days
        ))
    );
    
    -- Return summary
    RETURN QUERY
    SELECT 
        pr.branch_name,
        pr.recommendation_type,
        pr.reason,
        ROUND(pr.space_savings_bytes::DECIMAL / 1024 / 1024, 2),
        pr.priority
    FROM pggit.pruning_recommendations pr
    WHERE pr.status = 'PENDING'
    ORDER BY pr.priority DESC, pr.space_savings_bytes DESC;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Branch Pruning Operations
-- =====================================================

-- Delete a branch and all associated data
CREATE OR REPLACE FUNCTION pggit.delete_branch(
    p_branch_name TEXT,
    p_force BOOLEAN DEFAULT FALSE
) RETURNS TABLE (
    objects_deleted INTEGER,
    space_freed_bytes BIGINT
) AS $$
DECLARE
    v_branch_id INTEGER;
    v_objects_deleted INTEGER := 0;
    v_space_freed BIGINT := 0;
    v_branch_status pggit.branch_status;
BEGIN
    -- Get branch info
    SELECT id, status 
    INTO v_branch_id, v_branch_status
    FROM pggit.branches
    WHERE name = p_branch_name;
    
    IF v_branch_id IS NULL THEN
        RAISE EXCEPTION 'Branch % not found', p_branch_name;
    END IF;
    
    -- Check if safe to delete
    IF NOT p_force AND v_branch_status = 'ACTIVE' THEN
        RAISE EXCEPTION 'Cannot delete active branch % without force flag', p_branch_name;
    END IF;
    
    IF NOT p_force AND p_branch_name IN ('main', 'master') THEN
        RAISE EXCEPTION 'Cannot delete protected branch % without force flag', p_branch_name;
    END IF;
    
    -- Calculate space to be freed
    SELECT total_size_bytes 
    INTO v_space_freed
    FROM pggit.branch_size_metrics
    WHERE branch_name = p_branch_name;
    
    -- Delete branch data tables
    DELETE FROM pggit.data_branches
    WHERE branch_id = v_branch_id;
    
    -- Delete commits (cascades to other tables)
    DELETE FROM pggit.commits
    WHERE branch_id = v_branch_id;
    GET DIAGNOSTICS v_objects_deleted = ROW_COUNT;
    
    -- Delete branch reference
    DELETE FROM pggit.refs
    WHERE ref_name = 'refs/heads/' || p_branch_name;
    
    -- Finally delete the branch
    DELETE FROM pggit.branches
    WHERE id = v_branch_id;
    
    -- Clean up unreferenced blobs
    PERFORM pggit.cleanup_unreferenced_blobs();
    
    RETURN QUERY SELECT v_objects_deleted, v_space_freed;
END;
$$ LANGUAGE plpgsql;

-- List branches for deletion
CREATE OR REPLACE FUNCTION pggit.list_branches(
    p_status pggit.branch_status DEFAULT NULL,
    p_inactive_days INTEGER DEFAULT NULL
) RETURNS TABLE (
    branch_name TEXT,
    status pggit.branch_status,
    size_mb DECIMAL,
    last_commit TIMESTAMP,
    days_inactive INTEGER,
    commit_count INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        b.name,
        b.status,
        ROUND(bsm.total_size_bytes::DECIMAL / 1024 / 1024, 2),
        bsm.last_commit_date,
        EXTRACT(DAY FROM CURRENT_TIMESTAMP - bsm.last_commit_date)::INTEGER,
        bsm.commit_count
    FROM pggit.branches b
    LEFT JOIN pggit.branch_size_metrics bsm ON b.name = bsm.branch_name
    WHERE (p_status IS NULL OR b.status = p_status)
    AND (p_inactive_days IS NULL OR 
         EXTRACT(DAY FROM CURRENT_TIMESTAMP - bsm.last_commit_date) > p_inactive_days)
    ORDER BY bsm.total_size_bytes DESC NULLS LAST;
END;
$$ LANGUAGE plpgsql;

-- Clean up merged branches
CREATE OR REPLACE FUNCTION pggit.cleanup_merged_branches(
    p_dry_run BOOLEAN DEFAULT TRUE
) RETURNS TABLE (
    branch_name TEXT,
    space_freed_mb DECIMAL,
    action_taken TEXT
) AS $$
DECLARE
    v_branch RECORD;
    v_total_freed BIGINT := 0;
BEGIN
    FOR v_branch IN 
        SELECT b.name, bsm.total_size_bytes
        FROM pggit.branches b
        JOIN pggit.branch_size_metrics bsm ON b.name = bsm.branch_name
        WHERE b.status = 'MERGED'
        ORDER BY bsm.total_size_bytes DESC
    LOOP
        IF p_dry_run THEN
            RETURN QUERY
            SELECT 
                v_branch.name,
                ROUND(v_branch.total_size_bytes::DECIMAL / 1024 / 1024, 2),
                'WOULD DELETE'::TEXT;
        ELSE
            PERFORM pggit.delete_branch(v_branch.name, FALSE);
            v_total_freed := v_total_freed + v_branch.total_size_bytes;
            
            RETURN QUERY
            SELECT 
                v_branch.name,
                ROUND(v_branch.total_size_bytes::DECIMAL / 1024 / 1024, 2),
                'DELETED'::TEXT;
        END IF;
    END LOOP;
    
    IF NOT p_dry_run THEN
        RAISE NOTICE 'Total space freed: % MB', ROUND(v_total_freed::DECIMAL / 1024 / 1024, 2);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Apply pruning recommendations
CREATE OR REPLACE FUNCTION pggit.apply_pruning_recommendation(
    p_recommendation_id INTEGER
) RETURNS TEXT AS $$
DECLARE
    v_recommendation RECORD;
    v_result TEXT;
BEGIN
    -- Get recommendation
    SELECT * INTO v_recommendation
    FROM pggit.pruning_recommendations
    WHERE id = p_recommendation_id
    AND status = 'PENDING';
    
    IF v_recommendation IS NULL THEN
        RAISE EXCEPTION 'Recommendation % not found or already processed', p_recommendation_id;
    END IF;
    
    -- Apply based on type
    CASE v_recommendation.recommendation_type
        WHEN 'DELETE' THEN
            PERFORM pggit.delete_branch(v_recommendation.branch_name, FALSE);
            v_result := format('Deleted branch %s, freed %s MB', 
                             v_recommendation.branch_name,
                             ROUND(v_recommendation.space_savings_bytes::DECIMAL / 1024 / 1024, 2));
            
        WHEN 'ARCHIVE' THEN
            -- Archive implementation would go here
            v_result := format('Archived branch %s (not yet implemented)', v_recommendation.branch_name);
            
        WHEN 'COMPRESS' THEN
            -- Compression implementation would go here
            v_result := format('Compressed branch %s (not yet implemented)', v_recommendation.branch_name);
            
        ELSE
            RAISE EXCEPTION 'Unknown recommendation type: %', v_recommendation.recommendation_type;
    END CASE;
    
    -- Update recommendation status
    UPDATE pggit.pruning_recommendations
    SET status = 'APPLIED',
        applied_at = CURRENT_TIMESTAMP
    WHERE id = p_recommendation_id;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Monitoring Views
-- =====================================================

-- Database size overview
CREATE OR REPLACE VIEW pggit.database_size_overview AS
SELECT 
    (SELECT COUNT(*) FROM pggit.branches) as total_branches,
    (SELECT COUNT(*) FROM pggit.branches WHERE status = 'ACTIVE') as active_branches,
    (SELECT COUNT(*) FROM pggit.branches WHERE status = 'MERGED') as merged_branches,
    (SELECT SUM(total_size_bytes) FROM pggit.branch_size_metrics) as total_size_bytes,
    (SELECT pg_size_pretty(SUM(total_size_bytes)) FROM pggit.branch_size_metrics) as total_size_pretty,
    (SELECT COUNT(*) FROM pggit.commits) as total_commits,
    (SELECT COUNT(*) FROM pggit.blobs) as total_blobs,
    (SELECT COUNT(*) FROM pggit.find_unreferenced_blobs()) as unreferenced_blobs,
    (SELECT COUNT(*) FROM pggit.pruning_recommendations WHERE status = 'PENDING') as pending_recommendations;

-- Top space consuming branches
CREATE OR REPLACE VIEW pggit.top_space_consumers AS
SELECT 
    bsm.branch_name,
    b.status,
    pg_size_pretty(bsm.total_size_bytes) as total_size,
    pg_size_pretty(bsm.data_size_bytes) as data_size,
    pg_size_pretty(bsm.blob_size_bytes) as blob_size,
    bsm.commit_count,
    bsm.last_commit_date,
    EXTRACT(DAY FROM CURRENT_TIMESTAMP - bsm.last_commit_date) as days_inactive
FROM pggit.branch_size_metrics bsm
JOIN pggit.branches b ON b.name = bsm.branch_name
ORDER BY bsm.total_size_bytes DESC
LIMIT 20;

-- Size growth trend
CREATE OR REPLACE VIEW pggit.size_growth_trend AS
SELECT 
    DATE_TRUNC('day', measured_at) as date,
    pg_size_pretty(AVG(total_size_bytes)::BIGINT) as avg_size,
    AVG(branch_count)::INTEGER as avg_branches,
    AVG(active_branch_count)::INTEGER as avg_active_branches,
    pg_size_pretty((MAX(total_size_bytes) - MIN(total_size_bytes))::BIGINT) as daily_growth
FROM pggit.size_history
WHERE measured_at > CURRENT_TIMESTAMP - INTERVAL '30 days'
GROUP BY DATE_TRUNC('day', measured_at)
ORDER BY date DESC;

-- =====================================================
-- Scheduled Maintenance Functions
-- =====================================================

-- Run daily maintenance
CREATE OR REPLACE FUNCTION pggit.run_size_maintenance()
RETURNS TEXT AS $$
DECLARE
    v_recommendations_count INTEGER;
    v_space_freed BIGINT := 0;
    v_blobs_cleaned INTEGER;
    rec RECORD;
BEGIN
    -- Update metrics
    PERFORM pggit.update_branch_metrics();
    
    -- Generate new recommendations
    SELECT COUNT(*) INTO v_recommendations_count
    FROM pggit.generate_pruning_recommendations();
    
    -- Auto-apply safe recommendations
    FOR rec IN 
        SELECT id, space_savings_bytes
        FROM pggit.pruning_recommendations
        WHERE status = 'PENDING'
        AND confidence >= 0.9
        AND risk_level = 'LOW'
        AND recommendation_type = 'DELETE'
    LOOP
        BEGIN
            PERFORM pggit.apply_pruning_recommendation(rec.id);
            v_space_freed := v_space_freed + rec.space_savings_bytes;
        EXCEPTION WHEN OTHERS THEN
            -- Log error but continue
            RAISE WARNING 'Failed to apply recommendation %: %', rec.id, SQLERRM;
        END;
    END LOOP;
    
    -- Clean unreferenced blobs
    SELECT COUNT(*) INTO v_blobs_cleaned
    FROM pggit.cleanup_unreferenced_blobs(30);
    
    RETURN format('Maintenance complete: %s recommendations generated, %s MB freed, %s blobs cleaned',
                  v_recommendations_count,
                  ROUND(v_space_freed::DECIMAL / 1024 / 1024, 2),
                  v_blobs_cleaned);
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Helper Functions
-- =====================================================

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_branch_size_metrics_branch_name 
ON pggit.branch_size_metrics(branch_name);

CREATE INDEX IF NOT EXISTS idx_branch_size_metrics_total_size 
ON pggit.branch_size_metrics(total_size_bytes DESC);

CREATE INDEX IF NOT EXISTS idx_pruning_recommendations_status 
ON pggit.pruning_recommendations(status, priority DESC);

-- Add helpful comments
COMMENT ON TABLE pggit.branch_size_metrics IS 'Tracks size metrics for each branch';
COMMENT ON TABLE pggit.pruning_recommendations IS 'AI-generated recommendations for branch pruning';
COMMENT ON FUNCTION pggit.generate_pruning_recommendations IS 'Generates intelligent pruning recommendations based on branch activity and size';
COMMENT ON FUNCTION pggit.run_size_maintenance IS 'Daily maintenance task to manage database size';

-- Success message
DO $$
BEGIN
    RAISE NOTICE 'pggit Size Management & Pruning system installed successfully!';
    RAISE NOTICE 'Run SELECT * FROM pggit.generate_pruning_recommendations(); to get pruning suggestions';
    RAISE NOTICE 'View database size with: SELECT * FROM pggit.database_size_overview;';
END $$;