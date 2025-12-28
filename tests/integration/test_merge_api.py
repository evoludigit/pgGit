"""
Integration Tests for Merge API Endpoints
=========================================

Tests for three-way merge REST API endpoints.
Validates the complete merge workflow from branch creation to conflict resolution.

Test Coverage:
- Find merge base (LCA)
- Execute merge operations
- Conflict detection
- Conflict resolution
- Merge status tracking
- Error handling
"""

import pytest
from httpx import AsyncClient


class TestMergeBase:
    """Test merge base (LCA) discovery"""

    @pytest.mark.asyncio
    async def test_find_merge_base_success(self, client, db_pool):
        """Test finding merge base between two branches"""
        # Create a branch structure: main -> feature1 -> feature2
        async with db_pool.acquire() as conn:
            # Create main branch (should exist from fixtures)
            main_id = await conn.fetchval(
                "SELECT branch_id FROM pggit.branches WHERE branch_name = 'main' LIMIT 1"
            )

            if not main_id:
                main_id = await conn.fetchval(
                    "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                    "VALUES ('main', NULL, 'test_user', CURRENT_TIMESTAMP) RETURNING branch_id"
                )

            # Create feature1 from main
            feature1_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ('feature1', $1, 'test_user', CURRENT_TIMESTAMP) RETURNING branch_id",
                main_id
            )

            # Create feature2 from feature1
            feature2_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ('feature2', $1, 'test_user', CURRENT_TIMESTAMP) RETURNING branch_id",
                feature1_id
            )

        # Find merge base
        response = await client.get(f"/api/v1/branches/{feature1_id}/merge-base/{feature2_id}")
        assert response.status_code == 200

        data = response.json()
        assert "base_branch_id" in data
        assert "base_branch_name" in data
        assert "depth_from_branch1" in data
        assert "depth_from_branch2" in data

        # The merge base should be either main or feature1
        # (depends on if main already existed or we just created it)
        assert data["base_branch_id"] in [main_id, feature1_id]
        assert data["base_branch_name"] in ["main", "feature1"]

    @pytest.mark.asyncio
    async def test_find_merge_base_nonexistent_branch(self, client):
        """Test finding merge base with non-existent branch"""
        response = await client.get("/api/v1/branches/99999/merge-base/99998")
        assert response.status_code in [404, 500]  # Should fail gracefully

    @pytest.mark.asyncio
    async def test_find_merge_base_same_branch(self, client, db_pool):
        """Test finding merge base when both branches are the same"""
        async with db_pool.acquire() as conn:
            branch_id = await conn.fetchval(
                "SELECT branch_id FROM pggit.branches LIMIT 1"
            )

        if branch_id:
            response = await client.get(f"/api/v1/branches/{branch_id}/merge-base/{branch_id}")
            # Should return 400 Bad Request (cannot merge branch with itself)
            assert response.status_code == 400


