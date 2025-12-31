#!/usr/bin/env python3
"""
User Journey E2E Test Suite

Tests the complete user experience from the Getting Started guide.
Validates that all documented workflows actually work in a clean environment.

This test suite simulates a new user following the documentation:
- Chapter 2: Installation
- Chapter 3: First Automatic Tracking
- Chapter 4: Schema Evolution
- Chapter 5: Impact Analysis
- Chapter 6: Migration Generation
- Chapter 9: Complete API Reference

Each test runs SQL scenarios that match the documented examples.
"""

import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List

import psycopg
import pytest


class DatabaseConnection:
    """Helper class for database connections and queries."""

    def __init__(self):
        self.host = os.getenv("PGHOST", "localhost")
        self.port = int(os.getenv("PGPORT", "5432"))
        self.database = os.getenv("PGDATABASE", "pggit_user_journey")
        self.user = os.getenv("PGUSER", "testuser")
        self.password = os.getenv("PGPASSWORD", "testpass")
        self.conn = None

    def connect(self, retries=5, delay=2):
        """Connect to database with retries."""
        for attempt in range(retries):
            try:
                self.conn = psycopg.connect(
                    host=self.host,
                    port=self.port,
                    dbname=self.database,
                    user=self.user,
                    password=self.password,
                    autocommit=True,
                )
                print(f"✅ Connected to PostgreSQL: {self.host}:{self.port}/{self.database}")
                return self.conn
            except psycopg.OperationalError as e:
                if attempt < retries - 1:
                    print(f"⏳ Database not ready (attempt {attempt + 1}/{retries}), waiting {delay}s...")
                    time.sleep(delay)
                else:
                    print(f"❌ Failed to connect after {retries} attempts")
                    raise

    def execute_sql_file(self, filepath: Path) -> List[Dict[str, Any]]:
        """Execute SQL file and return all results."""
        if not self.conn:
            raise RuntimeError("Not connected to database")

        with open(filepath, "r") as f:
            sql = f.read()

        results = []
        with self.conn.cursor() as cur:
            # Handle \i includes (psql meta-command)
            lines = sql.split("\n")
            sql_buffer = []

            for line in lines:
                # Skip psql meta-commands we don't handle
                if line.strip().startswith("\\echo"):
                    continue

                # Handle \i directive by reading and including the file
                if line.strip().startswith("\\i "):
                    include_file = line.strip()[3:].strip()
                    include_path = (filepath.parent / include_file).resolve()
                    print(f"DEBUG: Processing \\i directive: {include_file}")
                    print(f"DEBUG: Resolved path: {include_path}")

                    if include_path.exists():
                        file_size = include_path.stat().st_size
                        print(f"DEBUG: Include file size: {file_size} bytes")

                        # If the included file is large (like pggit--1.0.0.sql), execute it immediately via psql
                        # This avoids SQL parsing issues with naive semicolon splitting
                        if file_size > 100000:
                            print(f"DEBUG: Large file detected, executing via psql immediately")
                            result = subprocess.run(
                                ['psql', '-h', self.host, '-p', str(self.port), '-U', self.user, '-d', self.database, '-f', str(include_path)],
                                env={**os.environ, 'PGPASSWORD': self.password},
                                capture_output=True,
                                text=True,
                                check=False  # Don't raise on errors, we'll check manually
                            )
                            if result.returncode != 0:
                                print(f"ERROR: psql execution failed!")
                                print(f"STDOUT: {result.stdout}")
                                print(f"STDERR: {result.stderr}")
                                raise RuntimeError(f"psql execution failed with code {result.returncode}")
                            if result.stderr:
                                print(f"PSQL WARNINGS/ERRORS: {result.stderr[:500]}")
                            print(f"DEBUG: psql execution of {include_file} successful")
                            # Don't add to buffer - already executed
                        else:
                            # Small files can be included normally
                            with open(include_path, "r") as inc_f:
                                included_content = inc_f.read()
                                sql_buffer.append(included_content)
                                print(f"DEBUG: Included {len(included_content)} bytes from {include_file}")
                    else:
                        print(f"ERROR: Include file not found: {include_path}")
                    continue

                sql_buffer.append(line)

            # Join all SQL into one string
            sql = "\n".join(sql_buffer)

            # Execute remaining SQL statements (large files already executed via psql in \i handler)
            # Split by semicolon and execute each statement
            statements = [s.strip() for s in sql.split(";") if s.strip()]
            print(f"DEBUG execute_sql_file: {len(statements)} statements to execute from {filepath.name}")

            executed_count = 0
            skipped_count = 0

            for i, stmt in enumerate(statements):
                # Remove leading/trailing whitespace
                stmt = stmt.strip()

                # Skip empty statements
                if not stmt:
                    skipped_count += 1
                    continue

                # Skip comment-only statements (all lines start with --)
                # But don't skip statements that have SQL after comments
                lines = [l.strip() for l in stmt.split('\n') if l.strip()]
                if all(l.startswith('--') for l in lines):
                    skipped_count += 1
                    continue

                try:
                    executed_count += 1
                    cur.execute(stmt)

                    # Collect results if query returns data
                    if cur.description:
                        columns = [desc[0] for desc in cur.description]
                        rows = cur.fetchall()
                        for row in rows:
                            results.append(dict(zip(columns, row)))

                except Exception as e:
                    print(f"❌ Error in statement: {stmt[:100]}...")
                    print(f"   Error: {e}")
                    raise

            print(f"DEBUG execute_sql_file: Executed {executed_count}, Skipped {skipped_count}, Results collected: {len(results)}")

        return results

    def close(self):
        """Close database connection."""
        if self.conn:
            self.conn.close()
            self.conn = None


