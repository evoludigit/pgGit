# pgGit Technical Glossary

**Quick reference for technical terms used in pgGit documentation**

---

## Core Concepts

### Content-Addressable Storage

A system where objects are identified and retrieved by their content hash rather than by location or name.

**In pgGit context**: Every schema commit gets a unique SHA-256 hash that represents its exact content. The same schema state always produces the same hash, ensuring integrity and enabling efficient change detection.

**Example**:
```
Commit: a1b2c3d4e5f6g7h8 (SHA-256 of schema content)
Same schema content always = same hash
Different schema content = different hash
```

**Why it matters**:
- Ensures data integrity
- Enables efficient change detection
- Allows identical schemas to be identified automatically

**Related**: Git commits, SHA-256 hashing, merkle trees

---

### Semantic Versioning

A versioning scheme using the format `vMAJOR.MINOR.PATCH` (e.g., v0.1.1) where:

- **MAJOR** (0): Major version - breaking changes require incrementing
- **MINOR** (1): Minor version - new features, backward-compatible
- **PATCH** (1): Patch version - bug fixes, backward-compatible

**In pgGit context**:
- v0.x.y = stable API, backward-compatible releases within the 0 series
- v1.0.0+ = future versions if breaking changes are needed

**Example**:
```
v0.1.0 → v0.1.1  (patch release, always backward-compatible)
v0.1.1 → v0.2.0  (minor release, new features, backward-compatible)
v0.x.x → v1.0.0  (major release, breaking changes allowed)
```

**Why it matters**:
- Users understand what to expect from version changes
- Backward-compatibility guarantees for v0.x.y
- Clear upgrade paths

**Related**: Version compatibility, breaking changes, API stability

---

### Copy-On-Write (COW)

A memory/storage optimization technique where data is initially shared between a parent and child copy. When data is modified, only the changes are stored, not the entire copy.

**In pgGit context**: When creating a branch:
1. New branch initially shares all data with parent (zero storage overhead)
2. When schema changes, only the changes are stored
3. Efficient storage: 100GB database branch uses ~5GB initially

**Example**:
```
Parent branch: users, orders, products tables (100GB)

Create feature branch (copy-on-write):
Initial size: 5MB (metadata only, no data duplication)
After ALTER TABLE: 5MB + delta storage
After INSERT: 5MB + delta storage

Without COW: ~100GB duplicate storage!
```

**Why it matters**:
- Enables efficient branching for large databases
- Minimal storage overhead for multiple branches
- Fast branch creation (no copying data)

**Related**: Branching, storage efficiency, forking

---

### DDL (Data Definition Language)

SQL statements that define or modify database structure (not data itself).

**Common DDL statements**:
- CREATE: CREATE TABLE, CREATE FUNCTION, CREATE INDEX
- ALTER: ALTER TABLE, ALTER FUNCTION, ALTER SCHEMA
- DROP: DROP TABLE, DROP FUNCTION, DROP VIEW
- TRUNCATE: Remove table contents

**In pgGit context**: pgGit specializes in tracking and versioning DDL changes. It captures what changed in the database structure and who changed it.

**Example**:
```sql
-- DDL statements (pgGit tracks these)
CREATE TABLE users (id SERIAL, name TEXT);
ALTER TABLE users ADD COLUMN email TEXT;
CREATE INDEX idx_email ON users(email);

-- DML statements (pgGit does NOT track data)
INSERT INTO users VALUES (1, 'Alice');
UPDATE users SET email = 'alice@example.com';
DELETE FROM users WHERE id = 1;
```

**Why it matters**:
- Separate from DML (data changes)
- Schema evolution tracking
- Regulatory compliance (audit trail of structure changes)

**Related**: DML, schema versioning, audit trail

---

### Commit

A snapshot of the schema at a point in time. Each commit contains:

- **Hash**: Unique SHA-256 identifier (content-addressable)
- **Author**: Who made the change
- **Timestamp**: When the change was made
- **Message**: Why the change was made (description)
- **Parent Commit**: Previous commit (forming a history chain)

**In pgGit context**: Similar to Git commits but for database schemas.

**Example**:
```
Commit: a1b2c3d4...
Author: alice@example.com
Date: 2025-12-21 10:30:00 UTC
Message: "Add users table with email column"
Parent: xyz789abc... (previous commit)
```

**Why it matters**:
- Enables complete history of schema changes
- Supports branching and merging
- Allows reverting to previous states
- Provides audit trail (who changed what when)

**Related**: Branch, merge, rebase, history

---

### Branch

An independent line of schema development. Each branch:

- Starts from a parent (usually 'main')
- Can change independently from parent
- Can be merged back to parent
- Doesn't affect other branches

**In pgGit context**: Like Git branches, but for database schemas.

