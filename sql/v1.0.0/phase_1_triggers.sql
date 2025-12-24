-- pgGit v0.0.1 - Phase 1: Event Triggers for DDL Capture
-- Event trigger framework for automatic DDL capture
-- NOTE: Full event trigger implementation requires complex catalog queries
-- This version provides the foundation and can be extended in Phase 2
-- Date: 2025-12-24

-- 1. Simple DDL event trigger function (foundation)
-- In production, this would connect to external DDL parsing service or
-- pg_dump/pg_restore hooks. Event triggers in PostgreSQL have limited
-- ability to access DDL command text directly.
CREATE OR REPLACE FUNCTION pggit.on_ddl_command()
RETURNS event_trigger AS $$
DECLARE
    v_object_type TEXT;
    v_schema_name TEXT;
    v_object_name TEXT;
    r_ddl record;
BEGIN
    -- PostgreSQL event triggers can detect that DDL occurred
    -- but have limited access to the actual SQL text.
    -- In Phase 2, we'll implement:
    -- 1. Integration with pg_dump for schema snapshots
    -- 2. Application-level logging of DDL statements
    -- 3. Custom catalog functions to detect changes

    FOR r_ddl IN
        SELECT classid, objid, object_type, schema_name
        FROM pg_event_trigger_ddl_commands()
    LOOP
        -- Skip system schemas
        IF r_ddl.schema_name IS NULL OR
           r_ddl.schema_name IN ('pg_catalog', 'information_schema', 'pg_toast') THEN
            CONTINUE;
        END IF;

        -- Skip pggit schema itself
        IF r_ddl.schema_name = 'pggit' THEN
            CONTINUE;
        END IF;

        -- This is a placeholder for Phase 2 DDL capture implementation
        -- The trigger successfully fires but full capture logic will be
        -- implemented using alternative approaches (see Phase 2 spec)
        RAISE DEBUG 'pgGit event: % on %', r_ddl.object_type, r_ddl.schema_name;

    END LOOP;

    -- Event trigger fired successfully
    RETURN;

END;
$$ LANGUAGE plpgsql;

-- 2. Create event trigger
-- This fires when DDL commands complete, allowing us to detect changes
CREATE EVENT TRIGGER pggit_ddl_capture
    ON ddl_command_end
    EXECUTE FUNCTION pggit.on_ddl_command();

-- 3. Helper function to capture schema state (for manual use)
-- This can be called periodically to snapshot current schema state
CREATE OR REPLACE FUNCTION pggit.capture_current_schema(p_branch_name TEXT DEFAULT 'main')
RETURNS TABLE(objects_captured INT) AS $$
DECLARE
    v_branch_id INTEGER;
    v_object_count INT := 0;
BEGIN
    -- Get branch ID
    v_branch_id := pggit.get_branch_by_name(p_branch_name);

    IF v_branch_id IS NULL THEN
        PERFORM pggit.raise_pggit_error('BRANCH_NOT_FOUND', format('Branch "%s" not found', p_branch_name));
    END IF;

    -- This function serves as the pattern for Phase 2 DDL capture
    -- It will be expanded to automatically query pg_catalog and
    -- record all schema objects

    RETURN QUERY SELECT COUNT(*)::INT FROM pggit.schema_objects WHERE is_active = true;

END;
$$ LANGUAGE plpgsql;
