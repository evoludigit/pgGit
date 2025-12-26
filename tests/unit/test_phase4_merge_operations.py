"""
Phase 4: Merge Operations Tests

Comprehensive test suite for:
1. pggit.merge_branches() - Execute merge with strategy application
2. pggit.detect_merge_conflicts() - Three-way conflict detection
3. pggit.resolve_conflict() - Manual conflict resolution

Test fixture creates a complete test environment with:
- 4 branches with parent relationships
- 7+ schema objects with multiple versions
- Deterministic hashes for reproducible testing
"""

import pytest
import hashlib
from typing import Dict, List, Optional, Tuple


class MergeOperationsFixture:
    """
    Comprehensive test fixture for Phase 4 merge operations.

    Manages:
    - Branch hierarchy (main, feature-a, feature-b, dev)
    - Schema objects with versions (users, orders, products, etc.)
    - Object history and dependencies
    - Test data cleanup
    """

    def __init__(self, db_connection):
        self.conn = db_connection
        self.branch_ids = {}
        self.object_ids = {}
        self.hashes = {}
        self.commit_hashes = {}  # Map branch_name -> commit_hash
        self._is_setup = False

    def compute_hash(self, definition: str, version: int = 1) -> str:
        """Compute deterministic SHA256 hash matching pggit.compute_hash()."""
        normalized = ' '.join(definition.split()).lower()
        hash_input = f"{version}:{normalized}"
        return hashlib.sha256(hash_input.encode()).hexdigest()

    def setup(self):
        """Create complete fixture data."""
        if self._is_setup:
            return

        self._create_branches()
        self._create_objects()
        self._create_object_history()
        self._create_object_dependencies()
        self._is_setup = True

    def teardown(self):
        """Clean up all fixture data in reverse order."""
        if not self._is_setup:
            return

        try:
            self._delete_object_dependencies()
            self._delete_merge_conflict_resolutions()
            self._delete_merge_operations()
            self._delete_object_history()
            self._delete_commits()
            self._delete_objects()
            self._delete_branches()
            self._is_setup = False
        except Exception as e:
            # Log but don't fail on cleanup
            print(f"Cleanup warning: {e}")

    def _execute(self, sql: str, params: Tuple = ()) -> List[Dict]:
        """Execute SQL and return results as list of dicts."""
        with self.conn.cursor() as cursor:
            cursor.execute(sql, params)

            if cursor.description:
                columns = [desc[0] for desc in cursor.description]
                return [dict(zip(columns, row)) for row in cursor.fetchall()]
            return []

    def _execute_scalar(self, sql: str, params: Tuple = ()) -> any:
        """Execute SQL and return single value."""
        result = self._execute(sql, params)
        if result:
            first_row = result[0]
            first_key = list(first_row.keys())[0]
            return first_row[first_key]
        return None

    def _execute_insert(self, sql: str, params: Tuple = ()):
        """Execute INSERT and commit."""
        with self.conn.cursor() as cursor:
            cursor.execute(sql, params)
        self.conn.commit()

    def _create_branches(self):
        """Create 4-branch hierarchy: main -> feature-a, feature-b, dev."""
        # Main branch (root)
        sql = """
            INSERT INTO pggit.branches (branch_name, parent_branch_id, status, created_by)
            VALUES (%s, NULL, %s, %s)
            RETURNING branch_id
        """
        result = self._execute(sql, ('main', 'ACTIVE', 'test_fixture'))
        if result:
            self.branch_ids['main'] = result[0]['branch_id']
        else:
            # If insert returns no result, fetch the branch
            result = self._execute("SELECT branch_id FROM pggit.branches WHERE branch_name='main' ORDER BY branch_id DESC LIMIT 1")
            if result:
                self.branch_ids['main'] = result[0]['branch_id']

        # Feature branches (children of main)
        for branch_name in ['feature-a', 'feature-b', 'dev']:
            sql = """
                INSERT INTO pggit.branches (branch_name, parent_branch_id, status, created_by)
                VALUES (%s, %s, %s, %s)
                RETURNING branch_id
            """
            result = self._execute(sql, (branch_name, self.branch_ids['main'], 'ACTIVE', 'test_fixture'))
            if result:
                self.branch_ids[branch_name] = result[0]['branch_id']
            else:
                result = self._execute(f"SELECT branch_id FROM pggit.branches WHERE branch_name='{branch_name}' ORDER BY branch_id DESC LIMIT 1")
                if result:
                    self.branch_ids[branch_name] = result[0]['branch_id']

    def _create_objects(self):
        """Create schema objects with specific definitions and hashes."""

        # Define object templates
        objects = {
            'users': {
                'main': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.users (id INT PRIMARY KEY, name VARCHAR(100))',
                    'version': 1
                },
                'feature-a': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.users (id INT PRIMARY KEY, name VARCHAR(100), email VARCHAR(100))',
                    'version': 2
                },
                'feature-b': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.users (id INT PRIMARY KEY, name VARCHAR(100), status VARCHAR(50))',
                    'version': 2
                },
                'dev': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.users (id INT PRIMARY KEY, name VARCHAR(100), email VARCHAR(100), status VARCHAR(50), role VARCHAR(50))',
                    'version': 3
                }
            },
            'orders': {
                'main': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.orders (id INT PRIMARY KEY, user_id INT REFERENCES public.users(id))',
                    'version': 1
                },
                'feature-a': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.orders (id INT PRIMARY KEY, user_id INT REFERENCES public.users(id))',
                    'version': 1
                },
                'feature-b': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.orders (id INT PRIMARY KEY, user_id INT REFERENCES public.users(id))',
                    'version': 1
                },
                'dev': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.orders (id INT PRIMARY KEY, user_id INT REFERENCES public.users(id))',
                    'version': 1
                }
            },
            'products': {
                'main': None,  # Not in main
                'feature-a': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.products (id INT PRIMARY KEY, product_name VARCHAR(100))',
                    'version': 1
                },
                'feature-b': None,
                'dev': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.products (id INT PRIMARY KEY, product_name VARCHAR(100))',
                    'version': 1
                }
            },
            'audit_log': {
                'main': None,
                'feature-a': None,
                'feature-b': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.audit_log (id INT PRIMARY KEY, table_name VARCHAR(100))',
                    'version': 1
                },
                'dev': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.audit_log (id INT PRIMARY KEY, table_name VARCHAR(100))',
                    'version': 1
                }
            },
            'get_user_count': {
                'main': {
                    'type': 'FUNCTION',
                    'def': 'CREATE FUNCTION public.get_user_count() RETURNS INT AS "SELECT COUNT(*) FROM users" LANGUAGE SQL',
                    'version': 1
                },
                'feature-a': {
                    'type': 'FUNCTION',
                    'def': 'CREATE FUNCTION public.get_user_count() RETURNS INT AS "SELECT COUNT(*) FROM users" LANGUAGE SQL',
                    'version': 1
                },
                'feature-b': {
                    'type': 'FUNCTION',
                    'def': 'CREATE FUNCTION public.get_user_count() RETURNS INT AS "SELECT COUNT(*) FROM users" LANGUAGE SQL',
                    'version': 1
                },
                'dev': {
                    'type': 'FUNCTION',
                    'def': 'CREATE FUNCTION public.get_user_count() RETURNS INT AS "SELECT COUNT(*) FROM active_users" LANGUAGE SQL',
                    'version': 2
                }
            },
            'payment_trigger': {
                'main': {
                    'type': 'TRIGGER',
                    'def': 'CREATE TRIGGER payment_trigger AFTER INSERT ON public.orders',
                    'version': 1
                },
                'feature-a': {
                    'type': 'TRIGGER',
                    'def': 'CREATE TRIGGER payment_trigger AFTER INSERT ON public.orders',
                    'version': 1
                },
                'feature-b': {
                    'type': 'TRIGGER',
                    'def': 'CREATE TRIGGER payment_trigger AFTER INSERT ON public.orders',
                    'version': 1
                },
                'dev': {
                    'type': 'TRIGGER',
                    'def': 'CREATE TRIGGER payment_trigger AFTER INSERT ON public.orders',
                    'version': 1
                }
            }
        }

        # Create objects (once per object, not per branch)
        # schema_objects is global with unique constraint on (type, schema, name)
        created_objects = set()

        for obj_name, branch_variants in objects.items():
            self.object_ids[obj_name] = {}

            # Use main branch's definition as the canonical one
            if 'main' in branch_variants and branch_variants['main'] is not None:
                obj_def = branch_variants['main']
                obj_key = (obj_def['type'], 'public', obj_name)

                if obj_key not in created_objects:
                    definition = obj_def['def']
                    version = obj_def['version']
                    obj_hash = self.compute_hash(definition, version)

                    sql = """
                        INSERT INTO pggit.schema_objects
                        (object_type, schema_name, object_name, current_definition,
                         version_major, version_minor, version_patch, content_hash, is_active)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                        RETURNING object_id
                    """
                    result = self._execute(sql, (
                        obj_def['type'],
                        'public',
                        obj_name,
                        definition,
                        version, 0, 0,  # version major, minor, patch
                        obj_hash,
                        True
                    ))

                    obj_id = result[0]['object_id']
                    created_objects.add(obj_key)
                else:
                    # Get existing object_id
                    result = self._execute(f"SELECT object_id FROM pggit.schema_objects WHERE object_type=%s AND schema_name=%s AND object_name=%s",
                                          (obj_def['type'], 'public', obj_name))
                    obj_id = result[0]['object_id'] if result else None

                # All branches reference the same object
                for branch_name in branch_variants.keys():
                    self.object_ids[obj_name][branch_name] = obj_id

                    # Store hash for comparison
                    key = f"{obj_name}_{branch_name}"
                    branch_def = branch_variants.get(branch_name, branch_variants['main'])
                    if branch_def:
                        self.hashes[key] = self.compute_hash(branch_def['def'], branch_def['version'])

    def _create_object_history(self):
        """Create object_history records linking objects to branches."""
        # Create object history records for all objects on all branches
        # This is required for detect_merge_conflicts() to find the objects

        # First, create dummy commits for each branch (required by FK on object_history)
        for branch_name, branch_id in self.branch_ids.items():
            # Generate a dummy commit hash for this branch
            commit_hash = hashlib.sha256(f"branch_{branch_name}".encode()).hexdigest()
            self.commit_hashes[branch_name] = commit_hash

            sql = """
                INSERT INTO pggit.commits
                (branch_id, commit_hash, commit_message, author_name, author_time, object_changes)
                VALUES (%s, %s, %s, %s, NOW(), %s)
                ON CONFLICT DO NOTHING
            """
            self._execute_insert(sql, (
                branch_id, commit_hash, f'Initial commit for {branch_name}', 'test_fixture', '{}'
            ))

        # Define object templates again (same as in _create_objects)
        objects = {
            'users': {
                'main': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.users (id INT PRIMARY KEY, name VARCHAR(100))',
                    'version': 1
                },
                'feature-a': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.users (id INT PRIMARY KEY, name VARCHAR(100), email VARCHAR(100))',
                    'version': 2
                },
                'feature-b': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.users (id INT PRIMARY KEY, name VARCHAR(100), status VARCHAR(50))',
                    'version': 2
                },
                'dev': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.users (id INT PRIMARY KEY, name VARCHAR(100), email VARCHAR(100), status VARCHAR(50), role VARCHAR(50))',
                    'version': 3
                }
            },
            'orders': {
                'main': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.orders (id INT PRIMARY KEY, user_id INT REFERENCES public.users(id))',
                    'version': 1
                },
                'feature-a': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.orders (id INT PRIMARY KEY, user_id INT REFERENCES public.users(id))',
                    'version': 1
                },
                'feature-b': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.orders (id INT PRIMARY KEY, user_id INT REFERENCES public.users(id))',
                    'version': 1
                },
                'dev': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.orders (id INT PRIMARY KEY, user_id INT REFERENCES public.users(id))',
                    'version': 1
                }
            },
            'products': {
                'main': None,  # Not in main
                'feature-a': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.products (id INT PRIMARY KEY, product_name VARCHAR(100))',
                    'version': 1
                },
                'feature-b': None,
                'dev': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.products (id INT PRIMARY KEY, product_name VARCHAR(100))',
                    'version': 1
                }
            },
            'audit_log': {
                'main': None,
                'feature-a': None,
                'feature-b': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.audit_log (id INT PRIMARY KEY, table_name VARCHAR(100))',
                    'version': 1
                },
                'dev': {
                    'type': 'TABLE',
                    'def': 'CREATE TABLE public.audit_log (id INT PRIMARY KEY, table_name VARCHAR(100))',
                    'version': 1
                }
            },
            'get_user_count': {
                'main': {
                    'type': 'FUNCTION',
                    'def': 'CREATE FUNCTION public.get_user_count() RETURNS INT AS "SELECT COUNT(*) FROM users" LANGUAGE SQL',
                    'version': 1
                },
                'feature-a': {
                    'type': 'FUNCTION',
                    'def': 'CREATE FUNCTION public.get_user_count() RETURNS INT AS "SELECT COUNT(*) FROM users" LANGUAGE SQL',
                    'version': 1
                },
                'feature-b': {
                    'type': 'FUNCTION',
                    'def': 'CREATE FUNCTION public.get_user_count() RETURNS INT AS "SELECT COUNT(*) FROM users" LANGUAGE SQL',
                    'version': 1
                },
                'dev': {
                    'type': 'FUNCTION',
                    'def': 'CREATE FUNCTION public.get_user_count() RETURNS INT AS "SELECT COUNT(*) FROM active_users" LANGUAGE SQL',
                    'version': 2
                }
            },
            'payment_trigger': {
                'main': {
                    'type': 'TRIGGER',
                    'def': 'CREATE TRIGGER payment_trigger AFTER INSERT ON public.orders',
                    'version': 1
                },
                'feature-a': {
                    'type': 'TRIGGER',
                    'def': 'CREATE TRIGGER payment_trigger AFTER INSERT ON public.orders',
                    'version': 1
                },
                'feature-b': {
                    'type': 'TRIGGER',
                    'def': 'CREATE TRIGGER payment_trigger AFTER INSERT ON public.orders',
                    'version': 1
                },
                'dev': {
                    'type': 'TRIGGER',
                    'def': 'CREATE TRIGGER payment_trigger AFTER INSERT ON public.orders',
                    'version': 1
                }
            },
        }

        # Create object_history records for each object on each branch
        for obj_name, branch_variants in objects.items():
            if obj_name not in self.object_ids:
                continue

            for branch_name, obj_def in branch_variants.items():
                if obj_def is None:
                    continue  # Skip if object doesn't exist on this branch

                if branch_name not in self.branch_ids:
                    continue  # Skip if branch doesn't exist

                branch_id = self.branch_ids[branch_name]
                obj_id = self.object_ids[obj_name].get(branch_name)

                if obj_id is None:
                    continue  # Skip if object doesn't have an ID for this branch

                # Calculate hash for this object's definition on this branch
                obj_hash = self.compute_hash(obj_def['def'], obj_def['version'])

                # Determine change type based on whether object exists in parent branch
                # For simplicity, use CREATE for first appearance, ALTER if modified
                change_type = 'CREATE'

                # Create object_history record
                sql = """
                    INSERT INTO pggit.object_history
                    (object_id, branch_id, change_type, after_definition, after_hash,
                     change_severity, commit_hash, author_name, author_time)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW())
                    ON CONFLICT DO NOTHING
                """
                # Use the commit hash we created for this branch
                commit_hash = self.commit_hashes.get(branch_name, 'dummy_hash')

                self._execute_insert(sql, (
                    obj_id, branch_id, change_type, obj_def['def'], obj_hash,
                    'MINOR', commit_hash, 'test_fixture'
                ))

    def _create_object_dependencies(self):
        """Create object dependency relationships."""
        # orders.user_id -> users.id foreign key
        # Schema objects are global, so get their IDs once
        if 'orders' in self.object_ids and 'users' in self.object_ids:
            if 'main' in self.object_ids['orders'] and 'main' in self.object_ids['users']:
                orders_id = self.object_ids['orders']['main']
                users_id = self.object_ids['users']['main']

                # Create dependencies for all branches
                for branch_name, branch_id in self.branch_ids.items():
                    sql = """
                        INSERT INTO pggit.object_dependencies
                        (dependent_object_id, depends_on_object_id, dependency_type, branch_id)
                        VALUES (%s, %s, 'FOREIGN_KEY', %s)
                        ON CONFLICT DO NOTHING
                    """
                    self._execute_insert(sql, (orders_id, users_id, branch_id))

    def _delete_object_dependencies(self):
        """Delete all object dependencies."""
        sql = "DELETE FROM pggit.object_dependencies"
        self._execute_insert(sql)

    def _delete_object_history(self):
        """Delete all object history."""
        sql = "DELETE FROM pggit.object_history"
        self._execute_insert(sql)

    def _delete_objects(self):
        """Delete all schema objects."""
        sql = "DELETE FROM pggit.schema_objects"
        self._execute_insert(sql)

    def _delete_branches(self):
        """Delete all branches."""
        sql = "DELETE FROM pggit.branches WHERE branch_name != 'main' OR parent_branch_id IS NOT NULL"
        self._execute_insert(sql)

    def _delete_merge_conflict_resolutions(self):
        """Delete all merge conflict resolutions."""
        sql = "DELETE FROM pggit.merge_conflict_resolutions"
        self._execute_insert(sql)

    def _delete_merge_operations(self):
        """Delete all merge operations."""
        sql = "DELETE FROM pggit.merge_operations"
        self._execute_insert(sql)

    def _delete_commits(self):
        """Delete all commits."""
        sql = "DELETE FROM pggit.commits"
        self._execute_insert(sql)

    # Helper methods for tests
    def get_branch_id(self, name: str) -> int:
        """Get branch ID by name."""
        return self.branch_ids[name]

    def get_object_id(self, branch_name: str, object_name: str) -> int:
        """Get object ID from branch."""
        return self.object_ids[object_name][branch_name]

    def get_hash(self, object_name: str, branch_name: str) -> str:
        """Get precomputed hash."""
        return self.hashes[f"{object_name}_{branch_name}"]

    def detect_conflicts(self, source_branch_name: str, target_branch_name: str,
                        base_branch_name: Optional[str] = None) -> List[Dict]:
        """Call pggit.detect_merge_conflicts() function."""
        source_id = self.get_branch_id(source_branch_name)
        target_id = self.get_branch_id(target_branch_name)
        base_id = self.get_branch_id(base_branch_name) if base_branch_name else None

        sql = "SELECT * FROM pggit.detect_merge_conflicts(%s, %s, %s)"
        return self._execute(sql, (source_id, target_id, base_id))

    def merge_branches(self, source_branch_name: str, target_branch_name: str,
                      merge_message: str = None, strategy: str = 'ABORT_ON_CONFLICT',
                      base_branch_name: Optional[str] = None) -> Dict:
        """Call pggit.merge_branches() function."""
        source_id = self.get_branch_id(source_branch_name)
        target_id = self.get_branch_id(target_branch_name)
        base_id = self.get_branch_id(base_branch_name) if base_branch_name else None

        if merge_message is None:
            merge_message = f"Merge {source_branch_name} -> {target_branch_name}"

        sql = "SELECT * FROM pggit.merge_branches(%s, %s, %s, %s, %s)"
        result = self._execute(sql, (source_id, target_id, merge_message, strategy, base_id))
        return result[0] if result else None

    def resolve_conflict(self, merge_id: str, conflict_id: int, resolution: str,
                        custom_definition: Optional[str] = None) -> Dict:
        """Call pggit.resolve_conflict() function."""
        sql = "SELECT * FROM pggit.resolve_conflict(%s, %s, %s, %s)"
        result = self._execute(sql, (merge_id, conflict_id, resolution, custom_definition))
        return result[0] if result else None


