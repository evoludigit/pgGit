"""
Custom Exception Hierarchy for pgGit API
========================================

Structured exception system for better error handling, logging, and recovery.
Replaces generic exceptions with domain-specific errors that include context.

Exception Hierarchy:
- PgGitException (base)
  - DatabaseException
    - TransactionException
    - IntegrityException
    - ConnectionException
  - MergeException
    - MergeConflictException
    - InvalidMergeException
    - MergeOperationException
  - ValidationException
    - InvalidInputException
    - InvalidStateException
  - ResourceException
    - ResourceNotFoundException
    - ResourceAlreadyExistsException

Benefits:
- Specific exception types for different failure modes
- Structured context data for debugging
- Recovery hints for clients
- Proper logging with categorization
"""

from typing import Optional, Dict, Any
from datetime import datetime


class PgGitException(Exception):
    """
    Base exception for all pgGit errors.

    All custom exceptions inherit from this to allow unified handling.
    Includes structured context for debugging and logging.
    """

    def __init__(
        self,
        message: str,
        *,
        error_code: Optional[str] = None,
        context: Optional[Dict[str, Any]] = None,
        recovery_hint: Optional[str] = None,
        original_error: Optional[Exception] = None
    ):
        super().__init__(message)
        self.message = message
        self.error_code = error_code or self.__class__.__name__
        self.context = context or {}
        self.recovery_hint = recovery_hint
        self.original_error = original_error
        self.timestamp = datetime.utcnow()

    def to_dict(self) -> Dict[str, Any]:
        """Convert exception to structured dictionary for logging/API responses"""
        return {
            "error_type": self.__class__.__name__,
            "error_code": self.error_code,
            "error_message": self.message,  # Renamed to avoid logging conflict
            "context": self.context,
            "recovery_hint": self.recovery_hint,
            "timestamp": self.timestamp.isoformat(),
        }


# ===== Database Exceptions =====

class DatabaseException(PgGitException):
    """Base class for all database-related errors"""
    pass


class TransactionException(DatabaseException):
    """
    Transaction-related errors (rollback failures, deadlocks, etc.)

    Use when: Transaction cannot be committed or rolled back
    Recovery: Retry operation or check database state
    """

    def __init__(
        self,
        message: str,
        *,
        transaction_id: Optional[str] = None,
        operation: Optional[str] = None,
        **kwargs
    ):
        context = kwargs.pop('context', {})
        context.update({
            'transaction_id': transaction_id,
            'operation': operation,
        })
        super().__init__(
            message,
            context=context,
            recovery_hint="Retry the operation or check database transaction state",
            **kwargs
        )


class IntegrityException(DatabaseException):
    """
    Data integrity violations (foreign keys, unique constraints, etc.)

    Use when: Database constraint is violated
    Recovery: Fix data to satisfy constraints
    """

    def __init__(
        self,
        message: str,
        *,
        constraint_name: Optional[str] = None,
        table_name: Optional[str] = None,
        **kwargs
    ):
        context = kwargs.pop('context', {})
        context.update({
            'constraint_name': constraint_name,
            'table_name': table_name,
        })
        super().__init__(
            message,
            context=context,
            recovery_hint="Ensure data satisfies database constraints",
            **kwargs
        )


class ConnectionException(DatabaseException):
    """
    Database connection errors (timeout, connection lost, etc.)

    Use when: Cannot connect to or communicate with database
    Recovery: Check database availability and retry
    """

    def __init__(
        self,
        message: str,
        *,
        host: Optional[str] = None,
        database: Optional[str] = None,
        **kwargs
    ):
        context = kwargs.pop('context', {})
        context.update({
            'host': host,
            'database': database,
        })
        super().__init__(
            message,
            context=context,
            recovery_hint="Check database connectivity and retry",
            **kwargs
        )


# ===== Merge Exceptions =====

class MergeException(PgGitException):
    """Base class for all merge-related errors"""
    pass


class MergeConflictException(MergeException):
    """
    Merge conflicts detected that require manual resolution.

    Use when: Merge detects conflicts that cannot be auto-resolved
    Recovery: Resolve conflicts manually
    """

    def __init__(
        self,
        message: str,
        *,
        merge_id: Optional[str] = None,
        conflict_count: Optional[int] = None,
        source_branch_id: Optional[int] = None,
        target_branch_id: Optional[int] = None,
        **kwargs
    ):
        context = kwargs.pop('context', {})
        context.update({
            'merge_id': merge_id,
            'conflict_count': conflict_count,
            'source_branch_id': source_branch_id,
            'target_branch_id': target_branch_id,
        })
        super().__init__(
            message,
            context=context,
            recovery_hint="Resolve conflicts manually using conflict resolution endpoints",
            **kwargs
        )


