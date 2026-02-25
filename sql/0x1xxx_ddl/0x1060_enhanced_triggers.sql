-- Enhanced pgGit Event Triggers with Configuration Support
-- Replaces the basic triggers with configuration-aware versions

-- DISABLED: Enhanced triggers have broken implementation (calls non-existent pggit.version_object)
-- Use original triggers from 002_event_triggers.sql instead
-- DROP EVENT TRIGGER IF EXISTS pggit_ddl_trigger CASCADE;
-- DROP EVENT TRIGGER IF EXISTS pggit_drop_trigger CASCADE;

-- Enhanced DDL trigger function with configuration support
CREATE OR REPLACE FUNCTION pggit.enhanced_ddl_trigger_func() 
RETURNS event_trigger AS $$
DECLARE
    obj record;
    should_track boolean;
    comment_directive boolean;
    operation text;
    current_deployment_id uuid;
BEGIN
    -- Check if tracking is paused
    IF EXISTS (
        SELECT 1 FROM pggit.system_events 
        WHERE event_type = 'tracking_paused' 
          AND (event_data->>'resume_at')::timestamptz > now()
        ORDER BY created_at DESC 
        LIMIT 1
    ) THEN
        RETURN;
    END IF;
    
    -- Get current operation
    operation := TG_TAG;
    
    -- Check if in deployment mode
    SELECT ds.current_deployment_id INTO current_deployment_id
    FROM pggit.deployment_state ds
    WHERE ds.is_active = true;
    
    FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands()
    LOOP
        -- Skip pggit schema objects
        IF obj.schema_name = 'pggit' THEN
            CONTINUE;
        END IF;
        
        -- Check comment-based directive first (highest priority)
        -- Extract just the object name without schema
        comment_directive := pggit.check_object_comment_directive(
            obj.object_type,
            obj.schema_name,
            CASE 
                WHEN obj.object_identity LIKE obj.schema_name || '.%' 
                THEN substring(obj.object_identity from length(obj.schema_name) + 2)
                ELSE obj.object_identity
            END
        );
        
        IF comment_directive IS NOT NULL THEN
            should_track := comment_directive;
        ELSE
            -- Check configuration
            should_track := pggit.should_track_object(
                obj.schema_name,
                obj.object_type,
                operation
            );
        END IF;
        
        -- Skip if not tracking
        IF NOT should_track THEN
            CONTINUE;
        END IF;
        
        -- Special handling for functions with enhanced versioning
        IF obj.object_type = 'function' THEN
            BEGIN
                PERFORM pggit.track_function(obj.object_identity);
            EXCEPTION WHEN OTHERS THEN
                -- Fall back to regular tracking
                NULL;
            END;
        END IF;
        
        -- Regular object tracking
        BEGIN
            -- In deployment mode, increment counter but don't create individual versions
            IF current_deployment_id IS NOT NULL THEN
                UPDATE pggit.deployment_mode
                SET changes_count = changes_count + 1
                WHERE deployment_id = current_deployment_id;
            ELSE
                -- Normal tracking
                PERFORM pggit.version_object(
                    obj.classid,
                    obj.objid,
                    obj.objsubid,
                    obj.command_tag,
                    obj.object_type,
                    obj.schema_name,
                    obj.object_identity,
                    obj.in_extension
                );
            END IF;
        EXCEPTION WHEN OTHERS THEN
            -- Log error but don't fail the DDL operation
            INSERT INTO pggit.system_events (event_type, event_data)
            VALUES ('tracking_error', jsonb_build_object(
                'error', SQLERRM,
                'object_type', obj.object_type,
                'object_identity', obj.object_identity,
                'operation', operation
            ));
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Enhanced DROP trigger function
CREATE OR REPLACE FUNCTION pggit.enhanced_drop_trigger_func() 
RETURNS event_trigger AS $$
DECLARE
    obj record;
    should_track boolean;
    operation text;
    current_deployment_id uuid;
