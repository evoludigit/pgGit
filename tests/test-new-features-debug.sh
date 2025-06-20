#!/bin/bash
# Debug version of test runner to see actual errors

set -e

echo "Testing pgGit New Features (Debug Mode)"
echo "======================================"

# Configuration
DB_NAME="pggit_test"
DB_USER="postgres"
CONTAINER_NAME="pggit-pg17"

# Clean start
echo "Recreating database..."
podman exec $CONTAINER_NAME psql -U $DB_USER -c "DROP DATABASE IF EXISTS $DB_NAME;" || true
podman exec $CONTAINER_NAME psql -U $DB_USER -c "CREATE DATABASE $DB_NAME;"

# Install base pgGit
echo "Installing base pgGit..."
podman exec -i $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME << 'EOF'
-- Minimal pgGit setup for testing
CREATE SCHEMA IF NOT EXISTS pggit;

-- Essential tables
CREATE TABLE IF NOT EXISTS pggit.commits (
    commit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    message text,
    author text,
    tree_id uuid,
    created_at timestamptz DEFAULT now(),
    metadata jsonb
);

CREATE TABLE IF NOT EXISTS pggit.versioned_objects (
    object_id serial PRIMARY KEY,
    object_name text UNIQUE NOT NULL,
    object_type text,
    schema_name text
);

CREATE TABLE IF NOT EXISTS pggit.version_history (
    version_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    object_id integer REFERENCES pggit.versioned_objects(object_id),
    is_current boolean DEFAULT false,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pggit.trees (
    tree_id uuid PRIMARY KEY DEFAULT gen_random_uuid()
);

CREATE TABLE IF NOT EXISTS pggit.tree_entries (
    tree_id uuid REFERENCES pggit.trees(tree_id),
    entry_name text,
    entry_type text,
    blob_id uuid
);

CREATE TABLE IF NOT EXISTS pggit.blobs (
    blob_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    hash text,
    data bytea,
    size bigint,
    compression_type text
);

CREATE TABLE IF NOT EXISTS pggit.branches (
    branch_name text PRIMARY KEY,
    head_commit_id uuid
);

-- Stub functions
CREATE OR REPLACE FUNCTION pggit.version_object(
    classid oid, objid oid, objsubid integer,
    command_tag text, object_type text, schema_name text,
    object_identity text, in_extension boolean
) RETURNS void AS $$
BEGIN
    INSERT INTO pggit.versioned_objects (object_name, object_type, schema_name)
    VALUES (object_identity, object_type, schema_name)
    ON CONFLICT (object_name) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit.version_drop(
    classid oid, objid oid, objsubid integer,
    object_type text, schema_name text, object_identity text
) RETURNS void AS $$
BEGIN
    DELETE FROM pggit.versioned_objects WHERE object_name = object_identity;
END;
$$ LANGUAGE plpgsql;

-- Basic triggers
CREATE OR REPLACE FUNCTION pggit.ddl_trigger_func() RETURNS event_trigger AS $$
DECLARE
    obj record;
BEGIN
    FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands()
    LOOP
        IF obj.schema_name != 'pggit' THEN
            PERFORM pggit.version_object(
                obj.classid, obj.objid, obj.objsubid,
                obj.command_tag, obj.object_type, obj.schema_name,
                obj.object_identity, obj.in_extension
            );
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Additional stub functions
CREATE OR REPLACE FUNCTION pggit.get_current_version() RETURNS uuid AS $$
    SELECT gen_random_uuid();
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pggit.diff_text(text1 text, text2 text)
RETURNS TABLE(line_number int, change_type text, version1_line text, version2_line text) AS $$
BEGIN
    RETURN QUERY SELECT 1, 'change'::text, text1, text2;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit.get_schema_at_commit(commit_id uuid) RETURNS text AS $$
BEGIN
    RETURN '-- Schema at commit ' || commit_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit.drop_trigger_func() RETURNS event_trigger AS $$
DECLARE
    obj record;
BEGIN
    FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
    LOOP
        IF obj.schema_name != 'pggit' THEN
            PERFORM pggit.version_drop(
                obj.classid, obj.objid, obj.objsubid,
                obj.object_type, obj.schema_name, obj.object_identity
            );
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER pggit_ddl_trigger ON ddl_command_end
EXECUTE FUNCTION pggit.ddl_trigger_func();

CREATE EVENT TRIGGER pggit_drop_trigger ON sql_drop
EXECUTE FUNCTION pggit.drop_trigger_func();
EOF

# Install new features one by one
for module in configuration conflict_resolution_api cqrs_support function_versioning migration_integration operations enhanced_triggers; do
    echo ""
    echo "Installing pggit_${module}.sql..."
    if podman exec -i $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME < "sql/pggit_${module}.sql" 2>&1; then
        echo "✓ Installed successfully"
    else
        echo "✗ Installation failed"
    fi
done

# Run a simple test
echo ""
echo "Running simple test..."
podman exec -i $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME << 'EOF'
-- Test configuration
SELECT pggit.configure_tracking(
    track_schemas => ARRAY['public'],
    ignore_schemas => ARRAY['pg_temp%']
);

-- Create test table
CREATE TABLE test_table (id int);

-- Check if tracked
SELECT EXISTS(
    SELECT 1 FROM pggit.versioned_objects 
    WHERE object_name = 'public.test_table'
) as table_tracked;
EOF

echo ""
echo "Done!"