@pytest.fixture(scope="session")
def db():
    """Session-scoped database connection."""
    db_conn = DatabaseConnection()
    db_conn.connect()
    yield db_conn
    db_conn.close()


class TestChapter2Installation:
    """Chapter 2: The Five-Minute Setup - Installation tests."""

    def test_extension_installation(self, db):
        """Test pgGit extension can be installed."""
        scenario_file = Path(__file__).parent / "scenarios" / "01_installation.sql"
        results = db.execute_sql_file(scenario_file)

        # Debug: Print all results
        print(f"\n=== DEBUG: Got {len(results)} results ===")
        for i, r in enumerate(results):
            print(f"Result {i}: {r}")
        print("=== END DEBUG ===\n")

        # Find the verification results
        assert any(r.get("extension_installed") for r in results), "Extension not installed"
        assert any(r.get("schema_exists") for r in results), "pgGit schema not found"
        assert any(r.get("event_triggers_installed") for r in results), "Event triggers not installed"
        assert any(r.get("core_functions_exist") for r in results), "Core functions missing"
        assert any(r.get("version_table_exists") for r in results), "Version tracking table missing"

        print("✅ Chapter 2: Installation - All checks passed")


class TestChapter3FirstTracking:
    """Chapter 3: Your First Automatic Tracking - Table creation tracking."""

    def test_first_table_tracking(self, db):
        """Test automatic tracking of first table creation."""
        scenario_file = Path(__file__).parent / "scenarios" / "02_first_tracking.sql"
        results = db.execute_sql_file(scenario_file)

        # Verify table was created and tracked
        assert any(r.get("table_created") for r in results), "Test table not created"
        assert any(r.get("correct_object_name") for r in results), "Object name incorrect"
        assert any(r.get("correct_schema") for r in results), "Schema name incorrect"
        assert any(r.get("has_version") for r in results), "No version assigned"
        assert any(r.get("has_version_string") for r in results), "No version string"
        assert any(r.get("has_timestamp") for r in results), "No timestamp recorded"
        assert any(r.get("version_format_valid") for r in results), "Version string format invalid"
        assert any(r.get("create_event_tracked") for r in results), "CREATE event not tracked"
        assert any(r.get("has_expected_columns") for r in results), "Table columns missing"

        # Find the status message
        status_results = [r for r in results if "status" in r]
        if status_results:
            print(f"✅ Chapter 3: First Tracking - {status_results[0]['status']}")


class TestChapter4SchemaEvolution:
    """Chapter 4: Watching Changes Evolve - ALTER table tracking."""

    def test_alter_table_tracking(self, db):
        """Test tracking of ALTER TABLE changes and version incrementing."""
        scenario_file = Path(__file__).parent / "scenarios" / "03_schema_evolution.sql"
        results = db.execute_sql_file(scenario_file)

        # Verify ALTER was tracked
        assert any(r.get("has_all_columns") for r in results), "ALTER columns not added"
        assert any(r.get("version_incremented") for r in results), "Version did not increment"
        assert any(r.get("version_string_changed") for r in results), "Version string unchanged"
        assert any(r.get("has_multiple_history_entries") for r in results), "History missing entries"
        assert any(r.get("has_create") for r in results), "CREATE event missing from history"
        assert any(r.get("has_alter") for r in results), "ALTER event not tracked"
        assert any(r.get("alter_description_has_details") for r in results), "ALTER description missing details"
        assert any(r.get("create_is_first") for r in results), "CREATE not first in history"
        assert any(r.get("alter_is_second") for r in results), "ALTER not second in history"

        # Find the status message
        status_results = [r for r in results if "status" in r and "current_version" in r]
        if status_results:
            print(f"✅ Chapter 4: Schema Evolution - Version {status_results[0]['current_version']}, "
                  f"{status_results[0]['total_changes']} changes tracked")


