#!/bin/bash
# Simple test script for pggit size management features

set -e

echo "=== Testing pggit Size Management System ==="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if podman is available, otherwise use docker
if command -v podman &> /dev/null; then
    CONTAINER_CMD="podman"
else
    CONTAINER_CMD="docker"
fi

echo "Using container command: $CONTAINER_CMD"

# Container and database settings
CONTAINER_NAME="pggit-size-test-simple"
DB_NAME="testdb"
DB_USER="postgres"
DB_PASS="postgres"
PG_PORT="5435"

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    $CONTAINER_CMD stop $CONTAINER_NAME 2>/dev/null || true
    $CONTAINER_CMD rm $CONTAINER_NAME 2>/dev/null || true
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Start PostgreSQL container
echo -e "${GREEN}Starting PostgreSQL container...${NC}"
$CONTAINER_CMD run -d \
    --name $CONTAINER_NAME \
    -e POSTGRES_PASSWORD=$DB_PASS \
    -e POSTGRES_DB=$DB_NAME \
    -p $PG_PORT:5432 \
    postgres:16

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to start..."
sleep 5

# Function to run SQL
run_sql() {
    PGPASSWORD=$DB_PASS psql -h localhost -p $PG_PORT -U $DB_USER -d $DB_NAME -c "$1" 2>&1
}

# Function to run SQL file
run_sql_file() {
    PGPASSWORD=$DB_PASS psql -h localhost -p $PG_PORT -U $DB_USER -d $DB_NAME -f "$1" 2>&1
}

# Wait for database to be ready
for i in {1..30}; do
    if run_sql "SELECT 1" > /dev/null 2>&1; then
        echo -e "${GREEN}Database is ready!${NC}"
        break
    fi
    echo "Waiting for database... ($i/30)"
    sleep 1
done

# Create minimal test SQL that combines necessary parts
cat > /tmp/pggit_size_test.sql << 'EOF'
-- Minimal pggit setup for size management testing

-- Create schema
CREATE SCHEMA IF NOT EXISTS pggit;

-- Basic types
CREATE TYPE pggit.branch_status AS ENUM ('ACTIVE', 'MERGED', 'DELETED', 'CONFLICTED');
CREATE TYPE pggit.commit_type AS ENUM ('COMMIT', 'MERGE', 'TAG', 'BRANCH');

