#!/bin/bash
# pggit Chaos Engineering Toolkit
# Real fault injection for production resilience testing

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CHAOS_CONTAINER="${CHAOS_CONTAINER:-pggit-chaos-test}"
DB_NAME="${DB_NAME:-chaos_test}"
LOG_FILE="${LOG_FILE:-/tmp/pggit-chaos-$(date +%Y%m%d-%H%M%S).log}"

# Logging function
log() {
    local level=$1
    shift
    echo -e "${level}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

# Usage information
usage() {
    cat << EOF
pggit Chaos Engineering Toolkit

Usage: $0 <fault-type> [options]

Fault Types:
    kill-primary        Kill primary database process
    network-partition   Create network partition
    disk-full          Fill disk to specified percentage
    memory-pressure    Create memory pressure
    cpu-spike          Create CPU spike
    io-latency         Add I/O latency
    corrupt-data       Corrupt random data pages
    clock-skew         Introduce clock skew
    connection-storm   Create connection storm
    deadlock-storm     Create intentional deadlocks

Options:
    --duration=SECONDS  Duration of fault (default: 30)
    --intensity=LEVEL   Intensity level 1-10 (default: 5)
    --target=CONTAINER  Target container (default: pggit-chaos-test)
    --measure           Measure impact on pggit operations

Examples:
    $0 network-partition --duration=60
    $0 disk-full --intensity=9 --measure
    $0 kill-primary --measure

EOF
    exit 1
}

# Parse command line arguments
parse_args() {
    FAULT_TYPE="${1:-}"
    shift || true
    
    DURATION=30
    INTENSITY=5
    MEASURE=false
    
    for arg in "$@"; do
        case $arg in
            --duration=*)
                DURATION="${arg#*=}"
                ;;
            --intensity=*)
                INTENSITY="${arg#*=}"
                ;;
            --target=*)
                CHAOS_CONTAINER="${arg#*=}"
                ;;
            --measure)
                MEASURE=true
                ;;
            *)
                log "$RED" "Unknown option: $arg"
                usage
                ;;
        esac
    done
}

# Verify container is running
verify_container() {
    if ! podman ps --format "{{.Names}}" | grep -q "^${CHAOS_CONTAINER}$"; then
        log "$RED" "Container $CHAOS_CONTAINER is not running!"
        log "$YELLOW" "Starting test container..."
        start_test_environment
    fi
}

# Start test environment
start_test_environment() {
    log "$BLUE" "Starting PostgreSQL test environment..."
    
    # Create network for testing
    podman network create pggit-chaos-net 2>/dev/null || true
    
    # Start PostgreSQL container
    podman run -d \
        --name "$CHAOS_CONTAINER" \
        --network pggit-chaos-net \
        -e POSTGRES_PASSWORD=postgres \
        -e POSTGRES_DB="$DB_NAME" \
        -v $(pwd):/pggit:ro \
        --memory=2g \
        --cpus=2 \
        postgres:17
    
    # Wait for PostgreSQL to be ready
    log "$BLUE" "Waiting for PostgreSQL to start..."
    sleep 10
    
    # Install pggit
    podman exec "$CHAOS_CONTAINER" bash -c "
        apt-get update -qq && \
        apt-get install -y -qq postgresql-server-dev-17 make gcc stress-ng iperf3 > /dev/null 2>&1
    "
    
    podman exec -w /pggit "$CHAOS_CONTAINER" make install
    podman exec -u postgres "$CHAOS_CONTAINER" psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS pggit CASCADE;"
    
    # Create test data
    create_test_data
}

# Create test data for chaos testing
create_test_data() {
    log "$BLUE" "Creating test data..."
    
    podman exec -u postgres "$CHAOS_CONTAINER" psql -d "$DB_NAME" << 'EOF'
-- Create test tables
CREATE TABLE IF NOT EXISTS chaos_test_users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE,
    data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS chaos_test_orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES chaos_test_users(id),
    total DECIMAL(10,2),
    status VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert test data
INSERT INTO chaos_test_users (email, data)
SELECT 
    'user' || i || '@chaos.test',
    jsonb_build_object('name', 'User ' || i, 'preferences', '{}')
FROM generate_series(1, 10000) i
ON CONFLICT DO NOTHING;

INSERT INTO chaos_test_orders (user_id, total, status)
SELECT 
    (random() * 9999 + 1)::INTEGER,
    (random() * 1000)::DECIMAL(10,2),
    CASE (random() * 3)::INTEGER
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'completed'
        ELSE 'cancelled'
    END
FROM generate_series(1, 50000) i;

-- Create pggit branches for testing
SELECT pggit.create_branch('chaos-test-1');
SELECT pggit.create_branch('chaos-test-2');
EOF
}

