"""
WebSocket Real-time Updates Endpoint
====================================

WebSocket endpoint for real-time dashboard updates.
CRITICAL FIX #3: WebSocket authentication with JWT tokens.

Features:
- JWT token validation for WebSocket connections
- Real-time metrics updates
- Alert notifications
- Webhook status changes
- Heartbeat mechanism (30-second intervals)
- Connection tracking and management
- Graceful error handling

Message Types:
- metrics_update: Performance metrics changed
- alert_new: New alert created
- webhook_status_changed: Webhook health status changed
- heartbeat: Keep-alive signal
"""

import logging
import json
import asyncio
from datetime import datetime
from typing import Set

from fastapi import WebSocket, WebSocketDisconnect, Query, status
from fastapi.exceptions import WebSocketException

from services.dependencies import verify_websocket_token
from services.cache import get_cache

logger = logging.getLogger(__name__)


class ConnectionManager:
    """
    Manages WebSocket connections and broadcasts messages to subscribers.

    Features:
    - Track active connections
    - Broadcast messages to multiple clients
    - Handle connection lifecycle
    - Filter messages by subscription type
    """

    def __init__(self):
        """Initialize connection manager with empty active connections set."""
        self.active_connections: Set[WebSocket] = set()
        self.connection_metadata: dict = {}  # Track user_id and subscriptions per connection

    async def connect(self, websocket: WebSocket, user_id: str):
        """
        Accept and register a new WebSocket connection.

        Args:
            websocket: WebSocket connection object
            user_id: Authenticated user ID
        """
        await websocket.accept()
        self.active_connections.add(websocket)
        self.connection_metadata[id(websocket)] = {
            "user_id": user_id,
            "connected_at": datetime.now(),
            "subscriptions": {"metrics", "alerts", "webhooks"},  # Default subscriptions
            "last_heartbeat": datetime.now()
        }
        logger.info(f"WebSocket connected: user={user_id}, total_connections={len(self.active_connections)}")

    async def disconnect(self, websocket: WebSocket):
        """
        Unregister and close a WebSocket connection.

        Args:
            websocket: WebSocket connection object
        """
        if websocket in self.active_connections:
            user_id = self.connection_metadata.get(id(websocket), {}).get("user_id", "unknown")
            self.active_connections.discard(websocket)
            del self.connection_metadata[id(websocket)]
            logger.info(f"WebSocket disconnected: user={user_id}, total_connections={len(self.active_connections)}")

    async def broadcast(self, message: dict):
        """
        Send message to all connected clients.

        Args:
            message: Message dictionary with type and data
        """
        if not self.active_connections:
            return

        disconnected = []
        for websocket in self.active_connections:
            try:
                await websocket.send_json(message)
            except Exception as e:
                logger.error(f"Failed to send message to client: {e}")
                disconnected.append(websocket)

        # Clean up disconnected clients
        for websocket in disconnected:
            await self.disconnect(websocket)

    async def broadcast_to_subscriptions(self, message_type: str, data: dict, user_id: str = None):
        """
        Broadcast message only to clients subscribed to the message type.

        Args:
            message_type: Type of message (e.g., 'metrics_update', 'alert_new')
            data: Message data payload
            user_id: Optional user_id to send to specific user only
        """
        message = {
            "type": message_type,
            "data": data,
            "timestamp": datetime.now().isoformat()
        }

        disconnected = []
        for websocket in self.active_connections:
            try:
                metadata = self.connection_metadata.get(id(websocket), {})
                ws_user_id = metadata.get("user_id")

                # Filter by user_id if specified
                if user_id and ws_user_id != user_id:
                    continue

                # Filter by subscription type
                if message_type.split("_")[0] not in metadata.get("subscriptions", set()):
                    continue

                await websocket.send_json(message)

            except Exception as e:
                logger.error(f"Failed to broadcast message: {e}")
                disconnected.append(websocket)

        # Clean up disconnected clients
        for websocket in disconnected:
            await self.disconnect(websocket)

    async def heartbeat_loop(self):
        """
        Send periodic heartbeat messages to keep connections alive.

        Runs every 30 seconds.
        """
        while True:
            try:
                await asyncio.sleep(30)
                heartbeat_message = {
                    "type": "heartbeat",
                    "timestamp": datetime.now().isoformat(),
                    "active_connections": len(self.active_connections)
                }
                await self.broadcast(heartbeat_message)
            except Exception as e:
                logger.error(f"Heartbeat error: {e}")

    def get_connection_stats(self) -> dict:
        """
        Get statistics about active connections.

        Returns:
            Dictionary with connection stats
        """
        return {
            "total_connections": len(self.active_connections),
            "connected_users": len(set(m.get("user_id") for m in self.connection_metadata.values())),
            "uptime_seconds": sum(
                (datetime.now() - m.get("connected_at", datetime.now())).total_seconds()
                for m in self.connection_metadata.values()
            ) / max(len(self.active_connections), 1)
        }


# Global connection manager
manager = ConnectionManager()


