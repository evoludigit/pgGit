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
   - Ensure all tests pass
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