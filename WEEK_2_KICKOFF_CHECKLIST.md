# Week 2 Kickoff Checklist

**Status**: ✅ READY TO BEGIN  
**Date**: December 21, 2025  
**Week 2 Duration**: 10-12 hours (Design & Schema)  

---

## ✅ Prerequisites Complete

- [x] All 4 spike analyses completed (Week 1)
- [x] GO decision made with high confidence
- [x] Technical unknowns resolved
- [x] Risk mitigation strategies designed
- [x] pggit_audit schema defined (ready to load)
- [x] Extraction functions designed (ready to implement)
- [x] Backfill algorithm designed (ready to implement)
- [x] Team capacity confirmed
- [x] Success criteria defined
- [x] Disaster recovery plan available

---

## 📋 Week 2 Tasks: Build Audit Layer Schema

### Task 1: Create pggit_audit Schema (2-3 hours)

**File**: `sql/pggit_audit_schema.sql` ✅ (READY)

**Status**: Schema definition complete and committed

**What's in the file**:
- DROP/CREATE pggit_audit schema
- 3 core tables:
  - `changes`: Track DDL changes (UUID change_id, commit_sha, object metadata)
  - `object_versions`: Point-in-time snapshots (version_number, definition, commit_sha)
  - `compliance_log`: Immutable audit trail (log_id, change_id, verification details)
- Immutability enforcement trigger on compliance_log
- 8 performance indices (optimized for common queries)
- 4 query views (recent_changes, unverified_changes, object_history, compliance_summary)
- 3 helper functions (verify_change, get_current_version, get_object_changes)
- Permissions and metadata

**Success Criteria**:
- [ ] Schema loads without errors
- [ ] 3 tables created with correct structure
- [ ] Immutability trigger functional (UPDATE/DELETE rejected on compliance_log)
- [ ] All 8 indices created
- [ ] All 4 views accessible
- [ ] All 3 helper functions registered
- [ ] Permissions applied

**How to Execute**:
```bash
# On test database:
psql -U postgres -d pggit_test -f sql/pggit_audit_schema.sql

# Verify:
psql -U postgres -d pggit_test -c "\dt pggit_audit.*"
psql -U postgres -d pggit_test -c "\dv pggit_audit.*"
psql -U postgres -d pggit_test -c "\df pggit_audit.*"
```

---

### Task 2: Verify Immutability Enforcement (1-2 hours)

**Test Procedure**:
```sql
-- Insert a test change
INSERT INTO pggit_audit.changes (
    commit_sha, object_schema, object_name, object_type, change_type
) VALUES (
    'test_sha_123', 'public', 'test_table', 'TABLE', 'CREATE'
);

-- Record in compliance log
INSERT INTO pggit_audit.compliance_log (
    change_id, verified_by, verification_status
)
SELECT change_id, 'test_user', 'PASSED'
FROM pggit_audit.changes
WHERE commit_sha = 'test_sha_123'
LIMIT 1;

-- TRY TO UPDATE - SHOULD FAIL ❌
UPDATE pggit_audit.compliance_log
SET verification_status = 'FAILED'
WHERE verification_status = 'PASSED';
-- Expected: ERROR: Compliance log is immutable

-- TRY TO DELETE - SHOULD FAIL ❌
DELETE FROM pggit_audit.compliance_log;
-- Expected: ERROR: Compliance log is immutable
```

**Success Criteria**:
- [ ] INSERT works
- [ ] UPDATE rejected with "immutable" error message
- [ ] DELETE rejected with "immutable" error message
- [ ] Compliance log cannot be modified after insertion

---

### Task 3: Test Query Views (1-2 hours)

**Test Procedure**:
```sql
-- Insert test data
INSERT INTO pggit_audit.changes (
    commit_sha, object_schema, object_name, object_type, change_type, verified
) VALUES 
    ('sha1', 'public', 'users', 'TABLE', 'CREATE', false),
    ('sha2', 'public', 'users', 'TABLE', 'ALTER', false),
    ('sha3', 'public', 'products', 'TABLE', 'CREATE', true);

-- Test: recent_changes view
SELECT * FROM pggit_audit.recent_changes;
-- Expected: 3 rows ordered by committed_at DESC

-- Test: unverified_changes view
SELECT * FROM pggit_audit.unverified_changes;
-- Expected: 2 rows (sha1, sha2)

-- Test: object_history view
INSERT INTO pggit_audit.object_versions (
    object_schema, object_name, version_number, definition, commit_sha, created_at
) VALUES
    ('public', 'users', 1, 'CREATE TABLE users...', 'sha1', CURRENT_TIMESTAMP);

SELECT * FROM pggit_audit.object_history;
-- Expected: 1 row with schema, name, version, definition, change metadata
```

**Success Criteria**:
- [ ] recent_changes returns all recent changes
- [ ] unverified_changes filters correctly
- [ ] object_history joins with changes metadata
- [ ] compliance_summary shows verification counts

---

### Task 4: Performance Index Verification (1-2 hours)

**Test Procedure**:
```sql
-- List all indices
SELECT indexname, tablename 
FROM pg_indexes 
WHERE schemaname = 'pggit_audit'
ORDER BY tablename;

-- Expected: 8 indices
-- - idx_changes_commit_sha (commit_sha lookup)
-- - idx_changes_object (schema, name query)
-- - idx_changes_time (time range queries)
-- - idx_changes_type (change_type filtering)
-- - idx_changes_verified (find unverified)
-- - idx_versions_object (object history)
-- - idx_versions_commit (commit lookup)
-- - idx_compliance_status (verification status)
-- - idx_compliance_time (timeline queries)

-- Verify index performance
ANALYZE pggit_audit.changes;
EXPLAIN ANALYZE SELECT * FROM pggit_audit.changes 
WHERE object_schema = 'public' AND object_name = 'users';
-- Expected: uses idx_changes_object index
```

