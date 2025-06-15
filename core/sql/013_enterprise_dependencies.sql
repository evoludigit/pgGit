-- Enterprise Dependency Resolution System
-- Handles complex real-world schema dependencies

-- ============================================
-- PART 1: Advanced Dependency Modeling
-- ============================================

-- Dependency relationship types
CREATE TYPE pggit.dependency_type AS ENUM (
    'FOREIGN_KEY',           -- Table FK references
    'VIEW_TABLE',            -- View depends on table
    'VIEW_VIEW',             -- View depends on view
    'FUNCTION_TABLE',        -- Function references table
    'FUNCTION_VIEW',         -- Function references view
    'FUNCTION_FUNCTION',     -- Function calls function
    'TRIGGER_FUNCTION',      -- Trigger uses function
    'CONSTRAINT_FUNCTION',   -- CHECK constraint uses function
    'INDEX_FUNCTION',        -- Functional index uses function
    'TYPE_DEPENDENCY',       -- Custom type dependencies
    'INHERITANCE',           -- Table inheritance
    'PARTITION',             -- Partition relationships
    'SEQUENCE_OWNERSHIP',    -- Sequence owned by column
    'GRANT_DEPENDENCY',      -- Permission dependencies
    'EXTENSION_DEPENDENCY',  -- Extension dependencies
    'SCHEMA_DEPENDENCY',     -- Cross-schema references
    'POLICY_DEPENDENCY',     -- RLS policy dependencies
    'PUBLICATION_DEPENDENCY' -- Logical replication dependencies
);

-- Comprehensive dependency tracking
CREATE TABLE IF NOT EXISTS pggit.object_dependencies (
    id SERIAL PRIMARY KEY,
    dependent_object_type pggit.pg_object_type NOT NULL,
    dependent_object_schema TEXT NOT NULL,
    dependent_object_name TEXT NOT NULL,
    depends_on_object_type pggit.pg_object_type NOT NULL,
    depends_on_object_schema TEXT NOT NULL,
    depends_on_object_name TEXT NOT NULL,
    dependency_type pggit.dependency_type NOT NULL,
    dependency_strength INTEGER DEFAULT 100, -- Higher = more critical
    is_direct BOOLEAN DEFAULT true,
    cascade_behavior TEXT, -- CASCADE, RESTRICT, SET NULL, etc.
    dependency_details JSONB,
    discovered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    commit_id UUID REFERENCES pggit.commits(id),
    UNIQUE(dependent_object_schema, dependent_object_name, depends_on_object_schema, depends_on_object_name, dependency_type)
);

-- Optimized indexes for dependency queries
CREATE INDEX idx_obj_deps_dependent ON pggit.object_dependencies(dependent_object_schema, dependent_object_name);
CREATE INDEX idx_obj_deps_depends_on ON pggit.object_dependencies(depends_on_object_schema, depends_on_object_name);
CREATE INDEX idx_obj_deps_type ON pggit.object_dependencies(dependency_type);
CREATE INDEX idx_obj_deps_strength ON pggit.object_dependencies(dependency_strength DESC);

-- ============================================
-- PART 2: Enterprise Schema Discovery
-- ============================================

-- Discover all dependencies in a schema (real enterprise complexity)
CREATE OR REPLACE FUNCTION pggit.discover_schema_dependencies(
    p_schema_name TEXT DEFAULT 'public'
) RETURNS TABLE (
    dependency_count INTEGER,
    dependency_type pggit.dependency_type,
    complexity_score INTEGER
) AS $$
DECLARE
    v_total_dependencies INTEGER := 0;
