#!/usr/bin/env bash
# Run pgTAP tests against a target database.
# Usage: run-pgtap.sh <dbname> <test_dir>
set -euo pipefail

DB="${1:?Usage: $0 <dbname> <test_dir>}"
TEST_DIR="${2:?Usage: $0 <dbname> <test_dir>}"

if [[ ! -d "$TEST_DIR" ]]; then
    echo "ERROR: test directory '$TEST_DIR' not found" >&2
    exit 1
fi

FAILURES=0

for f in "$TEST_DIR"/*.sql; do
    [[ -f "$f" ]] || continue
    echo "--- Running: $f"

    # Capture output and exit code separately.
    # Tests wrap themselves in BEGIN/ROLLBACK so errors abort the transaction;
    # psql exits non-zero on any ERROR when ON_ERROR_STOP is set.
    output=$(psql -v ON_ERROR_STOP=1 -d "$DB" -f "$f" 2>&1) && psql_rc=0 || psql_rc=$?
    echo "$output"

    if [[ $psql_rc -ne 0 ]] || echo "$output" | grep -qE 'not ok|# Looks like you failed|# Looks like you planned'; then
        echo "FAIL: $f" >&2
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $f"
    fi
done

if [[ $FAILURES -gt 0 ]]; then
    echo "FAILED: $FAILURES test file(s) had failures" >&2
    exit 1
fi

echo "All tests passed."
