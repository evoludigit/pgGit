#!/usr/bin/env bash
# Uninstall pggit core from a development database.
# Usage: uninstall-dev.sh [dbname]
set -euo pipefail

DB="${1:-pggit_dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(dirname "$SCRIPT_DIR")"

echo "Uninstalling pggit core from database: $DB"
psql -v ON_ERROR_STOP=1 -d "$DB" -f "$CORE_DIR/sql/uninstall/0000-drop-all.sql"
echo "Uninstall complete."
