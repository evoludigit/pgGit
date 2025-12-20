#!/bin/bash
# pgGit Upgrade Path Test
# Tests upgrading from 0.1.0 to 0.2.0 and back
# Run with: bash tests/upgrade/test-upgrade-path.sh

set -e

echo "🧪 Testing pgGit Upgrade Path: 0.1.0 → 0.2.0 → 0.1.0"
echo "==================================================="

TEST_DB="upgrade_test_$(date +%s)"
PG_USER="${PG_USER:-postgres}"

echo "Using test database: $TEST_DB"

# Cleanup function
cleanup() {
    echo "🧹 Cleaning up..."
    psql -U "$PG_USER" -h localhost -c "DROP DATABASE IF EXISTS $TEST_DB;" 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup EXIT

# Step 1: Setup test database with 0.1.0
echo ""
echo "📦 Step 1: Installing pgGit 0.1.0..."

psql -U "$PG_USER" -h localhost -c "CREATE DATABASE $TEST_DB;"

if [ -f "pggit--0.1.0.sql" ]; then
    psql -U "$PG_USER" -h localhost -d "$TEST_DB" -f pggit--0.1.0.sql
else
    echo "❌ pggit--0.1.0.sql not found"
    exit 1
fi

VERSION=$(psql -U "$PG_USER" -h localhost -d "$TEST_DB" -tA -c "SELECT pggit.version()")
echo "✅ Installed version: $VERSION"

if [ "$VERSION" != "0.1.0" ]; then
    echo "❌ Expected version 0.1.0, got $VERSION"
    exit 1
fi

# Step 2: Create test data
echo ""
echo "🗃️  Step 2: Creating test data..."

psql -U "$PG_USER" -h localhost -d "$TEST_DB" << 'EOF'
-- Create test table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert test data
INSERT INTO users (email) VALUES
    ('test1@example.com'),
    ('test2@example.com'),
    ('test3@example.com');

-- Create another table
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    amount DECIMAL(10,2),
    status TEXT DEFAULT 'pending'
);

-- Insert more data
INSERT INTO orders (user_id, amount) VALUES
    (1, 99.99),
    (2, 149.50),
    (1, 75.00);
EOF

# Check that data was created and tracked
OBJECT_COUNT=$(psql -U "$PG_USER" -h localhost -d "$TEST_DB" -tA -c "SELECT COUNT(*) FROM pggit.objects")
HISTORY_COUNT=$(psql -U "$PG_USER" -h localhost -d "$TEST_DB" -tA -c "SELECT COUNT(*) FROM pggit.history")

echo "✅ Created $OBJECT_COUNT objects"
echo "✅ Recorded $HISTORY_COUNT history entries"

# Step 3: Upgrade to 0.2.0
echo ""
echo "⬆️  Step 3: Upgrading to pgGit 0.2.0..."

if [ -f "migrations/pggit--0.1.0--0.2.0.sql" ]; then
    psql -U "$PG_USER" -h localhost -d "$TEST_DB" -f migrations/pggit--0.1.0--0.2.0.sql
else
    echo "❌ Upgrade script not found"
    exit 1
fi

VERSION=$(psql -U "$PG_USER" -h localhost -d "$TEST_DB" -tA -c "SELECT pggit.version()")
echo "✅ Upgraded to version: $VERSION"

if [ "$VERSION" != "0.2.0" ]; then
    echo "❌ Expected version 0.2.0, got $VERSION"
    exit 1
fi

# Step 4: Verify data integrity after upgrade
echo ""
echo "🔍 Step 4: Verifying data integrity..."

# Check that all objects still exist
NEW_OBJECT_COUNT=$(psql -U "$PG_USER" -h localhost -d "$TEST_DB" -tA -c "SELECT COUNT(*) FROM pggit.objects")
NEW_HISTORY_COUNT=$(psql -U "$PG_USER" -h localhost -d "$TEST_DB" -tA -c "SELECT COUNT(*) FROM pggit.history")

if [ "$NEW_OBJECT_COUNT" -lt "$OBJECT_COUNT" ]; then
    echo "❌ Object count decreased: $OBJECT_COUNT → $NEW_OBJECT_COUNT"
    exit 1
fi

if [ "$NEW_HISTORY_COUNT" -lt "$HISTORY_COUNT" ]; then
    echo "❌ History count decreased: $HISTORY_COUNT → $NEW_HISTORY_COUNT"
    exit 1
fi

echo "✅ Objects preserved: $OBJECT_COUNT → $NEW_OBJECT_COUNT"
echo "✅ History preserved: $HISTORY_COUNT → $NEW_HISTORY_COUNT"

# Check that tables still work
USER_COUNT=$(psql -U "$PG_USER" -h localhost -d "$TEST_DB" -tA -c "SELECT COUNT(*) FROM users")
ORDER_COUNT=$(psql -U "$PG_USER" -h localhost -d "$TEST_DB" -tA -c "SELECT COUNT(*) FROM orders")

if [ "$USER_COUNT" -ne 3 ] || [ "$ORDER_COUNT" -ne 3 ]; then
    echo "❌ Data corrupted during upgrade"
    echo "   Users: $USER_COUNT (expected 3)"
    echo "   Orders: $ORDER_COUNT (expected 3)"
    exit 1
fi

echo "✅ User data intact: $USER_COUNT users"
echo "✅ Order data intact: $ORDER_COUNT orders"

# Step 5: Downgrade back to 0.1.0
echo ""
echo "⬇️  Step 5: Downgrading back to pgGit 0.1.0..."

if [ -f "migrations/pggit--0.2.0--0.1.0.sql" ]; then
    psql -U "$PG_USER" -h localhost -d "$TEST_DB" -f migrations/pggit--0.2.0--0.1.0.sql
else
    echo "❌ Downgrade script not found"
    exit 1
fi

VERSION=$(psql -U "$PG_USER" -h localhost -d "$TEST_DB" -tA -c "SELECT pggit.version()")
echo "✅ Downgraded to version: $VERSION"

if [ "$VERSION" != "0.1.0" ]; then
    echo "❌ Expected version 0.1.0, got $VERSION"
    exit 1
fi

# Step 6: Final verification
echo ""
echo "🎯 Step 6: Final verification..."

FINAL_USER_COUNT=$(psql -U "$PG_USER" -h localhost -d "$TEST_DB" -tA -c "SELECT COUNT(*) FROM users")
FINAL_ORDER_COUNT=$(psql -U "$PG_USER" -h localhost -d "$TEST_DB" -tA -c "SELECT COUNT(*) FROM orders")

if [ "$FINAL_USER_COUNT" -ne 3 ] || [ "$FINAL_ORDER_COUNT" -ne 3 ]; then
    echo "❌ Data corrupted during downgrade"
    exit 1
fi

echo "✅ Final data integrity verified"
echo "   Users: $FINAL_USER_COUNT"
echo "   Orders: $FINAL_ORDER_COUNT"

# Check upgrade log
UPGRADE_COUNT=$(psql -U "$PG_USER" -h localhost -d "$TEST_DB" -tA -c "SELECT COUNT(*) FROM pggit.upgrade_log WHERE status = 'completed'")
echo "✅ Completed upgrades logged: $UPGRADE_COUNT"

echo ""
echo "🎉 UPGRADE PATH TEST PASSED!"
echo "============================="
echo "✅ 0.1.0 → 0.2.0 → 0.1.0 cycle successful"
echo "✅ Data integrity maintained throughout"
echo "✅ Upgrade/downgrade scripts working"
echo "✅ Version tracking accurate"