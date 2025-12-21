# Simplified Path A: Execution Roadmap

**Status**: APPROVED - Ready to Execute
**Timeline**: 2-3 months (7 weeks)
**Investment**: 110 hours (€15-20K)
**Approach**: Single-night cutover, no deprecation

---

## The Plan in One Page

```
Week 1:  Spike Analysis (18-20h)
         └─ Learn pggit_v0 format, DDL extraction, backfill algorithm
         └─ Decision: GO or NO-GO

Weeks 2-3: Build Audit Layer (20-25h)
           └─ pggit_audit schema, extraction functions, views

Weeks 4-5: Build Migration Tooling (25-30h)
           └─ Backfill script, analysis, verification

Week 6:   Staging Test Run (10-15h)
          └─ Full dress rehearsal on staging database
          └─ Verification: 100% accuracy
          └─ Test rollback procedure

Week 7:   Production Cutover (8-10h)
          └─ Saturday midnight, 6-hour window
          └─ Execute backfill, deploy new code, restart apps
          └─ Sunday morning: Success or rollback

Week 8-9: Monitoring & Docs (5-10h)
          └─ Performance monitoring
          └─ Documentation, lessons learned
```

---

## Week 1: Spike Analysis (18-20 hours)

**Goal**: Learn critical unknowns and verify feasibility

**Assign to**: 1 senior engineer
**Duration**: 5 days (Mon-Fri)
**Deliverable**: Spike findings document

### Spike 1.1: pggit_v0 Data Format (4-5 hours, Mon-Tue)

**Tasks**:
```sql
-- 1. Read schema file
cat sql/018_proper_git_three_way_merge.sql

-- 2. Understand structure:
--    - pggit_v0.objects (sha, type, content, size)
--    - pggit_v0.commits (tree_sha, author, timestamp, message)
--    - pggit_v0.trees (blob references)

-- 3. Create test scenario
CREATE TABLE test_schema.test_table (
  id INTEGER PRIMARY KEY,
  name TEXT
);

-- 4. Add to pggit_v0, make commits, examine what was stored
-- 5. Questions to answer:
--    - What's in content field? (SQL? Binary? JSON?)
--    - How big is it?
--    - Can you diff two versions?

-- 6. Extract and examine actual data
SELECT sha, type, content, size FROM pggit_v0.objects LIMIT 5;
```

**Document**:
- What pggit_v0 actually stores
- Content format
- How to get from commit to object definitions

### Spike 1.2: DDL Extraction (8-10 hours, Tue-Wed)

**Tasks**:
```sql
-- 1. Write extraction function skeleton
CREATE OR REPLACE FUNCTION extract_table_changes(
  p_old_commit_sha TEXT,
  p_new_commit_sha TEXT
) RETURNS TABLE (...) AS $$
BEGIN
  -- From Spike 1.1 findings:
  -- 1. Get tree SHAs from commits
  -- 2. Extract table definitions from blobs
  -- 3. Compare old vs new
  -- 4. Return CREATE/ALTER/DROP

  -- Implementation depends on Spike 1.1 results
END;
$$ LANGUAGE plpgsql;

-- 2. Test on real test commits
-- 3. Verify accuracy (manual spot-check)
-- 4. Estimate effort for all object types
```

**Document**:
- Extraction function works (Y/N)
- Performance acceptable? (Y/N)
- Effort estimate for all object types

### Spike 1.3: Backfill Algorithm (4-6 hours, Wed-Thu)

**Tasks**:
```sql
-- 1. Understand v1 to v2 conversion
--    v1: incremental changes (CREATE, ALTER, DROP)
--    v2: complete snapshots at each commit

-- 2. Design algorithm:
--    FOR EACH v1 version (in order):
--      - Apply change to schema
--      - Create blobs (one per object)
--      - Create tree (all objects)
--      - Create commit (with metadata)
--      - Verify against v1

-- 3. Identify risks:
--    - Objects without CREATE?
--    - Multiple CREATEs?
--    - Missing metadata (ownership, permissions)?

-- 4. Write pseudocode
```

**Document**:
- Algorithm flowchart
- 5+ risks identified
- Mitigation for each

### Spike 1.4: GO/NO-GO Decision (2 hours, Thu-Fri)