**Success Criteria**:
- [ ] All 8 indices exist
- [ ] Partial index on verified = false works
- [ ] Indices are used in EXPLAIN ANALYZE
- [ ] Query plans are efficient

---

## 🚀 Week 2 Success Criteria (All Must Pass)

- [ ] pggit_audit schema loads without errors
- [ ] All 3 tables created: changes, object_versions, compliance_log
- [ ] Immutability enforcement working (updates/deletes rejected)
- [ ] All 8 performance indices created
- [ ] All 4 query views accessible
- [ ] All 3 helper functions registered
- [ ] Test inserts work correctly
- [ ] Immutability trigger tested successfully
- [ ] Views return correct filtered results
- [ ] Indices present and being used

---

## 📖 Week 2 Reference Documentation

**Read These First** (in order):
1. `docs/SPIKE_1_1_PGGIT_V2_ANALYSIS.md` - Understand pggit_v2 format (20 min)
2. `docs/SPIKE_1_2_DDL_EXTRACTION_ANALYSIS.md` - See extraction algorithm (20 min)
3. `docs/SPIKE_1_3_BACKFILL_ALGORITHM.md` - Understand backfill approach (30 min)
4. `docs/SPIKE_1_4_GO_NO_GO_DECISION.md` - Confirm GO rationale (15 min)
5. `SPIKE_ANALYSIS_COMPLETE_READY_FOR_WEEK_2.md` - Week-by-week plan (30 min)

**SQL Files** (ready to execute):
- `sql/pggit_audit_schema.sql` - Week 2 schema (execute on test database)
- `sql/pggit_audit_functions.sql` - Week 3 functions (implement after schema verified)

---

## 🎯 Week 2 Timeline

| Task | Estimate | Notes |
|------|----------|-------|
| Schema creation | 2-3h | Run SQL file, verify structure |
| Immutability testing | 1-2h | Test UPDATE/DELETE rejection |
| View testing | 1-2h | Verify filtering and joins |
| Index verification | 1-2h | Check usage in EXPLAIN ANALYZE |
| Documentation | 1h | Update progress notes |
| **TOTAL** | **10-12h** | Flexible within week |

---

## 🔍 Quality Checks

**Before marking Week 2 complete**, verify:

```bash
# 1. Schema exists and is accessible
psql -d pggit_test -c "SELECT * FROM information_schema.tables WHERE table_schema='pggit_audit';"

# 2. All tables present
psql -d pggit_test -c "SELECT tablename FROM pg_tables WHERE schemaname='pggit_audit';"

# 3. Trigger is attached
psql -d pggit_test -c "SELECT * FROM pg_trigger WHERE tgname='compliance_immutability';"

# 4. Indices exist
psql -d pggit_test -c "SELECT indexname FROM pg_indexes WHERE schemaname='pggit_audit';"

# 5. Views are accessible
psql -d pggit_test -c "SELECT viewname FROM pg_views WHERE schemaname='pggit_audit';"

# 6. Functions registered
psql -d pggit_test -c "SELECT proname FROM pg_proc WHERE pronamespace=(SELECT oid FROM pg_namespace WHERE nspname='pggit_audit');"
```

---

## ⚠️ Known Considerations

### Table Structure
- `changes.commit_sha`: Links to pggit_v2 commits (can be backfilled from v1)
- `object_versions.version_number`: Auto-incremented per schema.object_name
- `compliance_log`: Immutable (insert only, no updates/deletes)

### Performance
- All queries are O(1) or O(log n) due to indices
- Batch operations can be chunked for large histories

### Constraints
- UUID primary keys for deduplication safety
- Foreign key from compliance_log → changes ensures referential integrity
- UNIQUE constraint on (object_schema, object_name, version_number)

---

## 🎓 Learning Goals for Week 2

By end of week, engineer should understand:

1. **pggit_audit schema design**
   - Why 3 tables (changes, versions, compliance_log)
   - Trade-offs: Denormalization vs normalization
   - Why compliance_log is immutable

2. **DDL extraction from pggit_v2**
   - How commits contain trees, trees contain blobs
   - How to diff trees to find changes
   - How to extract DDL from blobs

3. **Audit layer capabilities**
   - Track who changed what when
   - Point-in-time schema reconstruction
   - Compliance verification workflow

4. **Performance considerations**
   - Index selection for common queries
   - How partial indices optimize unverified lookup
   - View overhead on large datasets

---

## ✅ Week 2 Completion Checklist

- [ ] All spike analysis documents read and understood
- [ ] sql/pggit_audit_schema.sql executed on test database
- [ ] All tables, views, indices, functions created successfully
- [ ] Immutability enforcement verified working
- [ ] Test inserts/queries confirm correct behavior
- [ ] Performance verified with EXPLAIN ANALYZE
- [ ] Documentation updated with results
- [ ] Ready to start Week 3 (extraction functions)

---

## 🚀 Next: Week 3 Preparation

Once Week 2 schema is verified, Week 3 will implement:
- `extract_changes_between_commits()` - Use diff_trees to find changes
- `backfill_from_v1_history()` - Convert v1 history to audit records
- Query views and helper functions (beyond what schema provides)
- Performance benchmarking (target < 100ms)

**File to create in Week 3**: `sql/pggit_audit_functions.sql` (already designed)

---

**Status**: READY FOR ENGINEER TO BEGIN  
**Timeline**: Week 2 (starting Monday)  
**Success Path**: Follow checklist above, execute schema, verify structure  
**Contact**: See SPIKE_ANALYSIS_COMPLETE_READY_FOR_WEEK_2.md for team details  