# Measure pggit operations during chaos
measure_operations() {
    log "$BLUE" "Measuring pggit operations during chaos..."
    
    # Start measurement script in background
    (
        while true; do
            # Measure branch creation time
            START=$(date +%s.%N)
            podman exec -u postgres "$CHAOS_CONTAINER" psql -d "$DB_NAME" -c \
                "SELECT pggit.create_branch('measure-' || extract(epoch from now())::text);" \
                > /dev/null 2>&1 || echo "Branch creation failed"
            END=$(date +%s.%N)
            DURATION=$(echo "$END - $START" | bc)
            echo "$(date +%s),branch_create,$DURATION" >> "$LOG_FILE.metrics"
            
            # Measure query performance
            START=$(date +%s.%N)
            podman exec -u postgres "$CHAOS_CONTAINER" psql -d "$DB_NAME" -c \
                "SELECT COUNT(*) FROM chaos_test_orders WHERE status = 'completed';" \
                > /dev/null 2>&1 || echo "Query failed"
            END=$(date +%s.%N)
            DURATION=$(echo "$END - $START" | bc)
            echo "$(date +%s),query_performance,$DURATION" >> "$LOG_FILE.metrics"
            
            sleep 1
        done
    ) &
    MEASURE_PID=$!
    echo $MEASURE_PID > "$LOG_FILE.measure.pid"
}

# Stop measurement
stop_measurement() {
    if [ -f "$LOG_FILE.measure.pid" ]; then
        kill $(cat "$LOG_FILE.measure.pid") 2>/dev/null || true
        rm -f "$LOG_FILE.measure.pid"
        
        # Analyze metrics
        if [ -f "$LOG_FILE.metrics" ]; then
            log "$GREEN" "Performance impact analysis:"
            awk -F, '
                {
                    if ($2 == "branch_create") bc_sum += $3; bc_count++
                    if ($2 == "query_performance") qp_sum += $3; qp_count++
                }
                END {
                    if (bc_count > 0) printf "  Average branch creation time: %.3fs\n", bc_sum/bc_count
                    if (qp_count > 0) printf "  Average query time: %.3fs\n", qp_sum/qp_count
                }
            ' "$LOG_FILE.metrics"
        fi
    fi
}

# Fault injection functions

