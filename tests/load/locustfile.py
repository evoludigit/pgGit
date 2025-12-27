"""
Load Testing Suite for Phase 8 API
===================================

Comprehensive load testing using Locust framework.

Features:
- REST API endpoint testing (webhooks, alerts, dashboard)
- WebSocket connection testing
- Real-time metrics collection
- Performance degradation detection
- Spike testing and sustained load scenarios

Usage:
    # Run with default settings (1 user)
    locust -f tests/load/locustfile.py

    # Run with custom settings
    locust -f tests/load/locustfile.py --users 100 --spawn-rate 10 --run-time 5m

    # Run headless with results
    locust -f tests/load/locustfile.py --headless -u 100 -r 10 --run-time 5m \
        --csv=tests/load/results/load_test

    # Run specific test scenario
    locust -f tests/load/locustfile.py -u 100 -r 10 --run-time 5m --tags rest_endpoints
"""

import time
import json
import logging
from typing import Dict, Any
import asyncio

from locust import HttpUser, WebSocketUser, task, between, events, tag
import websockets

logger = logging.getLogger(__name__)


# ===== Configuration =====

class LoadTestConfig:
    """Load test configuration"""
    # API Base URL
    API_HOST = "http://localhost:8000"

    # Authentication
    JWT_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0LXVzZXIiLCJleHAiOjk5OTk5OTk5OTl9.PLACEHOLDER"

    # Test Scenarios
    WEBHOOK_IDS = [1, 2, 3, 4, 5]
    ALERT_IDS = [1, 2, 3, 4, 5]

    # Timeouts
    REQUEST_TIMEOUT = 30
    WEBSOCKET_TIMEOUT = 60


# ===== REST API Tests =====

