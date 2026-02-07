# pgGit Release Checklist

Use this checklist before creating any release to ensure quality and consistency.

## Pre-Release Validation (Run: `make release-check`)

- [ ] On `main` branch
- [ ] Working directory is clean (no uncommitted changes)
- [ ] All tests pass locally
- [ ] All lints pass (ruff, sqlfluff)
- [ ] GitHub CLI (`gh`) is installed and authenticated

## Code Quality (Before Pushing)

- [ ] All tests pass: `make test` or `make test-all`
- [ ] Linting passes: `ruff check --fix && ruff format`
- [ ] No console.log or debug statements remaining
- [ ] No TODO/FIXME comments in production code
- [ ] Type hints are complete (Python)
- [ ] Documentation is up-to-date

## Documentation (Before Release)

- [ ] README.md is accurate and complete
- [ ] API documentation is current
- [ ] Code examples work and are tested
- [ ] CONTRIBUTING.md is up-to-date
- [ ] Version mentioned in relevant docs

## Version & Release Notes

- [ ] Decide release type: MAJOR, MINOR, or PATCH
  - MAJOR: Breaking changes (0.1.0 → 1.0.0)
  - MINOR: New features, backward compatible (0.1.0 → 0.2.0)
  - PATCH: Bug fixes only (0.1.0 → 0.1.1)
- [ ] Draft release notes with key changes
- [ ] Categorize commits: Features, Fixes, Docs, Refactoring, Security

## Create Release (Run One Command)

Choose the appropriate command and run **only one**:

```bash
# For bug fixes only
make release-patch

# For new features (backward compatible)
make release-minor

# For breaking changes
make release-major
```

**What happens automatically:**
1. ✅ Validates all prerequisites
2. ✅ Bumps version in pyproject.toml
3. ✅ Updates CHANGELOG.md
4. ✅ Updates version badge in README.md
5. ✅ Creates release commit
6. ✅ Creates annotated git tag
7. ✅ Pushes branch and tag to remote
8. ✅ Creates GitHub release

## Post-Release

- [ ] Verify release on GitHub: https://github.com/evoludigit/pgGit/releases
- [ ] Check that tag is correctly created: `git tag -l`
- [ ] Verify release assets are available (if applicable)
- [ ] Update any downstream projects/documentation
- [ ] Announce release to team/community
- [ ] Check CI/CD passes on release tag

## Troubleshooting

### "Must be on 'main' branch"
```bash
git checkout main
git pull origin main
```

### "Working directory has uncommitted changes"
```bash
git status  # Review changes
git add .
git commit -m "..."
```

### "GitHub CLI not installed"
```bash
# macOS
brew install gh

# Ubuntu/Debian
sudo apt-get install gh

# Then authenticate
gh auth login
```

### "Git push failed"
```bash
# Ensure origin is set correctly
git remote -v

# Pull latest changes
git pull origin main

# Retry release
make release-patch  # (or minor/major)
```

### Release created but GitHub release didn't sync
```bash
# Manually create GitHub release
gh release create v0.2.1 --notes "Release notes here"
```

## Automation Benefits

✅ **Consistent versioning** - Always follows semver
✅ **Automatic changelog** - Captures all commits
✅ **No manual steps** - One command does it all
✅ **Audit trail** - Git history shows exactly what changed
✅ **Safety checks** - Validates before committing
✅ **Time saving** - What took 15 minutes now takes 1

## Example Release Flow

```bash
# 1. On main, pull latest
git checkout main
git pull origin main

# 2. Check what would be released
make release-dry-run

# 3. Run the release
make release-patch

# 4. Verify on GitHub
# https://github.com/evoludigit/pgGit/releases

# Done! ✅
```

## Version History

| Version | Date | Type | Commits |
|---------|------|------|---------|
| v0.2.1 | 2026-02-07 | PATCH | 3 |
| v0.2.0 | 2026-02-04 | MINOR | 357 |
| v0.1.4 | 2026-02-04 | MINOR | - |
| v0.1.3 | 2026-01-22 | PATCH | - |

## Questions?

See `.github/RELEASE_CHECKLIST.md` for complete details or run:
```bash
make release-help
```
