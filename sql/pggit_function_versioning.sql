-- pgGit Enhanced Function Versioning
-- Support for function overloading and signature tracking

-- Table to track function signatures separately from function names
CREATE TABLE IF NOT EXISTS pggit.function_signatures (
    signature_id serial PRIMARY KEY,
    schema_name text NOT NULL,
    function_name text NOT NULL,
    argument_types text[], -- Array of argument type names
    return_type text,
    signature_hash text,
    is_overloaded boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    UNIQUE(signature_hash)
);

-- Function to compute signature hash
CREATE OR REPLACE FUNCTION pggit.compute_signature_hash() RETURNS trigger AS $$
BEGIN
    NEW.signature_hash := md5(NEW.schema_name || '.' || NEW.function_name || '(' || 
            COALESCE(array_to_string(NEW.argument_types, ','), '') || ')');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to compute hash on insert/update
CREATE TRIGGER compute_signature_hash_trigger
BEFORE INSERT OR UPDATE ON pggit.function_signatures
FOR EACH ROW EXECUTE FUNCTION pggit.compute_signature_hash();

-- Enhanced function tracking with version metadata
CREATE TABLE IF NOT EXISTS pggit.function_versions (
    version_id serial PRIMARY KEY,
    signature_id integer REFERENCES pggit.function_signatures(signature_id),
    version text,
    source_hash text NOT NULL, -- Hash of function body
    metadata jsonb, -- Extracted from comments
    created_at timestamptz DEFAULT now(),
    created_by text DEFAULT current_user,
    commit_id uuid -- Foreign key removed: pggit.commits may not have commit_id column
);

-- Function to parse function signature
CREATE OR REPLACE FUNCTION pggit.parse_function_signature(
    function_oid oid
) RETURNS TABLE (
    schema_name text,
    function_name text,
    argument_types text[],
    return_type text,
    full_signature text
) AS $$
DECLARE
    arg_types text[];
    arg_names text[];
    arg_modes text[];
    ret_type text;
    i integer;
BEGIN
    -- Get function details
    SELECT 
        n.nspname,
        p.proname,
        p.proargtypes::oid[],
        p.proargnames,
        p.proargmodes,
        pg_get_function_result(p.oid)
    INTO
        schema_name,
        function_name,
        arg_types,
        arg_names,
        arg_modes,
        ret_type
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE p.oid = function_oid;
    
    -- Convert argument OIDs to type names
    SELECT array_agg(format_type(unnest::oid, NULL))
    INTO argument_types
    FROM unnest(arg_types::oid[]);
    
    -- Set return type
    return_type := ret_type;
    
    -- Build full signature
    full_signature := format('%s.%s(%s)',
        schema_name,
        function_name,
        COALESCE(array_to_string(argument_types, ', '), '')
    );
    
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

-- Function to track a specific function version
CREATE OR REPLACE FUNCTION pggit.track_function(
    function_signature text,
    version text DEFAULT NULL,
    metadata jsonb DEFAULT NULL
) RETURNS void AS $$
DECLARE
    func_oid oid;
    sig_record record;
    source_text text;
    source_hash text;
    sig_id integer;
    existing_version record;
    extracted_metadata jsonb;
