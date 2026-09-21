-- pggit v1.0 — Table definitions
-- Core invariant: content_hash is NEVER NULL.

-- Table 1: branches
CREATE TABLE pggit.branches (
    id              BIGSERIAL PRIMARY KEY,
    tenant_id       UUID,  -- NULL = shared/admin mode (backward compatible)
    name            TEXT NOT NULL,
    parent_id       BIGINT REFERENCES pggit.branches(id),
    status          pggit.branch_status NOT NULL DEFAULT 'active',
    head_commit_id  BIGINT,  -- FK added after commits table via ALTER
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT branches_name_valid
        CHECK (name ~ '^[a-zA-Z0-9._-]+$'),
    CONSTRAINT branches_name_unique
        UNIQUE (name)
);

COMMENT ON TABLE pggit.branches IS
    'Named branch, analogous to a Git branch. head_commit_id points to the '
    'most recent commit on this branch.';

COMMENT ON COLUMN pggit.branches.name IS
    'Branch names: alphanumeric, dots, hyphens only. No slashes.';

COMMENT ON COLUMN pggit.branches.head_commit_id IS
    'Most recent commit on this branch. NULL until the first commit is made.';

COMMENT ON COLUMN pggit.branches.tenant_id IS
    'Tenant UUID for multi-tenant isolation. NULL = shared/admin mode.';

-- Table 2: commits
CREATE TABLE pggit.commits (
    id              BIGSERIAL PRIMARY KEY,
    tenant_id       UUID,  -- NULL = shared/admin mode (backward compatible)
    branch_id       BIGINT NOT NULL REFERENCES pggit.branches(id),
    parent_id       BIGINT REFERENCES pggit.commits(id),  -- NULL for root commit only
    message         TEXT NOT NULL,
    tree_hash       TEXT NOT NULL,  -- SHA-256 of sorted object hash concatenation
    author          TEXT NOT NULL DEFAULT current_user,
    committed_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT commits_tree_hash_format
        CHECK (tree_hash ~ '^[0-9a-f]{64}$')
);

COMMENT ON TABLE pggit.commits IS
    'Named snapshot of the object tree at a point in time. parent_id forms '
    'the DAG. tree_hash is the SHA-256 of all tracked objects on this branch '
    'at commit time.';

COMMENT ON COLUMN pggit.commits.parent_id IS
    'NULL only for the initial commit on main. All other commits have a parent.';

COMMENT ON COLUMN pggit.commits.tenant_id IS
    'Tenant UUID for multi-tenant isolation. NULL = shared/admin mode.';

-- Add deferred FK from branches.head_commit_id to commits
ALTER TABLE pggit.branches
    ADD CONSTRAINT branches_head_commit_fk
    FOREIGN KEY (head_commit_id) REFERENCES pggit.commits(id)
    DEFERRABLE INITIALLY DEFERRED;