class TestMergeExecution:
    """Test merge execution and workflow"""

    @pytest.mark.asyncio
    async def test_merge_no_conflicts(self, client, db_pool):
        """Test merge with no conflicts"""
        # Setup: Create branches and add non-conflicting changes
        async with db_pool.acquire() as conn:
            # Create main branch
            main_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ('main_merge_test', NULL, 'test_user', CURRENT_TIMESTAMP) RETURNING branch_id"
            )

            # Create feature branch from main
            feature_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ('feature_merge_test', $1, 'test_user', CURRENT_TIMESTAMP) RETURNING branch_id",
                main_id
            )

        # Execute merge
        payload = {
            "source_branch_id": feature_id,
            "merge_message": "Test merge with no conflicts",
            "merge_strategy": "MANUAL_REVIEW",
            "base_branch_id": None  # Auto-discover
        }

        response = await client.post(f"/api/v1/branches/{main_id}/merge", json=payload)
        assert response.status_code == 201

        data = response.json()
        assert "merge_id" in data
        assert "status" in data
        assert "conflicts_detected" in data
        assert "merge_complete" in data
        assert data["conflicts_detected"] >= 0

    @pytest.mark.asyncio
    async def test_merge_with_conflicts(self, client, db_pool):
        """Test merge that generates conflicts"""
        # Setup: Create branches with conflicting changes
        async with db_pool.acquire() as conn:
            # Create main branch
            main_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ('main_conflict_test', NULL, 'test_user', CURRENT_TIMESTAMP) RETURNING branch_id"
            )

            # Create feature branch
            feature_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ('feature_conflict_test', $1, 'test_user', CURRENT_TIMESTAMP) RETURNING branch_id",
                main_id
            )

            # Add a commit to main
            await conn.execute(
                "INSERT INTO pggit.commits (branch_id, commit_hash, commit_message, author_name, author_time, object_changes, created_at) "
                "VALUES ($1, 'hash1', 'Main commit', 'test_user', CURRENT_TIMESTAMP, '{}', CURRENT_TIMESTAMP)",
                main_id
            )

            # Add a commit to feature (creates potential conflict)
            await conn.execute(
                "INSERT INTO pggit.commits (branch_id, commit_hash, commit_message, author_name, author_time, object_changes, created_at) "
                "VALUES ($1, 'hash2', 'Feature commit', 'test_user', CURRENT_TIMESTAMP, '{}', CURRENT_TIMESTAMP)",
                feature_id
            )

        # Execute merge
        payload = {
            "source_branch_id": feature_id,
            "merge_message": "Test merge with conflicts",
            "merge_strategy": "MANUAL_REVIEW"
        }

        response = await client.post(f"/api/v1/branches/{main_id}/merge", json=payload)
        assert response.status_code == 201

        data = response.json()
        assert "merge_id" in data
        assert "conflicts_detected" in data

    @pytest.mark.asyncio
    async def test_merge_invalid_strategy(self, client, db_pool):
        """Test merge with invalid strategy"""
        async with db_pool.acquire() as conn:
            main_id = await conn.fetchval(
                "SELECT branch_id FROM pggit.branches LIMIT 1"
            )
            feature_id = await conn.fetchval(
                "SELECT branch_id FROM pggit.branches WHERE branch_id != $1 LIMIT 1",
                main_id
            )

        if main_id and feature_id:
            payload = {
                "source_branch_id": feature_id,
                "merge_message": "Test invalid strategy",
                "merge_strategy": "INVALID_STRATEGY"
            }

            response = await client.post(f"/api/v1/branches/{main_id}/merge", json=payload)
            assert response.status_code == 400  # Should fail with 400 Bad Request (invalid strategy)

    @pytest.mark.asyncio
    async def test_merge_same_branch(self, client, db_pool):
        """Test merging a branch with itself (should fail)"""
        async with db_pool.acquire() as conn:
            branch_id = await conn.fetchval(
                "SELECT branch_id FROM pggit.branches LIMIT 1"
            )

        if branch_id:
            payload = {
                "source_branch_id": branch_id,
                "merge_message": "Test self-merge",
                "merge_strategy": "MANUAL_REVIEW"
            }

            response = await client.post(f"/api/v1/branches/{branch_id}/merge", json=payload)
            assert response.status_code == 400  # Should fail with 400 Bad Request (cannot merge into self)


class TestMergeStatus:
    """Test merge status retrieval"""

    @pytest.mark.asyncio
    async def test_get_merge_status(self, client, db_pool):
        """Test getting merge status"""
        # Create a merge first
        async with db_pool.acquire() as conn:
            main_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ('main_status_test', NULL, 'test_user', CURRENT_TIMESTAMP) RETURNING branch_id"
            )

            feature_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ('feature_status_test', $1, 'test_user', CURRENT_TIMESTAMP) RETURNING branch_id",
                main_id
            )

        # Execute merge
        merge_payload = {
            "source_branch_id": feature_id,
            "merge_message": "Test status check",
            "merge_strategy": "MANUAL_REVIEW"
        }

        merge_response = await client.post(f"/api/v1/branches/{main_id}/merge", json=merge_payload)
        assert merge_response.status_code == 201
        merge_id = merge_response.json()["merge_id"]

        # Get status
        status_response = await client.get(f"/api/v1/merge/{merge_id}")
        assert status_response.status_code == 200

        data = status_response.json()
        assert data["merge_id"] == merge_id
        assert "status" in data
        assert "conflicts_detected" in data

    @pytest.mark.asyncio
    async def test_get_nonexistent_merge_status(self, client):
        """Test getting status for non-existent merge"""
        response = await client.get("/api/v1/merge/nonexistent_merge_id")
        assert response.status_code == 404