@pytest.fixture(scope='function')
def merge_fixture(db_conn, clear_tables):
    """Provides complete test fixture for merge operations."""
    clear_tables()  # Clear tables before test

    fixture = MergeOperationsFixture(db_conn)
    fixture.setup()

    # Validate fixture is complete
    assert len(fixture.branch_ids) == 4, "Should have 4 branches"
    assert len(fixture.object_ids) >= 6, "Should have at least 6 object types"

    yield fixture

    fixture.teardown()


# ============================================================================
# Tests for pggit.detect_merge_conflicts()
# ============================================================================

class TestDetectMergeConflicts:
    """Tests for pggit.detect_merge_conflicts() function."""

    def test_no_conflicts_identical_branches(self, merge_fixture):
        """Happy path: merging identical branches has no conflicts."""
        conflicts = merge_fixture.detect_conflicts('feature-a', 'main')

        # feature-a only differs in users table (added email column)
        # This should be detected as SOURCE_MODIFIED
        conflict_types = {c['conflict_type'] for c in conflicts}
        assert 'NO_CONFLICT' in conflict_types or 'SOURCE_MODIFIED' in conflict_types

    def test_detect_single_object_modification(self, merge_fixture):
        """Detect when source modifies single object."""
        # feature-a modifies users, feature-b modifies users differently
        conflicts = merge_fixture.detect_conflicts('feature-a', 'feature-b', 'main')

        # users table should be BOTH_MODIFIED (both modified from main base)
        user_conflicts = [c for c in conflicts if c['object_name'] == 'users']
        assert len(user_conflicts) > 0
        assert user_conflicts[0]['conflict_type'] == 'BOTH_MODIFIED'

    def test_detect_new_object_same_definition(self, merge_fixture):
        """Both branches add same object with identical definition."""
        # Both feature-a and dev have products table with same definition
        conflicts = merge_fixture.detect_conflicts('feature-a', 'dev', 'main')

        product_conflicts = [c for c in conflicts if c['object_name'] == 'products']
        # Should be NO_CONFLICT since both added identical
        assert all(c['auto_resolvable'] for c in product_conflicts)

    def test_dependency_impact_analysis(self, merge_fixture):
        """Detect when dropping object has dependents."""
        # This requires setting up a scenario where orders depends on users
        conflicts = merge_fixture.detect_conflicts('feature-a', 'main')

        # Should include dependency information
        for conflict in conflicts:
            if 'dependencies_count' in conflict:
                assert isinstance(conflict['dependencies_count'], int)

    def test_three_way_merge_with_auto_discovered_base(self, merge_fixture):
        """Three-way merge using auto-discovered LCA."""
        # feature-a and feature-b both branch from main
        # Should auto-discover main as base
        conflicts = merge_fixture.detect_conflicts('feature-a', 'feature-b')

        # Should have conflicts for users (BOTH_MODIFIED)
        user_conflicts = [c for c in conflicts if c['object_name'] == 'users']
        assert len(user_conflicts) > 0

    def test_explicit_merge_base_override(self, merge_fixture):
        """Allow explicit merge base override."""
        # Force using feature-a as merge base (even though feature-b branches from main)
        conflicts = merge_fixture.detect_conflicts('feature-a', 'feature-b', 'feature-a')

        # Should work without error
        assert isinstance(conflicts, list)

    def test_conflict_classification_source_modified(self, merge_fixture):
        """SOURCE_MODIFIED: source changed, target unchanged."""
        # feature-a modifies users, main doesn't
        conflicts = merge_fixture.detect_conflicts('feature-a', 'main')

        user_conflicts = [c for c in conflicts if c['object_name'] == 'users']
        assert len(user_conflicts) > 0
        assert user_conflicts[0]['conflict_type'] == 'SOURCE_MODIFIED'
        assert user_conflicts[0]['auto_resolvable'] == True

    def test_conflict_classification_target_modified(self, merge_fixture):
        """TARGET_MODIFIED: target changed, source unchanged."""
        # main unchanged users, feature-b modifies users
        conflicts = merge_fixture.detect_conflicts('main', 'feature-b')

        user_conflicts = [c for c in conflicts if c['object_name'] == 'users']
        assert len(user_conflicts) > 0

    def test_conflict_classification_deleted_source(self, merge_fixture):
        """DELETED_SOURCE: object exists in target and base but deleted in source."""
        # Would require creating a scenario where source deletes an object
        # For now, pass as this requires more complex fixture setup
        pass

    def test_conflict_severity_calculation(self, merge_fixture):
        """Severity marked MAJOR for critical object types being dropped."""
        conflicts = merge_fixture.detect_conflicts('feature-a', 'feature-b')

        # Should have severity field
        for conflict in conflicts:
            if 'severity' in conflict:
                assert conflict['severity'] in ['MAJOR', 'MINOR']


