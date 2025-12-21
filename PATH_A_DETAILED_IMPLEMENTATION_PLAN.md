# Path A: Full Migration - Detailed Implementation Plan

**Status**: Ready for team approval and execution
**Total Investment**: 370 hours (6-9 months including support)
**Breakdown**: 18h spike + 216-240h implementation + 120h+ support
**Timeline**: 1 week spike analysis → 8-10 weeks implementation → 6-12 months support

---

## Part 1: Spike Analysis (Week 1, 18-20 hours)

### Spike 1.1: Examine pggit_v2 Data Format (4-5 hours)

**Objective**: Understand what pggit_v2 actually stores and how to work with it

**Files to examine**:
```bash
sql/018_proper_git_three_way_merge.sql
```

**Tasks**:

1. **Read and document schema** (1.5 hours)
   - [ ] Read entire 018_proper_git_three_way_merge.sql file
   - [ ] Document pggit_v2.objects table structure
     - How is content stored? (TEXT, BYTEA, JSON?)
     - What metadata is available? (sha, type, size)
     - How do you find a specific object?
   - [ ] Document pggit_v2.commits table structure
     - How are commits linked to objects/trees?
     - What metadata (author, timestamp, message)?
     - How do you trace history?
   - [ ] Document pggit_v2.refs structure
     - How do branches/tags work?
     - How do you point to a tree?

2. **Create test scenario** (1.5 hours)
   ```sql
   -- Create a simple test table
   CREATE TABLE test_schema.users (
     id INTEGER PRIMARY KEY,
     name TEXT NOT NULL
   );

   -- Add via pggit_v2 (understand the flow)
   -- Make a commit
   -- Modify the table
   -- Make another commit

   -- Questions to answer:
   -- - What was stored in objects table?
   -- - How is the old vs new definition represented?
   -- - Can you reconstruct full DDL from object content?
   -- - What's in the content field exactly?
   ```

3. **Extract and examine actual data** (1-1.5 hours)
   ```sql
   SELECT
     sha,
     type,
     content,
     size
   FROM pggit_v2.objects
   LIMIT 5;

   -- Is content readable as text?
   -- Is it SQL, JSON, or binary?
   -- How big is it?
   -- Can you diff two versions?

   SELECT * FROM pggit_v2.commits;
   -- What metadata is available?
   -- How do you link commit to objects?

   SELECT * FROM pggit_v2.trees;
   -- How are blobs organized in trees?
   ```

**Deliverable**: Document (2-3 pages, with examples)
```
pggit_v2 Data Format Analysis:

Objects Table:
  - Stores complete schema object definitions
  - Content format: [actual format found]
  - Example row: [paste actual example]

Commits Table:
  - Links trees to metadata
  - Available metadata: [list]
  - Timestamp availability: [yes/no, format]

Key findings:
  - To extract DDL: [steps needed]
  - To diff commits: [algorithm needed]
  - To reconstruct schema: [dependencies]
```

**Success Criteria**:
- [ ] Can you extract a complete table definition from a commit?
- [ ] Can you identify what changed between two commits?
- [ ] Do you understand the content format completely?

---

### Spike 1.2: Prototype DDL Extraction (8-10 hours)

**Objective**: Prove that extracting DDL from pggit_v2 is feasible and estimate effort

**Scope**: One object type only - just TABLE definitions, no functions/triggers

**Phase 1: Understand the problem** (1-2 hours)

```sql
-- Start with a concrete example:
-- Take commit A and commit B from your test scenario
-- What tables exist in A? What in B?
-- What changed?

-- The challenge:
-- v1 tracks: "ALTER TABLE users ADD COLUMN email TEXT"
-- v2 should have: Full definition at each commit
--   Commit A tree: {users blob with version 1}
--   Commit B tree: {users blob with version 2}

-- How do we get from "blob content" to "full DDL"?
-- And detect "what changed"?
```

**Phase 2: Write extraction function skeleton** (3-4 hours)

```sql
CREATE OR REPLACE FUNCTION pggit_audit.extract_table_changes(
  p_old_commit_sha TEXT,
  p_new_commit_sha TEXT
)
RETURNS TABLE (
  table_name TEXT,
  change_type TEXT,  -- CREATE, ALTER, DROP
  old_definition TEXT,
  new_definition TEXT,
  column_changes TEXT  -- JSON or structured
) AS $$
DECLARE
  v_old_tree_sha TEXT;
  v_new_tree_sha TEXT;
  v_old_tables RECORD;
  v_new_tables RECORD;
BEGIN
  -- Step 1: Get tree SHAs from commits
  SELECT tree_sha INTO v_old_tree_sha
  FROM pggit_v2.commits
  WHERE sha = p_old_commit_sha;

  SELECT tree_sha INTO v_new_tree_sha
  FROM pggit_v2.commits
  WHERE sha = p_new_commit_sha;

  IF v_old_tree_sha IS NULL OR v_new_tree_sha IS NULL THEN
    RAISE EXCEPTION 'Commit not found';
  END IF;

  -- Step 2: Extract table definitions from old tree
  -- This is where we need to understand pggit_v2 structure
  -- How do we go from tree_sha to actual table definitions?

  -- Option A: If objects.content contains SQL text
  --   Parse it to find CREATE TABLE statements

  -- Option B: If objects are serialized schema
  --   Deserialize them to get column information

  -- Option C: If pggit_v2 has helper functions
  --   Use them to reconstruct definitions

  -- Step 3: Compare old vs new definitions
  -- Identify:
  --   - New tables (CREATE)
  --   - Deleted tables (DROP)
  --   - Modified tables (ALTER) with column diff

  -- Step 4: Return structured results

  RETURN QUERY
  SELECT 'users'::TEXT, 'ALTER'::TEXT,
         'CREATE TABLE users (id INT, name TEXT)'::TEXT,
         'CREATE TABLE users (id INT, name TEXT, email TEXT)'::TEXT,
         '{"added": ["email TEXT"]}'::TEXT;
END;
$$ LANGUAGE plpgsql;
```

**Phase 3: Test the function** (2-3 hours)

```sql
-- Test with your real test commits
SELECT * FROM pggit_audit.extract_table_changes(
  'commit_a_sha_here',
  'commit_b_sha_here'
);

-- Verify:
-- [ ] Detected table changes correctly?
-- [ ] Identified CREATE/ALTER/DROP accurately?
-- [ ] Column-level changes captured?
-- [ ] Old and new definitions are complete?

-- Manual verification:
-- Get the actual table definitions from your database at each point
-- Compare with what extraction found
-- Do they match?
```

**Phase 4: Estimate effort for all object types** (1-2 hours)

```
Based on single object type (TABLE), estimate effort for all types:

Type      | Effort (hours) | Complexity | Notes
----------|---|---|---
TABLE     | 8-10          | Medium     | Column tracking, constraints
FUNCTION  | 12-15         | High       | Parameters, body, dependencies
INDEX     | 4-6           | Low        | Depends on table definition
TRIGGER   | 6-8           | Medium     | Complex logic, dependencies
CONSTRAINT| 3-4           | Low        | References other objects
SEQUENCE  | 2-3           | Low        | Simple
PERMISSION| 8-10          | Medium     | Complex GRANT/REVOKE logic

Total extraction logic effort: 43-56 hours
Testing extraction: 10-15 hours
```

