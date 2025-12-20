-- File: templates/extension-template/sql/001_schema.sql
-- Example extension schema
CREATE SCHEMA IF NOT EXISTS pggit_example;

CREATE TABLE pggit_example.metadata (
    key TEXT PRIMARY KEY,
    value JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE pggit_example.metadata IS 'Extension metadata storage';