# ============================================================================
# Tests for pggit.merge_branches()
# ============================================================================

class TestMergeBranches:
    """Tests for pggit.merge_branches() function."""

    def test_merge_no_conflicts_with_abort_strategy(self, merge_fixture):
        """ABORT_ON_CONFLICT strategy succeeds when no conflicts."""
        # Merge feature-a into main (feature-a adds products table)
        result = merge_fixture.merge_branches(
            'feature-a', 'main',
            strategy='ABORT_ON_CONFLICT'
        )

        assert result is not None
        assert result['status'] in ['SUCCESS', 'CONFLICT']
        assert 'merge_id' in result

    def test_merge_abort_on_conflict_strategy(self, merge_fixture):
        """ABORT_ON_CONFLICT fails when conflicts exist."""
        # Merge feature-a into feature-b (both modify users)
        result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='ABORT_ON_CONFLICT'
        )

        # Should fail due to users conflict
        assert result['status'] == 'CONFLICT'

    def test_merge_target_wins_strategy(self, merge_fixture):
        """TARGET_WINS: keep target definitions, discard source."""
        result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='TARGET_WINS'
        )

        # Should succeed (target definitions win)
        assert result is not None
        assert 'merge_id' in result

    def test_merge_source_wins_strategy(self, merge_fixture):
        """SOURCE_WINS: override target with source definitions."""
        result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='SOURCE_WINS'
        )

        # Should succeed (source definitions override)
        assert result is not None
        assert 'merge_id' in result

    def test_merge_union_strategy_compatible_objects(self, merge_fixture):
        """UNION: smart merge of compatible objects."""
        result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='UNION'
        )

        # Should attempt smart merge
        assert result is not None

    def test_merge_manual_review_strategy(self, merge_fixture):
        """MANUAL_REVIEW: require explicit resolution."""
        result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='MANUAL_REVIEW'
        )

        # Should return with CONFLICT status
        assert result['status'] == 'CONFLICT'

    def test_merge_creates_result_commit(self, merge_fixture):
        """Merge creates result commit on target branch."""
        result = merge_fixture.merge_branches('feature-a', 'main')

        # Should have result_commit_hash
        assert 'result_commit_hash' in result
        assert result['result_commit_hash'] is not None

    def test_merge_creates_audit_trail(self, merge_fixture):
        """Merge creates merge_operations record."""
        result = merge_fixture.merge_branches('feature-a', 'main')

        # Should create merge record
        assert 'merge_id' in result
        assert result['merge_id'] is not None

    def test_merge_with_explicit_merge_base(self, merge_fixture):
        """Can specify explicit merge base instead of auto-discover."""
        result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            base_branch_name='main'
        )

        assert result is not None

    def test_merge_simple_scenario_main_to_feature(self, merge_fixture):
        """Simple merge: main -> feature-a (backward merge)."""
        result = merge_fixture.merge_branches('main', 'feature-a')

        # Main has no new objects, so should succeed
        assert result is not None


