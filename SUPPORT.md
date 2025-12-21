# Support & Help for pgGit

**How to get help, report issues, and get community support for pgGit**

---

## Quick Help

### I have a question about pgGit

**Documentation first** - Most questions are answered in our comprehensive documentation:

1. **[Getting Started](docs/Getting_Started.md)** - Installation and first steps (5 minutes)
2. **[API Reference](docs/API_Reference.md)** - All functions explained with examples
3. **[Integration Guide](docs/pggit_v0_integration_guide.md)** - Real-world workflow patterns
4. **[Troubleshooting](docs/getting-started/Troubleshooting.md)** - Common problems and solutions
5. **[GLOSSARY](docs/GLOSSARY.md)** - Technical terms explained
6. **[Documentation Index](docs/INDEX.md)** - Find docs by user role or feature

**Still can't find the answer?** Open a GitHub Discussion (see below).

---

### I found a bug

**Report it on GitHub**:

1. Go to [pgGit Issues](https://github.com/evoludigit/pgGit/issues)
2. Click "New issue"
3. Choose template: "Bug report"
4. Fill in:
   - What you were doing
   - What you expected to happen
   - What actually happened
   - Your PostgreSQL and pgGit versions
   - Steps to reproduce (with code example)
5. Click "Submit new issue"

**Before reporting**, check:
- [ ] You're using the latest pgGit version
- [ ] Your PostgreSQL version is supported (see [Getting Started](docs/Getting_Started.md))
- [ ] You've checked [Troubleshooting](docs/getting-started/Troubleshooting.md) for similar issues
- [ ] You've searched existing issues for similar reports

---

### I have a feature request

**Suggest it on GitHub Discussions**:

1. Go to [pgGit Discussions](https://github.com/evoludigit/pgGit/discussions)
2. Click "New discussion"
3. Category: "Ideas"
4. Explain:
   - What you want to do
   - Why it would be useful
   - How you imagine it working
5. Submit

**Example**:
> **Title**: Request: Copy-on-write for data branches
>
> **Description**: When creating a data branch from a 100GB database, I'd like pgGit to use copy-on-write so the new branch starts at 5MB instead of 100GB. This would speed up our dev environment creation.

---

### I found a security vulnerability

**DO NOT create a GitHub issue for security vulnerabilities.**

See [SECURITY.md](SECURITY.md) for responsible disclosure procedure.

---

## Support Channels

### GitHub Issues (Bug Reports)
**Best for**: Bugs, errors, reproducible problems
**Response time**: 24-48 hours
**Link**: https://github.com/evoludigit/pgGit/issues

```
Examples of good bug reports:
- "ALTER TABLE fails with 'permission denied' on Windows"
- "merge_branch doesn't detect conflicts between 'age' column modifications"
- "Performance degrades with 100GB+ databases"
```

### GitHub Discussions (Questions & Ideas)
**Best for**: Questions, feature requests, best practices, discussion
**Response time**: 24-72 hours
**Link**: https://github.com/evoludigit/pgGit/discussions

**Categories**:
- **Q&A**: "How do I...?" questions
- **Ideas**: Feature requests and suggestions
- **Show & Tell**: Share your pgGit projects
- **Announcements**: New releases and updates

```
Examples of good discussions:
- "How do I structure branches for a microservices project?"
- "What's the best way to audit schema changes?"
- "Feature request: support for Oracle databases"
```

### Documentation Issues
**Best for**: Errors or outdated information in docs
**Response time**: 24 hours
**Link**: https://github.com/evoludigit/pgGit/issues/new?labels=docs

Include in your issue:
- Which doc has the problem
- What's wrong (outdated, unclear, incorrect)
- What it should say
- URL of the doc

---

## Learning Resources

### For Beginners
1. **[Getting Started](docs/Getting_Started.md)** (5 min)
   - Installation and setup
   - Your first database branch

2. **[Explained Like I'm 10](docs/getting-started/PgGit_Explained_Like_Im_10.md)** (10 min)
   - Simple conceptual overview
   - No technical knowledge required

3. **[Onboarding Guide](docs/Onboarding_Guide.md)** (2-4 hours)
   - Structured learning path with exercises

### For Developers
1. **[Integration Guide](docs/pggit_v0_integration_guide.md)**
   - How to use pgGit in your applications
   - Code examples and patterns

2. **[API Reference](docs/API_Reference.md)**
   - All 50+ functions documented
   - With real-world examples

3. **[Pattern Examples](docs/Pattern_Examples.md)**
   - Common development scenarios
   - Best practices and workflows

### For Database Administrators
1. **[Operations Runbook](docs/operations/RUNBOOK.md)**
   - Production procedures
   - Incident response
   - Maintenance tasks

2. **[Monitoring Guide](docs/operations/MONITORING.md)**
   - Health checks and alerting
   - Prometheus integration

3. **[Performance Tuning](docs/guides/PERFORMANCE_TUNING.md)**
   - Optimization for large databases (100GB+)
   - Benchmarking procedures

### For Security & Compliance Teams
1. **[Security Hardening Guide](docs/guides/Security.md)**
   - 30+ security checklist items
   - Implementation guidance

2. **[FIPS 140-2 Compliance](docs/compliance/FIPS_COMPLIANCE.md)**
   - Regulated industry requirements

3. **[SOC2 Preparation](docs/compliance/SOC2_PREPARATION.md)**
   - Trust Service Criteria mapping

---

## Common Questions (FAQ)

### Installation & Setup

**Q: What versions of PostgreSQL does pgGit support?**
A: PostgreSQL 12 and later. See [Getting Started](docs/Getting_Started.md) for detailed version matrix.

**Q: Can I install pgGit on Windows?**
A: Yes, using Docker. See [Getting Started - Docker Installation](docs/Getting_Started.md#installation-with-docker).

**Q: Does pgGit work with PostgreSQL cloud services?**
A: Yes (AWS RDS, Google Cloud SQL, Azure Database for PostgreSQL). See [Getting Started](docs/Getting_Started.md) for cloud-specific setup.

### Basic Usage

**Q: How do I create my first branch?**
A: See [Getting Started](docs/Getting_Started.md) for step-by-step instructions.

**Q: Can I branch from a branch?**
A: Yes. Use `SELECT pggit_v0.create_branch('parent_branch_name', 'new_branch_name');`

**Q: How do I merge changes back to main?**
A: See [Integration Guide - Merging](docs/pggit_v0_integration_guide.md#merging-branches).

### Performance & Scalability

**Q: How does pgGit perform with large databases (100GB+)?**
A: pgGit uses copy-on-write for efficient branching. See [Performance Analysis](docs/Performance_Analysis.md) for benchmarks.

**Q: Can I use pgGit for data as well as schema?**
A: pgGit currently tracks DDL (schema changes) only, not DML (data changes). Data branches preserve data state but pgGit doesn't version data modifications.

**Q: What's the maximum database size pgGit can handle?**
A: Tested with 500GB+ databases. See [Performance Tuning](docs/guides/PERFORMANCE_TUNING.md) for optimization strategies.

### Troubleshooting

**Q: I get a "permission denied" error. What should I do?**
A: See [Troubleshooting - Permission Errors](docs/getting-started/Troubleshooting.md#permission-errors).

**Q: My merge has conflicts. How do I resolve them?**
A: See [Conflict Resolution Guide](docs/conflict-resolution-and-operations.md).

**Q: pgGit commands are running slowly. How can I speed them up?**
A: See [Performance Tuning Guide](docs/guides/PERFORMANCE_TUNING.md) for optimization recommendations.

---

## Troubleshooting Steps

### Step 1: Check Documentation
- Search [Documentation Index](docs/INDEX.md) for your topic
- Read [Troubleshooting Guide](docs/getting-started/Troubleshooting.md)
- Check [GLOSSARY](docs/GLOSSARY.md) for unfamiliar terms

### Step 2: Gather Diagnostic Information
```bash
# Check your pgGit version
SELECT pggit_v0.version();

# Check PostgreSQL version
SELECT version();

# Check pgGit tables exist
SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = 'pggit_v0';

# Check for recent errors
SELECT * FROM pggit_audit.audit_log ORDER BY timestamp DESC LIMIT 10;
```

### Step 3: Try to Reproduce the Issue
- Create a minimal example that shows the problem
- Document the exact steps to reproduce
- Include expected vs actual results

### Step 4: Search Existing Issues
- Search [GitHub Issues](https://github.com/evoludigit/pgGit/issues) for similar problems
- Add your information to existing issues if relevant

### Step 5: Create a Report
- Open a [GitHub Issue](https://github.com/evoludigit/pgGit/issues/new?template=bug_report.md)
- Include diagnostic information from Step 2
- Provide reproduction steps from Step 3

---

## Reporting Guidelines

### For Bug Reports

Include ALL of:
- [ ] pgGit version
- [ ] PostgreSQL version
- [ ] Operating system (Windows/Mac/Linux)
- [ ] Exact error message (copy-paste, not paraphrased)
- [ ] Steps to reproduce (with SQL or code)
- [ ] Expected behavior
- [ ] Actual behavior
- [ ] Relevant logs or stack trace

### For Feature Requests

Include:
- [ ] Use case: Why this feature matters
- [ ] Expected behavior: How it should work
- [ ] Examples: Proposed SQL syntax or API
- [ ] Alternatives: Other ways to accomplish this
- [ ] Priority: Critical / High / Medium / Low

### For Documentation Issues

Include:
- [ ] Which documentation (file name)
- [ ] What's wrong (outdated / unclear / incorrect)
- [ ] Link to the problematic section
- [ ] What should it say instead

---

## Communication Standards

### Etiquette
- ✅ Be respectful and professional
- ✅ Search before asking (avoid duplicate questions)
- ✅ Provide complete information upfront
- ✅ Follow up on your issues/discussions
- ✅ Acknowledge solutions and thank helpers

### What NOT to Do
- ❌ Don't create duplicate issues (search first)
- ❌ Don't ask for urgent responses (we're volunteers)
- ❌ Don't report security issues publicly (see SECURITY.md)
- ❌ Don't demand new features
- ❌ Don't use issues for support questions (use Discussions)

---

## Getting Updates

### Release Notifications
- **Watch** [pgGit GitHub repository](https://github.com/evoludigit/pgGit)
- **Star** the repository to stay connected
- **Subscribe** to [GitHub Releases](https://github.com/evoludigit/pgGit/releases)

### Communication Channels
- **GitHub Discussions** - New announcements posted here
- **Changelog** - See [CHANGELOG.md](CHANGELOG.md) for version history
- **Release Notes** - Detailed in each [GitHub Release](https://github.com/evoludigit/pgGit/releases)

---

## Contributing to pgGit

Want to help improve pgGit? See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- How to submit pull requests
- Coding standards and conventions
- Testing requirements
- Documentation expectations

---

## Contact

- **Main Repository**: https://github.com/evoludigit/pgGit
- **Issues**: https://github.com/evoludigit/pgGit/issues
- **Discussions**: https://github.com/evoludigit/pgGit/discussions
- **Security**: See [SECURITY.md](SECURITY.md) for responsible disclosure

---

**Last Updated**: December 21, 2025
**Version**: pgGit v0.1.1
**Maintained By**: pgGit Team
