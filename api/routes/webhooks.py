"""
Webhook REST API Endpoints
==========================

REST endpoints for webhook management.
Endpoints: GET, POST, PUT, DELETE webhooks with full CRUD operations.

Features:
- JWT authentication
- Response caching (60-second TTL)
- Pagination support
- Error handling
- Database connection pooling
"""

import logging
from typing import Optional
from datetime import datetime

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status, Query
from pydantic import BaseModel, Field

from services.dependencies import get_current_user, get_db, rate_limit_dependency
from services.cache import get_cache

logger = logging.getLogger(__name__)

router = APIRouter()


# ===== PYDANTIC MODELS =====

class WebhookCreate(BaseModel):
    """Model for creating a new webhook"""
    name: str = Field(..., min_length=1, max_length=255)
    url: str = Field(..., min_length=10, max_length=2048)
    events: list[str] = Field(default=["*"], description="Events to subscribe to")
    active: bool = Field(default=True)
    description: Optional[str] = Field(None, max_length=1000)

    class Config:
        json_schema_extra = {
            "example": {
                "name": "My Webhook",
                "url": "https://example.com/webhook",
                "events": ["anomaly_detected", "performance_degradation"],
                "active": True,
                "description": "Sends alerts to our monitoring system"
            }
        }


class WebhookUpdate(BaseModel):
    """Model for updating a webhook"""
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    url: Optional[str] = Field(None, min_length=10, max_length=2048)
    events: Optional[list[str]] = None
    active: Optional[bool] = None
    description: Optional[str] = Field(None, max_length=1000)


class WebhookResponse(BaseModel):
    """Model for webhook response"""
    id: int
    name: str
    url: str
    events: list[str]
    active: bool
    description: Optional[str]
    created_at: datetime
    updated_at: datetime
    health_status: Optional[str]
    total_deliveries: int = 0
    successful_deliveries: int = 0


class WebhookListResponse(BaseModel):
    """Model for paginated webhook list response"""
    webhooks: list[WebhookResponse]
    total: int
    page: int
    page_size: int
    pages: int


# ===== ENDPOINTS =====

@router.get("/webhooks", response_model=WebhookListResponse, tags=["Webhooks"])
async def list_webhooks(
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100)
):
    """
    List all webhooks with pagination.

    Query Parameters:
    - page: Page number (1-indexed)
    - page_size: Items per page (1-100)

    Returns:
        List of webhooks with pagination metadata
    """
    cache = await get_cache()
    cache_key = f"webhooks:list:{page}:{page_size}"

    # Try cache first
    cached_result = await cache.get(cache_key)
    if cached_result:
        logger.debug(f"Cache hit for {cache_key}")
        return cached_result

    try:
        # Get total count
        total_result = await db.fetchval("SELECT COUNT(*) FROM pggit.webhooks")
        total = total_result or 0

        # Calculate pagination
        offset = (page - 1) * page_size
        pages = (total + page_size - 1) // page_size

        # Fetch webhooks
        webhooks_data = await db.fetch(
            """
            SELECT
                w.id, w.name, w.url, w.events, w.active,
                w.description, w.created_at, w.updated_at,
                COALESCE(whm.health_status, 'UNKNOWN') as health_status,
                COALESCE(whm.total_deliveries, 0) as total_deliveries,
                COALESCE(whm.successful_deliveries, 0) as successful_deliveries
            FROM pggit.webhooks w
            LEFT JOIN pggit.webhook_health_metrics whm ON w.id = whm.webhook_id
            ORDER BY w.created_at DESC
            LIMIT $1 OFFSET $2
            """,
            page_size,
            offset
        )

        webhooks = [
            WebhookResponse(
                id=row['id'],
                name=row['name'],
                url=row['url'],
                events=row['events'] or [],
                active=row['active'],
                description=row['description'],
                created_at=row['created_at'],
                updated_at=row['updated_at'],
                health_status=row['health_status'],
                total_deliveries=row['total_deliveries'],
                successful_deliveries=row['successful_deliveries']
            )
            for row in webhooks_data
        ]

        response = WebhookListResponse(
            webhooks=webhooks,
            total=total,
            page=page,
            page_size=page_size,
            pages=pages
        )

        # Cache for 60 seconds
        await cache.set(cache_key, response, ttl_seconds=60)
        return response

    except asyncpg.PostgresError as e:
        logger.error(f"Database error listing webhooks: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list webhooks"
        )


@router.get("/webhooks/{webhook_id}", response_model=WebhookResponse, tags=["Webhooks"])
async def get_webhook(
    webhook_id: int,
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency)
):
    """
    Get webhook details by ID.

    Path Parameters:
    - webhook_id: ID of the webhook

    Returns:
        Webhook details with health metrics
    """
    cache = await get_cache()
    cache_key = f"webhook:{webhook_id}"

    # Try cache first
    cached_result = await cache.get(cache_key)
    if cached_result:
        return cached_result

    try:
        webhook_data = await db.fetchrow(
            """
            SELECT
                w.id, w.name, w.url, w.events, w.active,
                w.description, w.created_at, w.updated_at,
                COALESCE(whm.health_status, 'UNKNOWN') as health_status,
                COALESCE(whm.total_deliveries, 0) as total_deliveries,
                COALESCE(whm.successful_deliveries, 0) as successful_deliveries
            FROM pggit.webhooks w
            LEFT JOIN pggit.webhook_health_metrics whm ON w.id = whm.webhook_id
            WHERE w.id = $1
            """,
            webhook_id
        )

        if not webhook_data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Webhook {webhook_id} not found"
            )

        response = WebhookResponse(
            id=webhook_data['id'],
            name=webhook_data['name'],
            url=webhook_data['url'],
            events=webhook_data['events'] or [],
            active=webhook_data['active'],
            description=webhook_data['description'],
            created_at=webhook_data['created_at'],
            updated_at=webhook_data['updated_at'],
            health_status=webhook_data['health_status'],
            total_deliveries=webhook_data['total_deliveries'],
            successful_deliveries=webhook_data['successful_deliveries']
        )

        # Cache for 60 seconds
        await cache.set(cache_key, response, ttl_seconds=60)
        return response

    except HTTPException:
        raise
    except asyncpg.PostgresError as e:
        logger.error(f"Database error fetching webhook {webhook_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch webhook"
        )


