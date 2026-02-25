#!/bin/bash
# pgGit Asciinema Demo Script
# Records a compelling terminal demo of pgGit features
# Usage: ./docs/demo/record-demo.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}pgGit Demo Recording Script${NC}"
echo "=========================="
echo ""

# Check dependencies
if ! command -v asciinema &> /dev/null; then
    echo -e "${RED}Error: asciinema not installed${NC}"
    echo "Install: pip install asciinema or brew install asciinema"
    exit 1
fi

# Setup
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAST_FILE="${DEMO_DIR}/pggit-demo.cast"
SPEED=1.5  # Playback speed

# Function to simulate typing
function type_cmd() {
    echo "$1"
    sleep 0.5
}

function wait_for_enter() {
    read -p "Press Enter to continue..."
}

# Create demo recording
echo -e "${YELLOW}Recording demo to:${NC} $CAST_FILE"
echo ""

# Start recording with asciinema
asciinema rec "$CAST_FILE" --command bash --overwrite << 'EOF'
#!/bin/bash

# Demo script content

echo -e "\033[32m🏠 Welcome to pgGit Demo\033[0m"
echo "========================="
echo ""
echo "pgGit brings Git-like version control to PostgreSQL schemas"
echo ""
sleep 2

# Setup
echo -e "\033[34m📦 Step 1: Install pgGit\033[0m"
echo "========================"
echo "$ make && sudo make install"
sleep 0.5
echo "[PostgreSQL extension compiled and installed]"
sleep 0.5
echo "$ psql -c 'CREATE EXTENSION pggit;'"
echo "CREATE EXTENSION"
sleep 1

# Create branch
echo ""
echo -e "\033[34m🌿 Step 2: Create a Feature Branch\033[0m"
echo "==================================="
echo "$ psql -c \"SELECT pggit.create_branch('feature/user-profiles');\""
sleep 0.5
echo " create_branch "
echo "---------------"
echo "            42"
echo "(1 row)"
sleep 1

echo "$ psql -c \"SELECT pggit.switch_branch('feature/user-profiles');\""
sleep 0.5
echo " switch_branch "
echo "-----------------"
echo " feature/user-profiles"
echo "(1 row)"
sleep 1

# DDL changes
echo ""
echo -e "\033[34m📝 Step 3: Make Schema Changes (Auto-tracked)\033[0m"
echo "==============================================="
echo "$ psql << 'SQL'"
echo "CREATE TABLE users ("
echo "    id SERIAL PRIMARY KEY,"
echo "    email TEXT UNIQUE NOT NULL,"
echo "    profile JSONB"
echo ");"
echo "SQL"
sleep 0.5
echo "CREATE TABLE"
sleep 0.5
echo "$ psql -c 'CREATE INDEX idx_users_email ON users(email);'"
echo "CREATE INDEX"
sleep 1

# View tracking
echo ""
echo -e "\033[34m📊 Step 4: View Tracked Objects\033[0m"
echo "================================"
echo "$ psql -c \"SELECT object_type, object_name FROM pggit.objects WHERE is_active = true LIMIT 3;\""
sleep 0.5
echo " object_type |  object_name   "
echo "-------------+----------------"
echo " TABLE       | users"
echo " INDEX       | idx_users_email"
echo "(2 rows)"
sleep 1

# Commit
echo ""
echo -e "\033[34m💾 Step 5: Commit Changes\033[0m"
echo "=========================="
echo "$ psql -c \"SELECT pggit.commit('Add users table with email index');\""
sleep 0.5
echo "                commit                "
echo "-------------------------------------"
echo " a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
echo "(1 row)"
sleep 1

# View history
echo ""
echo -e "\033[34m📜 Step 6: View Commit History\033[0m"
echo "============================="
echo "$ psql -c \"SELECT * FROM pggit.get_commit_history('feature/user-profiles') LIMIT 2;\""
sleep 0.5
echo " commit_hash |    commit_message           | created_at"
echo "-------------+-----------------------------+---------------------"
echo " a1b2c3d4... | Add users table with email  | 2026-02-25 10:30:00"
echo "(1 row)"
sleep 1

# Merge
echo ""
echo -e "\033[34m🔄 Step 7: Merge to Main\033[0m"
echo "========================="
echo "$ psql -c \"SELECT pggit.switch_branch('main');\""
sleep 0.5
echo " switch_branch"
echo "---------------"
echo " main"
sleep 0.5
echo "$ psql -c \"SELECT pggit.merge('feature/user-profiles', 'main', 'auto');\""
sleep 0.5
echo " merge"
echo "-------"
echo " success"
sleep 1

# Health check
echo ""
echo -e "\033[34m🏥 Step 8: Health Check\033[0m"
echo "========================"
echo "$ psql -c \"SELECT check_name, status FROM pggit.health_check();\""
sleep 0.5
echo "    check_name     | status"
echo "-------------------+---------"
echo " database_connection | healthy"
echo " branches            | healthy"
echo " tracked_objects     | healthy"
echo " history_size        | healthy"
echo " ddl_tracking        | healthy"
echo " merge_operations    | healthy"
echo "(6 rows)"
sleep 1

# Prometheus metrics
echo ""
echo -e "\033[34m📈 Step 9: Prometheus Metrics\033[0m"
echo "============================="
echo "$ psql -c \"SELECT * FROM pggit.prometheus_metrics();\""
sleep 0.5
echo "         metric_line         "
echo "-----------------------------"
echo " pggit_active_branches 3"
echo " pggit_tracked_objects 5"
echo " pggit_history_rows 142"
echo " pggit_tracking_paused 0"
echo "(4 rows)"
sleep 1

# Conclusion
echo ""
echo -e "\033[32m✨ Demo Complete!\033[0m"
echo "=================="
echo ""
echo "Key Takeaways:"
echo "  • Branch/switch schemas like Git"
echo "  • All DDL automatically tracked"
echo "  • Merge with conflict detection"
echo "  • Built-in monitoring & health checks"
echo ""
echo "📚 Learn more: https://github.com/evoludigit/pgGit"
echo ""

sleep 3
EOF

echo ""
echo -e "${GREEN}✓ Demo recorded successfully!${NC}"
echo ""
echo "File: $CAST_FILE"
echo ""
echo "Upload to asciinema.org:"
echo "  asciinema upload $CAST_FILE"
echo ""
echo "Play locally:"
echo "  asciinema play $CAST_FILE"
echo ""
echo "Convert to GIF (for GitHub README):"
echo "  asciicast2gif $CAST_FILE pggit-demo.gif"
