# Complete Implementation Plan for pggit_v0 - Full Git Object Model & Three-Way Merge

**Date**: 2025-12-21
**Scope**: Full implementation of git-like object model with three-way merge algorithm
**Duration**: 8-10 hours
**Complexity**: HIGH
**Priority**: P1 (Critical blocker for 3-way merge feature tests)

---

## Executive Summary

The `pggit_v0` schema will implement a **complete git-like object model** with:
1. **Content-addressable storage** - Objects identified by SHA-1 hashes
2. **Immutable objects** - Blobs, trees, commits
3. **Git-compatible merge algorithm** - Three-way merge with conflict detection
4. **Branch tracking** - References and history

This enables the test suite to verify production-grade merge capabilities used in real git-based version control.

---

## Part 1: Architecture & Data Model

### 1.1 Core Objects

#### Blob (File Content)
```
Blob represents a file's contents at a point in time

Structure:
  sha1:      TEXT PRIMARY KEY (40 chars, hex-encoded SHA-1 of content)
  content:   TEXT (raw file content)
  size:      BIGINT (file size in bytes)
  created_at: TIMESTAMP (when blob was created)

Example:
  sha1='356a192b7913b04c54574d18c28d46e6395428ab'
  content='Hello, World!'
  size=13
```

#### Tree (Directory Listing)
```
Tree represents a directory snapshot - maps filenames to blob/tree SHAs

Structure:
  sha1:      TEXT PRIMARY KEY
  entries:   JSONB (array of {name, mode, type, sha})
  created_at: TIMESTAMP

Example:
  sha1='...'
  entries='[
    {"name": "file.txt", "mode": "100644", "type": "blob", "sha": "356a19..."},
    {"name": "subdir", "mode": "040000", "type": "tree", "sha": "abc123..."}
  ]'

Entry Structure:
  - name:  Filename (string)
  - mode:  Unix permissions (100644=file, 100755=executable, 040000=dir)
  - type:  "blob" or "tree"
  - sha:   SHA-1 of blob or tree
```

#### Commit (Version Snapshot)
```
Commit represents a single version/snapshot - points to tree + parent(s)

Structure:
  sha1:       TEXT PRIMARY KEY
  tree:       TEXT REFERENCES Tree(sha1)
  parents:    TEXT[] (array of parent commit SHAs)
  author:     TEXT (author name/email)
  message:    TEXT (commit message)
  timestamp:  TIMESTAMP (commit date)
  created_at: TIMESTAMP (when record was created)

Example:
  sha1='...'
  tree='a1b2c3...' (points to root tree)
  parents='{parent1, parent2}' (can have 0, 1, or 2+ parents)
  author='John Doe <john@example.com>'
  message='Initial commit'
  timestamp='2025-12-21 12:00:00'
```

### 1.2 Merge-Related Objects

#### Merge Context
```
Tracks state during three-way merge operation

Structure:
  merge_id:       UUID PRIMARY KEY
  base_sha:       TEXT REFERENCES Commit
  ours_sha:       TEXT REFERENCES Commit
  theirs_sha:     TEXT REFERENCES Commit
  status:         TEXT ('in_progress', 'success', 'conflict', 'error')
  conflict_count: INTEGER
  created_at:     TIMESTAMP
```

#### Conflicts
```
Records individual file-level conflicts found during merge

Structure:
  conflict_id:    UUID PRIMARY KEY
  merge_id:       UUID REFERENCES MergeContext
  file_path:      TEXT (path to conflicting file)
  base_content:   TEXT (their version at base)
  ours_content:   TEXT (our version)
  theirs_content: TEXT (their version)
  resolved:       BOOLEAN
  resolution:     TEXT (how it was resolved)
  created_at:     TIMESTAMP
```

#### Merge Result
```
Complete result of a three-way merge

Structure:
  merge_id:       UUID PRIMARY KEY REFERENCES MergeContext
  result_tree:    TEXT REFERENCES Tree (or NULL if conflicts)
  merged_commit:  TEXT REFERENCES Commit (only if auto-merged)
  conflict_count: INTEGER
  success:        BOOLEAN
  details:        JSONB (merge metadata)
```

### 1.3 Performance Tables

#### Statistics & Metadata
```
pggit_v0.statistics:
  - total_objects: INTEGER
  - total_commits: INTEGER
  - total_blobs: INTEGER
  - total_trees: INTEGER
  - total_merges: INTEGER
  - last_updated: TIMESTAMP

pggit_v0.object_stats:
  - object_type: TEXT ('blob', 'tree', 'commit')
  - count: INTEGER
  - total_size: BIGINT
  - last_updated: TIMESTAMP
```

---

## Part 2: Core Functions

### 2.1 Blob Functions

