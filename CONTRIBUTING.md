# Contributing to pgGit

Thank you for your interest in contributing to pgGit! We're excited to have you here.

pgGit is an open-source PostgreSQL extension that brings Git-like version control to databases. Whether you're fixing a bug, adding a feature, improving documentation, or just asking questions, your contribution is valuable.

## 🌟 Ways to Contribute

There are many ways to contribute to pgGit:

- **🐛 Report bugs** - Found something broken? Let us know!
- **💡 Suggest features** - Have an idea? We'd love to hear it!
- **📝 Improve documentation** - Help others understand pgGit better
- **🧪 Write tests** - Increase our test coverage
- **💻 Submit code changes** - Fix bugs or implement features
- **🎨 Improve examples** - Add real-world use cases
- **💬 Answer questions** - Help others in GitHub Discussions
- **⭐ Star the repo** - Show your support and help others discover pgGit

## 🚀 Getting Started

### Prerequisites

Before you begin, make sure you have:

- **PostgreSQL 15, 16, or 17** installed
- **C compiler** (gcc or clang)
- **PostgreSQL development headers** (`postgresql-server-dev-*` package)
- **Git** for version control
- **Make** for building
- **Python 3.8+** and **pytest** for running tests

### Development Setup

1. **Fork the repository**
   ```bash
   # Click "Fork" on GitHub, then clone your fork
   git clone https://github.com/YOUR_USERNAME/pgGit.git
   cd pgGit
   ```

2. **Add the upstream remote**
   ```bash
   git remote add upstream https://github.com/evoludigit/pgGit.git
   ```

3. **Install dependencies**
   ```bash
   # Install Python dependencies
   pip install -r requirements-dev.txt

   # Install pre-commit hooks (see section below)
   pre-commit install
   pre-commit install --hook-type pre-push
   ```

4. **Build the extension**
   ```bash
   make clean
   make
   ```

5. **Install locally (for testing)**
   ```bash
   sudo make install
   ```

6. **Run tests**
   ```bash
   make test
   ```

   All tests should pass. If any fail, please report it as a bug!

## 🏷️ Good First Issues

New to pgGit? Look for issues labeled [`good first issue`](https://github.com/evoludigit/pgGit/labels/good%20first%20issue).

**Great starter tasks:**
- Improving error messages
- Adding examples to documentation
- Writing tests for untested edge cases
- Fixing typos or formatting
- Adding code comments

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

## 💻 Code Style

pgGit follows PostgreSQL extension coding conventions:

### Python Code Style
- **Formatter**: Black (line length 88)
- **Linter**: Ruff
- **Type hints**: Required for public APIs
- **Docstrings**: Google style

### SQL Code Style
- **Keywords**: UPPERCASE (e.g., `CREATE`, `SELECT`)
- **Identifiers**: lowercase (e.g., `table_name`)
- **Indentation**: 4 spaces
- **Functions**: `pggit.function_name()` (use schema prefix)

### C Code Style
(For PostgreSQL extension C code, if applicable)
- **Indentation**: Tabs (width 4)
- **Line length**: Max 80 characters
- **Naming**:
  - Functions: `snake_case` (e.g., `pggit_create_branch`)
  - Types: `PascalCase` with `Pggit` prefix
  - Macros: `UPPER_SNAKE_CASE`

## 🐛 Reporting Bugs

**Before reporting:**
1. Check if the bug is already reported in [Issues](https://github.com/evoludigit/pgGit/issues)
2. Try the latest version from `main` branch
3. Gather reproduction steps

**Bug report should include:**
- Clear description of the bug
- Steps to reproduce
- Expected vs. actual behavior
- Environment (pgGit version, PostgreSQL version, OS)
- Error messages or logs
- SQL code that reproduces the issue

## 💡 Suggesting Features

We love new ideas! Before suggesting a feature:

1. Check [GitHub Discussions](https://github.com/evoludigit/pgGit/discussions) to see if it's been discussed
2. Consider if it aligns with pgGit's goals (Git-like database version control)
3. Think about the implementation complexity

**Feature request should include:**
- Problem this feature would solve
- Proposed solution
- Alternatives considered
- Real-world use case

## 🤝 Code of Conduct

### Our Standards

- **Be respectful**: Treat everyone with kindness and professionalism
- **Be constructive**: Provide helpful feedback
- **Be patient**: Remember that contributors have different experience levels
- **Be inclusive**: Welcome people of all backgrounds

### Unacceptable Behavior

- Harassment or discrimination
- Trolling or insulting comments
- Publishing others' private information
- Any conduct that would be inappropriate in a professional setting

## 📞 Getting Help

**Need help contributing?**

- **GitHub Discussions**: [Ask questions](https://github.com/evoludigit/pgGit/discussions)
- **Issues**: [Browse existing issues](https://github.com/evoludigit/pgGit/issues)
- **Documentation**: [pgGit Docs](https://pggit.dev)

## 🎓 Learning Resources

**PostgreSQL Extension Development:**
- [PostgreSQL Extension Documentation](https://www.postgresql.org/docs/current/extend.html)
- [PostgreSQL Server Programming Interface (SPI)](https://www.postgresql.org/docs/current/spi.html)

**pgGit Architecture:**
- [Architecture Overview](https://pggit.dev/reference/architecture/)
- [User Guide](https://pggit.dev/guides/user-guide/)
- [Database Branching Guide](https://pggit.dev/guides/branching/)

## 🙏 Recognition

All contributors will be:
- Listed in the project README
- Mentioned in release notes (for significant contributions)
- Given credit in commit messages

## 📜 License

By contributing to pgGit, you agree that your contributions will be licensed under the [MIT License](LICENSE).

---

**Thank you for contributing to pgGit!** 🎉

Every contribution, no matter how small, makes a difference. Whether you're fixing a typo or implementing a major feature, you're helping make database version control accessible to everyone.

Happy coding! 🚀