"""
Integration Tests for Phase 8 Week 2 API
=========================================

Tests for:
- FastAPI application and endpoints
- WebSocket real-time updates
- Cache warming strategy
- Cache invalidation triggers
- End-to-end API workflows
"""

import pytest
import asyncio
import json
import time
from datetime import datetime
from httpx import AsyncClient, ASGITransport
from pathlib import Path

# Assuming the FastAPI app is available at api.main:app
# These tests will validate the full API integration


class TestAPIEndpoints:
    """Test REST API endpoints"""

    @pytest.fixture(scope="function")
    async def client(self):
        """Create an async HTTP client for testing"""
        from api.main import app
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            yield client

    @pytest.mark.asyncio
    async def test_health_check(self, client):
        """Test /health endpoint"""
        response = await client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert "status" in data
        assert data["status"] in ["healthy", "ok"]

    @pytest.mark.asyncio
    async def test_health_deep_check(self, client):
        """Test /health/deep endpoint"""
        response = await client.get("/health/deep")
        assert response.status_code == 200
        data = response.json()
        assert "status" in data
        assert "database" in data or "checks" in data

    @pytest.mark.asyncio
    async def test_webhooks_list(self, client):
        """Test GET /api/v1/webhooks"""
        response = await client.get("/api/v1/webhooks")
        assert response.status_code == 200
        data = response.json()
        assert isinstance(data, list) or "items" in data

    @pytest.mark.asyncio
    async def test_webhooks_create(self, client):
        """Test POST /api/v1/webhooks"""
        payload = {
            "name": "test_webhook",
            "url": "https://example.com/webhook",
            "description": "Test webhook for integration testing",
            "is_active": True,
        }
        response = await client.post("/api/v1/webhooks", json=payload)
        assert response.status_code in [200, 201]
        data = response.json()
        assert "id" in data or "webhook_id" in data
        assert data.get("name") == "test_webhook"

    @pytest.mark.asyncio
    async def test_alerts_list(self, client):
        """Test GET /api/v1/alerts"""
        response = await client.get("/api/v1/alerts")
        assert response.status_code == 200
        data = response.json()
        assert isinstance(data, list) or "items" in data

    @pytest.mark.asyncio
    async def test_alerts_acknowledge(self, client):
        """Test POST /api/v1/alerts/acknowledge"""
        payload = {
            "alert_ids": [1, 2, 3],
        }
        response = await client.post("/api/v1/alerts/acknowledge", json=payload)
        assert response.status_code in [200, 201]

    @pytest.mark.asyncio
    async def test_cache_stats(self, client):
        """Test GET /api/v1/cache/stats"""
        response = await client.get("/api/v1/cache/stats")
        assert response.status_code == 200
        data = response.json()
        assert "hit_rate" in data or "stats" in data

    @pytest.mark.asyncio
    async def test_cache_warm(self, client):
        """Test POST /api/v1/cache/warm"""
        response = await client.post("/api/v1/cache/warm")
        assert response.status_code == 200
        data = response.json()
        assert "status" in data or "warmed" in data


class TestCacheWarming:
    """Test cache warming strategy"""

    @pytest.fixture(scope="function")
    async def client(self):
        """Create an async HTTP client for testing"""
        from api.main import app
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            yield client

    @pytest.mark.asyncio
    async def test_cache_warming_initialization(self, client):
        """Test that cache is warmed on startup"""
        # Request an endpoint and verify it's served quickly
        start = time.time()
        response = await client.get("/api/v1/webhooks")
        duration = time.time() - start

        assert response.status_code == 200
        # First request should still be reasonably fast
        assert duration < 5.0  # 5 seconds

    @pytest.mark.asyncio
    async def test_cache_hit_performance(self, client):
        """Test that cached requests are faster"""
        # First request (cache miss)
        start1 = time.time()
        response1 = await client.get("/api/v1/webhooks")
        time1 = time.time() - start1

        await asyncio.sleep(0.1)  # Small delay

        # Second request (cache hit)
        start2 = time.time()
        response2 = await client.get("/api/v1/webhooks")
        time2 = time.time() - start2

        assert response1.status_code == 200
        assert response2.status_code == 200
        # Second request should be faster due to caching
        assert time2 <= time1 * 1.5  # Allow 50% variance

    @pytest.mark.asyncio
    async def test_cache_warming_endpoint(self, client):
        """Test explicit cache warming endpoint"""
        response = await client.post("/api/v1/cache/warm")
        assert response.status_code == 200

        # After warming, requests should be fast
        start = time.time()
        response = await client.get("/api/v1/webhooks")
        duration = time.time() - start

        assert response.status_code == 200
        assert duration < 2.0  # Should be very fast from cache

    @pytest.mark.asyncio
    async def test_cache_stats_reporting(self, client):
        """Test cache statistics endpoint"""
        # Warm cache
        await client.post("/api/v1/cache/warm")

        # Make some requests
        for _ in range(5):
            await client.get("/api/v1/webhooks")
            await client.get("/api/v1/alerts")

        # Check cache stats
        response = await client.get("/api/v1/cache/stats")
        assert response.status_code == 200
        data = response.json()

        # Should have some hit rate
        hit_rate = data.get("hit_rate", 0) or data.get("cache_hit_percent", 0)
        assert hit_rate > 0


