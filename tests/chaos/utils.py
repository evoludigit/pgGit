"""
Chaos Engineering Utilities

This module provides utilities for injecting chaos into database operations,
capturing state snapshots, and measuring performance during chaos testing.
"""

import asyncio
import random
import time
from contextlib import contextmanager
from typing import Any, Awaitable, Callable

import psycopg


class ChaosInjector:
    """Utility class for injecting chaos into database operations."""

    @staticmethod
    async def random_delay(min_ms: int = 0, max_ms: int = 100) -> None:
        """Inject a random delay to simulate network latency."""
        delay = random.uniform(min_ms / 1000, max_ms / 1000)
        await asyncio.sleep(delay)

    @staticmethod
    def sync_random_delay(min_ms: int = 0, max_ms: int = 100) -> None:
        """Inject a random delay in synchronous code."""
        delay = random.uniform(min_ms / 1000, max_ms / 1000)
        time.sleep(delay)

    @staticmethod
    @contextmanager
    def simulate_connection_failure(probability: float = 0.1):
        """Context manager that randomly fails connections."""
        if random.random() < probability:
            raise psycopg.OperationalError("Simulated connection failure")
        yield

    @staticmethod
    async def with_retry(
        func: Callable[..., Awaitable[Any]],
        max_attempts: int = 3,
        backoff: float = 0.1,
        *args,
        **kwargs,
    ) -> Any:
        """Retry a function with exponential backoff."""
        for attempt in range(max_attempts):
            try:
                return await func(*args, **kwargs)
            except Exception:
                if attempt < max_attempts - 1:
                    await asyncio.sleep(backoff * (2**attempt))
                else:
                    raise  # Re-raise the last exception

    @staticmethod
    def sync_with_retry(
        func: Callable[..., Any],
        max_attempts: int = 3,
        backoff: float = 0.1,
        *args,
        **kwargs,
    ) -> Any:
        """Retry a synchronous function with exponential backoff."""
        for attempt in range(max_attempts):
            try:
                return func(*args, **kwargs)
            except Exception:
                if attempt < max_attempts - 1:
                    time.sleep(backoff * (2**attempt))
                else:
                    raise  # Re-raise the last exception

    @staticmethod
    async def simulate_deadlock(
        conn1: psycopg.AsyncConnection,
        conn2: psycopg.AsyncConnection,
    ) -> None:
        """Simulate a deadlock scenario between two connections."""
        # Start transaction on conn1 and lock resource A
        await conn1.execute("BEGIN")
        await conn1.execute("SELECT pg_advisory_lock(1)")
        await conn1.commit()

        # Start transaction on conn2 and lock resource B
        await conn2.execute("BEGIN")
        await conn2.execute("SELECT pg_advisory_lock(2)")
        await conn2.commit()

        # Now try to create deadlock: conn1 wants B, conn2 wants A
        # This will cause deadlock detection
        try:
            await asyncio.gather(
                conn1.execute("SELECT pg_advisory_lock(2)"),
                conn2.execute("SELECT pg_advisory_lock(1)"),
                return_exceptions=True,
            )
        except Exception:
            pass  # Expected deadlock
        finally:
            # Cleanup
            await conn1.execute("SELECT pg_advisory_unlock_all()")
            await conn2.execute("SELECT pg_advisory_unlock_all()")
            await conn1.rollback()
            await conn2.rollback()


class DatabaseStateSnapshot:
    """Capture and compare database state for validation."""

    def __init__(self, conn: psycopg.Connection) -> None:
        self.conn = conn
        self.snapshots: dict[str, list[dict]] = {}

    def capture(self, name: str, query: str) -> None:
        """Capture a snapshot of query results."""
        cursor = self.conn.execute(query)
        self.snapshots[name] = cursor.fetchall()

    def compare(self, name: str, query: str) -> tuple[bool, str]:
        """Compare current state to a snapshot."""
        if name not in self.snapshots:
            return False, f"No snapshot named '{name}'"

        cursor = self.conn.execute(query)
        current = cursor.fetchall()
        expected = self.snapshots[name]

        if current == expected:
            return True, "States match"
        return False, f"Expected {len(expected)} rows, got {len(current)} rows"

    def get_snapshot(self, name: str) -> list[dict] | None:
        """Get a stored snapshot."""
        return self.snapshots.get(name)

    def clear_snapshots(self) -> None:
        """Clear all stored snapshots."""
        self.snapshots.clear()