#### create_blob(content TEXT) RETURNS TEXT
```sql
Purpose: Create a blob (file content) and return its SHA-1

Algorithm:
  1. Compute SHA-1 hash of content
  2. Check if blob with this SHA already exists
  3. If not, insert into pggit_v0.blobs table
  4. Return the SHA-1 hex string

Implementation:
  CREATE FUNCTION pggit_v0.create_blob(p_content TEXT)
  RETURNS TEXT AS $$
  DECLARE
    v_sha TEXT;
  BEGIN
    -- Compute SHA-1 hash of content
    v_sha := encode(digest(p_content, 'sha1'), 'hex');

    -- Insert blob if not already exists
    INSERT INTO pggit_v0.blobs (sha1, content, size, created_at)
    VALUES (v_sha, p_content, LENGTH(p_content), NOW())
    ON CONFLICT (sha1) DO NOTHING;

    RETURN v_sha;
  END;
  $$ LANGUAGE plpgsql;

Test:
  SELECT pggit_v0.create_blob('Hello, World!')
  -- Returns: '356a192b7913b04c54574d18c28d46e6395428ab'
```

#### get_blob(sha TEXT) RETURNS TEXT
```sql
Purpose: Retrieve blob content by SHA

Implementation:
  CREATE FUNCTION pggit_v0.get_blob(p_sha TEXT)
  RETURNS TEXT AS $$
  BEGIN
    RETURN content FROM pggit_v0.blobs WHERE sha1 = p_sha;
  END;
  $$ LANGUAGE plpgsql;
```

---

### 2.2 Tree Functions

#### create_tree(entries JSONB) RETURNS TEXT
```sql
Purpose: Create a tree (directory listing) and return its SHA-1

Algorithm:
  1. Validate all entries (check referenced blobs/trees exist)
  2. Sort entries by name (git uses canonical ordering)
  3. Compute SHA-1 of sorted tree structure
  4. Insert into pggit_v0.trees table
  5. Return SHA-1

Tree Entry Format:
  {
    "name": "filename.txt",
    "mode": "100644",          // Unix permissions
    "type": "blob",            // "blob" or "tree"
    "sha": "abc123..."         // SHA-1 of blob/tree
  }

Implementation:
  CREATE FUNCTION pggit_v0.create_tree(p_entries JSONB)
  RETURNS TEXT AS $$
  DECLARE
    v_sha TEXT;
    v_sorted_entries JSONB;
    v_entry JSONB;
  BEGIN
    -- Validate all entries exist
    FOR v_entry IN SELECT jsonb_array_elements(p_entries)
    LOOP
      IF v_entry->>'type' = 'blob' THEN
        IF NOT EXISTS (SELECT 1 FROM pggit_v0.blobs WHERE sha1 = v_entry->>'sha') THEN
          RAISE EXCEPTION 'Blob not found: %', v_entry->>'sha';
        END IF;
      ELSIF v_entry->>'type' = 'tree' THEN
        IF NOT EXISTS (SELECT 1 FROM pggit_v0.trees WHERE sha1 = v_entry->>'sha') THEN
          RAISE EXCEPTION 'Tree not found: %', v_entry->>'sha';
        END IF;
      END IF;
    END LOOP;

    -- Sort entries by name (git canonical order)
    v_sorted_entries := (
      SELECT jsonb_agg(elem ORDER BY elem->>'name')
      FROM jsonb_array_elements(p_entries) elem
    );

    -- Compute SHA-1 of sorted tree
    v_sha := encode(digest(v_sorted_entries::TEXT, 'sha1'), 'hex');

    -- Insert tree
    INSERT INTO pggit_v0.trees (sha1, entries, created_at)
    VALUES (v_sha, v_sorted_entries, NOW())
    ON CONFLICT (sha1) DO NOTHING;

    RETURN v_sha;
  END;
  $$ LANGUAGE plpgsql;
```

#### get_tree(sha TEXT) RETURNS JSONB
```sql
Purpose: Retrieve tree entries by SHA

Implementation:
  CREATE FUNCTION pggit_v0.get_tree(p_sha TEXT)
  RETURNS JSONB AS $$
  BEGIN
    RETURN entries FROM pggit_v0.trees WHERE sha1 = p_sha;
  END;
  $$ LANGUAGE plpgsql;
```

---

### 2.3 Commit Functions

