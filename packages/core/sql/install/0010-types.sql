-- pggit v1.0 — Enum type definitions

-- Branch lifecycle state
CREATE TYPE pggit.branch_status AS ENUM (
    'active',
    'merged',
    'deleted'
);

-- Object types tracked by the event trigger
CREATE TYPE pggit.object_type AS ENUM (
    'table',
    'view',
    'materialized_view',
    'function',
    'procedure',
    'trigger',
    'index',
    'sequence',
    'type',
    'domain'
);

-- Merge state machine
CREATE TYPE pggit.merge_status AS ENUM (
    'pending',      -- LCA found, classification in progress
    'in_progress',  -- Classification done, conflicts remain
    'completed',    -- All conflicts resolved, DDL applied
    'aborted'       -- User cancelled
);

-- Per-object merge outcome
CREATE TYPE pggit.conflict_status AS ENUM (
    'auto_merged',  -- No user action needed
    'conflicted',   -- Requires user resolution
    'resolved'      -- User provided resolution, not yet applied
);