**Deliverable**: Working prototype + documentation
```
DDL Extraction Prototype Results:

Working code:
  - Function: pggit_audit.extract_table_changes()
  - Test case: [commits A and B]
  - Result: [what it found]

Actual performance:
  - Query time: [N] ms per commit pair
  - Accuracy: [%] of changes detected correctly
  - Missing: [list any undetected changes]

Edge cases found:
  - [problem 1]
  - [problem 2]
  - [problem 3]

Effort estimate for all types:
  - Total extraction logic: 43-56 hours
  - Adjustment from prototype: ±20%
  - Revised Phase 2 estimate: [update original]
```

**Success Criteria**:
- [ ] Prototype extracts changes from test commits?
- [ ] Manual verification confirms accuracy?
- [ ] Performance is acceptable (<100ms per pair)?
- [ ] Can estimate total effort for all object types?

---

### Spike 1.3: Backfill Algorithm Design (4-6 hours)

**Objective**: Design algorithm to convert v1 history to v2 commits and identify risks

**Phase 1: Map v1 history to v2 structure** (1.5 hours)

```sql
-- Sample v1 history (what we have):
SELECT * FROM pggit.history LIMIT 20;

-- Output example:
version_id | object_name      | object_type | change_type | change_sql
-----------|------------------|-------------|-------------|-------------------
1          | public.users     | TABLE       | CREATE      | CREATE TABLE users (id INT)
2          | public.orders    | TABLE       | CREATE      | CREATE TABLE orders (id INT, user_id INT)
3          | public.users     | TABLE       | ALTER       | ALTER TABLE users ADD COLUMN email TEXT
4          | public.users     | TABLE       | ALTER       | ALTER TABLE users ADD COLUMN created_at TIMESTAMP

-- Problem: How do we convert this to v2 commits?

-- v2 should have trees representing "complete state"
-- Commit 1: Tree with {users blob}
-- Commit 2: Tree with {users blob, orders blob}
-- Commit 3: Tree with {users blob (updated), orders blob}
-- Commit 4: Tree with {users blob (updated again), orders blob}

-- So the algorithm must:
-- 1. Reconstruct full definitions at each step
-- 2. Create blobs for each object
-- 3. Create tree pointing to all relevant blobs
-- 4. Create commit linking to tree + metadata
```

**Phase 2: Design backfill algorithm** (2-3 hours)

```
BACKFILL ALGORITHM:

Input: pggit.history (v1 incremental changes)
Output: pggit_v2 commits with complete snapshots

Algorithm:

1. Initialize empty schema state
2. FOR EACH version_id in v1 history (in order):
   a. Apply change_sql to current state
     - Execute CREATE/ALTER/DROP statements
     - Track which objects were modified

   b. Capture full current schema state
     - Get FULL definition of every object
     - (Not just the change, but the result)

   c. Create blobs for changed objects
     - For each changed object: INSERT into pggit_v2.objects
     - Content = full DDL definition
     - sha = computed hash
     - type = object_type (TABLE, FUNCTION, etc.)

   d. Create tree
     - Tree = collection of {object_name → blob_sha}
     - INSERT into pggit_v2.trees
     - tree_sha = computed hash

   e. Create commit
     - Link tree_sha to metadata
     - author = v1.author (from history)
     - committed_at = v1.created_at
     - message = v1.reason (or synthetic)
     - parent = previous_commit_sha (for history)
     - INSERT into pggit_v2.commits

   f. Update refs
     - main branch ref → latest commit_sha

   g. Verify step
     - Extract changes from previous commit
     - Compare with v1 record
     - If mismatch: LOG ERROR and STOP

3. RETURN {processed_count, error_count, first_error_details}

Pseudocode:

  v_current_schema := empty_schema;
  v_previous_commit := NULL;

  FOR v_rec IN (SELECT * FROM pggit.history ORDER BY version_id) LOOP
    -- 1. Apply change
    EXECUTE v_rec.change_sql;
    v_current_schema := capture_schema_state();

    -- 2. Create blobs for changed objects
    FOR v_obj IN (SELECT * FROM v_current_schema WHERE modified) LOOP
      INSERT INTO pggit_v2.objects (sha, type, content, size)
      VALUES (
        hash_sha1(v_obj.definition),
        v_obj.type,
        v_obj.definition,
        octet_length(v_obj.definition)
      );
    END LOOP;

    -- 3. Create tree
    v_tree_sha := create_tree_from_blobs(v_current_schema);

    -- 4. Create commit
    v_commit_sha := create_commit(
      tree_sha := v_tree_sha,
      author := v_rec.author,
      timestamp := v_rec.created_at,
      message := v_rec.reason,
      parent := v_previous_commit
    );

    -- 5. Verify
    IF NOT verify_commit_against_v1(v_commit_sha, v_rec) THEN
      RAISE EXCEPTION 'Backfill verification failed at version %', v_rec.version_id;
    END IF;

    v_previous_commit := v_commit_sha;

  END LOOP;
```

**Phase 3: Identify critical unknowns and risks** (1 hour)

**Unknown 1: Grouping changes into commits**
```
Problem: v1 tracks object versions independently
  v1.version_1: CREATE TABLE users
  v1.version_2: CREATE TABLE orders  ← Different table
  v1.version_3: ALTER TABLE users

Question: Are versions 1 and 2 in the same commit or separate commits?

If separate commits:
  ✓ Preserves exact history
  ✗ Creates many commits (one per version)

If grouped by time:
  ✓ Fewer, more logical commits
  ✗ Loses exact change order

Current decision: One v2 commit per v1 version (safest, most faithful)
```

**Unknown 2: Schema reconstruction complexity**
```
Problem: v1 only has change_sql, not full definitions

Example: v1 has
  Version 1: CREATE TABLE users (id INT, name TEXT)
  Version 2: ALTER TABLE users ADD COLUMN email TEXT
  Version 3: DROP COLUMN email
  Version 4: ALTER TABLE users ADD COLUMN created_at TIMESTAMP

To create v2 commits, we need full definitions:
  Commit 1: users = (id, name)
  Commit 2: users = (id, name, email)  ← Must reconstruct
  Commit 3: users = (id, name)  ← Must reconstruct
  Commit 4: users = (id, name, created_at)  ← Must reconstruct

Can we do this?
  - We have v1 history (sequence of changes)
  - We can apply it to get current state
  - But can we go BACKWARD to previous states?

Risk: If any intermediate state is corrupted/incomplete
      The entire backfill is wrong
```

**Unknown 3: Schema that no longer exists**
```
Problem: What if v1 history includes DROP TABLE, but table doesn't exist in current schema?

Example:
  v1 has: CREATE TABLE old_data (...)
  v1 has: DROP TABLE old_data
  Current schema: No old_data table

How do we reconstruct old_data's definition?
  - Only from v1 history (CREATE TABLE statement)

What if CREATE TABLE was incomplete/wrong?
  - Backfill will replicate the error

Solution: Manual review of all DROP statements before backfill
```

**Unknown 4: Non-DDL metadata**
```
v1 history tracks DDL statements: CREATE, ALTER, DROP

But what about:
  - Table ownership (ALTER TABLE ... OWNER TO)
  - Comments (COMMENT ON TABLE)
  - Permissions (GRANT/REVOKE)
  - Table options (TABLESPACE, WITH clauses)

v2 blobs store content as-is
But if v1.change_sql doesn't include these, they're lost

Solution: Include COMMENT and GRANT in pggit_audit.changes
          Mark as "metadata not tracked in v1"
```

