-- pgGit CQRS Architecture Support
-- Enables tracking of Command Query Responsibility Segregation patterns

-- Type for CQRS changes
CREATE TYPE pggit.cqrs_change AS (
    command_operations text[],
    query_operations text[],
    description text,
    version text
);

-- Table to track CQRS change sets
CREATE TABLE IF NOT EXISTS pggit.cqrs_changesets (
    changeset_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    description text NOT NULL,
    version text,
    command_operations text[],
    query_operations text[],
    status text DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'failed')),
    created_at timestamptz DEFAULT now(),
    created_by text DEFAULT current_user,
    completed_at timestamptz,
    commit_id uuid, -- Foreign key removed: pggit.commits may not have commit_id column
    error_message text
);

-- Track individual operations within a CQRS changeset
CREATE TABLE IF NOT EXISTS pggit.cqrs_operations (
    operation_id serial PRIMARY KEY,
    changeset_id uuid REFERENCES pggit.cqrs_changesets(changeset_id),
    side text NOT NULL CHECK (side IN ('command', 'query')),
    operation_sql text NOT NULL,
    operation_order integer NOT NULL,
    executed_at timestamptz,
    success boolean,
    error_message text
);

-- Function to track CQRS changes
CREATE OR REPLACE FUNCTION pggit.track_cqrs_change(
    change pggit.cqrs_change,
    atomic boolean DEFAULT true
) RETURNS uuid AS $$
DECLARE
    changeset_id uuid;
    operation text;
    operation_order integer := 0;
    current_deployment_id uuid;
BEGIN
    -- Create new changeset
    INSERT INTO pggit.cqrs_changesets (
        description,
        version,
        command_operations,
        query_operations
    ) VALUES (
        change.description,
        change.version,
        change.command_operations,
        change.query_operations
    ) RETURNING pggit.cqrs_changesets.changeset_id INTO changeset_id;
    
    -- Add command operations
    IF change.command_operations IS NOT NULL THEN
        FOREACH operation IN ARRAY change.command_operations
        LOOP
            operation_order := operation_order + 1;
            INSERT INTO pggit.cqrs_operations (
                changeset_id,
                side,
                operation_sql,
                operation_order
            ) VALUES (
                changeset_id,
                'command',
                operation,
                operation_order
            );
        END LOOP;
    END IF;
    
    -- Add query operations
    IF change.query_operations IS NOT NULL THEN
        FOREACH operation IN ARRAY change.query_operations
        LOOP
            operation_order := operation_order + 1;
            INSERT INTO pggit.cqrs_operations (
                changeset_id,
                side,
                operation_sql,
                operation_order
            ) VALUES (
                changeset_id,
                'query',
                operation,
                operation_order
            );
        END LOOP;
    END IF;
    
    -- If in deployment mode, link to current deployment
    SELECT ds.current_deployment_id INTO current_deployment_id 
    FROM pggit.deployment_state ds
    WHERE ds.is_active = true;
    
    IF current_deployment_id IS NOT NULL THEN
        -- Increment deployment changes count
        UPDATE pggit.deployment_mode 
        SET changes_count = changes_count + 1
        WHERE deployment_id = current_deployment_id;
    END IF;
    
    -- Execute the changeset if atomic is true
    IF atomic THEN
        PERFORM pggit.execute_cqrs_changeset(changeset_id);
    END IF;
    
    RETURN changeset_id;
END;
$$ LANGUAGE plpgsql;

-- Function to execute a CQRS changeset
CREATE OR REPLACE FUNCTION pggit.execute_cqrs_changeset(
    changeset_id uuid
) RETURNS void AS $$
DECLARE
    operation_record record;
    execution_error text;
    all_success boolean := true;
BEGIN
    -- Update changeset status
    UPDATE pggit.cqrs_changesets 
    SET status = 'in_progress' 
    WHERE pggit.cqrs_changesets.changeset_id = execute_cqrs_changeset.changeset_id;
    
    -- Execute operations in order
    FOR operation_record IN 
        SELECT * FROM pggit.cqrs_operations 
        WHERE pggit.cqrs_operations.changeset_id = execute_cqrs_changeset.changeset_id
        ORDER BY operation_order
    LOOP
        BEGIN
            -- Temporarily disable tracking if needed
            IF pggit.in_deployment_mode() THEN
                -- Operations are batched in deployment mode
                EXECUTE operation_record.operation_sql;
            ELSE
                -- Normal execution with tracking
                EXECUTE operation_record.operation_sql;
            END IF;
            
            -- Mark operation as successful
            UPDATE pggit.cqrs_operations
            SET executed_at = now(), success = true
            WHERE operation_id = operation_record.operation_id;
            
        EXCEPTION WHEN OTHERS THEN
            -- Capture error
            GET STACKED DIAGNOSTICS execution_error = MESSAGE_TEXT;
            
            -- Mark operation as failed
            UPDATE pggit.cqrs_operations
            SET executed_at = now(), 
                success = false,
                error_message = execution_error
            WHERE operation_id = operation_record.operation_id;
            
            all_success := false;
            
            -- If atomic, rollback and exit
            IF all_success = false THEN
                UPDATE pggit.cqrs_changesets
                SET status = 'failed',
                    error_message = format('Operation %s failed: %s', 
                        operation_record.operation_order, execution_error)
                WHERE pggit.cqrs_changesets.changeset_id = execute_cqrs_changeset.changeset_id;
                
                RAISE EXCEPTION 'CQRS changeset execution failed: %', execution_error;
            END IF;
        END;
    END LOOP;
    
    -- Mark changeset as completed
    UPDATE pggit.cqrs_changesets
    SET status = 'completed',
        completed_at = now()
    WHERE pggit.cqrs_changesets.changeset_id = execute_cqrs_changeset.changeset_id;
    
    -- Create a commit if not in deployment mode
    IF NOT pggit.in_deployment_mode() THEN
        INSERT INTO pggit.commits (message, author, metadata)
        SELECT 
            'CQRS Change: ' || description,
            current_user,
            jsonb_build_object(
                'changeset_id', changeset_id,
                'version', version,
                'command_ops_count', array_length(command_operations, 1),
                'query_ops_count', array_length(query_operations, 1)
            )
        FROM pggit.cqrs_changesets
        WHERE pggit.cqrs_changesets.changeset_id = execute_cqrs_changeset.changeset_id;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Helper function for common CQRS patterns
