"""
Example 2: Concurrency Testing

This example demonstrates how to test concurrent operations that may expose
race conditions, deadlocks, and serialization issues.

Concept:
  Concurrency tests use multiple threads/processes to run operations
  simultaneously, which can reveal timing-dependent bugs that don't show up
  in sequential tests.

Key Insight:
  Most production bugs are timing-dependent and only appear under load.
  Concurrency tests force concurrent execution to find these bugs.
"""

import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import pytest


class TestConcurrencyPatterns:
    """Examples of concurrent operation patterns."""

    @pytest.mark.chaos
    @pytest.mark.concurrent
    @pytest.mark.parametrize("num_workers", [2, 5, 10])
    def test_concurrent_counter_increment(self, num_workers: int):
        """
        Test: Concurrent increments with proper synchronization.

        Without a lock, increments would race and lose updates.
        This test verifies that with proper locking, all increments are counted.
        """
        counter = 0
        lock = threading.Lock()

        def worker():
            nonlocal counter
            for _ in range(100):
                with lock:
                    counter += 1

        # Run workers concurrently
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(worker) for _ in range(num_workers)]
            [f.result() for f in as_completed(futures)]

        # Verify all increments were counted
        expected = num_workers * 100
        assert counter == expected, f"Expected {expected} increments, got {counter}"

    @pytest.mark.chaos
    @pytest.mark.concurrent
    def test_concurrent_list_modifications(self):
        """
        Test: Concurrent modifications to shared data structure.

        This demonstrates why thread-safe data structures are important.
        """
        items = []
        lock = threading.Lock()

        def worker(worker_id: int):
            for i in range(10):
                with lock:
                    items.append((worker_id, i))

        # Run 5 workers
        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(worker, i) for i in range(5)]
            [f.result() for f in as_completed(futures)]

        # Verify all items were added
        assert len(items) == 50, f"Expected 50 items, got {len(items)}"

        # Verify uniqueness
        unique_items = set(items)
        assert len(unique_items) == 50, "All items should be unique"

    @pytest.mark.chaos
    @pytest.mark.concurrent
    def test_concurrent_dict_updates(self):
        """
        Test: Concurrent dictionary updates with locking.

        Dictionaries are not thread-safe in Python, so all updates
        must be protected with locks.
        """
        data = {}
        lock = threading.Lock()

        def worker(worker_id: int):
            for i in range(20):
                with lock:
                    key = f"worker_{worker_id}_item_{i}"
                    data[key] = i

        # Run 5 workers
        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(worker, i) for i in range(5)]
            [f.result() for f in as_completed(futures)]

        # Verify all updates succeeded
        assert len(data) == 100, f"Expected 100 items, got {len(data)}"

    @pytest.mark.chaos
    @pytest.mark.concurrent
    def test_race_condition_detection(self):
        """
        Test: Demonstrate a race condition (without locking).

        This test intentionally shows what happens WITHOUT proper locking.
        """
        counter = 0  # No lock!

        def worker():
            nonlocal counter
            # This is a race condition: read, increment, write are not atomic
            for _ in range(100):
                temp = counter
                temp += 1
                counter = temp

        # Run workers
        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(worker) for _ in range(5)]
            [f.result() for f in as_completed(futures)]

        # Without locking, we LOSE updates due to race condition
        expected = 500  # 5 workers * 100 increments
        # Due to race condition: counter < expected
        print(f"Expected: {expected}, Got: {counter}")
        # This assertion will likely FAIL, demonstrating the race condition

    @pytest.mark.chaos
    @pytest.mark.concurrent
    def test_barrier_synchronization(self):
        """
        Test: Using barriers to synchronize worker threads.

        Barriers ensure all threads reach a point before proceeding.
        """
        barrier = threading.Barrier(3)  # Sync 3 threads
        results = []

        def worker(worker_id: int):
            # Each worker does some work
            time.sleep(0.1 * worker_id)  # Stagger the workers

            # Wait for all workers
            barrier.wait()

            # All workers arrive at same time
            results.append((worker_id, "synchronized"))

        # Run 3 workers
        with ThreadPoolExecutor(max_workers=3) as executor:
            futures = [executor.submit(worker, i) for i in range(3)]
            [f.result() for f in as_completed(futures)]

        # All workers should complete
        assert len(results) == 3, "All workers should reach barrier"

    @pytest.mark.chaos
    @pytest.mark.concurrent
    def test_event_signaling(self):
        """
        Test: Using events for inter-thread communication.

        Events allow one thread to signal others that something happened.
        """
        event = threading.Event()
        results = []

        def waiter():
            results.append("waiting")
            event.wait()  # Wait for signal
            results.append("done")

        def signaler():
            time.sleep(0.1)  # Wait a bit
            results.append("signaling")
            event.set()  # Signal all waiters

        # Run waiter and signaler
        with ThreadPoolExecutor(max_workers=2) as executor:
            f1 = executor.submit(waiter)
            f2 = executor.submit(signaler)
            f1.result()
            f2.result()

        # Verify order
        assert results[0] == "waiting", "Waiter should start first"
        assert results[1] == "signaling", "Signaler should signal"
        assert results[2] == "done", "Waiter should complete after signal"


class TestConcurrencyEdgeCases:
    """Examples of edge cases in concurrent programming."""

    @pytest.mark.chaos
    @pytest.mark.concurrent
    def test_thread_local_storage(self):
        """
        Test: Using thread-local storage for thread-safe data.

        Each thread gets its own copy of data, no locking needed.
        """
        local_data = threading.local()
        results = []

        def worker(worker_id: int):
            # Set thread-local value
            local_data.value = worker_id
            time.sleep(0.01)  # Let other threads run

            # Read thread-local value (should be unchanged)
            results.append(local_data.value)

        # Run workers
        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(worker, i) for i in range(5)]
            [f.result() for f in as_completed(futures)]

        # Each thread sees its own value
        assert sorted(results) == [0, 1, 2, 3, 4], "Each thread should see its own value"

    @pytest.mark.chaos
    @pytest.mark.concurrent
    def test_no_data_loss_under_concurrent_writes(self):
        """
        Test: Ensure no data loss under concurrent writes with locking.
        """
        shared_list = []
        lock = threading.Lock()

        def writer(writer_id: int):
            for item_id in range(100):
                with lock:
                    shared_list.append((writer_id, item_id))

        # 5 writers, each adding 100 items
        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(writer, i) for i in range(5)]
            [f.result() for f in as_completed(futures)]

        # All data should be present
        assert len(shared_list) == 500, f"Expected 500 items, got {len(shared_list)}"

        # All unique
        unique = set(shared_list)
        assert len(unique) == 500, "All items should be unique"


class TestConcurrencyBoundaries:
    """Examples of testing behavior at concurrency boundaries."""

    @pytest.mark.chaos
    @pytest.mark.concurrent
    @pytest.mark.parametrize("num_workers", [1, 2, 5, 10, 20])
    def test_scaling_behavior(self, num_workers: int):
        """
        Test: System behavior scales with number of concurrent workers.

        This helps identify bottlenecks and contention issues.
        """
        results = []
        lock = threading.Lock()

        def worker(worker_id: int):
            return worker_id * 2

        # Run N workers
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(worker, i) for i in range(num_workers)]
            results = [f.result() for f in as_completed(futures)]

        # All workers should complete
        assert len(results) == num_workers, f"Expected {num_workers} results, got {len(results)}"

        # Results should be correct
        assert sorted(results) == [i * 2 for i in range(num_workers)], "Results should be correct"