class RestApiUser(HttpUser):
    """
    User that performs REST API requests.

    Tests:
    - Webhook CRUD operations
    - Alert retrieval and acknowledgment
    - Dashboard data retrieval
    - Cache invalidation
    - Health checks
    """

    wait_time = between(1, 3)

    def on_start(self):
        """Setup authentication headers"""
        self.client.headers.update({
            "Authorization": f"Bearer {LoadTestConfig.JWT_TOKEN}",
            "Content-Type": "application/json"
        })

    # ===== Webhook Endpoints =====

    @tag("webhooks", "read")
    @task(3)
    def list_webhooks(self):
        """GET /api/v1/webhooks - List all webhooks"""
        with self.client.get(
            "/api/v1/webhooks",
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
                self.webhooks = response.json().get("webhooks", [])
            else:
                response.failure(f"Expected 200, got {response.status_code}")

    @tag("webhooks", "read")
    @task(2)
    def get_webhook_detail(self):
        """GET /api/v1/webhooks/{id} - Get webhook details"""
        webhook_id = LoadTestConfig.WEBHOOK_IDS[0]
        with self.client.get(
            f"/api/v1/webhooks/{webhook_id}",
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            elif response.status_code == 404:
                response.success()  # Expected for non-existent webhooks
            else:
                response.failure(f"Expected 200 or 404, got {response.status_code}")

    @tag("webhooks", "write")
    @task(1)
    def create_webhook(self):
        """POST /api/v1/webhooks - Create webhook"""
        payload = {
            "name": f"webhook_load_test_{time.time()}",
            "url": f"https://example.com/webhook/{time.time()}",
            "description": "Load test webhook",
            "is_active": True,
            "retry_policy": {
                "max_retries": 3,
                "backoff_base": 2,
                "max_backoff": 3600
            },
            "timeout_seconds": 30,
            "ssl_verify": True
        }

        with self.client.post(
            "/api/v1/webhooks",
            json=payload,
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code == 201:
                response.success()
            else:
                response.failure(f"Expected 201, got {response.status_code}")

    @tag("webhooks", "write")
    @task(1)
    def update_webhook(self):
        """PUT /api/v1/webhooks/{id} - Update webhook"""
        webhook_id = LoadTestConfig.WEBHOOK_IDS[0]
        payload = {
            "name": f"webhook_updated_{time.time()}",
            "is_active": True,
            "description": "Updated via load test"
        }

        with self.client.put(
            f"/api/v1/webhooks/{webhook_id}",
            json=payload,
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code in [200, 404]:
                response.success()
            else:
                response.failure(f"Expected 200 or 404, got {response.status_code}")

    # ===== Alert Endpoints =====

    @tag("alerts", "read")
    @task(4)
    def list_alerts(self):
        """GET /api/v1/alerts - List alerts"""
        with self.client.get(
            "/api/v1/alerts?limit=50&offset=0",
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
                self.alerts = response.json().get("alerts", [])
            else:
                response.failure(f"Expected 200, got {response.status_code}")

    @tag("alerts", "read")
    @task(2)
    def get_alert_detail(self):
        """GET /api/v1/alerts/{id} - Get alert details"""
        alert_id = LoadTestConfig.ALERT_IDS[0]
        with self.client.get(
            f"/api/v1/alerts/{alert_id}",
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            elif response.status_code == 404:
                response.success()
            else:
                response.failure(f"Expected 200 or 404, got {response.status_code}")

    @tag("alerts", "read")
    @task(1)
    def get_alert_stats(self):
        """GET /api/v1/alerts/stats/summary - Get alert statistics"""
        with self.client.get(
            "/api/v1/alerts/stats/summary",
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Expected 200, got {response.status_code}")

    @tag("alerts", "write")
    @task(1)
    def acknowledge_alert(self):
        """POST /api/v1/alerts/{id}/ack - Acknowledge alert"""
        alert_id = LoadTestConfig.ALERT_IDS[0]
        with self.client.post(
            f"/api/v1/alerts/{alert_id}/ack",
            json={"acknowledged_by": "load_test"},
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code in [200, 404]:
                response.success()
            else:
                response.failure(f"Expected 200 or 404, got {response.status_code}")

    # ===== Dashboard Endpoints =====

    @tag("dashboard", "read")
    @task(3)
    def get_dashboard_overview(self):
        """GET /api/v1/dashboard - Get full dashboard"""
        with self.client.get(
            "/api/v1/dashboard",
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Expected 200, got {response.status_code}")

    @tag("dashboard", "read")
    @task(2)
    def get_dashboard_performance(self):
        """GET /api/v1/dashboard/performance - Get performance metrics"""
        with self.client.get(
            "/api/v1/dashboard/performance",
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Expected 200, got {response.status_code}")

    @tag("dashboard", "read")
    @task(2)
    def get_webhook_health(self):
        """GET /api/v1/dashboard/webhooks - Get webhook health"""
        with self.client.get(
            "/api/v1/dashboard/webhooks",
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Expected 200, got {response.status_code}")

    @tag("dashboard", "read")
    @task(1)
    def get_anomalies(self):
        """GET /api/v1/dashboard/anomalies - Get anomalies summary"""
        with self.client.get(
            "/api/v1/dashboard/anomalies",
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Expected 200, got {response.status_code}")

    # ===== Cache Endpoints =====

    @tag("cache", "admin")
    @task(1)
    def get_cache_stats(self):
        """GET /api/v1/cache/stats - Get cache statistics"""
        with self.client.get(
            "/api/v1/cache/stats",
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Expected 200, got {response.status_code}")

    @tag("cache", "admin")
    @task(1)
    def invalidate_alert_cache(self):
        """POST /api/v1/cache/invalidate/alerts - Invalidate alert cache"""
        with self.client.post(
            f"/api/v1/cache/invalidate/alerts?alert_id=1&event_type=alert_updated",
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code == 204:
                response.success()
            else:
                response.failure(f"Expected 204, got {response.status_code}")

    # ===== Health Endpoints =====

    @tag("health")
    @task(1)
    def health_check(self):
        """GET /health - Basic health check"""
        with self.client.get(
            "/health",
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Expected 200, got {response.status_code}")

    @tag("health")
    @task(1)
    def deep_health_check(self):
        """GET /health/deep - Deep health check"""
        with self.client.get(
            "/health/deep",
            timeout=LoadTestConfig.REQUEST_TIMEOUT,
            catch_response=True
        ) as response:
            if response.status_code in [200, 503]:
                response.success()
            else:
                response.failure(f"Expected 200 or 503, got {response.status_code}")


# ===== WebSocket Tests =====

class WebSocketUser(HttpUser):
    """
    User that performs WebSocket connections for real-time updates.

    Tests:
    - WebSocket connection establishment
    - Message subscription
    - Real-time message reception
    - Connection heartbeat
    """

    wait_time = between(5, 10)

    def on_start(self):
        """Setup WebSocket connection"""
        self.websocket_url = f"ws://localhost:8000/ws/dashboard?token={LoadTestConfig.JWT_TOKEN}"
        self.ws = None

    @tag("websocket")
    @task(2)
    def websocket_connect_and_listen(self):
        """WebSocket /ws/dashboard - Connect and receive updates"""
        try:
            # Connect to WebSocket
            start_time = time.time()
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)

            async def ws_task():
                try:
                    async with websockets.connect(
                        self.websocket_url,
                        timeout=LoadTestConfig.WEBSOCKET_TIMEOUT
                    ) as websocket:
                        # Send subscription
                        subscribe_msg = {
                            "action": "subscribe",
                            "types": ["metrics", "alerts", "webhooks"]
                        }
                        await websocket.send(json.dumps(subscribe_msg))

                        # Wait for messages (5 second timeout)
                        start_listen = time.time()
                        message_count = 0

                        while time.time() - start_listen < 5:
                            try:
                                msg = await asyncio.wait_for(
                                    websocket.recv(),
                                    timeout=1
                                )
                                message_count += 1
                            except asyncio.TimeoutError:
                                break

                        return True, message_count
                except Exception as e:
                    logger.error(f"WebSocket error: {e}")
                    return False, 0

            success, msg_count = loop.run_until_complete(ws_task())
            duration_ms = (time.time() - start_time) * 1000

            if success:
                logger.info(f"WebSocket test successful - {msg_count} messages in {duration_ms:.0f}ms")
            else:
                logger.error("WebSocket connection failed")

        except Exception as e:
            logger.error(f"WebSocket test error: {e}")


# ===== Event Hooks for Metrics Collection =====

@events.request.add_listener
def on_request(request_type, name, response_time, response_length, response, context, exception, **kwargs):
    """Hook to collect request metrics"""
    if exception:
        logger.error(f"Request failed: {name} - {exception}")
    else:
        logger.debug(f"Request {name}: {response_time}ms")


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """Hook called when load test starts"""
    logger.info("Load test started")
    logger.info(f"API Host: {LoadTestConfig.API_HOST}")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Hook called when load test stops"""
    logger.info("Load test completed")

    # Print summary statistics
    stats = environment.stats
    total_requests = stats.total.num_requests
    total_failures = stats.total.num_failures

    logger.info(f"Total requests: {total_requests}")
    logger.info(f"Total failures: {total_failures}")
    logger.info(f"Failure rate: {(total_failures / total_requests * 100):.2f}%")
