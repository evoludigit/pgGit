"""
Pytest Configuration for Load Tests
====================================

Provides shared fixtures and configuration for load testing suite.
"""

import pytest
import os
from pathlib import Path
from typing import Dict, Any

# Test results directory
RESULTS_DIR = Path(__file__).parent / "results"
RESULTS_DIR.mkdir(exist_ok=True)


@pytest.fixture(scope="session")
def load_test_config():
    """Fixture providing load test configuration"""
    return {
        "api_host": os.getenv("API_HOST", "http://localhost:8000"),
        "jwt_token": os.getenv("JWT_TOKEN", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0LXVzZXIiLCJleHAiOjk5OTk5OTk5OTl9.PLACEHOLDER"),
        "timeout": int(os.getenv("REQUEST_TIMEOUT", "30")),
        "ws_timeout": int(os.getenv("WS_TIMEOUT", "60")),
    }


@pytest.fixture(scope="session")
def results_dir():
    """Fixture providing results directory path"""
    return RESULTS_DIR


@pytest.fixture
def sample_webhook():
    """Fixture providing sample webhook data"""
    return {
        "name": "test_webhook",
        "url": "https://example.com/webhook",
        "description": "Test webhook for load testing",
        "is_active": True,
        "retry_policy": {
            "max_retries": 3,
            "backoff_base": 2,
            "max_backoff": 3600
        },
        "timeout_seconds": 30,
        "ssl_verify": True
    }


@pytest.fixture
def sample_alert():
    """Fixture providing sample alert data"""
    return {
        "operation_type": "commit",
        "severity": "WARNING",
        "message": "Load test alert",
        "context": {
            "test": True,
            "timestamp": "2024-01-01T00:00:00Z"
        }
    }


@pytest.fixture(scope="session", autouse=True)
def setup_test_environment():
    """Setup test environment before running tests"""
    # Create results directory
    RESULTS_DIR.mkdir(exist_ok=True)

    # Print configuration info
    print("\n" + "="*80)
    print("LOAD TEST ENVIRONMENT SETUP")
    print("="*80)
    print(f"Results directory: {RESULTS_DIR}")
    print(f"API Host: {os.getenv('API_HOST', 'http://localhost:8000')}")
    print("="*80 + "\n")

    yield

    # Cleanup after tests
    print("\nTest execution completed")


class PerformanceSLA:
    """Helper class for checking performance SLAs"""

    def __init__(self, targets: Dict[str, Dict[str, float]]):
        """
        Initialize with performance targets.

        Args:
            targets: Dict mapping endpoint names to SLA targets
                     Expected keys: p50_ms, p95_ms, p99_ms, error_rate_percent
        """
        self.targets = targets

    def check_endpoint(self, endpoint_name: str, metrics: Dict[str, Any]) -> Dict[str, bool]:
        """
        Check if endpoint metrics meet SLA targets.

        Args:
            endpoint_name: Name of the endpoint
            metrics: Metrics dict with keys: avg_ms, p95_ms, p99_ms, error_rate_percent

        Returns:
            Dict of {metric_name: passed_bool}
        """
        target = self.targets.get(endpoint_name, {})

        return {
            "p50": metrics.get("avg_ms", 0) <= target.get("p50_ms", float('inf')),
            "p95": metrics.get("p95_ms", 0) <= target.get("p95_ms", float('inf')),
            "p99": metrics.get("p99_ms", 0) <= target.get("p99_ms", float('inf')),
            "error_rate": metrics.get("error_rate_percent", 100) <= target.get("error_rate_percent", 100),
        }

    def all_passed(self, endpoint_name: str, metrics: Dict[str, Any]) -> bool:
        """Check if all SLAs passed for an endpoint"""
        results = self.check_endpoint(endpoint_name, metrics)
        return all(results.values())
