-- pggit v1.0 — Bootstrap
-- Creates the initial 'main' branch and sets default GUC values.
-- Safe to run multiple times (idempotent).

-- Insert main branch if it does not already exist
INSERT INTO pggit.branches (name, parent_id, status)
VALUES ('main', NULL, 'active')
ON CONFLICT (name) DO NOTHING;

-- Set default session GUC values
SELECT set_config('pggit.current_branch', 'main', FALSE);
SELECT set_config('pggit.tracking_paused', 'false', FALSE);
