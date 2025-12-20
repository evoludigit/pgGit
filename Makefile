# pgGit Makefile - Minimal Version

EXTENSION = pggit
DATA = pggit--1.0.0.sql
REGRESS = 

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Test targets
.PHONY: test test-pgtap test-core test-enterprise test-ai test-podman test-all test-clean install clean

# Run all tests locally
test:
	@echo "Running pgGit test suite..."
	@./tests/test-full.sh

# Run pgTAP tests
test-pgtap:
	@echo "Running pgTAP tests..."
	@DB_NAME=pgtap_test ./tests/test-runner.sh

# Generate test coverage report
test-coverage:
	@echo "Generating test coverage report..."
	@psql -d pgtap_test -f tests/coverage-report.sql

# Run all tests (alias for test)
test-all: test

# Run individual test suites
test-core:
	@echo "Running core tests..."
	@echo "Note: For best results, ensure a clean database state."
	@echo "Consider running 'DROP SCHEMA IF EXISTS pggit CASCADE;' first if you encounter conflicts."
	@psql -f tests/test-core.sql

test-enterprise:
	@echo "Running enterprise tests..."
	@echo "Note: This test requires all pgGit modules to be installed."
	@echo "If it fails, first run: psql -f sql/install.sql"
	@psql -f tests/test-enterprise.sql

test-ai:
	@echo "Running AI tests..."
	@echo "Note: This test loads required modules automatically."
	@echo "For best results, ensure a clean database state."
	@psql -f tests/test-ai.sql

# Run tests in Podman container (bulletproof)
test-podman:
	@echo "Running tests in Podman container..."
	@./tests/test-full.sh --podman

# Quick test (just core functionality)
test-quick: test-core

# Clean install for testing
test-clean:
	@echo "Cleaning pgGit schema and reinstalling..."
	@psql -c "DROP SCHEMA IF EXISTS pggit CASCADE;" 2>/dev/null || true
	@psql -f sql/install.sql
	@echo "Clean installation complete. Ready for testing."

# Install the extension
install:
	@echo "Installing pgGit extension..."
	@psql -f sql/install.sql

# Clean the database
clean:
	@echo "Removing pgGit schema..."
	@psql -c "DROP SCHEMA IF EXISTS pggit CASCADE;"
	@echo "pgGit schema removed."

# Help for test commands
test-help:
	@echo "pgGit Test Commands:"
	@echo "  make test          - Run all tests locally"
	@echo "  make test-core     - Run core functionality tests"
	@echo "  make test-enterprise - Run enterprise feature tests"
	@echo "  make test-ai       - Run AI feature tests"
	@echo "  make test-podman   - Run all tests in Podman container"
	@echo "  make test-quick    - Run just core tests (fastest)"
	@echo "  make test-clean    - Clean install and prepare for testing"
	@echo "  make install       - Install pgGit extension"
	@echo "  make clean         - Remove pgGit schema"
	@echo "  make test-help     - Show this help message"