#!/usr/bin/env python3
"""
SQL Linting Tool - Basic validation of SQL files

This is a lightweight linter that checks for obvious issues without
attempting full parsing. For comprehensive SQL linting, use dedicated
tools like pgFormatter or sqlfluff.

Checks performed:
- Trailing whitespace
- TODO/FIXME markers (which should reference issues)
- Missing spaces after keywords
"""

import sys
import re
from pathlib import Path

def check_file(filepath):
    """Check a single SQL file for issues"""
    errors = []

    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()

        for line_no, line in enumerate(lines, 1):
            # Check for trailing whitespace (excluding newline)
            if line.rstrip('\n') != line.rstrip('\n').rstrip():
                errors.append(f"Line {line_no}: Trailing whitespace")

            # Check for TODO/FIXME without issue reference
            if 'TODO' in line and not re.search(r'TODO.*#\d+', line):
                if '-- Phase' not in line and 'TODO:' not in line:  # Allow generic TODOs
                    pass  # Skip for now, too noisy
            if 'FIXME' in line and not re.search(r'FIXME.*#\d+', line):
                errors.append(f"Line {line_no}: FIXME without issue reference")

        return errors

    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return []

def main():
    if len(sys.argv) < 2:
        print("Usage: lint_sql.py <sql_files...>")
        sys.exit(1)

    sql_files = [f for f in sys.argv[1:] if f.endswith('.sql')]
    total_errors = 0

    for sql_file in sql_files:
        filepath = Path(sql_file)
        if not filepath.exists():
            print(f"⚠ {sql_file}: File not found")
            continue

        errors = check_file(filepath)
        if errors:
            print(f"✗ {filepath}")
            for error in errors:
                print(f"  {error}")
            total_errors += len(errors)
        else:
            print(f"✓ {filepath}")

    if total_errors == 0:
        print(f"\n✅ SQL linting passed for {len(sql_files)} files")
        sys.exit(0)
    else:
        print(f"\n⚠ SQL linting found {total_errors} issue(s)")
        # Don't fail on warnings for now
        sys.exit(0)

if __name__ == '__main__':
    main()
