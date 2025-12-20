# pgGit Extension Template

This template helps you create custom pgGit extensions.

## Structure

```
my-extension/
├── sql/
│   ├── 001_schema.sql       # Extension schema
│   ├── 002_functions.sql    # Extension functions
│   └── 003_integration.sql  # pgGit integration hooks
├── tests/
│   └── test-extension.sql
└── my-extension.control     # Extension metadata
```

## Example: Audit Extension

```sql
-- sql/001_schema.sql
CREATE SCHEMA IF NOT EXISTS pggit_audit;

CREATE TABLE pggit_audit.change_log (
    log_id BIGSERIAL PRIMARY KEY,
    object_id INTEGER REFERENCES pggit.objects(id),
    change_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    user_name TEXT DEFAULT current_user,
    change_data JSONB
);

COMMENT ON TABLE pggit_audit.change_log IS 'Audit trail for all pgGit changes';
```

```sql
-- sql/002_functions.sql
CREATE OR REPLACE FUNCTION pggit_audit.log_change()
RETURNS event_trigger AS $$
BEGIN
    -- Log DDL changes to audit table
    INSERT INTO pggit_audit.change_log (object_id, change_data)
    SELECT
        obj.id,
        jsonb_build_object(
            'command', tg_tag,
            'object_type', obj.object_type,
            'object_name', obj.object_name,
            'schema', obj.schema_name
        )
    FROM pg_event_trigger_ddl_commands() AS cmd
    JOIN pggit.objects obj ON obj.object_name = cmd.object_identity;

    RAISE NOTICE 'Change logged to audit trail';
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION pggit_audit.log_change() IS 'Log DDL changes to audit trail';
```

```sql
-- sql/003_integration.sql
-- Create event trigger to automatically log changes
CREATE EVENT TRIGGER pggit_audit_trigger
    ON ddl_command_end
    WHEN TAG IN ('CREATE TABLE', 'ALTER TABLE', 'DROP TABLE',
                 'CREATE FUNCTION', 'ALTER FUNCTION', 'DROP FUNCTION')
    EXECUTE FUNCTION pggit_audit.log_change();

-- Grant permissions
GRANT USAGE ON SCHEMA pggit_audit TO pggit_users;
GRANT SELECT ON pggit_audit.change_log TO pggit_users;
```

## Quick Start

1. Copy this template:
   ```bash
   cp -r templates/extension-template/ my-audit-extension/
   cd my-audit-extension/
   ```

2. Customize the files for your extension

3. Install the extension:
   ```bash
   make install  # or psql -f sql/*.sql
   ```

4. Test your extension:
   ```bash
   psql -f tests/test-extension.sql
   ```

## Best Practices

- Use schema isolation (`pggit_<extension_name>`)
- Follow pgGit naming conventions
- Include comprehensive tests
- Document your extension thoroughly
- Handle errors gracefully
- Use event triggers sparingly for performance

## Available pgGit Hooks

- `ddl_command_start/end`: DDL operations
- `sql_drop`: Object drops
- `table_rewrite`: Table rewrites

See the pgGit documentation for complete hook reference.