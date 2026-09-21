-- pggit v1.0 — Index definitions

-- objects: branch + schema + name lookup (most common query pattern)
CREATE INDEX objects_branch_schema_name_idx
    ON pggit.objects (branch_id, schema_name, object_name);

-- objects: OID lookup for event trigger (frequent during DDL)
CREATE INDEX objects_branch_oid_idx
    ON pggit.objects (branch_id, pg_oid)
    WHERE pg_oid IS NOT NULL AND is_deleted = FALSE;

-- history: BRIN for time-range scans on the append-only log
CREATE INDEX history_changed_at_brin_idx
    ON pggit.history USING BRIN (changed_at);

-- history: object timeline lookup
CREATE INDEX history_object_id_idx
    ON pggit.history (object_id, changed_at DESC);

-- commits: branch DAG walk
CREATE INDEX commits_branch_parent_idx
    ON pggit.commits (branch_id, parent_id);

-- commits: head lookup (newest commit on a branch)
CREATE INDEX commits_branch_committed_at_idx
    ON pggit.commits (branch_id, committed_at DESC);

-- merge_conflicts: open conflict lookup
CREATE INDEX merge_conflicts_open_idx
    ON pggit.merge_conflicts (merge_id, status)
    WHERE status = 'conflicted';
