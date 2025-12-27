"""
Test fixtures for pgGit tests

This package provides reusable test fixtures and scenario builders for
constructing reproducible test environments across all phases.

Architecture:
- scenario_builder.py: Core ScenarioBuilder class for composing test data
- pytest fixtures use transaction-scoped cleanup for isolation
"""

from .scenario_builder import ScenarioBuilder

__all__ = ['ScenarioBuilder']
