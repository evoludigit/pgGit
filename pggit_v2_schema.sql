-- Basic pggit_v2 schema setup
CREATE TABLE IF NOT EXISTS pggit_v2.objects (
    sha TEXT PRIMARY KEY,
    type TEXT NOT NULL CHECK (type IN ('blob', 'tree', 'commit')),
    size BIGINT DEFAULT 0,
    data BYTEA,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS pggit_v2.refs (
    name TEXT PRIMARY KEY,
    target_sha TEXT NOT NULL REFERENCES pggit_v2.objects(sha),
    type TEXT NOT NULL CHECK (type IN ('branch', 'tag', 'remote')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS pggit_v2.commit_graph (
    commit_sha TEXT PRIMARY KEY REFERENCES pggit_v2.objects(sha),
    tree_sha TEXT NOT NULL REFERENCES pggit_v2.objects(sha),
    author TEXT,
    message TEXT,
    committed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS pggit_v2.tree_entries (
    tree_sha TEXT REFERENCES pggit_v2.objects(sha),
    name TEXT,
    object_sha TEXT REFERENCES pggit_v2.objects(sha),
    type TEXT CHECK (type IN ('blob', 'tree')),
    PRIMARY KEY (tree_sha, name)
);

CREATE TABLE IF NOT EXISTS pggit_v2.commit_parents (
    commit_sha TEXT REFERENCES pggit_v2.commit_graph(commit_sha),
    parent_sha TEXT REFERENCES pggit_v2.commit_graph(commit_sha),
    PRIMARY KEY (commit_sha, parent_sha)
);

CREATE TABLE IF NOT EXISTS pggit_v2.head (
    ref_name TEXT REFERENCES pggit_v2.refs(name),
    PRIMARY KEY (ref_name)
);

CREATE TABLE IF NOT EXISTS pggit_v2.merge_base_cache (
    commit1_sha TEXT,
    commit2_sha TEXT,
    merge_base_sha TEXT,
    PRIMARY KEY (commit1_sha, commit2_sha)
);

CREATE TABLE IF NOT EXISTS pggit_v2.performance_metrics (
    operation TEXT,
    duration_ms BIGINT,
    measured_at TIMESTAMPTZ DEFAULT NOW()
);