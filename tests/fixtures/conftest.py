"""Conftest for tests/fixtures - imports fixtures from e2e conftest for validation tests."""

# Import all E2E fixtures to make them available for validation tests
from tests.e2e.conftest import (  # noqa: F401
    docker_setup,
    pggit_installed,
    e2e_pool,
    db_setup,
    db_unit,
    db_integration,
    db_e2e,
    db_load,
)
