"""
Test Scenario Builder - Composable fixture builder for pgGit tests

This module provides a ScenarioBuilder class for constructing test scenarios
by composing simple building blocks (branches, commits, objects).

Pattern: Builder pattern combined with transaction-scoped cleanup
- Each scenario is built fresh for a test
- No cleanup needed - transaction rollback handles it
- Scenarios are composed: basic → feature-rich → phase-specific
"""

from datetime import datetime, timedelta
import hashlib
from typing import List, Dict, Optional


class ScenarioBuilder:
    """Build test scenarios from reusable components"""

    def __init__(self, db_conn):
        """Initialize scenario builder with database connection"""
        self.conn = db_conn
        self.created_items = {
            'branches': {},  # name -> id mapping
            'commits': {},   # hash -> id mapping
            'objects': {},   # name -> id mapping
        }
        self.base_time = datetime(2025, 12, 26, 10, 0, 0)
        self.time_offset = timedelta(minutes=0)

    def _get_branch_id(self, branch_name: str) -> int:
        """Get or create a branch, returning its ID"""
        if branch_name in self.created_items['branches']:
            return self.created_items['branches'][branch_name]

        # Get existing branch (e.g., 'main')
        with self.conn.cursor() as cur:
            cur.execute(
                "SELECT branch_id FROM pggit.branches WHERE branch_name = %s",
                (branch_name,)
            )
            result = cur.fetchone()
            if result:
                branch_id = result[0]
                self.created_items['branches'][branch_name] = branch_id
                return branch_id

        raise ValueError(f"Branch '{branch_name}' does not exist")

    def _create_branch(self, name: str, parent_name: Optional[str] = None) -> int:
        """Create a feature branch"""
        parent_id = None
        if parent_name:
            parent_id = self._get_branch_id(parent_name)

        with self.conn.cursor() as cur:
            cur.execute(
                """INSERT INTO pggit.branches
                   (branch_name, parent_branch_id, created_by, status, created_at)
                   VALUES (%s, %s, %s, %s, %s)
                   RETURNING branch_id""",
                (name, parent_id, 'test_user', 'ACTIVE', datetime.now())
            )
            branch_id = cur.fetchone()[0]

        self.created_items['branches'][name] = branch_id
        return branch_id

    def _create_object(self, name: str, obj_type: str = 'TABLE', schema: str = 'public') -> int:
        """Create a schema object"""
        definition = f"CREATE {obj_type} {schema}.{name}"
        content_hash = hashlib.sha256(definition.encode()).hexdigest()

        with self.conn.cursor() as cur:
            cur.execute(
                """INSERT INTO pggit.schema_objects
                   (object_type, schema_name, object_name, current_definition,
                    content_hash, is_active, version_major, version_minor, version_patch)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                   RETURNING object_id""",
                (obj_type, schema, name, definition, content_hash, True, 1, 0, 0)
            )
            object_id = cur.fetchone()[0]

        self.created_items['objects'][f"{schema}.{name}"] = object_id
        return object_id

    def _create_commit(self, branch_name: str, message: str, commit_hash: str,
                      author: str = 'test_user') -> int:
        """Create a commit on a branch"""
        branch_id = self._get_branch_id(branch_name)
        current_time = self.base_time + self.time_offset
        self.time_offset += timedelta(minutes=1)

        with self.conn.cursor() as cur:
            cur.execute(
                """INSERT INTO pggit.commits
                   (branch_id, commit_hash, commit_message, author_name, author_time)
                   VALUES (%s, %s, %s, %s, %s)
                   RETURNING commit_id""",
                (branch_id, commit_hash, message, author, current_time)
            )
            commit_id = cur.fetchone()[0]

        self.created_items['commits'][commit_hash] = commit_id
        return commit_id

    # ========================================================================
    # Public Builder Methods
    # ========================================================================

    def add_branches(self, names: List[str], parent: str = 'main') -> 'ScenarioBuilder':
        """
        Add feature branches.

        Args:
            names: List of branch names to create
            parent: Parent branch name (default: 'main')

        Returns:
            self for chaining
        """
        for name in names:
            self._create_branch(name, parent_name=parent)
        return self

    def add_objects(self, count: int, on_branch: str = 'main',
                   naming_pattern: str = 'table_{i}') -> 'ScenarioBuilder':
        """
        Add schema objects on a branch.

        Args:
            count: Number of objects to create
            on_branch: Branch name to associate with
            naming_pattern: Pattern for object names (use {i} for index)

        Returns:
            self for chaining
        """
        branch_id = self._get_branch_id(on_branch)

        for i in range(count):
            obj_name = naming_pattern.format(i=i)
            obj_id = self._create_object(obj_name)

            # Create object_history entry
            with self.conn.cursor() as cur:
                cur.execute(
                    """INSERT INTO pggit.object_history
                       (object_id, branch_id, change_type, after_definition,
                        after_hash, commit_hash, author_name, author_time)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
                    (obj_id, branch_id, 'CREATE',
                     f'CREATE TABLE {obj_name}',
                     hashlib.sha256(f'CREATE TABLE {obj_name}'.encode()).hexdigest(),
                     f'hash_{obj_name}', 'test_user', datetime.now())
                )

        return self

    def add_commits(self, count: int, on_branch: str = 'main',
                   naming_pattern: str = 'commit_{i}') -> 'ScenarioBuilder':
        """
        Add commits on a branch.

        Args:
            count: Number of commits to create
            on_branch: Branch name to create commits on
            naming_pattern: Pattern for commit messages (use {i} for index)

        Returns:
            self for chaining
        """
        for i in range(count):
            message = naming_pattern.format(i=i)
            commit_hash = f"hash_{message}"
            self._create_commit(on_branch, message, commit_hash)

        return self

    def add_object_changes(self, object_name: str, on_branch: str = 'main',
                          change_count: int = 3) -> 'ScenarioBuilder':
        """
        Add a sequence of changes to an object (temporal history).

        Args:
            object_name: Name of object to modify
            on_branch: Branch name to track changes on
            change_count: Number of modifications to create

        Returns:
            self for chaining
        """
        obj_id = self.created_items['objects'].get(f"public.{object_name}")
        if not obj_id:
            obj_id = self._create_object(object_name)

        branch_id = self._get_branch_id(on_branch)

        modifications = [
            ('CREATE', f'CREATE TABLE {object_name} (id INT)'),
            ('ALTER', f'ALTER TABLE {object_name} ADD COLUMN name VARCHAR(100)'),
            ('ALTER', f'ALTER TABLE {object_name} ADD COLUMN email VARCHAR(100)'),
        ]

        for i, (change_type, definition) in enumerate(modifications[:change_count]):
            commit_hash = f"hash_{object_name}_{i}"
            content_hash = hashlib.sha256(definition.encode()).hexdigest()

            with self.conn.cursor() as cur:
                cur.execute(
                    """INSERT INTO pggit.object_history
                       (object_id, branch_id, change_type, after_definition,
                        after_hash, commit_hash, author_name, author_time)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
                    (obj_id, branch_id, change_type, definition, content_hash,
                     commit_hash, 'test_user', datetime.now())
                )

        return self

    def add_merge_scenario(self, source_branch: str, target_branch: str = 'main') -> 'ScenarioBuilder':
        """
        Set up a merge scenario between two branches.

        Args:
            source_branch: Source branch name
            target_branch: Target branch name (default: 'main')

        Returns:
            self for chaining
        """
        source_id = self._get_branch_id(source_branch)
        target_id = self._get_branch_id(target_branch)

        with self.conn.cursor() as cur:
            # Create merge_operations record
            cur.execute(
                """INSERT INTO pggit.merge_operations
                   (id, source_branch_id, target_branch_id, status, created_at)
                   VALUES (%s, %s, %s, %s, %s)""",
                (f"merge_{source_branch}_{target_branch}",
                 source_id, target_id, 'PENDING', datetime.now())
            )

        return self

    def build(self) -> Dict:
        """
        Return the built scenario.

        Returns:
            Dictionary with 'branches', 'commits', 'objects' mappings
        """
        self.conn.commit()
        return {
            'branches': self.created_items['branches'].copy(),
            'commits': self.created_items['commits'].copy(),
            'objects': self.created_items['objects'].copy(),
        }

    def get_branch_id(self, name: str) -> int:
        """Get a created branch ID"""
        return self.created_items['branches'].get(name)

    def get_object_id(self, name: str, schema: str = 'public') -> int:
        """Get a created object ID"""
        return self.created_items['objects'].get(f"{schema}.{name}")

    def get_commit_hash(self, index: int, on_branch: str = 'main') -> Optional[str]:
        """Get commit hash for a specific commit"""
        # This is a helper for tests that need to reference commits
        # Implementation depends on how commits are tracked
        return None  # Placeholder
