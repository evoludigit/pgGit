-- pggit v1.0 — Complete uninstall
-- Drops all pggit objects in dependency order.
-- Safe to run on a clean database (IF EXISTS everywhere).

-- Drop event triggers first (they reference functions)
DROP EVENT TRIGGER IF EXISTS pggit_ddl_command_end;
DROP EVENT TRIGGER IF EXISTS pggit_sql_drop;

-- Drop schemas CASCADE (removes all tables, functions, views, types, etc.)
DROP SCHEMA IF EXISTS pggit CASCADE;
DROP SCHEMA IF EXISTS pggit_internal CASCADE;