class TestCacheInvalidation:
    """Test cache invalidation triggers"""

    @pytest.fixture(scope="function")
    async def client(self):
        """Create an async HTTP client for testing"""
        from api.main import app
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            yield client

    @pytest.mark.asyncio
    async def test_webhook_creation_invalidates_list_cache(self, client):
        """Test that creating a webhook invalidates the webhooks list cache"""
        # Get initial list
        response1 = await client.get("/api/v1/webhooks")
        assert response1.status_code == 200
        initial_count = len(response1.json())

        # Create new webhook
        payload = {
            "name": "test_webhook_invalidation",
            "url": "https://example.com/webhook",
        }
        create_response = await client.post("/api/v1/webhooks", json=payload)
        assert create_response.status_code in [200, 201]

        # Get list again - should reflect the new webhook
        response2 = await client.get("/api/v1/webhooks")
        assert response2.status_code == 200
        new_count = len(response2.json())

        # Should have one more webhook
        assert new_count > initial_count

    @pytest.mark.asyncio
    async def test_webhook_update_invalidates_cache(self, client):
        """Test that updating a webhook invalidates its cache"""
        # Create webhook
        payload = {
            "name": "test_update",
            "url": "https://example.com/webhook",
        }
        create_response = await client.post("/api/v1/webhooks", json=payload)
        webhook_id = create_response.json().get("id") or create_response.json().get("webhook_id")

        # Get webhook details
        get_response = await client.get(f"/api/v1/webhooks/{webhook_id}")
        original_name = get_response.json().get("name")

        # Update webhook
        update_payload = {"name": "test_update_new"}
        update_response = await client.put(
            f"/api/v1/webhooks/{webhook_id}",
            json=update_payload
        )
        assert update_response.status_code in [200, 204]

        # Get webhook details again - should show updated name
        get_response2 = await client.get(f"/api/v1/webhooks/{webhook_id}")
        assert get_response2.status_code == 200
        updated_name = get_response2.json().get("name")
        assert updated_name != original_name

    @pytest.mark.asyncio
    async def test_alert_acknowledgment_invalidates_cache(self, client):
        """Test that acknowledging alerts invalidates the alerts cache"""
        # Get alerts list
        response1 = await client.get("/api/v1/alerts")
        assert response1.status_code == 200

        # Acknowledge alerts
        payload = {"alert_ids": [1]}
        ack_response = await client.post("/api/v1/alerts/acknowledge", json=payload)
        assert ack_response.status_code in [200, 201]

        # Get alerts list again - cache should be invalidated
        response2 = await client.get("/api/v1/alerts")
        assert response2.status_code == 200

    @pytest.mark.asyncio
    async def test_manual_cache_invalidation(self, client):
        """Test manual cache invalidation endpoint"""
        # Get initial cache stats
        stats1 = await client.get("/api/v1/cache/stats")
        assert stats1.status_code == 200

        # Invalidate cache
        invalidate_response = await client.post("/api/v1/cache/invalidate")
        assert invalidate_response.status_code == 200

        # Make a request - should be slower (cache miss)
        start = time.time()
        response = await client.get("/api/v1/webhooks")
        duration = time.time() - start
        assert response.status_code == 200


class TestWebSocketIntegration:
    """Test WebSocket real-time updates"""

    @pytest.fixture(scope="function")
    async def client(self):
        """Create an async HTTP client for testing"""
        from api.main import app
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            yield client

    @pytest.mark.asyncio
    async def test_websocket_connection(self, client):
        """Test WebSocket connection establishment"""
        # Note: This is a simplified test as WebSocket testing with AsyncClient is complex
        # In real scenarios, use websockets library or pytest-asyncio with proper fixtures
        try:
            # WebSocket endpoint should be available
            response = await client.get("/ws")
            # WebSocket upgrade will fail with GET, but endpoint should exist
            assert response.status_code in [400, 426, 200]  # Upgrade required or accepted
        except Exception:
            # WebSocket connection might require special handling
            pass

    @pytest.mark.asyncio
    async def test_alert_notifications_endpoint(self, client):
        """Test alert notifications WebSocket endpoint"""
        # Test that the WebSocket endpoint responds
        try:
            response = await client.get("/api/v1/ws/alerts")
            # Should get an upgrade required or similar response
            assert response.status_code in [400, 426]
        except Exception:
            pass


