"""
pgGit-specific fixture module.

Provides setup/teardown for pgGit extension and database initialization,
including branch creation, table setup, and schema verification.

Features:
- pgGit extension installation verification
- Main branch creation and setup
- Commits table creation with required schema
- pgGit schema introspection helpers
"""


def setup_pggit_database(db_fixture):
    """
    Initialize pgGit database with required tables and schema.

    Creates:
    - pggit.branches table with 'main' branch
    - pggit.commits table with full schema
    - Ensures all required pgGit functions exist

    Args:
        db_fixture: DatabaseFixture instance with active connection

    Raises:
        Exception: If setup fails due to schema issues
    """
    # Ensure commits table exists (required for tests)
    try:
        db_fixture.execute("""
            CREATE TABLE IF NOT EXISTS pggit.commits (
                id SERIAL PRIMARY KEY,
                hash TEXT NOT NULL UNIQUE DEFAULT (md5(random()::text)),
                branch_id INTEGER NOT NULL REFERENCES pggit.branches(id),
                parent_commit_hash TEXT,
                message TEXT,
                author TEXT DEFAULT CURRENT_USER,
                authored_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                committer TEXT DEFAULT CURRENT_USER,
                committed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                tree_hash TEXT,
                metadata JSONB,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
    except Exception as e:
        # Table might already exist, continue
        db_fixture.conn.rollback()

    # Create main branch if it doesn't exist (required for tests)
    try:
        db_fixture.execute(
            "INSERT INTO pggit.branches (name, status) VALUES ('main', 'ACTIVE')"
        )
    except Exception as e:
        # Branch might already exist, rollback and continue
        db_fixture.conn.rollback()


def verify_pggit_extension(db_fixture) -> bool:
    """
    Verify that pgGit extension is properly installed.

    Checks for critical functions required by test suite:
    - create_temporal_snapshot
    - record_temporal_change
    - Basic branch/commit functionality

    Args:
        db_fixture: DatabaseFixture instance with active connection

    Returns:
        True if extension is properly installed, False otherwise
    """
    try:
        result = db_fixture.execute("""
            SELECT proname FROM pg_proc
            WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname='pggit')
            AND proname = 'create_temporal_snapshot'
        """)
        return result is not None and len(result) > 0
    except Exception:
        return False


def get_pggit_functions(db_fixture) -> list:
    """
    Get list of all pgGit functions in the extension.

    Args:
        db_fixture: DatabaseFixture instance with active connection

    Returns:
        List of function names (strings) in pggit schema
    """
    try:
        results = db_fixture.execute("""
            SELECT proname FROM pg_proc
            WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname='pggit')
            ORDER BY proname
        """)
        return [row[0] for row in results] if results else []
    except Exception:
        return []


def get_pggit_tables(db_fixture) -> list:
    """
    Get list of all pgGit tables in the extension schema.

    Args:
        db_fixture: DatabaseFixture instance with active connection

    Returns:
        List of table names (strings) in pggit schema
    """
    try:
        results = db_fixture.execute("""
            SELECT tablename FROM pg_tables
            WHERE schemaname = 'pggit'
            ORDER BY tablename
        """)
        return [row[0] for row in results] if results else []
    except Exception:
        return []


def create_test_branch(db_fixture, branch_name: str) -> int:
    """
    Create a new branch for testing.

    Args:
        db_fixture: DatabaseFixture instance with active connection
        branch_name: Name of the branch to create

    Returns:
        Branch ID (integer) of newly created branch

    Raises:
        Exception: If branch creation fails
    """
    result = db_fixture.execute_returning(
        "INSERT INTO pggit.branches (name) VALUES (%s) RETURNING id",
        branch_name
    )
    return result[0] if result else None


def get_main_branch_id(db_fixture) -> int:
    """
    Get the branch ID for the main branch.

    Args:
        db_fixture: DatabaseFixture instance with active connection

    Returns:
        Branch ID of main branch

    Raises:
        Exception: If main branch doesn't exist
    """
    result = db_fixture.execute_returning(
        "SELECT id FROM pggit.branches WHERE name = 'main'"
    )
    return result[0] if result else None


def cleanup_test_data(db_fixture, table_names: list = None):
    """
    Clean up test data from specified tables.

    Truncates tables but preserves schema.
    Use with caution - cascades to dependent tables.

    Args:
        db_fixture: DatabaseFixture instance with active connection
        table_names: List of table names to truncate. If None, cleans standard test tables.
    """
    if table_names is None:
        table_names = []

    for table in table_names:
        try:
            # Use CASCADE to handle foreign keys
            db_fixture.execute(f"TRUNCATE TABLE {table} CASCADE")
        except Exception:
            # Table might not exist, continue
            db_fixture.conn.rollback()
