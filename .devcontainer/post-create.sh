#!/bin/bash
set -e

echo "🚀 Setting up pgGit development environment..."

# Add uv to PATH for this session
export PATH="$HOME/.cargo/bin:$PATH"

# Install Python dependencies
echo "📦 Installing Python dependencies..."
if command -v uv &> /dev/null; then
    uv venv .venv
    source .venv/bin/activate
    uv pip install -e ".[chaos]"
else
    python3 -m venv .venv
    source .venv/bin/activate
    pip install --upgrade pip
    pip install -e ".[chaos]"
fi

# Install pre-commit hooks
echo "🔧 Installing pre-commit hooks..."
pip install pre-commit
pre-commit install
pre-commit install --hook-type commit-msg

# Wait for PostgreSQL to be ready
echo "⏳ Waiting for PostgreSQL..."
until pg_isready -h postgres -U postgres; do
    echo "PostgreSQL is unavailable - sleeping"
    sleep 2
done

echo "✅ PostgreSQL is ready!"

# Install pgGit extension
echo "🔨 Installing pgGit extension..."
cd core/sql
psql -h postgres -U postgres -d pggit_dev -f install.sql || echo "Note: Core installation had some warnings"
cd ../..

# Verify installation
echo "✅ Verifying pgGit installation..."
psql -h postgres -U postgres -d pggit_dev -c "SELECT pggit.version();" || echo "Note: pggit.version() not available yet"

# Create test database
echo "🧪 Setting up test database..."
psql -h postgres -U postgres -c "CREATE DATABASE pggit_test;" || echo "Test database may already exist"

echo ""
echo "✨ Development environment ready!"
echo ""
echo "Quick Start:"
echo "  - PostgreSQL: psql -h postgres -U postgres -d pggit_dev"
echo "  - Run tests: pytest tests/e2e/ -v"
echo "  - Run chaos tests: pytest tests/chaos/ -v -m 'chaos and not slow'"
echo "  - Pre-commit: pre-commit run --all-files"
echo ""
echo "Happy coding! 🎉"
