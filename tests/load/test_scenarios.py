"""
Load Test Scenarios for Phase 8 API
====================================

Predefined test scenarios with different user profiles and load patterns.

Scenarios:
1. Normal Load: Baseline traffic pattern (1-10 users)
2. Peak Load: High volume scenario (50-100 users)
3. Spike Test: Sudden traffic spike (0→100→0 users)
4. Sustained Load: Long-running stability test (25 users for 30+ min)
5. Ramp-up: Gradual load increase
6. WebSocket Heavy: Real-time updates focus

Usage:
    # Run normal load scenario
    locust -f tests/load/locustfile.py -u 10 -r 2 --run-time 5m

    # Run peak load scenario
    locust -f tests/load/locustfile.py -u 100 -r 10 --run-time 10m

    # Run spike test
    locust -f tests/load/locustfile.py --headless -u 100 -r 50 --run-time 3m
"""

from dataclasses import dataclass
from typing import Dict, Any


@dataclass
class LoadScenario:
    """Load test scenario configuration"""
    name: str
    description: str
    users: int
    spawn_rate: int
    duration_minutes: int
    target_endpoint: str = ""
    tags: list = None
    ramp_up: bool = False
    spike_pattern: bool = False

    def __post_init__(self):
        if self.tags is None:
            self.tags = []


# ===== Scenario Definitions =====

SCENARIOS: Dict[str, LoadScenario] = {
    "normal_load": LoadScenario(
        name="Normal Load",
        description="Baseline traffic pattern - typical production usage",
        users=10,
        spawn_rate=2,
        duration_minutes=5,
        tags=["webhooks", "alerts", "dashboard", "rest_endpoints"]
    ),

    "peak_load": LoadScenario(
        name="Peak Load",
        description="High volume scenario - expected peak traffic",
        users=100,
        spawn_rate=10,
        duration_minutes=10,
        tags=["webhooks", "alerts", "dashboard", "rest_endpoints"]
    ),

    "spike_test": LoadScenario(
        name="Spike Test",
        description="Sudden traffic spike - sudden 10x increase",
        users=100,
        spawn_rate=50,
        duration_minutes=3,
        spike_pattern=True,
        tags=["webhooks", "alerts", "dashboard"]
    ),

    "sustained_load": LoadScenario(
        name="Sustained Load",
        description="Long-running stability test",
        users=25,
        spawn_rate=5,
        duration_minutes=30,
        tags=["webhooks", "alerts", "dashboard", "rest_endpoints"]
    ),

    "ramp_up": LoadScenario(
        name="Ramp-Up Test",
        description="Gradual load increase from 1 to 50 users",
        users=50,
        spawn_rate=2,
        duration_minutes=15,
        ramp_up=True,
        tags=["webhooks", "alerts", "dashboard"]
    ),

    "websocket_heavy": LoadScenario(
        name="WebSocket Heavy",
        description="Focus on real-time updates and WebSocket connections",
        users=50,
        spawn_rate=5,
        duration_minutes=10,
        tags=["websocket"]
    ),

    "rest_only": LoadScenario(
        name="REST API Only",
        description="Test only REST endpoints, exclude WebSocket",
        users=100,
        spawn_rate=10,
        duration_minutes=10,
        tags=["rest_endpoints"]
    ),

    "cache_invalidation": LoadScenario(
        name="Cache Invalidation",
        description="Test cache invalidation triggers under load",
        users=20,
        spawn_rate=4,
        duration_minutes=10,
        tags=["cache"]
    ),

    "smoke_test": LoadScenario(
        name="Smoke Test",
        description="Quick verification that API responds",
        users=1,
        spawn_rate=1,
        duration_minutes=1,
        tags=["health", "webhooks", "alerts"]
    ),

    "stress_test": LoadScenario(
        name="Stress Test",
        description="Maximum load until system breaks (200+ users)",
        users=200,
        spawn_rate=20,
        duration_minutes=15,
        tags=["webhooks", "alerts", "dashboard"]
    )
}


# ===== Performance Targets =====