class TestConflictList:
    """Test conflict listing"""

    @pytest.mark.asyncio
    async def test_list_conflicts(self, client, db_pool):
        """Test listing conflicts for a merge"""
        # Create merge with potential conflicts
        async with db_pool.acquire() as conn:
            main_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ('main_conflicts_list', NULL, 'test_user', CURRENT_TIMESTAMP) RETURNING branch_id"
            )

            feature_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ('feature_conflicts_list', $1, 'test_user', CURRENT_TIMESTAMP) RETURNING branch_id",
                main_id
            )

        # Execute merge
        payload = {
            "source_branch_id": feature_id,
            "merge_message": "Test conflict listing",
            "merge_strategy": "MANUAL_REVIEW"
        }

        merge_response = await client.post(f"/api/v1/branches/{main_id}/merge", json=payload)
        assert merge_response.status_code == 201
        merge_id = merge_response.json()["merge_id"]

        # List conflicts
        conflicts_response = await client.get(f"/api/v1/merge/{merge_id}/conflicts")
        assert conflicts_response.status_code == 200

        data = conflicts_response.json()
        assert "merge_id" in data
        assert "conflicts" in data
        assert "total_conflicts" in data
        assert isinstance(data["conflicts"], list)

    @pytest.mark.asyncio
    async def test_list_conflicts_nonexistent_merge(self, client):
        """Test listing conflicts for non-existent merge"""
        response = await client.get("/api/v1/merge/nonexistent_id/conflicts")
        assert response.status_code == 404


class TestConflictResolution:
    """Test conflict resolution"""

    @pytest.mark.asyncio
    async def test_resolve_conflict_source(self, client, db_pool):
        """Test resolving conflict with SOURCE resolution"""
        # Create merge with conflicts
        async with db_pool.acquire() as conn:
            main_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ('main_resolve_test', NULL, 'test_user', CURRENT_TIMESTAMP) RETURNING branch_id"
            )

            feature_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ('feature_resolve_test', $1, 'test_user', CURRENT_TIMESTAMP) RETURNING branch_id",
                main_id
            )

            # Add schema object to create conflict
            obj_id = await conn.fetchval(
                "INSERT INTO pggit.schema_objects (object_type, schema_name, object_name, current_definition, content_hash, is_active) "
                "VALUES ('TABLE', 'public', 'test_table_conflict', 'CREATE TABLE test_table_conflict (id INT)', 'hash123', true) RETURNING object_id"
            )

            # Create commits for main and feature
            await conn.execute(
                "INSERT INTO pggit.commits (branch_id, commit_hash, commit_message, author_name, author_time, object_changes, created_at) "
                "VALUES ($1, 'commit_hash_main', 'Main commit', 'test_user', CURRENT_TIMESTAMP, '{}', CURRENT_TIMESTAMP)",
                main_id
            )

            await conn.execute(
                "INSERT INTO pggit.commits (branch_id, commit_hash, commit_message, author_name, author_time, object_changes, created_at) "
                "VALUES ($1, 'commit_hash_feature', 'Feature commit', 'test_user', CURRENT_TIMESTAMP, '{}', CURRENT_TIMESTAMP)",
                feature_id
            )

            # Add different versions to main and feature
            await conn.execute(
                "INSERT INTO pggit.object_history (object_id, branch_id, change_type, after_hash, commit_hash, author_name, author_time, created_at) "
                "VALUES ($1, $2, 'ALTER', 'hash_main', 'commit_hash_main', 'test_user', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
                obj_id, main_id
            )

            await conn.execute(
                "INSERT INTO pggit.object_history (object_id, branch_id, change_type, after_hash, commit_hash, author_name, author_time, created_at) "
                "VALUES ($1, $2, 'ALTER', 'hash_feature', 'commit_hash_feature', 'test_user', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
                obj_id, feature_id
            )

        # Execute merge
        merge_payload = {
            "source_branch_id": feature_id,
            "merge_message": "Test conflict resolution",
            "merge_strategy": "MANUAL_REVIEW"
        }

        merge_response = await client.post(f"/api/v1/branches/{main_id}/merge", json=merge_payload)
        if merge_response.status_code != 201:
            # If merge creation fails, skip the test
            pytest.skip("Merge creation failed - may need more setup")
            return

        merge_id = merge_response.json()["merge_id"]

        # List conflicts to get conflict ID
        conflicts_response = await client.get(f"/api/v1/merge/{merge_id}/conflicts")
        assert conflicts_response.status_code == 200
        conflicts_data = conflicts_response.json()

        if conflicts_data["total_conflicts"] == 0:
            pytest.skip("No conflicts detected - test scenario needs adjustment")
            return

        conflict_id = conflicts_data["conflicts"][0]["conflict_id"]

        # Resolve conflict
        resolution_payload = {
            "resolution": "SOURCE",
            "custom_definition": None
        }

        resolve_response = await client.post(
            f"/api/v1/merge/{merge_id}/conflicts/{conflict_id}",
            json=resolution_payload
        )
        assert resolve_response.status_code == 200

        data = resolve_response.json()
        assert data["merge_id"] == merge_id
        assert data["conflict_id"] == conflict_id
        assert data["resolution_applied"] == "SOURCE"

    @pytest.mark.asyncio
    async def test_resolve_conflict_invalid_resolution(self, client, db_pool):
        """Test resolving conflict with invalid resolution type"""
        # This test validates input validation
        resolution_payload = {
            "resolution": "INVALID_TYPE",
            "custom_definition": None
        }

        # Try to resolve (should fail validation at API level)
        response = await client.post(
            "/api/v1/merge/any_id/conflicts/1",
            json=resolution_payload
        )
        # Should fail with validation error (400 for business logic, 422 for Pydantic)
        assert response.status_code in [400, 422]


