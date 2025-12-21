-- UAT Testing: Developer Functions
-- Test all 12 developer functions systematically

\echo '=== Testing Developer Functions ==='

-- 1. get_current_schema() - Lists objects at HEAD
\echo '\n1. Testing get_current_schema()...'
SELECT COUNT(*) as objects_at_head FROM pggit_v0.get_current_schema();

-- 2. list_objects(commit_sha) - Lists objects at any commit
\echo '\n2. Testing list_objects()...'
-- Get the latest commit SHA first
SELECT pggit_v0.get_head_sha() as head_sha;

-- 3. create_branch() - Creates branches
\echo '\n3. Testing create_branch()...'
SELECT pggit_v0.create_branch('uat-test-branch');

-- 4. list_branches() - Lists all branches
\echo '\n4. Testing list_branches()...'
SELECT * FROM pggit_v0.list_branches();

-- 5. delete_branch() - Deletes branches
\echo '\n5. Testing delete_branch()...'
SELECT pggit_v0.delete_branch('uat-test-branch');

-- 6. get_commit_history() - Shows commit log
\echo '\n6. Testing get_commit_history()...'
SELECT * FROM pggit_v0.get_commit_history(5);

-- 7. get_object_history() - Shows object changes
\echo '\n7. Testing get_object_history()...'
SELECT * FROM pggit_v0.get_object_history('uat_test', 'users', 5);

-- 8. diff_commits() - Compares commits
\echo '\n8. Testing diff_commits()...'
-- Get two commits to compare
SELECT commit_sha FROM pggit_v0.commit_graph ORDER BY committed_at DESC LIMIT 2;

-- 9. diff_branches() - Compares branches
\echo '\n9. Testing diff_branches()...'
-- Create two branches for comparison
SELECT pggit_v0.create_branch('uat-branch-a');
SELECT pggit_v0.create_branch('uat-branch-b');
SELECT * FROM pggit_v0.diff_branches('uat-branch-a', 'uat-branch-b');

-- 10. get_object_definition() - Gets DDL
\echo '\n10. Testing get_object_definition()...'
SELECT pggit_v0.get_object_definition('uat_test', 'users', 'TABLE');

-- 11. get_object_metadata() - Gets metadata
\echo '\n11. Testing get_object_metadata()...'
SELECT * FROM pggit_v0.get_object_metadata('uat_test', 'users', 'TABLE');

-- 12. get_head_sha() - Gets current HEAD
\echo '\n12. Testing get_head_sha()...'
SELECT pggit_v0.get_head_sha() as current_head;

-- Clean up test branches
SELECT pggit_v0.delete_branch('uat-branch-a');
SELECT pggit_v0.delete_branch('uat-branch-b');

\echo '\n=== Developer Functions Test Complete ==='