**Example**:
```
main (production branch)
  ├── feature/new-api (in development)
  ├── feature/analytics (in development)
  └── hotfix/bug-fix (urgent production fix)

Each branch develops independently, then merges back to main
```

**Typical workflow**:
1. Create feature branch from main: `feature/user-auth`
2. Make schema changes in branch (isolated)
3. Test changes thoroughly
4. Merge back to main when ready

**Why it matters**:
- Multiple teams develop independently
- Reduces conflicts
- Enables testing before production
- Safe experimentation

**Related**: Merge, rebase, conflict, branching strategy

---

### Merge

Combining changes from one branch into another.

**Merge strategies available in pgGit**:
- **Recursive**: Find common ancestor, apply all changes (smart merging)
- **Ours**: Keep target branch's schema, discard source
- **Theirs**: Accept source branch's schema

**Example**:
```
Before merge:
  main: CREATE TABLE users (id, name)
  feature/email: ALTER TABLE users ADD COLUMN email

After recursive merge:
  result: CREATE TABLE users (id, name, email)
          (both changes applied)
```

**When conflicts occur**:
- Different changes to same object
- Incompatible modifications
- Requires manual resolution

**Why it matters**:
- Integrates parallel development
- Combines improvements from multiple branches
- Final schema represents all accepted changes

**Related**: Branch, rebase, conflict, merge strategy

---

### Rebase

Replaying one branch's changes on top of a newer parent branch.

**When to use**:
- Parent branch (main) changed since feature branch created
- Want to include new main features in feature branch
- Clean commit history (alternative to merge)

**Example**:
```
Before rebase:
  main: A → B → C
  feature: B → X → Y

After rebase:
  main: A → B → C
  feature: A → B → C → X → Y
  (feature replayed on top of updated main)
```

**Why it matters**:
- Clean, linear history
- Easier to understand what changed
- Simpler merges (fewer conflicts)

**Related**: Merge, commit, branch

---

### Conflict

When two branches make incompatible changes to the same schema object.

**Types of conflicts**:
- **Schema conflict**: Both branches modify same table/function differently
- **Dependency conflict**: One branch drops object that another branch uses
- **Type conflict**: Different schema changes are fundamentally incompatible

**Example**:
```
Branch A: ALTER TABLE users ADD COLUMN age INT
Branch B: ALTER TABLE users DROP COLUMN age

Conflict: Can't apply both changes!
Result: Manual resolution required
```

**Resolution strategies**:
1. Accept Branch A's change (ours)
2. Accept Branch B's change (theirs)
3. Manually merge both changes (combined)
4. Keep original schema (resolve as neither)

**Why it matters**:
- Prevents corrupting schema
- Forces explicit decision on conflicting changes
- Maintains data integrity

**Related**: Merge, branch, resolution strategy

---

## Version Control Concepts

### Schema Versioning

Tracking database schema changes over time using Git-like version control.

**Enables**:
- **History**: See what changed, when, and who changed it
- **Branching**: Parallel development of different schema versions
- **Auditing**: Complete change log for compliance
- **Recovery**: Revert to previous schema states if needed

**In pgGit**: Content-addressable versioning with commit history.

**Why it matters**:
- Database development becomes like code development
- Improved team collaboration
- Regulatory compliance (audit trail)
- Safe schema evolution

**Related**: Commit, branch, merge, content-addressable

---

### Deployment Mode

A special mode where pgGit automatically tracks all DDL changes without requiring manual commits.

**How it works**:
1. Enable deployment mode: `BEGIN DEPLOYMENT`
2. Make DDL changes (CREATE, ALTER, DROP)
3. pgGit captures all changes automatically
4. End deployment mode: `END DEPLOYMENT`
5. All changes are committed as one atomic unit

**When to use**:
- Automated deployment pipelines
- CI/CD integrations
- Automated schema migrations

**Why it matters**:
- Integrates seamlessly with deployment tools
- No manual commit required
- Atomic deployments (all changes succeed or all fail)

**Related**: Commit, transaction, deployment pipeline

---

### Audit Trail / Audit Log

An immutable record of all schema changes, including what changed and who changed it.

**Contains**:
- Object: What changed (table, function, index, etc.)
- Operation: CREATE, ALTER, DROP
- Author: Who made the change
- Timestamp: When the change was made
- Commit message: Why the change was made
- Before/After: Previous and new definitions (for ALTER)

**In pgGit context**: `pggit_audit` schema maintains immutable change history.

**Why it matters**:
- Compliance (regulatory requirements)
- Debugging (understand schema evolution)
- Forensics (who changed what and when)
- Rollback planning (see previous states)

**Related**: Compliance, change tracking, immutable

---

## Technical Terms

### SHA (Secure Hash Algorithm)

A cryptographic algorithm that produces a unique fingerprint (hash) of any data.