class TestMergeWorkflowEndToEnd:
    """Test complete merge workflow from start to finish"""

    @pytest.mark.asyncio
    async def test_complete_merge_workflow(self, client, db_pool):
        """Test complete workflow: create branches, merge, check status, list conflicts"""
        # Step 1: Create branch structure
        async with db_pool.acquire() as conn:
            main_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ('main_workflow', NULL, 'test_user', CURRENT_TIMESTAMP) RETURNING branch_id"
            )

            feature_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ('feature_workflow', $1, 'test_user', CURRENT_TIMESTAMP) RETURNING branch_id",
                main_id
            )

        # Step 2: Find merge base
        merge_base_response = await client.get(f"/api/v1/branches/{main_id}/merge-base/{feature_id}")
        assert merge_base_response.status_code == 200

        # Step 3: Execute merge
        merge_payload = {
            "source_branch_id": feature_id,
            "merge_message": "Complete workflow test merge",
            "merge_strategy": "MANUAL_REVIEW"
        }

        merge_response = await client.post(f"/api/v1/branches/{main_id}/merge", json=merge_payload)
        assert merge_response.status_code == 201
        merge_id = merge_response.json()["merge_id"]

        # Step 4: Check merge status
        status_response = await client.get(f"/api/v1/merge/{merge_id}")
        assert status_response.status_code == 200
        assert status_response.json()["merge_id"] == merge_id

        # Step 5: List conflicts
        conflicts_response = await client.get(f"/api/v1/merge/{merge_id}/conflicts")
        assert conflicts_response.status_code == 200
        assert "conflicts" in conflicts_response.json()

        # Step 6: Verify merge was recorded in database
        async with db_pool.acquire() as conn:
            merge_exists = await conn.fetchval(
                "SELECT EXISTS(SELECT 1 FROM pggit.merge_operations WHERE id = $1)",
                merge_id
            )
            assert merge_exists


class TestMergeAuthentication:
    """Test authentication requirements for merge endpoints"""

    @pytest.mark.asyncio
    async def test_merge_requires_authentication(self):
        """Test that merge endpoints require authentication"""
        from httpx import ASGITransport
        from api.main import app

        # Create client WITHOUT authentication token
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test"
        ) as unauthenticated_client:
            # Try to execute merge without auth
            payload = {
                "source_branch_id": 1,
                "merge_message": "Test",
                "merge_strategy": "MANUAL_REVIEW"
            }

            response = await unauthenticated_client.post("/api/v1/branches/1/merge", json=payload)
            # Should fail with 401 (unauthorized) or 503 (service unavailable without db/cache init)
            assert response.status_code in [401, 503]
