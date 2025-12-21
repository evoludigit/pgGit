#!/bin/bash

# Test script for 'make install' command
# This script validates that the installation process works correctly
# and that the pggit schema is properly created.

set -e

CONTAINER_NAME="pggit_install_test"
POSTGRES_VERSION="${POSTGRES_VERSION:-18}"
TEST_RESULT=0

echo "=========================================="
echo "pgGit Installation Test"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to cleanup
cleanup() {
    echo ""
    echo "Cleaning up test container..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Step 1: Start PostgreSQL container
echo "Step 1: Starting PostgreSQL $POSTGRES_VERSION container..."
docker run -d \
  --name "$CONTAINER_NAME" \
  -e POSTGRES_PASSWORD=testpass \
  -e POSTGRES_USER=testuser \
  -e POSTGRES_DB=testdb \
  -p 5433:5432 \
  "postgres:$POSTGRES_VERSION" > /dev/null

echo "Container started. Waiting for PostgreSQL to be ready..."
sleep 10

# Verify connection
echo "Step 2: Verifying PostgreSQL connection..."
for i in {1..30}; do
    if PGPASSWORD=testpass psql -h localhost -p 5433 -U testuser -d testdb -c "SELECT 1" > /dev/null 2>&1; then
        echo "PostgreSQL is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}ERROR: PostgreSQL failed to start${NC}"
        exit 1
    fi
    echo "Attempt $i/30... waiting..."
    sleep 1
done

# Step 3: Run make install
echo ""
echo "Step 3: Running 'make install'..."
if PGHOST=localhost PGPORT=5433 PGUSER=testuser PGPASSWORD=testpass PGDATABASE=testdb make install > /tmp/make_install.log 2>&1; then
    echo -e "${GREEN}✓ make install completed successfully${NC}"
else
    echo -e "${RED}✗ make install failed${NC}"
    echo "Log output:"
    cat /tmp/make_install.log
    TEST_RESULT=1
fi

# Step 4: Verify pggit schema exists
echo ""
echo "Step 4: Verifying pggit schema installation..."
if PGHOST=localhost PGPORT=5433 PGUSER=testuser PGPASSWORD=testpass PGDATABASE=testdb psql -c "SELECT nspname FROM pg_namespace WHERE nspname = 'pggit';" > /tmp/schema_check.log 2>&1; then
    SCHEMA_EXISTS=$(PGHOST=localhost PGPORT=5433 PGUSER=testuser PGPASSWORD=testpass PGDATABASE=testdb psql -t -c "SELECT COUNT(*) FROM pg_namespace WHERE nspname = 'pggit';")
    if [ "$SCHEMA_EXISTS" -eq 1 ]; then
        echo -e "${GREEN}✓ pggit schema exists${NC}"
    else
        echo -e "${RED}✗ pggit schema not found${NC}"
        TEST_RESULT=1
    fi
else
    echo -e "${RED}✗ Failed to check schema${NC}"
    TEST_RESULT=1
fi

# Step 5: Verify tables were created
echo ""
echo "Step 5: Verifying tables in pggit schema..."
TABLE_COUNT=$(PGHOST=localhost PGPORT=5433 PGUSER=testuser PGPASSWORD=testpass PGDATABASE=testdb psql -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'pggit';")
if [ "$TABLE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Found $TABLE_COUNT tables in pggit schema${NC}"
else
    echo -e "${RED}✗ No tables found in pggit schema${NC}"
    TEST_RESULT=1
fi

# Step 6: Verify functions were created
echo ""
echo "Step 6: Verifying functions in pggit schema..."
FUNCTION_COUNT=$(PGHOST=localhost PGPORT=5433 PGUSER=testuser PGPASSWORD=testpass PGDATABASE=testdb psql -t -c "SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema = 'pggit';")
if [ "$FUNCTION_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Found $FUNCTION_COUNT functions in pggit schema${NC}"
else
    echo -e "${RED}✗ No functions found in pggit schema${NC}"
    TEST_RESULT=1
fi

# Step 7: Test quick start queries
echo ""
echo "Step 7: Testing quick start queries..."
if PGHOST=localhost PGPORT=5433 PGUSER=testuser PGPASSWORD=testpass PGDATABASE=testdb psql -c "SELECT * FROM pggit.database_size_overview LIMIT 1;" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ database_size_overview view works${NC}"
else
    echo -e "${YELLOW}⚠ database_size_overview query had issues (may be expected)${NC}"
fi

# Final summary
echo ""
echo "=========================================="
if [ $TEST_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    echo "=========================================="
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    echo "=========================================="
    exit 1
fi
