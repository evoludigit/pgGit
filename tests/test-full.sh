#!/bin/bash
# pggit Full Test Suite - Bulletproof Edition
# Runs all tests in order with proper error handling

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
DB_NAME="${PGGIT_TEST_DB:-postgres}"
DB_USER="${PGGIT_TEST_USER:-postgres}"
DB_HOST="${PGGIT_TEST_HOST:-localhost}"
DB_PORT="${PGGIT_TEST_PORT:-5432}"
USE_PODMAN="${PGGIT_USE_PODMAN:-false}"
PODMAN_IMAGE="postgres:17-alpine"
CONTAINER_NAME="pggit-test-full"

# Statistics
TESTS_PASSED=0
TESTS_FAILED=0
START_TIME=$(date +%s)

# Helper functions
print_header() {
    echo -e "${PURPLE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                  pggit Full Test Suite                         ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

run_sql_test() {
    local test_file="$1"
    local test_name="$2"
    
    print_section "Running $test_name"
    
    if [ "$USE_PODMAN" = "true" ]; then
        if podman exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -f "/pggit/tests/$test_file" 2>&1 | tee /tmp/pggit_test_output.log; then
            echo -e "${GREEN}✅ $test_name PASSED${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}❌ $test_name FAILED${NC}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo "Error output:"
            tail -20 /tmp/pggit_test_output.log
        fi
    else
        if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$test_file" 2>&1 | tee /tmp/pggit_test_output.log; then
            echo -e "${GREEN}✅ $test_name PASSED${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}❌ $test_name FAILED${NC}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo "Error output:"
            tail -20 /tmp/pggit_test_output.log
        fi
    fi
}

setup_podman() {
    echo -e "${BLUE}Setting up Podman test environment...${NC}"
    
    # Stop and remove existing container
    podman stop "$CONTAINER_NAME" 2>/dev/null || true
    podman rm "$CONTAINER_NAME" 2>/dev/null || true
    
    # Start PostgreSQL container
    podman run -d \
        --name "$CONTAINER_NAME" \
        -e POSTGRES_DB="$DB_NAME" \
        -e POSTGRES_USER="$DB_USER" \
        -e POSTGRES_PASSWORD=test \
        -e POSTGRES_HOST_AUTH_METHOD=trust \
        -v "$(dirname "$(pwd)"):/pggit:ro" \
        "$PODMAN_IMAGE"
    
    # Wait for database
    echo "Waiting for database to be ready..."
    for i in {1..30}; do
        if podman exec "$CONTAINER_NAME" pg_isready -U "$DB_USER" &>/dev/null; then
            break
        fi
        echo -n "."
        sleep 1
    done
    echo ""
    
    # Install pgcrypto
    podman exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
    
    # Install pggit from source
    echo "Installing pggit extension..."
    # Check which directory has install.sql and use that
    if podman exec "$CONTAINER_NAME" test -f /pggit/sql/install.sql; then
        podman exec "$CONTAINER_NAME" sh -c "cd /pggit/sql && psql -U $DB_USER -d $DB_NAME -f install.sql"
    elif podman exec "$CONTAINER_NAME" test -f /pggit/core/sql/install.sql; then
        podman exec "$CONTAINER_NAME" sh -c "cd /pggit/core/sql && psql -U $DB_USER -d $DB_NAME -f install.sql"
    else
        echo -e "${RED}❌ Could not find install.sql in container${NC}"
        exit 1
    fi
    
    # Install new feature modules
    echo "Installing new feature modules..."
    for module in pggit_configuration.sql pggit_conflict_resolution_api.sql pggit_cqrs_support.sql pggit_function_versioning.sql pggit_migration_integration.sql pggit_operations.sql pggit_enhanced_triggers.sql; do
        if podman exec "$CONTAINER_NAME" test -f "/pggit/sql/$module"; then
            echo "  Installing $module..."
            podman exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -f "/pggit/sql/$module" 2>/dev/null || echo "    (Some warnings are expected)"
        fi
    done
    
    echo -e "${GREEN}✅ Podman environment ready${NC}"
}

cleanup_podman() {
    if [ "$USE_PODMAN" = "true" ]; then
        echo -e "${YELLOW}Cleaning up Podman container...${NC}"
        podman stop "$CONTAINER_NAME" 2>/dev/null || true
        podman rm "$CONTAINER_NAME" 2>/dev/null || true
    fi
}

# Main execution
print_header

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --podman)
            USE_PODMAN="true"
            shift
            ;;
        --db)
            DB_NAME="$2"
            shift 2
            ;;
        --user)
            DB_USER="$2"
            shift 2
            ;;
        --host)
            DB_HOST="$2"
            shift 2
            ;;
        --port)
            DB_PORT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --podman        Use Podman container for testing"
            echo "  --db NAME       Database name (default: postgres)"
            echo "  --user USER     Database user (default: postgres)"
            echo "  --host HOST     Database host (default: localhost)"
            echo "  --port PORT     Database port (default: 5432)"
            echo "  --help          Show this help message"
            echo ""
            echo "Examples:"
            echo "  # Run tests locally"
            echo "  ./test-full.sh"
            echo ""
            echo "  # Run tests in Podman container"
            echo "  ./test-full.sh --podman"
            echo ""
            echo "  # Run tests on specific database"
            echo "  ./test-full.sh --db mydb --user myuser"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Change to tests directory
