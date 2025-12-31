# pgGit Dev Container

**One-click development environment for pgGit**

## Quick Start

### Option 1: VS Code (Recommended)

1. Install [VS Code](https://code.visualstudio.com/) and [Docker](https://www.docker.com/products/docker-desktop)
2. Install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
3. Open this repository in VS Code
4. Click "Reopen in Container" when prompted (or use Command Palette: `Dev Containers: Reopen in Container`)
5. Wait for the container to build and setup (~5-10 minutes first time)
6. Done! Start coding 🎉

### Option 2: GitHub Codespaces

1. Click "Code" → "Codespaces" → "Create codespace on main"
2. Wait for environment setup (~5-10 minutes)
3. Done! Start coding in your browser 🎉

## What's Included

### Tools & Extensions

- **Python 3.11** with uv package manager
- **PostgreSQL 17** (running in separate container)
- **Git** with GitHub CLI
- **Pre-commit hooks** (auto-installed)
- **VS Code extensions**:
  - Python (Pylance, Ruff, Black)
  - SQL Tools (PostgreSQL driver)
  - Markdown All in One
  - GitLens
  - GitHub Actions support

### Databases

- **pggit_dev** - Development database (auto-created, pgGit installed)
- **pggit_test** - Test database (auto-created)

### Environment Variables

```bash
PGHOST=postgres
PGPORT=5432
PGUSER=postgres
PGPASSWORD=postgres
PGDATABASE=pggit_dev
```

## Common Tasks

### Database Access

```bash
# Connect to development database
psql -h postgres -U postgres -d pggit_dev

# Connect to test database
psql -h postgres -U postgres -d pggit_test

# Run SQL file
psql -h postgres -U postgres -d pggit_dev -f sql/example.sql
```

### Running Tests

```bash
# E2E tests
pytest tests/e2e/ -v

# Chaos tests (smoke only)
pytest tests/chaos/ -v -m "chaos and not slow and not destructive"

# All tests
pytest tests/ -v

# With coverage
pytest tests/e2e/ -v --cov=tests --cov-report=html
```

### Pre-commit Hooks

```bash
# Run all hooks
pre-commit run --all-files

# Run specific hook
pre-commit run gitleaks --all-files

# Update hooks
pre-commit autoupdate
```

### Installing pgGit

```bash
# Reinstall after changes
cd core/sql
psql -h postgres -U postgres -d pggit_dev -f install.sql
cd ../..
```

## Architecture

```
Dev Container
├── app (Ubuntu 22.04)
│   ├── Python 3.11 + uv
│   ├── PostgreSQL client tools
│   ├── Git + GitHub CLI
│   └── Your workspace (/workspace)
│
└── postgres (PostgreSQL 17)
    ├── pggit_dev (development DB)
    ├── pggit_test (test DB)
    └── Persistent volume (postgres-data)
```

## Troubleshooting

### PostgreSQL not responding

```bash
# Check status
docker-compose -f .devcontainer/docker-compose.yml ps

# Restart PostgreSQL
docker-compose -f .devcontainer/docker-compose.yml restart postgres

# View logs
docker-compose -f .devcontainer/docker-compose.yml logs postgres
```

### Rebuild container

1. Command Palette: `Dev Containers: Rebuild Container`
2. Or: `Dev Containers: Rebuild Without Cache` (slower, fresh start)

### Reset database

```bash
# Drop and recreate
psql -h postgres -U postgres -c "DROP DATABASE pggit_dev;"
psql -h postgres -U postgres -c "CREATE DATABASE pggit_dev;"

# Reinstall pgGit
cd core/sql && psql -h postgres -U postgres -d pggit_dev -f install.sql
```

## Performance Tips

- **First build**: ~5-10 minutes (downloads images, installs dependencies)
- **Subsequent builds**: ~1-2 minutes (uses cached layers)
- **Container startup**: ~30 seconds

## Customization

### Add VS Code extensions

Edit `.devcontainer/devcontainer.json`:

```json
"customizations": {
  "vscode": {
    "extensions": [
      "your-extension-id"
    ]
  }
}
```

### Add system packages

Edit `.devcontainer/Dockerfile`:

```dockerfile
RUN apt-get update && apt-get install -y \
    your-package \
    && apt-get clean
```

### Change PostgreSQL version

Edit `.devcontainer/docker-compose.yml`:

```yaml
postgres:
  image: postgres:16-alpine  # Change to desired version
```

## Resources

- [Dev Containers Documentation](https://containers.dev/)
- [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers)
- [GitHub Codespaces](https://github.com/features/codespaces)