-- Core tables
CREATE TABLE IF NOT EXISTS pggit.branches (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    status pggit.branch_status DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pggit.commits (
    id SERIAL PRIMARY KEY,
    branch_id INTEGER REFERENCES pggit.branches(id),
    tree_id INTEGER,
    commit_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pggit.trees (
    id SERIAL PRIMARY KEY,
    schema_hash TEXT
);

CREATE TABLE IF NOT EXISTS pggit.blobs (
    id SERIAL PRIMARY KEY,
    tree_id INTEGER REFERENCES pggit.trees(id),
    content TEXT,
    content_hash TEXT
);

CREATE TABLE IF NOT EXISTS pggit.refs (
    ref_name TEXT PRIMARY KEY,
    commit_id INTEGER
);

CREATE TABLE IF NOT EXISTS pggit.data_branches (
    branch_name TEXT,
    original_table TEXT
);

-- Function to find unreferenced blobs (stub)
CREATE OR REPLACE FUNCTION pggit.find_unreferenced_blobs()
RETURNS TABLE (
    blob_id INTEGER,
    content_hash TEXT,
    size_bytes INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        b.id,
        b.content_hash,
        LENGTH(b.content::text)
    FROM pggit.blobs b
    WHERE NOT EXISTS (
        SELECT 1
        FROM pggit.trees t
        WHERE b.tree_id = t.id
    );
END;
$$ LANGUAGE plpgsql;

-- Stub for cleanup function
CREATE OR REPLACE FUNCTION pggit.cleanup_unreferenced_blobs(days INTEGER DEFAULT 7)
RETURNS TABLE(blob_id INTEGER) AS $$
BEGIN
    RETURN QUERY
    DELETE FROM pggit.blobs 
    WHERE id IN (SELECT blob_id FROM pggit.find_unreferenced_blobs())
    RETURNING id;
END;
$$ LANGUAGE plpgsql;

-- Now include the size management module
\i sql/040_size_management.sql

-- Create test data
INSERT INTO pggit.branches (name, status) VALUES 
    ('main', 'ACTIVE'),
    ('feature/old-merged', 'MERGED'),
    ('feature/abandoned', 'ACTIVE'),
    ('feature/deleted', 'DELETED');

-- Create some commits and trees
INSERT INTO pggit.trees (schema_hash) VALUES ('hash1'), ('hash2'), ('hash3');

INSERT INTO pggit.commits (branch_id, tree_id, commit_date) VALUES
    (1, 1, CURRENT_TIMESTAMP),
    (2, 2, CURRENT_TIMESTAMP - INTERVAL '100 days'),
    (3, 3, CURRENT_TIMESTAMP - INTERVAL '200 days'),
    (4, 1, CURRENT_TIMESTAMP - INTERVAL '300 days');

-- Add some blobs
INSERT INTO pggit.blobs (tree_id, content, content_hash) VALUES
    (1, 'CREATE TABLE test1 (id INT)', 'hash1'),
    (2, 'CREATE TABLE test2 (id BIGINT, data JSONB)', 'hash2'),
    (3, 'CREATE TABLE test3 (id SERIAL PRIMARY KEY, content TEXT)', 'hash3'),
    (NULL, 'Unreferenced blob content', 'orphan1');

-- Create test tables first
CREATE TABLE test_table (id INT, data TEXT);
CREATE TABLE another_table (id INT, content JSONB);

-- Add data branches
INSERT INTO pggit.data_branches (branch_name, original_table) VALUES
    ('feature/old-merged', 'public.test_table'),
    ('feature/abandoned', 'public.another_table');

EOF

# Install and test
echo -e "\n${GREEN}Installing pggit size management...${NC}"
run_sql_file "/tmp/pggit_size_test.sql"

# Run tests
echo -e "\n${GREEN}Running size management tests...${NC}"

# Test 1: Update metrics
echo -e "\n${YELLOW}Test 1: Updating branch metrics${NC}"
run_sql "SELECT * FROM pggit.update_branch_metrics();"

# Test 2: Database overview
echo -e "\n${YELLOW}Test 2: Database size overview${NC}"
run_sql "SELECT * FROM pggit.database_size_overview;"

# Test 3: Generate recommendations
echo -e "\n${YELLOW}Test 3: Generating pruning recommendations${NC}"
run_sql "SELECT * FROM pggit.generate_pruning_recommendations(0, 30);"

# Test 4: Branch analysis
echo -e "\n${YELLOW}Test 4: Analyzing specific branches${NC}"
run_sql "SELECT 
    'feature/old-merged' as branch,
    (pggit.analyze_branch_for_pruning('feature/old-merged')).*;"

# Test 5: List branches by status
echo -e "\n${YELLOW}Test 5: Listing branches${NC}"
run_sql "SELECT * FROM pggit.list_branches('MERGED');"

# Test 6: Clean merged branches (dry run)
echo -e "\n${YELLOW}Test 6: Cleanup simulation${NC}"
run_sql "SELECT * FROM pggit.cleanup_merged_branches(true);"

# Test 7: Size impact analysis
echo -e "\n${YELLOW}Test 7: Migration size impact analysis${NC}"
run_sql "SELECT * FROM pggit.analyze_migration_size_impact(
    'CREATE TABLE large_table (
        id BIGSERIAL PRIMARY KEY,
        data JSONB,
        content TEXT
    );
    CREATE INDEX idx_data ON large_table USING GIN(data);'
);"

echo -e "\n${GREEN}All tests completed successfully!${NC}"