**Unknown 5: Transaction atomicity**
```
v1 version might be "atomic unit" representing logical change
But change_sql might be one statement or multiple

Example:
  v1.version_5 = "ALTER TABLE users ADD COLUMN email TEXT;"
  But semantically this might depend on:
    - Concurrent changes to other tables
    - Application logic before/after

When we replay v1 history linearly:
  - Do we replay exactly as v1 recorded?
  - Or do we rebuild from scratch each time?

Decision: Replay exactly as recorded (most faithful)
Risk: If order matters in subtle ways, we'll duplicate the same bugs
```

**Deliverable**: Algorithm document + risk assessment
```
BACKFILL ALGORITHM DESIGN:

Algorithm: [pseudocode from above]

Key steps:
  1. Reconstruct schema state at each v1 version
  2. Create blobs for changed objects
  3. Create tree from blobs
  4. Create commit with metadata
  5. Verify against v1 history

Critical risks:
  1. Unknown: How to group changes into commits
     Impact: Could create wrong commit structure
     Mitigation: Use 1:1 v1_version to v2_commit mapping

  2. Unknown: Can we reconstruct intermediate states?
     Impact: Could have incomplete definitions
     Mitigation: Test with sample v1 history first

  3. Unknown: What about dropped objects?
     Impact: Could lose historical definitions
     Mitigation: Manual review of all DROP statements

  4. Unknown: Non-DDL metadata (ownership, permissions)
     Impact: Could lose important metadata
     Mitigation: Document as "not tracked in v1"

  5. Unknown: Transaction atomicity and dependencies
     Impact: Could duplicate subtle bugs
     Mitigation: Preserve exact ordering

Revised Phase 3 estimate: [update based on unknowns]
```

**Success Criteria**:
- [ ] Algorithm is documented clearly?
- [ ] Can explain how to reconstruct schema at each step?
- [ ] Identified 5+ critical unknowns?
- [ ] Mitigation strategies defined?

---

### Spike 1.4: Verify ROI and Make Decision (2 hours)

**Objective**: Determine if migration is worth 370 hours given findings

**Tasks**:

1. **Quantify current pain** (0.5 hour)
   ```
   Questions to answer:
   - How many times per month do users hit "two schemas confuse me"?
   - How much time is spent manually resolving merge conflicts?
   - How often do teams actually branch and merge schema?
   - What's the cost of current confusion in developer time?

   Example calculation:
   - 5 developers × 2 hours/month confusion = 10 hours/month
   - 10 hours/month × 12 months = 120 hours/year pain
   - If migration saves even 50% of this: 60 hours/year saved
   - Payback period: 370 hours / 60 hours/year = 6 years
   - Verdict: NOT WORTH IT (unless more pain identified)
   ```

2. **Quantify migration benefit** (0.5 hour)
   ```
   Questions to answer:
   - Will auto-merging actually reduce manual work?
     (Spike 1.2 showed DDL merge is still hard)
   - How many branches/merges per month?
   - What's the reduction in merge time with v2?

   Example calculation:
   - Currently: 2 merges/month × 4 hours = 8 hours/month manual
   - With v2: 2 merges/month × 2 hours = 4 hours/month (still hard)
   - Savings: 4 hours/month = 48 hours/year
   - Payback: 370 / 48 = 7.7 years
   ```

3. **Make go/no-go decision** (1 hour)

   **GO (Path A) if**:
   - [ ] Team does real branching/merging (5+ times per month)
   - [ ] Merge conflicts cost >2 hours per occurrence
   - [ ] Pain from two schemas is quantified >50 hours/year
   - [ ] Leadership approves 370-hour investment
   - [ ] Team can commit 6-9 months to this project
   - [ ] Long-term codebase value justifies investment

   **NO-GO (Path B/C) if**:
   - [ ] Team is mostly linear development
   - [ ] Merging happens rarely
   - [ ] Two schemas aren't actually confusing in practice
   - [ ] Migration cost (370h) > expected savings
   - [ ] Team can't commit 6-9 months
   - [ ] Other projects are higher priority

**Deliverable**: Decision document
```
SPIKE ANALYSIS RESULTS AND RECOMMENDATION:

Spike 1.1 (pggit_v2 format): [findings]
Spike 1.2 (DDL extraction): [feasibility + effort estimate]
Spike 1.3 (backfill algorithm): [algorithm + risks]
Spike 1.4 (ROI):
  Current pain: [hours/year]
  Projected savings: [hours/year]
  Payback period: [years]

RECOMMENDATION: [GO / NO-GO]

If GO:
  - Proceed to Phases 1-6 with confidence
  - Use spike findings to update estimates
  - Timeline: 8-10 weeks implementation + 6-12 months support

If NO-GO:
  - Recommend Path B (Hybrid) or Path C (Status Quo)
  - Revisit in 12 months
```

---

## Part 2: Implementation Phases (8-10 weeks, 216-240 hours)

### Phase 1: Build Audit Layer (20-25 hours)

**Duration**: 1 week
**Effort**: 20-25 hours

**Goal**: Create pggit_audit schema that captures compliance data from pggit_v2

**1.1: Design audit schema** (6-8 hours)

**Create schema file**: `sql/pggit_audit_schema.sql`

