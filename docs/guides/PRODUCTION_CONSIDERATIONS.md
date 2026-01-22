# pgGit in Production: Considerations and Trade-offs

This document explains when pgGit makes sense in production and when it doesn't.

## TL;DR

**Default recommendation**: Use pgGit in development, migration tools in production.

**Exception**: If your compliance requirements demand automatic DDL audit trails beyond what migration tools provide, pgGit can be deployed in production with appropriate considerations.

---

## When pgGit in Production Makes Sense

### 1. Compliance and Audit Requirements

If your organization is subject to regulatory compliance, pgGit provides automatic DDL audit trails.

**Applicable regulations**:

| Region | Regulation | Sector | Audit Requirement |
|--------|------------|--------|-------------------|
| **Intl** | CIS Controls | All sectors | Technical security benchmarks |
| **Intl** | ISO 27001 | All sectors | Information security management |
| **Intl** | NIST CSF | All sectors | Cybersecurity framework |
| **Intl** | PCI-DSS | Payments | Cardholder data protection |
| **Intl** | SOC 2 Type II | Service providers | Trust service criteria |
| **EU** | DORA | Financial services | ICT risk management, resilience |
| **EU** | eIDAS | Digital services | Electronic identification |
| **EU** | EU AI Act | AI systems | AI system transparency, audit trails |
| **EU** | GDPR | All sectors | Data protection, breach notification |
| **EU** | MiCA | Crypto/fintech | Markets in Crypto-Assets regulation |
| **EU** | NIS2 | Critical infrastructure | Cybersecurity incident reporting |
| **UK** | FCA regulations | Financial services | Financial Conduct Authority requirements |
| **UK** | UK GDPR | All sectors | Data protection (post-Brexit) |
| **US** | FedRAMP | Government | Security controls |
| **US** | HIPAA | Healthcare | Access and change logging |
| **US** | HITRUST | Healthcare | Health information trust certification |
| **US** | SOX | Public companies | Financial data integrity |
| **Industry** | GxP | Pharma/life sciences | FDA-regulated data integrity |
| **Industry** | NERC CIP | Energy/utilities | Critical infrastructure protection |
| **Regional** | APPI | Japan | Data protection |
| **Regional** | LGPD | Brazil | Data protection (GDPR-like) |
| **Regional** | PDPA | Singapore/Thailand | Data protection |
| **Regional** | PIPEDA | Canada | Privacy law |

**What pgGit provides**:

| Requirement | Migration Tools | pgGit |
|-------------|-----------------|-------|
| Track planned changes | Yes | Yes |
| Track ad-hoc/emergency changes | No | **Yes** |
| Automatic capture (no manual step) | No | **Yes** |
| Immutable audit trail | Varies | **Yes** |
| Who/what/when attribution | Basic | **Detailed** |
| Detect unauthorized changes | No | **Yes** |

**Example**: A developer runs an emergency `ALTER TABLE` directly on production to fix a critical bug. Migration tools won't capture this. pgGit will.

### 2. Schema Drift Detection

pgGit can detect when production schema differs from expected state:

```sql
-- Compare actual schema against what migrations should have created
SELECT * FROM pggit.detect_schema_drift();

-- Find changes that weren't in migration files
SELECT * FROM pggit.log()
WHERE change_source != 'migration_tool';
```

### 3. Security Monitoring

Track all DDL activity for security analysis:

```sql
-- Recent schema changes by user
SELECT changed_by, object_name, change_type, changed_at
FROM pggit.audit_log
WHERE changed_at > NOW() - INTERVAL '24 hours'
ORDER BY changed_at DESC;

-- Alert on unexpected changes
-- (integrate with your monitoring system)
```

### 4. Forensic Analysis

When something goes wrong, pgGit provides detailed history:

```sql
-- What changed around the time of the incident?
SELECT * FROM pggit.log()
WHERE changed_at BETWEEN '2026-01-20 14:00' AND '2026-01-20 16:00';

-- Who modified this table and when?
SELECT * FROM pggit.get_history('critical_table');
```

---

## When pgGit in Production Doesn't Make Sense

### 1. High-Availability Setups (Without Compliance Needs)

pgGit uses event triggers that fire on every DDL command:

```sql
CREATE EVENT TRIGGER pggit_ddl_tracker ON ddl_command_end
EXECUTE FUNCTION pggit.track_ddl_change();
```

**Impact**:
- Adds latency to migrations (typically milliseconds)
- Additional transaction work
- More components that could fail

If you don't need compliance-level audit trails, this overhead provides no benefit.

### 2. Simple Applications

For straightforward applications where:
- One team manages the database
- All changes go through migrations
- No regulatory requirements

Migration tools alone are sufficient.

### 3. Replication Complexity

pgGit tables and triggers can complicate replication:

- **Logical replication**: Decide whether to replicate pgGit tables
- **Physical replication**: Triggers fire on primary only
- **Read replicas**: pgGit state may differ from primary

This is manageable but requires planning.

---

## Technical Considerations for Production Deployment

### Event Trigger Overhead

pgGit triggers execute within the same transaction as DDL:

```
Without pgGit:
DDL Statement → PostgreSQL → Commit
(~10ms for typical ALTER)

With pgGit:
DDL Statement → Event Trigger → pgGit Function → Write Audit → PostgreSQL → Commit
(~15-25ms for typical ALTER)
```

**In practice**: DDL is rare in production. The overhead only affects schema changes, not normal queries. For most systems, this is negligible.

### Storage Growth

pgGit maintains history tables that grow over time:

