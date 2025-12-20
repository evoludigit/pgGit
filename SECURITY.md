# Security Policy

## Supported Versions

| Version | Supported          | Status |
| ------- | ------------------ | ------ |
| 0.1.x   | :warning: Experimental | Not for production |

## Reporting a Vulnerability

**DO NOT** open a public GitHub issue for security vulnerabilities.

### Reporting Process

1. **Email**: Send details to [your-email]@[domain]
    - Subject: "SECURITY: [brief description]"
    - Include: pgGit version, PostgreSQL version, description, reproduction steps

2. **Response Time**:
    - Initial acknowledgment: 48 hours
    - Status update: 7 days
    - Fix timeline: Based on severity

3. **Disclosure**:
    - We follow responsible disclosure (90 days)
    - You will be credited (unless you prefer anonymity)

### Security Best Practices

See [Security Guide](docs/guides/Security.md) for:
- Access control configuration
- Audit trail setup
- Production hardening

### Known Limitations

⚠️ **v0.1.x is experimental**:
- No security audit performed
- Not recommended for production
- Use at your own risk

## Security Features Status

| Feature | Status | Version |
|---------|--------|---------|
| DDL Audit Trail | ✅ Implemented | 0.1.0 |
| Event Trigger Security | ✅ Implemented | 0.1.0 |
| RBAC System | 🚧 Planned | Future |
| Compliance Reporting | 🚧 Planned | Future |