BEGIN
    -- Clear existing dependencies for schema
    DELETE FROM pggit.object_dependencies 
    WHERE dependent_object_schema = p_schema_name;
    
    -- Discover Foreign Key Dependencies
    INSERT INTO pggit.object_dependencies (
        dependent_object_type, dependent_object_schema, dependent_object_name,
        depends_on_object_type, depends_on_object_schema, depends_on_object_name,
        dependency_type, dependency_strength, cascade_behavior, dependency_details
    )
    SELECT 
        'TABLE', 
        tc.table_schema,
        tc.table_name,
        'TABLE',
        ccu.table_schema,
        ccu.table_name,
        'FOREIGN_KEY',
        200, -- High strength
        rc.delete_rule,
        jsonb_build_object(
            'constraint_name', tc.constraint_name,
            'column_name', kcu.column_name,
            'referenced_column', ccu.column_name,
            'update_rule', rc.update_rule,
            'delete_rule', rc.delete_rule
        )
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name
    JOIN information_schema.referential_constraints rc ON rc.constraint_name = tc.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema = p_schema_name;
    
    -- Discover View Dependencies
    INSERT INTO pggit.object_dependencies (
        dependent_object_type, dependent_object_schema, dependent_object_name,
        depends_on_object_type, depends_on_object_schema, depends_on_object_name,
        dependency_type, dependency_strength, dependency_details
    )
    SELECT DISTINCT
        'VIEW',
        v.table_schema,
        v.table_name,
        CASE 
            WHEN t.table_type = 'VIEW' THEN 'VIEW'
            ELSE 'TABLE'
        END,
        vtu.table_schema,
        vtu.table_name,
        CASE 
            WHEN t.table_type = 'VIEW' THEN 'VIEW_VIEW'
            ELSE 'VIEW_TABLE'
        END,
        150,
        jsonb_build_object(
            'view_definition', v.view_definition
        )
    FROM information_schema.views v
    CROSS JOIN LATERAL (
        SELECT DISTINCT
            (regexp_matches(v.view_definition, '\b([a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_]*)\b', 'g'))[1] as full_name
    ) refs
    CROSS JOIN LATERAL (
        SELECT 
            split_part(refs.full_name, '.', 1) as table_schema,
            split_part(refs.full_name, '.', 2) as table_name
    ) vtu
    LEFT JOIN information_schema.tables t ON t.table_schema = vtu.table_schema AND t.table_name = vtu.table_name
    WHERE v.table_schema = p_schema_name
    AND t.table_name IS NOT NULL;
    
    -- Discover Function Dependencies
    INSERT INTO pggit.object_dependencies (
        dependent_object_type, dependent_object_schema, dependent_object_name,
        depends_on_object_type, depends_on_object_schema, depends_on_object_name,
        dependency_type, dependency_strength, dependency_details
    )
    SELECT DISTINCT
        'FUNCTION',
        r.routine_schema,
        r.routine_name,
        'TABLE',
        ft.table_schema,
        ft.table_name,
        'FUNCTION_TABLE',
        100,
        jsonb_build_object(
            'function_definition', r.routine_definition,
            'language', r.external_language
        )
    FROM information_schema.routines r
    CROSS JOIN LATERAL (
        SELECT DISTINCT
            (regexp_matches(r.routine_definition, '\b([a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_]*)\b', 'g'))[1] as full_name
    ) refs
    CROSS JOIN LATERAL (
        SELECT 
            split_part(refs.full_name, '.', 1) as table_schema,
            split_part(refs.full_name, '.', 2) as table_name
    ) ft
    WHERE r.routine_schema = p_schema_name
    AND EXISTS (
        SELECT 1 FROM information_schema.tables t 
        WHERE t.table_schema = ft.table_schema AND t.table_name = ft.table_name
    );
    
    -- Discover Trigger Dependencies
    INSERT INTO pggit.object_dependencies (
        dependent_object_type, dependent_object_schema, dependent_object_name,
        depends_on_object_type, depends_on_object_schema, depends_on_object_name,
        dependency_type, dependency_strength, dependency_details
    )
    SELECT 
        'TRIGGER',
        t.trigger_schema,
        t.trigger_name,
        'FUNCTION',
        t.action_statement_schema,
        regexp_replace(t.action_statement, '^EXECUTE (?:PROCEDURE|FUNCTION) ([^(]+).*', '\1'),
        'TRIGGER_FUNCTION',
        180,
        jsonb_build_object(
            'event_manipulation', t.event_manipulation,
            'action_timing', t.action_timing,
            'action_statement', t.action_statement
        )
    FROM information_schema.triggers t
    WHERE t.trigger_schema = p_schema_name;
    
    -- Discover Index Dependencies (functional indexes)
    INSERT INTO pggit.object_dependencies (
        dependent_object_type, dependent_object_schema, dependent_object_name,
        depends_on_object_type, depends_on_object_schema, depends_on_object_name,
        dependency_type, dependency_strength, dependency_details
    )
    SELECT DISTINCT
        'INDEX',
        i.schemaname,
        i.indexname,
        'FUNCTION',
        p.pronamespace::regnamespace::text,
        p.proname,
        'INDEX_FUNCTION',
        120,
        jsonb_build_object(
            'index_definition', i.indexdef
        )
    FROM pg_indexes i
    JOIN pg_class c ON c.relname = i.indexname
    JOIN pg_index idx ON idx.indexrelid = c.oid
    JOIN pg_proc p ON p.oid = ANY(idx.indexprs::text::oid[])
    WHERE i.schemaname = p_schema_name;
    
    -- Discover Inheritance Dependencies
    INSERT INTO pggit.object_dependencies (
        dependent_object_type, dependent_object_schema, dependent_object_name,
        depends_on_object_type, depends_on_object_schema, depends_on_object_name,
        dependency_type, dependency_strength, dependency_details
    )
    SELECT 
        'TABLE',
        child_ns.nspname,
        child_class.relname,
        'TABLE',
        parent_ns.nspname,
        parent_class.relname,
        'INHERITANCE',
        250, -- Very high strength
        jsonb_build_object(
            'inheritance_type', 'table_inheritance'
        )
    FROM pg_inherits i
    JOIN pg_class child_class ON child_class.oid = i.inhrelid
    JOIN pg_namespace child_ns ON child_ns.oid = child_class.relnamespace
    JOIN pg_class parent_class ON parent_class.oid = i.inhparent
    JOIN pg_namespace parent_ns ON parent_ns.oid = parent_class.relnamespace
    WHERE child_ns.nspname = p_schema_name;
    
    -- Discover Sequence Ownership
    INSERT INTO pggit.object_dependencies (
        dependent_object_type, dependent_object_schema, dependent_object_name,
        depends_on_object_type, depends_on_object_schema, depends_on_object_name,
        dependency_type, dependency_strength, dependency_details
    )
    SELECT 
        'SEQUENCE',
        seq_ns.nspname,
        seq_class.relname,
        'TABLE',
        tbl_ns.nspname,
        tbl_class.relname,
        'SEQUENCE_OWNERSHIP',
        190,
        jsonb_build_object(
            'column_name', a.attname,
            'column_number', a.attnum
        )
    FROM pg_depend d
    JOIN pg_class seq_class ON seq_class.oid = d.objid
    JOIN pg_namespace seq_ns ON seq_ns.oid = seq_class.relnamespace
    JOIN pg_class tbl_class ON tbl_class.oid = d.refobjid
    JOIN pg_namespace tbl_ns ON tbl_ns.oid = tbl_class.relnamespace
    JOIN pg_attribute a ON a.attrelid = d.refobjid AND a.attnum = d.refobjsubid
    WHERE d.classid = 'pg_class'::regclass
    AND d.refclassid = 'pg_class'::regclass
    AND d.deptype = 'a'
    AND seq_class.relkind = 'S'
    AND seq_ns.nspname = p_schema_name;
    
    -- Return summary
    RETURN QUERY
    SELECT 
        COUNT(*)::INTEGER,
        od.dependency_type,
        CASE od.dependency_type
            WHEN 'FOREIGN_KEY' THEN COUNT(*) * 2
            WHEN 'INHERITANCE' THEN COUNT(*) * 3
            WHEN 'VIEW_VIEW' THEN COUNT(*) * 2
            ELSE COUNT(*)::INTEGER
        END as complexity_score
    FROM pggit.object_dependencies od
    WHERE od.dependent_object_schema = p_schema_name
    GROUP BY od.dependency_type
    ORDER BY complexity_score DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 3: Dependency Impact Analysis
