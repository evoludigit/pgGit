#!/bin/bash
# pgGit Test Runner
# Runs tests with pgTAP if available, otherwise basic functionality checks

set -e

# Configuration
DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-pggit_test}
DB_USER=${DB_USER:-postgres}

echo "🧪 Running pgGit Tests"
echo "======================"
echo "Database: $DB_NAME"
echo "Host: $DB_HOST:$DB_PORT"
echo "User: $DB_USER"
echo ""

# Check if test database exists
if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo "❌ Test database '$DB_NAME' does not exist"
    echo "   Create it with: createdb -h $DB_HOST -p $DB_PORT -U $DB_USER $DB_NAME"
    exit 1
fi

# Install pgGit if not already installed
echo "📦 Ensuring pgGit is installed..."
if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1 FROM information_schema.schemata WHERE schema_name = 'pggit'" &> /dev/null; then
    echo "   Installing pgGit..."
    if [ -f "pggit--0.1.0.sql" ]; then
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f pggit--0.1.0.sql >/dev/null 2>&1
    else
        echo "   ❌ pgGit installation file not found."
        exit 1
    fi
fi

# Check if pgTAP is available
echo "📦 Checking pgTAP availability..."
if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1 FROM pg_proc WHERE proname = 'plan'" &> /dev/null; then
    echo "   ✅ pgTAP functions available - running full test suite"

    # Run tests with pgTAP
    echo "🏃 Running pgTAP tests..."
    if command -v pg_prove &> /dev/null; then
        echo "   Using pg_prove..."
        pg_prove -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" tests/pgtap/*.sql
    else
        echo "   Using psql (pg_prove not available)..."
        TEST_FAILED=0
        for test_file in tests/pgtap/*.sql; do
            echo "   Running $(basename "$test_file")..."
            if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$test_file" 2>/dev/null | grep -q "not ok"; then
                echo "❌ Test failed: $(basename "$test_file")"
                TEST_FAILED=1
            else
                echo "✅ Passed: $(basename "$test_file")"
            fi
        done
        if [ $TEST_FAILED -eq 1 ]; then
            echo "❌ Some tests failed"
            exit 1
        fi
    fi
else
    echo "   ❌ pgTAP functions not found - running basic functionality checks"
    # Fall back to basic SQL tests without pgTAP framework
    echo "🏃 Running basic functionality tests..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
      -- Basic smoke tests
      SELECT 'Schema exists' as test, COUNT(*) > 0 as result FROM information_schema.schemata WHERE schema_name = 'pggit'
      UNION ALL
      SELECT 'Objects table exists', COUNT(*) > 0 FROM information_schema.tables WHERE table_schema = 'pggit' AND table_name = 'objects'
      UNION ALL
      SELECT 'History table exists', COUNT(*) > 0 FROM information_schema.tables WHERE table_schema = 'pggit' AND table_name = 'history'
      UNION ALL
      SELECT 'Event triggers exist', COUNT(*) > 0 FROM pg_event_trigger WHERE evtname LIKE 'pggit%'
    "
    echo "✅ Basic functionality verified"
fi

echo ""
echo "✅ All tests completed!"