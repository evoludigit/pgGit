# Phase 8 Week 2 API Documentation

## Overview

Phase 8 Week 2 introduces a comprehensive FastAPI-based REST API with WebSocket support for real-time updates, intelligent caching strategy, and production-ready infrastructure for the pggit system.

## Architecture

### Components

1. **FastAPI Application** (`api/main.py`)
   - ASGI-compatible async web framework
   - OpenAPI/Swagger documentation
   - Health check endpoints
   - Request/response validation

2. **REST Endpoints**
   - Webhook management (`/api/v1/webhooks`)
   - Alert management (`/api/v1/alerts`)
   - Cache operations (`/api/v1/cache`)
   - Dashboard views (`/api/v1/dashboard`)
   - Merge operations (`/api/v1/merge`)

3. **WebSocket Endpoints**
   - Real-time alert notifications (`/api/v1/ws/alerts`)
   - Bidirectional communication
   - Automatic reconnection support

4. **Caching Layer**
   - Request-level caching
   - Automatic cache warming
   - Intelligent cache invalidation

## REST API Endpoints

### Webhooks

#### List Webhooks
```
GET /api/v1/webhooks
```

**Response:**
```json
{
  "items": [
    {
      "id": 1,
      "name": "production-alerts",
      "url": "https://example.com/webhook",
      "is_active": true,
      "created_at": "2024-01-01T00:00:00Z"
    }
  ],
  "total": 1
}
```

#### Create Webhook
```
POST /api/v1/webhooks
Content-Type: application/json

{
  "name": "production-alerts",
  "url": "https://example.com/webhook",
  "description": "Production alert notifications",
  "is_active": true,
  "retry_policy": {
    "max_retries": 3,
    "backoff_base": 2,
    "max_backoff": 3600
  },
  "timeout_seconds": 30,
  "ssl_verify": true
}
```

**Response:** `201 Created`
```json
{
  "id": 1,
  "name": "production-alerts",
  "url": "https://example.com/webhook",
  "is_active": true
}
```

#### Get Webhook Details
```
GET /api/v1/webhooks/{webhook_id}
```

**Response:** `200 OK`
```json
{
  "id": 1,
  "name": "production-alerts",
  "url": "https://example.com/webhook",
  "description": "Production alert notifications",
  "is_active": true,
  "created_at": "2024-01-01T00:00:00Z",
  "last_used_at": "2024-01-15T10:30:00Z"
}
```

#### Update Webhook
```
PUT /api/v1/webhooks/{webhook_id}
Content-Type: application/json

{
  "description": "Updated description",
  "is_active": false
}
```

**Response:** `200 OK`

#### Delete Webhook
```
DELETE /api/v1/webhooks/{webhook_id}
```

**Response:** `204 No Content`

### Alerts

#### List Alerts
```
GET /api/v1/alerts?status=pending&limit=20&offset=0
```

**Query Parameters:**
- `status` (optional): pending, acknowledged, resolved
- `severity` (optional): INFO, WARNING, CRITICAL
- `limit` (optional): Default 20, max 100
- `offset` (optional): Default 0

**Response:**
```json
{
  "items": [
    {
      "id": 1,
      "operation_type": "commit",
      "severity": "WARNING",
      "message": "Commit operation exceeding P95 latency",
      "status": "pending",
      "created_at": "2024-01-15T10:30:00Z"
    }
  ],
  "total": 1
}
```

#### Get Alert Details
```
GET /api/v1/alerts/{alert_id}
```

**Response:** `200 OK`
```json
{
  "id": 1,
  "operation_type": "commit",
  "severity": "WARNING",
  "message": "Commit operation exceeding P95 latency",
  "status": "pending",
  "context": {
    "p99_ms": 450,
    "baseline_ms": 300,
    "affected_operations": 150
  },
  "created_at": "2024-01-15T10:30:00Z"
}
```

#### Acknowledge Alerts
```
POST /api/v1/alerts/acknowledge
Content-Type: application/json

{
  "alert_ids": [1, 2, 3]
}
```

**Response:** `200 OK`
```json
{
  "acknowledged": 3,
  "failed": 0
}
```

### Cache Management

#### Get Cache Statistics
```
GET /api/v1/cache/stats
```