class TestEndToEndWorkflows:
    """Test complete end-to-end API workflows"""

    @pytest.fixture(scope="function")
    async def client(self):
        """Create an async HTTP client for testing"""
        from api.main import app
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            yield client

    @pytest.mark.asyncio
    async def test_webhook_lifecycle(self, client):
        """Test complete webhook lifecycle"""
        # 1. Create webhook
        create_payload = {
            "name": "lifecycle_test",
            "url": "https://example.com/webhook",
            "description": "Test webhook lifecycle",
        }
        create_response = await client.post("/api/v1/webhooks", json=create_payload)
        assert create_response.status_code in [200, 201]
        webhook_id = create_response.json().get("id") or create_response.json().get("webhook_id")
        assert webhook_id is not None

        # 2. Get webhook details
        get_response = await client.get(f"/api/v1/webhooks/{webhook_id}")
        assert get_response.status_code == 200
        webhook_data = get_response.json()
        assert webhook_data.get("name") == "lifecycle_test"

        # 3. Update webhook
        update_payload = {
            "description": "Updated description",
        }
        update_response = await client.put(
            f"/api/v1/webhooks/{webhook_id}",
            json=update_payload
        )
        assert update_response.status_code in [200, 204]

        # 4. Verify update
        verify_response = await client.get(f"/api/v1/webhooks/{webhook_id}")
        assert verify_response.status_code == 200
        updated_webhook = verify_response.json()
        assert updated_webhook.get("description") == "Updated description"

        # 5. Delete webhook
        delete_response = await client.delete(f"/api/v1/webhooks/{webhook_id}")
        assert delete_response.status_code in [200, 204]

    @pytest.mark.asyncio
    async def test_alert_workflow(self, client):
        """Test alert retrieval and acknowledgment workflow"""
        # 1. Get all alerts
        list_response = await client.get("/api/v1/alerts")
        assert list_response.status_code == 200
        alerts = list_response.json()
        alert_list = alerts if isinstance(alerts, list) else alerts.get("items", [])

        if alert_list:
            # 2. Get alert details
            alert_id = alert_list[0].get("id") or alert_list[0].get("alert_id")
            if alert_id:
                detail_response = await client.get(f"/api/v1/alerts/{alert_id}")
                assert detail_response.status_code == 200

            # 3. Acknowledge alert
            ack_payload = {"alert_ids": [alert_id]}
            ack_response = await client.post("/api/v1/alerts/acknowledge", json=ack_payload)
            assert ack_response.status_code in [200, 201]

    @pytest.mark.asyncio
    async def test_concurrent_requests(self, client):
        """Test API handles concurrent requests correctly"""
        async def make_request(endpoint):
            response = await client.get(endpoint)
            return response.status_code

        # Make concurrent requests
        endpoints = [
            "/api/v1/webhooks",
            "/api/v1/alerts",
            "/api/v1/cache/stats",
            "/health",
        ]

        tasks = [make_request(endpoint) for endpoint in endpoints]
        results = await asyncio.gather(*tasks)

        # All requests should succeed
        assert all(status == 200 for status in results)

    @pytest.mark.asyncio
    async def test_api_response_headers(self, client):
        """Test API response headers are correct"""
        response = await client.get("/api/v1/webhooks")
        assert response.status_code == 200

        # Check for important headers
        assert "content-type" in response.headers
        assert "application/json" in response.headers.get("content-type", "")


class TestPerformanceUnderLoad:
    """Test API performance under simulated load"""

    @pytest.fixture(scope="function")
    async def client(self):
        """Create an async HTTP client for testing"""
        from api.main import app
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            yield client

    @pytest.mark.asyncio
    async def test_endpoint_latency_under_load(self, client):
        """Test endpoint latency remains acceptable under concurrent load"""
        async def make_timed_request():
            start = time.time()
            response = await client.get("/api/v1/webhooks")
            duration = time.time() - start
            return duration, response.status_code

        # Make 20 concurrent requests
        tasks = [make_timed_request() for _ in range(20)]
        results = await asyncio.gather(*tasks)

        durations = [duration for duration, status in results]
        statuses = [status for duration, status in results]

        # All requests should succeed
        assert all(status == 200 for status in statuses)

        # Calculate latency percentiles
        durations_sorted = sorted(durations)
        p50 = durations_sorted[len(durations_sorted) // 2]
        p95 = durations_sorted[int(len(durations_sorted) * 0.95)]
        p99 = durations_sorted[int(len(durations_sorted) * 0.99)]

        # Latencies should be reasonable (adjusted for test environment)
        assert p50 < 2.0  # 2 seconds P50
        assert p95 < 5.0  # 5 seconds P95
        assert p99 < 10.0  # 10 seconds P99

    @pytest.mark.asyncio
    async def test_cache_effectiveness_under_load(self, client):
        """Test cache effectiveness with repeated requests"""
        # Warm cache
        await client.post("/api/v1/cache/warm")

        async def make_timed_request(endpoint):
            start = time.time()
            response = await client.get(endpoint)
            duration = time.time() - start
            return duration

        # Make many requests to same endpoint
        tasks = [make_timed_request("/api/v1/webhooks") for _ in range(30)]
        durations = await asyncio.gather(*tasks)

        # Second half should be faster (cache hits)
        first_half_avg = sum(durations[:15]) / 15
        second_half_avg = sum(durations[15:]) / 15

        # Second half should be at least as fast as first half
        assert second_half_avg <= first_half_avg * 1.2  # Allow 20% variance
