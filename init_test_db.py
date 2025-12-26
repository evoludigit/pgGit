#!/usr/bin/env python
"""Initialize test database with all schema files."""

import psycopg
import os

conn_params = {
    'host': 'localhost',
    'port': 5432,
    'user': 'postgres',
    'password': '',
}

try:
    # Drop and create test database
    with psycopg.connect(**conn_params, autocommit=True, dbname='postgres') as conn:
        with conn.cursor() as cur:
            cur.execute('DROP DATABASE IF EXISTS pggit_test')
            cur.execute('CREATE DATABASE pggit_test')

    print("✓ Test database created")

    # Load schema files
    conn_params['dbname'] = 'pggit_test'
    schema_files = [
        'sql/v1.0.0/phase_1_schema.sql',
        'sql/v1.0.0/phase_1_utilities.sql',
        'sql/v1.0.0/phase_1_triggers.sql',
        'sql/v1.0.0/phase_1_bootstrap.sql',
        'sql/030_pggit_branch_management.sql',
        'sql/031_pggit_object_tracking.sql',
        'sql/032_pggit_merge_operations.sql',
        'sql/033_pggit_history_audit.sql',
        'sql/034_pggit_rollback_operations.sql',
    ]

    with psycopg.connect(**conn_params, autocommit=True) as conn:
        with conn.cursor() as cur:
            for schema_file in schema_files:
                if os.path.exists(schema_file):
                    with open(schema_file) as f:
                        sql = f.read()
                    try:
                        cur.execute(sql)
                        print(f'✓ {schema_file}')
                    except Exception as e:
                        print(f'✗ {schema_file}: {str(e)[:150]}')
                        raise
                else:
                    print(f'✗ Missing: {schema_file}')

    # Verify schema
    with psycopg.connect(**conn_params) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM information_schema.tables WHERE table_schema = 'pggit'")
            table_count = cur.fetchone()[0]

            cur.execute("SELECT count(*) FROM information_schema.routines WHERE routine_schema = 'pggit'")
            func_count = cur.fetchone()[0]

            print(f"\n✓ Schema initialized: {table_count} tables, {func_count} functions")

            # List Phase 6 functions
            cur.execute("""SELECT routine_name FROM information_schema.routines
                          WHERE routine_schema = 'pggit' AND routine_name LIKE 'rollback%'
                          ORDER BY routine_name""")
            funcs = [r[0] for r in cur.fetchall()]
            if funcs:
                print(f"  Phase 6 functions: {', '.join(funcs)}")

except Exception as e:
    print(f"\n✗ Error: {e}")
    raise