**Response:** `200 OK`
```json
{
  "hit_rate": 0.87,
  "total_requests": 1000,
  "cache_hits": 870,
  "cache_misses": 130,
  "evicted_entries": 5,
  "current_size_bytes": 52428800,
  "max_size_bytes": 104857600
}
```

#### Warm Cache
```
POST /api/v1/cache/warm
```

**Response:** `200 OK`
```json
{
  "status": "success",
  "warmed_entries": 45,
  "duration_ms": 234,
  "timestamp": "2024-01-15T10:30:00Z"
}
```

#### Invalidate Cache
```
POST /api/v1/cache/invalidate
Content-Type: application/json

{
  "keys": ["webhooks_list", "alerts_summary"],
  "pattern": null
}
```

**Response:** `200 OK`
```json
{
  "invalidated": 2,
  "total_entries": 45
}
```

### Health Checks

#### Basic Health Check
```
GET /health
```

**Response:** `200 OK`
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

#### Deep Health Check
```
GET /health/deep
```

**Response:** `200 OK`
```json
{
  "status": "healthy",
  "database": {
    "status": "connected",
    "response_time_ms": 5
  },
  "cache": {
    "status": "operational",
    "hit_rate": 0.87
  },
  "webhooks": {
    "status": "operational",
    "active_count": 12,
    "failed_count": 0
  }
}
```

## WebSocket Endpoints

### Real-time Alert Notifications

**Connection:**
```
WebSocket /api/v1/ws/alerts
```

**Authentication:**
- Optional bearer token or session cookie

**Messages Sent by Server:**

```json
{
  "type": "alert",
  "data": {
    "id": 1,
    "operation_type": "commit",
    "severity": "WARNING",
    "message": "Commit operation exceeding P95 latency",
    "timestamp": "2024-01-15T10:30:00Z"
  }
}
```

```json
{
  "type": "system_status",
  "data": {
    "cache_hit_rate": 0.87,
    "active_webhooks": 12,
    "pending_deliveries": 3
  }
}
```

**Messages Received from Client:**

```json
{
  "type": "subscribe",
  "channels": ["critical_alerts", "performance_warnings"]
}
```

```json
{
  "type": "ping"
}
```

## Error Responses

All error responses follow this format:

```json
{
  "detail": "Error message",
  "error_code": "RESOURCE_NOT_FOUND",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

### Common HTTP Status Codes

- **400 Bad Request**: Invalid request parameters
- **401 Unauthorized**: Missing or invalid authentication
- **403 Forbidden**: Insufficient permissions
- **404 Not Found**: Resource does not exist
- **409 Conflict**: Resource already exists or state conflict
- **429 Too Many Requests**: Rate limit exceeded
- **500 Internal Server Error**: Server error
- **503 Service Unavailable**: Service temporarily unavailable

## Authentication

Currently, the API supports:
- No authentication (development mode)
- Bearer token (future)
- Session cookies (future)

For production, implement OAuth2/JWT authentication.

## Rate Limiting

- Default: 100 requests per minute per IP
- Webhooks: 1000 requests per hour per webhook
- Custom limits available for premium tiers

Headers:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 87
X-RateLimit-Reset: 1234567890
```

## Caching Strategy

### Cache Warming

On startup, the API pre-loads frequently accessed data:
- Webhook list (TTL: 2 minutes)
- Alert summary (TTL: 1 minute)
- Dashboard metrics (TTL: 5 minutes)

### Cache Invalidation

Automatic invalidation triggers:
- Webhook creation/update/deletion → invalidate `webhooks_list`
- Alert acknowledgment → invalidate `alerts_summary`
- Cache metrics update → invalidate `cache_stats`

Manual invalidation:
```
POST /api/v1/cache/invalidate
```

### Merge Operations

#### Initiate Merge
```
POST /api/v1/merge/{target_branch_id}/merge
Content-Type: application/json

{
  "source_branch_id": 101,
  "merge_message": "Merge feature/user-auth into main",
  "merge_strategy": "auto",
  "base_branch_id": null
}
```

**Path Parameters:**
- `target_branch_id` (required): Branch to merge INTO

**Request Body:**
- `source_branch_id` (required): Branch to merge FROM
- `merge_message` (required): Descriptive commit message (1-500 chars)
- `merge_strategy` (required): One of: `auto`, `three-way`, `fast-forward`, `ours`, `theirs`
- `base_branch_id` (optional): Common ancestor branch (required for `three-way` strategy)