CREATE OR REPLACE FUNCTION pggit.refresh_query_side(
    materialized_view_name text,
    skip_tracking boolean DEFAULT true
) RETURNS void AS $$
BEGIN
    IF skip_tracking THEN
        -- Temporarily disable tracking for MV refresh
        PERFORM pggit.pause_tracking('1 minute'::interval);
        EXECUTE format('REFRESH MATERIALIZED VIEW %s', materialized_view_name);
        PERFORM pggit.resume_tracking();
    ELSE
        EXECUTE format('REFRESH MATERIALIZED VIEW %s', materialized_view_name);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to analyze CQRS dependencies
CREATE OR REPLACE FUNCTION pggit.analyze_cqrs_dependencies(
    command_schema text DEFAULT 'command',
    query_schema text DEFAULT 'query'
) RETURNS TABLE (
    command_object text,
    query_object text,
    dependency_type text,
    dependency_path text[]
) AS $$
BEGIN
    -- Find materialized views in query schema that depend on command schema tables
    RETURN QUERY
    WITH RECURSIVE dep_tree AS (
        -- Base case: direct dependencies
        SELECT DISTINCT
            depender.schemaname || '.' || depender.tablename as query_obj,
            dependee.schemaname || '.' || dependee.tablename as command_obj,
            'direct'::text as dep_type,
            ARRAY[dependee.schemaname || '.' || dependee.tablename, 
                  depender.schemaname || '.' || depender.tablename] as path
        FROM pg_depend d
        JOIN pg_class c1 ON d.refobjid = c1.oid
        JOIN pg_class c2 ON d.objid = c2.oid
        JOIN pg_namespace n1 ON c1.relnamespace = n1.oid
        JOIN pg_namespace n2 ON c2.relnamespace = n2.oid
        JOIN pg_tables dependee ON dependee.tablename = c1.relname 
            AND dependee.schemaname = n1.nspname
        JOIN pg_matviews depender ON depender.matviewname = c2.relname 
            AND depender.schemaname = n2.nspname
        WHERE n1.nspname = command_schema
          AND n2.nspname = query_schema
        
        UNION
        
        -- Recursive case: indirect dependencies through views
        SELECT 
            dt.query_obj,
            dependee.schemaname || '.' || dependee.tablename,
            'indirect'::text,
            dt.path || (dependee.schemaname || '.' || dependee.tablename)
        FROM dep_tree dt
        JOIN pg_depend d ON true -- simplified for example
        JOIN pg_class c ON d.refobjid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        JOIN pg_tables dependee ON dependee.tablename = c.relname 
            AND dependee.schemaname = n.nspname
        WHERE n.nspname = command_schema
          AND NOT (dependee.schemaname || '.' || dependee.tablename) = ANY(dt.path)
    )
    SELECT 
        command_obj as command_object,
        query_obj as query_object,
        dep_type as dependency_type,
        path as dependency_path
    FROM dep_tree
    ORDER BY command_obj, query_obj;
END;
$$ LANGUAGE plpgsql;

-- View to show CQRS changeset history
CREATE OR REPLACE VIEW pggit.cqrs_history AS
SELECT 
    c.changeset_id,
    c.description,
    c.version,
    c.status,
    c.created_at,
    c.created_by,
    c.completed_at,
    array_length(c.command_operations, 1) as command_ops_count,
    array_length(c.query_operations, 1) as query_ops_count,
    (SELECT count(*) FROM pggit.cqrs_operations o 
     WHERE o.changeset_id = c.changeset_id AND o.success = true) as successful_ops,
    (SELECT count(*) FROM pggit.cqrs_operations o 
     WHERE o.changeset_id = c.changeset_id AND o.success = false) as failed_ops,
    c.error_message,
    com.commit_id,
    com.message as commit_message
FROM pggit.cqrs_changesets c
LEFT JOIN pggit.commits com ON com.metadata->>'changeset_id' = c.changeset_id::text
ORDER BY c.created_at DESC;