**Tasks**:
```
1. Can we extract DDL? (From Spike 1.2)
   YES → continue
   NO → switch to Path B or C

2. Can we backfill safely? (From Spike 1.3)
   YES → continue
   NO → switch to Path B or C

3. Do we understand pggit_v0? (From Spike 1.1)
   YES → continue
   NO → more research needed

4. Is ROI positive?
   YES → GO to implementation
   NO → reconsider
```

**Decision Meeting (Friday afternoon)**:
- Team reviews spike findings
- Decision: **GO** (proceed to Phase 1) or **NO-GO** (switch paths)
- If GO: Assign engineers for Weeks 2-7

---

## Weeks 2-3: Build Audit Layer (20-25 hours)

**Goal**: Create pggit_audit schema with extraction functions

**Assign to**: 1 engineer
**Duration**: 2 weeks
**Deliverable**: Working pggit_audit schema + extraction functions

### Week 2: Design & Schema (10-12 hours)

**Create file**: `sql/pggit_audit_schema.sql`

```sql
CREATE SCHEMA pggit_audit;

-- Table: changes
CREATE TABLE pggit_audit.changes (
  change_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  commit_sha TEXT NOT NULL UNIQUE,
  object_schema TEXT NOT NULL,
  object_name TEXT NOT NULL,
  object_type TEXT NOT NULL,  -- TABLE, FUNCTION, etc.
  change_type TEXT NOT NULL,  -- CREATE, ALTER, DROP
  old_definition TEXT,
  new_definition TEXT,
  author TEXT,
  committed_at TIMESTAMP,
  commit_message TEXT,
  backfilled_from_v1 BOOLEAN DEFAULT FALSE,
  verified BOOLEAN DEFAULT FALSE
);

-- Table: object_versions
CREATE TABLE pggit_audit.object_versions (
  version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  object_schema TEXT NOT NULL,
  object_name TEXT NOT NULL,
  version_number BIGINT NOT NULL,
  definition TEXT NOT NULL,
  commit_sha TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL,
  UNIQUE(object_schema, object_name, version_number)
);

-- Table: compliance_log (immutable)
CREATE TABLE pggit_audit.compliance_log (
  log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  change_id UUID NOT NULL REFERENCES pggit_audit.changes,
  verified_at TIMESTAMP NOT NULL,
  verified_by TEXT NOT NULL,
  verification_status TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Prevent compliance_log updates
CREATE OR REPLACE FUNCTION prevent_compliance_modification()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    RAISE EXCEPTION 'Compliance log is immutable';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER compliance_immutability
  BEFORE UPDATE OR DELETE ON pggit_audit.compliance_log
  FOR EACH ROW EXECUTE FUNCTION prevent_compliance_modification();

-- Create indices
CREATE INDEX idx_changes_object ON pggit_audit.changes(object_schema, object_name);
CREATE INDEX idx_changes_time ON pggit_audit.changes(committed_at);
CREATE INDEX idx_versions_object ON pggit_audit.object_versions(object_schema, object_name);
```

**Tasks**:
- [ ] Write schema file
- [ ] Load on test database - no errors
- [ ] Test immutability enforcement
- [ ] Verify indices are created

### Week 3: Extraction Functions (10-13 hours)

**Create file**: `sql/pggit_audit_functions.sql`

```sql
-- Use findings from Spike 1.2

CREATE OR REPLACE FUNCTION pggit_audit.extract_changes_between_commits(
  p_old_commit_sha TEXT,
  p_new_commit_sha TEXT
)
RETURNS TABLE (...) AS $$
-- Implementation from Spike 1.2
-- Extract all changes between two commits
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit_audit.backfill_from_v1_history()
RETURNS TABLE (processed INT, errors INT) AS $$
-- Main backfill algorithm from Spike 1.3
-- FOR EACH v1 version: reconstruct, create blobs/tree/commit
$$ LANGUAGE plpgsql;

-- Create views for queries
CREATE VIEW pggit_audit.object_history AS
SELECT * FROM pggit_audit.object_versions
ORDER BY object_schema, object_name, version_number;

CREATE VIEW pggit_audit.recent_changes AS
SELECT * FROM pggit_audit.changes
WHERE committed_at > CURRENT_TIMESTAMP - INTERVAL '30 days'
ORDER BY committed_at DESC;
```