class InvalidMergeException(MergeException):
    """
    Invalid merge operation requested (self-merge, invalid strategy, etc.)

    Use when: Merge parameters are logically invalid
    Recovery: Fix merge parameters
    """

    def __init__(
        self,
        message: str,
        *,
        source_branch_id: Optional[int] = None,
        target_branch_id: Optional[int] = None,
        merge_strategy: Optional[str] = None,
        **kwargs
    ):
        context = kwargs.pop('context', {})
        context.update({
            'source_branch_id': source_branch_id,
            'target_branch_id': target_branch_id,
            'merge_strategy': merge_strategy,
        })
        super().__init__(
            message,
            context=context,
            recovery_hint="Check merge parameters and ensure they are valid",
            **kwargs
        )


class MergeOperationException(MergeException):
    """
    Merge operation failed during execution.

    Use when: Merge operation fails for operational reasons
    Recovery: Check operation state and retry
    """

    def __init__(
        self,
        message: str,
        *,
        merge_id: Optional[str] = None,
        operation_step: Optional[str] = None,
        **kwargs
    ):
        context = kwargs.pop('context', {})
        context.update({
            'merge_id': merge_id,
            'operation_step': operation_step,
        })
        super().__init__(
            message,
            context=context,
            recovery_hint="Check merge operation status and retry if needed",
            **kwargs
        )


# ===== Validation Exceptions =====

class ValidationException(PgGitException):
    """Base class for validation errors"""
    pass


class InvalidInputException(ValidationException):
    """
    Invalid input data (IDs, strings, etc.)

    Use when: Input validation fails
    Recovery: Correct input and retry
    """

    def __init__(
        self,
        message: str,
        *,
        field_name: Optional[str] = None,
        field_value: Optional[Any] = None,
        expected_format: Optional[str] = None,
        **kwargs
    ):
        context = kwargs.pop('context', {})
        context.update({
            'field_name': field_name,
            'field_value': field_value,
            'expected_format': expected_format,
        })
        super().__init__(
            message,
            context=context,
            recovery_hint="Provide valid input matching expected format",
            **kwargs
        )


class InvalidStateException(ValidationException):
    """
    Operation invalid in current state.

    Use when: Operation cannot proceed due to current state
    Recovery: Ensure system is in correct state
    """

    def __init__(
        self,
        message: str,
        *,
        current_state: Optional[str] = None,
        expected_state: Optional[str] = None,
        resource_id: Optional[str] = None,
        **kwargs
    ):
        context = kwargs.pop('context', {})
        context.update({
            'current_state': current_state,
            'expected_state': expected_state,
            'resource_id': resource_id,
        })
        super().__init__(
            message,
            context=context,
            recovery_hint="Ensure resource is in correct state before operation",
            **kwargs
        )


# ===== Resource Exceptions =====

class ResourceException(PgGitException):
    """Base class for resource-related errors"""
    pass


class ResourceNotFoundException(ResourceException):
    """
    Requested resource not found.

    Use when: Resource lookup fails
    Recovery: Verify resource exists
    """

    def __init__(
        self,
        message: str,
        *,
        resource_type: Optional[str] = None,
        resource_id: Optional[Any] = None,
        **kwargs
    ):
        context = kwargs.pop('context', {})
        context.update({
            'resource_type': resource_type,
            'resource_id': resource_id,
        })
        super().__init__(
            message,
            context=context,
            recovery_hint=f"Verify {resource_type or 'resource'} exists and ID is correct",
            **kwargs
        )


class ResourceAlreadyExistsException(ResourceException):
    """
    Resource already exists (duplicate creation attempt).

    Use when: Attempting to create resource that already exists
    Recovery: Use existing resource or delete and recreate
    """

    def __init__(
        self,
        message: str,
        *,
        resource_type: Optional[str] = None,
        resource_id: Optional[Any] = None,
        **kwargs
    ):
        context = kwargs.pop('context', {})
        context.update({
            'resource_type': resource_type,
            'resource_id': resource_id,
        })
        super().__init__(
            message,
            context=context,
            recovery_hint="Use existing resource or delete before creating",
            **kwargs
        )


# ===== Configuration Exceptions =====

class ConfigurationException(PgGitException):
    """
    Configuration errors (missing settings, invalid values, etc.)

    Use when: Application configuration is invalid
    Recovery: Fix configuration and restart
    """

    def __init__(
        self,
        message: str,
        *,
        config_key: Optional[str] = None,
        config_value: Optional[Any] = None,
        **kwargs
    ):
        context = kwargs.pop('context', {})
        context.update({
            'config_key': config_key,
            'config_value': config_value,
        })
        super().__init__(
            message,
            context=context,
            recovery_hint="Check application configuration and restart",
            **kwargs
        )
