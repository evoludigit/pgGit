#!/usr/bin/env python3
"""
Performance Benchmark Runner for pgGit

Runs benchmark SQL scripts and extracts performance metrics for regression detection.
"""

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional


class BenchmarkResult:
    """Represents a single benchmark result."""

    def __init__(self, name: str, duration_ms: float, extra: Optional[Dict] = None):
        self.name = name
        self.duration_ms = duration_ms
        self.extra = extra or {}

    def to_dict(self) -> Dict:
        return {
            "name": self.name,
            "duration_ms": self.duration_ms,
            **self.extra,
        }


class BenchmarkRunner:
    """Runs SQL benchmarks and collects metrics."""

    def __init__(self, db_url: str, benchmark_file: Path):
        self.db_url = db_url
        self.benchmark_file = benchmark_file
        self.results: List[BenchmarkResult] = []

    def run(self) -> List[BenchmarkResult]:
        """Execute benchmark SQL file and parse results."""
        print(f"Running benchmarks from: {self.benchmark_file}")

        try:
            # Run psql with benchmark file
            result = subprocess.run(
                ["psql", self.db_url, "-f", str(self.benchmark_file)],
                capture_output=True,
                text=True,
                check=True,
            )

            # Parse output for timing information
            self._parse_output(result.stderr)

            return self.results

        except subprocess.CalledProcessError as e:
            print(f"Error running benchmarks: {e}", file=sys.stderr)
            print(f"stdout: {e.stdout}", file=sys.stderr)
            print(f"stderr: {e.stderr}", file=sys.stderr)
            sys.exit(1)

    def _parse_output(self, output: str):
        """Parse psql output to extract benchmark results."""

        # Pattern for benchmark names
        bench_pattern = re.compile(r"=== Benchmark: (.+) ===")

        # Pattern for timing results (e.g., "Created 100 tables in: 00:00:01.234")
        timing_pattern = re.compile(r"in: (\d{2}):(\d{2}):(\d{2}\.?\d*)")

        current_benchmark = None

        for line in output.split("\n"):
            # Check for benchmark name
            bench_match = bench_pattern.search(line)
            if bench_match:
                current_benchmark = bench_match.group(1)
                continue

            # Check for timing
            timing_match = timing_pattern.search(line)
            if timing_match and current_benchmark:
                hours = int(timing_match.group(1))
                minutes = int(timing_match.group(2))
                seconds = float(timing_match.group(3))

                total_ms = (hours * 3600 + minutes * 60 + seconds) * 1000

                self.results.append(
                    BenchmarkResult(name=current_benchmark, duration_ms=total_ms)
                )

                current_benchmark = None  # Reset for next benchmark


def compare_benchmarks(
    baseline: List[BenchmarkResult],
    current: List[BenchmarkResult],
    threshold_percent: float = 10.0,
) -> Dict:
    """Compare two sets of benchmark results and detect regressions."""

    # Create lookup by name
    baseline_dict = {r.name: r for r in baseline}
    current_dict = {r.name: r for r in current}

    regressions = []
    improvements = []
    unchanged = []

    for name, current_result in current_dict.items():
        if name not in baseline_dict:
            continue  # New benchmark, skip

        baseline_result = baseline_dict[name]

        percent_change = (
            (current_result.duration_ms - baseline_result.duration_ms)
            / baseline_result.duration_ms
            * 100
        )

        comparison = {
            "name": name,
            "baseline_ms": baseline_result.duration_ms,
            "current_ms": current_result.duration_ms,
            "change_percent": percent_change,
        }

        if abs(percent_change) < threshold_percent:
            unchanged.append(comparison)
        elif percent_change > 0:
            regressions.append(comparison)
        else:
            improvements.append(comparison)

    return {
        "regressions": regressions,
        "improvements": improvements,
        "unchanged": unchanged,
        "has_regressions": len(regressions) > 0,
    }


def main():
    parser = argparse.ArgumentParser(description="Run pgGit performance benchmarks")
    parser.add_argument(
        "--db-url",
        default="postgresql://postgres@localhost/pggit_test",
        help="PostgreSQL connection URL",
    )
    parser.add_argument(
        "--benchmark-file",
        type=Path,
        default=Path("tests/benchmarks/baseline.sql"),
        help="Path to benchmark SQL file",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Output JSON file for results",
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        help="Baseline JSON file for comparison",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=10.0,
        help="Regression threshold percentage (default: 10%%)",
    )

    args = parser.parse_args()

    # Run benchmarks
    runner = BenchmarkRunner(args.db_url, args.benchmark_file)
    results = runner.run()

    # Save results to JSON
    results_data = {
        "timestamp": datetime.now().isoformat(),
        "benchmarks": [r.to_dict() for r in results],
    }

    if args.output:
        with open(args.output, "w") as f:
            json.dump(results_data, f, indent=2)
        print(f"Results saved to: {args.output}")

    # Compare with baseline if provided
    if args.baseline:
        with open(args.baseline) as f:
            baseline_data = json.load(f)

        baseline_results = [
            BenchmarkResult(**b) for b in baseline_data["benchmarks"]
        ]

        comparison = compare_benchmarks(baseline_results, results, args.threshold)

        print("\n=== Performance Comparison ===")
        print(f"Threshold: {args.threshold}%\n")

        if comparison["regressions"]:
            print("⚠️  REGRESSIONS DETECTED:")
            for r in comparison["regressions"]:
                print(
                    f"  - {r['name']}: {r['baseline_ms']:.2f}ms → {r['current_ms']:.2f}ms "
                    f"({r['change_percent']:+.1f}%)"
                )
            print()

        if comparison["improvements"]:
            print("✅ IMPROVEMENTS:")
            for r in comparison["improvements"]:
                print(
                    f"  - {r['name']}: {r['baseline_ms']:.2f}ms → {r['current_ms']:.2f}ms "
                    f"({r['change_percent']:+.1f}%)"
                )
            print()

        if comparison["unchanged"]:
            print(f"➖ UNCHANGED ({len(comparison['unchanged'])} benchmarks)")

        # Exit with error if regressions found
        if comparison["has_regressions"]:
            sys.exit(1)

    else:
        # Just print results
        print("\n=== Benchmark Results ===")
        for result in results:
            print(f"  {result.name}: {result.duration_ms:.2f}ms")

    print("\n✅ Benchmarks completed successfully!")


if __name__ == "__main__":
    main()
