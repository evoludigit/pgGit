#!/bin/bash
# scripts/chaos/disk-pressure.sh

echo "🔥 Chaos Test: Disk pressure simulation"

# Fill up 80% of /tmp
AVAILABLE=$(df /tmp | tail -1 | awk '{print $4}')
FILL_SIZE=$((AVAILABLE * 8 / 10))

echo "Filling ${FILL_SIZE}KB on /tmp"
dd if=/dev/zero of=/tmp/chaos-fill bs=1K count=$FILL_SIZE 2>/dev/null

# Try pgGit operations under pressure
if psql -c "CREATE TABLE chaos_test (id INT)"; then
    echo "✅ PASS: DDL operations work under disk pressure"
    psql -c "DROP TABLE chaos_test"
else
    echo "⚠️  WARNING: DDL failed under disk pressure"
fi

# Cleanup
rm -f /tmp/chaos-fill
echo "Chaos test complete"