#### create_commit(tree_sha TEXT, parents TEXT[], author TEXT, message TEXT) RETURNS TEXT
```sql
Purpose: Create a commit (version snapshot)

Algorithm:
  1. Validate tree exists
  2. Validate all parent commits exist
  3. Compute SHA-1 of commit data
  4. Insert into pggit_v0.commits table
  5. Return SHA-1

Implementation:
  CREATE FUNCTION pggit_v0.create_commit(
    p_tree_sha TEXT,
    p_parents TEXT[],
    p_author TEXT,
    p_message TEXT
  ) RETURNS TEXT AS $$
  DECLARE
    v_sha TEXT;
    v_commit_data TEXT;
    v_parent TEXT;
  BEGIN
    -- Validate tree exists
    IF NOT EXISTS (SELECT 1 FROM pggit_v0.trees WHERE sha1 = p_tree_sha) THEN
      RAISE EXCEPTION 'Tree not found: %', p_tree_sha;
    END IF;

    -- Validate all parents exist
    FOREACH v_parent IN ARRAY p_parents
    LOOP
      IF NOT EXISTS (SELECT 1 FROM pggit_v0.commits WHERE sha1 = v_parent) THEN
        RAISE EXCEPTION 'Parent commit not found: %', v_parent;
      END IF;
    END LOOP;

    -- Create canonical commit data for SHA computation
    v_commit_data := format(
      'tree %s
parents %s
author %s
message %s',
      p_tree_sha,
      ARRAY_TO_STRING(p_parents, E'\n'),
      p_author,
      p_message
    );

    -- Compute SHA-1
    v_sha := encode(digest(v_commit_data, 'sha1'), 'hex');

    -- Insert commit
    INSERT INTO pggit_v0.commits (sha1, tree, parents, author, message, timestamp, created_at)
    VALUES (v_sha, p_tree_sha, p_parents, p_author, p_message, NOW(), NOW())
    ON CONFLICT (sha1) DO NOTHING;

    RETURN v_sha;
  END;
  $$ LANGUAGE plpgsql;
```

#### get_commit(sha TEXT) RETURNS TABLE(...)
```sql
Purpose: Retrieve commit by SHA

Implementation:
  CREATE FUNCTION pggit_v0.get_commit(p_sha TEXT)
  RETURNS TABLE(
    sha1 TEXT,
    tree TEXT,
    parents TEXT[],
    author TEXT,
    message TEXT,
    timestamp TIMESTAMP
  ) AS $$
  BEGIN
    RETURN QUERY
    SELECT
      commits.sha1,
      commits.tree,
      commits.parents,
      commits.author,
      commits.message,
      commits.timestamp
    FROM pggit_v0.commits
    WHERE commits.sha1 = p_sha;
  END;
  $$ LANGUAGE plpgsql;
```

---

### 2.4 Merge Functions - PART A: Utilities

#### find_merge_base(sha1 TEXT, sha2 TEXT) RETURNS TEXT
```sql
Purpose: Find the lowest common ancestor (merge base) of two commits

Algorithm (Breadth-First Search):
  1. Get all ancestors of commit 1 (BFS from sha1)
  2. Get all ancestors of commit 2 (BFS from sha2)
  3. Find most recent common ancestor
  4. Return that commit's SHA

Why This Matters:
  - Base is the common version before divergence
  - Needed for three-way merge

Implementation:
  CREATE FUNCTION pggit_v0.find_merge_base(p_sha1 TEXT, p_sha2 TEXT)
  RETURNS TEXT AS $$
  DECLARE
    v_ancestors1 TEXT[];
    v_ancestors2 TEXT[];
    v_ancestor TEXT;
    v_queue TEXT[];
    v_base TEXT;
  BEGIN
    -- Get all ancestors of commit 1 (breadth-first)
    v_queue := ARRAY[p_sha1];
    v_ancestors1 := ARRAY[p_sha1];

    WHILE array_length(v_queue, 1) > 0
    LOOP
      v_ancestor := v_queue[1];
      v_queue := v_queue[2:];

      -- Add all parents to queue
      SELECT parents INTO v_parents FROM pggit_v0.commits WHERE sha1 = v_ancestor;
      IF v_parents IS NOT NULL THEN
        v_queue := v_queue || v_parents;
        v_ancestors1 := v_ancestors1 || v_parents;
      END IF;
    END LOOP;

    -- Find first common ancestor (most recent in commit 2's history)
    WITH RECURSIVE ancestors_of_sha2 AS (
      SELECT sha1, parents, timestamp FROM pggit_v0.commits WHERE sha1 = p_sha2
      UNION ALL
      SELECT c.sha1, c.parents, c.timestamp
      FROM pggit_v0.commits c
      JOIN ancestors_of_sha2 a ON c.sha1 = ANY(a.parents)
    )
    SELECT sha1 INTO v_base
    FROM ancestors_of_sha2
    WHERE sha1 = ANY(v_ancestors1)
    ORDER BY timestamp DESC
    LIMIT 1;

    RETURN v_base;
  END;
  $$ LANGUAGE plpgsql;
```

