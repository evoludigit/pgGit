# pgGit Makefile - Minimal Version

EXTENSION = pggit
DATA = pggit--0.3.0.sql
REGRESS = 

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Version and release management
CURRENT_VERSION := $(shell grep 'version = ' pyproject.toml | head -1 | sed 's/version = "\(.*\)"/\1/')
GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
GIT_REMOTE := origin

# Hex-organized SQL directories
SQL_HEX_DIRS := sql/0x0xxx_core sql/0x1xxx_ddl sql/0x2xxx_branching sql/0x3xxx_merging \
                sql/0x4xxx_data sql/0x5xxx_security sql/0x6xxx_monitoring \
                sql/0x7xxx_performance sql/0x8xxx_utilities sql/0x9xxx_testing \
                sql/0xAxxx_migration sql/0xBxxx_enterprise sql/0xCxxx_integration

# Test targets
.PHONY: test test-pgtap test-core test-enterprise test-ai test-podman test-all test-clean install clean lint
.PHONY: build-hex build-legacy build-check
# Release targets
.PHONY: release release-patch release-minor release-major release-check release-dry-run release-help validate-changelog

# ============================================================================
# Build Targets (Hex Organization)
# ============================================================================

# Build extension SQL file from hex-organized structure (RECOMMENDED)
build-hex:
	@echo "🔨 Building pgGit from hex-organized structure..."
	@echo "Concatenating SQL files in order..."
	@cat $(SQL_HEX_DIRS:%=%/*.sql) > pggit--$(CURRENT_VERSION).sql 2>/dev/null || \
		(for dir in $(SQL_HEX_DIRS); do cat $$dir/*.sql 2>/dev/null; done) > pggit--$(CURRENT_VERSION).sql
	@echo "✅ Built pggit--$(CURRENT_VERSION).sql"
	@wc -l pggit--$(CURRENT_VERSION).sql | awk '{print "   Total lines: " $$1}'
	@grep -c "CREATE.*FUNCTION" pggit--$(CURRENT_VERSION).sql | awk '{print "   Functions: " $$1}'
	@echo ""
	@echo "Files included (in order):"
	@for dir in $(SQL_HEX_DIRS); do \
		for file in $$dir/*.sql; do \
			[ -f "$$file" ] && echo "   $$file"; \
		done; \
	done

# Legacy build (for backward compatibility)
build-legacy:
	@echo "🔨 Building pgGit (legacy mode)..."
	@echo "WARNING: Using legacy sql/*.sql files"
	@cat sql/*.sql > pggit--$(CURRENT_VERSION).sql
	@echo "✅ Built pggit--$(CURRENT_VERSION).sql (legacy)"

# Verify build integrity
build-check: build-hex
	@echo "🔍 Verifying build integrity..."
	@if [ ! -f pggit--$(CURRENT_VERSION).sql ]; then \
		echo "❌ ERROR: pggit--$(CURRENT_VERSION).sql not found"; \
		exit 1; \
	fi
	@echo "✅ Build file exists"
	
	@func_count=$$(grep -c "CREATE.*FUNCTION" pggit--$(CURRENT_VERSION).sql || echo 0); \
	if [ "$$func_count" -lt 400 ]; then \
		echo "⚠️  WARNING: Expected ~461 functions, found $$func_count"; \
	else \
		echo "✅ Function count: $$func_count"; \
	fi
	
	@if grep -q "TODO\|FIXME" pggit--$(CURRENT_VERSION).sql; then \
		echo "⚠️  WARNING: Found TODO/FIXME markers in build"; \
	fi
	
	@echo "✅ Build verification complete"

# Install with hex build (default)
install: build-hex
	@echo "📦 Installing pgGit extension..."
	@cp pggit--$(CURRENT_VERSION).sql $(shell $(PG_CONFIG) --sharedir)/extension/ 2>/dev/null || \
		echo "Note: Manual install - copy pggit--$(CURRENT_VERSION).sql to your PostgreSQL extension directory"
	@echo "✅ Installation complete"
	@echo ""
	@echo "To use in database:"
	@echo "  psql -c \"CREATE EXTENSION pggit;\""

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

# Validate CHANGELOG.md format
validate-changelog:
	@echo "Validating CHANGELOG.md..."
	@./scripts/validate-changelog.sh

# Help for build commands
build-help:
	@echo "pgGit Build Commands (Hex Organization):"
	@echo ""
	@echo "  make build-hex       - Build from hex-organized structure (RECOMMENDED)"
	@echo "  make build-legacy    - Build from legacy sql/*.sql files"
	@echo "  make build-check     - Verify build integrity"
	@echo "  make install         - Build and install extension"
	@echo ""
	@echo "Hex Organization Structure:"
	@echo "  sql/0x0xxx_core/           - Core schema & infrastructure (12 files)"
	@echo "  sql/0x1xxx_ddl/            - DDL tracking & triggers (4 files)"
	@echo "  sql/0x2xxx_branching/      - Branching & version control (5 files)"
	@echo "  sql/0x3xxx_merging/         - Merging & conflict resolution (6 files)"
	@echo "  sql/0x4xxx_data/            - Data management & storage (8 files)"
	@echo "  sql/0x5xxx_security/        - Security, RLS & multi-tenancy (2 files)"
	@echo "  sql/0x6xxx_monitoring/      - Monitoring & metrics (7 files)"
	@echo "  sql/0x7xxx_performance/     - Performance optimization (3 files)"
	@echo "  sql/0x8xxx_utilities/         - Internal helpers (3 files)"
	@echo "  sql/0x9xxx_testing/          - Testing infrastructure (2 files)"
	@echo "  sql/0xAxxx_migration/        - Migration scripts (4 files)"
	@echo "  sql/0xBxxx_enterprise/       - Enterprise features ⭐ CQRS (5 files)"
	@echo "  sql/0xCxxx_integration/      - Integration & APIs (8 files)"
	@echo ""
	@echo "Total: 69 files, ~461 functions, 10-second discovery"

# ============================================================================
# Hex Organization Helpers
# ============================================================================

# List all hex-organized SQL files
list-hex:
	@echo "📂 Hex-Organized SQL Files:"
	@echo ""
	@for dir in $(SQL_HEX_DIRS); do \
		echo "$$dir:"; \
		for file in $$dir/*.sql; do \
			[ -f "$$file" ] && echo "  - $$(basename $$file)"; \
		done; \
		echo ""; \
	done

# Count functions per category
count-functions:
	@echo "🔢 Function Count by Category:"
	@echo ""
	@for dir in $(SQL_HEX_DIRS); do \
		count=0; \
		for file in $$dir/*.sql; do \
			[ -f "$$file" ] && c=$$(grep -c "CREATE.*FUNCTION" "$$file" 2>/dev/null || echo 0) && count=$$((count + c)); \
		done; \
		echo "$$dir: $$count functions"; \
	done
	@echo ""
	@total=$$(grep -c "CREATE.*FUNCTION" pggit--$(CURRENT_VERSION).sql 2>/dev/null || echo 0); \
	echo "Total: $$total functions"

# Find function by name
find-function:
	@if [ -z "$(FUNC)" ]; then \
		echo "Usage: make find-function FUNC=function_name"; \
		exit 1; \
	fi
	@echo "🔍 Searching for '$(FUNC)'..."
	@grep -rn "CREATE.*FUNCTION.*$(FUNC)" sql/ 2>/dev/null || echo "Not found"

# Default target help
help: build-help test-help release-help
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