@dataclass
class PerformanceTarget:
    """Performance SLA targets"""
    p50_ms: int
    p95_ms: int
    p99_ms: int
    error_rate_percent: float
    min_throughput_rps: int

    def to_dict(self) -> Dict[str, Any]:
        return {
            "p50_ms": self.p50_ms,
            "p95_ms": self.p95_ms,
            "p99_ms": self.p99_ms,
            "error_rate_percent": self.error_rate_percent,
            "min_throughput_rps": self.min_throughput_rps
        }


PERFORMANCE_TARGETS: Dict[str, PerformanceTarget] = {
    "webhooks_list": PerformanceTarget(
        p50_ms=50,
        p95_ms=150,
        p99_ms=300,
        error_rate_percent=0.5,
        min_throughput_rps=100
    ),

    "alerts_list": PerformanceTarget(
        p50_ms=75,
        p95_ms=200,
        p99_ms=400,
        error_rate_percent=0.5,
        min_throughput_rps=80
    ),

    "dashboard_overview": PerformanceTarget(
        p50_ms=100,
        p95_ms=250,
        p99_ms=500,
        error_rate_percent=1.0,
        min_throughput_rps=50
    ),

    "webhook_detail": PerformanceTarget(
        p50_ms=40,
        p95_ms=100,
        p99_ms=200,
        error_rate_percent=0.5,
        min_throughput_rps=150
    ),

    "cache_stats": PerformanceTarget(
        p50_ms=30,
        p95_ms=75,
        p99_ms=150,
        error_rate_percent=0.1,
        min_throughput_rps=200
    ),

    "health_check": PerformanceTarget(
        p50_ms=10,
        p95_ms=25,
        p99_ms=50,
        error_rate_percent=0.0,
        min_throughput_rps=500
    ),

    "websocket_connect": PerformanceTarget(
        p50_ms=100,
        p95_ms=300,
        p99_ms=600,
        error_rate_percent=1.0,
        min_throughput_rps=10
    )
}


# ===== Test Suites =====

TEST_SUITES: Dict[str, Dict[str, Any]] = {
    "quick_smoke": {
        "description": "Quick 1-minute smoke test to verify API is up",
        "scenarios": ["smoke_test"],
        "total_duration_minutes": 1
    },

    "nightly": {
        "description": "Nightly performance regression testing",
        "scenarios": ["smoke_test", "normal_load", "peak_load", "sustained_load"],
        "total_duration_minutes": 50
    },

    "pre_release": {
        "description": "Pre-release comprehensive testing",
        "scenarios": ["smoke_test", "normal_load", "peak_load", "spike_test", "sustained_load", "stress_test"],
        "total_duration_minutes": 90
    },

    "continuous": {
        "description": "Continuous monitoring scenario",
        "scenarios": ["normal_load"],
        "total_duration_minutes": 60
    }
}


# ===== Helper Functions =====

def get_scenario(scenario_name: str) -> LoadScenario:
    """Get scenario by name"""
    if scenario_name not in SCENARIOS:
        raise ValueError(f"Unknown scenario: {scenario_name}")
    return SCENARIOS[scenario_name]


def get_target(endpoint_name: str) -> PerformanceTarget:
    """Get performance target by endpoint name"""
    if endpoint_name not in PERFORMANCE_TARGETS:
        raise ValueError(f"Unknown endpoint: {endpoint_name}")
    return PERFORMANCE_TARGETS[endpoint_name]


def list_scenarios() -> None:
    """Print all available scenarios"""
    print("\nAvailable Load Test Scenarios:")
    print("=" * 80)
    for name, scenario in SCENARIOS.items():
        print(f"\n{scenario.name} ({name})")
        print(f"  Description: {scenario.description}")
        print(f"  Users: {scenario.users}, Spawn rate: {scenario.spawn_rate} per second")
        print(f"  Duration: {scenario.duration_minutes} minutes")
        print(f"  Tags: {', '.join(scenario.tags)}")


def list_test_suites() -> None:
    """Print all available test suites"""
    print("\nAvailable Test Suites:")
    print("=" * 80)
    for name, suite in TEST_SUITES.items():
        print(f"\n{name}")
        print(f"  Description: {suite['description']}")
        print(f"  Scenarios: {', '.join(suite['scenarios'])}")
        print(f"  Total Duration: {suite['total_duration_minutes']} minutes")


if __name__ == "__main__":
    list_scenarios()
    print("\n")
    list_test_suites()
