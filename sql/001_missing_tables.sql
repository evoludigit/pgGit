-- pgGit Missing Tables - Schema Snapshots and Migration Plans
-- These tables are referenced throughout the codebase but were never explicitly created
-- Adding them here to fix installation errors

-- ============================================================================
-- TABLE: schema_snapshots
-- ============================================================================
-- Stores point-in-time schema snapshots for branches
CREATE TABLE IF NOT EXISTS pggit.schema_snapshots (
    id bigserial PRIMARY KEY,
    branch_id integer NOT NULL,
    branch_name text NOT NULL,
    schema_json jsonb NOT NULL,
    object_count integer DEFAULT 0,
    snapshot_date timestamp NOT NULL DEFAULT NOW(),
    UNIQUE(branch_id, snapshot_date)
);

COMMENT ON TABLE pggit.schema_snapshots IS
'Stores point-in-time snapshots of database schemas for branches';

COMMENT ON COLUMN pggit.schema_snapshots.branch_id IS 'Reference to the branch';
COMMENT ON COLUMN pggit.schema_snapshots.branch_name IS 'Name of the branch';
COMMENT ON COLUMN pggit.schema_snapshots.schema_json IS 'Complete schema definition as JSON';
COMMENT ON COLUMN pggit.schema_snapshots.object_count IS 'Number of objects in the schema';
COMMENT ON COLUMN pggit.schema_snapshots.snapshot_date IS 'Timestamp of when snapshot was taken';

-- ============================================================================
-- TABLE: migration_plans
-- ============================================================================
-- Stores migration plans between branches
CREATE TABLE IF NOT EXISTS pggit.migration_plans (
    id bigserial PRIMARY KEY,
    source_branch text NOT NULL,
    target_branch text NOT NULL,
    plan_json jsonb NOT NULL,
    feasibility text DEFAULT 'UNKNOWN', -- 'HIGH', 'MEDIUM', 'LOW', 'UNKNOWN'
    estimated_duration_seconds integer,
    created_at timestamp NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE pggit.migration_plans IS
'Stores migration plans for moving data between branches';

COMMENT ON COLUMN pggit.migration_plans.source_branch IS 'Source branch name';
COMMENT ON COLUMN pggit.migration_plans.target_branch IS 'Target branch name';
COMMENT ON COLUMN pggit.migration_plans.plan_json IS 'Detailed migration plan as JSON';
COMMENT ON COLUMN pggit.migration_plans.feasibility IS 'Assessment of migration feasibility';
COMMENT ON COLUMN pggit.migration_plans.estimated_duration_seconds IS 'Estimated time to complete migration';
COMMENT ON COLUMN pggit.migration_plans.created_at IS 'Timestamp when plan was created';
