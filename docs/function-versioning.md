# pgGit Function Versioning

pgGit's enhanced function versioning provides comprehensive tracking for PostgreSQL functions, including full support for overloading, signature-based tracking, and metadata management.

## Table of Contents

- [Overview](#overview)
- [Basic Function Tracking](#basic-function-tracking)
- [Function Overloading](#function-overloading)
- [Metadata and Comments](#metadata-and-comments)
- [Version Management](#version-management)
- [Function History](#function-history)
- [Best Practices](#best-practices)

## Overview

PostgreSQL functions can be overloaded (multiple functions with the same name but different parameters). pgGit's function versioning:

- Tracks each function signature separately
- Maintains version history for function changes
- Extracts metadata from function comments
- Supports semantic versioning
- Detects when functions haven't actually changed

## Basic Function Tracking

### Track a Simple Function

```sql
-- Create a function
CREATE OR REPLACE FUNCTION calculate_tax(amount decimal, rate decimal)
RETURNS decimal AS $$
    SELECT amount * rate;
$$ LANGUAGE sql;

-- Track it
SELECT pggit.track_function('calculate_tax(decimal, decimal)');
```

### Automatic Version Assignment

If you don't specify a version, pgGit assigns one automatically:

```sql
-- First version gets 1.0.0
SELECT pggit.track_function('my_function(text)');

-- Updates increment patch version (1.0.1, 1.0.2, etc.)
CREATE OR REPLACE FUNCTION my_function(input text) 
RETURNS text AS $$ 
    SELECT upper(input); -- Changed implementation
$$ LANGUAGE sql;

SELECT pggit.track_function('my_function(text)');
```

## Function Overloading

### Track Overloaded Functions

```sql
-- Create overloaded functions
CREATE FUNCTION process_data(value integer)
RETURNS integer AS $$ SELECT value * 2 $$ LANGUAGE sql;

CREATE FUNCTION process_data(value integer, multiplier integer)
RETURNS integer AS $$ SELECT value * multiplier $$ LANGUAGE sql;

CREATE FUNCTION process_data(value text)
RETURNS text AS $$ SELECT upper(value) $$ LANGUAGE sql;

-- Track each overload separately
SELECT pggit.track_function('process_data(integer)');
SELECT pggit.track_function('process_data(integer, integer)');
SELECT pggit.track_function('process_data(text)');
```

### List Function Overloads

```sql
-- See all overloads of a function
SELECT * FROM pggit.list_function_overloads('public', 'process_data');
```

Example output:
```
signature                      | argument_types      | return_type | current_version | last_modified
-------------------------------|---------------------|-------------|-----------------|---------------
public.process_data(integer)   | {integer}          | integer     | 1.0.0          | 2024-01-20
public.process_data(integer, integer) | {integer,integer} | integer | 1.0.0     | 2024-01-20
public.process_data(text)      | {text}             | text        | 1.0.0          | 2024-01-20
```

## Metadata and Comments

### Add Metadata via Comments

```sql
CREATE OR REPLACE FUNCTION api.authenticate_user(
    username text,
    password text
) RETURNS TABLE (user_id int, token text, expires_at timestamptz) AS $$
BEGIN
    -- Authentication logic here
    RETURN QUERY SELECT 1, 'token123', now() + interval '1 hour';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION api.authenticate_user(text, text) IS 
'Authenticate user and return session token
@pggit-version: 2.1.0
@pggit-author: Security Team
@pggit-tags: authentication, api, security
@pggit-breaking: Changed return type in v2.0.0';
```

### Extract and Use Metadata

```sql
-- Track function with metadata extraction
SELECT pggit.track_function('api.authenticate_user(text, text)');

-- View function metadata
SELECT 
    version,
    metadata->>'author' as author,
    metadata->'tags' as tags
FROM pggit.function_versions fv
JOIN pggit.function_signatures fs ON fs.signature_id = fv.signature_id
WHERE fs.function_name = 'authenticate_user';
```

### Ignore Functions

```sql
-- Mark internal functions to be ignored
CREATE FUNCTION internal_helper() RETURNS void AS $$ BEGIN END $$ LANGUAGE plpgsql;

COMMENT ON FUNCTION internal_helper() IS 
'Internal use only @pggit-ignore';
```

## Version Management

### Explicit Version Control

```sql
-- Specify version explicitly
SELECT pggit.track_function(
    function_signature => 'calculate_discount(decimal, decimal)',
    version => '1.2.0',
    metadata => jsonb_build_object(
        'author', 'Pricing Team',
        'reviewed_by', 'Finance Team',
        'jira_ticket', 'PRICE-123'
    )
);
```

### Get Current Version

```sql
-- Check current version of a function
SELECT * FROM pggit.get_function_version('calculate_discount(decimal, decimal)');
```

### Version History

```sql
-- View complete version history
SELECT 
    version,
    created_at,
    created_by,
    metadata
FROM pggit.function_history
WHERE schema_name = 'public' 
  AND function_name = 'calculate_discount'
ORDER BY created_at DESC;
```

## Function History

### View Function Changes

```sql
-- See all functions changed recently
SELECT * FROM pggit.function_history
WHERE created_at > now() - interval '7 days'
ORDER BY created_at DESC;
```

### Compare Function Versions

```sql
-- Compare two versions of a function
SELECT * FROM pggit.diff_function_versions(
    'calculate_tax(decimal, decimal)',
    '1.0.0',  -- old version
    '1.1.0'   -- new version
);
```

### Track Function Deployments

```sql
-- Link function changes to deployments
SELECT 
    fh.function_name,
    fh.version,
    c.message as deployment,
    fh.created_at
FROM pggit.function_history fh
JOIN pggit.commits c ON c.commit_id = fh.commit_id
WHERE c.message LIKE '%deployment%'
ORDER BY fh.created_at DESC;
```

## Best Practices

### 1. Use Semantic Versioning

```sql
-- Major version: Breaking changes
COMMENT ON FUNCTION api.get_user(int) IS 
'Get user details
@pggit-version: 2.0.0
@pggit-breaking: Return type changed from record to jsonb';

-- Minor version: New features
COMMENT ON FUNCTION api.get_user(int) IS 
'Get user details
@pggit-version: 1.1.0
@pggit-feature: Added last_login to response';

-- Patch version: Bug fixes
COMMENT ON FUNCTION api.get_user(int) IS 
'Get user details
@pggit-version: 1.0.1
@pggit-fix: Fixed null handling for deleted users';
```

### 2. Document Complex Functions

```sql
CREATE OR REPLACE FUNCTION analytics.calculate_cohort_retention(
    cohort_date date,
    period_type text DEFAULT 'month'
) RETURNS TABLE (
    period int,
    users_retained int,
    retention_rate decimal
) AS $$
    -- Complex implementation
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION analytics.calculate_cohort_retention(date, text) IS 
'Calculate user retention rates for a given cohort
@pggit-version: 3.2.1
@pggit-author: Analytics Team
@pggit-tags: analytics, retention, cohort
@pggit-performance: Optimized in v3.2.0 for large datasets
@pggit-dependencies: Requires user_events table
@pggit-example: SELECT * FROM calculate_cohort_retention(''2024-01-01'', ''week'')';
```

### 3. Handle Deprecated Functions

```sql
-- Mark function as deprecated
CREATE OR REPLACE FUNCTION old_api_endpoint(data text)
RETURNS text AS $$
BEGIN
    RAISE WARNING 'Function old_api_endpoint is deprecated, use new_api_endpoint instead';
    RETURN new_api_endpoint(data::jsonb);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION old_api_endpoint(text) IS 
'DEPRECATED: Use new_api_endpoint instead
@pggit-version: 1.9.9
@pggit-deprecated: true
@pggit-removal-date: 2024-12-31
@pggit-alternative: new_api_endpoint(jsonb)';
```

### 4. Track Function Groups

```sql
-- Track related functions together
DO $$
BEGIN
    -- Start deployment for function group
    PERFORM pggit.begin_deployment('User API Functions v2.0');
    
    -- Update all user-related functions
    CREATE OR REPLACE FUNCTION api.create_user(data jsonb) RETURNS jsonb AS $$ ... $$;
    CREATE OR REPLACE FUNCTION api.update_user(id int, data jsonb) RETURNS jsonb AS $$ ... $$;
    CREATE OR REPLACE FUNCTION api.delete_user(id int) RETURNS boolean AS $$ ... $$;
    
    -- Track them
    PERFORM pggit.track_function('api.create_user(jsonb)', '2.0.0');
    PERFORM pggit.track_function('api.update_user(integer, jsonb)', '2.0.0');
    PERFORM pggit.track_function('api.delete_user(integer)', '2.0.0');
    
    PERFORM pggit.end_deployment('Updated all user API functions to v2.0');
END $$;
```

### 5. Monitor Function Performance

```sql
-- Track performance-critical functions
CREATE OR REPLACE FUNCTION report.generate_monthly_summary(month date)
RETURNS TABLE (...) AS $$
    -- Complex report logic
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION report.generate_monthly_summary(date) IS 
'Generate monthly summary report
@pggit-version: 1.3.2
@pggit-performance-baseline: 2.5s for 100k records
@pggit-optimization: Added parallel processing in v1.3.0
@pggit-sla: Must complete within 5 seconds';

-- Track performance changes
SELECT pggit.track_function(
    'report.generate_monthly_summary(date)',
    '1.3.2',
    jsonb_build_object(
        'performance_test', '2.1s for 100k records',
        'optimization', 'Improved query plan'
    )
);
```

## Function Versioning Reference

### Tables

| Table | Description |
|-------|-------------|
| `pggit.function_signatures` | Unique function signatures |
| `pggit.function_versions` | Version history for each signature |

### Functions

| Function | Description |
|----------|-------------|
| `pggit.track_function()` | Track a function version |
| `pggit.get_function_version()` | Get current version info |
| `pggit.list_function_overloads()` | List all overloads of a function |
| `pggit.diff_function_versions()` | Compare function versions |
| `pggit.extract_function_metadata()` | Extract metadata from comments |
| `pggit.next_function_version()` | Calculate next semantic version |

### Views

| View | Description |
|------|-------------|
| `pggit.function_history` | Complete function change history |

### Comment Directives

| Directive | Description |
|-----------|-------------|
| `@pggit-version:` | Specify function version |
| `@pggit-author:` | Function author/team |
| `@pggit-tags:` | Comma-separated tags |
| `@pggit-ignore` | Don't track this function |
| `@pggit-deprecated:` | Mark as deprecated |
| `@pggit-breaking:` | Note breaking changes |