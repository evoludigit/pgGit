"""
Performance Profiling & Optimization Suite
============================================

Analyzes API performance, identifies bottlenecks, and provides optimization recommendations.

Features:
- Load test result analysis
- Performance bottleneck identification
- Cache hit rate monitoring
- Query performance analysis
- Optimization recommendations
- Cache TTL tuning
"""

import csv
import json
import sys
from pathlib import Path
from typing import Dict, List, Tuple, Any
from dataclasses import dataclass
from statistics import mean, median, stdev


@dataclass
class EndpointMetrics:
    """Performance metrics for an endpoint"""
    name: str
    requests: int
    failures: int
    avg_ms: float
    min_ms: float
    max_ms: float
    median_ms: float
    p95_ms: float
    p99_ms: float
    error_rate: float


class PerformanceAnalyzer:
    """Analyzes load test results and identifies bottlenecks"""

    def __init__(self, csv_file: str):
        """Initialize with load test CSV results"""
        self.csv_file = Path(csv_file)
        self.endpoints: Dict[str, EndpointMetrics] = {}
        self.bottlenecks: List[str] = []
        self.recommendations: List[str] = []

    def parse_csv(self) -> None:
        """Parse Locust CSV results"""
        if not self.csv_file.exists():
            print(f"Warning: CSV file not found: {self.csv_file}")
            return

        with open(self.csv_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                self._process_row(row)

    def _process_row(self, row: Dict[str, str]) -> None:
        """Process a single CSV row"""
        try:
            name = row.get('Name', '').strip()
            if not name or name == 'Total':
                return

            metrics = EndpointMetrics(
                name=name,
                requests=int(row.get('Request Count', 0)),
                failures=int(row.get('Failure Count', 0)),
                avg_ms=float(row.get('Average Response Time', 0)),
                min_ms=float(row.get('Min Response Time', 0)),
                max_ms=float(row.get('Max Response Time', 0)),
                median_ms=float(row.get('Median Response Time', 0)),
                p95_ms=float(row.get('95%', 0)),
                p99_ms=float(row.get('99%', 0)),
                error_rate=float(row.get('Failure Rate', '0%').rstrip('%') or 0)
            )

            self.endpoints[name] = metrics
        except (KeyError, ValueError) as e:
            print(f"Warning: Error parsing row: {e}")

    def identify_bottlenecks(self) -> None:
        """Identify performance bottlenecks"""
        self.bottlenecks = []

        for name, metrics in self.endpoints.items():
            # High response time
            if metrics.p99_ms > 500:
                self.bottlenecks.append(
                    f"CRITICAL: {name} P99 latency {metrics.p99_ms:.0f}ms exceeds 500ms target"
                )
            elif metrics.p99_ms > 300:
                self.bottlenecks.append(
                    f"WARNING: {name} P99 latency {metrics.p99_ms:.0f}ms exceeds 300ms target"
                )

            # High error rate
            if metrics.error_rate > 1.0:
                self.bottlenecks.append(
                    f"CRITICAL: {name} error rate {metrics.error_rate:.2f}% exceeds 1% threshold"
                )

            # Large variance (indicates inconsistent performance)
            if metrics.max_ms > metrics.p99_ms * 2:
                self.bottlenecks.append(
                    f"WARNING: {name} has high variance (max {metrics.max_ms:.0f}ms vs P99 {metrics.p99_ms:.0f}ms)"
                )

    def generate_recommendations(self) -> None:
        """Generate optimization recommendations"""
        self.recommendations = []

        for name, metrics in self.endpoints.items():
            # Cache-related recommendations
            if 'list' in name.lower() or 'get' in name.lower():
                if metrics.avg_ms > 100:
                    self.recommendations.append(
                        f"Cache optimization: Consider longer TTL for {name} "
                        f"(currently {metrics.avg_ms:.0f}ms avg)"
                    )

            # Database query optimization
            if 'dashboard' in name.lower() or 'overview' in name.lower():
                if metrics.avg_ms > 150:
                    self.recommendations.append(
                        f"Query optimization: Consider materialized views for {name}"
                    )

            # Connection pool optimization
            if metrics.p99_ms > metrics.p95_ms * 1.5:
                self.recommendations.append(
                    f"Connection pool: Increase pool size or optimize connection usage for {name}"
                )

            # Caching strategy
            if 'alert' in name.lower() and metrics.avg_ms > 75:
                self.recommendations.append(
                    f"Cache strategy: Implement L2 Redis caching for {name}"
                )

    def print_summary(self) -> None:
        """Print performance summary"""
        print("\n" + "=" * 80)
        print("PERFORMANCE ANALYSIS SUMMARY")
        print("=" * 80 + "\n")

        # Endpoint metrics
        print("Endpoint Performance Metrics:")
        print("-" * 80)
        print(f"{'Endpoint':<40} {'Avg':<8} {'P95':<8} {'P99':<8} {'Errors':<8}")
        print("-" * 80)

        for name, metrics in sorted(self.endpoints.items(), key=lambda x: x[1].p99_ms, reverse=True):
            print(
                f"{name:<40} "
                f"{metrics.avg_ms:<8.0f} "
                f"{metrics.p95_ms:<8.0f} "
                f"{metrics.p99_ms:<8.0f} "
                f"{metrics.error_rate:<8.2f}%"
            )

        # Bottlenecks
        if self.bottlenecks:
            print("\n" + "=" * 80)
            print("IDENTIFIED BOTTLENECKS")
            print("=" * 80 + "\n")
            for bottleneck in sorted(self.bottlenecks):
                status = "🔴 CRITICAL" if "CRITICAL" in bottleneck else "🟡 WARNING"
                print(f"{status}: {bottleneck}")

        # Recommendations
        if self.recommendations:
            print("\n" + "=" * 80)
            print("OPTIMIZATION RECOMMENDATIONS")
            print("=" * 80 + "\n")
            for i, rec in enumerate(self.recommendations, 1):
                print(f"{i}. {rec}")

        print("\n" + "=" * 80)

    def get_cache_tuning(self) -> Dict[str, int]:
        """Recommend cache TTLs based on metrics"""
        cache_ttl = {}

        for name, metrics in self.endpoints.items():
            # Base TTL on response time and request count
            if metrics.requests > 1000:  # High traffic
                ttl = 300  # 5 minutes
            elif metrics.requests > 100:  # Medium traffic
                ttl = 120  # 2 minutes
            elif metrics.requests > 10:   # Low traffic
                ttl = 60   # 1 minute
            else:
                ttl = 30   # 30 seconds

            # Adjust based on latency
            if metrics.p99_ms > 200:
                ttl = max(ttl, 300)  # At least 5 minutes
            elif metrics.p99_ms < 50:
                ttl = min(ttl, 60)   # Max 1 minute

            cache_ttl[name] = ttl

        return cache_ttl


class OptimizationPlan:
    """Generates an optimization implementation plan"""

    def __init__(self, analyzer: PerformanceAnalyzer):
        self.analyzer = analyzer

    def generate(self) -> Dict[str, Any]:
        """Generate optimization plan"""
        plan = {
            "immediate": [],
            "short_term": [],
            "long_term": [],
            "cache_ttl": self.analyzer.get_cache_tuning(),
            "estimated_impact": {}
        }

        # Immediate optimizations (high impact, low effort)
        plan["immediate"].append({
            "action": "Increase cache TTLs for high-traffic endpoints",
            "rationale": "Reduce database load for frequently accessed data",
            "effort": "Low",
            "estimated_impact": "15-25% latency reduction"
        })

        plan["immediate"].append({
            "action": "Enable L2 Redis caching for dashboard endpoints",
            "rationale": "Distributed caching for consistent performance across instances",
            "effort": "Low",
            "estimated_impact": "30-40% latency reduction"
        })

        # Short-term optimizations (medium impact/effort)
        plan["short_term"].append({
            "action": "Optimize database indexes for alert queries",
            "rationale": "Many alert endpoints have high latency",
            "effort": "Medium",
            "estimated_impact": "20-30% latency reduction"
        })

        plan["short_term"].append({
            "action": "Implement query result pagination",
            "rationale": "Reduce data transfer for list endpoints",
            "effort": "Medium",
            "estimated_impact": "10-20% latency reduction"
        })

        # Long-term optimizations
        plan["long_term"].append({
            "action": "Implement materialized views for aggregations",
            "rationale": "Pre-compute expensive dashboard calculations",
            "effort": "High",
            "estimated_impact": "40-50% latency reduction"
        })

        plan["long_term"].append({
            "action": "Add read replicas for read-heavy queries",
            "rationale": "Distribute query load across multiple instances",
            "effort": "High",
            "estimated_impact": "25-35% latency reduction"
        })

        return plan

    def print_plan(self) -> None:
        """Print optimization plan"""
        plan = self.generate()

        print("\n" + "=" * 80)
        print("OPTIMIZATION IMPLEMENTATION PLAN")
        print("=" * 80 + "\n")

        # Immediate actions
        print("IMMEDIATE ACTIONS (Next 1-2 hours)")
        print("-" * 80)
        for i, action in enumerate(plan["immediate"], 1):
            print(f"\n{i}. {action['action']}")
            print(f"   Rationale: {action['rationale']}")
            print(f"   Effort: {action['effort']}")
            print(f"   Expected Impact: {action['estimated_impact']}")

        # Short-term actions
        print("\n\nSHORT-TERM ACTIONS (Next 4-8 hours)")
        print("-" * 80)
        for i, action in enumerate(plan["short_term"], 1):
            print(f"\n{i}. {action['action']}")
            print(f"   Rationale: {action['rationale']}")
            print(f"   Effort: {action['effort']}")
            print(f"   Expected Impact: {action['estimated_impact']}")

        # Long-term actions
        print("\n\nLONG-TERM ACTIONS (Next sprint)")
        print("-" * 80)
        for i, action in enumerate(plan["long_term"], 1):
            print(f"\n{i}. {action['action']}")
            print(f"   Rationale: {action['rationale']}")
            print(f"   Effort: {action['effort']}")
            print(f"   Expected Impact: {action['estimated_impact']}")

        # Cache TTL recommendations
        print("\n\nCACHE TTL RECOMMENDATIONS")
        print("-" * 80)
        for endpoint, ttl in sorted(plan["cache_ttl"].items()):
            print(f"{endpoint:<40} {ttl}s")

        print("\n" + "=" * 80)


def main():
    """Main entry point"""
    if len(sys.argv) < 2:
        print("Usage: python profile_and_optimize.py <csv_file>")
        print("Example: python profile_and_optimize.py results/load_test_stats.csv")
        sys.exit(1)

    csv_file = sys.argv[1]

    # Analyze performance
    analyzer = PerformanceAnalyzer(csv_file)
    analyzer.parse_csv()
    analyzer.identify_bottlenecks()
    analyzer.generate_recommendations()
    analyzer.print_summary()

    # Generate optimization plan
    plan_generator = OptimizationPlan(analyzer)
    plan_generator.print_plan()


if __name__ == "__main__":
    main()