BEGIN
    -- Parse the function signature to get OID
    BEGIN
        func_oid := function_signature::regprocedure;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Invalid function signature: %', function_signature;
    END;
    
    -- Get parsed signature components
    SELECT * INTO sig_record 
    FROM pggit.parse_function_signature(func_oid);
    
    -- Get function source
    SELECT pg_get_functiondef(func_oid) INTO source_text;
    source_hash := md5(source_text);
    
    -- Extract metadata from function comments if not provided
    IF metadata IS NULL THEN
        extracted_metadata := pggit.extract_function_metadata(func_oid);
        IF extracted_metadata IS NOT NULL THEN
            metadata := extracted_metadata;
        END IF;
    END IF;
    
    -- Extract version from metadata if not provided
    IF version IS NULL AND metadata ? 'version' THEN
        version := metadata->>'version';
    END IF;
    
    -- Insert or get function signature
    INSERT INTO pggit.function_signatures (
        schema_name,
        function_name,
        argument_types,
        return_type
    ) VALUES (
        sig_record.schema_name,
        sig_record.function_name,
        sig_record.argument_types,
        sig_record.return_type
    )
    ON CONFLICT (signature_hash) DO UPDATE
    SET is_overloaded = true
    RETURNING signature_id INTO sig_id;
    
    -- Check if this exact version already exists
    SELECT * INTO existing_version
    FROM pggit.function_versions fv
    WHERE fv.signature_id = sig_id
      AND fv.source_hash = source_hash;
    
    IF existing_version IS NULL THEN
        -- Insert new version
        INSERT INTO pggit.function_versions (
            signature_id,
            version,
            source_hash,
            metadata
        ) VALUES (
            sig_id,
            COALESCE(version, pggit.next_function_version(sig_id)),
            source_hash,
            metadata
        );
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to extract metadata from function comments
CREATE OR REPLACE FUNCTION pggit.extract_function_metadata(
    function_oid oid
) RETURNS jsonb AS $$
DECLARE
    func_comment text;
    metadata jsonb := '{}'::jsonb;
    version_match text;
    author_match text;
    tags_match text;
BEGIN
    -- Get function comment
    SELECT obj_description(function_oid, 'pg_proc') INTO func_comment;
    
    IF func_comment IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Extract @pggit-version
    version_match := substring(func_comment from '@pggit-version:\s*([^\s]+)');
    IF version_match IS NOT NULL THEN
        metadata := metadata || jsonb_build_object('version', version_match);
    END IF;
    
    -- Extract @pggit-author
    author_match := substring(func_comment from '@pggit-author:\s*([^\n]+)');
    IF author_match IS NOT NULL THEN
        metadata := metadata || jsonb_build_object('author', trim(author_match));
    END IF;
    
    -- Extract @pggit-tags
    tags_match := substring(func_comment from '@pggit-tags:\s*([^\n]+)');
    IF tags_match IS NOT NULL THEN
        metadata := metadata || jsonb_build_object('tags', 
            string_to_array(trim(tags_match), ',')
        );
    END IF;
    
    -- Check for @pggit-ignore directive
    IF func_comment ~ '@pggit-ignore' THEN
        metadata := metadata || jsonb_build_object('ignore', true);
    END IF;
    
    RETURN CASE WHEN metadata = '{}'::jsonb THEN NULL ELSE metadata END;
END;
$$ LANGUAGE plpgsql;

-- Function to get next version number for a function
CREATE OR REPLACE FUNCTION pggit.next_function_version(
    sig_id integer
) RETURNS text AS $$
DECLARE
    last_version text;
    major integer;
    minor integer;
    patch integer;
BEGIN
    -- Get the last version
    SELECT version INTO last_version
    FROM pggit.function_versions
    WHERE signature_id = sig_id
    ORDER BY created_at DESC
    LIMIT 1;
    
    IF last_version IS NULL THEN
        RETURN '1.0.0';
    END IF;
    
    -- Parse semantic version
    IF last_version ~ '^\d+\.\d+\.\d+$' THEN
        SELECT 
            split_part(last_version, '.', 1)::integer,
            split_part(last_version, '.', 2)::integer,
            split_part(last_version, '.', 3)::integer
        INTO major, minor, patch;
        
        -- Increment patch version
        RETURN format('%s.%s.%s', major, minor, patch + 1);
    ELSE
        -- Non-semantic version, just append .1
        RETURN last_version || '.1';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to get function version
CREATE OR REPLACE FUNCTION pggit.get_function_version(
    function_signature text
) RETURNS TABLE (
    version text,
    created_at timestamptz,
    created_by text,
    metadata jsonb
) AS $$
DECLARE
    func_oid oid;
    sig_record record;
    source_hash text;