**Tasks**:
- [ ] Implement extraction_between_commits()
- [ ] Implement backfill_from_v1_history()
- [ ] Create query views
- [ ] Test on sample data
- [ ] Benchmark performance (<100ms)

---

## Weeks 4-5: Build Migration Tooling (25-30 hours)

**Goal**: Create backfill script, analysis tools, verification

**Assign to**: 1 engineer + DBA
**Duration**: 2 weeks
**Deliverable**: Backfill script that works on test database

### Week 4: Analysis & Backfill (15-18 hours)

**Create file**: `sql/migration_tools/001_analyze_v1.sql`

```sql
-- What uses pggit.*?
SELECT routine_schema, routine_name
FROM information_schema.routines
WHERE routine_definition LIKE '%pggit.%'
  AND routine_schema NOT IN ('pggit', 'pggit_v0');

-- How much v1 history?
SELECT COUNT(*), COUNT(DISTINCT object_name)
FROM pggit.history;

-- Potential problems?
-- - Objects without CREATE?
-- - Multiple CREATEs?
-- - NULL authors/timestamps?
```

**Create file**: `sql/migration_tools/002_backfill_process.sql`

```sql
-- MAIN BACKFILL (from Spike 1.3 algorithm)

BEGIN;

DO $$
DECLARE
  v_rec RECORD;
  v_processed INT := 0;
  v_errors INT := 0;
BEGIN
  FOR v_rec IN (SELECT * FROM pggit.history ORDER BY version_id) LOOP
    BEGIN
      -- 1. Reconstruct schema at this version
      -- 2. Create blobs in pggit_v0.objects
      -- 3. Create tree in pggit_v0.trees
      -- 4. Create commit in pggit_v0.commits
      -- 5. Populate pggit_audit.changes
      -- 6. Verify against v1

      v_processed := v_processed + 1;

      IF v_processed % 100 = 0 THEN
        RAISE NOTICE 'Processed %', v_processed;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
      RAISE WARNING 'ERROR at version %: %', v_rec.version_id, SQLERRM;
      RAISE EXCEPTION 'Stop on first error';
    END;
  END LOOP;

  RAISE NOTICE 'Done: % processed, % errors', v_processed, v_errors;
END;
$$;

-- Verify
SELECT COUNT(*) as v1_records FROM pggit.history;
SELECT COUNT(*) as audit_changes FROM pggit_audit.changes;

-- ROLLBACK; -- Default: don't commit until verified
```

**Tasks**:
- [ ] Write analysis scripts
- [ ] Write backfill main loop
- [ ] Test on test database
- [ ] Fix any bugs
- [ ] Document verification checks

### Week 5: Verification & Cutover Plan (10-12 hours)

**Create file**: `sql/migration_tools/003_verify.sql`

```sql
-- Record count check
SELECT 'v1' as source, COUNT(*) FROM pggit.history
UNION ALL
SELECT 'v2 audit' as source, COUNT(*) FROM pggit_audit.changes;

-- Spot-check definitions (manual)
SELECT h.object_name, h.version_id, h.change_sql,
       av.definition
FROM pggit.history h
LEFT JOIN pggit_audit.object_versions av ON
  av.object_name = h.object_name
  AND av.version_number = h.version_id
LIMIT 20;

-- Author attribution
SELECT COUNT(*) FROM pggit_audit.changes WHERE author IS NULL;

-- Timestamp coverage
SELECT MIN(committed_at), MAX(committed_at), COUNT(*)
FROM pggit_audit.changes;
```

**Create file**: `docs/CUTOVER_PROCEDURE.md`