```sql
-- Schema: pggit_audit
-- Purpose: Compliance and audit layer derived from pggit_v2

CREATE SCHEMA IF NOT EXISTS pggit_audit;

-- Table: changes
-- Each row represents one DDL change detected from v2 commits
CREATE TABLE pggit_audit.changes (
  change_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Links to pggit_v2
  commit_sha TEXT NOT NULL UNIQUE,
  parent_commit_sha TEXT,

  -- Object identification
  object_schema TEXT NOT NULL,
  object_name TEXT NOT NULL,
  object_type TEXT NOT NULL,  -- TABLE, FUNCTION, INDEX, etc

  -- Change details
  change_type TEXT NOT NULL CHECK (change_type IN ('CREATE', 'ALTER', 'DROP', 'MODIFY')),
  old_definition TEXT,
  new_definition TEXT,
  change_diff JSONB,  -- Structured diff of what changed

  -- Metadata
  author TEXT,
  committed_at TIMESTAMP,
  commit_message TEXT,
  breaking_change BOOLEAN DEFAULT FALSE,

  -- Data integrity
  backfilled_from_v1 BOOLEAN DEFAULT FALSE,
  verified BOOLEAN DEFAULT FALSE,
  verification_notes TEXT,

  -- Audit trail
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT valid_change_type CHECK (change_type IN ('CREATE', 'ALTER', 'DROP')),
  CONSTRAINT definition_required CHECK (
    CASE change_type
      WHEN 'CREATE' THEN new_definition IS NOT NULL AND old_definition IS NULL
      WHEN 'ALTER' THEN old_definition IS NOT NULL AND new_definition IS NOT NULL
      WHEN 'DROP' THEN old_definition IS NOT NULL AND new_definition IS NULL
    END
  )
);

-- Table: object_versions
-- Point-in-time snapshots of each object
CREATE TABLE pggit_audit.object_versions (
  version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Object identification
  object_schema TEXT NOT NULL,
  object_name TEXT NOT NULL,
  object_type TEXT NOT NULL,
  version_number BIGINT NOT NULL,

  -- Definition
  definition TEXT NOT NULL,

  -- Links
  commit_sha TEXT NOT NULL,
  change_id UUID REFERENCES pggit_audit.changes(change_id) ON DELETE RESTRICT,

  -- Metadata
  created_at TIMESTAMP NOT NULL,
  author TEXT,

  UNIQUE(object_schema, object_name, object_type, version_number),
  CONSTRAINT version_number_positive CHECK (version_number > 0)
);

-- Table: compliance_log (IMMUTABLE)
-- Regulatory audit trail
CREATE TABLE pggit_audit.compliance_log (
  log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Links to change
  change_id UUID NOT NULL REFERENCES pggit_audit.changes(change_id) ON DELETE RESTRICT,

  -- Verification
  verified_at TIMESTAMP NOT NULL,
  verified_by TEXT NOT NULL,
  verification_status TEXT NOT NULL CHECK (verification_status IN ('pending', 'verified', 'rejected')),
  verification_notes TEXT,

  -- Immutability (enforced by trigger)
  locked BOOLEAN DEFAULT FALSE,

  -- Audit trail
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Prevent updates/deletes on compliance_log
CREATE OR REPLACE FUNCTION pggit_audit.prevent_compliance_modification()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    RAISE EXCEPTION 'Compliance log is immutable - cannot modify %', TG_OP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER compliance_immutability
  BEFORE UPDATE OR DELETE ON pggit_audit.compliance_log
  FOR EACH ROW EXECUTE FUNCTION pggit_audit.prevent_compliance_modification();

-- Create indices
CREATE INDEX idx_changes_object ON pggit_audit.changes(object_schema, object_name);
CREATE INDEX idx_changes_type ON pggit_audit.changes(change_type);
CREATE INDEX idx_changes_time ON pggit_audit.changes(committed_at);
CREATE INDEX idx_versions_object ON pggit_audit.object_versions(object_schema, object_name);
CREATE INDEX idx_versions_time ON pggit_audit.object_versions(created_at);
CREATE INDEX idx_compliance_time ON pggit_audit.compliance_log(verified_at);

COMMENT ON SCHEMA pggit_audit IS
  'Compliance and audit layer derived from pggit_v2 commits. ' ||
  'Single source of truth for DDL change history.';

COMMENT ON TABLE pggit_audit.changes IS
  'Each row represents one DDL change detected from pggit_v2 commits. ' ||
  'Backfilled from pggit v1 history initially, then updated with new commits.';

COMMENT ON TABLE pggit_audit.object_versions IS
  'Point-in-time snapshots of object definitions. Used for compliance reporting ' ||
  'and determining "what did the schema look like at version X?"';

COMMENT ON TABLE pggit_audit.compliance_log IS
  'Immutable regulatory audit trail. Can only INSERT, never UPDATE/DELETE. ' ||
  'Used for regulatory compliance and change verification.';
```

**Tasks**:
- [ ] Create schema file with all tables
- [ ] Add constraints and checks
- [ ] Create immutability enforcement
- [ ] Create indices for common queries
- [ ] Add comprehensive comments
- [ ] Test schema loads without errors
- [ ] Verify indices are created

**1.2: Create extraction functions** (8-10 hours)

Use findings from Spike 1.2 to implement actual extraction

**Create file**: `sql/pggit_audit_extraction.sql`

```sql
CREATE OR REPLACE FUNCTION pggit_audit.extract_changes_between_commits(
  p_old_commit_sha TEXT,
  p_new_commit_sha TEXT
)
RETURNS TABLE (
  object_schema TEXT,
  object_name TEXT,
  object_type TEXT,
  change_type TEXT,
  old_definition TEXT,
  new_definition TEXT,
  change_diff JSONB
) AS $$
-- Implementation based on Spike 1.2 findings
-- [Use pseudocode from spike, adapt to real pggit_v2 structure]
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit_audit.populate_changes_from_commit(
  p_commit_sha TEXT
)
RETURNS TABLE (
  inserted_count INT,
  error_count INT
) AS $$
-- Implementation based on Spike 1.2 findings
-- For a single commit, extract all changes and populate changes table
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit_audit.backfill_from_v1_history()
RETURNS TABLE (
  processed_records INT,
  errors_found INT,
  first_error_message TEXT
) AS $$
-- Implementation based on Spike 1.3 algorithm
-- Replay entire v1 history to populate audit tables
$$ LANGUAGE plpgsql;
```

**Tasks**:
- [ ] Implement extraction_between_commits function
  - [ ] Test with real commits
  - [ ] Verify accuracy (manual spot-check)
  - [ ] Benchmark performance
- [ ] Implement populate_changes_from_commit function
  - [ ] Test on single commit
  - [ ] Verify all object types detected
- [ ] Implement backfill_from_v1_history function
  - [ ] Test on sample v1 history
  - [ ] Verify reconstructed schema matches
  - [ ] Create verification report
- [ ] Add error handling and logging
- [ ] Test with sample data

**1.3: Create views for queries** (4-5 hours)

**Create file**: `sql/pggit_audit_views.sql`

```sql
CREATE VIEW pggit_audit.recent_changes AS
SELECT
  change_id,
  object_schema,
  object_name,
  object_type,
  change_type,
  author,
  committed_at,
  commit_message,
  breaking_change
FROM pggit_audit.changes
WHERE committed_at > CURRENT_TIMESTAMP - INTERVAL '30 days'
ORDER BY committed_at DESC;

CREATE VIEW pggit_audit.object_history AS
SELECT
  object_schema,
  object_name,
  object_type,
  version_number,
  committed_at,
  author,
  change_type
FROM pggit_audit.object_versions
ORDER BY object_schema, object_name, version_number;

CREATE VIEW pggit_audit.breaking_changes AS
SELECT
  change_id,
  object_schema,
  object_name,
  object_type,
  change_type,
  author,
  committed_at,
  commit_message,
  breaking_change
FROM pggit_audit.changes
WHERE breaking_change = TRUE
ORDER BY committed_at DESC;

CREATE VIEW pggit_audit.compliance_report AS
SELECT
  c.change_id,
  c.object_schema,
  c.object_name,
  c.change_type,
  c.author,
  c.committed_at,
  c.commit_message,
  cl.verified_at,
  cl.verified_by,
  cl.verification_status
FROM pggit_audit.changes c
LEFT JOIN pggit_audit.compliance_log cl ON c.change_id = cl.change_id
ORDER BY c.committed_at;
```

**Tasks**:
- [ ] Create all query views
- [ ] Test each view with sample data
- [ ] Document view purpose and usage
- [ ] Add view comments

**Testing** (3-4 hours):
- [ ] Load schema file - no errors
- [ ] Create test pggit_v2 commits
- [ ] Run extraction functions
- [ ] Query views - return expected data
- [ ] Verify with manual spot-checks
- [ ] Performance test (queries < 100ms)

---

### Phase 2: Create v1 Compatibility Layer (12-15 hours)

**Duration**: 1 week
**Effort**: 12-15 hours

**Goal**: Create read-only shim that makes old code continue working

**2.1: Design v1 compatibility schema** (2 hours)

**Create file**: `sql/pggit_v1_compat_schema.sql`