#### get_tree_files(tree_sha TEXT, path_prefix TEXT DEFAULT '') RETURNS TABLE(...)
```sql
Purpose: Get all files in a tree recursively (flattened list)

Returns:
  - file_path: Full path from root (e.g., "src/main.sql")
  - blob_sha: SHA of file content
  - mode: Unix permissions

Implementation:
  CREATE FUNCTION pggit_v0.get_tree_files(
    p_tree_sha TEXT,
    p_path_prefix TEXT DEFAULT ''
  )
  RETURNS TABLE(
    file_path TEXT,
    blob_sha TEXT,
    mode TEXT
  ) AS $$
  WITH RECURSIVE tree_walker AS (
    -- Base case: entries in root tree
    SELECT
      jsonb_array_elements(entries)->>'name' AS name,
      jsonb_array_elements(entries)->>'sha' AS sha,
      jsonb_array_elements(entries)->>'type' AS type,
      jsonb_array_elements(entries)->>'mode' AS mode,
      '' AS path_so_far
    FROM pggit_v0.trees
    WHERE sha1 = p_tree_sha

    UNION ALL

    -- Recursive case: descend into subtrees
    SELECT
      jsonb_array_elements(t.entries)->>'name',
      jsonb_array_elements(t.entries)->>'sha',
      jsonb_array_elements(t.entries)->>'type',
      jsonb_array_elements(t.entries)->>'mode',
      CASE WHEN tw.path_so_far = ''
        THEN tw.name
        ELSE tw.path_so_far || '/' || tw.name
      END
    FROM tree_walker tw
    JOIN pggit_v0.trees t ON t.sha1 = tw.sha
    WHERE tw.type = 'tree'
  )
  SELECT
    p_path_prefix || path_so_far || '/' || name AS file_path,
    sha AS blob_sha,
    mode
  FROM tree_walker
  WHERE type = 'blob';
  $$ LANGUAGE plpgsql;
```

---

### 2.5 Merge Functions - PART B: Three-Way Merge

#### three_way_merge(base_sha TEXT, ours_sha TEXT, theirs_sha TEXT) RETURNS TABLE(...)
```sql
Purpose: Perform git-style three-way merge on two commits

Algorithm:
  1. Get merge base using find_merge_base()
  2. Extract all files from base, ours, and theirs
  3. For each file, determine merge result:
     a. If file only in ours → keep ours
     b. If file only in theirs → take theirs
     c. If deleted by one side, modified by other → CONFLICT
     d. If both sides modified differently → check if mergeable
     e. If same content → no conflict
  4. Build result tree from merged files
  5. Record any conflicts

Returns:
  - success: BOOLEAN (true if no conflicts)
  - result_tree_sha: TEXT (SHA of merged tree, or NULL if conflicts)
  - conflict_count: INTEGER
  - conflicts: JSONB (array of conflict details)

Implementation:
  CREATE FUNCTION pggit_v0.three_way_merge(
    p_base_sha TEXT,
    p_ours_sha TEXT,
    p_theirs_sha TEXT
  )
  RETURNS TABLE(
    success BOOLEAN,
    result_tree_sha TEXT,
    conflict_count INTEGER,
    conflicts JSONB
  ) AS $$
  DECLARE
    v_base_tree TEXT;
    v_ours_tree TEXT;
    v_theirs_tree TEXT;
    v_base_files RECORD;
    v_ours_files RECORD;
    v_theirs_files RECORD;
    v_merged_entries JSONB;
    v_conflicts JSONB;
    v_conflict_count INTEGER := 0;
    v_file_path TEXT;
    v_base_content TEXT;
    v_ours_content TEXT;
    v_theirs_content TEXT;
    v_result_content TEXT;
    v_all_files TEXT[];
  BEGIN
    -- Get trees for each commit
    SELECT tree INTO v_base_tree FROM pggit_v0.commits WHERE sha1 = p_base_sha;
    SELECT tree INTO v_ours_tree FROM pggit_v0.commits WHERE sha1 = p_ours_sha;
    SELECT tree INTO v_theirs_tree FROM pggit_v0.commits WHERE sha1 = p_theirs_sha;

    -- Get all file lists
    SELECT array_agg(DISTINCT file_path ORDER BY file_path)
    INTO v_all_files
    FROM (
      SELECT file_path FROM pggit_v0.get_tree_files(v_base_tree)
      UNION ALL
      SELECT file_path FROM pggit_v0.get_tree_files(v_ours_tree)
      UNION ALL
      SELECT file_path FROM pggit_v0.get_tree_files(v_theirs_tree)
    ) all_files;

    v_merged_entries := '[]'::JSONB;
    v_conflicts := '[]'::JSONB;

    -- Merge each file
    FOREACH v_file_path IN ARRAY v_all_files
    LOOP
      -- Get content from each version
      SELECT blob_sha INTO v_base_content
      FROM pggit_v0.get_tree_files(v_base_tree)
      WHERE file_path = v_file_path;

      SELECT blob_sha INTO v_ours_content
      FROM pggit_v0.get_tree_files(v_ours_tree)
      WHERE file_path = v_file_path;

      SELECT blob_sha INTO v_theirs_content
      FROM pggit_v0.get_tree_files(v_theirs_tree)
      WHERE file_path = v_file_path;

      -- Merge logic
      IF v_ours_content = v_theirs_content THEN
        -- Both sides same → no conflict
        IF v_ours_content IS NOT NULL THEN
          v_merged_entries := v_merged_entries || jsonb_build_object(
            'name', v_file_path,
            'mode', '100644',
            'type', 'blob',
            'sha', v_ours_content
          );
        END IF;
      ELSIF v_ours_content = v_base_content THEN
        -- Only theirs changed
        IF v_theirs_content IS NOT NULL THEN
          v_merged_entries := v_merged_entries || jsonb_build_object(
            'name', v_file_path,
            'mode', '100644',
            'type', 'blob',
            'sha', v_theirs_content
          );
        END IF;
      ELSIF v_theirs_content = v_base_content THEN
        -- Only ours changed
        IF v_ours_content IS NOT NULL THEN
          v_merged_entries := v_merged_entries || jsonb_build_object(
            'name', v_file_path,
            'mode', '100644',
            'type', 'blob',
            'sha', v_ours_content
          );
        END IF;
      ELSE
        -- Both sides changed differently → CONFLICT
        v_conflict_count := v_conflict_count + 1;
        v_conflicts := v_conflicts || jsonb_build_object(
          'file_path', v_file_path,
          'base_sha', v_base_content,
          'ours_sha', v_ours_content,
          'theirs_sha', v_theirs_content,
          'base_content', pggit_v0.get_blob(v_base_content),
          'ours_content', pggit_v0.get_blob(v_ours_content),
          'theirs_content', pggit_v0.get_blob(v_theirs_content)
        );

        -- For now, keep ours in case of conflict
        -- (can be customized later)
        IF v_ours_content IS NOT NULL THEN
          v_merged_entries := v_merged_entries || jsonb_build_object(
            'name', v_file_path,
            'mode', '100644',
            'type', 'blob',
            'sha', v_ours_content,
            'conflict', TRUE
          );
        END IF;
      END IF;
    END LOOP;

    -- Create result tree
    IF v_conflict_count = 0 THEN
      RETURN QUERY SELECT
        TRUE::BOOLEAN,
        pggit_v0.create_tree(v_merged_entries),
        0::INTEGER,
        NULL::JSONB;
    ELSE
      RETURN QUERY SELECT
        FALSE::BOOLEAN,
        NULL::TEXT,
        v_conflict_count::INTEGER,
        v_conflicts;
    END IF;
  END;
  $$ LANGUAGE plpgsql;
```

