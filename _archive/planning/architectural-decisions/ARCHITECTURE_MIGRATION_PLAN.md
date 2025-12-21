# Architecture Migration Plan: pggit v1 → pggit v2 + Audit Layer

**Date**: 2025-12-21
**Status**: Planning Phase
**Scope**: Transition from name-based DDL tracking to Git-like content versioning
**Duration**: 3-4 weeks (phased approach)
**Breaking Changes**: Yes - requires coordinated rollout

---

## Executive Summary

Migrate from two separate schemas (`pggit` and `pggit_v0`) to a unified architecture:

```
CURRENT STATE:
  pggit (v1)     - Name-based DDL tracking (to be deprecated)
  pggit_v0       - Git-like model (to become primary)
  
NEW STATE:
  pggit_v0       - Primary versioning (Git-like)
  pggit_audit    - Audit layer (compliance, history extraction)
  pggit_v1       - Compatibility shim (deprecated, read-only)
```

**Benefits**:
- Single source of truth (pggit_v0)
- Real Git-semantics (merging, branching)
- Better team collaboration
- Audit trail via derived views/tables
- Clear deprecation path

---

## Phase 1: Prepare & Document (Week 1)

### 1.1 Create Audit Layer Design Document
**Objective**: Design what compliance data we need to extract from pggit_v0

**Tasks**:
- [ ] Document all current pggit audit queries
- [ ] Map audit needs to pggit_v0 structure
- [ ] Design audit view schema
- [ ] Plan performance implications

**Deliverables**:
- Audit schema design
- Migration queries (pggit → pggit_audit)
- View definitions for compliance reports

**Example Audit Views to Create**:
```sql
pggit_audit.change_history
  - When did each object change?
  - What changed (diff)?
  - Who changed it?
  - Why (commit message)?

pggit_audit.object_timeline
  - Version history of object X
  - All versions with timestamps

pggit_audit.breaking_changes
  - What changes broke existing schemas?
  - Dependency impact analysis

pggit_audit.compliance_report
  - Full audit trail for regulatory
  - Immutable change log
```

### 1.2 Create v1 Deprecation Notice
**Objective**: Notify users that pggit (v1) is being deprecated

**Tasks**:
- [ ] Create DEPRECATION.md
- [ ] Add migration guide
- [ ] Document pggit_v0 equivalents for each v1 function
- [ ] Provide clear timeline

**Deliverables**:
```
docs/DEPRECATION.md
  ├── v1 deprecation timeline
  ├── Migration guide (v1 → v2)
  ├── Function mapping
  ├── Breaking changes
  └── Support policy
```

### 1.3 Audit Current Usage
**Objective**: Understand what's actually using pggit (v1)

**Tasks**:
- [ ] Search codebase for pggit.* calls (not pggit_v0.*)
- [ ] Categorize by usage pattern
- [ ] Identify which are critical vs. nice-to-have
- [ ] Estimate migration effort per module

**Output**: Migration difficulty matrix

---

## Phase 2: Build Audit Layer (Weeks 1-2)

### 2.1 Create pggit_audit Schema
**Objective**: Build audit infrastructure on top of pggit_v0

**Create Tables**:
```sql
CREATE SCHEMA pggit_audit;

-- Track changes extracted from commits
CREATE TABLE pggit_audit.changes (
    change_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    commit_sha TEXT NOT NULL REFERENCES pggit_v0.objects(sha),
    object_name TEXT NOT NULL,  -- e.g., "public.users"
    object_type TEXT NOT NULL,  -- TABLE, FUNCTION, TYPE, etc.
    change_type TEXT NOT NULL,  -- CREATE, ALTER, DROP
    old_definition TEXT,        -- Previous DDL
    new_definition TEXT,        -- Current DDL
    change_diff TEXT,           -- What specifically changed
    author TEXT NOT NULL,       -- Who made the change
    committed_at TIMESTAMP NOT NULL,
    change_reason TEXT,         -- From commit message
    breaking_change BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT now()
);

-- Track object versions
CREATE TABLE pggit_audit.object_versions (
    version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    object_name TEXT NOT NULL,
    object_type TEXT NOT NULL,
    definition TEXT NOT NULL,
    commit_sha TEXT NOT NULL REFERENCES pggit_v0.objects(sha),
    version_number INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL,
    UNIQUE(object_name, version_number)
);

-- Compliance log (immutable)
CREATE TABLE pggit_audit.compliance_log (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    change_id UUID NOT NULL REFERENCES pggit_audit.changes(change_id),
    audit_timestamp TIMESTAMP DEFAULT now(),
    auditor TEXT DEFAULT current_user,
    verification_status TEXT DEFAULT 'pending',
    notes TEXT,
    -- Make immutable (no UPDATE/DELETE)
    created_at TIMESTAMP DEFAULT now() NOT NULL
);
```