@router.post("/webhooks", response_model=WebhookResponse, status_code=status.HTTP_201_CREATED, tags=["Webhooks"])
async def create_webhook(
    webhook: WebhookCreate,
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency)
):
    """
    Create a new webhook.

    Request Body:
    - name: Webhook name
    - url: Target URL for webhook delivery
    - events: List of event types to subscribe to
    - active: Whether webhook is active
    - description: Optional description

    Returns:
        Created webhook with ID and metadata
    """
    try:
        webhook_data = await db.fetchrow(
            """
            INSERT INTO pggit.webhooks (name, url, events, active, description, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            RETURNING id, name, url, events, active, description, created_at, updated_at
            """,
            webhook.name,
            webhook.url,
            webhook.events,
            webhook.active,
            webhook.description
        )

        # Invalidate list cache
        cache = await get_cache()
        await cache.delete("webhooks:list:*")

        logger.info(f"Created webhook: {webhook_data['id']}")

        return WebhookResponse(
            id=webhook_data['id'],
            name=webhook_data['name'],
            url=webhook_data['url'],
            events=webhook_data['events'] or [],
            active=webhook_data['active'],
            description=webhook_data['description'],
            created_at=webhook_data['created_at'],
            updated_at=webhook_data['updated_at'],
            health_status="NEW",
            total_deliveries=0,
            successful_deliveries=0
        )

    except asyncpg.PostgresError as e:
        logger.error(f"Database error creating webhook: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create webhook"
        )


@router.put("/webhooks/{webhook_id}", response_model=WebhookResponse, tags=["Webhooks"])
async def update_webhook(
    webhook_id: int,
    webhook: WebhookUpdate,
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency)
):
    """
    Update an existing webhook.

    Path Parameters:
    - webhook_id: ID of the webhook to update

    Request Body:
    - All fields are optional; only provided fields are updated

    Returns:
        Updated webhook with new metadata
    """
    try:
        # Build update query dynamically
        update_fields = []
        update_values = []
        param_count = 1

        if webhook.name is not None:
            update_fields.append(f"name = ${param_count}")
            update_values.append(webhook.name)
            param_count += 1

        if webhook.url is not None:
            update_fields.append(f"url = ${param_count}")
            update_values.append(webhook.url)
            param_count += 1

        if webhook.events is not None:
            update_fields.append(f"events = ${param_count}")
            update_values.append(webhook.events)
            param_count += 1

        if webhook.active is not None:
            update_fields.append(f"active = ${param_count}")
            update_values.append(webhook.active)
            param_count += 1

        if webhook.description is not None:
            update_fields.append(f"description = ${param_count}")
            update_values.append(webhook.description)
            param_count += 1

        if not update_fields:
            # No fields to update, fetch current webhook
            return await get_webhook(webhook_id, db, user)

        update_fields.append(f"updated_at = CURRENT_TIMESTAMP")

        query = f"""
            UPDATE pggit.webhooks
            SET {', '.join(update_fields)}
            WHERE id = ${param_count}
            RETURNING id, name, url, events, active, description, created_at, updated_at
        """

        update_values.append(webhook_id)

        webhook_data = await db.fetchrow(query, *update_values)

        if not webhook_data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Webhook {webhook_id} not found"
            )

        # Invalidate cache
        cache = await get_cache()
        await cache.delete(f"webhook:{webhook_id}")
        await cache.delete("webhooks:list:*")

        logger.info(f"Updated webhook: {webhook_id}")

        return WebhookResponse(
            id=webhook_data['id'],
            name=webhook_data['name'],
            url=webhook_data['url'],
            events=webhook_data['events'] or [],
            active=webhook_data['active'],
            description=webhook_data['description'],
            created_at=webhook_data['created_at'],
            updated_at=webhook_data['updated_at'],
            health_status="UPDATED"
        )

    except HTTPException:
        raise
    except asyncpg.PostgresError as e:
        logger.error(f"Database error updating webhook {webhook_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update webhook"
        )


@router.delete("/webhooks/{webhook_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["Webhooks"])
async def delete_webhook(
    webhook_id: int,
    db: asyncpg.Connection = Depends(get_db),
    user: dict = Depends(get_current_user),
    _: dict = Depends(rate_limit_dependency)
):
    """
    Delete a webhook.

    Path Parameters:
    - webhook_id: ID of the webhook to delete

    Returns:
        204 No Content on success
    """
    try:
        result = await db.execute(
            "DELETE FROM pggit.webhooks WHERE id = $1",
            webhook_id
        )

        # Check if webhook existed
        if result == "DELETE 0":
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Webhook {webhook_id} not found"
            )

        # Invalidate cache
        cache = await get_cache()
        await cache.delete(f"webhook:{webhook_id}")
        await cache.delete("webhooks:list:*")

        logger.info(f"Deleted webhook: {webhook_id}")

    except HTTPException:
        raise
    except asyncpg.PostgresError as e:
        logger.error(f"Database error deleting webhook {webhook_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete webhook"
        )