**Response** (200 OK - Auto-merge successful):
```json
{
  "merge_id": "mrg_abc123def456",
  "status": "completed",
  "conflicts_detected": false,
  "merge_commit_id": 523,
  "message": "Merge completed successfully",
  "created_at": "2025-12-28T10:15:00Z",
  "completed_at": "2025-12-28T10:15:01Z"
}
```

**Response** (409 Conflict - Manual resolution required):
```json
{
  "merge_id": "mrg_xyz789abc012",
  "status": "pending_conflicts",
  "conflicts_detected": true,
  "conflicts": [
    {
      "conflict_id": 1,
      "table_name": "users",
      "conflict_type": "schema_mismatch",
      "description": "Column 'email' type mismatch"
    }
  ],
  "message": "Merge requires manual conflict resolution"
}
```

**Merge Strategies**:
- `auto`: Automatic merge, fails on conflicts (default)
- `three-way`: Uses base branch for better conflict detection
- `fast-forward`: Only succeeds if no divergence (linear history)
- `ours`: Auto-resolves conflicts using target version
- `theirs`: Auto-resolves conflicts using source version

#### Get Merge Status
```
GET /api/v1/merge/{merge_id}
```

**Response:** `200 OK`
```json
{
  "merge_id": "mrg_abc123def456",
  "source_branch_id": 101,
  "target_branch_id": 100,
  "merge_base_branch_id": null,
  "status": "completed",
  "merge_strategy": "auto",
  "conflicts_detected": false,
  "merge_commit_id": 523,
  "created_at": "2025-12-28T10:15:00Z",
  "completed_at": "2025-12-28T10:15:01Z"
}
```

**Possible Statuses**:
- `pending_conflicts`: Waiting for conflict resolution
- `in_progress`: Merge executing
- `completed`: Successfully merged
- `aborted`: Merge cancelled
- `failed`: Merge error

#### List Merges
```
GET /api/v1/merge?status=pending_conflicts&limit=20&offset=0
```

**Query Parameters:**
- `status` (optional): Filter by status
- `source_branch_id` (optional): Filter by source branch
- `target_branch_id` (optional): Filter by target branch
- `limit` (optional): Default 20, max 100
- `offset` (optional): Default 0

**Response:**
```json
{
  "items": [
    {
      "merge_id": "mrg_pending123",
      "source_branch_id": 103,
      "target_branch_id": 100,
      "status": "pending_conflicts",
      "conflicts_detected": true,
      "created_at": "2025-12-28T10:30:00Z"
    }
  ],
  "total": 1
}
```

#### List Conflicts
```
GET /api/v1/merge/{merge_id}/conflicts
```

**Response:** `200 OK`
```json
{
  "merge_id": "mrg_xyz789abc012",
  "conflicts": [
    {
      "conflict_id": 1,
      "table_name": "users",
      "conflict_type": "schema_mismatch",
      "column_name": "email",
      "source_schema": {
        "data_type": "varchar",
        "max_length": 255
      },
      "target_schema": {
        "data_type": "varchar",
        "max_length": 100
      },
      "description": "Column 'email' type mismatch: varchar(100) vs varchar(255)",
      "resolution_status": "pending"
    }
  ],
  "total_conflicts": 1
}
```

#### Get Conflict Details
```
GET /api/v1/merge/{merge_id}/conflicts/{conflict_id}
```

**Response:** `200 OK`
```json
{
  "conflict_id": 1,
  "merge_id": "mrg_xyz789abc012",
  "conflict_type": "schema_mismatch",
  "table_name": "users",
  "column_name": "email",
  "source_schema": {
    "column_name": "email",
    "data_type": "varchar",
    "max_length": 255,
    "nullable": false
  },
  "target_schema": {
    "column_name": "email",
    "data_type": "varchar",
    "max_length": 100,
    "nullable": false
  },
  "description": "Column 'email' type mismatch",
  "resolution_status": "pending"
}
```

#### Resolve Conflict
```
POST /api/v1/merge/{merge_id}/conflicts/{conflict_id}/resolve
Content-Type: application/json

{
  "resolution_strategy": "use_source",
  "resolution_notes": "Using source schema for better compatibility",
  "custom_schema": null
}
```

