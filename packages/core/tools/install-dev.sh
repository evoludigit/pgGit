#!/usr/bin/env bash
# Install pggit core into a local development database.
# Usage: install-dev.sh [dbname]
set -euo pipefail

DB="${1:-pggit_dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(dirname "$SCRIPT_DIR")"

echo "Installing pggit core into database: $DB"

for f in "$CORE_DIR"/sql/install/*.sql; do
    echo "  Applying: $(basename "$f")"
    psql -v ON_ERROR_STOP=1 -d "$DB" -f "$f"
done

echo "Install complete."