```markdown
# Production Cutover Procedure

## Saturday Midnight Cutover

**Maintenance window**: 6 hours (Sat 24:00 - Sun 06:00)

### Pre-cutover (Week 6)
1. Test backfill on staging - 100% accurate
2. Test new code path on staging
3. Backup pggit schema on production
4. Communicate maintenance window to users
5. Prepare rollback procedure

### Cutover Steps (Saturday Midnight)

1. **Stop applications** (23:30)
   - Kill all processes using pggit
   - Wait 30 seconds for graceful shutdown

2. **Backup v1** (23:45)
   ```bash
   pg_dump -Fc pggit_schema > /backup/pggit_v1_backup.sql
   ```

3. **Run backfill** (00:00, expect 30-45 minutes)
   ```sql
   -- In production database
   \i sql/migration_tools/002_backfill_process.sql
   -- This will populate pggit_audit with all v1 history
   ```

4. **Verify** (00:45)
   ```sql
   \i sql/migration_tools/003_verify.sql
   -- Check: record counts match, spot-checks accurate
   ```

5. **Deploy new code** (01:00)
   - Stop old applications
   - Update code: change pggit.* to pggit_audit.*
   - Restart applications

6. **Monitor** (01:30 - 06:00)
   - Watch logs for errors
   - Monitor performance
   - Spot-check functionality
   - If issues: ROLLBACK procedure

### Rollback Procedure (If Something Goes Wrong)

```bash
# 1. Stop applications
# 2. Restore pggit schema
psql < /backup/pggit_v1_backup.sql

# 3. Revert code to old version (uses pggit.*)
# 4. Restart applications

# Now back to using pggit v1
# Saturday morning: assess what went wrong
```

### Sunday Morning

**If cutover succeeded** (06:00):
- ✓ Announce completion
- ✓ Monitor for issues (next 24 hours)
- ✓ Disable old code paths

**If rollback happened**:
- Analyze what failed
- Fix issue
- Schedule new cutover attempt for next weekend
```

**Tasks**:
- [ ] Write verification queries
- [ ] Test on staging (100% accuracy)
- [ ] Document cutover procedure
- [ ] Document rollback procedure
- [ ] Create pre-cutover checklist

---

## Week 6: Staging Test Run (10-15 hours)

**Goal**: Full dress rehearsal - verify everything works before production

**Assign to**: 1 engineer + DBA
**Duration**: 1 week
**Deliverable**: Confidence that production cutover will succeed

### Monday: Staging Setup

```bash
# 1. Restore production backup to staging
pg_restore staging_database < /backup/production.sql

# 2. Verify staging has same data as production
SELECT COUNT(*) FROM pggit.history;  -- Match production

# 3. Backup staging pggit schema
pg_dump -Fc staging_pggit_schema > /backup/staging_pggit_backup.sql
```

### Tuesday-Wednesday: Full Test Run

```sql
-- Run backfill on staging
\i sql/migration_tools/002_backfill_process.sql

-- Verify accuracy
\i sql/migration_tools/003_verify.sql

-- Manual spot-checks
-- For 20 random objects:
--   - Get v1 definition
--   - Get v2 definition
--   - Compare: do they match?

-- Questions to answer:
-- [ ] Backfill completed without errors?
-- [ ] Record counts match?
-- [ ] Spot-checks accurate (>95%)?
-- [ ] Timestamps preserved?
-- [ ] Authors attributed correctly?
```

### Thursday: New Code Testing

```sql
-- Test queries against pggit_audit instead of pggit

-- Old code:
SELECT * FROM pggit.get_object_version('users', 5);

-- New code:
SELECT definition FROM pggit_audit.object_versions
WHERE object_name = 'users' AND version_number = 5;

-- Both should return same definition

-- Test all migration queries:
-- [ ] Query 1: Works? Same result?
-- [ ] Query 2: Works? Same result?
-- ... repeat for all queries

-- Performance test:
-- [ ] Queries complete in <100ms?
-- [ ] No slow queries?
-- [ ] Indices being used?
```

### Friday: Rollback Test

```bash
# 1. Simulate failure scenario
# 2. Run rollback procedure
pg_restore staging_database < /backup/staging_pggit_backup.sql

# 3. Verify pggit.* functions work again
SELECT * FROM pggit.get_object_version('users', 1);

# 4. Confirm: "If this fails on production, we can recover"
```

### Friday Evening: GO/NO-GO for Production

**Decision checklist**:
- [ ] Backfill works 100% on staging
- [ ] New code works on staging
- [ ] Rollback procedure works
- [ ] Performance acceptable
- [ ] All spot-checks passed

**GO** → Proceed to production cutover (Week 7)
**NO-GO** → Fix issues, try again next week

---

## Week 7: Production Cutover (8-10 hours)

**Goal**: Execute backfill on production, deploy new code, go live

