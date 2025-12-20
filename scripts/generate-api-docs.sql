-- pgGit API Documentation Generator
-- This script generates comprehensive API documentation from function signatures

\o /tmp/api-reference.md

SELECT E'# pgGit API Reference

Complete reference for all pgGit functions.

## Overview

pgGit provides comprehensive SQL API for database version control. All functions are available in the `pggit` schema.

### Function Categories

- **Core Functions**: Basic versioning and tracking
- **Branching Functions**: Git-like branch operations (planned)
- **Migration Functions**: Schema change management
- **Utility Functions**: Helper and maintenance functions

### Function Count
';

-- Add function count
SELECT format(E'- Total Functions: %s\n- Core Functions: %s\n- Extension Functions: %s\n\n---\n\n',
    (SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = 'pggit'),
    (SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = 'pggit' AND p.proname NOT LIKE 'analyze_%' AND p.proname NOT LIKE 'run_%'),
    (SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = 'pggit' AND (p.proname LIKE 'analyze_%' OR p.proname LIKE 'run_%'))
);

-- Generate documentation for each function
SELECT format(
    E'## %s.%s\n\n**Purpose**: %s\n\n**Signature**:\n```sql\n%s\n```\n\n**Parameters**:\n%s\n\n**Returns**: `%s`\n\n**Example**:\n```sql\n%s\n```\n\n---\n\n',
    n.nspname,
    p.proname,
    COALESCE(d.description, 'Database version control operation'),
    regexp_replace(pg_get_functiondef(p.oid), E'\\s+', ' ', 'g'),
    -- Parameter list
    CASE
        WHEN p.proargnames IS NOT NULL THEN
            (SELECT string_agg(
                format('- `%s`: %s', param_name, param_type),
                E'\n'
            )
            FROM unnest(p.proargnames, p.proargtypes::regtype[])
            AS t(param_name, param_type))
        ELSE 'No parameters required'
    END,
    pg_get_function_result(p.oid),
    -- Example based on function type
    CASE
        WHEN p.proname = 'get_version' THEN 'SELECT * FROM pggit.get_version(''users'');'
        WHEN p.proname = 'get_history' THEN 'SELECT * FROM pggit.get_history(''users'');'
        WHEN p.proname = 'generate_migration' THEN E'SELECT pggit.generate_migration(\n    ''Migration description'',\n    ''schema_name''\n);'
        ELSE format('SELECT %s.%s();', n.nspname, p.proname)
    END
)
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
LEFT JOIN pg_description d ON p.oid = d.objoid
WHERE n.nspname = 'pggit'
ORDER BY p.proname;

\o