fault_kill_primary() {
    log "$RED" "🔥 CHAOS: Killing primary database process..."
    
    # Find and kill postgres process
    podman exec "$CHAOS_CONTAINER" bash -c "
        PID=\$(ps aux | grep 'postgres.*writer' | grep -v grep | awk '{print \$2}' | head -1)
        if [ -n \"\$PID\" ]; then
            kill -9 \$PID
            echo 'Killed postgres process \$PID'
        fi
    "
    
    # PostgreSQL should auto-restart, measure recovery time
    START=$(date +%s)
    while ! podman exec -u postgres "$CHAOS_CONTAINER" pg_isready -d "$DB_NAME" > /dev/null 2>&1; do
        sleep 1
    done
    END=$(date +%s)
    
    log "$GREEN" "✓ Database recovered in $((END - START)) seconds"
}

fault_network_partition() {
    log "$RED" "🔥 CHAOS: Creating network partition for $DURATION seconds..."
    
    # Block incoming connections
    podman exec "$CHAOS_CONTAINER" iptables -A INPUT -p tcp --dport 5432 -j DROP
    
    sleep "$DURATION"
    
    # Restore network
    podman exec "$CHAOS_CONTAINER" iptables -D INPUT -p tcp --dport 5432 -j DROP
    
    log "$GREEN" "✓ Network partition resolved"
}

fault_disk_full() {
    local target_percent=$((90 + INTENSITY))
    log "$RED" "🔥 CHAOS: Filling disk to ${target_percent}%..."
    
    # Create large file to fill disk
    podman exec "$CHAOS_CONTAINER" bash -c "
        # Get available space
        AVAILABLE=\$(df /var/lib/postgresql | tail -1 | awk '{print \$4}')
        FILL_SIZE=\$((AVAILABLE * $target_percent / 100))
        
        # Create file
        dd if=/dev/zero of=/tmp/chaos_disk_fill bs=1K count=\$FILL_SIZE 2>/dev/null
        
        # Show disk usage
        df -h /var/lib/postgresql
    "
    
    sleep "$DURATION"
    
    # Clean up
    podman exec "$CHAOS_CONTAINER" rm -f /tmp/chaos_disk_fill
    
    log "$GREEN" "✓ Disk space restored"
}

fault_memory_pressure() {
    local memory_percent=$((50 + INTENSITY * 5))
    log "$RED" "🔥 CHAOS: Creating memory pressure (${memory_percent}% usage)..."
    
    # Use stress-ng to consume memory
    podman exec "$CHAOS_CONTAINER" stress-ng \
        --vm 2 \
        --vm-bytes ${memory_percent}% \
        --timeout ${DURATION}s \
        > /dev/null 2>&1 &
    
    wait
    
    log "$GREEN" "✓ Memory pressure released"
}

fault_cpu_spike() {
    local cpu_workers=$((INTENSITY))
    log "$RED" "🔥 CHAOS: Creating CPU spike with $cpu_workers workers..."
    
    # Use stress-ng for CPU load
    podman exec "$CHAOS_CONTAINER" stress-ng \
        --cpu "$cpu_workers" \
        --timeout ${DURATION}s \
        > /dev/null 2>&1 &
    
    wait
    
    log "$GREEN" "✓ CPU load normalized"
}

fault_io_latency() {
    local latency_ms=$((10 * INTENSITY))
    log "$RED" "🔥 CHAOS: Adding ${latency_ms}ms I/O latency..."
    
    # Use tc to add latency (requires NET_ADMIN capability)
    podman exec "$CHAOS_CONTAINER" tc qdisc add dev lo root netem delay ${latency_ms}ms
    
    sleep "$DURATION"
    
    # Remove latency
    podman exec "$CHAOS_CONTAINER" tc qdisc del dev lo root netem
    
    log "$GREEN" "✓ I/O latency removed"
}

fault_connection_storm() {
    local connections=$((100 * INTENSITY))
    log "$RED" "🔥 CHAOS: Creating connection storm with $connections connections..."
    
    # Create many connections
    for i in $(seq 1 $connections); do
        podman exec -u postgres "$CHAOS_CONTAINER" psql -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1 &
    done
    
    sleep "$DURATION"
    
    # Connections will auto-close
    log "$GREEN" "✓ Connection storm subsided"
}

fault_deadlock_storm() {
    log "$RED" "🔥 CHAOS: Creating intentional deadlocks..."
    
    # Create competing transactions
    for i in $(seq 1 $INTENSITY); do
        (
            podman exec -u postgres "$CHAOS_CONTAINER" psql -d "$DB_NAME" << EOF &
BEGIN;
UPDATE chaos_test_users SET data = '{}' WHERE id = $i;
SELECT pg_sleep(1);
UPDATE chaos_test_users SET data = '{}' WHERE id = $(($i + 1));
COMMIT;
EOF
        ) &
        
        (
            podman exec -u postgres "$CHAOS_CONTAINER" psql -d "$DB_NAME" << EOF &
BEGIN;
UPDATE chaos_test_users SET data = '{}' WHERE id = $(($i + 1));
SELECT pg_sleep(1);
UPDATE chaos_test_users SET data = '{}' WHERE id = $i;
COMMIT;
EOF
        ) &
    done
    
    wait
    
    log "$GREEN" "✓ Deadlock storm completed"
}

# Cleanup function
cleanup() {
    log "$YELLOW" "Cleaning up..."
    stop_measurement
    
    if [ "$CHAOS_CONTAINER" != "production" ]; then
        podman stop "$CHAOS_CONTAINER" 2>/dev/null || true
        podman rm "$CHAOS_CONTAINER" 2>/dev/null || true
    fi
    
    log "$GREEN" "✓ Cleanup complete. Logs saved to: $LOG_FILE"
}

# Main execution
main() {
    # Setup signal handlers
    trap cleanup EXIT INT TERM
    
    # Parse arguments
    parse_args "$@"
    
    if [ -z "$FAULT_TYPE" ]; then
        usage
    fi
    
    # Start logging
    log "$BLUE" "=== pggit Chaos Engineering Test ==="
    log "$BLUE" "Fault Type: $FAULT_TYPE"
    log "$BLUE" "Duration: ${DURATION}s"
    log "$BLUE" "Intensity: $INTENSITY/10"
    log "$BLUE" "Target: $CHAOS_CONTAINER"
    
    # Verify environment
    verify_container
    
    # Start measurement if requested
    if [ "$MEASURE" = true ]; then
        measure_operations
    fi
    
    # Execute fault injection
    case "$FAULT_TYPE" in
        kill-primary)
            fault_kill_primary
            ;;
        network-partition)
            fault_network_partition
            ;;
        disk-full)
            fault_disk_full
            ;;
        memory-pressure)
            fault_memory_pressure
            ;;
        cpu-spike)
            fault_cpu_spike
            ;;
        io-latency)
            fault_io_latency
            ;;
        connection-storm)
            fault_connection_storm
            ;;
        deadlock-storm)
            fault_deadlock_storm
            ;;
        *)
            log "$RED" "Unknown fault type: $FAULT_TYPE"
            usage
            ;;
    esac
    
    # Stop measurement
    if [ "$MEASURE" = true ]; then
        sleep 2  # Allow final measurements
        stop_measurement
    fi
    
    log "$GREEN" "✓ Chaos test completed successfully!"
}

# Run main function
main "$@"