**Assign to**: DBA + 2 engineers on call
**Duration**: 1 night + 1 morning

### Saturday Evening (23:00-23:30)

- [ ] Send maintenance notification to all users
- [ ] Notify: "System down 00:00-06:00 Saturday"
- [ ] Prepare: Backfill script, new code, rollback backup
- [ ] Team on call ready

### Saturday Midnight (00:00)

```
00:00 - CUTOVER BEGINS
00:05 - Applications stopped
00:15 - v1 pggit schema backed up
00:30 - Backfill process started
        (Monitor progress every 5 minutes)
01:00 - Backfill should be complete
01:15 - Verification running
01:45 - If verification OK: deploy new code
02:00 - New code deployed, applications restarted
02:15 - Smoke tests: can access pggit_audit data?
03:00 - Spot-check: 20 random objects
04:00 - Full hour of monitoring (no errors?)
06:00 - CUTOVER COMPLETE
```

### Decision Points During Cutover

**At 01:15 (after verification)**:
- ✅ Accuracy >95% → Continue to deployment
- ❌ Accuracy <95% → Rollback + abort

**At 02:15 (after new code restart)**:
- ✅ Applications running, pggit_audit queries work → Continue
- ❌ Applications crashing → Rollback to old code + pggit v1

**At 04:00 (after 1 hour operation)**:
- ✅ No critical errors → Declare success
- ❌ Critical errors → Rollback + investigate

### Sunday Morning (06:00)

**If successful**:
```
✓ System is live on pggit_v0 + pggit_audit
✓ pggit.* no longer available
✓ All code using new API
✓ Announce to users: "Maintenance complete, system restored"
```

**If rollback needed**:
```
✓ Restored to pggit v1
✓ Old code still working
✓ Analyze what failed
✓ Schedule new attempt for next weekend
```

---

## Weeks 8-9: Monitoring & Documentation (5-10 hours)

**Goal**: Ensure system is healthy, document lessons learned

**Assign to**: 1 engineer (part-time)
**Duration**: 2 weeks
**Deliverable**: Performance monitoring, docs, lessons learned

### Week 8: Monitoring

- [ ] Monitor query performance (pggit_audit queries)
- [ ] Check error logs for issues
- [ ] Verify compliance_log is immutable
- [ ] Spot-check data accuracy (10+ random objects)
- [ ] User feedback collection

### Week 9: Documentation

- [ ] Write "Migration Completed" announcement
- [ ] Create "Lessons Learned" document
- [ ] Update architecture documentation
- [ ] Create pggit_v0/pggit_audit user guide
- [ ] Archive spike analysis and verification reports

---

## Pre-Cutover Checklist

**Before Week 1 Starts**:
- [ ] Spike analysis engineer identified
- [ ] Test database available
- [ ] Staging database available
- [ ] Production backup procedure verified
- [ ] Team communication plan in place

**Before Week 2 Starts**:
- [ ] Spike analysis completed
- [ ] GO decision made
- [ ] Implementation engineers assigned
- [ ] Database backups verified

**Before Week 6 Starts**:
- [ ] All migration tooling complete
- [ ] All code paths identified (pggit.*)
- [ ] New code written and tested
- [ ] Staging database ready for test

**Before Week 7 Starts**:
- [ ] Staging test run completed
- [ ] GO/NO-GO decision made
- [ ] Maintenance window scheduled
- [ ] Users notified
- [ ] Rollback procedure tested

---

## Success Criteria

### After Week 1
- ✅ Spike analysis complete
- ✅ GO decision made
- ✅ Understanding of pggit_v0 format
- ✅ Confidence in DDL extraction
- ✅ Backfill algorithm designed

### After Week 3
- ✅ pggit_audit schema working
- ✅ Extraction functions tested
- ✅ Views return expected data
- ✅ Performance acceptable

### After Week 5
- ✅ Backfill script works on test database
- ✅ Verification confirms 100% accuracy
- ✅ Cutover procedure documented

### After Week 6
- ✅ Staging test run 100% successful
- ✅ Rollback procedure works
- ✅ New code tested and ready
- ✅ GO decision for production

### After Week 7
- ✅ Production cutover successful
- ✅ All users on new API
- ✅ No critical errors
- ✅ pggit_v0 is now primary