-- ============================================

-- Analyze impact of changing/dropping an object
CREATE OR REPLACE FUNCTION pggit.analyze_dependency_impact(
    p_object_schema TEXT,
    p_object_name TEXT,
    p_operation TEXT DEFAULT 'DROP' -- DROP, ALTER, RENAME
) RETURNS TABLE (
    impact_level TEXT,
    affected_object_type pggit.pg_object_type,
    affected_object_schema TEXT,
    affected_object_name TEXT,
    dependency_path TEXT[],
    risk_assessment TEXT,
    suggested_action TEXT
) AS $$
DECLARE
    v_max_depth INTEGER := 10;
BEGIN
    RETURN QUERY
    WITH RECURSIVE dependency_tree AS (
        -- Direct dependencies
        SELECT 
            1 as depth,
            od.dependent_object_type,
            od.dependent_object_schema,
            od.dependent_object_name,
            od.dependency_type,
            od.dependency_strength,
            ARRAY[p_object_schema || '.' || p_object_name, 
                  od.dependent_object_schema || '.' || od.dependent_object_name] as path
        FROM pggit.object_dependencies od
        WHERE od.depends_on_object_schema = p_object_schema
        AND od.depends_on_object_name = p_object_name
        
        UNION ALL
        
        -- Indirect dependencies (recursive)
        SELECT 
            dt.depth + 1,
            od.dependent_object_type,
            od.dependent_object_schema,
            od.dependent_object_name,
            od.dependency_type,
            od.dependency_strength,
            dt.path || (od.dependent_object_schema || '.' || od.dependent_object_name)
        FROM dependency_tree dt
        JOIN pggit.object_dependencies od 
            ON od.depends_on_object_schema = dt.dependent_object_schema
            AND od.depends_on_object_name = dt.dependent_object_name
        WHERE dt.depth < v_max_depth
        AND NOT (od.dependent_object_schema || '.' || od.dependent_object_name) = ANY(dt.path) -- Prevent cycles
    ),
    impact_analysis AS (
        SELECT 
            dt.*,
            CASE 
                WHEN dt.depth = 1 THEN 'DIRECT'
                WHEN dt.depth <= 3 THEN 'INDIRECT'
                ELSE 'DEEP'
            END as impact_level,
            CASE 
                WHEN dt.dependency_strength >= 200 THEN 'HIGH'
                WHEN dt.dependency_strength >= 150 THEN 'MEDIUM'
                ELSE 'LOW'
            END as risk_level
        FROM dependency_tree dt
    )
    SELECT 
        ia.impact_level,
        ia.dependent_object_type,
        ia.dependent_object_schema,
        ia.dependent_object_name,
        ia.path,
        ia.risk_level || ' - ' || 
        CASE ia.dependency_type
            WHEN 'FOREIGN_KEY' THEN 'Data integrity constraint'
            WHEN 'VIEW_TABLE' THEN 'View will become invalid'
            WHEN 'FUNCTION_TABLE' THEN 'Function may fail'
            WHEN 'TRIGGER_FUNCTION' THEN 'Trigger will be dropped'
            WHEN 'INHERITANCE' THEN 'Child table structure affected'
            ELSE 'Dependency relationship'
        END as risk_assessment,
        CASE 
            WHEN p_operation = 'DROP' AND ia.dependency_type = 'FOREIGN_KEY' THEN 'Drop FK constraint first or use CASCADE'
            WHEN p_operation = 'DROP' AND ia.dependency_type = 'VIEW_TABLE' THEN 'Drop dependent views first or use CASCADE'
            WHEN p_operation = 'ALTER' AND ia.dependency_type = 'VIEW_TABLE' THEN 'Verify view compatibility after change'
            WHEN p_operation = 'RENAME' THEN 'Update references in dependent objects'
            ELSE 'Manual review required'
        END as suggested_action
    FROM impact_analysis ia
    ORDER BY 
        CASE ia.impact_level 
            WHEN 'DIRECT' THEN 1 
            WHEN 'INDIRECT' THEN 2 
            ELSE 3 
        END,
        ia.dependency_strength DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 4: Safe Dependency Order Resolution
