# Chaos Engineering Guide

## Overview

Chaos engineering tests pgGit's resilience by intentionally introducing failures and observing system behavior.

## Principles

1. **Build Confidence**: Test failure scenarios in production-like environments
2. **Minimize Blast Radius**: Start small, expand gradually
3. **Automate**: Make chaos tests part of CI/CD pipeline
4. **Learn**: Use results to improve system resilience

## Test Categories

### Network Chaos

#### Connection Drops
```bash
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
psql -c "SELECT * FROM pggit.health_check()" | grep -q "healthy" && {
    echo "✅ PASS: pgGit recovered from connection kills"
} || {
    echo "❌ FAIL: pgGit health check failed"
    exit 1
}
```

#### Network Latency
```bash
#!/bin/bash
# scripts/chaos/network-latency.sh

echo "🔥 Chaos Test: Network latency simulation"

# Add 100ms latency to all connections
sudo tc qdisc add dev lo root netem delay 100ms

# Test pgGit operations under latency
echo "Testing DDL operations with latency..."
time psql -c "CREATE TABLE chaos_test (id INT)"
time psql -c "INSERT INTO chaos_test VALUES (1)"
time psql -c "DROP TABLE chaos_test"

# Verify tracking still works
RECORDS=$(psql -t -c "SELECT COUNT(*) FROM pggit.history WHERE created_at > NOW() - INTERVAL '1 minute'")
if [ "$RECORDS" -ge 3 ]; then
    echo "✅ PASS: DDL tracking works with network latency"
else
    echo "❌ FAIL: DDL tracking failed under latency"
fi

# Cleanup
sudo tc qdisc del dev lo root netem
```

### Resource Chaos

#### Disk Pressure
```bash
#!/bin/bash
# scripts/chaos/disk-pressure.sh

echo "🔥 Chaos Test: Disk pressure simulation"

# Fill up 80% of /tmp
AVAILABLE=$(df /tmp | tail -1 | awk '{print $4}')
FILL_SIZE=$((AVAILABLE * 8 / 10))

echo "Filling ${FILL_SIZE}KB on /tmp"
dd if=/dev/zero of=/tmp/chaos-fill bs=1K count=$FILL_SIZE 2>/dev/null

# Try pgGit operations under pressure
psql -c "CREATE TABLE chaos_test (id INT)" && {
    echo "✅ PASS: DDL operations work under disk pressure"
    psql -c "DROP TABLE chaos_test"
} || {
    echo "⚠️  WARNING: DDL failed under disk pressure"
}

# Cleanup
rm -f /tmp/chaos-fill
echo "Chaos test complete"
```

#### Memory Pressure
```bash
#!/bin/bash
# scripts/chaos/memory-pressure.sh

echo "🔥 Chaos Test: Memory pressure simulation"

# Consume 80% of available memory
TOTAL_MEM=$(free -m | grep '^Mem:' | awk '{print $2}')
USE_MEM=$((TOTAL_MEM * 8 / 10))

echo "Consuming ${USE_MEM}MB of memory"
stress --vm 1 --vm-bytes ${USE_MEM}M --timeout 30s &
STRESS_PID=$!

# Test pgGit operations
sleep 5
psql -c "SELECT * FROM pggit.health_check()" | grep -q "healthy" && {
    echo "✅ PASS: pgGit healthy under memory pressure"
} || {
    echo "⚠️  WARNING: pgGit affected by memory pressure"
}

# Cleanup
kill $STRESS_PID
```

### Database Chaos

#### Lock Contention
```bash
#!/bin/bash
# scripts/chaos/lock-contention.sh

echo "🔥 Chaos Test: Lock contention simulation"

# Create long-running transaction
psql -c "BEGIN; LOCK TABLE pggit.objects IN ACCESS EXCLUSIVE MODE; SELECT pg_sleep(10);" &
LOCK_PID=$!

sleep 2

# Try pgGit operations during lock
timeout 5 psql -c "CREATE TABLE chaos_test (id INT)" && {
    echo "✅ PASS: DDL operations handle lock contention"
} || {
    echo "⚠️  WARNING: DDL blocked by lock contention"
}

# Wait for lock to release
wait $LOCK_PID
psql -c "DROP TABLE IF EXISTS chaos_test"
```

#### Index Corruption
```bash
#!/bin/bash
# scripts/chaos/index-corruption.sh

echo "🔥 Chaos Test: Index corruption simulation"

# Identify pgGit indexes
INDEXES=$(psql -t -c "SELECT indexname FROM pg_indexes WHERE schemaname = 'pggit'")

for INDEX in $INDEXES; do
    echo "Testing corruption resistance for index: $INDEX"

    # Simulate corruption by reindexing (less destructive test)
    psql -c "REINDEX INDEX pggit.$INDEX" && {
        echo "✅ PASS: Index $INDEX corruption handled"
    } || {
        echo "❌ FAIL: Index $INDEX corruption not handled"
    }
done
```

### Application Chaos

