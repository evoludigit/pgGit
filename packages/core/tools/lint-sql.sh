#!/usr/bin/env bash
# SQL lint pass: check for archaeology markers in SQL files.
# Usage: lint-sql.sh <sql_dir>
set -euo pipefail

SQL_DIR="${1:?Usage: $0 <sql_dir>}"
FAILURES=0

# Fail on development archaeology markers
PATTERNS=(
    'TODO'
    'FIXME'
    'HACK'
    'XXX'
    'RAISE NOTICE'
    'Phase [0-9]'
    '-- DEBUG'
)

for pattern in "${PATTERNS[@]}"; do
    if grep -rn --include='*.sql' "$pattern" "$SQL_DIR" 2>/dev/null; then
        echo "LINT FAILURE: found '$pattern' in SQL files" >&2
        FAILURES=$((FAILURES + 1))
    fi
done

if [[ $FAILURES -gt 0 ]]; then
    echo "$FAILURES lint failure(s) found" >&2
    exit 1
fi

echo "SQL lint clean."
