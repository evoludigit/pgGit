-- pggit v1.0 — Schema creation
-- Must be the first file executed during install.

CREATE SCHEMA IF NOT EXISTS pggit;
CREATE SCHEMA IF NOT EXISTS pggit_internal;

COMMENT ON SCHEMA pggit IS
    'pgGit public API. Application code may reference only objects in this schema.';

COMMENT ON SCHEMA pggit_internal IS
    'pgGit internal implementation. Subject to change without notice. '
    'Access revoked from PUBLIC.';

REVOKE ALL ON SCHEMA pggit_internal FROM PUBLIC;
