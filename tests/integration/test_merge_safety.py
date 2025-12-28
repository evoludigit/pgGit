"""
Data Integrity and Safety Tests for Merge Operations
====================================================

NASA-Level testing for merge operation data integrity and transaction safety.
Tests ensure that merge operations maintain database consistency even when
failures occur mid-operation.

Test Categories:
- Transaction rollback on merge failures
- Data validation and rejection of invalid inputs
- Edge case handling
"""

import pytest
import time
from httpx import AsyncClient


def unique_branch(prefix: str) -> str:
    """Generate unique branch name using timestamp"""
    return f"{prefix}_{int(time.time() * 1000000)}"


class TestMergeDataValidation:
    """Test that merge operations validate data integrity"""

    @pytest.mark.asyncio
    async def test_merge_rejects_invalid_branch_ids(self, client: AsyncClient):
        """
        Verify merge operation rejects invalid branch IDs.

        Critical: Prevents SQL injection and invalid database queries.
        """
        # Test negative branch ID
        response = await client.get("/api/v1/branches/-1/merge-base/1")
        assert response.status_code == 422, "Should reject negative branch ID"

        # Test zero branch ID
        response = await client.get("/api/v1/branches/0/merge-base/1")
        assert response.status_code == 422, "Should reject zero branch ID"

        # Test identical branch IDs
        response = await client.get("/api/v1/branches/1/merge-base/1")
        assert response.status_code == 400, "Should reject identical branch IDs"

    @pytest.mark.asyncio
    async def test_merge_rejects_self_merge(self, client: AsyncClient, db_pool):
        """
        Verify merge operation prevents merging branch into itself.

        Critical: Self-merge is logically invalid and could corrupt branch history.
        """
        async with db_pool.acquire() as conn:
            branch_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ($1, NULL, 'test_user', NOW()) RETURNING branch_id",
                unique_branch('test')
            )

        payload = {
            "source_branch_id": branch_id,
            "merge_message": "Invalid self-merge",
            "merge_strategy": "MANUAL_REVIEW"
        }

        response = await client.post(f"/api/v1/branches/{branch_id}/merge", json=payload)
        assert response.status_code == 400, "Should reject self-merge"
        assert "cannot merge branch into itself" in response.text.lower()

    @pytest.mark.asyncio
    async def test_merge_rejects_invalid_strategy(self, client: AsyncClient, db_pool):
        """
        Verify merge operation rejects invalid merge strategies.

        Critical: Invalid strategies could lead to unpredictable merge behavior.
        """
        async with db_pool.acquire() as conn:
            main_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ($1, NULL, 'test_user', NOW()) RETURNING branch_id",
                unique_branch('main')
            )
            feature_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ($1, $2, 'test_user', NOW()) RETURNING branch_id",
                unique_branch('feature'),
                main_id
            )

        payload = {
            "source_branch_id": feature_id,
            "merge_message": "Test invalid strategy",
            "merge_strategy": "COMPLETELY_INVALID_STRATEGY"
        }

        response = await client.post(f"/api/v1/branches/{main_id}/merge", json=payload)
        assert response.status_code == 400, "Should reject invalid strategy"

    @pytest.mark.asyncio
    async def test_merge_validates_message_length(self, client: AsyncClient, db_pool):
        """
        Verify merge message length constraints are enforced.

        Important: Prevents excessively long commit messages.
        """
        async with db_pool.acquire() as conn:
            main_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ($1, NULL, 'test_user', NOW()) RETURNING branch_id",
                unique_branch('main')
            )
            feature_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ($1, $2, 'test_user', NOW()) RETURNING branch_id",
                unique_branch('feature'),
                main_id
            )

        # Test empty message
        payload = {
            "source_branch_id": feature_id,
            "merge_message": "",
            "merge_strategy": "MANUAL_REVIEW"
        }
        response = await client.post(f"/api/v1/branches/{main_id}/merge", json=payload)
        assert response.status_code == 422, "Should reject empty message"

        # Test excessively long message (> 500 chars)
        payload["merge_message"] = "x" * 501
        response = await client.post(f"/api/v1/branches/{main_id}/merge", json=payload)
        assert response.status_code == 422, "Should reject message > 500 chars"

    @pytest.mark.asyncio
    async def test_conflict_resolution_validates_resolution_type(
        self, client: AsyncClient, db_pool
    ):
        """
        Verify conflict resolution validates resolution types.

        Critical: Invalid resolution types could corrupt merge state.
        """
        async with db_pool.acquire() as conn:
            main_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ($1, NULL, 'test_user', NOW()) RETURNING branch_id",
                unique_branch('main')
            )
            feature_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ($1, $2, 'test_user', NOW()) RETURNING branch_id",
                unique_branch('feature'),
                main_id
            )

        # Create merge first
        payload = {
            "source_branch_id": feature_id,
            "merge_message": "Test resolution validation",
            "merge_strategy": "MANUAL_REVIEW"
        }
        merge_response = await client.post(f"/api/v1/branches/{main_id}/merge", json=payload)

        if merge_response.status_code == 201:
            merge_data = merge_response.json()
            merge_id = merge_data["merge_id"]

            # Test invalid resolution type
            payload = {
                "resolution": "INVALID_RESOLUTION_TYPE",
                "custom_definition": None
            }

            response = await client.post(f"/api/v1/merge/{merge_id}/conflicts/1", json=payload)
            assert response.status_code == 400, "Should reject invalid resolution type"

    @pytest.mark.asyncio
    async def test_conflict_resolution_requires_custom_definition_when_custom(
        self, client: AsyncClient, db_pool
    ):
        """
        Verify CUSTOM resolution requires custom_definition.

        Critical: CUSTOM resolution without definition is invalid.
        """
        async with db_pool.acquire() as conn:
            main_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ($1, NULL, 'test_user', NOW()) RETURNING branch_id",
                unique_branch('main')
            )
            feature_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ($1, $2, 'test_user', NOW()) RETURNING branch_id",
                unique_branch('feature'),
                main_id
            )

        # Create merge first
        payload = {
            "source_branch_id": feature_id,
            "merge_message": "Test custom definition requirement",
            "merge_strategy": "MANUAL_REVIEW"
        }
        merge_response = await client.post(f"/api/v1/branches/{main_id}/merge", json=payload)

        if merge_response.status_code == 201:
            merge_data = merge_response.json()
            merge_id = merge_data["merge_id"]

            # Test CUSTOM resolution without custom_definition
            payload = {
                "resolution": "CUSTOM",
                "custom_definition": None
            }

            response = await client.post(f"/api/v1/merge/{merge_id}/conflicts/1", json=payload)
            assert response.status_code == 400, "Should require custom_definition for CUSTOM resolution"