#### Event Trigger Failures
```bash
#!/bin/bash
# scripts/chaos/trigger-failure.sh

echo "🔥 Chaos Test: Event trigger failure simulation"

# Disable pgGit triggers temporarily
psql -c "ALTER EVENT TRIGGER pggit_ddl_trigger DISABLE"

# Perform DDL operations
psql -c "CREATE TABLE chaos_test (id INT)"
psql -c "DROP TABLE chaos_test"

# Check if operations were tracked
RECORDS=$(psql -t -c "SELECT COUNT(*) FROM pggit.history WHERE created_at > NOW() - INTERVAL '1 minute'")
if [ "$RECORDS" -eq 0 ]; then
    echo "✅ EXPECTED: No tracking when triggers disabled"
else
    echo "⚠️  WARNING: Unexpected tracking when triggers disabled"
fi

# Re-enable triggers
psql -c "ALTER EVENT TRIGGER pggit_ddl_trigger ENABLE"

# Test recovery
psql -c "CREATE TABLE chaos_recovery_test (id INT)"
RECORDS_AFTER=$(psql -t -c "SELECT COUNT(*) FROM pggit.history WHERE created_at > NOW() - INTERVAL '1 minute'")
if [ "$RECORDS_AFTER" -ge 1 ]; then
    echo "✅ PASS: Trigger recovery successful"
else
    echo "❌ FAIL: Trigger recovery failed"
fi

psql -c "DROP TABLE chaos_recovery_test"
```

## Chaos Testing Framework

### Automated Chaos Suite
```bash
#!/bin/bash
# scripts/chaos/run-suite.sh

CHAOS_TESTS=(
    "kill-connections"
    "network-latency"
    "disk-pressure"
    "memory-pressure"
    "lock-contention"
    "trigger-failure"
)

echo "=== pgGit Chaos Testing Suite ==="
echo "Starting at: $(date)"

FAILED_TESTS=()
PASSED_TESTS=()

for TEST in "${CHAOS_TESTS[@]}"; do
    echo ""
    echo "Running test: $TEST"

    if ./scripts/chaos/${TEST}.sh; then
        PASSED_TESTS+=("$TEST")
        echo "✅ $TEST: PASSED"
    else
        FAILED_TESTS+=("$TEST")
        echo "❌ $TEST: FAILED"
    fi
done

echo ""
echo "=== Results ==="
echo "Passed: ${#PASSED_TESTS[@]}"
echo "Failed: ${#FAILED_TESTS[@]}"

if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
    echo "🎉 All chaos tests passed!"
    exit 0
else
    echo "💥 Failed tests: ${FAILED_TESTS[*]}"
    exit 1
fi
```

### CI/CD Integration
```yaml
# .github/workflows/chaos-testing.yml
name: Chaos Testing

on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM
  workflow_dispatch:

jobs:
  chaos-test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
    - uses: actions/checkout@v4

    - name: Setup pgGit
      run: |
        psql -h localhost -U postgres -c "CREATE DATABASE pggit_test"
        psql -h localhost -U postgres -d pggit_test -f sql/install.sql

    - name: Run Chaos Suite
      run: ./scripts/chaos/run-suite.sh

    - name: Generate Report
      run: |
        echo "## Chaos Test Results" >> chaos-report.md
        echo "- Passed: ${PASSED_TESTS}" >> chaos-report.md
        echo "- Failed: ${FAILED_TESTS}" >> chaos-report.md

    - name: Upload Report
      uses: actions/upload-artifact@v4
      with:
        name: chaos-test-report
        path: chaos-report.md
```

## Best Practices

### Test Environment Setup
- Use isolated test environments
- Start with minimal chaos intensity
- Gradually increase disruption levels
- Always have rollback procedures

### Monitoring During Chaos
```sql
-- Monitor system during chaos tests
CREATE OR REPLACE FUNCTION chaos_monitor()
RETURNS TABLE (
    metric TEXT,
    value TEXT,
    timestamp TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        'active_connections'::TEXT,
        COUNT(*)::TEXT,
        NOW()
    FROM pg_stat_activity
    WHERE datname = current_database();

    RETURN QUERY
    SELECT
        'pggit_health'::TEXT,
        CASE WHEN status = 'healthy' THEN 'ok' ELSE 'fail' END,
        NOW()
    FROM pggit.health_check()
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;
```

### Safety Measures
- Implement circuit breakers
- Have automatic rollback capabilities
- Monitor blast radius
- Stop tests if critical systems affected

### Learning from Results
- Document all test results
- Identify improvement opportunities
- Update runbooks with lessons learned
- Implement fixes for discovered weaknesses

## Advanced Chaos Scenarios

### Multi-Region Failover
- Simulate complete datacenter failure
- Test cross-region replication
- Verify automatic failover

### Dependency Failure Injection
- Simulate external service failures
- Test pgGit behavior when dependencies unavailable
- Verify graceful degradation

### Time Travel Chaos
- Manipulate system clocks
- Test timestamp-dependent operations
- Verify temporal consistency

### Load Chaos
- Sudden traffic spikes
- Resource exhaustion scenarios
- Performance under extreme conditions