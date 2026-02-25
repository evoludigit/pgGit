#!/bin/bash
# Test Runner for pgGit Unit Tests
# Usage: ./tests/run-unit-tests.sh [test_file_pattern]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default database
DB_NAME="${DB_NAME:-pggit_test}"
PGUSER="${PGUSER:-postgres}"

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Function to check if pgTAP is installed
check_pgtap() {
    if ! psql -U "$PGUSER" -d "$DB_NAME" -c "SELECT 1 FROM pg_extension WHERE extname = 'pgtap'" 2>/dev/null | grep -q "1"; then
        print_info "pgTAP extension not found. Attempting to install..."
        
        # Try to create pgTAP extension
        if psql -U "$PGUSER" -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS pgtap;" 2>/dev/null; then
            print_success "pgTAP extension installed"
        else
            print_error "Failed to install pgTAP extension"
            print_info "Please install pgTAP manually: https://pgtap.org/documentation/"
            exit 1
        fi
    else
        print_success "pgTAP extension is available"
    fi
}

# Function to run a single test file
run_test_file() {
    local test_file="$1"
    local test_name=$(basename "$test_file")
    
    print_info "Running: $test_name"
    
    if psql -U "$PGUSER" -d "$DB_NAME" -f "$test_file" -v ON_ERROR_STOP=1 2>&1; then
        print_success "PASSED: $test_name"
        return 0
    else
        print_error "FAILED: $test_name"
        return 1
    fi
}

# Main execution
echo "=========================================="
echo "pgGit Unit Test Runner"
echo "=========================================="
echo "Database: $DB_NAME"
echo "User: $PGUSER"
echo ""

# Check database connection
if ! psql -U "$PGUSER" -d "$DB_NAME" -c "SELECT 1" >/dev/null 2>&1; then
    print_error "Cannot connect to database '$DB_NAME'"
    print_info "Please ensure PostgreSQL is running and database exists"
    print_info "You can create the database with: createdb -U $PGUSER $DB_NAME"
    exit 1
fi

print_success "Connected to database: $DB_NAME"

# Check for pgTAP
check_pgtap

# Determine which tests to run
TEST_PATTERN="${1:-*.sql}"
TEST_DIR="tests/unit"

if [ ! -d "$TEST_DIR" ]; then
    print_error "Test directory not found: $TEST_DIR"
    exit 1
fi

# Count total tests
TOTAL_TESTS=$(find "$TEST_DIR" -name "$TEST_PATTERN" -type f | wc -l)
print_info "Found $TOTAL_TESTS test files"
echo ""

# Run tests
PASSED=0
FAILED=0

for test_file in $(find "$TEST_DIR" -name "$TEST_PATTERN" -type f | sort); do
    if run_test_file "$test_file"; then
        ((PASSED++))
    else
        ((FAILED++))
    fi
    echo ""
done

# Summary
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo "Total: $TOTAL_TESTS"
echo ""

if [ $FAILED -eq 0 ]; then
    print_success "All tests passed! ✨"
    exit 0
else
    print_error "Some tests failed. Please review the output above."
    exit 1
fi