async def websocket_endpoint(
    websocket_connection: WebSocket,
    token: str = Query(..., description="JWT authentication token")
):
    """
    WebSocket endpoint for real-time dashboard updates.

    Path: /ws/dashboard?token=<jwt_token>

    Features:
    - JWT authentication (CRITICAL FIX #3)
    - Real-time metrics, alerts, and webhook updates
    - Heartbeat keep-alive (30 seconds)
    - Connection tracking
    - Graceful error handling

    Message Types Received:
    - subscribe: Subscribe to specific message types
      Example: {"action": "subscribe", "types": ["metrics", "alerts"]}
    - unsubscribe: Unsubscribe from message types
      Example: {"action": "unsubscribe", "types": ["webhooks"]}
    - ping: Request server status
      Example: {"action": "ping"}

    Message Types Sent:
    - metrics_update: Performance metrics changed
      Payload: {
        "type": "metrics_update",
        "data": {
          "p50_latency_ms": 45.2,
          "p95_latency_ms": 120.5,
          "p99_latency_ms": 350.8,
          "error_rate_percent": 0.05,
          "cache_hit_rate_percent": 87.3
        },
        "timestamp": "2024-01-01T12:00:00.000Z"
      }

    - alert_new: New alert created
      Payload: {
        "type": "alert_new",
        "data": {
          "alert_id": 123,
          "severity": "WARNING",
          "message": "Statistical anomaly detected in commit operation",
          "webhook_id": 5
        },
        "timestamp": "2024-01-01T12:00:00.000Z"
      }

    - webhook_status_changed: Webhook health status changed
      Payload: {
        "type": "webhook_status_changed",
        "data": {
          "webhook_id": 5,
          "webhook_name": "My Webhook",
          "health_status": "DEGRADED",
          "success_rate_percent": 45.2
        },
        "timestamp": "2024-01-01T12:00:00.000Z"
      }

    - heartbeat: Keep-alive signal
      Payload: {
        "type": "heartbeat",
        "timestamp": "2024-01-01T12:00:00.000Z",
        "active_connections": 42
      }
    """
    try:
        # CRITICAL FIX #3: Verify JWT token before accepting connection
        user = await verify_websocket_token(websocket_connection, token)
        user_id = user.get("user_id")

        # Accept connection
        await manager.connect(websocket_connection, user_id)

        # Start heartbeat loop (once per process, could be optimized)
        try:
            asyncio.create_task(manager.heartbeat_loop())
        except RuntimeError:
            # Heartbeat task already running
            pass

        logger.info(f"WebSocket authenticated: user_id={user_id}")

        # Listen for client messages
        while True:
            data = await websocket_connection.receive_json()
            action = data.get("action")

            if action == "subscribe":
                # Subscribe to message types
                types = data.get("types", [])
                metadata = manager.connection_metadata.get(id(websocket_connection), {})
                metadata["subscriptions"] = set(types)
                logger.debug(f"User {user_id} subscribed to: {types}")

                await websocket_connection.send_json({
                    "type": "subscription_confirmed",
                    "subscriptions": list(types),
                    "timestamp": datetime.now().isoformat()
                })

            elif action == "unsubscribe":
                # Unsubscribe from message types
                types = data.get("types", [])
                metadata = manager.connection_metadata.get(id(websocket_connection), {})
                metadata["subscriptions"] -= set(types)
                logger.debug(f"User {user_id} unsubscribed from: {types}")

                await websocket_connection.send_json({
                    "type": "unsubscribe_confirmed",
                    "timestamp": datetime.now().isoformat()
                })

            elif action == "ping":
                # Server status request
                stats = manager.get_connection_stats()
                await websocket_connection.send_json({
                    "type": "pong",
                    "data": stats,
                    "timestamp": datetime.now().isoformat()
                })

            else:
                logger.warning(f"Unknown action from {user_id}: {action}")
                await websocket_connection.send_json({
                    "type": "error",
                    "message": f"Unknown action: {action}",
                    "timestamp": datetime.now().isoformat()
                })

    except WebSocketException as e:
        logger.warning(f"WebSocket authentication failed: {e}")
        await websocket_connection.close(code=status.WS_1008_POLICY_VIOLATION)

    except WebSocketDisconnect:
        await manager.disconnect(websocket_connection)

    except Exception as e:
        logger.error(f"WebSocket error: {type(e).__name__}: {e}")
        await manager.disconnect(websocket_connection)


async def notify_metrics_update(metrics: dict):
    """
    Broadcast metrics update to all connected clients.

    Args:
        metrics: Metrics data dictionary
    """
    await manager.broadcast_to_subscriptions("metrics_update", metrics)


async def notify_new_alert(alert: dict):
    """
    Broadcast new alert notification to all connected clients.

    Args:
        alert: Alert data dictionary with id, severity, message, webhook_id
    """
    await manager.broadcast_to_subscriptions("alert_new", alert)


async def notify_webhook_status_change(webhook: dict):
    """
    Broadcast webhook status change to all connected clients.

    Args:
        webhook: Webhook data with id, name, health_status, success_rate_percent
    """
    await manager.broadcast_to_subscriptions("webhook_status_changed", webhook)