### After Week 9
- ✅ Performance monitoring shows healthy system
- ✅ Lessons learned documented
- ✅ Architecture docs updated
- ✅ Migration officially complete

---

## Risk Mitigation

| Risk | Probability | Mitigation |
|------|-------------|-----------|
| Backfill is incomplete | Medium | Week 6 staging test - 100% verification |
| New code has bugs | Medium | Week 6 testing on staging |
| Cutover takes too long | Low | Staged cutover (backfill, then deploy) |
| Rollback doesn't work | Low | Test rollback on staging Week 6 |
| Performance degrades | Low | Indices created, queries benchmarked |
| Data corruption | Low | Spike 1.2 proves extraction works |

---

## Team & Resources

**Needed**:
- 1 senior engineer (Weeks 1-7)
- 1 DBA (Weeks 4-7)
- 1 engineer on call (Week 7, Saturday night)

**Tools**:
- PostgreSQL with pggit v1 and pggit_v0
- Test and staging databases (identical to production)
- Git for code changes
- Monitoring tools (for Saturday night)

**Budget**:
- Engineer time: 110 hours @ €150/hour = €16,500
- Infrastructure (test/staging databases): ~€500
- Contingency: 10% = €1,700
- **Total**: ~€18,700

---

## Go/No-Go Decision Points

### After Week 1 (Spike Analysis)
**Decision**: Can we feasibly extract DDL and backfill?
- **GO** → Proceed to Weeks 2-9
- **NO-GO** → Switch to Path B or C

### After Week 5 (Tooling Complete)
**Decision**: Does backfill script work on test database?
- **GO** → Proceed to Week 6 (staging test)
- **NO-GO** → Debug and retry, or switch paths

### After Week 6 (Staging Test)
**Decision**: Did staging test succeed 100%?
- **GO** → Proceed to Week 7 (production cutover)
- **NO-GO** → Fix issues and retry staging, or switch paths

### Week 7 - Saturday Midnight (Cutover)
**Decision**: Does verification after backfill pass?
- **GO** → Deploy new code
- **ROLLBACK** → Restore backup, try again next weekend

---

## Communication Plan

**Week 1**: Team knows spike analysis is happening
**Week 2**: GO decision announced, implementation begins
**Week 5**: All users notified: "Maintenance scheduled Saturday 00:00-06:00"
**Week 6**: Reminder: "System down Saturday midnight"
**Week 7 - Saturday 23:00**: "Maintenance starting now"
**Week 7 - Sunday 06:00**: "Maintenance complete, system restored"
**Week 8+**: Regular monitoring, no further communication

---

## What Happens After Cutover

**What you have**:
- ✅ pggit_audit: New compliance layer (immutable)
- ✅ pggit_v0: Primary version control system
- ❌ pggit (v1): No longer available (deleted or archived)
- ❌ pggit_v1 (compat layer): Not needed (no deprecation)

**What users do**:
- Replace old code: `pggit.get_object_version()` → `pggit_audit.object_versions`
- Replace old code: `pggit.list_changes()` → `pggit_audit.changes`
- Use new Git-like API: `pggit_v0.*` for branching/merging

**What you maintain**:
- pggit_v0 as primary system
- pggit_audit for compliance queries
- No v1 support needed

---

## Timeline at a Glance

```
Week 1: Spike Analysis                    18-20h  🔍 Learn
Week 2-3: Build Audit Layer              20-25h  🏗️ Build
Week 4-5: Migration Tooling              25-30h  🔧 Tools
Week 6: Staging Test Run                 10-15h  ✅ Verify
Week 7: Production Cutover                8-10h  🚀 Execute
Week 8-9: Monitoring & Docs               5-10h  📚 Document

Total: 110 hours over 9 weeks (2-3 months)
```

---

## Next Immediate Steps

1. **TODAY**: Identify spike analysis engineer
2. **TOMORROW**: Schedule spike kickoff meeting
3. **NEXT MONDAY**: Spike analysis starts
4. **FRIDAY (Week 1)**: Spike analysis ends, GO/NO-GO decision
5. **NEXT MONDAY (Week 2)**: If GO, start building audit layer

---

**You have a clear, executable plan. Ready to start Week 1?**
