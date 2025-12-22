"""
Test fixtures module - Centralized fixture library for E2E and integration tests.

This module re-exports all fixture utilities for easy importing across the test suite.

Usage in tests:
    from tests.fixtures import DatabaseFixture, BranchBuilder, CommitBuilder
    from tests.fixtures import DockerPostgresSetup, TableBuilder

Submodules:
    - database: DatabaseFixture class for DB connection management
    - pggit: pgGit-specific setup and helpers
    - docker_helpers: DockerPostgresSetup for container management
    - data_builders: Factory classes for test data generation
"""

from tests.fixtures.database import DatabaseFixture
from tests.fixtures.pggit import (
    setup_pggit_database,
    verify_pggit_extension,
    get_pggit_functions,
    get_pggit_tables,
    create_test_branch,
    get_main_branch_id,
    cleanup_test_data,
)
from tests.fixtures.docker_helpers import DockerPostgresSetup
from tests.fixtures.data_builders import (
    BranchBuilder,
    CommitBuilder,
    TableBuilder,
    DataGenerator,
)

__all__ = [
    # Database fixtures
    "DatabaseFixture",
    # pgGit setup functions
    "setup_pggit_database",
    "verify_pggit_extension",
    "get_pggit_functions",
    "get_pggit_tables",
    "create_test_branch",
    "get_main_branch_id",
    "cleanup_test_data",
    # Docker helpers
    "DockerPostgresSetup",
    # Data builders
    "BranchBuilder",
    "CommitBuilder",
    "TableBuilder",
    "DataGenerator",
]
