-- File: templates/extension-template/sql/002_functions.sql
-- Example extension functions
CREATE OR REPLACE FUNCTION pggit_example.get_metadata(key_param TEXT)
RETURNS JSONB AS $$
    SELECT value FROM pggit_example.metadata WHERE key = key_param;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pggit_example.set_metadata(key_param TEXT, value_param JSONB)
RETURNS VOID AS $$
    INSERT INTO pggit_example.metadata (key, value)
    VALUES (key_param, value_param)
    ON CONFLICT (key) DO UPDATE SET
        value = EXCLUDED.value,
        created_at = CURRENT_TIMESTAMP;
$$ LANGUAGE sql;

COMMENT ON FUNCTION pggit_example.get_metadata(TEXT) IS 'Get extension metadata by key';
COMMENT ON FUNCTION pggit_example.set_metadata(TEXT, JSONB) IS 'Set extension metadata';