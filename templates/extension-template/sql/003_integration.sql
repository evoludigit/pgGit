-- File: templates/extension-template/sql/003_integration.sql
-- Example pgGit integration hooks

-- Example: Log when extension functions are called
CREATE OR REPLACE FUNCTION pggit_example.log_usage()
RETURNS event_trigger AS $$
BEGIN
    -- Log extension usage in pgGit history
    INSERT INTO pggit.history (
        object_type, object_name, schema_name,
        change_type, metadata, created_by
    ) VALUES (
        'extension', 'pggit_example', 'pggit_example',
        'USAGE', jsonb_build_object('event', tg_tag),
        current_user
    );
END;
$$ LANGUAGE plpgsql;

-- Example event trigger (customize as needed)
CREATE EVENT TRIGGER pggit_example_usage_trigger
    ON ddl_command_end
    WHEN TAG IN ('SELECT')  -- Customize trigger conditions
    EXECUTE FUNCTION pggit_example.log_usage();

-- Grant necessary permissions
GRANT USAGE ON SCHEMA pggit_example TO public;
GRANT SELECT ON pggit_example.metadata TO public;