# pgGit Makefile - Minimal Version

EXTENSION = pggit
DATA = pggit--0.1.3.sql
REGRESS = 

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Version and release management
CURRENT_VERSION := $(shell grep 'version = ' pyproject.toml | head -1 | sed 's/version = "\(.*\)"/\1/')
GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
GIT_REMOTE := origin

# Test targets
.PHONY: test test-pgtap test-core test-enterprise test-ai test-podman test-all test-clean install clean lint
# Release targets
.PHONY: release release-patch release-minor release-major release-check release-dry-run release-help

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

# Clean the database
clean:
	@echo "Removing pgGit extension..."
	@psql -c "DROP EXTENSION IF EXISTS pggit CASCADE;" 2>/dev/null || true
	@psql -c "DROP SCHEMA IF EXISTS pggit CASCADE;" 2>/dev/null || true
	@echo "pgGit extension removed."

# Lint SQL files for syntax errors
lint:
	@echo "Linting SQL files for syntax errors..."
	@python3 scripts/lint_sql.py sql/*.sql
	@echo "✓ SQL linting complete"

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

# ============================================================================
# Release Management Commands
# ============================================================================

# Validate release prerequisites
release-check:
	@echo "🔍 Validating release prerequisites..."
	@echo ""
	@echo "Current version: $(CURRENT_VERSION)"
	@echo "Current branch: $(GIT_BRANCH)"
	@echo ""
	@if [ "$(GIT_BRANCH)" != "main" ]; then \
		echo "❌ ERROR: Must be on 'main' branch. Current: $(GIT_BRANCH)"; \
		exit 1; \
	fi
	@echo "✅ Branch: main"
	@echo ""
	@if ! git diff-index --quiet HEAD --; then \
		echo "❌ ERROR: Working directory has uncommitted changes"; \
		git status --short; \
		exit 1; \
	fi
	@echo "✅ Working directory: clean"
	@echo ""
	@if ! command -v gh &> /dev/null; then \
		echo "❌ ERROR: GitHub CLI (gh) not installed"; \
		exit 1; \
	fi
	@echo "✅ GitHub CLI: installed"
	@echo ""
	@echo "✅ All prerequisites met!"

# Show what would be released (dry run)
release-dry-run: release-check
	@echo ""
	@echo "📋 Release Dry-Run"
	@echo "Current version: $(CURRENT_VERSION)"
	@echo ""
	@echo "Changes since last tag:"
	@git log $$(git describe --tags --abbrev=0)..HEAD --oneline | head -10
	@echo ""
	@echo "Commits on branch:"
	@git rev-list --count main
	@echo ""

# Release a patch version (e.g., 0.2.0 → 0.2.1)
release-patch: release-check
	@echo "🚀 Creating PATCH release..."
	@./scripts/release.sh patch
	@echo "✅ Patch release complete!"

# Release a minor version (e.g., 0.2.0 → 0.3.0)
release-minor: release-check
	@echo "🚀 Creating MINOR release..."
	@./scripts/release.sh minor
	@echo "✅ Minor release complete!"

# Release a major version (e.g., 0.2.0 → 1.0.0)
release-major: release-check
	@echo "🚀 Creating MAJOR release..."
	@./scripts/release.sh major
	@echo "✅ Major release complete!"

# Default release target (requires VERSION argument)
release:
	@echo "❌ ERROR: Specify release type: make release-patch, release-minor, or release-major"
	@echo ""
	@echo "Usage examples:"
	@echo "  make release-patch   # 0.2.0 → 0.2.1"
	@echo "  make release-minor   # 0.2.0 → 0.3.0"
	@echo "  make release-major   # 0.2.0 → 1.0.0"
	@echo ""
	@exit 1

# Help for release commands
release-help:
	@echo "pgGit Release Commands:"
	@echo ""
	@echo "  make release-check     - Validate prerequisites for release"
	@echo "  make release-dry-run   - Preview what would be released"
	@echo "  make release-patch     - Create patch release (0.2.0 → 0.2.1)"
	@echo "  make release-minor     - Create minor release (0.2.0 → 0.3.0)"
	@echo "  make release-major     - Create major release (0.2.0 → 1.0.0)"
	@echo "  make release-help      - Show this help message"
	@echo ""
	@echo "Release Process:"
	@echo "  1. Ensure you're on 'main' branch"
	@echo "  2. All changes committed (no pending work)"
	@echo "  3. Run 'make release-patch' (or minor/major)"
	@echo ""
	@echo "What happens:"
	@echo "  ✓ Validates prerequisites"
	@echo "  ✓ Bumps version in pyproject.toml"
	@echo "  ✓ Updates CHANGELOG.md with changes"
	@echo "  ✓ Creates annotated git tag"
	@echo "  ✓ Pushes tag to remote"
	@echo "  ✓ Creates GitHub release"
	@echo ""
