"""
Chaos Engineering Test Suite

This package contains chaos engineering tests for the pgGit PostgreSQL extension.
These tests validate system behavior under adverse conditions including:

- Concurrency: Race conditions, deadlocks, serialization failures
- Failures: Transaction rollbacks, connection losses, crashes
- Resource exhaustion: Connection pool limits, memory pressure
- Data corruption: Schema migration failures, partial commits

For more information, see tests/chaos/README.md
"""