```sql
CREATE SCHEMA IF NOT EXISTS pggit_v1;

COMMENT ON SCHEMA pggit_v1 IS
  'DEPRECATED: Read-only compatibility layer for pggit v1. ' ||
  'This schema provides backwards-compatible functions that read from pggit_audit. ' ||
  'New code should use pggit_audit directly. ' ||
  'pggit_v1 will be removed in [DATE]. ' ||
  'See docs/MIGRATION.md for migration guide.';
```

**2.2: Implement compatibility functions** (8-10 hours)

**Create file**: `sql/pggit_v1_compat_functions.sql`

```sql
CREATE OR REPLACE FUNCTION pggit_v1.get_object_version(
  p_object_name TEXT,
  p_version INT
)
RETURNS TABLE (
  version_id INT,
  object_name TEXT,
  definition TEXT,
  created_at TIMESTAMP,
  author TEXT
) AS $$
BEGIN
  RAISE WARNING 'DEPRECATED: pggit_v1.get_object_version() is deprecated. ' ||
    'Use pggit_audit.object_versions instead. ' ||
    'See docs/MIGRATION.md for migration guide.';

  RETURN QUERY
  SELECT
    v.version_number::INT,
    v.object_name,
    v.definition,
    v.created_at,
    v.author
  FROM pggit_audit.object_versions v
  WHERE v.object_name = p_object_name
    AND v.version_number = p_version
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit_v1.list_changes(
  p_object_name TEXT DEFAULT NULL,
  p_limit INT DEFAULT 100
)
RETURNS TABLE (
  change_id UUID,
  object_name TEXT,
  change_type TEXT,
  author TEXT,
  committed_at TIMESTAMP,
  message TEXT
) AS $$
BEGIN
  RAISE WARNING 'DEPRECATED: pggit_v1.list_changes() is deprecated. ' ||
    'Use pggit_audit.recent_changes instead.';

  RETURN QUERY
  SELECT
    c.change_id,
    c.object_name,
    c.change_type,
    c.author,
    c.committed_at,
    c.commit_message
  FROM pggit_audit.changes c
  WHERE (p_object_name IS NULL OR c.object_name = p_object_name)
  ORDER BY c.committed_at DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit_v1.get_history(
  p_object_name TEXT
)
RETURNS TABLE (
  version_id INT,
  object_name TEXT,
  change_type TEXT,
  author TEXT,
  committed_at TIMESTAMP,
  definition TEXT
) AS $$
BEGIN
  RAISE WARNING 'DEPRECATED: pggit_v1.get_history() is deprecated. ' ||
    'Use pggit_audit.object_history instead.';

  RETURN QUERY
  SELECT
    v.version_number::INT,
    v.object_name,
    (SELECT change_type FROM pggit_audit.changes c
     WHERE c.change_id = v.change_id)::TEXT,
    v.author,
    v.created_at,
    v.definition
  FROM pggit_audit.object_versions v
  WHERE v.object_name = p_object_name
  ORDER BY v.version_number;
END;
$$ LANGUAGE plpgsql;

-- Document what broke
COMMENT ON FUNCTION pggit_v1.get_object_version(TEXT, INT) IS
  'DEPRECATED: Read from pggit_audit.object_versions instead. ' ||
  'WARNING: This function is READ-ONLY. Code that tries to UPDATE pggit.history ' ||
  'will fail because the old tables no longer support writes. ' ||
  'Update your code to use pggit_audit for reading, or ' ||
  'contact your DBA if you need data migration assistance.';
```

**Tasks**:
- [ ] Implement get_object_version (read-only wrapper)
- [ ] Implement list_changes (read-only wrapper)
- [ ] Implement get_history (read-only wrapper)
- [ ] Add deprecation warnings to each function
- [ ] Add comments about read-only limitation
- [ ] Test each function with v1 API calls

**2.3: Update install.sql** (2-3 hours)

- [ ] Add pggit_audit schema load
- [ ] Add pggit_v1 compat schema load
- [ ] Verify load order (audit before v1)
- [ ] Test full installation
- [ ] Update README with deprecation notice

**Testing** (2-3 hours):
- [ ] Load compat schema - no errors
- [ ] Call each v1 function - returns data
- [ ] Verify deprecation warnings appear
- [ ] Check that UPDATE attempts fail
- [ ] Test backwards compatibility (old code still works)

---

### Phase 3: Build Migration Tooling (30-40 hours)

**Duration**: 2 weeks
**Effort**: 30-40 hours

**Goal**: Create scripts to safely migrate v1 data to v2/audit

**3.1: Create analysis scripts** (8-10 hours)

**Create file**: `sql/migration_tools/001_analyze_v1_usage.sql`

```sql
-- Analyze what uses pggit.* and how
SELECT
  routine_schema,
  routine_name,
  routine_definition,
  routine_type
FROM information_schema.routines
WHERE routine_definition LIKE '%pggit.%'
  AND routine_schema != 'pggit'
  AND routine_schema != 'pggit_v2'
ORDER BY routine_schema, routine_name;

-- Count by usage pattern
WITH usage_patterns AS (
  SELECT
    CASE
      WHEN routine_definition LIKE '%pggit.get_object_version%' THEN 'get_object_version'
      WHEN routine_definition LIKE '%pggit.list_changes%' THEN 'list_changes'
      WHEN routine_definition LIKE '%pggit.get_history%' THEN 'get_history'
      ELSE 'other'
    END as pattern,
    COUNT(*) as count
  FROM information_schema.routines
  WHERE routine_definition LIKE '%pggit.%'
)
SELECT pattern, count FROM usage_patterns;
```

**Create file**: `sql/migration_tools/002_identify_backfill_scope.sql`

```sql
-- How much v1 history do we need to convert?
SELECT
  COUNT(*) as total_versions,
  COUNT(DISTINCT object_name) as unique_objects,
  COUNT(DISTINCT object_type) as object_types,
  MAX(version_id) as latest_version,
  MIN(created_at) as earliest_change,
  MAX(created_at) as latest_change
FROM pggit.history;

-- Breakdown by object type
SELECT
  object_type,
  COUNT(*) as count,
  COUNT(DISTINCT object_name) as unique_objects
FROM pggit.history
GROUP BY object_type
ORDER BY count DESC;

-- Growth over time
SELECT
  DATE_TRUNC('month', created_at) as month,
  COUNT(*) as changes
FROM pggit.history
GROUP BY DATE_TRUNC('month', created_at)
ORDER BY month;
```

**Create file**: `sql/migration_tools/003_detect_potential_issues.sql`

```sql
-- Potential problems that could break backfill

-- Issue 1: Objects with no CREATE statement
SELECT DISTINCT object_name
FROM pggit.history
WHERE change_type = 'ALTER'
  AND NOT EXISTS (
    SELECT 1 FROM pggit.history h2
    WHERE h2.object_name = pggit.history.object_name
      AND h2.change_type = 'CREATE'
      AND h2.version_id < pggit.history.version_id
  );

-- Issue 2: DROP without preceding CREATE
SELECT DISTINCT object_name
FROM pggit.history
WHERE change_type = 'DROP'
  AND NOT EXISTS (
    SELECT 1 FROM pggit.history h2
    WHERE h2.object_name = pggit.history.object_name
      AND h2.change_type = 'CREATE'
      AND h2.version_id < pggit.history.version_id
  );

-- Issue 3: Multiple CREATEs (shouldn't happen)
SELECT object_name, COUNT(*) as create_count
FROM pggit.history
WHERE change_type = 'CREATE'
GROUP BY object_name
HAVING COUNT(*) > 1;

-- Issue 4: Gaps in version_id
SELECT
  v1.version_id,
  v2.version_id,
  v2.version_id - v1.version_id as gap
FROM pggit.history v1
JOIN pggit.history v2 ON v2.version_id = v1.version_id + 1
WHERE v2.version_id - v1.version_id > 1;

-- Issue 5: NULL author or timestamp
SELECT COUNT(*) as null_author
FROM pggit.history
WHERE author IS NULL;

SELECT COUNT(*) as null_created_at
FROM pggit.history
WHERE created_at IS NULL;
```

