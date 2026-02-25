-- Utility views and functions for querying version information

-- View showing all active objects with their versions
CREATE OR REPLACE VIEW pggit.object_versions AS
SELECT 
    o.object_type,
    o.full_name,
    o.version,
    o.version_major || '.' || o.version_minor || '.' || o.version_patch AS version_string,
    o.parent_id,
    p.full_name AS parent_name,
    o.metadata,
    o.created_at,
    o.updated_at
FROM pggit.objects o
LEFT JOIN pggit.objects p ON o.parent_id = p.id
WHERE o.is_active = true
ORDER BY o.object_type, o.full_name;

-- View showing recent changes
CREATE OR REPLACE VIEW pggit.recent_changes AS
SELECT 
    o.object_type,
    o.full_name AS object_name,
    h.change_type,
    h.change_severity,
    h.old_version,
    h.new_version,
    h.change_description,
    h.created_at,
    h.created_by
FROM pggit.history h
JOIN pggit.objects o ON h.object_id = o.id
ORDER BY h.created_at DESC
LIMIT 100;

-- View showing object dependencies
CREATE OR REPLACE VIEW pggit.dependency_graph AS
SELECT 
    dependent.object_type AS dependent_type,
    dependent.full_name AS dependent_name,
    depends_on.object_type AS depends_on_type,
    depends_on.full_name AS depends_on_name,
    d.dependency_type,
    d.metadata
FROM pggit.dependencies d
JOIN pggit.objects dependent ON d.dependent_id = dependent.id
JOIN pggit.objects depends_on ON d.depends_on_id = depends_on.id
WHERE dependent.is_active = true
AND depends_on.is_active = true
ORDER BY dependent.full_name, depends_on.full_name;

-- Function to get impact analysis for an object
-- Returns columns matching the user journey test expectations
CREATE OR REPLACE FUNCTION pggit.get_impact_analysis(
    p_object_name TEXT
) RETURNS TABLE (
    level INTEGER,
    object_type pggit.object_type,
    dependent_object TEXT,
    dependency_type TEXT,
    impact_description TEXT
) AS $$
WITH RECURSIVE impact_tree AS (
    -- Base case: direct dependents
    SELECT
        1 AS level,
        o.id,
        o.object_type,
        o.full_name,
        d.dependency_type,
        'Direct dependency' AS impact_description
    FROM pggit.objects o
    JOIN pggit.dependencies d ON d.dependent_id = o.id
    JOIN pggit.objects base ON d.depends_on_id = base.id
    WHERE base.full_name = p_object_name
    AND base.is_active = true
    AND o.is_active = true

    UNION ALL

    -- Recursive case: indirect dependents
    SELECT
        it.level + 1,
        o.id,
        o.object_type,
        o.full_name,
        d.dependency_type,
        'Indirect dependency (level ' || (it.level + 1) || ')' AS impact_description
    FROM impact_tree it
    JOIN pggit.dependencies d ON d.depends_on_id = it.id
    JOIN pggit.objects o ON d.dependent_id = o.id
    WHERE o.is_active = true
    AND it.level < 5  -- Limit recursion depth
)
SELECT DISTINCT
    level,
    object_type,
    full_name AS dependent_object,
    dependency_type,
    impact_description
FROM impact_tree
ORDER BY level, object_type, dependent_object;
$$ LANGUAGE sql;