class AsyncDatabaseStateSnapshot:
    """Async version of DatabaseStateSnapshot."""

    def __init__(self, conn: psycopg.AsyncConnection) -> None:
        self.conn = conn
        self.snapshots: dict[str, list[dict]] = {}

    async def capture(self, name: str, query: str) -> None:
        """Capture a snapshot of query results."""
        cursor = await self.conn.execute(query)
        self.snapshots[name] = cursor.fetchall()

    async def compare(self, name: str, query: str) -> tuple[bool, str]:
        """Compare current state to a snapshot."""
        if name not in self.snapshots:
            return False, f"No snapshot named '{name}'"

        cursor = await self.conn.execute(query)
        current = cursor.fetchall()
        expected = self.snapshots[name]

        if current == expected:
            return True, "States match"
        return False, f"Expected {len(expected)} rows, got {len(current)} rows"

    def get_snapshot(self, name: str) -> list[dict] | None:
        """Get a stored snapshot."""
        return self.snapshots.get(name)

    def clear_snapshots(self) -> None:
        """Clear all stored snapshots."""
        self.snapshots.clear()


def measure_performance(func: Callable) -> Callable:
    """Decorator to measure function execution time."""

    async def async_wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = await func(*args, **kwargs)
        elapsed = time.perf_counter() - start
        print(f"{func.__name__} took {elapsed:.4f}s")
        return result

    def sync_wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = func(*args, **kwargs)
        elapsed = time.perf_counter() - start
        print(f"{func.__name__} took {elapsed:.4f}s")
        return result

    if asyncio.iscoroutinefunction(func):
        return async_wrapper
    return sync_wrapper


class TransactionMonitor:
    """Monitor active transactions and locks."""

    def __init__(self, conn: psycopg.Connection) -> None:
        self.conn = conn

    def get_active_transactions(self) -> list[dict]:
        """Get information about active transactions."""
        cursor = self.conn.execute("""
            SELECT
                pid,
                state,
                query,
                wait_event_type,
                wait_event,
                EXTRACT(epoch FROM (now() - query_start)) as query_age_seconds
            FROM pg_stat_activity
            WHERE datname = current_database()
            AND pid != pg_backend_pid()
            AND state IS NOT NULL
        """)
        return cursor.fetchall()

    def get_locks(self) -> list[dict]:
        """Get information about current locks."""
        cursor = self.conn.execute("""
            SELECT
                locktype,
                relation::regclass,
                mode,
                granted,
                pid,
                EXTRACT(epoch FROM (now() - granted)) as lock_age_seconds
            FROM pg_locks
            WHERE pid != pg_backend_pid()
        """)
        return cursor.fetchall()

    def get_blocking_queries(self) -> list[dict]:
        """Get information about queries that are blocking others."""
        cursor = self.conn.execute("""
            SELECT
                blocked.pid as blocked_pid,
                blocked.query as blocked_query,
                blocking.pid as blocking_pid,
                blocking.query as blocking_query,
                blocked.wait_event_type,
                blocked.wait_event
            FROM pg_stat_activity blocked
            JOIN pg_stat_activity blocking ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
            WHERE blocked.datname = current_database()
            AND blocked.pid != pg_backend_pid()
        """)
        return cursor.fetchall()


class AsyncTransactionMonitor:
    """Async version of TransactionMonitor."""

    def __init__(self, conn: psycopg.AsyncConnection) -> None:
        self.conn = conn

    async def get_active_transactions(self) -> list[dict]:
        """Get information about active transactions."""
        cursor = await self.conn.execute("""
            SELECT
                pid,
                state,
                query,
                wait_event_type,
                wait_event,
                EXTRACT(epoch FROM (now() - query_start)) as query_age_seconds
            FROM pg_stat_activity
            WHERE datname = current_database()
            AND pid != pg_backend_pid()
            AND state IS NOT NULL
        """)
        return cursor.fetchall()

    async def get_locks(self) -> list[dict]:
        """Get information about current locks."""
        cursor = await self.conn.execute("""
            SELECT
                locktype,
                relation::regclass,
                mode,
                granted,
                pid,
                EXTRACT(epoch FROM (now() - granted)) as lock_age_seconds
            FROM pg_locks
            WHERE pid != pg_backend_pid()
        """)
        return cursor.fetchall()

    async def get_blocking_queries(self) -> list[dict]:
        """Get information about queries that are blocking others."""
        cursor = await self.conn.execute("""
            SELECT
                blocked.pid as blocked_pid,
                blocked.query as blocked_query,
                blocking.pid as blocking_pid,
                blocking.query as blocking_query,
                blocked.wait_event_type,
                blocked.wait_event
            FROM pg_stat_activity blocked
            JOIN pg_stat_activity blocking ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
            WHERE blocked.datname = current_database()
            AND blocked.pid != pg_backend_pid()
        """)
        return cursor.fetchall()
