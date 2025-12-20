# Security Audit Checklist

## Overview
This checklist covers security-critical aspects of pgGit for community review.

## SQL Injection Vulnerabilities

### Dynamic SQL Safety
- [ ] All dynamic SQL uses `quote_ident()` or `quote_literal()`
- [ ] No string concatenation for SQL generation
- [ ] `format()` used with `%I` and `%L` specifiers for identifiers and literals
- [ ] User input never directly inserted into SQL strings

### Event Trigger Security
- [ ] DDL event triggers don't execute arbitrary SQL from user input
- [ ] Event trigger functions validate input parameters
- [ ] No privilege escalation through event triggers

## Privilege Escalation Risks

### Function Security
- [ ] No `SECURITY DEFINER` functions without explicit permission checks
- [ ] Functions respect current user's permissions
- [ ] Superuser-only operations are clearly documented

### Schema Access
- [ ] pgGit schema permissions are minimal and documented
- [ ] No automatic privilege grants to users
- [ ] Schema access follows principle of least privilege

## Data Exposure Vulnerabilities

### Audit Trail Security
- [ ] Audit logs don't leak sensitive data
- [ ] Query text is sanitized before storage
- [ ] User-supplied content is escaped in logs

### Information Disclosure
- [ ] Error messages don't reveal internal structure
- [ ] Function results don't expose unauthorized data
- [ ] Metadata access is properly restricted

## Input Validation

### Parameter Validation
- [ ] All user inputs are validated
- [ ] Branch names validated (no SQL injection chars)
- [ ] Object names checked against catalog
- [ ] Schema names validated

### Command Processing
- [ ] DDL commands parsed safely
- [ ] No command execution from user input
- [ ] Command tags validated against whitelist

## Access Control

### Authentication Integration
- [ ] No built-in authentication (uses PostgreSQL auth)
- [ ] Session management follows PostgreSQL security model
- [ ] No password storage or handling

### Authorization Checks
- [ ] Object ownership verified before operations
- [ ] Schema permissions checked
- [ ] Cross-schema operations validated

## Automated Security Checks

### Semgrep Rules
```bash
# Run automated security scans
semgrep --config=p/sql-injection core/sql/ sql/
semgrep --config=p/privilege-escalation core/sql/ sql/

# Check for dangerous patterns
grep -rn "EXECUTE.*||" core/sql/ sql/  # String concatenation
grep -rn "SECURITY DEFINER" core/sql/ sql/  # Elevated privileges
grep -rn "format.*%s" core/sql/ sql/  # Unquoted format strings
```

## Audit Scope

### High Priority Files
1. `core/sql/002_event_triggers.sql` - DDL capture logic
2. `core/sql/006_git_implementation.sql` - Core operations
3. `core/sql/007_ddl_parser.sql` - SQL parsing
4. `sql/pggit_configuration.sql` - User configuration

### Medium Priority Files
- Migration functions
- Utility functions
- View definitions

## Security Testing

### Test Cases to Verify
```sql
-- Test SQL injection attempts
SELECT pggit.create_branch('malicious; DROP TABLE users; --');

-- Test privilege escalation
-- (As non-superuser) attempt operations requiring elevated privileges

-- Test data exposure
-- Check if sensitive information appears in logs
```

## Community Review Process

1. **Self-Assessment**: Core team reviews checklist
2. **Issue Creation**: Open security audit request issue
3. **Community Review**: 2-week review period
4. **Fix Implementation**: Address findings
5. **Final Report**: Publish security assessment

## Security Contacts

- **Report Security Issues**: [SECURITY.md contact]
- **Audit Coordination**: GitHub security advisory
- **Responsible Disclosure**: 90-day disclosure period