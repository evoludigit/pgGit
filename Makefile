# pgGit Makefile
#
# This Makefile auto-generates the extension SQL file from source files.
# The bundled pggit--$(PGGIT_VERSION).sql is NOT checked into git - it's built on demand.

EXTENSION = pggit
PGGIT_VERSION = 0.5.0
DATA = pggit--$(PGGIT_VERSION).sql
REGRESS =

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)

# SQL source files in dependency order (from sql/install.sql)
SQL_DIR = sql
SQL_FILES = \
	$(SQL_DIR)/001_schema.sql \
	$(SQL_DIR)/002_event_triggers.sql \
	$(SQL_DIR)/003_migration_functions.sql \
	$(SQL_DIR)/test_helpers.sql \
	$(SQL_DIR)/004_utility_views.sql \
	$(SQL_DIR)/009_ddl_hashing.sql \
	$(SQL_DIR)/017_performance_optimizations.sql \
	$(SQL_DIR)/020_git_core_implementation.sql \
	$(SQL_DIR)/030_ai_migration_analysis.sql \
	$(SQL_DIR)/040_size_management.sql \
	$(SQL_DIR)/050_create_commit.sql \
	$(SQL_DIR)/050_branch_merge_operations.sql \
	$(SQL_DIR)/055_storage_tier_stubs.sql \
	$(SQL_DIR)/056_versioning_stubs.sql \
	$(SQL_DIR)/pggit_cqrs_support.sql \
	$(SQL_DIR)/051_data_branching_cow.sql \
	$(SQL_DIR)/052_merge_operations.sql \
	$(SQL_DIR)/053_advanced_merge_operations.sql \
	$(SQL_DIR)/054_batch_operations_monitoring.sql \
	$(SQL_DIR)/055_schema_diffing_foundation.sql \
	$(SQL_DIR)/056_advanced_workflows.sql \
	$(SQL_DIR)/057_advanced_reporting.sql \
	$(SQL_DIR)/058_analytics_insights.sql \
	$(SQL_DIR)/059_performance_optimization.sql \
	$(SQL_DIR)/pggit_conflict_resolution_minimal.sql \
	$(SQL_DIR)/pggit_diff_functionality.sql \
	$(SQL_DIR)/060_time_travel.sql \
	$(SQL_DIR)/070_backup_integration.sql \
	$(SQL_DIR)/071_backup_automation.sql \
	$(SQL_DIR)/072_backup_management.sql \
	$(SQL_DIR)/073_backup_recovery.sql \
	$(SQL_DIR)/074_error_codes.sql \
	$(SQL_DIR)/075_audit_log.sql \
	$(SQL_DIR)/061_advanced_ml_optimization.sql \
	$(SQL_DIR)/062_advanced_conflict_resolution.sql

# Generate the bundled SQL file from source files
# This runs automatically before 'make install' if any source file changed
$(DATA): $(SQL_FILES)
	@echo "Generating $(DATA) from source files..."
	@cat $(SQL_FILES) > $@
	@echo "Generated $(DATA) ($$(wc -l < $@) lines)"

# Include PGXS for standard extension targets (install, uninstall, etc.)
include $(PGXS)

# Test targets
.PHONY: test test-pgtap test-core test-enterprise test-ai test-podman test-all test-clean clean generate

# Explicitly generate the SQL file
generate: $(DATA)

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
	@psql -c "DROP EXTENSION IF EXISTS pggit CASCADE;" 2>/dev/null || true
	@psql -c "DROP SCHEMA IF EXISTS pggit CASCADE;" 2>/dev/null || true
	@psql -c "CREATE EXTENSION pggit;" 2>/dev/null || true
	@echo "Clean installation complete. Ready for testing."

# Note: 'make install' is handled by PGXS and installs files to PostgreSQL's extension directory
# To create the extension in a database, use: psql -c "CREATE EXTENSION pggit;"

# Clean the database and generated files
clean:
	@echo "Removing pgGit extension..."
	@psql -c "DROP EXTENSION IF EXISTS pggit CASCADE;" 2>/dev/null || true
	@psql -c "DROP SCHEMA IF EXISTS pggit CASCADE;" 2>/dev/null || true
	@rm -f $(DATA)
	@echo "pgGit extension removed."

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
	@echo "  make generate      - Generate bundled SQL without installing"
	@echo "  make clean         - Remove pgGit schema and generated files"
	@echo "  make test-help     - Show this help message"