class TestChapter5ImpactAnalysis:
    """Chapter 5: The Safety Net - Impact analysis before changes."""

    def test_impact_analysis(self, db):
        """Test dependency detection via impact analysis."""
        scenario_file = Path(__file__).parent / "scenarios" / "04_impact_analysis.sql"
        results = db.execute_sql_file(scenario_file)

        # Verify dependencies were created
        assert any(r.get("dependent_table_exists") for r in results), "Dependent table not created"
        assert any(r.get("dependent_view_exists") for r in results), "Dependent view not created"

        # Verify impact analysis detects them
        assert any(r.get("impact_analysis_returns_results") for r in results), "Impact analysis returned no results"
        assert any(r.get("detects_foreign_key") for r in results), "Foreign key dependency not detected"
        assert any(r.get("detects_view") for r in results), "View dependency not detected"
        assert any(r.get("has_dependent_object") for r in results), "Dependent object info missing"
        assert any(r.get("has_dependency_type") for r in results), "Dependency type info missing"
        assert any(r.get("has_multiple_dependencies") for r in results), "Not detecting all dependencies"

        # Find the status message
        status_results = [r for r in results if "status" in r and "total_dependencies" in r]
        if status_results:
            print(f"✅ Chapter 5: Impact Analysis - {status_results[0]['total_dependencies']} dependencies detected: "
                  f"{status_results[0].get('dependent_objects', 'N/A')}")


class TestChapter6MigrationGeneration:
    """Chapter 6: Migration Magic - Migration script generation."""

    def test_migration_generation(self, db):
        """Test migration script generation."""
        scenario_file = Path(__file__).parent / "scenarios" / "05_migration_generation.sql"
        results = db.execute_sql_file(scenario_file)

        # Verify migration function exists
        assert any(r.get("migration_function_exists") for r in results), "Migration function not found"

        # Verify migration can be generated
        assert any(r.get("migration_generated") for r in results), "Migration generation failed"
        assert any(r.get("migration_has_content") for r in results), "Migration result empty"

        # Verify second migration also works
        assert any(r.get("second_migration_generated") for r in results), "Cannot generate multiple migrations"

        # Find the status message
        status_results = [r for r in results if "status" in r and "capability" in r]
        if status_results:
            print(f"✅ Chapter 6: Migration Generation - {status_results[0]['status']}")


class TestChapter9CompleteAPI:
    """Chapter 9: Complete API Reference - All documented functions."""

    def test_all_api_functions(self, db):
        """Test all documented API functions work correctly."""
        scenario_file = Path(__file__).parent / "scenarios" / "06_all_api_functions.sql"
        results = db.execute_sql_file(scenario_file)

        # Test get_version()
        assert any(r.get("get_version_returns_object_name") for r in results), "get_version() missing object_name"
        assert any(r.get("get_version_returns_schema") for r in results), "get_version() missing schema"
        assert any(r.get("get_version_returns_version") for r in results), "get_version() missing version"
        assert any(r.get("get_version_returns_version_string") for r in results), "get_version() missing version_string"
        assert any(r.get("get_version_returns_timestamp") for r in results), "get_version() missing timestamp"

        # Test get_history()
        assert any(r.get("get_history_returns_records") for r in results), "get_history() returned no records"
        assert any(r.get("history_has_version") for r in results), "get_history() missing version"
        assert any(r.get("history_has_change_type") for r in results), "get_history() missing change_type"
        assert any(r.get("history_has_description") for r in results), "get_history() missing description"
        assert any(r.get("history_has_timestamp") for r in results), "get_history() missing timestamp"
        assert any(r.get("history_has_user") for r in results), "get_history() missing user"
        assert any(r.get("get_history_respects_limit") for r in results), "get_history() limit not working"

        # Test show_table_versions()
        assert any(r.get("show_table_versions_returns_data") for r in results), "show_table_versions() no data"
        assert any(r.get("versions_has_object_name") for r in results), "show_table_versions() missing object_name"
        assert any(r.get("versions_has_schema") for r in results), "show_table_versions() missing schema"
        assert any(r.get("versions_has_version_string") for r in results), "show_table_versions() missing version_string"

        # Test get_impact_analysis()
        assert any(r.get("get_impact_analysis_callable") for r in results), "get_impact_analysis() not callable"

        # Test generate_migration()
        assert any(r.get("generate_migration_callable") for r in results), "generate_migration() not callable"
        assert any(r.get("generate_migration_returns_value") for r in results), "generate_migration() no return value"

        # Verify all documented functions exist
        assert any(r.get("all_documented_functions_exist") for r in results), "Some documented functions missing"

        # Verify event triggers are active
        assert any(r.get("event_triggers_active") for r in results), "Event triggers not active"

        # Verify schema access
        assert any(r.get("can_access_pggit_schema") for r in results), "Cannot access pgGit schema"
        assert any(r.get("can_query_version_table") is not None for r in results), "Cannot query version table"

        # Find the status message
        status_results = [r for r in results if "status" in r and "total_functions" in r]
        if status_results:
            print(f"✅ Chapter 9: Complete API - {status_results[0]['total_functions']} functions verified")


if __name__ == "__main__":
    """Run tests directly with python."""
    sys.exit(pytest.main([__file__, "-v", "--tb=short", "--color=yes"]))
