#!/bin/bash
# Test runner for new pgGit features addressing PrintOptim requirements

set -e

echo "============================================"
echo "pgGit New Features Test Suite"
echo "============================================"

# Configuration
DB_NAME="pggit_test"
DB_USER="postgres"
DB_HOST="localhost"
DB_PORT="5433"
CONTAINER_NAME="pggit-pg17"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to run test file
run_test() {
    local test_file=$1
    local test_name=$2
    
    echo -e "\n${GREEN}Running: ${test_name}${NC}"
    echo "----------------------------------------"
    
    if podman exec -i $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -f - < "$test_file"; then
        echo -e "${GREEN}✓ ${test_name} PASSED${NC}"
        return 0
    else
        echo -e "${RED}✗ ${test_name} FAILED${NC}"
        return 1
    fi
}

# Check if container exists and start if needed
if podman ps -a | grep -q $CONTAINER_NAME; then
    if ! podman ps | grep -q $CONTAINER_NAME; then
        echo "Starting existing PostgreSQL container..."
        podman start $CONTAINER_NAME
        sleep 3
    fi
else
    echo "Creating new PostgreSQL container..."
    podman run -d \
        --name $CONTAINER_NAME \
        -e POSTGRES_PASSWORD=postgres \
        -e POSTGRES_DB=$DB_NAME \
        -p $DB_PORT:5432 \
        postgres:17
    sleep 5
fi

# Wait for PostgreSQL to be ready
until podman exec $CONTAINER_NAME pg_isready -U $DB_USER; do
    echo "Waiting for database..."
    sleep 2
done

# Install pgGit and new features
echo -e "\n${GREEN}Installing pgGit and new features...${NC}"

# Core pgGit installation
podman exec -i $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME << 'EOF'
-- Create pggit schema
CREATE SCHEMA IF NOT EXISTS pggit;

-- Basic tables needed for tests (simplified)
CREATE TABLE IF NOT EXISTS pggit.commits (
    commit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    message text,
    author text,
    tree_id uuid,
    parent_commit_id uuid,
    created_at timestamptz DEFAULT now(),
    metadata jsonb
);

CREATE TABLE IF NOT EXISTS pggit.branches (
    branch_id serial PRIMARY KEY,
    branch_name text UNIQUE NOT NULL,
    head_commit_id uuid REFERENCES pggit.commits(commit_id),
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pggit.trees (
    tree_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pggit.tree_entries (
    tree_id uuid REFERENCES pggit.trees(tree_id),
    entry_name text,
    entry_type text,
    blob_id uuid,
    PRIMARY KEY (tree_id, entry_name)
);

CREATE TABLE IF NOT EXISTS pggit.blobs (
    blob_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    hash text UNIQUE NOT NULL,
    data bytea,
    size bigint,
    compression_type text,
    original_size bigint,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pggit.versioned_objects (
    object_id serial PRIMARY KEY,
    object_name text UNIQUE NOT NULL,
    object_type text,
    schema_name text,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pggit.version_history (
    version_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    object_id integer REFERENCES pggit.versioned_objects(object_id),
    version_major integer DEFAULT 1,
    version_minor integer DEFAULT 0,
    version_patch integer DEFAULT 0,
    is_current boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    created_by text DEFAULT current_user
);

-- Stub functions for core functionality
CREATE OR REPLACE FUNCTION pggit.get_current_version() RETURNS uuid AS $$
    SELECT gen_random_uuid();
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pggit.version_object(
    classid oid, objid oid, objsubid integer,
    command_tag text, object_type text, schema_name text,
    object_identity text, in_extension boolean
) RETURNS void AS $$
BEGIN
    -- Simplified version tracking
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
    -- Simplified drop tracking
    DELETE FROM pggit.versioned_objects WHERE object_name = object_identity;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit.diff_text(text1 text, text2 text)
RETURNS TABLE(line_number int, change_type text, version1_line text, version2_line text) AS $$
BEGIN
    -- Stub implementation
    RETURN QUERY SELECT 1, 'change'::text, text1, text2;
END;
$$ LANGUAGE plpgsql;

-- Create original event triggers for testing
CREATE OR REPLACE FUNCTION pggit.ddl_trigger_func() RETURNS event_trigger AS $$
BEGIN
    -- Original simple trigger
    RAISE NOTICE 'Original DDL trigger fired';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit.drop_trigger_func() RETURNS event_trigger AS $$
BEGIN
    -- Original simple trigger
    RAISE NOTICE 'Original DROP trigger fired';
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER pggit_ddl_trigger ON ddl_command_end
EXECUTE FUNCTION pggit.ddl_trigger_func();

CREATE EVENT TRIGGER pggit_drop_trigger ON sql_drop
EXECUTE FUNCTION pggit.drop_trigger_func();
EOF

# Install new features
echo -e "\n${GREEN}Installing new feature modules...${NC}"

for sql_file in sql/pggit_*.sql; do
    if [ -f "$sql_file" ]; then
        echo "Installing $(basename $sql_file)..."
        podman exec -i $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME < "$sql_file"
    fi
done

# Run tests
echo -e "\n${GREEN}Running test suites...${NC}"

TOTAL_TESTS=0
PASSED_TESTS=0

# Run each test suite
for test in "configuration-system" "cqrs-support" "function-versioning" "migration-integration" "conflict-resolution"; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if run_test "tests/test-${test}.sql" "${test}"; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
    fi
done

# Summary
echo -e "\n============================================"
echo -e "Test Summary: ${PASSED_TESTS}/${TOTAL_TESTS} test suites passed"
if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo -e "${GREEN}All tests PASSED!${NC}"
    exit 0
else
    echo -e "${RED}Some tests FAILED!${NC}"
    exit 1
fi