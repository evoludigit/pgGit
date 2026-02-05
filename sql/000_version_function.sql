-- pgGit Version Function
-- Provides version information for the extension

CREATE OR REPLACE FUNCTION pggit.version()
RETURNS TEXT AS $$
BEGIN
    RETURN '0.1.3';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION pggit.version() IS
'Returns the pgGit extension version';