**Resolution Strategies**:
- `use_source`: Accept source branch version
- `use_target`: Keep target branch version
- `custom`: Provide custom schema (requires `custom_schema` field)

**Example Custom Resolution**:
```json
{
  "resolution_strategy": "custom",
  "custom_schema": {
    "column_name": "email",
    "data_type": "varchar",
    "max_length": 320,
    "nullable": false,
    "unique": true
  },
  "resolution_notes": "Using RFC 5321 max length"
}
```

**Response:** `200 OK`
```json
{
  "conflict_id": 1,
  "resolution_id": "res_123456",
  "resolution_strategy": "use_source",
  "resolution_notes": "Using source schema for better compatibility",
  "resolved_at": "2025-12-28T10:22:00Z"
}
```

#### Complete Merge
```
POST /api/v1/merge/{merge_id}/complete
Content-Type: application/json

{
  "merge_message": "Resolved conflicts and merged feature/modify-user-table"
}
```

**Response:** `200 OK`
```json
{
  "merge_id": "mrg_xyz789abc012",
  "status": "completed",
  "conflicts_detected": true,
  "conflicts_resolved": 1,
  "merge_commit_id": 524,
  "message": "Merge completed after conflict resolution",
  "created_at": "2025-12-28T10:20:00Z",
  "completed_at": "2025-12-28T10:23:00Z"
}
```

#### Abort Merge
```
POST /api/v1/merge/{merge_id}/abort
```

**Response:** `200 OK`
```json
{
  "merge_id": "mrg_xyz789abc012",
  "status": "aborted",
  "message": "Merge operation aborted",
  "aborted_at": "2025-12-28T10:25:00Z"
}
```

**Tutorial**: For a complete walkthrough, see `MERGE_TUTORIAL.md`

## Performance Targets

| Endpoint | P50 | P95 | P99 |
|----------|-----|-----|-----|
| health_check | 10ms | 25ms | 50ms |
| webhooks_list | 50ms | 150ms | 300ms |
| alerts_list | 75ms | 200ms | 400ms |
| cache_stats | 30ms | 75ms | 150ms |

## Troubleshooting

### High Latency

**Symptoms:** Requests taking >500ms

**Solutions:**
1. Check cache hit rates: `GET /api/v1/cache/stats`
2. Warm cache: `POST /api/v1/cache/warm`
3. Check database connectivity: `GET /health/deep`
4. Review slow queries in database logs

### WebSocket Disconnections

**Symptoms:** Frequent connection drops

**Solutions:**
1. Check network connectivity
2. Enable automatic reconnection on client
3. Verify server logs for errors
4. Increase server connection limits

### Cache Misses

**Symptoms:** Cache hit rate <50%

**Solutions:**
1. Increase cache TTLs in configuration
2. Warm cache more frequently
3. Implement L2 Redis caching
4. Review cache invalidation triggers

## OpenAPI Documentation

Full interactive API documentation available at:
- **Swagger UI**: `/docs`
- **ReDoc**: `/redoc`
- **OpenAPI JSON**: `/openapi.json`

## Code Examples

### Python
```python
import httpx
import asyncio

async def get_alerts():
    async with httpx.AsyncClient() as client:
        response = await client.get(
            "http://localhost:8000/api/v1/alerts",
            params={"status": "pending"}
        )
        return response.json()

asyncio.run(get_alerts())
```

### JavaScript
```javascript
// Using fetch API
const response = await fetch(
  'http://localhost:8000/api/v1/webhooks'
);
const webhooks = await response.json();

// Using WebSocket
const ws = new WebSocket('ws://localhost:8000/api/v1/ws/alerts');
ws.onmessage = (event) => {
  const message = JSON.parse(event.data);
  console.log('Alert:', message.data);
};
```

### cURL
```bash
# List webhooks
curl http://localhost:8000/api/v1/webhooks

# Create webhook
curl -X POST http://localhost:8000/api/v1/webhooks \
  -H "Content-Type: application/json" \
  -d '{
    "name": "production-alerts",
    "url": "https://example.com/webhook"
  }'

# Get cache stats
curl http://localhost:8000/api/v1/cache/stats
```

## API Versioning

Current version: **v1**

Future versions will be available at:
- `/api/v2/...`
- `/api/v3/...`

Deprecation warnings will be provided 6 months in advance.