-- Function to generate a version report for a schema
CREATE OR REPLACE FUNCTION pggit.generate_version_report(
    p_schema_name TEXT DEFAULT 'public'
) RETURNS TABLE (
    report_section TEXT,
    report_data JSONB
) AS $$
BEGIN
    -- Summary section
    RETURN QUERY
    SELECT 
        'summary',
        jsonb_build_object(
            'total_objects', COUNT(*),
            'tables', COUNT(*) FILTER (WHERE object_type = 'TABLE'),
            'views', COUNT(*) FILTER (WHERE object_type = 'VIEW'),
            'functions', COUNT(*) FILTER (WHERE object_type = 'FUNCTION'),
            'last_change', MAX(updated_at)
        )
    FROM pggit.objects
    WHERE schema_name = p_schema_name
    AND is_active = true;
    
    -- Version distribution
    RETURN QUERY
    WITH version_stats AS (
        SELECT 
            object_type::text as type_name,
            AVG(version) as avg_ver,
            MAX(version) as max_ver,
            SUM(version - 1) as total_changes
        FROM pggit.objects
        WHERE schema_name = p_schema_name
        AND is_active = true
        GROUP BY object_type
    )
    SELECT 
        'version_distribution',
        jsonb_object_agg(
            type_name,
            jsonb_build_object(
                'avg_version', avg_ver,
                'max_version', max_ver,
                'total_changes', total_changes
            )
        )
    FROM version_stats;
    
    -- Recent changes
    RETURN QUERY
    SELECT 
        'recent_changes',
        jsonb_agg(
            jsonb_build_object(
                'object', o.full_name,
                'change_type', h.change_type,
                'severity', h.change_severity,
                'description', h.change_description,
                'timestamp', h.created_at
            ) ORDER BY h.created_at DESC
        )
    FROM pggit.history h
    JOIN pggit.objects o ON h.object_id = o.id
    WHERE o.schema_name = p_schema_name
    AND h.created_at > CURRENT_TIMESTAMP - INTERVAL '7 days'
    LIMIT 20;
    
    -- High-change objects (potential hotspots)
    RETURN QUERY
    SELECT 
        'high_change_objects',
        jsonb_agg(
            jsonb_build_object(
                'object', full_name,
                'type', object_type,
                'version', version,
                'changes_per_day', 
                    ROUND((version - 1)::numeric / 
                    GREATEST(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - created_at)) / 86400, 1), 2)
            ) ORDER BY version DESC
        )
    FROM pggit.objects
    WHERE schema_name = p_schema_name
    AND is_active = true
    AND version > 5
    LIMIT 10;
END;
$$ LANGUAGE plpgsql;

-- Function to check version compatibility between objects
CREATE OR REPLACE FUNCTION pggit.check_compatibility(
    p_object1 TEXT,
    p_object2 TEXT
) RETURNS TABLE (
    compatible BOOLEAN,
    reason TEXT,
    recommendations TEXT[]
) AS $$
DECLARE
    v_obj1 RECORD;
    v_obj2 RECORD;
    v_recommendations TEXT[];
BEGIN
    -- Get object information
    SELECT * INTO v_obj1
    FROM pggit.objects
    WHERE full_name = p_object1 AND is_active = true;
    
    SELECT * INTO v_obj2
    FROM pggit.objects
    WHERE full_name = p_object2 AND is_active = true;
    
    -- Check if objects exist
    IF v_obj1 IS NULL OR v_obj2 IS NULL THEN
        RETURN QUERY
        SELECT 
            FALSE,
            'One or both objects not found in version tracking',
            ARRAY['Ensure both objects are being tracked']::TEXT[];
        RETURN;
    END IF;
    
    -- Check for dependency relationship
    IF EXISTS (
        SELECT 1 FROM pggit.dependencies
        WHERE (dependent_id = v_obj1.id AND depends_on_id = v_obj2.id)
           OR (dependent_id = v_obj2.id AND depends_on_id = v_obj1.id)
    ) THEN
        -- Check version compatibility
        IF v_obj1.version_major != v_obj2.version_major THEN
            v_recommendations := array_append(v_recommendations, 
                'Major version mismatch - review breaking changes');
        END IF;
        
        RETURN QUERY
        SELECT 
            v_obj1.version_major = v_obj2.version_major,
            CASE 
                WHEN v_obj1.version_major = v_obj2.version_major 
                THEN 'Objects are compatible (same major version)'
                ELSE 'Potential incompatibility due to major version difference'
            END,
            v_recommendations;
    ELSE
        RETURN QUERY
        SELECT 
            TRUE,
            'No direct dependency relationship found',
            ARRAY['Objects appear to be independent']::TEXT[];
    END IF;
END;
$$ LANGUAGE plpgsql;

-- View showing version information for all schemas
CREATE OR REPLACE VIEW pggit.schema_versions AS
SELECT
    schema_name,
    object_type,
    object_name,
    version,
    version_major || '.' || version_minor || '.' || version_patch AS version_string,
    created_at,
    updated_at
FROM pggit.objects
WHERE is_active = true
ORDER BY schema_name, object_type, object_name;

-- Convenience function to show version for all tables
CREATE OR REPLACE FUNCTION pggit.show_table_versions(
    p_schema_name TEXT DEFAULT 'public'
) RETURNS TABLE (
    object_name TEXT,
    schema_name TEXT,
    version_string TEXT,
    last_change TIMESTAMP,
    column_count BIGINT
) AS $$
SELECT
    object_name,
    schema_name,
    version_major || '.' || version_minor || '.' || version_patch AS version_string,
    updated_at AS last_change,
    COALESCE((SELECT COUNT(*) FROM jsonb_object_keys(metadata->'columns')), 0) AS column_count
FROM pggit.objects
WHERE object_type = 'TABLE'
AND schema_name = p_schema_name
AND is_active = true
ORDER BY object_name;
$$ LANGUAGE sql;