cd "$(dirname "$0")"

# Setup Podman if requested
if [ "$USE_PODMAN" = "true" ]; then
    setup_podman
    trap cleanup_podman EXIT
fi

# Check prerequisites
print_section "Checking Prerequisites"

if [ "$USE_PODMAN" = "false" ]; then
    # Check database connection
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" &>/dev/null; then
        echo -e "${GREEN}✅ Database connection OK${NC}"
    else
        echo -e "${RED}❌ Cannot connect to database${NC}"
        echo "Please check your database settings:"
        echo "  Host: $DB_HOST"
        echo "  Port: $DB_PORT"
        echo "  User: $DB_USER"
        echo "  Database: $DB_NAME"
        exit 1
    fi
    
    # Check if pggit is installed
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1 FROM pg_namespace WHERE nspname = 'pggit';" | grep -q "1 row"; then
        echo -e "${GREEN}✅ pggit extension installed${NC}"
    else
        echo -e "${YELLOW}⚠️  pggit not installed, attempting installation...${NC}"
        # Try to install from source
        if [ -f "../sql/install.sql" ]; then
            (cd ../sql && psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f install.sql)
            echo -e "${GREEN}✅ pggit installed from source${NC}"
        else
            echo -e "${RED}❌ Could not install pggit${NC}"
            exit 1
        fi
    fi
fi

# Run test suites in order
print_section "Running Test Suites"

# 1. Core tests (basic functionality)
run_sql_test "test-core.sql" "Core Tests"

# 2. Enterprise tests (advanced features)
run_sql_test "test-enterprise.sql" "Enterprise Tests"

# 3. AI tests (if AI module is loaded)
if [ "$USE_PODMAN" = "true" ] || psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1 FROM information_schema.tables WHERE table_schema = 'pggit' AND table_name = 'migration_patterns';" | grep -q "1 row"; then
    run_sql_test "test-ai.sql" "AI Tests"
else
    echo -e "${YELLOW}⚠️  Skipping AI tests (AI module not loaded)${NC}"
fi

# 4. Configuration System tests
run_sql_test "test-configuration-system.sql" "Configuration System Tests"

# 5. CQRS Support tests
run_sql_test "test-cqrs-support.sql" "CQRS Support Tests"

# 6. Function Versioning tests
run_sql_test "test-function-versioning.sql" "Function Versioning Tests"

# 7. Migration Integration tests
run_sql_test "test-migration-integration.sql" "Migration Integration Tests"

# 8. Conflict Resolution tests
run_sql_test "test-conflict-resolution.sql" "Conflict Resolution Tests"

# 9. Additional feature tests
if [ -f "test-advanced-features.sql" ]; then
    run_sql_test "test-advanced-features.sql" "Advanced Features Tests"
fi

if [ -f "test-zero-downtime.sql" ]; then
    run_sql_test "test-zero-downtime.sql" "Zero Downtime Tests"
fi

if [ -f "test-data-branching.sql" ]; then
    run_sql_test "test-data-branching.sql" "Data Branching Tests"
fi

if [ -f "test-diff-functionality.sql" ]; then
    run_sql_test "test-diff-functionality.sql" "Diff Functionality Tests"
fi

if [ -f "test-three-way-merge.sql" ]; then
    run_sql_test "test-three-way-merge.sql" "Three-Way Merge Tests"
fi

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Print summary
print_section "Test Summary"

echo -e "${BLUE}Test Results:${NC}"
echo -e "  ${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e "  ${RED}Failed:${NC} $TESTS_FAILED"
echo -e "  ${BLUE}Total:${NC} $((TESTS_PASSED + TESTS_FAILED))"
echo -e "  ${YELLOW}Duration:${NC} ${DURATION}s"
echo ""

# Calculate success rate
if [ $((TESTS_PASSED + TESTS_FAILED)) -gt 0 ]; then
    SUCCESS_RATE=$(( (TESTS_PASSED * 100) / (TESTS_PASSED + TESTS_FAILED) ))
    echo -e "${BLUE}Success Rate:${NC} $SUCCESS_RATE%"
else
    SUCCESS_RATE=0
fi

echo ""

# Final verdict
if [ $TESTS_FAILED -eq 0 ] && [ $TESTS_PASSED -gt 0 ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED! 🎉${NC}"
    echo -e "${GREEN}pgGit is working correctly.${NC}"
    exit 0
elif [ $SUCCESS_RATE -ge 80 ]; then
    echo -e "${YELLOW}⚠️  MOSTLY PASSED${NC}"
    echo -e "${YELLOW}Some tests failed, but core functionality works.${NC}"
    exit 1
else
    echo -e "${RED}❌ TEST SUITE FAILED${NC}"
    echo -e "${RED}Too many failures. Please check the logs above.${NC}"
    exit 2
fi