#### create_merge_commit(base_sha TEXT, ours_sha TEXT, theirs_sha TEXT, author TEXT, message TEXT) RETURNS TABLE(...)
```sql
Purpose: If merge succeeds, create a merge commit with both parents

Implementation:
  CREATE FUNCTION pggit_v0.create_merge_commit(
    p_base_sha TEXT,
    p_ours_sha TEXT,
    p_theirs_sha TEXT,
    p_author TEXT,
    p_message TEXT
  )
  RETURNS TABLE(
    success BOOLEAN,
    merge_commit_sha TEXT,
    conflicts_count INTEGER
  ) AS $$
  DECLARE
    v_merge_result RECORD;
    v_merge_commit_sha TEXT;
  BEGIN
    -- Perform merge
    SELECT * INTO v_merge_result
    FROM pggit_v0.three_way_merge(p_base_sha, p_ours_sha, p_theirs_sha);

    IF v_merge_result.success THEN
      -- Create merge commit with both parents
      v_merge_commit_sha := pggit_v0.create_commit(
        v_merge_result.result_tree_sha,
        ARRAY[p_ours_sha, p_theirs_sha],
        p_author,
        p_message || E'\n\n(Merge commit from ' || p_base_sha || ')'
      );

      RETURN QUERY SELECT
        TRUE::BOOLEAN,
        v_merge_commit_sha,
        0::INTEGER;
    ELSE
      RETURN QUERY SELECT
        FALSE::BOOLEAN,
        NULL::TEXT,
        v_merge_result.conflict_count;
    END IF;
  END;
  $$ LANGUAGE plpgsql;
```

---

## Part 3: Database Schema

### 3.1 Create Schema
```sql
CREATE SCHEMA IF NOT EXISTS pggit_v0;
```

### 3.2 Create Tables

#### pggit_v0.blobs
```sql
CREATE TABLE pggit_v0.blobs (
    sha1 TEXT PRIMARY KEY CHECK (LENGTH(sha1) = 40),
    content TEXT NOT NULL,
    size BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_blobs_size ON pggit_v0.blobs(size);
CREATE INDEX idx_blobs_created ON pggit_v0.blobs(created_at);
```

#### pggit_v0.trees
```sql
CREATE TABLE pggit_v0.trees (
    sha1 TEXT PRIMARY KEY CHECK (LENGTH(sha1) = 40),
    entries JSONB NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_trees_created ON pggit_v0.trees(created_at);
```

#### pggit_v0.commits
```sql
CREATE TABLE pggit_v0.commits (
    sha1 TEXT PRIMARY KEY CHECK (LENGTH(sha1) = 40),
    tree TEXT NOT NULL REFERENCES pggit_v0.trees(sha1),
    parents TEXT[] DEFAULT ARRAY[]::TEXT[],
    author TEXT NOT NULL,
    message TEXT NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_commits_tree ON pggit_v0.commits(tree);
CREATE INDEX idx_commits_timestamp ON pggit_v0.commits(timestamp);
CREATE INDEX idx_commits_author ON pggit_v0.commits(author);
```

