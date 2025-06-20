-- pgGit Configuration System for Selective Tracking
-- Addresses PrintOptim's requirements for schema and operation filtering

-- Configuration table to store tracking preferences
CREATE TABLE IF NOT EXISTS pggit.tracking_config (
    config_id serial PRIMARY KEY,
    config_type text NOT NULL CHECK (config_type IN ('schema', 'operation', 'pattern')),
    action text NOT NULL CHECK (action IN ('track', 'ignore')),
    pattern text NOT NULL,
    priority integer DEFAULT 0, -- Higher priority rules override lower ones
    created_at timestamptz DEFAULT now(),
    created_by text DEFAULT current_user,
    UNIQUE(config_type, pattern)
);

-- Index for fast lookups during event processing
CREATE INDEX idx_tracking_config_lookup ON pggit.tracking_config(config_type, action);

-- Function to configure tracking preferences
CREATE OR REPLACE FUNCTION pggit.configure_tracking(
    track_schemas text[] DEFAULT NULL,
    ignore_schemas text[] DEFAULT NULL,
    track_operations text[] DEFAULT NULL,
    ignore_operations text[] DEFAULT NULL
) RETURNS void AS $$
DECLARE
    schema_name text;
    operation text;
BEGIN
    -- Clear existing configuration
    DELETE FROM pggit.tracking_config;
    
    -- Add track schemas
    IF track_schemas IS NOT NULL THEN
        FOREACH schema_name IN ARRAY track_schemas
        LOOP
            INSERT INTO pggit.tracking_config (config_type, action, pattern, priority)
            VALUES ('schema', 'track', schema_name, 100);
        END LOOP;
    END IF;
    
    -- Add ignore schemas (lower priority than track)
    IF ignore_schemas IS NOT NULL THEN
        FOREACH schema_name IN ARRAY ignore_schemas
        LOOP
            INSERT INTO pggit.tracking_config (config_type, action, pattern, priority)
            VALUES ('schema', 'ignore', schema_name, 50);
        END LOOP;
    END IF;
    
    -- Add track operations
    IF track_operations IS NOT NULL THEN
        FOREACH operation IN ARRAY track_operations
        LOOP
            INSERT INTO pggit.tracking_config (config_type, action, pattern, priority)
            VALUES ('operation', 'track', operation, 100);
        END LOOP;
    END IF;
    
    -- Add ignore operations
    IF ignore_operations IS NOT NULL THEN
        FOREACH operation IN ARRAY ignore_operations
        LOOP
            INSERT INTO pggit.tracking_config (config_type, action, pattern, priority)
            VALUES ('operation', 'ignore', operation, 50);
        END LOOP;
    END IF;
    
    -- Add default ignores for system schemas if no schemas specified
    IF track_schemas IS NULL AND ignore_schemas IS NULL THEN
        INSERT INTO pggit.tracking_config (config_type, action, pattern, priority)
        VALUES 
            ('schema', 'ignore', 'pg_temp%', 10),
            ('schema', 'ignore', 'pg_toast%', 10);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to add ignore patterns
CREATE OR REPLACE FUNCTION pggit.add_ignore_pattern(pattern text) RETURNS void AS $$
BEGIN
    INSERT INTO pggit.tracking_config (config_type, action, pattern, priority)
    VALUES ('pattern', 'ignore', pattern, 75)
    ON CONFLICT (config_type, pattern) 
    DO UPDATE SET action = 'ignore', priority = 75;
END;
$$ LANGUAGE plpgsql;

-- Function to check if an object should be tracked
CREATE OR REPLACE FUNCTION pggit.should_track_object(
    object_schema text,
    object_type text,
    operation text
) RETURNS boolean AS $$
DECLARE
    should_track boolean := true;
    config_record record;