**Indices**:
```sql
CREATE INDEX idx_changes_object ON pggit_audit.changes(object_name);
CREATE INDEX idx_changes_author ON pggit_audit.changes(author);
CREATE INDEX idx_changes_type ON pggit_audit.changes(change_type);
CREATE INDEX idx_changes_commit ON pggit_audit.changes(commit_sha);
CREATE INDEX idx_object_versions_name ON pggit_audit.object_versions(object_name);
```

### 2.2 Create Audit Functions
**Objective**: Extract audit data from pggit_v0 commits

**Functions to Create**:
```sql
-- Extract object changes between commits
CREATE FUNCTION pggit_audit.extract_changes_between_commits(
    p_from_commit TEXT,
    p_to_commit TEXT
) RETURNS TABLE (
    object_name TEXT,
    change_type TEXT,
    old_def TEXT,
    new_def TEXT
);

-- Populate change history from existing commits
CREATE FUNCTION pggit_audit.backfill_change_history()
    RETURNS integer;  -- Number of changes extracted

-- Generate compliance report
CREATE FUNCTION pggit_audit.generate_compliance_report(
    p_start_date TIMESTAMP,
    p_end_date TIMESTAMP
) RETURNS TABLE (
    object_name TEXT,
    change_count INTEGER,
    authors TEXT[],
    earliest_change TIMESTAMP,
    latest_change TIMESTAMP
);

-- Detect breaking changes
CREATE FUNCTION pggit_audit.detect_breaking_changes(
    p_commit_sha TEXT
) RETURNS TABLE (
    breaking_change TEXT,
    affected_objects TEXT[],
    severity TEXT
);
```

### 2.3 Create Audit Views (for easy access)
**Objective**: Simple queries for common audit needs

**Views to Create**:
```sql
CREATE VIEW pggit_audit.object_history AS
    SELECT 
        object_name,
        version_number,
        change_type,
        author,
        committed_at,
        change_reason
    FROM pggit_audit.object_versions
    ORDER BY object_name, version_number DESC;

CREATE VIEW pggit_audit.recent_changes AS
    SELECT 
        object_name,
        change_type,
        author,
        committed_at,
        change_reason,
        breaking_change
    FROM pggit_audit.changes
    ORDER BY committed_at DESC
    LIMIT 100;

CREATE VIEW pggit_audit.breaking_changes_log AS
    SELECT 
        change_id,
        object_name,
        change_type,
        old_definition,
        new_definition,
        author,
        committed_at,
        change_reason
    FROM pggit_audit.changes
    WHERE breaking_change = true
    ORDER BY committed_at DESC;
```

---

## Phase 3: Create v1 Compatibility Shim (Week 2)

### 3.1 Create pggit_v1 Compatibility Schema
**Objective**: Existing code continues working with read-only fallback

**Strategy**:
```sql
CREATE SCHEMA pggit_v1;  -- Deprecated, read-only

-- Redirect old functions to generate audit data from v2
-- Use views and functions that read from pggit_audit

-- For each old pggit.* function:
--   1. Create equivalent in pggit_v1.*
--   2. Function reads from pggit_audit tables
--   3. Add deprecation warning
--   4. Document in DEPRECATION.md
```

### 3.2 Create Compatibility Functions
**Example Pattern**:
```sql
-- OLD: SELECT * FROM pggit.get_object_version('public.users', 5);
-- NEW: SELECT * FROM pggit_v1.get_object_version('public.users', 5);
--      (reads from pggit_audit, emits deprecation warning)

CREATE OR REPLACE FUNCTION pggit_v1.get_object_version(
    p_object_name TEXT,
    p_version_number INTEGER
) RETURNS TABLE (
    definition TEXT,
    author TEXT,
    created_at TIMESTAMP
) AS $$
BEGIN
    RAISE WARNING 'DEPRECATED: pggit_v1.get_object_version() - use pggit_audit.object_versions instead';
    
    RETURN QUERY
    SELECT 
        ov.definition,
        ch.author,
        ch.committed_at
    FROM pggit_audit.object_versions ov
    JOIN pggit_audit.changes ch ON ch.change_id = ov.version_id
    WHERE ov.object_name = p_object_name
    AND ov.version_number = p_version_number;
END;
$$ LANGUAGE plpgsql;
```

### 3.3 Update install.sql
**Objective**: Include new audit layer in standard installation