#### pggit_v0.merge_context
```sql
CREATE TABLE pggit_v0.merge_context (
    merge_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    base_sha TEXT NOT NULL REFERENCES pggit_v0.commits(sha1),
    ours_sha TEXT NOT NULL REFERENCES pggit_v0.commits(sha1),
    theirs_sha TEXT NOT NULL REFERENCES pggit_v0.commits(sha1),
    status TEXT NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'success', 'conflict', 'error')),
    conflict_count INTEGER DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_merge_status ON pggit_v0.merge_context(status);
```

#### pggit_v0.conflicts
```sql
CREATE TABLE pggit_v0.conflicts (
    conflict_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merge_id UUID NOT NULL REFERENCES pggit_v0.merge_context(merge_id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    base_sha TEXT REFERENCES pggit_v0.blobs(sha1),
    ours_sha TEXT NOT NULL REFERENCES pggit_v0.blobs(sha1),
    theirs_sha TEXT NOT NULL REFERENCES pggit_v0.blobs(sha1),
    resolved BOOLEAN DEFAULT FALSE,
    resolution TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_conflicts_merge ON pggit_v0.conflicts(merge_id);
CREATE INDEX idx_conflicts_file ON pggit_v0.conflicts(file_path);
```

#### pggit_v0.merge_results
```sql
CREATE TABLE pggit_v0.merge_results (
    merge_id UUID PRIMARY KEY REFERENCES pggit_v0.merge_context(merge_id) ON DELETE CASCADE,
    result_tree_sha TEXT REFERENCES pggit_v0.trees(sha1),
    merged_commit_sha TEXT REFERENCES pggit_v0.commits(sha1),
    conflict_count INTEGER,
    success BOOLEAN,
    details JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
```

#### pggit_v0.statistics
```sql
CREATE TABLE pggit_v0.statistics (
    stat_date DATE PRIMARY KEY DEFAULT CURRENT_DATE,
    total_objects INTEGER,
    total_commits INTEGER,
    total_blobs INTEGER,
    total_trees INTEGER,
    total_merges INTEGER,
    successful_merges INTEGER,
    conflicted_merges INTEGER,
    last_updated TIMESTAMP DEFAULT NOW()
);
```

---

## Part 4: Utilities & Helpers

### 4.1 Verification Functions

#### verify_blob_exists(sha TEXT) RETURNS BOOLEAN
```sql
Purpose: Check if blob exists

Implementation:
  CREATE FUNCTION pggit_v0.verify_blob_exists(p_sha TEXT)
  RETURNS BOOLEAN AS $$
  BEGIN
    RETURN EXISTS(SELECT 1 FROM pggit_v0.blobs WHERE sha1 = p_sha);
  END;
  $$ LANGUAGE plpgsql STABLE;
```

#### verify_tree_exists(sha TEXT) RETURNS BOOLEAN
```sql
Similar to verify_blob_exists
```

#### verify_commit_exists(sha TEXT) RETURNS BOOLEAN
```sql
Similar to verify_blob_exists
```

#### verify_object_integrity(object_type TEXT, sha TEXT) RETURNS BOOLEAN
```sql
Purpose: Verify object hasn't been corrupted

Implementation:
  - For blobs: Re-hash content and compare to stored SHA
  - For trees: Validate all referenced objects exist
  - For commits: Validate tree and parents exist
```

---

### 4.2 Analysis Functions

#### get_commit_ancestry(commit_sha TEXT) RETURNS TABLE(...)
```sql
Purpose: Get all ancestors of a commit

Returns:
  - ancestor_sha: SHA of ancestor
  - distance: Distance from root (0 = direct parent)
  - timestamp: When committed
```

#### count_commits_between(base_sha TEXT, head_sha TEXT) RETURNS INTEGER
```sql
Purpose: Count commits between two points

Implementation:
  Get all ancestors of head_sha, filter for those after base_sha
```

#### get_divergence_point(sha1 TEXT, sha2 TEXT) RETURNS TEXT
```sql
Purpose: Find where two branches diverged

Implementation:
  Find merge base, return that SHA
```

---

### 4.3 Utility Functions

#### reset_pggit_v0() RETURNS VOID
```sql
Purpose: Clear all data (for testing)

Implementation:
  DELETE FROM pggit_v0.conflicts;
  DELETE FROM pggit_v0.merge_results;
  DELETE FROM pggit_v0.merge_context;
  DELETE FROM pggit_v0.commits;
  DELETE FROM pggit_v0.trees;
  DELETE FROM pggit_v0.blobs;
  DELETE FROM pggit_v0.statistics;
```

#### rebuild_statistics() RETURNS VOID
```sql
Purpose: Recalculate all statistics

Implementation:
  INSERT INTO pggit_v0.statistics (...)
  SELECT ... FROM pggit_v0 tables
  ON CONFLICT DO UPDATE
```

---

## Part 5: Implementation Phases