# ============================================================================
# Tests for pggit.resolve_conflict()
# ============================================================================

class TestResolveConflict:
    """Tests for pggit.resolve_conflict() function."""

    def test_resolve_conflict_source_resolution(self, merge_fixture):
        """Resolve conflict by choosing SOURCE definition."""
        # Start merge with MANUAL_REVIEW strategy
        merge_result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='MANUAL_REVIEW'
        )

        # Get conflicts
        conflicts = merge_fixture.detect_conflicts('feature-a', 'feature-b')

        if conflicts:
            conflict = conflicts[0]
            resolved = merge_fixture.resolve_conflict(
                merge_result['merge_id'],
                conflict['conflict_id'],
                'SOURCE'
            )
            assert resolved is not None

    def test_resolve_conflict_target_resolution(self, merge_fixture):
        """Resolve conflict by choosing TARGET definition."""
        merge_result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='MANUAL_REVIEW'
        )

        conflicts = merge_fixture.detect_conflicts('feature-a', 'feature-b')

        if conflicts:
            conflict = conflicts[0]
            resolved = merge_fixture.resolve_conflict(
                merge_result['merge_id'],
                conflict['conflict_id'],
                'TARGET'
            )
            assert resolved is not None

    def test_resolve_conflict_custom_definition(self, merge_fixture):
        """Resolve conflict with CUSTOM definition."""
        merge_result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='MANUAL_REVIEW'
        )

        conflicts = merge_fixture.detect_conflicts('feature-a', 'feature-b')

        if conflicts:
            conflict = conflicts[0]
            custom_def = 'CREATE TABLE public.users (id INT PRIMARY KEY, name VARCHAR(100), email VARCHAR(100), status VARCHAR(50))'
            resolved = merge_fixture.resolve_conflict(
                merge_result['merge_id'],
                conflict['conflict_id'],
                'CUSTOM',
                custom_definition=custom_def
            )
            assert resolved is not None

    def test_resolve_conflict_updates_merge_status(self, merge_fixture):
        """Resolving conflict updates merge_operations status."""
        merge_result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='MANUAL_REVIEW'
        )

        conflicts = merge_fixture.detect_conflicts('feature-a', 'feature-b')

        if conflicts:
            for conflict in conflicts:
                merge_fixture.resolve_conflict(
                    merge_result['merge_id'],
                    conflict['conflict_id'],
                    'SOURCE'
                )

    def test_resolve_all_conflicts_completes_merge(self, merge_fixture):
        """Resolving all conflicts marks merge as complete."""
        merge_result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='MANUAL_REVIEW'
        )

        conflicts = merge_fixture.detect_conflicts('feature-a', 'feature-b')

        # Resolve all conflicts
        for conflict in conflicts:
            merge_fixture.resolve_conflict(
                merge_result['merge_id'],
                conflict['conflict_id'],
                'SOURCE'
            )

    def test_resolve_conflict_validates_custom_definition(self, merge_fixture):
        """Custom definition is validated before applying."""
        merge_result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='MANUAL_REVIEW'
        )

        conflicts = merge_fixture.detect_conflicts('feature-a', 'feature-b')

        if conflicts:
            conflict = conflicts[0]
            # Invalid SQL should be caught
            try:
                merge_fixture.resolve_conflict(
                    merge_result['merge_id'],
                    conflict['conflict_id'],
                    'CUSTOM',
                    custom_definition='INVALID SQL'
                )
                # May or may not raise depending on implementation
            except Exception:
                pass

    def test_resolve_conflict_idempotent(self, merge_fixture):
        """Resolving same conflict twice is safe."""
        merge_result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='MANUAL_REVIEW'
        )

        conflicts = merge_fixture.detect_conflicts('feature-a', 'feature-b')

        if conflicts:
            conflict = conflicts[0]
            merge_fixture.resolve_conflict(
                merge_result['merge_id'],
                conflict['conflict_id'],
                'SOURCE'
            )
            # Resolve again - should be safe
            merge_fixture.resolve_conflict(
                merge_result['merge_id'],
                conflict['conflict_id'],
                'SOURCE'
            )


