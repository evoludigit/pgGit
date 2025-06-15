#!/bin/bash
# Example CI/CD pipeline script integrating database versioning and pgTAP

set -e  # Exit on error

# Configuration
DB_NAME="${DB_NAME:-dev_db}"
DB_USER="${DB_USER:-dbuser}"
SQL_DIR="${SQL_DIR:-./sql}"
TEST_DIR="${TEST_DIR:-./tests}"

echo "=== Database Schema Deployment Pipeline ==="
echo "Database: $DB_NAME"
echo "SQL Directory: $SQL_DIR"
echo ""

# Step 1: Install database versioning if not present
echo "1. Checking database versioning installation..."
psql -U $DB_USER -d $DB_NAME -c "
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'gitversion') THEN
        RAISE NOTICE 'Installing database versioning...';
        \i extensions/pg_gitversion/sql/install.sql
    ELSE
        RAISE NOTICE 'Database versioning already installed';
    END IF;
END \$\$;
"

# Step 2: Apply SQL schema files
echo -e "\n2. Applying SQL schema files..."
for sql_file in $SQL_DIR/*.sql; do
    if [ -f "$sql_file" ]; then
        base_name=$(basename "$sql_file" .sql)
        
        echo "   Processing $sql_file..."
        
        # Apply schema with versioning
        psql -U $DB_USER -d $DB_NAME <<EOF
-- Apply the schema with full versioning
DO \$\$
DECLARE
    v_result RECORD;
    v_failed BOOLEAN := FALSE;
BEGIN
    RAISE NOTICE 'Applying schema: %', '$base_name';
    
    -- Execute SQL file
    \i $sql_file
    
    -- Check for any errors in versioning
    FOR v_result IN 
        SELECT * FROM gitversion.get_recent_changes(5)
    LOOP
        RAISE NOTICE '   % - %: %', 
            v_result.change_type, 
            v_result.object_type, 
            v_result.full_name;
    END LOOP;
END \$\$;
EOF
    fi
done

# Step 3: Run pgTAP tests
echo -e "\n3. Running pgTAP tests..."

# First, generate version-aware tests
echo "   Generating version tests..."
psql -U $DB_USER -d $DB_NAME -t -c "SELECT gitversion.generate_version_tests();" > /tmp/version_tests.sql

# Run all tests including generated ones
pg_prove -U $DB_USER -d $DB_NAME \
    $TEST_DIR/*.sql \
    /tmp/version_tests.sql \
    sql/007_pgtap_examples.sql

# Step 4: Record test results
echo -e "\n4. Recording test results in versioning system..."
TEST_RESULTS=$(pg_prove -U $DB_USER -d $DB_NAME --quiet --failures $TEST_DIR/*.sql 2>&1 || true)
PASSED=$(echo "$TEST_RESULTS" | grep -oP '\d+(?= passed)' || echo "0")
FAILED=$(echo "$TEST_RESULTS" | grep -oP '\d+(?= failed)' || echo "0")

psql -U $DB_USER -d $DB_NAME <<EOF
SELECT gitversion.record_test_run(
    'ci_pipeline_tests',
    $PASSED,
    $FAILED,
    0,
    \$\$${TEST_RESULTS}\$\$
);
EOF

# Step 5: Version compatibility check
echo -e "\n5. Checking version compatibility..."
psql -U $DB_USER -d $DB_NAME <<'EOF'
DO $$
DECLARE
    v_compatible BOOLEAN;
    v_report RECORD;
BEGIN
    -- Check if current schema version has passing tests
    v_compatible := gitversion.has_passing_tests(0.95);
    
    IF NOT v_compatible THEN
        RAISE WARNING 'Current schema version does not have sufficient test coverage';
        
        -- Show recent test failures
        RAISE NOTICE 'Recent test results:';
        FOR v_report IN 
            SELECT * FROM gitversion.test_runs 
            ORDER BY run_at DESC 
            LIMIT 5
        LOOP
            RAISE NOTICE '   % - Passed: %, Failed: %', 
                v_report.run_at, v_report.passed, v_report.failed;
        END LOOP;
    END IF;
    
    -- Generate version report
    RAISE NOTICE E'\nVersion Report:';
    FOR v_report IN 
        SELECT * FROM gitversion.generate_version_report('public')
    LOOP
        RAISE NOTICE '% : %', v_report.report_section, v_report.report_data;
    END LOOP;
END $$;
EOF

# Step 6: Generate migration script for production
echo -e "\n6. Generating production migration..."
MIGRATION_FILE="/tmp/migration_$(date +%Y%m%d_%H%M%S).sql"

psql -U $DB_USER -d $DB_NAME -t -c "
SELECT gitversion.generate_migration(
    'release_$(date +%Y%m%d_%H%M%S)',
    'Auto-generated from CI pipeline'
);" > "$MIGRATION_FILE"

echo "   Migration saved to: $MIGRATION_FILE"

# Step 7: Final status check
echo -e "\n7. Final status check..."
if [ "$FAILED" -gt 0 ]; then
    echo "❌ Pipeline FAILED - $FAILED tests failed"
    exit 1
else
    echo "✅ Pipeline PASSED - All tests passed"
    
    # Show version summary
    psql -U $DB_USER -d $DB_NAME -c "
    SELECT 
        object_type,
        COUNT(*) as count,
        AVG(version) as avg_version,
        MAX(version) as max_version
    FROM gitversion.objects
    WHERE is_active = true
    GROUP BY object_type
    ORDER BY object_type;"
fi

echo -e "\n=== Pipeline Complete ===="