### Phase 1: Schema Creation (1 hour)
- [ ] Create pggit_v0 schema
- [ ] Create all tables
- [ ] Create indexes
- [ ] Test: Can create tables, inserts work

### Phase 2: Core Object Functions (2 hours)
- [ ] Implement create_blob()
- [ ] Implement get_blob()
- [ ] Implement create_tree()
- [ ] Implement get_tree()
- [ ] Test: Can create and retrieve blobs/trees

### Phase 3: Commit Functions (1.5 hours)
- [ ] Implement create_commit()
- [ ] Implement get_commit()
- [ ] Test: Can create commits with parents

### Phase 4: Merge Utilities (1 hour)
- [ ] Implement find_merge_base()
- [ ] Implement get_tree_files()
- [ ] Test: Can find merge base

### Phase 5: Three-Way Merge (2 hours)
- [ ] Implement three_way_merge()
- [ ] Test simple merges without conflicts
- [ ] Test conflict detection

### Phase 6: Merge Commit & Helpers (1 hour)
- [ ] Implement create_merge_commit()
- [ ] Implement verification functions
- [ ] Implement analysis functions

### Phase 7: Testing & Verification (1-2 hours)
- [ ] Run all test-proper-three-way-merge.sql tests
- [ ] Run all test-three-way-merge-simple.sql tests
- [ ] Verify no regressions

---

## Part 6: Testing Strategy

### Unit Tests (Per Function)

#### Test create_blob()
```sql
-- Test 1: Basic blob creation
SELECT pggit_v0.create_blob('Hello, World!')
-- Expected: Returns valid SHA (40 chars)

-- Test 2: Idempotence (same content = same SHA)
SELECT pggit_v0.create_blob('test') = pggit_v0.create_blob('test')
-- Expected: TRUE

-- Test 3: Different content = different SHA
SELECT pggit_v0.create_blob('a') <> pggit_v0.create_blob('b')
-- Expected: TRUE
```

#### Test create_tree()
```sql
-- Test 1: Basic tree creation
SELECT pggit_v0.create_tree('[
  {"name": "file.txt", "mode": "100644", "type": "blob", "sha": "..."}
]')
-- Expected: Valid SHA

-- Test 2: Tree with invalid blob reference
SELECT pggit_v0.create_tree('[
  {"name": "file.txt", "mode": "100644", "type": "blob", "sha": "invalid"}
]')
-- Expected: EXCEPTION "Blob not found"
```

#### Test find_merge_base()
```sql
-- Create linear history
c0 = create_commit(tree0, [], 'author', 'initial')
c1 = create_commit(tree0, [c0], 'author', 'update')
c2 = create_commit(tree0, [c0], 'author', 'branch')

-- find_merge_base(c1, c2) should return c0
SELECT pggit_v0.find_merge_base(c1, c2) = c0
-- Expected: TRUE
```

#### Test three_way_merge()
```sql
-- Scenario 1: No conflicts
base: file.txt = 'line1\nline2'
ours: file.txt = 'line1\nline2\nline3'  (added line3)
theirs: file.txt = 'line1\nline2\nline4' (added line4)

Result: CONFLICT (both added different lines)

-- Scenario 2: One-sided change
base: file.txt = 'content'
ours: file.txt = 'content' (no change)
theirs: file.txt = 'modified'

Result: SUCCESS (keep theirs)

-- Scenario 3: Same change by both
base: file.txt = 'content'
ours: file.txt = 'same'
theirs: file.txt = 'same'

Result: SUCCESS (no conflict)
```

### Integration Tests (Full Workflow)

Test case from test-proper-three-way-merge.sql:
```sql
-- Create initial commit
SET blob1 = pggit_v0.create_blob('Hello, World!')
SET tree1 = pggit_v0.create_tree('[{"name": "file.txt", "mode": "100644", "type": "blob", "sha": blob1}]')
SET commit1 = pggit_v0.create_commit(tree1, [], 'Author', 'Initial commit')

-- Create branch and make changes
SET blob2 = pggit_v0.create_blob('Hello, World!\nOur changes')
SET tree2 = pggit_v0.create_tree('[{"name": "file.txt", "mode": "100644", "type": "blob", "sha": blob2}]')
SET commit2 = pggit_v0.create_commit(tree2, [commit1], 'Author', 'Our changes')

-- Create conflicting branch
SET blob3 = pggit_v0.create_blob('Hello, World!\nTheir changes')
SET tree3 = pggit_v0.create_tree('[{"name": "file.txt", "mode": "100644", "type": "blob", "sha": blob3}]')
SET commit3 = pggit_v0.create_commit(tree3, [commit1], 'Author', 'Their changes')

-- Attempt merge
SELECT pggit_v0.three_way_merge(commit1, commit2, commit3)
-- Expected: success=FALSE, conflict_count=1, conflicts=[{...}]
```

### Regression Tests
```sql
-- After implementation, run these test files:
\i tests/test-proper-three-way-merge.sql
\i tests/test-three-way-merge-simple.sql

-- Expected: All tests pass
```

