-- Unit Test Suite for pgGit Utility Functions
-- Test File: 005_test_utility_functions.sql
-- Coverage: Helper functions, validation, formatting

BEGIN;

-- Plan: 35 tests for utility functions
SELECT plan(35);

-- ============================================================================
-- TEST GROUP 1: Validation Functions (Tests 1-10)
-- ============================================================================

-- Test 1: is_valid_branch_name should accept valid names
SELECT is(
    pggit.is_valid_branch_name('feature_branch'),
    true,
    'Valid branch name should be accepted'
);

-- Test 2: is_valid_branch_name should reject empty string
SELECT is(
    pggit.is_valid_branch_name(''),
    false,
    'Empty branch name should be rejected'
);

-- Test 3: is_valid_branch_name should reject NULL
SELECT is(
    pggit.is_valid_branch_name(NULL),
    false,
    'NULL branch name should be rejected'
);

-- Test 4: is_valid_branch_name should reject names > 255 chars
SELECT is(
    pggit.is_valid_branch_name(repeat('a', 256)),
    false,
    'Branch names >255 chars should be rejected'
);

-- Test 5: is_valid_branch_name should accept alphanumeric with hyphens
SELECT is(
    pggit.is_valid_branch_name('feature-v1-2-3'),
    true,
    'Branch names with hyphens should be accepted'
);

-- Test 6: is_valid_branch_name should accept underscores
SELECT is(
    pggit.is_valid_branch_name('feature_v1_test'),
    true,
    'Branch names with underscores should be accepted'
);

-- Test 7: is_valid_branch_name should accept unicode
SELECT is(
    pggit.is_valid_branch_name('日本語_branch'),
    true,
    'Unicode branch names should be accepted'
);

-- Test 8: is_valid_object_name should validate object names
SELECT is(
    pggit.is_valid_object_name('valid_table_name'),
    true,
    'Valid object name should be accepted'
);

-- Test 9: is_valid_object_name should reject reserved words
SELECT is(
    pggit.is_valid_object_name('select'),
    false,
    'Reserved SQL words should be rejected as object names'
);

-- Test 10: is_valid_schema_name should validate schema names
SELECT is(
    pggit.is_valid_schema_name('valid_schema'),
    true,
    'Valid schema name should be accepted'
);

-- ============================================================================
-- TEST GROUP 2: String and Formatting Functions (Tests 11-18)
-- ============================================================================

-- Test 11: normalize_identifier should handle case
SELECT is(
    pggit.normalize_identifier('TestTable'),
    'testtable',
    'normalize_identifier should lowercase'
);

-- Test 12: normalize_identifier should handle quotes
SELECT is(
    pggit.normalize_identifier('"Test Table"'),
    'test table',
    'normalize_identifier should remove quotes'
);

-- Test 13: sanitize_branch_name should clean input
SELECT is(
    pggit.sanitize_branch_name(' branch with spaces '),
    'branch_with_spaces',
    'sanitize_branch_name should trim and replace spaces'
);

-- Test 14: sanitize_branch_name should handle special chars
SELECT is(
    pggit.sanitize_branch_name('branch@#$%name'),
    'branch_name',
    'sanitize_branch_name should remove special chars'
);

-- Test 15: generate_slug should create URL-friendly string
SELECT is(
    pggit.generate_slug('Feature Branch Name'),
    'feature-branch-name',
    'generate_slug should create URL-friendly slug'
);

-- Test 16: generate_slug should handle multiple spaces
SELECT is(
    pggit.generate_slug('Feature   Multiple   Spaces'),
    'feature-multiple-spaces',
    'generate_slug should collapse multiple spaces'
);

-- Test 17: format_object_name should create full name
SELECT is(
    pggit.format_object_name('public', 'users'),
    'public.users',
    'format_object_name should combine schema and name'
);

-- Test 18: format_object_name should handle empty schema
SELECT is(
    pggit.format_object_name('', 'users'),
    'users',
    'format_object_name should handle empty schema'
);

-- ============================================================================
-- TEST GROUP 3: Hash and Comparison Functions (Tests 19-25)
-- ============================================================================

-- Test 19: compute_content_hash should return consistent hash
SELECT is(
    pggit.compute_content_hash('test content'),
    pggit.compute_content_hash('test content'),
    'compute_content_hash should return consistent hash for same content'
);

