#!/bin/bash
# scripts/chaos/kill-connections.sh

echo "🔥 Chaos Test: Killing random database connections"

# Get random connection PIDs
PIDS=$(psql -t -c "
    SELECT pid
    FROM pg_stat_activity
    WHERE datname = current_database()
    AND pid != pg_backend_pid()
    ORDER BY random()
    LIMIT 3
")

for PID in $PIDS; do
    echo "Terminating connection PID: $PID"
    psql -c "SELECT pg_terminate_backend($PID)"
    sleep 1
done

# Verify pgGit still works
echo "Verifying pgGit health..."
if psql -c "SELECT * FROM pggit.health_check()" | grep -q "healthy"; then
    echo "✅ PASS: pgGit recovered from connection kills"
else
    echo "❌ FAIL: pgGit health check failed"
    exit 1
fi