**Tasks**:
- [ ] Create analysis scripts
- [ ] Run each script to understand data
- [ ] Document findings
- [ ] Identify potential issues
- [ ] Create remediation plan if issues found

**3.2: Implement backfill process** (12-15 hours)

**Create file**: `sql/migration_tools/004_backfill_audit_from_v1.sql`

This is the **most critical and dangerous** phase. Use algorithm from Spike 1.3.

```sql
-- BACKFILL MAIN PROCESS
-- This is a dry run - ROLLBACK at the end
-- Run in READONLY first, then with COMMIT

BEGIN;

-- Step 1: Create temporary working tables
CREATE TEMP TABLE backfill_progress (
  version_id INT,
  processed BOOLEAN DEFAULT FALSE,
  error_message TEXT,
  commit_sha TEXT
);

CREATE TEMP TABLE backfill_changes (
  object_schema TEXT,
  object_name TEXT,
  object_type TEXT,
  change_type TEXT,
  old_definition TEXT,
  new_definition TEXT
);

-- Step 2: FOR EACH version in v1 history (in order)
DO $$
DECLARE
  v_rec RECORD;
  v_total INT;
  v_processed INT := 0;
  v_errors INT := 0;
BEGIN
  SELECT COUNT(*) INTO v_total FROM pggit.history;

  FOR v_rec IN
    SELECT * FROM pggit.history
    ORDER BY version_id
  LOOP
    BEGIN
      -- Extract changes for this version
      -- (Use extraction function from Phase 1)

      INSERT INTO backfill_progress
      VALUES (v_rec.version_id, TRUE, NULL, NULL);

      v_processed := v_processed + 1;

      -- Every 100 versions, COMMIT (if not test run)
      IF v_processed % 100 = 0 THEN
        RAISE NOTICE 'Processed % of % versions', v_processed, v_total;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      INSERT INTO backfill_progress
      VALUES (v_rec.version_id, FALSE, SQLERRM, NULL);

      v_errors := v_errors + 1;

      -- Stop on first error (for safety)
      RAISE WARNING 'ERROR at version %: %', v_rec.version_id, SQLERRM;
      RAISE EXCEPTION 'Backfill stopped at first error';
    END;
  END LOOP;

  RAISE NOTICE 'Backfill complete: % processed, % errors', v_processed, v_errors;
END;
$$;

-- Step 3: Verify (spot checks)
-- Compare v1 records with backfilled pggit_audit records
SELECT COUNT(*) as v1_records FROM pggit.history;
SELECT COUNT(*) as audit_changes FROM pggit_audit.changes;
-- Should be approximately equal (1:1 for simple case)

-- Step 4: Detailed verification on sample
-- Take 10 random objects and compare definitions
SELECT
  h.object_name,
  h.version_id,
  h.change_sql as v1_sql,
  av.definition as v2_definition
FROM pggit.history h
LEFT JOIN pggit_audit.object_versions av ON
  av.object_name = h.object_name
  AND av.version_number = h.version_id
WHERE h.object_type = 'TABLE'
LIMIT 20;

-- Step 5: Commit or rollback
-- COMMIT;  -- Uncomment after verification
-- ROLLBACK;  -- Default: don't commit yet
```

**Tasks**:
- [ ] Write backfill process
- [ ] Test on dev/test database first (FULL RUN)
- [ ] Verify all records match
- [ ] Identify any discrepancies
- [ ] Fix backfill logic based on findings
- [ ] Re-test until clean
- [ ] Document verification checklist

**3.3: Create verification tools** (6-8 hours)

**Create file**: `sql/migration_tools/005_verify_migration.sql`

```sql
-- Post-backfill verification

-- Check 1: Record counts
SELECT
  'v1 history' as source,
  COUNT(*) as count
FROM pggit.history
UNION ALL
SELECT
  'pggit_audit changes' as source,
  COUNT(*) as count
FROM pggit_audit.changes
UNION ALL
SELECT
  'pggit_audit versions' as source,
  COUNT(*) as count
FROM pggit_audit.object_versions;

-- Check 2: Spot-check definitions
-- For each table, verify latest definition matches current schema
WITH latest_audit AS (
  SELECT
    object_name,
    definition,
    version_number,
    ROW_NUMBER() OVER (PARTITION BY object_name ORDER BY version_number DESC) as rn
  FROM pggit_audit.object_versions
  WHERE object_type = 'TABLE'
)
SELECT
  object_name,
  definition
FROM latest_audit
WHERE rn = 1;

-- Check 3: Author attribution
SELECT
  COUNT(*) as null_author
FROM pggit_audit.changes
WHERE author IS NULL;

-- Check 4: Timestamp coverage
SELECT
  MIN(committed_at) as earliest,
  MAX(committed_at) as latest,
  COUNT(*) as count
FROM pggit_audit.changes;

-- Check 5: Breaking changes detected?
SELECT
  COUNT(*) as breaking_changes
FROM pggit_audit.changes
WHERE breaking_change = TRUE;
```

**Create file**: `sql/migration_tools/006_generate_verification_report.sql`

```sql
-- Generate CSV report for manual verification
\copy (
  SELECT
    av.object_name,
    av.version_number,
    ac.change_type,
    ac.author,
    ac.committed_at,
    ac.breaking_change,
    ac.verified
  FROM pggit_audit.object_versions av
  LEFT JOIN pggit_audit.changes ac ON ac.change_id = av.change_id
  ORDER BY av.object_name, av.version_number
) TO '/tmp/migration_verification_report.csv' WITH (FORMAT CSV, HEADER);

-- Report statistics
SELECT
  COUNT(*) as total_changes,
  COUNT(*) FILTER (WHERE change_type = 'CREATE') as creates,
  COUNT(*) FILTER (WHERE change_type = 'ALTER') as alters,
  COUNT(*) FILTER (WHERE change_type = 'DROP') as drops,
  COUNT(*) FILTER (WHERE breaking_change = TRUE) as breaking,
  COUNT(*) FILTER (WHERE verified = FALSE) as unverified
FROM pggit_audit.changes;
```

**Tasks**:
- [ ] Create comprehensive verification queries
- [ ] Create verification checklist
- [ ] Create reporting scripts
- [ ] Manual review process defined

**3.4: Migration documentation** (4-6 hours)

**Create file**: `docs/MIGRATION_GUIDE.md`