BEGIN
    -- Check if tracking is paused
    IF EXISTS (
        SELECT 1 FROM pggit.system_events 
        WHERE event_type = 'tracking_paused' 
          AND (event_data->>'resume_at')::timestamptz > now()
        ORDER BY created_at DESC 
        LIMIT 1
    ) THEN
        RETURN;
    END IF;
    
    operation := 'DROP';
    
    -- Check if in deployment mode
    SELECT ds.current_deployment_id INTO current_deployment_id
    FROM pggit.deployment_state ds
    WHERE ds.is_active = true;
    
    FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
    LOOP
        -- Skip pggit schema objects
        IF obj.schema_name = 'pggit' THEN
            CONTINUE;
        END IF;
        
        -- Check configuration for drops
        should_track := pggit.should_track_object(
            obj.schema_name,
            obj.object_type,
            operation
        );
        
        IF NOT should_track THEN
            CONTINUE;
        END IF;
        
        BEGIN
            -- In deployment mode, just count the change
            IF current_deployment_id IS NOT NULL THEN
                UPDATE pggit.deployment_mode
                SET changes_count = changes_count + 1
                WHERE deployment_id = current_deployment_id;
            ELSE
                -- Normal tracking for drops
                PERFORM pggit.version_drop(
                    obj.classid,
                    obj.objid,
                    obj.objsubid,
                    obj.object_type,
                    obj.schema_name,
                    obj.object_identity
                );
            END IF;
        EXCEPTION WHEN OTHERS THEN
            -- Log error
            INSERT INTO pggit.system_events (event_type, event_data)
            VALUES ('tracking_error', jsonb_build_object(
                'error', SQLERRM,
                'object_type', obj.object_type,
                'object_identity', obj.object_identity,
                'operation', 'DROP'
            ));
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create new event triggers with enhanced functions
CREATE EVENT TRIGGER pggit_enhanced_ddl_trigger 
ON ddl_command_end
EXECUTE FUNCTION pggit.enhanced_ddl_trigger_func();

CREATE EVENT TRIGGER pggit_enhanced_drop_trigger 
ON sql_drop
EXECUTE FUNCTION pggit.enhanced_drop_trigger_func();

-- Function to switch between standard and enhanced triggers
CREATE OR REPLACE FUNCTION pggit.use_enhanced_triggers(
    enable boolean DEFAULT true
) RETURNS void AS $$
BEGIN
    IF enable THEN
        -- Disable standard triggers
        BEGIN
            ALTER EVENT TRIGGER pggit_ddl_trigger DISABLE;
        EXCEPTION WHEN undefined_object THEN NULL;
        END;
        BEGIN
            ALTER EVENT TRIGGER pggit_drop_trigger DISABLE;
        EXCEPTION WHEN undefined_object THEN NULL;
        END;
        
        -- Enable enhanced triggers
        ALTER EVENT TRIGGER pggit_enhanced_ddl_trigger ENABLE;
        ALTER EVENT TRIGGER pggit_enhanced_drop_trigger ENABLE;
        
        RAISE NOTICE 'Enhanced pgGit triggers enabled with configuration support';
    ELSE
        -- Enable standard triggers
        BEGIN
            ALTER EVENT TRIGGER pggit_ddl_trigger ENABLE;
        EXCEPTION WHEN undefined_object THEN NULL;
        END;
        BEGIN
            ALTER EVENT TRIGGER pggit_drop_trigger ENABLE;
        EXCEPTION WHEN undefined_object THEN NULL;
        END;
        
        -- Disable enhanced triggers
        ALTER EVENT TRIGGER pggit_enhanced_ddl_trigger DISABLE;
        ALTER EVENT TRIGGER pggit_enhanced_drop_trigger DISABLE;
        
        RAISE NOTICE 'Standard pgGit triggers enabled';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- DISABLED: Enhanced trigger implementation is broken (calls non-existent pggit.version_object)
-- Comment out to use original working triggers from 002_event_triggers.sql
-- SELECT pggit.use_enhanced_triggers(true);