BEGIN
    -- Parse the function signature
    BEGIN
        func_oid := function_signature::regprocedure;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Invalid function signature: %', function_signature;
    END;
    
    -- Get current source hash
    SELECT md5(pg_get_functiondef(func_oid)) INTO source_hash;
    
    -- Get version info
    RETURN QUERY
    SELECT 
        fv.version,
        fv.created_at,
        fv.created_by,
        fv.metadata
    FROM pggit.function_versions fv
    JOIN pggit.function_signatures fs ON fs.signature_id = fv.signature_id
    WHERE fs.signature_hash = md5(function_signature)
      AND fv.source_hash = source_hash
    ORDER BY fv.created_at DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Function to list all overloaded versions of a function
CREATE OR REPLACE FUNCTION pggit.list_function_overloads(
    schema_name text,
    function_name text
) RETURNS TABLE (
    signature text,
    argument_types text[],
    return_type text,
    current_version text,
    last_modified timestamptz
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        fs.schema_name || '.' || fs.function_name || '(' || 
            COALESCE(array_to_string(fs.argument_types, ', '), '') || ')' as signature,
        fs.argument_types,
        fs.return_type,
        (SELECT fv.version 
         FROM pggit.function_versions fv 
         WHERE fv.signature_id = fs.signature_id 
         ORDER BY fv.created_at DESC 
         LIMIT 1) as current_version,
        (SELECT fv.created_at 
         FROM pggit.function_versions fv 
         WHERE fv.signature_id = fs.signature_id 
         ORDER BY fv.created_at DESC 
         LIMIT 1) as last_modified
    FROM pggit.function_signatures fs
    WHERE fs.schema_name = list_function_overloads.schema_name
      AND fs.function_name = list_function_overloads.function_name
    ORDER BY array_length(fs.argument_types, 1), fs.argument_types::text;
END;
$$ LANGUAGE plpgsql;

-- Function to compare function versions
CREATE OR REPLACE FUNCTION pggit.diff_function_versions(
    function_signature text,
    version1 text DEFAULT NULL,
    version2 text DEFAULT NULL
) RETURNS TABLE (
    line_number integer,
    change_type text,
    version1_line text,
    version2_line text
) AS $$
DECLARE
    func_oid oid;
    source1 text;
    source2 text;
    sig_hash text;
BEGIN
    -- Get signature hash
    sig_hash := md5(function_signature);
    
    -- Get sources for the versions
    IF version1 IS NULL THEN
        -- Get oldest version
        SELECT pg_get_functiondef(function_signature::regprocedure) INTO source1
        FROM pggit.function_versions fv
        JOIN pggit.function_signatures fs ON fs.signature_id = fv.signature_id
        WHERE fs.signature_hash = sig_hash
        ORDER BY fv.created_at ASC
        LIMIT 1;
    ELSE
        -- Get specific version (simplified - would need version storage)
        source1 := '-- Version ' || version1 || ' source would be here';
    END IF;
    
    IF version2 IS NULL THEN
        -- Get current version
        source2 := pg_get_functiondef(function_signature::regprocedure);
    ELSE
        -- Get specific version
        source2 := '-- Version ' || version2 || ' source would be here';
    END IF;
    
    -- Use pgGit's diff algorithm
    RETURN QUERY
    SELECT * FROM pggit.diff_text(source1, source2);
END;
$$ LANGUAGE plpgsql;

-- View to show function version history
CREATE OR REPLACE VIEW pggit.function_history AS
SELECT 
    fs.schema_name,
    fs.function_name,
    fs.schema_name || '.' || fs.function_name || '(' || 
        COALESCE(array_to_string(fs.argument_types, ', '), '') || ')' as full_signature,
    fs.argument_types,
    fs.return_type,
    fs.is_overloaded,
    fv.version,
    fv.created_at,
    fv.created_by,
    fv.metadata,
    c.message as commit_message,
    c.commit_id
FROM pggit.function_signatures fs
JOIN pggit.function_versions fv ON fs.signature_id = fv.signature_id
LEFT JOIN pggit.commits c ON c.commit_id = fv.commit_id
ORDER BY fs.schema_name, fs.function_name, fv.created_at DESC;