```markdown
# Migration Guide: pggit v1 → v2 + Audit Layer

## Overview
This document guides users through migrating from pggit v1 to the new audit layer.

## What's Changing
- Old: pggit.* functions
- New: pggit_audit.* tables and views

## Migration Steps

### Step 1: Review deprecation timeline
[Dates and deadlines]

### Step 2: Update your code
[From/to examples]

### Step 3: Test with new API
[Test procedure]

### Step 4: Deploy changes

### Step 5: Support period
[How to get help]

## Function Mapping

| Old Function | New Table/View | Migration |
|---|---|---|
| pggit.get_object_version() | pggit_audit.object_versions | Query view directly |
| pggit.list_changes() | pggit_audit.recent_changes | Query view directly |
| pggit.get_history() | pggit_audit.object_history | Query view directly |

## Troubleshooting
[Common issues and solutions]

## Support
[Contact DBA if issues]
```

**Tasks**:
- [ ] Write migration guide
- [ ] Create function mapping document
- [ ] Create troubleshooting guide
- [ ] Create FAQ document

---

### Phase 4: Deprecation & Warnings (6-8 hours)

**Duration**: 1 week
**Effort**: 6-8 hours

**4.1: Add deprecation warnings** (2 hours)

- [ ] Modify all pggit_v1.* functions to emit RAISE WARNING
- [ ] Include date deadline in warnings
- [ ] Include link to migration guide
- [ ] Test warnings are visible

**4.2: Update documentation** (2 hours)

- [ ] Mark all pggit v1 functions as DEPRECATED in README
- [ ] Add migration links to documentation
- [ ] Update changelog
- [ ] Create DEPRECATION.md file

**4.3: Create monitoring** (2-4 hours)

```sql
-- Track usage of deprecated functions
CREATE TABLE pggit_audit.deprecation_usage_log (
  logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  function_name TEXT NOT NULL,
  caller_module TEXT,
  call_count INT DEFAULT 1,
  last_called TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Trigger on v1 function calls
-- (or periodic log analysis from slow_query_log)
```

---

### Phase 5: Gradual Deprecation Period (ONGOING: 6-12 months)

**Effort**: 120+ hours spread over 6-12 months (20h/month)

**5.1: User communication** (30-40 hours during Phase 5)

**Timeline**:
- Week 1: Email announcement
- Week 2: FAQ and support channel setup
- Month 1: First migration report
- Months 2-6: Monthly check-ins

**Activities**:
- [ ] Email: "pggit v1 is deprecated, here's timeline"
- [ ] Email: "Here's migration guide and how we can help"
- [ ] Email: "Milestone: X% teams have migrated"
- [ ] Support: Answer migration questions
- [ ] Training: Help teams with migration
- [ ] Documentation: Create team-specific examples

**5.2: Bug fixes and support** (60-80 hours during Phase 5)

**Activities**:
- [ ] Monitor migration issues in support channel
- [ ] Debug extraction/backfill problems teams encounter
- [ ] Fix bugs found during user migrations
- [ ] Handle data inconsistencies
- [ ] Support partial migrations (users running both)
- [ ] Timeline extension requests

**Realistic estimates**:
- 20 hours/month × 6 months = 120 hours
- If issues are severe: 30 hours/month × 6 months = 180 hours

**5.3: Cutover enforcement** (optional, after 6+ months)

```sql
-- Make v1 read-only (no writes)
CREATE POLICY v1_readonly ON pggit FOR UPDATE USING (FALSE);
CREATE POLICY v1_readonly ON pggit FOR DELETE USING (FALSE);
```

---

### Phase 6: Final Cleanup & Monitoring (10-12 hours)

**Duration**: 1 week (after all migrations complete)
**Effort**: 10-12 hours

**6.1: Archive old data** (2 hours)

```sql
-- After 5 years, can archive compliance_log to separate table/database
-- For now, create archive procedure for future use
```

**6.2: Final documentation** (4-6 hours)

- [ ] Document "Migration completed on [DATE]"
- [ ] Write "Lessons learned" document
- [ ] Update architecture documentation
- [ ] Create pggit_v2 user guide

**6.3: Post-migration monitoring** (4 hours)

- [ ] Monitor query performance on audit tables
- [ ] Check index effectiveness
- [ ] Verify compliance_log is immutable
- [ ] Spot-check data accuracy

---

## Part 3: Support Period (6-12 months, ongoing)

### Typical Monthly Activities

**Week 1: Communication**
- Send deprecation reminder email
- Post in communication channel
- Update status dashboard

**Week 2: Support**
- Help teams with migration planning
- Answer technical questions
- Provide code review on migration changes

**Week 3: Monitoring**
- Track migration progress
- Monitor for issues
- Fix bugs as discovered

**Week 4: Planning**
- Plan next steps
- Adjust timeline if needed
- Prepare next month's communication

### Support Checklist

- [ ] Monitor migration progress (track % of teams migrated)
- [ ] Respond to migration questions within 24 hours
- [ ] Fix bugs found during user migrations
- [ ] Maintain migration documentation
- [ ] Schedule training sessions
- [ ] Monthly progress email to stakeholders
- [ ] Keep deprecation warnings working
- [ ] Monitor slow_query_log for v1 usage

---

## Part 4: Timeline & Milestones

### Weeks 1 (Spike Analysis)
- [ ] **Week 1-1.5**: Spike 1.1 - pggit_v2 format analysis
- [ ] **Week 1-2**: Spike 1.2 - DDL extraction prototype
- [ ] **Week 2-2.5**: Spike 1.3 - Backfill algorithm design
- [ ] **Week 2-3**: Spike 1.4 - ROI verification
- [ ] **Decision point**: GO to Phases 1-6, or NO-GO to Path B/C

### Months 1 (Implementation Phases 1-2)
- [ ] **Week 3**: Phase 1.1 - Design audit schema
- [ ] **Week 4**: Phase 1.2-1.3 - Create extraction functions and views
- [ ] **Week 4-5**: Phase 2 - Create v1 compatibility layer
- [ ] **Testing**: Full schema testing on test database
- [ ] **Checkpoint**: Both schemas loading without errors

### Months 2 (Implementation Phases 3-4)
- [ ] **Week 5-7**: Phase 3.1 - Analysis and planning scripts
- [ ] **Week 7-8**: Phase 3.2 - Backfill process (test database)
- [ ] **Week 8-9**: Phase 3.3 - Verification and reporting
- [ ] **Week 9-10**: Phase 3.4 - Migration documentation
- [ ] **Week 10**: Phase 4 - Add deprecation warnings
- [ ] **Checkpoint**: Full backfill tested, verified, documented

### Months 2-9 (Phase 5: Deprecation Period)
- [ ] **Month 2**: Launch deprecation announcement
- [ ] **Months 2-4**: First 50% of teams migrate
- [ ] **Months 4-7**: Remaining 50% migrate
- [ ] **Months 7-9**: Support stragglers, fix edge cases
- [ ] **Checkpoint**: 95%+ of teams migrated

### Month 10 (Phase 6: Cleanup)
- [ ] **Week 1**: Final documentation and lessons learned
- [ ] **Week 1-2**: Post-migration monitoring
- [ ] **Week 2-3**: Archive old data (if needed)
- [ ] **Checkpoint**: Migration declared complete

---

## Success Criteria

### Phase 0 (Spike Analysis)
- [ ] All 4 spikes completed with findings documented
- [ ] ROI verified positive
- [ ] Team decision made (GO ahead with full migration)
- [ ] Budget approved by leadership

