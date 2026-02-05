-- Test assertion utilities for explicit failure
CREATE OR REPLACE FUNCTION pggit.assert_function_exists(
    p_function_name TEXT,
    p_schema TEXT DEFAULT 'pggit'
) RETURNS VOID AS $$
DECLARE
    v_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE proname = p_function_name
        AND pronamespace = p_schema::regnamespace
    ) INTO v_exists;

    IF NOT v_exists THEN
        RAISE EXCEPTION 'Required function %.%() does not exist',
            p_schema, p_function_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit.assert_table_exists(
    p_table_name TEXT,
    p_schema TEXT DEFAULT 'pggit'
) RETURNS VOID AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = p_schema
        AND table_name = p_table_name
    ) THEN
        RAISE EXCEPTION 'Required table %.% does not exist',
            p_schema, p_table_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pggit.assert_type_exists(
    p_type_name TEXT,
    p_schema TEXT DEFAULT 'pggit'
) RETURNS VOID AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.schemata s
        JOIN pg_type t ON t.typnamespace = (s.schema_name::regnamespace)::oid
        WHERE s.schema_name = p_schema
        AND t.typname = p_type_name
    ) THEN
        RAISE EXCEPTION 'Required type %.% does not exist',
            p_schema, p_type_name;
    END IF;
END;
$$ LANGUAGE plpgsql;