---

## Part 7: Performance Considerations

### Indexes
- sha1 columns: PRIMARY KEY (automatic index)
- tree.entries: JSONB column (consider GIN index for large trees)
- commits.timestamp: For historical queries
- merge_context.status: For filtering merges

### Query Optimization
```sql
-- For get_tree_files(), the recursive CTE might be slow on deep trees
-- Alternative: Flatten tree structure on write (pre-compute file list)
-- Trade-off: Faster reads, slower writes

-- For three_way_merge(), getting all files is expensive
-- Optimization: Only compute differences (3-way diff algorithm)
-- But: Would require implementing unified diff logic
```

### Scaling Considerations
- For very large repositories:
  - Consider partitioning by date/hash range
  - Archive old commits to separate table
  - Cache merge results
  - Use materialized views for common queries

---

## Part 8: Success Criteria

### Functional Requirements
- [x] Can create blobs with deterministic SHA-1
- [x] Can create trees with sorted entries
- [x] Can create commits with parent pointers
- [x] Can find merge base of two commits
- [x] Can detect conflicts in three-way merge
- [x] Can create merge commits

### Test Requirements
- [ ] test-proper-three-way-merge.sql: ALL TESTS PASS
- [ ] test-three-way-merge-simple.sql: ALL TESTS PASS
- [ ] No regressions in other tests
- [ ] Chaos tests: Still 117/120 passing

### Code Quality
- [ ] All functions documented with purpose
- [ ] All edge cases handled
- [ ] All errors have meaningful messages
- [ ] Consistent naming conventions
- [ ] Proper transaction handling

### Performance
- [ ] blob creation: < 1ms
- [ ] tree creation: < 5ms (for trees with 100 entries)
- [ ] commit creation: < 1ms
- [ ] find_merge_base: < 50ms (for typical repos)
- [ ] three_way_merge: < 100ms (for typical changes)

---

## Part 9: Implementation Checklist

### Pre-Implementation
- [ ] Review this entire plan
- [ ] Create separate branch for implementation
- [ ] Set up test environment

### Schema Phase
- [ ] Create sql/pggit_v0_schema.sql with all tables
- [ ] Create indexes
- [ ] Verify schema loads without errors
- [ ] Write schema tests

### Blob Functions Phase
- [ ] Implement create_blob()
- [ ] Implement get_blob()
- [ ] Test with various content sizes
- [ ] Test idempotence

### Tree Functions Phase
- [ ] Implement create_tree()
- [ ] Implement get_tree()
- [ ] Implement get_tree_files()
- [ ] Test entry validation
- [ ] Test recursive file extraction

### Commit Functions Phase
- [ ] Implement create_commit()
- [ ] Implement get_commit()
- [ ] Test parent validation
- [ ] Test linear history
- [ ] Test merge commits (2+ parents)

### Merge Utilities Phase
- [ ] Implement find_merge_base()
- [ ] Test with various tree structures
- [ ] Test with deep history

### Three-Way Merge Phase
- [ ] Implement three_way_merge()
- [ ] Test no-conflict scenario
- [ ] Test one-sided change
- [ ] Test both-sides-change (conflict)
- [ ] Test file deletions
- [ ] Test file additions

### Merge Commit Phase
- [ ] Implement create_merge_commit()
- [ ] Test successful merge commit creation
- [ ] Test merge commit with parents

### Utility Functions Phase
- [ ] Implement verification functions
- [ ] Implement analysis functions
- [ ] Implement reset_pggit_v0()
- [ ] Implement rebuild_statistics()

### Testing Phase
- [ ] Run unit tests for each function
- [ ] Run integration tests
- [ ] Run test-proper-three-way-merge.sql
- [ ] Run test-three-way-merge-simple.sql
- [ ] Run full test suite (./tests/test-full.sh)
- [ ] Run chaos tests (pytest)

### Verification Phase
- [ ] All tests pass
- [ ] No regressions
- [ ] Performance acceptable
- [ ] Code review complete
- [ ] Documentation complete

### Final
- [ ] Commit with descriptive message
- [ ] Create PR/merge to main
- [ ] Update related documentation
- [ ] Mark Phase 1 as complete

---

## Estimated Timeline

| Phase | Task | Duration |
|-------|------|----------|
| 1 | Schema creation | 1 hour |
| 2 | Core object functions | 2 hours |
| 3 | Commit functions | 1.5 hours |
| 4 | Merge utilities | 1 hour |
| 5 | Three-way merge | 2 hours |
| 6 | Merge commit & helpers | 1 hour |
| 7 | Testing & verification | 1-2 hours |
| **TOTAL** | | **9.5-10.5 hours** |

---

## Next Steps

1. ✅ Review and approve this plan
2. → Create implementation branch
3. → Start Phase 1 (Schema)
4. → Complete each phase sequentially
5. → Test after each phase
6. → Verify all tests pass
7. → Commit and merge

Ready to proceed?