BEGIN
    -- Check schema rules
    FOR config_record IN 
        SELECT action, pattern, priority 
        FROM pggit.tracking_config 
        WHERE config_type = 'schema' 
            AND (object_schema = pattern OR object_schema LIKE pattern)
        ORDER BY priority DESC
        LIMIT 1
    LOOP
        should_track := (config_record.action = 'track');
        EXIT;
    END LOOP;
    
    -- Check operation rules (can override schema rules)
    FOR config_record IN 
        SELECT action, pattern, priority 
        FROM pggit.tracking_config 
        WHERE config_type = 'operation' 
            AND operation = pattern
        ORDER BY priority DESC
        LIMIT 1
    LOOP
        should_track := (config_record.action = 'track');
    END LOOP;
    
    -- Check pattern rules (highest precedence)
    FOR config_record IN 
        SELECT action, pattern, priority 
        FROM pggit.tracking_config 
        WHERE config_type = 'pattern' 
            AND operation LIKE pattern
        ORDER BY priority DESC
        LIMIT 1
    LOOP
        should_track := (config_record.action = 'track');
    END LOOP;
    
    RETURN should_track;
END;
$$ LANGUAGE plpgsql;

-- Deployment mode support
CREATE TABLE IF NOT EXISTS pggit.deployment_mode (
    deployment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    deployment_name text NOT NULL,
    started_at timestamptz DEFAULT now(),
    started_by text DEFAULT current_user,
    ended_at timestamptz,
    auto_commit boolean DEFAULT false,
    changes_count integer DEFAULT 0,
    status text DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled'))
);

-- Global flag for deployment mode
CREATE TABLE IF NOT EXISTS pggit.deployment_state (
    id integer PRIMARY KEY DEFAULT 1 CHECK (id = 1), -- Ensure single row
    current_deployment_id uuid REFERENCES pggit.deployment_mode(deployment_id),
    is_active boolean DEFAULT false
);

-- Initialize deployment state
INSERT INTO pggit.deployment_state (id, is_active) 
VALUES (1, false) 
ON CONFLICT (id) DO NOTHING;

-- Begin deployment mode
CREATE OR REPLACE FUNCTION pggit.begin_deployment(
    deployment_name text,
    auto_commit boolean DEFAULT false
) RETURNS uuid AS $$
DECLARE
    deployment_id uuid;
    current_state record;
BEGIN
    -- Check if deployment is already active
    SELECT * INTO current_state FROM pggit.deployment_state WHERE id = 1;
    IF current_state.is_active THEN
        RAISE EXCEPTION 'Deployment already in progress: %', current_state.current_deployment_id;
    END IF;
    
    -- Create new deployment
    INSERT INTO pggit.deployment_mode (deployment_name, auto_commit)
    VALUES (deployment_name, auto_commit)
    RETURNING pggit.deployment_mode.deployment_id INTO deployment_id;
    
    -- Update global state
    UPDATE pggit.deployment_state 
    SET current_deployment_id = deployment_id, is_active = true 
    WHERE id = 1;
    
    RETURN deployment_id;
END;
$$ LANGUAGE plpgsql;

-- End deployment mode
CREATE OR REPLACE FUNCTION pggit.end_deployment(
    message text DEFAULT NULL,
    tags text[] DEFAULT NULL
) RETURNS void AS $$
DECLARE
    current_deployment record;
    deployment_changes integer;
BEGIN
    -- Get current deployment
    SELECT d.* INTO current_deployment 
    FROM pggit.deployment_mode d
    JOIN pggit.deployment_state s ON s.current_deployment_id = d.deployment_id
    WHERE s.is_active = true;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No active deployment found';
    END IF;
    
    -- Update deployment record
    UPDATE pggit.deployment_mode 
    SET ended_at = now(), status = 'completed'
    WHERE deployment_id = current_deployment.deployment_id;
    
    -- Create a single commit for all deployment changes if auto_commit is true
    IF current_deployment.auto_commit AND current_deployment.changes_count > 0 THEN
        INSERT INTO pggit.commits (
            message, 
            author, 
            metadata
        ) VALUES (
            COALESCE(message, 'Deployment: ' || current_deployment.deployment_name),
            current_user,
            jsonb_build_object(
                'deployment_id', current_deployment.deployment_id,
                'tags', tags,
                'changes_count', current_deployment.changes_count
            )
        );
    END IF;
    
    -- Clear deployment state
    UPDATE pggit.deployment_state 
    SET current_deployment_id = NULL, is_active = false 
    WHERE id = 1;