-- Table 3: objects — current state per branch
CREATE TABLE pggit.objects (
    id              BIGSERIAL PRIMARY KEY,
    tenant_id       UUID,  -- NULL = shared/admin mode (backward compatible)
    branch_id       BIGINT NOT NULL REFERENCES pggit.branches(id),
    schema_name     TEXT NOT NULL,
    object_name     TEXT NOT NULL,
    object_type     pggit.object_type NOT NULL,
    content_hash    TEXT NOT NULL,  -- Core invariant: NEVER NULL
    ddl_text        TEXT NOT NULL,  -- Normalized DDL at time of last change
    pg_oid          OID,            -- pg_class/pg_proc OID, NULL after DROP
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT objects_content_hash_format
        CHECK (content_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT objects_branch_object_unique
        UNIQUE (branch_id, schema_name, object_name, object_type)
);

COMMENT ON TABLE pggit.objects IS
    'Current state of each tracked object per branch. One row per '
    '(branch, schema, name, type). Updated in-place on ALTER, soft-deleted '
    'on DROP. content_hash is always populated — never NULL.';

COMMENT ON COLUMN pggit.objects.content_hash IS
    'SHA-256 hex of normalized DDL text. Populated synchronously by the '
    'event trigger. Never NULL.';

COMMENT ON COLUMN pggit.objects.tenant_id IS
    'Tenant UUID for multi-tenant isolation. NULL = shared/admin mode.';

-- Table 4: history — append-only audit log
CREATE TABLE pggit.history (
    id              BIGSERIAL PRIMARY KEY,
    tenant_id       UUID,  -- NULL = shared/admin mode (backward compatible)
    branch_id       BIGINT NOT NULL REFERENCES pggit.branches(id),
    object_id       BIGINT NOT NULL REFERENCES pggit.objects(id),
    commit_id       BIGINT REFERENCES pggit.commits(id),  -- NULL = uncommitted
    operation       TEXT NOT NULL,      -- 'CREATE', 'ALTER', 'DROP'
    content_hash    TEXT NOT NULL,      -- Hash at this point in time
    ddl_text        TEXT NOT NULL,      -- DDL text at this point in time
    changed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT history_operation_valid
        CHECK (operation IN ('CREATE', 'ALTER', 'DROP')),
    CONSTRAINT history_content_hash_format
        CHECK (content_hash ~ '^[0-9a-f]{64}$')
);

COMMENT ON TABLE pggit.history IS
    'Append-only log of every DDL change captured by the event trigger. '
    'commit_id is NULL for changes made after the last commit (working tree). '
    'Used for audit trail and time-travel queries.';

COMMENT ON COLUMN pggit.history.tenant_id IS
    'Tenant UUID for multi-tenant isolation. NULL = shared/admin mode.';

-- Table 5: merge_history — one row per merge attempt
CREATE TABLE pggit.merge_history (
    id                  BIGSERIAL PRIMARY KEY,
    tenant_id           UUID,  -- NULL = shared/admin mode (backward compatible)
    source_branch_id    BIGINT NOT NULL REFERENCES pggit.branches(id),
    target_branch_id    BIGINT NOT NULL REFERENCES pggit.branches(id),
    lca_commit_id       BIGINT NOT NULL REFERENCES pggit.commits(id),
    source_commit_id    BIGINT NOT NULL REFERENCES pggit.commits(id),
    target_commit_id    BIGINT NOT NULL REFERENCES pggit.commits(id),
    status              pggit.merge_status NOT NULL DEFAULT 'pending',
    result_commit_id    BIGINT REFERENCES pggit.commits(id),  -- set on completion
    started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at        TIMESTAMPTZ,

    CONSTRAINT merge_history_distinct_branches
        CHECK (source_branch_id <> target_branch_id)
);

COMMENT ON TABLE pggit.merge_history IS
    'One row per merge attempt. Tracks the three-way merge: LCA, source tip, '
    'target tip. result_commit_id set when merge completes successfully.';

COMMENT ON COLUMN pggit.merge_history.tenant_id IS
    'Tenant UUID for multi-tenant isolation. NULL = shared/admin mode.';

-- Table 6: merge_conflicts — per-object merge outcomes
CREATE TABLE pggit.merge_conflicts (
    id              BIGSERIAL PRIMARY KEY,
    tenant_id       UUID,  -- NULL = shared/admin mode (backward compatible)
    merge_id        BIGINT NOT NULL REFERENCES pggit.merge_history(id),
    schema_name     TEXT NOT NULL,
    object_name     TEXT NOT NULL,
    object_type     pggit.object_type NOT NULL,
    lca_hash        TEXT,       -- NULL if object didn't exist at LCA
    source_hash     TEXT,       -- NULL if object deleted on source
    target_hash     TEXT,       -- NULL if object deleted on target
    source_ddl      TEXT,
    target_ddl      TEXT,
    resolution      TEXT,       -- 'ours', 'theirs', 'manual'
    resolved_ddl    TEXT,       -- Final DDL to apply (set on resolution)
    status          pggit.conflict_status NOT NULL DEFAULT 'conflicted',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at     TIMESTAMPTZ,

    CONSTRAINT merge_conflicts_merge_object_unique
        UNIQUE (merge_id, schema_name, object_name, object_type)
);

COMMENT ON TABLE pggit.merge_conflicts IS
    'Per-object merge outcome. auto_merged rows need no user action. '
    'conflicted rows must be resolved before merge can complete. '
    'resolved rows have user-provided DDL ready to apply.';

COMMENT ON COLUMN pggit.merge_conflicts.tenant_id IS
    'Tenant UUID for multi-tenant isolation. NULL = shared/admin mode.';

-- Table 7: tags — lightweight named references to commits
CREATE TABLE pggit.tags (
    id              BIGSERIAL PRIMARY KEY,
    tenant_id       UUID,  -- NULL = shared/admin mode (backward compatible)
    name            TEXT NOT NULL,
    commit_id       BIGINT NOT NULL REFERENCES pggit.commits(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT tags_name_valid
        CHECK (name ~ '^[a-zA-Z0-9._-]+$'),
    CONSTRAINT tags_name_unique
        UNIQUE (name)
);

COMMENT ON TABLE pggit.tags IS
    'Lightweight named references to commits, similar to Git tags. '
    'Tags are global (not branch-specific) and immutable once created.';

COMMENT ON COLUMN pggit.tags.name IS
    'Tag names: alphanumeric, dots, hyphens only. No slashes.';

COMMENT ON COLUMN pggit.tags.tenant_id IS
    'Tenant UUID for multi-tenant isolation. NULL = shared/admin mode.';
