# Commit Message Convention

**pgGit follows the [Conventional Commits](https://www.conventionalcommits.org/) specification**

## Format

```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

## Type

Must be one of the following:

| Type | Description | Changelog |
|------|-------------|-----------|
| `feat` | New feature | ✅ Shown |
| `fix` | Bug fix | ✅ Shown |
| `docs` | Documentation changes | ✅ Shown |
| `style` | Code style (formatting, whitespace) | ❌ Hidden |
| `refactor` | Code refactoring | ✅ Shown |
| `perf` | Performance improvements | ✅ Shown |
| `test` | Test changes | ❌ Hidden |
| `build` | Build system changes | ❌ Hidden |
| `ci` | CI/CD changes | ❌ Hidden |
| `chore` | Maintenance tasks | ❌ Hidden |
| `revert` | Revert previous commit | ✅ Shown |

## Scope (optional but recommended)

| Scope | Usage |
|-------|-------|
| `core` | Core SQL modules (001-018) |
| `sql` | Extension SQL modules |
| `tests` | Test suite changes |
| `e2e` | End-to-end tests |
| `chaos` | Chaos engineering tests |
| `docs` | Documentation |
| `ci` | CI/CD workflows |
| `deps` | Dependencies |
| `config` | Configuration |
| `perf` | Performance |
| `security` | Security |
| `api` | API changes |
| `db` | Database schema |
| `ops` | Operations |
| `dev` | Development environment |
| `release` | Release management |

## Subject

- Use imperative, present tense: "add" not "added" or "adds"
- Don't capitalize first letter
- No period (.) at the end
- Minimum 10 characters
- Maximum 100 characters

## Body (optional)

- Use imperative, present tense
- Include motivation for the change
- Contrast with previous behavior
- Maximum 100 characters per line

## Footer (optional)

- Reference GitHub issues: `Fixes #123`, `Closes #456`
- Breaking changes: `BREAKING CHANGE: description`

## Examples

### Simple commit

```
feat(core): add three-way merge support
```

### With scope and body

```
fix(sql): resolve deadlock in concurrent commits

The previous implementation had a race condition when multiple
transactions committed to the same branch simultaneously. This
adds proper locking to prevent deadlocks.

Fixes #234
```

### Breaking change

```
feat(api): redesign branch creation API

BREAKING CHANGE: The `create_branch()` function now requires
a parent branch parameter. Update calls to:

  Old: SELECT pggit.create_branch('feature');
  New: SELECT pggit.create_branch('feature', 'main');
```

### Multiple types

```
feat(core): add copy-on-write data branching
test(chaos): add concurrency tests for data branching
docs(api): document new data branching functions
```

## Validation

Commits are validated:

1. **Locally**: Pre-commit hook (if installed)
   ```bash
   # Install
   npm install -g @commitlint/cli @commitlint/config-conventional

   # Manual check
   echo "feat(core): add new feature" | commitlint
   ```

2. **CI/CD**: Automated validation on PRs
   - Workflow: `.github/workflows/commitlint.yml`
   - All commits in PR must pass

## Tips

### Good commit messages

✅ `feat(core): add schema diff algorithm`
✅ `fix(sql): prevent null pointer in version check`
✅ `docs(api): update migration examples`
✅ `perf(core): optimize hash computation by 40%`
✅ `refactor(tests): extract common test fixtures`

### Bad commit messages

❌ `add feature` - too vague, no scope
❌ `Fix bug` - capitalized, no scope
❌ `docs: updated docs.` - period at end
❌ `wip` - not descriptive
❌ `asdfasdf` - meaningless

## Automated Changelog

pgGit uses [Release Please](https://github.com/googleapis/release-please) to automatically:

1. Generate changelog from commit messages
2. Determine version bump (major/minor/patch)
3. Create GitHub releases
4. Update version numbers

**Only commits with proper conventional format appear in the changelog!**

## Workflow

1. Make changes
2. Stage files: `git add .`
3. Commit with conventional format: `git commit`
4. Pre-commit hook validates message
5. Push to GitHub
6. PR validation runs on all commits
7. After merge, Release Please creates release PR
8. Merge release PR to publish new version

## Resources

- [Conventional Commits Specification](https://www.conventionalcommits.org/)
- [Commitlint Rules](https://commitlint.js.org/#/reference-rules)
- [Release Please Documentation](https://github.com/googleapis/release-please)
- [Semantic Versioning](https://semver.org/)

## Questions?

See issues or ask in discussions: https://github.com/evoludigit/pgGit/discussions