END;
$$ LANGUAGE plpgsql;

-- Check if currently in deployment mode
CREATE OR REPLACE FUNCTION pggit.in_deployment_mode() RETURNS boolean AS $$
    SELECT is_active FROM pggit.deployment_state WHERE id = 1;
$$ LANGUAGE sql;

-- Emergency pause tracking
CREATE OR REPLACE FUNCTION pggit.pause_tracking(duration interval DEFAULT '1 hour'::interval) RETURNS void AS $$
DECLARE
    resume_time timestamptz;
BEGIN
    resume_time := now() + duration;
    
    -- Disable event triggers
    ALTER EVENT TRIGGER pggit_ddl_trigger DISABLE;
    ALTER EVENT TRIGGER pggit_drop_trigger DISABLE;
    
    -- Log the pause
    INSERT INTO pggit.system_events (event_type, event_data)
    VALUES ('tracking_paused', jsonb_build_object(
        'paused_at', now(),
        'resume_at', resume_time,
        'duration', duration,
        'paused_by', current_user
    ));
    
    -- Schedule re-enable (would need pg_cron or similar in production)
    RAISE NOTICE 'pgGit tracking paused until %. Manual resume available with pggit.resume_tracking()', resume_time;
END;
$$ LANGUAGE plpgsql;

-- Resume tracking
CREATE OR REPLACE FUNCTION pggit.resume_tracking() RETURNS void AS $$
BEGIN
    -- Re-enable event triggers
    ALTER EVENT TRIGGER pggit_ddl_trigger ENABLE;
    ALTER EVENT TRIGGER pggit_drop_trigger ENABLE;
    
    -- Log the resume
    INSERT INTO pggit.system_events (event_type, event_data)
    VALUES ('tracking_resumed', jsonb_build_object(
        'resumed_at', now(),
        'resumed_by', current_user
    ));
    
    RAISE NOTICE 'pgGit tracking resumed';
END;
$$ LANGUAGE plpgsql;

-- System events table for tracking administrative actions
CREATE TABLE IF NOT EXISTS pggit.system_events (
    event_id serial PRIMARY KEY,
    event_type text NOT NULL,
    event_data jsonb,
    created_at timestamptz DEFAULT now()
);

-- Comment-based tracking control
CREATE OR REPLACE FUNCTION pggit.parse_object_comment(comment_text text) 
RETURNS jsonb AS $$
DECLARE
    pggit_directive text;
    result jsonb := '{}'::jsonb;
BEGIN
    -- Look for @pggit: directives in comments
    IF comment_text ~ '@pggit:' THEN
        pggit_directive := substring(comment_text from '@pggit:(\w+)');
        
        CASE pggit_directive
            WHEN 'ignore' THEN
                result := jsonb_build_object('track', false);
            WHEN 'track' THEN
                result := jsonb_build_object('track', true);
            WHEN 'version' THEN
                -- Extract version number
                result := jsonb_build_object(
                    'track', true,
                    'version', substring(comment_text from '@pggit:version\s+(\S+)')
                );
        END CASE;
    END IF;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Function to check object comments for tracking directives
CREATE OR REPLACE FUNCTION pggit.check_object_comment_directive(
    object_type text,
    object_schema text,
    object_name text
) RETURNS boolean AS $$
DECLARE
    comment_text text;
    directive jsonb;
BEGIN
    -- Get object comment based on type
    CASE object_type
        WHEN 'table' THEN
            SELECT obj_description((object_schema || '.' || object_name)::regclass, 'pg_class')
            INTO comment_text;
        WHEN 'function' THEN
            SELECT obj_description((object_schema || '.' || object_name)::regprocedure, 'pg_proc')
            INTO comment_text;
        ELSE
            -- For other object types, return NULL
            comment_text := NULL;
    END CASE;
    
    IF comment_text IS NOT NULL THEN
        directive := pggit.parse_object_comment(comment_text);
        IF directive ? 'track' THEN
            RETURN (directive->>'track')::boolean;
        END IF;
    END IF;
    
    -- No directive found, use default behavior
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;