**Changes**:
```sql
\i 001_schema.sql                           -- Keep (pggit core)
\i 002_event_triggers.sql
\i 003_migration_functions.sql
\i test_helpers.sql
\i 004_utility_views.sql
\i 009_ddl_hashing.sql
\i 017_performance_optimizations.sql
\i 020_git_core_implementation.sql
\i 030_ai_migration_analysis.sql
\i 040_size_management.sql
\i pggit_cqrs_support.sql
\i 051_data_branching_cow.sql
\i pggit_conflict_resolution_minimal.sql
\i pggit_diff_functionality.sql

-- NEW: pggit_v0 as primary (was already included)
\i core/sql/018_proper_git_three_way_merge.sql

-- NEW: Audit layer
\i sql/pggit_audit_layer.sql
\i sql/pggit_audit_functions.sql
\i sql/pggit_audit_views.sql

-- NEW: Compatibility shim (optional - can deprecate)
-- \i sql/pggit_v1_compat.sql
```

---

## Phase 4: Migration Tooling (Week 2-3)

### 4.1 Create Migration Scripts
**Objective**: Help users migrate from v1 to v2

**Scripts to Create**:
```
sql/migrate/
├── 001_analyze_v1_usage.sql        -- Show what's using v1
├── 002_extract_v1_history.sql      -- Convert v1 history → audit
├── 003_backfill_audit_from_v1.sql  -- Populate audit tables
├── 004_verify_migration.sql        -- Sanity checks
└── 005_cleanup_v1.sql              -- Optional: drop v1 (irreversible)
```

### 4.2 Create Migration Guide
**Objective**: Step-by-step migration for users

**Document**: docs/MIGRATION_V1_TO_V2.md
```markdown
# Migration Guide: pggit v1 → pggit v2

## Timeline
- 2025-12: Initial audit layer (Phase 2)
- 2026-01: v1 deprecation warnings (Phase 3)
- 2026-02: Recommended migration (Phase 4)
- 2026-06: v1 support ends
- 2026-12: v1 removed

## Step 1: Audit Current Usage
$ psql -f sql/migrate/001_analyze_v1_usage.sql

## Step 2: Update Code
Replace pggit.* calls with pggit_v0.* or pggit_audit.*

## Step 3: Run Migration
$ psql -f sql/migrate/002_extract_v1_history.sql
$ psql -f sql/migrate/003_backfill_audit_from_v1.sql

## Step 4: Verify
$ psql -f sql/migrate/004_verify_migration.sql

## Step 5: Disable v1 (Optional)
DROP SCHEMA pggit_v1 CASCADE;
```

### 4.3 Function Mapping Document
**Objective**: Clear equivalents for all v1 functions

**Reference Table**:
| v1 Function | v2 Equivalent | Audit View |
|------------|---------------|------------|
| pggit.get_object_version | pggit_audit.object_versions | pggit_audit.object_history |
| pggit.list_changes | pggit_audit.changes | pggit_audit.recent_changes |
| pggit.detect_schema_changes | pggit_v0.diff_schemas | pggit_audit.detect_breaking_changes |
| pggit.generate_migration | pggit_v0.* functions | Manual via commits |
| ... | ... | ... |

---

## Phase 5: Gradual Deprecation (Weeks 3-4)

### 5.1 Add Deprecation Warnings
**Objective**: Warn users before removal

**Implementation**:
```sql
-- In pggit_v1.* functions:
CREATE OR REPLACE FUNCTION pggit_v1.get_object_version(...)
AS $$
BEGIN
    RAISE WARNING 'DEPRECATED: This function will be removed 2026-12-31. '
                  'Use pggit_audit.object_versions instead. '
                  'See docs/MIGRATION_V1_TO_V2.md';
    
    -- ... actual implementation ...
END;
$$;
```

### 5.2 Update Documentation
**Objective**: Make v1 status clear everywhere

**Changes**:
- Mark v1 functions as @deprecated in comments
- Add migration links to docs
- Update README
- Add notice to main schema file

### 5.3 Monitor Usage
**Objective**: Track when v1 is no longer used

**Script**:
```sql
-- Log v1 function calls
CREATE TABLE pggit_audit.v1_deprecation_log (
    call_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    function_name TEXT NOT NULL,
    called_at TIMESTAMP DEFAULT now(),
    caller TEXT DEFAULT current_user
);

-- Hook into v1 functions to log calls
```

---

## Phase 6: Full Migration & Cleanup (Post-Phase 5)

### 6.1 Option A: Keep v1 Compatibility (Conservative)
```sql
-- Keep pggit_v1 schema indefinitely
-- But mark as deprecated
-- Support limited to bug fixes, no new features
-- Users should migrate at their own pace
```

### 6.2 Option B: Require Migration (Aggressive)
```sql
-- Remove pggit_v1 schema after support ends
-- Force users to migrate
-- Timeline: 6-12 months notice
```

