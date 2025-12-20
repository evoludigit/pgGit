-- pgGit API Documentation Generator
-- This script generates comprehensive API documentation from function signatures

\o /tmp/api-reference.md

SELECT format(E'# pgGit API Reference\n\nComplete reference for all pgGit functions.\n\n## Overview\n\npgGit provides %s functions across %s schemas.\n\n',
    (SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = 'pggit'),
    (SELECT COUNT(DISTINCT n.nspname) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname LIKE 'pggit%')
);

-- Generate documentation for each function
SELECT format(
    E'## %s.%s\n\n**Signature**: `%s`\n\n**Description**: %s\n\n**Parameters**:\n%s\n\n**Returns**: `%s`\n\n**Example**:\n```sql\n%s\n```\n\n---\n\n',
    n.nspname,
    p.proname,
    pg_get_functiondef(p.oid),
    COALESCE(d.description, '_No description available_'),
    -- Parameter list
    CASE
        WHEN p.proargnames IS NOT NULL THEN
            (SELECT string_agg(
                format('- `%s` (%s): %s', param_name, param_type, '_No description_'),
                E'\n'
            )
            FROM unnest(p.proargnames, p.proargtypes::regtype[])
            AS t(param_name, param_type))
        ELSE '_No parameters_'
    END,
    pg_get_function_result(p.oid),
    -- Example (placeholder for now)
    format('-- Example usage\nSELECT %s.%s();', n.nspname, p.proname)
)
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
LEFT JOIN pg_description d ON p.oid = d.objoid
WHERE n.nspname = 'pggit'
ORDER BY p.proname;

\o