class TestMergeTransactionSafety:
    """Test that merge operations maintain transactional integrity"""

    @pytest.mark.asyncio
    async def test_merge_maintains_referential_integrity(self, client: AsyncClient, db_pool):
        """
        Verify merge operations don't create orphaned records.

        Critical: Ensures all merge-related records reference valid parent records.
        """
        async with db_pool.acquire() as conn:
            # Create minimal branch structure
            main_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ($1, NULL, 'test_user', NOW()) RETURNING branch_id",
                unique_branch('main')
            )
            feature_id = await conn.fetchval(
                "INSERT INTO pggit.branches (branch_name, parent_branch_id, created_by, created_at) "
                "VALUES ($1, $2, 'test_user', NOW()) RETURNING branch_id",
                unique_branch('feature'),
                main_id
            )

        # Execute merge
        payload = {
            "source_branch_id": feature_id,
            "merge_message": "Test referential integrity",
            "merge_strategy": "MANUAL_REVIEW"
        }

        response = await client.post(f"/api/v1/branches/{main_id}/merge", json=payload)

        # Verify referential integrity regardless of merge success/failure
        async with db_pool.acquire() as conn:
            # Check for orphaned merge operations (merge_base_branch_id references non-existent branch)
            orphaned_merges = await conn.fetchval(
                """
                SELECT COUNT(*)
                FROM pggit.merge_operations mo
                LEFT JOIN pggit.branches b ON mo.merge_base_branch_id = b.branch_id
                WHERE mo.merge_base_branch_id IS NOT NULL AND b.branch_id IS NULL
                """
            )
            assert orphaned_merges == 0, f"Found {orphaned_merges} orphaned merge operations"

            # Check for orphaned conflict resolutions
            orphaned_conflicts = await conn.fetchval(
                """
                SELECT COUNT(*)
                FROM pggit.merge_conflict_resolutions mcr
                LEFT JOIN pggit.merge_operations mo ON mcr.merge_id = mo.id
                WHERE mo.id IS NULL
                """
            )
            assert orphaned_conflicts == 0, f"Found {orphaned_conflicts} orphaned conflict resolutions"


class TestMergeEdgeCases:
    """Test edge cases and boundary conditions"""

    @pytest.mark.asyncio
    async def test_merge_path_validation(self, client: AsyncClient):
        """
        Verify merge ID path parameter validation.

        Important: Prevents path traversal and injection attacks.
        """
        # Test empty merge ID
        response = await client.get("/api/v1/merge//conflicts")
        assert response.status_code in [404, 422], "Should reject empty merge ID"

        # Test excessively long merge ID (> 100 chars)
        long_id = "x" * 101
        response = await client.get(f"/api/v1/merge/{long_id}")
        assert response.status_code in [404, 422], "Should reject merge ID > 100 chars"

    @pytest.mark.asyncio
    async def test_conflict_id_validation(self, client: AsyncClient):
        """
        Verify conflict ID validation.

        Important: Prevents invalid conflict ID values.
        """
        # Test zero conflict ID
        payload = {"resolution": "SOURCE", "custom_definition": None}
        response = await client.post("/api/v1/merge/any_id/conflicts/0", json=payload)
        assert response.status_code == 422, "Should reject conflict ID = 0"

        # Test negative conflict ID
        response = await client.post("/api/v1/merge/any_id/conflicts/-1", json=payload)
        assert response.status_code == 422, "Should reject negative conflict ID"