-- Test 20: compute_content_hash should return different hash for different content
SELECT isnt(
    pggit.compute_content_hash('content a'),
    pggit.compute_content_hash('content b'),
    'compute_content_hash should return different hash for different content'
);

-- Test 21: compute_content_hash should handle empty string
SELECT cmp_ok(
    length(pggit.compute_content_hash('')),
    '>',
    0::INTEGER,
    'compute_content_hash should handle empty string'
);

-- Test 22: compute_content_hash should handle NULL
SELECT is(
    pggit.compute_content_hash(NULL),
    NULL,
    'compute_content_hash should return NULL for NULL input'
);

-- Test 23: compare_content_hashes should identify matches
SELECT is(
    pggit.compare_content_hashes(
        pggit.compute_content_hash('same'),
        pggit.compute_content_hash('same')
    ),
    true,
    'compare_content_hashes should identify matching content'
);

-- Test 24: compare_content_hashes should identify differences
SELECT is(
    pggit.compare_content_hashes(
        pggit.compute_content_hash('content1'),
        pggit.compute_content_hash('content2')
    ),
    false,
    'compare_content_hashes should identify different content'
);

-- Test 25: generate_version_hash should create unique hashes
SELECT isnt(
    pggit.generate_version_hash('branch1', 1),
    pggit.generate_version_hash('branch2', 1),
    'generate_version_hash should create different hashes for different branches'
);

-- ============================================================================
-- TEST GROUP 4: Date and Time Functions (Tests 26-30)
-- ============================================================================

-- Test 26: format_timestamp should format ISO 8601
SELECT like(
    pggit.format_timestamp(CURRENT_TIMESTAMP),
    '%-%-%T%:%:%',
    'format_timestamp should format as ISO 8601'
);

-- Test 27: parse_timestamp should parse ISO 8601
SELECT lives_ok(
    $$ SELECT pggit.parse_timestamp('2026-02-25T10:30:00Z') $$,
    'parse_timestamp should parse ISO 8601'
);

-- Test 28: get_timestamp_age should return interval
SELECT cmp_ok(
    pggit.get_timestamp_age(CURRENT_TIMESTAMP - INTERVAL '1 hour'),
    '>=',
    INTERVAL '1 hour',
    'get_timestamp_age should return correct interval'
);

-- Test 29: is_timestamp_recent should identify recent timestamps
SELECT is(
    pggit.is_timestamp_recent(CURRENT_TIMESTAMP - INTERVAL '1 minute', INTERVAL '5 minutes'),
    true,
    'is_timestamp_recent should identify recent timestamps'
);

-- Test 30: is_timestamp_recent should reject old timestamps
SELECT is(
    pggit.is_timestamp_recent(CURRENT_TIMESTAMP - INTERVAL '10 minutes', INTERVAL '5 minutes'),
    false,
    'is_timestamp_recent should reject old timestamps'
);

-- ============================================================================
-- TEST GROUP 5: JSON and Metadata Functions (Tests 31-35)
-- ============================================================================

-- Test 31: merge_metadata should combine JSON objects
SELECT results_eq(
    $$ SELECT pggit.merge_metadata('{"a": 1}'::jsonb, '{"b": 2}'::jsonb) $$,
    $$ VALUES ('{"a": 1, "b": 2}'::jsonb) $$,
    'merge_metadata should combine JSON objects'
);

-- Test 32: merge_metadata should handle nested objects
SELECT results_eq(
    $$ SELECT pggit.merge_metadata('{"a": {"b": 1}}'::jsonb, '{"a": {"c": 2}}'::jsonb) $$,
    $$ VALUES ('{"a": {"b": 1, "c": 2}}'::jsonb) $$,
    'merge_metadata should merge nested objects'
);

-- Test 33: extract_metadata_value should get values
SELECT is(
    pggit.extract_metadata_value('{"key": "value"}'::jsonb, 'key'),
    'value',
    'extract_metadata_value should extract values'
);

-- Test 34: extract_metadata_value should handle missing keys
SELECT is(
    pggit.extract_metadata_value('{"key": "value"}'::jsonb, 'missing'),
    NULL,
    'extract_metadata_value should return NULL for missing keys'
);

-- Test 35: validate_metadata_schema should validate against schema
SELECT is(
    pggit.validate_metadata_schema('{"name": "test", "version": 1}'::jsonb, '{"required": ["name", "version"]}'::jsonb),
    true,
    'validate_metadata_schema should validate required fields'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

SELECT * FROM finish();

ROLLBACK;
