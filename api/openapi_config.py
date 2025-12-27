"""
OpenAPI Configuration
====================

OpenAPI schema generation and documentation configuration.
Provides automatic API documentation with Swagger and ReDoc.

Features:
- Custom OpenAPI schema generation
- Authentication scheme documentation
- Error response examples
- Endpoint descriptions and examples
"""

def get_openapi_schema(app):
    """
    Generate custom OpenAPI schema with detailed documentation.

    Args:
        app: FastAPI application instance

    Returns:
        OpenAPI schema dictionary
    """
    return {
        "openapi": "3.1.0",
        "info": {
            "title": "PGGIT API",
            "description": """
# Phase 8 Real-time Analytics & Monitoring API

## Overview

PGGIT is a production-grade real-time analytics and monitoring platform for webhook management and alert delivery. This API provides comprehensive webhooks management, alert routing, and real-time dashboard capabilities.

## Authentication

All endpoints require JWT (JSON Web Token) authentication via the `Authorization` header:

```
Authorization: Bearer <your_jwt_token>
```

WebSocket connections require the token via query parameter:

```
ws://api.example.com/ws/dashboard?token=<your_jwt_token>
```

## Key Features

### REST API (Synchronous)
- **Webhook Management**: Full CRUD operations for webhook management
- **Alert Management**: View, filter, and acknowledge alerts
- **Dashboard Analytics**: Real-time system metrics and health status

### WebSocket (Real-time)
- **Live Updates**: Receive real-time metrics, alerts, and webhook status changes
- **Subscriptions**: Subscribe/unsubscribe from specific message types
- **Heartbeat**: 30-second keep-alive mechanism

### Caching
- **Multi-tier**: L1 in-memory LRU, L2 Redis distributed cache
- **Transparent**: Automatic cache invalidation on data changes
- **Performance**: >80% cache hit rate target

## Rate Limiting

- **Limit**: 100 requests per user per 60 seconds
- **Headers**: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`
- **Exceeded**: Returns HTTP 429 with `Retry-After` header

## Error Handling

All errors follow standard HTTP status codes:
- **400**: Bad Request (invalid parameters)
- **401**: Unauthorized (missing or invalid token)
- **403**: Forbidden (insufficient permissions)
- **404**: Not Found (resource doesn't exist)
- **429**: Too Many Requests (rate limit exceeded)
- **500**: Internal Server Error (server error)

## WebSocket Message Format

All WebSocket messages use JSON format:

```json
{
  "type": "message_type",
  "data": { "key": "value" },
  "timestamp": "2024-01-01T12:00:00.000Z"
}
```

## Performance Targets

- **API Response Time**: P95 < 200ms, P99 < 500ms
- **WebSocket Latency**: < 100ms
- **Cache Hit Rate**: > 80%
- **Error Rate**: < 0.1%
- **Availability**: 99.9% (SLO)

## Examples

### Getting Started with Python

```python
import httpx
import asyncio

# REST API request
async with httpx.AsyncClient() as client:
    headers = {"Authorization": f"Bearer {token}"}
    response = await client.get(
        "https://api.example.com/api/v1/dashboard",
        headers=headers
    )
    dashboard_data = response.json()

# WebSocket connection
import websockets

async with websockets.connect(
    f"wss://api.example.com/ws/dashboard?token={token}"
) as websocket:
    # Subscribe to metrics updates
    await websocket.send(json.dumps({
        "action": "subscribe",
        "types": ["metrics", "alerts"]
    }))

    # Listen for updates
    async for message in websocket:
        update = json.loads(message)
        print(f"Received: {update['type']}")
```

### Getting Started with JavaScript

```javascript
// REST API request
const response = await fetch(
    'https://api.example.com/api/v1/webhooks',
    {
        headers: {
            'Authorization': `Bearer ${token}`
        }
    }
);
const webhooks = await response.json();

// WebSocket connection
const ws = new WebSocket(
    `wss://api.example.com/ws/dashboard?token=${token}`
);

ws.onopen = () => {
    ws.send(JSON.stringify({
        action: 'subscribe',
        types: ['metrics', 'alerts', 'webhooks']
    }));
};

ws.onmessage = (event) => {
    const update = JSON.parse(event.data);
    console.log(`Received: ${update.type}`, update.data);
};
```

## API Endpoints

### Webhooks
- `GET /api/v1/webhooks` - List all webhooks
- `GET /api/v1/webhooks/{id}` - Get webhook details
- `POST /api/v1/webhooks` - Create webhook
- `PUT /api/v1/webhooks/{id}` - Update webhook
- `DELETE /api/v1/webhooks/{id}` - Delete webhook

### Alerts
- `GET /api/v1/alerts` - List alerts
- `GET /api/v1/alerts/{id}` - Get alert details
- `POST /api/v1/alerts/{id}/ack` - Acknowledge alert
- `GET /api/v1/alerts/stats/summary` - Alert statistics

### Dashboard
- `GET /api/v1/dashboard` - Full dashboard data
- `GET /api/v1/dashboard/overview` - Overview metrics
- `GET /api/v1/dashboard/performance` - Performance metrics
- `GET /api/v1/dashboard/webhooks` - Webhook health
- `GET /api/v1/dashboard/anomalies` - Anomalies summary

### WebSocket
- `WebSocket /ws/dashboard` - Real-time updates

### Health
- `GET /health` - Basic health check
- `GET /health/deep` - Detailed health check

## Status Codes

- **2xx**: Success
  - 200 OK: Request successful
  - 201 Created: Resource created
  - 204 No Content: Request successful, no response body

- **4xx**: Client Error
  - 400 Bad Request: Invalid parameters
  - 401 Unauthorized: Authentication required
  - 404 Not Found: Resource not found
  - 429 Too Many Requests: Rate limit exceeded

- **5xx**: Server Error
  - 500 Internal Server Error: Unexpected server error
  - 503 Service Unavailable: Service temporarily unavailable

## Documentation

- **Swagger UI**: `/api/docs`
- **ReDoc**: `/api/redoc`
- **OpenAPI JSON**: `/api/openapi.json`

## Support

For issues, questions, or feature requests, please contact the PGGIT team or create an issue in the repository.
            """,
            "termsOfService": "https://docs.pggit.io/terms",
            "contact": {
                "name": "PGGIT Support",
                "url": "https://docs.pggit.io",
                "email": "support@pggit.io"
            },
            "license": {
                "name": "Proprietary",
                "url": "https://docs.pggit.io/license"
            },
            "version": "1.0.0"
        },
        "servers": [
            {
                "url": "https://api.example.com",
                "description": "Production environment"
            },
            {
                "url": "https://staging-api.example.com",
                "description": "Staging environment"
            },
            {
                "url": "http://localhost:8000",
                "description": "Local development"
            }
        ],
        "components": {
            "securitySchemes": {
                "bearerAuth": {
                    "type": "http",
                    "scheme": "bearer",
                    "bearerFormat": "JWT",
                    "description": "JWT token for authentication"
                }
            },
            "schemas": {
                "Error": {
                    "type": "object",
                    "properties": {
                        "error": {
                            "type": "string",
                            "description": "Error message"
                        },
                        "request_id": {
                            "type": "string",
                            "description": "Unique request ID for debugging"
                        },
                        "detail": {
                            "type": "string",
                            "description": "Detailed error information (development only)"
                        }
                    }
                },
                "HealthStatus": {
                    "type": "object",
                    "properties": {
                        "status": {
                            "type": "string",
                            "enum": ["healthy", "degraded", "unhealthy"]
                        },
                        "service": {
                            "type": "string"
                        },
                        "database": {
                            "type": "object",
                            "properties": {
                                "status": {"type": "string"},
                                "error": {"type": "string"}
                            }
                        },
                        "cache": {
                            "type": "object",
                            "properties": {
                                "status": {"type": "string"},
                                "hit_rate": {"type": "number"}
                            }
                        }
                    }
                }
            }
        },
        "security": [
            {"bearerAuth": []}
        ],
        "tags": [
            {
                "name": "Webhooks",
                "description": "Webhook management endpoints"
            },
            {
                "name": "Alerts",
                "description": "Alert management endpoints"
            },
            {
                "name": "Dashboard",
                "description": "Dashboard and analytics endpoints"
            },
            {
                "name": "Health",
                "description": "Health check endpoints"
            }
        ]
    }