### Phase 1 (Audit Layer)
- [ ] pggit_audit schema loads without errors
- [ ] All extraction functions implemented and tested
- [ ] Views work and return expected data
- [ ] Performance acceptable (<100ms queries)

### Phase 2 (v1 Compat)
- [ ] All v1 functions work as read-only wrappers
- [ ] Deprecation warnings appear
- [ ] UPDATE/DELETE attempts fail gracefully
- [ ] Old code still runs (backwards compatible)

### Phase 3 (Migration Tooling)
- [ ] Backfill script runs successfully on test database
- [ ] Verification shows 100% accuracy
- [ ] All records match expected counts
- [ ] Spot-checks confirm data integrity

### Phase 4 (Deprecation)
- [ ] Warnings visible to all users
- [ ] Documentation updated
- [ ] Migration guide published
- [ ] Support channel established

### Phase 5 (Support Period)
- [ ] 95%+ of teams have migrated
- [ ] No critical issues in migration
- [ ] Deprecation timeline met
- [ ] All support questions answered

### Phase 6 (Cleanup)
- [ ] Migration declared complete
- [ ] Lessons learned documented
- [ ] Final monitoring shows healthy system
- [ ] Archive plan in place (if keeping v1 forever)

---

## Risk Mitigation Strategies

### Risk 1: Backfill Data Corruption
**Impact**: All audit data is wrong, unusable
**Probability**: Medium (if algorithm bugs)
**Mitigation**:
- [ ] Run on test database first (full dress rehearsal)
- [ ] Verify every step (analysis, backfill, check)
- [ ] Spot-check 20+ random objects manually
- [ ] Keep v1 data intact during backfill
- [ ] Backup v1 tables before cutover

### Risk 2: DDL Extraction Complexity
**Impact**: Can't extract some object types
**Probability**: Medium (unknowns in pggit_v2 format)
**Mitigation**:
- [ ] Spike 1.2 must prove extraction works
- [ ] Start with just TABLE type (simplest)
- [ ] Add other types incrementally
- [ ] Have fallback to manual extraction if needed

### Risk 3: User Confusion During Deprecation
**Impact**: Users ignore warnings, try to write to v1
**Probability**: High (normal user behavior)
**Mitigation**:
- [ ] Clear deprecation warnings (every 100 calls)
- [ ] Multiple communication channels
- [ ] Pair migration with training
- [ ] Make v1 read-only after 6 months
- [ ] Extended support period (12 months if needed)

### Risk 4: Performance Degradation
**Impact**: New audit queries are slow
**Probability**: Low (with proper indices)
**Mitigation**:
- [ ] Benchmark Phase 1 queries
- [ ] Create indices on common columns
- [ ] Consider materialized views for heavy queries
- [ ] Monitor performance during support period

### Risk 5: Concurrent Development During Backfill
**Impact**: Backfill is incomplete/inconsistent
**Probability**: High (normal operations)
**Mitigation**:
- [ ] Do backfill during low-activity window
- [ ] Backfill only v1 history (not new commits)
- [ ] Run incremental backfill in batches
- [ ] Mark changes as "backfilled_from_v1" for clarity

### Risk 6: v1 Support Forever
**Impact**: Engineering burden lasts years
**Probability**: High (some users never migrate)
**Mitigation**:
- [ ] Set hard deadline for v1 removal
- [ ] Make v1 read-only after 6 months
- [ ] No new features in v1 (bug fixes only)
- [ ] Budget ongoing support for v1 maint

---

## Decision Checkpoints

### After Spike Analysis (Week 2)
**Decision**: Is migration still worth 370 hours?
- **YES**: Proceed to Phase 1
- **NO**: Switch to Path B (Hybrid) or Path C (Status Quo)

### After Phase 2 (Week 5)
**Decision**: Is v1 compatibility shim working?
- **YES**: Proceed to Phase 3
- **NO**: Fix compat issues or reconsider migration

### After Phase 3 (Week 10)
**Decision**: Is backfill accurate and complete?
- **YES**: Schedule Phase 5 launch
- **NO**: Fix backfill issues or revert to Path B

### After Phase 4 (Week 11)
**Decision**: Ready to launch deprecation?
- **YES**: Send deprecation email, begin Phase 5
- **NO**: Delay launch, extend planning

### After Month 3 of Phase 5
**Decision**: Are teams migrating on schedule?
- **YES**: Continue as planned
- **NO**: Extend timeline or increase support
- **CRITICAL ISSUES**: May need to revert to v1 primary

---

## Budget and Resource Requirements

### Phase 0 (Spike Analysis)
- **Person-hours**: 18-20
- **Resource**: 1 senior engineer
- **Duration**: 1 week
- **Cost**: €3,000-4,000

### Phases 1-3 (Implementation)
- **Person-hours**: 62-80
- **Resource**: 1-2 engineers
- **Duration**: 8 weeks
- **Cost**: €12,000-16,000

### Phase 4 (Deprecation Launch)
- **Person-hours**: 6-8
- **Resource**: 1 engineer + 1 DBA
- **Duration**: 1 week
- **Cost**: €1,500-2,000

### Phase 5 (Support Period)
- **Person-hours**: 120+ spread over 6-12 months
- **Resource**: 0.5 engineer (20h/month)
- **Duration**: 6-12 months
- **Cost**: €12,000-24,000

### Phase 6 (Cleanup)
- **Person-hours**: 10-12
- **Resource**: 1 engineer
- **Duration**: 1 week
- **Cost**: €2,000-3,000

### Total Investment
- **Person-hours**: 216-240 (implementation) + 120+ (support)
- **Resources**: 1-2 engineers + DBA
- **Timeline**: 9-15 months
- **Cost**: €30,500-49,000 (depending on location/rates)

---

## Post-Migration Success Criteria

### Architecture Quality
- [ ] Single source of truth (pggit_v2 primary)
- [ ] Compliance trail is immutable (compliance_log)
- [ ] Schemas are well-documented
- [ ] Performance is acceptable

### User Satisfaction
- [ ] 95%+ of teams migrated
- [ ] No critical issues in production
- [ ] Migration was easier than feared
- [ ] Support burden is manageable

### Business Value
- [ ] Git-like workflows enabled
- [ ] Team collaboration improved
- [ ] Merge conflicts reduced (even if DDL still hard)
- [ ] ROI is positive within expected timeframe

### Technical Debt
- [ ] v1 no longer blocks new features
- [ ] Architecture is future-proof
- [ ] Code is maintainable
- [ ] Testing is comprehensive

---

## Glossary

**pggit (v1)**: Name-based DDL tracking schema (being deprecated)
**pggit_v2**: Git-like content-addressable storage (becoming primary)
**pggit_audit**: Compliance layer derived from v2 (new)
**pggit_v1**: Compatibility shim schema (temporary, deprecated)
**Backfill**: Converting v1 history to v2 commits
**Spike**: Research task to learn unknowns
**ROI**: Return on Investment

---

## Next Steps

1. **Immediately**: Review this plan with team
2. **This week**: Stakeholder meeting to approve Path A
3. **Next week**: Start spike analysis
4. **Week 3**: Make final GO/NO-GO decision based on spikes
5. **Week 4+**: Begin Phase 1 implementation (if GO)

---

**This plan is ready for implementation. Proceed to spike analysis to verify feasibility.**
