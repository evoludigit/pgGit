# Contributing to PgGit

## Git Workflow

This project follows a classic Git workflow strategy:

### Branches

- **main**: Production-ready code. Protected branch.
- **dev**: Development branch where features are integrated.
- **feature/***: Feature branches created from dev.
- **hotfix/***: Emergency fixes created from main.

### Workflow

1. **Feature Development**
   ```bash
   git checkout dev
   git pull origin dev
   git checkout -b feature/your-feature-name
   # Make your changes
   git add .
   git commit -m "feat: describe your feature"
   git push origin feature/your-feature-name
   ```

2. **Creating a Pull Request**
    - Create PR from feature branch to dev
    - Use the PR template for proper formatting
    - Ensure all tests pass (`make test`)
    - Run linting (`make lint`)
    - Request code review
    - Merge after approval

3. **Release Process**
   ```bash
   git checkout main
   git pull origin main
   git merge dev
   git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin main --tags
    ```

## Reporting Issues

We use GitHub issues to track bugs, features, and security issues:

- **Bug Reports**: Use the bug report template
- **Feature Requests**: Use the feature request template
- **Security Issues**: Use the security vulnerability template (see SECURITY.md)
- **General Questions**: Use GitHub Discussions

## Setting Up Pre-commit Hooks

Pre-commit hooks help maintain code quality by running automated checks before commits.

### Installation

1. **Install pre-commit**:
   ```bash
   pip install pre-commit
   # OR
   pip3 install pre-commit
   ```

2. **Install the hooks**:
   ```bash
   cd pggit
   pre-commit install
   pre-commit install --hook-type pre-push
   ```

3. **Test the hooks**:
   ```bash
   pre-commit run --all-files
   ```

### What the Hooks Do

- **trailing-whitespace**: Removes trailing whitespace
- **end-of-file-fixer**: Ensures files end with a newline
- **check-yaml**: Validates YAML syntax
- **check-added-large-files**: Prevents large files (>500KB)
- **check-merge-conflict**: Detects merge conflict markers
- **sqlfluff-lint/fix**: SQL code quality checks
- **shellcheck**: Shell script validation
- **markdownlint**: Markdown formatting
- **test-core**: Runs core tests before push

### Skipping Hooks

In rare cases, you can skip hooks:
```bash
git commit --no-verify -m "Your message"
```

But only do this if you understand why the hook is failing.

4. **Hotfixes**
   ```bash
   git checkout main
   git checkout -b hotfix/fix-description
   # Fix the issue
   git add .
   git commit -m "fix: describe the fix"
   # Merge to main and dev
   git checkout main
   git merge hotfix/fix-description
   git checkout dev
   git merge hotfix/fix-description
   ```

### Commit Message Convention

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `style:` Code style changes (formatting, etc)
- `refactor:` Code refactoring
- `test:` Adding or updating tests
- `chore:` Maintenance tasks

### Testing

All PRs must pass the test suite:
```bash
make test
```

### Code Review

- All code must be reviewed before merging
- Ensure tests are included for new features
- Follow existing code conventions