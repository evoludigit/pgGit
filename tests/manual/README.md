# Manual Testing Procedures for pgGit

This directory contains procedures for testing pgGit scenarios that require special environments, manual setup, or cannot be reliably automated.

## Procedures

### [Deadlock Testing](./deadlock.md)
Tests the system's ability to detect and recover from deadlock scenarios. Requires carefully timed concurrent operations.

**Related Test:** `test_deadlock_detection_and_recovery` in `tests/e2e/test_concurrency.py`

### [Crash Recovery](./crash.md)
Tests the system's recovery behavior when the database crashes or connection is forcefully closed.

**Related Test:** `test_database_crash_recovery` in `tests/chaos/test_crash_recovery.py`

### [Disk Space Exhaustion](./diskspace.md)
Tests the system's behavior when disk space runs out during backup or retention operations.

**Related Tests:** `TestDiskSpace` class in `tests/chaos/test_disk_space.py`

## Why Manual Testing?

Some scenarios are difficult or impossible to test reliably in CI/CD environments:

1. **Deadlock Detection:** Requires precise timing and multiple concurrent sessions with coordinated operations
2. **Crash Recovery:** Requires intentionally crashing the database or connections
3. **Disk Space:** Requires special Docker volumes or test infrastructure that may not be available

## Running Manual Tests

1. Choose a procedure from above
2. Follow the setup instructions
3. Execute the test steps
4. Verify the expected outcomes
5. Document any issues or deviations

## Integration with CI/CD

Automated tests validate the **core functionality** of these features:
- Transaction safety is tested through other tests
- Error handling is verified via function code inspection
- Sequential operations validate business logic

The manual tests complement this by testing the **edge cases** that require special environments.

## Best Practices

- Run manual tests in an isolated environment
- Use a test database that can be safely destroyed
- Monitor system resources during testing
- Document results for future reference
- Consider security implications when testing failure scenarios