-- ============================================

-- Generate safe order for creating/dropping objects
CREATE OR REPLACE FUNCTION pggit.calculate_dependency_order(
    p_schema_name TEXT,
    p_operation TEXT DEFAULT 'CREATE' -- CREATE or DROP
) RETURNS TABLE (
    execution_order INTEGER,
    object_type pggit.pg_object_type,
    object_schema TEXT,
    object_name TEXT,
    depends_on_count INTEGER,
    dependents_count INTEGER,
    complexity_score INTEGER
) AS $$
DECLARE
    v_object RECORD;
    v_order INTEGER := 1;
    v_processed TEXT[] := ARRAY[]::TEXT[];
    v_remaining_objects TEXT[];
    v_full_name TEXT;
    v_can_process BOOLEAN;
BEGIN
    -- Get all objects in schema
    CREATE TEMP TABLE temp_objects AS
    WITH all_objects AS (
        -- Tables
        SELECT 'TABLE'::pggit.pg_object_type as object_type, 
               table_schema as object_schema, 
               table_name as object_name
        FROM information_schema.tables 
        WHERE table_schema = p_schema_name
        AND table_type = 'BASE TABLE'
        
        UNION ALL
        
        -- Views
        SELECT 'VIEW'::pggit.pg_object_type, 
               table_schema, 
               table_name
        FROM information_schema.views 
        WHERE table_schema = p_schema_name
        
        UNION ALL
        
        -- Functions
        SELECT 'FUNCTION'::pggit.pg_object_type, 
               routine_schema, 
               routine_name
        FROM information_schema.routines 
        WHERE routine_schema = p_schema_name
        AND routine_type = 'FUNCTION'
        
        UNION ALL
        
        -- Sequences
        SELECT 'SEQUENCE'::pggit.pg_object_type,
               sequence_schema,
               sequence_name
        FROM information_schema.sequences
        WHERE sequence_schema = p_schema_name
    )
    SELECT 
        ao.*,
        COALESCE(dep_count.depends_on, 0) as depends_on_count,
        COALESCE(dependent_count.dependents, 0) as dependents_count,
        (COALESCE(dep_count.depends_on, 0) + COALESCE(dependent_count.dependents, 0)) as complexity_score,
        0 as execution_order
    FROM all_objects ao
    LEFT JOIN (
        SELECT 
            dependent_object_schema,
            dependent_object_name,
            COUNT(*) as depends_on
        FROM pggit.object_dependencies
        WHERE dependent_object_schema = p_schema_name
        GROUP BY dependent_object_schema, dependent_object_name
    ) dep_count ON dep_count.dependent_object_schema = ao.object_schema 
                AND dep_count.dependent_object_name = ao.object_name
    LEFT JOIN (
        SELECT 
            depends_on_object_schema,
            depends_on_object_name,
            COUNT(*) as dependents
        FROM pggit.object_dependencies
        WHERE depends_on_object_schema = p_schema_name
        GROUP BY depends_on_object_schema, depends_on_object_name
    ) dependent_count ON dependent_count.depends_on_object_schema = ao.object_schema 
                      AND dependent_count.depends_on_object_name = ao.object_name;
    
    -- Topological sort for dependency order
    WHILE EXISTS (SELECT 1 FROM temp_objects WHERE execution_order = 0) LOOP
        -- Find objects that can be processed (no unprocessed dependencies)
        FOR v_object IN
            SELECT *
            FROM temp_objects
            WHERE execution_order = 0
            ORDER BY 
                CASE p_operation
                    WHEN 'CREATE' THEN depends_on_count ASC  -- Process dependencies first
                    WHEN 'DROP' THEN dependents_count ASC    -- Process dependents first
                END,
                complexity_score ASC
        LOOP
            v_full_name := v_object.object_schema || '.' || v_object.object_name;
            v_can_process := true;
            
            -- Check if all dependencies are already processed
            IF p_operation = 'CREATE' THEN
                -- For CREATE: check if all objects this depends on are already processed
                SELECT EXISTS (
                    SELECT 1 
                    FROM pggit.object_dependencies od
                    WHERE od.dependent_object_schema = v_object.object_schema
                    AND od.dependent_object_name = v_object.object_name
                    AND NOT (od.depends_on_object_schema || '.' || od.depends_on_object_name) = ANY(v_processed)
                ) INTO v_can_process;
                v_can_process := NOT v_can_process;
            ELSE
                -- For DROP: check if all objects that depend on this are already processed
                SELECT EXISTS (
                    SELECT 1 
                    FROM pggit.object_dependencies od
                    WHERE od.depends_on_object_schema = v_object.object_schema
                    AND od.depends_on_object_name = v_object.object_name
                    AND NOT (od.dependent_object_schema || '.' || od.dependent_object_name) = ANY(v_processed)
                ) INTO v_can_process;
                v_can_process := NOT v_can_process;
            END IF;
            
            IF v_can_process THEN
                -- Process this object
                UPDATE temp_objects 
                SET execution_order = v_order
                WHERE object_schema = v_object.object_schema 
                AND object_name = v_object.object_name;
                
                v_processed := v_processed || v_full_name;
                v_order := v_order + 1;
                
                EXIT; -- Process next iteration
            END IF;
        END LOOP;
        
        -- Safety check to prevent infinite loops
        IF NOT FOUND THEN
            -- Circular dependency detected - process remaining objects in complexity order
            UPDATE temp_objects 
            SET execution_order = v_order + row_number() OVER (ORDER BY complexity_score ASC)
            WHERE execution_order = 0;
            EXIT;
        END IF;
    END LOOP;
    
    -- Return results
    RETURN QUERY
    SELECT 
        t.execution_order,
        t.object_type,
        t.object_schema,
        t.object_name,
        t.depends_on_count,
        t.dependents_count,
        t.complexity_score
    FROM temp_objects t
    ORDER BY t.execution_order;
    
    DROP TABLE temp_objects;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- PART 5: Enterprise Schema Validation
