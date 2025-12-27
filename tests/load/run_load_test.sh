#!/bin/bash

# Load Testing Helper Script
# ==========================
#
# Usage: ./run_load_test.sh [scenario] [options]
#
# Examples:
#   ./run_load_test.sh smoke_test
#   ./run_load_test.sh peak_load --users 100 --spawn-rate 10
#   ./run_load_test.sh normal_load --run-time 10m --csv results/test1

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
LOCUSTFILE="$SCRIPT_DIR/locustfile.py"

# Create results directory if it doesn't exist
mkdir -p "$RESULTS_DIR"

# Default values
SCENARIO="${1:-smoke_test}"
API_HOST="${API_HOST:-http://localhost:8000}"
USERS=10
SPAWN_RATE=2
RUN_TIME="5m"
CSV_OUTPUT=""
HEADLESS=true
TAG=""

# Parse remaining arguments
shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --users)
            USERS="$2"
            shift 2
            ;;
        --spawn-rate)
            SPAWN_RATE="$2"
            shift 2
            ;;
        --run-time)
            RUN_TIME="$2"
            shift 2
            ;;
        --csv)
            CSV_OUTPUT="$2"
            shift 2
            ;;
        --web)
            HEADLESS=false
            shift
            ;;
        --tags)
            TAG="--tags $2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Print test configuration
echo -e "${GREEN}=================================${NC}"
echo -e "${GREEN}PGGIT Load Test Configuration${NC}"
echo -e "${GREEN}=================================${NC}"
echo "Scenario: $SCENARIO"
echo "API Host: $API_HOST"
echo "Users: $USERS"
echo "Spawn Rate: $SPAWN_RATE/second"
echo "Duration: $RUN_TIME"
if [ -n "$CSV_OUTPUT" ]; then
    echo "CSV Output: $CSV_OUTPUT"
fi
if [ "$HEADLESS" = true ]; then
    echo "Mode: Headless (automated)"
else
    echo "Mode: Web UI (interactive)"
fi
echo -e "${GREEN}=================================${NC}\n"

# Verify Locust is installed
if ! command -v locust &> /dev/null; then
    echo -e "${RED}Error: Locust is not installed${NC}"
    echo "Install with: pip install locust"
    exit 1
fi

# Verify API is running
echo "Checking API connectivity..."
if ! curl -s -f "$API_HOST/health" > /dev/null 2>&1; then
    echo -e "${RED}Error: API is not responding at $API_HOST${NC}"
    echo "Start the API with: uvicorn api.main:app --host 0.0.0.0 --port 8000"
    exit 1
fi
echo -e "${GREEN}✓ API is responding${NC}\n"

# Build Locust command
LOCUST_CMD="locust -f $LOCUSTFILE"

if [ "$HEADLESS" = true ]; then
    LOCUST_CMD="$LOCUST_CMD --headless"
fi

LOCUST_CMD="$LOCUST_CMD -u $USERS -r $SPAWN_RATE --run-time $RUN_TIME"

if [ -n "$CSV_OUTPUT" ]; then
    LOCUST_CMD="$LOCUST_CMD --csv=$CSV_OUTPUT"
fi

if [ -n "$TAG" ]; then
    LOCUST_CMD="$LOCUST_CMD $TAG"
fi

# Add host
LOCUST_CMD="$LOCUST_CMD --host=$API_HOST"

# Run the load test
echo -e "${YELLOW}Starting load test...${NC}\n"
eval "$LOCUST_CMD"

# Check if test completed successfully
if [ $? -eq 0 ] && [ "$HEADLESS" = true ]; then
    echo -e "\n${GREEN}✓ Load test completed successfully${NC}\n"

    # Print results summary
    if [ -n "$CSV_OUTPUT" ]; then
        STATS_FILE="${CSV_OUTPUT}_stats.csv"
        if [ -f "$STATS_FILE" ]; then
            echo -e "${GREEN}=== Test Results Summary ===${NC}"
            echo ""
            # Extract and display top endpoints by request count
            echo "Top endpoints by request count:"
            head -6 "$STATS_FILE" | tail -5 | awk -F',' '{print $1, "(" $2 " requests)"}'
            echo ""
        fi
    fi

    echo -e "${GREEN}Results saved to: $RESULTS_DIR${NC}"
    echo ""
    echo "To analyze results:"
    echo "  - CSV statistics: ${CSV_OUTPUT}_stats.csv"
    echo "  - CSV history: ${CSV_OUTPUT}_stats_history.csv"
    echo "  - CSV failures: ${CSV_OUTPUT}_failures.csv"
else
    if [ "$HEADLESS" = false ]; then
        echo -e "\n${GREEN}Web UI is running at http://localhost:8089${NC}"
        echo "Press Ctrl+C to stop"
    fi
fi