**In pgGit context**: Uses SHA-256 to create unique hashes for:
- Schema commits (full schema state)
- Objects (individual tables, functions)
- Enables content-addressable storage

**Properties**:
- Deterministic: Same input always produces same hash
- Unique: Different inputs produce different hashes
- One-way: Can't reverse hash to get original data
- Fixed size: SHA-256 always produces 256-bit (64 hex) hash

**Example**:
```
Schema state A → SHA-256 → a1b2c3d4e5f6...
Schema state A → SHA-256 → a1b2c3d4e5f6... (same!)
Schema state B → SHA-256 → f6e5d4c3b2a1... (different!)
```

**Why it matters**:
- Ensures integrity (hash changes if data changes)
- Enables efficient change detection
- Supports content-addressable storage

**Related**: Hash, content-addressable, commit

---

### SLO (Service Level Objective)

A target for system reliability and availability. Measured as uptime percentage.

**Common SLOs**:
- 99.0% (two 9s) = 43 minutes downtime/month
- 99.9% (three 9s) = 4 minutes downtime/month
- 99.99% (four 9s) = 26 seconds downtime/month

**In pgGit context**: Operations teams set SLO targets and monitor pgGit to ensure compliance.

**Why it matters**:
- Sets clear reliability expectations
- Guides operations decisions (redundancy, monitoring)
- Supports service contracts

**Related**: Availability, monitoring, uptime

---

### CQRS (Command Query Responsibility Segregation)

An architectural pattern separating read operations (queries) from write operations (commands).

**In pgGit context**: Separate schemas for:
- **Command Schema** (pggit_v0): Write operations (commits, branches)
- **Query Schema** (pggit_audit): Immutable read access to history

**Why it matters**:
- Optimized read and write performance
- Audit trail remains immutable
- Scalability (can scale read and write independently)

**Related**: Architecture, audit, performance

---

### Immutable

Data that cannot be changed or deleted after creation.

**In pgGit context**: Audit logs are immutable:
- Can INSERT new audit records
- Cannot UPDATE existing audit records
- Cannot DELETE audit records
- Prevents tampering with historical records

**Why it matters**:
- Compliance (regulations require immutable audit trails)
- Forensics (proves what actually changed)
- Trust (audit trail can't be falsified)

**Related**: Audit trail, compliance, database design

---

### DDL Extraction

The process of detecting and capturing DDL changes from PostgreSQL commits.

**How it works**:
1. Scan committed DDL statements
2. Parse SQL to understand what changed
3. Classify as CREATE, ALTER, or DROP
4. Determine object type (TABLE, FUNCTION, VIEW, etc.)
5. Store change in audit trail

**Challenges**:
- Multiple SQL variations for same operation
- Partial modifications (ALTER doesn't show complete state)
- Implicit changes (dependencies)

**Why it matters**:
- Captures schema history automatically
- Enables audit trail creation
- Powers change tracking and analytics

**Related**: DDL, audit trail, change tracking

---

## Abbreviations

| Abbreviation | Meaning | Context |
|--------------|---------|---------|
| **DDL** | Data Definition Language | Schema changes (CREATE, ALTER, DROP) |
| **DML** | Data Manipulation Language | Data changes (INSERT, UPDATE, DELETE) |
| **CQRS** | Command Query Responsibility Segregation | Architecture pattern |
| **COW** | Copy-On-Write | Storage efficiency technique |
| **SHA** | Secure Hash Algorithm | Cryptographic hashing |
| **SLO** | Service Level Objective | Reliability target |
| **SOC2** | System and Organization Controls 2 | Compliance framework |
| **FIPS** | Federal Information Processing Standards | Cryptographic standards |
| **SLSA** | Supply chain Levels for Software Artifacts | Supply chain security |
| **PR** | Pull Request | Code review mechanism (Git) |
| **UUID** | Universally Unique Identifier | Unique identifier format |
| **API** | Application Programming Interface | Function interface |
| **DB** | Database | Relational database system |
| **ORM** | Object-Relational Mapping | Data mapping library |
| **HA** | High Availability | Redundancy and failover |
| **DR** | Disaster Recovery | Recovery procedures |

---

## Related Documentation

Need more details? Check these guides:

- **Getting Started**: [Getting_Started.md](Getting_Started.md) - Introduction to pgGit
- **Architecture**: [Architecture_Decision.md](Architecture_Decision.md) - Design decisions
- **API Reference**: [API_Reference.md](API_Reference.md) - Function documentation
- **Operations**: [operations/RUNBOOK.md](operations/RUNBOOK.md) - Production procedures
- **Integration**: [pggit_v0_integration_guide.md](pggit_v0_integration_guide.md) - Usage examples

---

**Last Updated**: December 31, 2025
**Version**: pgGit v0.1.3
**Questions**: See [Troubleshooting.md](getting-started/Troubleshooting.md) or [../README.md](../README.md) for support