-- ============================================

-- Validate schema for complex enterprise patterns
CREATE OR REPLACE FUNCTION pggit.validate_enterprise_schema(
    p_schema_name TEXT
) RETURNS TABLE (
    validation_type TEXT,
    severity TEXT,
    object_name TEXT,
    issue_description TEXT,
    remediation_suggestion TEXT
) AS $$
BEGIN
    -- Check for circular dependencies
    RETURN QUERY
    WITH circular_deps AS (
        SELECT DISTINCT
            od1.dependent_object_schema || '.' || od1.dependent_object_name as object1,
            od1.depends_on_object_schema || '.' || od1.depends_on_object_name as object2
        FROM pggit.object_dependencies od1
        JOIN pggit.object_dependencies od2 
            ON od1.depends_on_object_schema = od2.dependent_object_schema
            AND od1.depends_on_object_name = od2.dependent_object_name
            AND od1.dependent_object_schema = od2.depends_on_object_schema
            AND od1.dependent_object_name = od2.depends_on_object_name
        WHERE od1.dependent_object_schema = p_schema_name
    )
    SELECT 
        'CIRCULAR_DEPENDENCY'::TEXT,
        'ERROR'::TEXT,
        cd.object1,
        'Circular dependency detected between ' || cd.object1 || ' and ' || cd.object2,
        'Review and break circular dependency by restructuring relationships'
    FROM circular_deps cd;
    
    -- Check for complex inheritance chains
    RETURN QUERY
    WITH inheritance_depth AS (
        SELECT 
            dependent_object_name,
            COUNT(*) as inheritance_levels
        FROM pggit.object_dependencies
        WHERE dependency_type = 'INHERITANCE'
        AND dependent_object_schema = p_schema_name
        GROUP BY dependent_object_name
        HAVING COUNT(*) > 3
    )
    SELECT 
        'DEEP_INHERITANCE'::TEXT,
        'WARNING'::TEXT,
        id.dependent_object_name,
        'Table has ' || id.inheritance_levels || ' levels of inheritance',
        'Consider flattening inheritance hierarchy for better performance'
    FROM inheritance_depth id;
    
    -- Check for excessive foreign key relationships
    RETURN QUERY
    WITH fk_complexity AS (
        SELECT 
            depends_on_object_name,
            COUNT(*) as incoming_fks
        FROM pggit.object_dependencies
        WHERE dependency_type = 'FOREIGN_KEY'
        AND depends_on_object_schema = p_schema_name
        GROUP BY depends_on_object_name
        HAVING COUNT(*) > 10
    )
    SELECT 
        'HIGH_FK_COMPLEXITY'::TEXT,
        'WARNING'::TEXT,
        fk.depends_on_object_name,
        'Table has ' || fk.incoming_fks || ' foreign key references',
        'Consider normalizing or partitioning highly referenced tables'
    FROM fk_complexity fk;
    
    -- Check for view chains
    RETURN QUERY
    WITH view_chains AS (
        SELECT 
            dependent_object_name,
            COUNT(*) as view_depth
        FROM pggit.object_dependencies
        WHERE dependency_type = 'VIEW_VIEW'
        AND dependent_object_schema = p_schema_name
        GROUP BY dependent_object_name
        HAVING COUNT(*) > 5
    )
    SELECT 
        'DEEP_VIEW_CHAIN'::TEXT,
        'WARNING'::TEXT,
        vc.dependent_object_name,
        'View depends on ' || vc.view_depth || ' other views',
        'Consider materializing intermediate results for better performance'
    FROM view_chains vc;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit.discover_schema_dependencies IS 'Discover all dependency relationships in enterprise schema';
COMMENT ON FUNCTION pggit.analyze_dependency_impact IS 'Analyze impact of changes with recursive dependency traversal';
COMMENT ON FUNCTION pggit.calculate_dependency_order IS 'Calculate safe execution order for schema operations';
COMMENT ON FUNCTION pggit.validate_enterprise_schema IS 'Validate schema for enterprise complexity patterns';