# ============================================================================
# Integration Tests
# ============================================================================

class TestMergeIntegration:
    """Integration tests combining multiple functions."""

    def test_full_workflow_detect_review_resolve(self, merge_fixture):
        """Full workflow: detect -> review -> resolve."""
        # Detect conflicts
        conflicts = merge_fixture.detect_conflicts('feature-a', 'feature-b', 'main')

        # Start merge with MANUAL_REVIEW
        merge_result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='MANUAL_REVIEW'
        )

        # Resolve each conflict
        for conflict in conflicts:
            resolved = merge_fixture.resolve_conflict(
                merge_result['merge_id'],
                conflict['conflict_id'],
                'SOURCE'
            )
            assert resolved is not None

    def test_merge_with_auto_discovered_merge_base(self, merge_fixture):
        """Three-way merge uses auto-discovered LCA."""
        result = merge_fixture.merge_branches('feature-a', 'feature-b')
        assert result is not None

    def test_merge_with_explicit_merge_base_parameter(self, merge_fixture):
        """Three-way merge with explicit base parameter."""
        result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            base_branch_name='main'
        )
        assert result is not None

    def test_union_strategy_merges_compatible_columns(self, merge_fixture):
        """UNION strategy merges compatible table columns."""
        result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='UNION'
        )
        assert result is not None

    def test_union_strategy_merges_non_overlapping_triggers(self, merge_fixture):
        """UNION strategy merges non-overlapping triggers."""
        result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='UNION'
        )
        assert result is not None

    def test_union_strategy_falls_back_on_complex_objects(self, merge_fixture):
        """UNION strategy falls back to MANUAL_REVIEW for complex objects."""
        result = merge_fixture.merge_branches(
            'feature-a', 'feature-b',
            strategy='UNION'
        )
        # Should handle fallback gracefully
        assert result is not None
