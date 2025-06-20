#!/bin/bash
# Debug script to test locally what might be failing in CI

echo "Checking SQL files..."
echo "===================="

# Check if install.sql exists
if [ -f "sql/install.sql" ]; then
    echo "✓ sql/install.sql found"
else
    echo "✗ sql/install.sql NOT FOUND"
fi

# Check test files
echo ""
echo "Test files found:"
echo "================="
for test in tests/test-*.sql; do
    if [ -f "$test" ] && [[ "$(basename $test)" =~ ^test-(configuration|cqrs|function|migration|conflict) ]]; then
        echo "✓ $test"
    fi
done

# Check for syntax errors in key files
echo ""
echo "Checking for obvious syntax issues..."
echo "===================================="

# Check for common SQL syntax issues
for sql_file in sql/pggit_*.sql; do
    if [ -f "$sql_file" ]; then
        echo -n "Checking $(basename $sql_file)... "
        # Look for common issues
        if grep -q "IF EXISTS.*ALTER EVENT TRIGGER" "$sql_file"; then
            echo "✗ Found unsupported IF EXISTS with ALTER EVENT TRIGGER"
        elif grep -q "GENERATED ALWAYS AS.*STORED" "$sql_file"; then
            echo "✗ Found GENERATED ALWAYS AS which might not be supported in older PG"
        else
            echo "✓"
        fi
    fi
done

echo ""
echo "Checking install.sql for issues..."
echo "=================================="
if [ -f "sql/install.sql" ]; then
    # Check if it references files that don't exist
    grep -E "\\\\i|\\\\include" sql/install.sql | while read -r line; do
        file_ref=$(echo "$line" | grep -oE "'[^']+'" | tr -d "'")
        if [ -n "$file_ref" ] && [ ! -f "sql/$file_ref" ]; then
            echo "✗ install.sql references missing file: $file_ref"
        fi
    done
fi