```sql
-- Monitor pgGit storage usage
SELECT pg_size_pretty(pg_total_relation_size('pggit_audit.audit_log'));

-- Configure retention policy
SELECT pggit.set_audit_retention_days(365);  -- Keep 1 year for compliance
```

### Failure Modes

If pgGit trigger fails, the DDL statement fails:

```
Migration → Event Trigger (FAILS) → DDL Rolled Back
```

**Mitigation**:
- Test migrations on staging with pgGit installed
- pgGit is designed to be robust, but test your specific workload

---

## Decision Framework

### Use pgGit in Production If:

- [ ] You have compliance requirements for DDL audit trails
- [ ] You need to detect unauthorized schema changes
- [ ] You want forensic capabilities for incident response
- [ ] Schema changes are infrequent (typical for production)
- [ ] You've tested the overhead in staging

### Skip pgGit in Production If:

- [ ] Migration tools meet all your audit needs
- [ ] Simplicity is more important than detailed tracking
- [ ] You have unusual DDL patterns (frequent schema changes)
- [ ] Replication complexity is a concern

---

## Hybrid Approach: Best of Both Worlds

Many organizations use pgGit in development AND production:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  LOCAL DEV DB   │     │   STAGING DB    │     │  PRODUCTION DB  │
│  + pgGit        │ ──► │   + pgGit       │ ──► │  + pgGit        │
│                 │     │                 │     │  (optional)     │
│ Branch, merge,  │     │ Validate merges │     │ Audit trail,    │
│ experiment      │     │ Test workflows  │     │ compliance,     │
│                 │     │                 │     │ drift detection │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        │                       │                       │
        ▼                       ▼                       ▼
   Development              Testing                Production
   workflows               validation             audit/compliance
```

**Development**: Full pgGit features (branching, merging, time-travel)

**Production**: Audit-only mode (tracking, compliance, no branching needed)

---

## Production Deployment Checklist

If deploying pgGit to production:

### Pre-Deployment

- [ ] Document compliance requirements that justify pgGit
- [ ] Test on staging with production-like workload
- [ ] Measure DDL overhead (should be minimal)
- [ ] Plan audit log retention policy
- [ ] Review replication implications (if applicable)

### Configuration

```sql
-- Configure for production audit-only mode
SELECT pggit.configure_tracking(
    track_schemas => ARRAY['public', 'api'],  -- Schemas to audit
    ignore_schemas => ARRAY['pg_catalog'],    -- System schemas
    audit_mode => true                        -- Disable branching features
);

-- Set retention policy
SELECT pggit.set_audit_retention_days(365);  -- Compliance: 1 year

-- Enable alerting integration
SELECT pggit.configure_alerts(
    webhook_url => 'https://your-monitoring-system/webhook'
);
```

### Monitoring

```sql
-- Create monitoring view
CREATE VIEW pggit_production_health AS
SELECT
    (SELECT COUNT(*) FROM pggit_audit.audit_log
     WHERE timestamp > NOW() - INTERVAL '1 hour') as changes_last_hour,
    (SELECT pg_size_pretty(pg_total_relation_size('pggit_audit.audit_log'))) as audit_log_size,
    (SELECT MAX(timestamp) FROM pggit_audit.audit_log) as last_change;
```

---

## Comparison: Migration Tools vs pgGit for Compliance

| Aspect | Migration Tools Only | pgGit in Production |
|--------|---------------------|---------------------|
| Planned changes tracked | Yes | Yes |
| Ad-hoc changes tracked | No | **Yes** |
| Emergency fixes captured | No | **Yes** |
| Automatic (no manual step) | No | **Yes** |
| Audit trail integrity | Depends on Git | **Immutable in DB** |
| Query audit history | Limited | **Rich SQL queries** |
| Storage overhead | None | Small (audit tables) |
| DDL overhead | None | Minimal (~10-15ms) |
| Complexity | Lower | Higher |

---

## FAQ

### "Our auditors want proof of all schema changes"

pgGit provides exactly this. Deploy to production and configure retention to meet your compliance window (typically 1-7 years).

### "What if someone bypasses migrations and runs DDL directly?"

Without pgGit: You might never know.
With pgGit: Every DDL command is captured with timestamp and user attribution.

### "Is the event trigger overhead significant?"

For typical production systems (rare DDL), the overhead is negligible. DDL operations might take 15-25ms instead of 10ms. Normal queries are unaffected.

### "Can I use pgGit for audit only, without branching features?"

Yes. Configure `audit_mode => true` to disable branching and use pgGit purely for compliance tracking.

### "What about logical replication?"

Decide whether to include pgGit schemas in replication. For audit purposes, you typically want audit data on the primary only.

---

## Summary

| Scenario | Recommendation |
|----------|----------------|
| Development database | **Always use pgGit** |
| Staging database | **Always use pgGit** |
| Production (no compliance needs) | Migration tools sufficient |
| Production (compliance required) | **Consider pgGit** |
| Production (security monitoring) | **Consider pgGit** |

pgGit in production is a trade-off: small overhead in exchange for comprehensive audit capabilities. Make the decision based on your specific compliance and operational requirements.

---

## Related Documentation

- [Development Workflow Guide](DEVELOPMENT_WORKFLOW.md) - Using pgGit in development
- [Installation Guide](../INSTALLATION.md) - Setup instructions
- [Compliance Guide](../compliance/FIPS_COMPLIANCE.md) - FIPS 140-2 compliance
- [SOC2 Preparation](../compliance/SOC2_PREPARATION.md) - SOC2 audit readiness
