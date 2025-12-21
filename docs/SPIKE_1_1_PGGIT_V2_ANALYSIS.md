# Spike 1.1: pggit_v2 Data Format Analysis

**Date**: December 21, 2025
**Engineer**: Claude (Spike Analysis)
**Duration**: ~3 hours (including bug fixes)

## Executive Summary

pggit_v2 uses a proper Git-like content-addressable storage system with the following key characteristics:

- **Content-addressable**: All objects identified by SHA-256 hash of content
- **Complete snapshots**: Each commit stores full schema snapshot, not incremental changes
- **Git-compatible format**: Uses Git's object format (blob, tree, commit)
- **Performance optimized**: Includes commit graph and tree entry caches

## pggit_v2.objects Table Structure

```sql
CREATE TABLE pggit_v2.objects (
    sha TEXT PRIMARY KEY,
    type TEXT NOT NULL CHECK (type IN ('commit', 'tree', 'blob', 'tag')),
    size INTEGER NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Content Format by Object Type

#### 1. Blob Objects
- **Purpose**: Store individual object definitions (tables, functions, etc.)
- **Content**: Plain text SQL DDL definition
- **Example**:
  ```sql
  CREATE TABLE test_schema.test_table (
    id INTEGER PRIMARY KEY,
    name TEXT
  );
  ```
- **SHA calculation**: `sha256('blob ' || length(content) || ':' || content)`

#### 2. Tree Objects
- **Purpose**: Represent directory structure at a point in time
- **Content**: Base64-encoded Git tree format
- **Raw format**: `mode path|sha|mode path|sha|...`
- **Example decoded content**:
  ```
  100644 test_schema.test_table|967f36ce0feaf048c21d53671afc3bf35a581bd5ee9126dce69dceaecb4e7e3a|
  ```
- **SHA calculation**: `sha256('tree ' || length(raw_content) || ':' || raw_content)`

#### 3. Commit Objects
- **Purpose**: Represent commits with metadata
- **Content**: Git commit format (plain text)
- **Example**:
  ```
  tree bf19b24bc20284c8e12dceaea22348fc94c176de929350b1419aa1229b719a65
  author lionel <lionel@pggit> 1766352754 +0000
  committer lionel <lionel@pggit> 1766352754 +0000

  Initial commit: Add test_schema.test_table
  ```
- **SHA calculation**: `sha256('commit ' || length(content) || ':' || content)`

## Performance Optimization Structures

### pggit_v2.commit_graph
- **Purpose**: Fast commit traversal and merge-base calculation
- **Key fields**:
  - `parent_shas TEXT[]`: Array of parent commit SHAs
  - `generation INTEGER`: Distance from root commit
  - Denormalized author/committer/timestamp data

### pggit_v2.tree_entries
- **Purpose**: Fast tree comparison without decoding base64
- **Structure**: `(tree_sha, path, mode, object_sha)`
- **Enables O(1) tree diffs**

## Key Findings

### 1. Data Storage Model
- **Complete snapshots**: Each commit contains full schema state
- **Content-addressable**: Deduplication via SHA-256 hashing
- **Immutable objects**: Once created, objects never change

### 2. Change Detection
- **Tree comparison**: Changes detected by comparing tree SHAs
- **Path-based diffing**: `diff_trees()` function shows added/modified/deleted paths
- **Efficient**: Uses cached tree_entries for fast comparisons

### 3. From Commit to DDL
**Path**: `commit_sha` → `commit_graph.tree_sha` → `tree_entries` → `objects.sha` → `objects.content`

```sql
-- Get DDL for specific object at specific commit
SELECT o.content
FROM pggit_v2.commit_graph cg
JOIN pggit_v2.tree_entries te ON te.tree_sha = cg.tree_sha
JOIN pggit_v2.objects o ON o.sha = te.object_sha
WHERE cg.commit_sha = 'f5bcb99dc602c2532f5b17f13eae2c2adb01eb6775d0b2f0e952829372eb5057'
  AND te.path = 'test_schema.test_table';
```

### 4. Size Characteristics
- **Blob size**: DDL text length (e.g., 78 chars for simple table)
- **Tree size**: Scales with number of objects
- **Commit size**: ~200-300 chars (metadata + message)

### 5. Limitations Discovered
- **JSON handling bug**: `create_tree()` function had JSONB operator issues (fixed during testing)
- **Diff function bug**: Column name conflicts in `diff_trees()` (fixed during testing)

## Implications for Migration

### ✅ Positive Findings
- **Clear data model**: Well-structured Git-like objects
- **Diff capability**: Can detect changes between any two commits
- **DDL extraction**: Straightforward path from commit → tree → blob → DDL
- **Performance**: Optimized with caches for common operations

### ⚠️ Challenges Identified
- **Complete snapshots**: Backfill must reconstruct entire schema at each version
- **No incremental changes**: Cannot easily extract "what changed" between commits
- **Function bugs**: Some functions need fixes before production use

### 📊 Effort Estimate for Spike 1.2
Based on data format understanding:
- **DDL extraction**: 6-8 hours (need to build extraction functions)
- **Backfill algorithm**: 4-6 hours (complex due to snapshot reconstruction)
- **Total Spike 1.2-1.3**: 10-14 hours

## Test Data Created

```sql
-- Objects created during testing:
-- 2 blobs: Original table, modified table (added email column)
-- 2 trees: Tree with original table, tree with modified table
-- 2 commits: Initial commit, commit with email column addition

SELECT type, COUNT(*) FROM pggit_v2.objects GROUP BY type;
-- blob: 2, tree: 2, commit: 2
```

## Next Steps

1. **Spike 1.2**: Build DDL extraction functions using this understanding
2. **Spike 1.3**: Design backfill algorithm for v1 → v2 conversion
3. **Fix remaining bugs**: Test all pggit_v2 functions thoroughly

## Confidence Level

**High confidence** in pggit_v2 data format understanding. The Git-like structure is well-designed and appropriate for schema versioning. The main remaining unknowns are around extraction implementation details and backfill performance.</content>
<parameter name="filePath">SPIKE_1_1_PGGIT_V2_ANALYSIS.md