---

## Architecture After Migration

### New Structure
```
pggit_v0 (PRIMARY)
├── objects           ← Content-addressable storage (blobs, trees, commits)
├── refs              ← Branches and tags
├── commit_graph      ← Performance optimization
├── tree_entries      ← Fast tree comparisons
└── HEAD              ← Current branch tracking

pggit_audit (COMPLIANCE)
├── changes           ← Who changed what when
├── object_versions   ← Version history
├── compliance_log    ← Immutable audit trail
└── Views
    ├── object_history
    ├── recent_changes
    ├── breaking_changes_log
    └── compliance_report

pggit_v1 (DEPRECATED - OPTIONAL)
└── Compatibility functions (read-only, emit warnings)

pggit (ORIGINAL - UNCHANGED)
└── Keep for backward compatibility during migration
```

### Query Examples (After Migration)

**Old way (v1)**:
```sql
SELECT * FROM pggit.get_object_version('public.users', 5);
```

**New way (v2 + audit)**:
```sql
-- Get a specific version
SELECT definition FROM pggit_audit.object_versions
WHERE object_name = 'public.users' AND version_number = 5;

-- Get history
SELECT * FROM pggit_audit.object_history
WHERE object_name = 'public.users';

-- Get compliance report
SELECT * FROM pggit_audit.compliance_report
WHERE object_name = 'public.users'
AND committed_at BETWEEN '2025-01-01' AND '2025-12-31';

-- Three-way merge (now possible!)
SELECT pggit_v0.three_way_merge(
    base_tree_sha,
    branch1_tree_sha,
    branch2_tree_sha
);
```

---

## Implementation Roadmap

### Immediate (This Week)
- [ ] Complete Phase 2 Phases 1 + 2 together
- [ ] Design audit schema (4 hours)
- [ ] Build audit functions (6 hours)
- [ ] Create audit views (2 hours)

### Short-term (Next 2 Weeks)
- [ ] Create v1 compatibility shim (4 hours)
- [ ] Update install.sql (1 hour)
- [ ] Create migration tools (6 hours)
- [ ] Write migration guide (3 hours)

### Medium-term (Weeks 3-4)
- [ ] Add deprecation warnings (2 hours)
- [ ] Monitor usage (ongoing)
- [ ] Help users migrate (varies)

### Long-term (Post-Phase 5)
- [ ] Decision: Keep v1 or remove (async)
- [ ] Cleanup (varies)

---

## Success Criteria

### Phase 2 Complete
- [ ] pggit_audit schema created
- [ ] All audit functions implemented
- [ ] All audit views created
- [ ] Can extract full history from pggit_v0

### Phase 3 Complete
- [ ] pggit_v1 compat schema created
- [ ] Old functions work with deprecation warnings
- [ ] Existing code still runs
- [ ] No breaking changes for users

### Phase 4 Complete
- [ ] Migration guide published
- [ ] Function mapping document complete
- [ ] Migration scripts tested
- [ ] Users can self-serve migration

### Phase 5 Complete
- [ ] Deprecation warnings in place
- [ ] Usage is monitored
- [ ] Documentation updated
- [ ] Clear timeline communicated

---

## Risk Mitigation

### Risk 1: Breaking Changes
**Mitigation**:
- Keep v1 working via compat shim
- Long deprecation window (6+ months)
- Clear migration guide

### Risk 2: Audit Data Accuracy
**Mitigation**:
- Backfill from v1 history
- Verify consistency checks
- Manual spot-checking

### Risk 3: Performance Issues
**Mitigation**:
- Proper indices on audit tables
- Materialized views for heavy queries
- Archive old changes after 5 years

### Risk 4: User Confusion
**Mitigation**:
- Clear documentation
- Migration guide
- Deprecation warnings
- Support period

---

## Benefits After Migration

| Aspect | Before | After |
|--------|--------|-------|
| **Merging** | Manual, complex | Automatic, Git-like |
| **Branching** | Version-based | Commit-based |
| **Compliance** | In pggit tables | Derived audit layer |
| **Audit** | Single model | Optimized for audit |
| **Performance** | Mixed concerns | Specialized schemas |
| **Scalability** | Limited by DDL tracking | Scales to enterprise |
| **Team Collaboration** | Hard | Easy |

---

## Questions for Stakeholder Review

1. **Timeline**: Is 6-month deprecation window acceptable?
2. **v1 Retention**: Keep v1 compatibility long-term or remove after migration?
3. **Audit Level**: What compliance regulations must audit layer satisfy?
4. **Performance**: Any SLA requirements for audit queries?
5. **Backfill**: Should we auto-migrate existing pggit data to audit layer?

