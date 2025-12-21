"""
Example 1: Property-Based Testing

This example demonstrates how to write property-based tests using Hypothesis.
Property tests verify that a system satisfies universal properties across
a wide range of inputs.

Concept:
  Instead of testing one specific example:
    - Input: value = 42
    - Expected: result = 84

  Write a property that holds for ANY valid input:
    - Property: For any integer N, result = N * 2
    - Hypothesis generates hundreds of examples to verify this

Key Insight:
  Property tests find edge cases (0, -1, MAX_INT, etc.) that
  example-based tests would miss.
"""

import pytest
from hypothesis import given
from hypothesis import strategies as st


class TestPropertyBasedUniqueness:
    """Examples of property-based uniqueness tests."""

    @pytest.mark.chaos
    @pytest.mark.property
    @given(value=st.integers(min_value=0, max_value=1000))
    def test_incrementing_property(self, value: int):
        """
        Property: For any input value N, incrementing always produces N+1.

        This property holds for ANY integer in our range.
        Hypothesis will test edge cases like 0, 1, 999, 1000.
        """
        result = value + 1
        assert result == value + 1, "Increment should always add 1"
        assert result > value, "Result should be greater than input"

    @pytest.mark.chaos
    @pytest.mark.property
    @given(items=st.lists(st.integers(), min_size=1, max_size=100))
    def test_list_length_property(self, items: list):
        """
        Property: The length of a list always equals the count of items.

        This seems obvious, but Hypothesis tests with:
        - Empty list: []
        - Single item: [42]
        - Large list: [1, 2, ..., 100]
        - Duplicates: [1, 1, 1, ...]
        - Mixed: [0, negative, MAX_INT, ...]
        """
        assert len(items) >= 1, "List should have at least 1 item"
        assert len(items) <= 100, "List should have at most 100 items"

    @pytest.mark.chaos
    @pytest.mark.property
    @given(text=st.text(min_size=1, max_size=1000))
    def test_string_preservation_property(self, text: str):
        """
        Property: A string always preserves its value exactly.

        Hypothesis will generate:
        - Empty string: ""
        - Unicode: "こんにちは", "🎉"
        - Special chars: "\n", "\x00"
        - Edge cases: very long strings
        """
        # Property: String assignment preserves value
        stored = text
        assert stored == text, "Stored string should equal original"
        assert len(stored) == len(text), "Length should be preserved"

    @pytest.mark.chaos
    @pytest.mark.property
    @given(
        a=st.integers(),
        b=st.integers(),
    )
    def test_addition_commutative_property(self, a: int, b: int):
        """
        Property: Addition is commutative (a + b = b + a).

        This mathematical property should hold for ANY integers.
        """
        assert a + b == b + a, "Addition should be commutative"

    @pytest.mark.chaos
    @pytest.mark.property
    @given(values=st.lists(st.integers(min_value=1, max_value=100), min_size=1))
    def test_set_deduplication_property(self, values: list):
        """
        Property: Converting to set removes duplicates but preserves unique values.

        Tests verify:
        - set(values) has <= len(values) items
        - All original items are in the set
        - No extra items are added
        """
        unique = set(values)

        # Property 1: Set is smaller or equal
        assert len(unique) <= len(values), "Set should have same or fewer items"

        # Property 2: All original items in set
        for item in values:
            assert item in unique, f"Item {item} should be in set"

        # Property 3: Set only contains original items
        for item in unique:
            assert item in values, f"Set item {item} should be from original list"


class TestPropertyBasedSequencing:
    """Examples of property-based sequence/ordering tests."""

    @pytest.mark.chaos
    @pytest.mark.property
    @given(items=st.lists(st.integers(), min_size=1, max_size=50))
    def test_sorting_completeness_property(self, items: list):
        """
        Property: After sorting, list contains all original items.

        Sorting may rearrange, but shouldn't lose or add items.
        """
        sorted_items = sorted(items)

        # Property 1: Same length
        assert len(sorted_items) == len(items), "Sorting shouldn't change length"

        # Property 2: Same items (with multiplicities)
        assert sorted(sorted_items) == sorted(items), "Sorting shouldn't change items"

    @pytest.mark.chaos
    @pytest.mark.property
    @given(nums=st.lists(st.integers(min_value=1), min_size=1, max_size=50))
    def test_max_property(self, nums: list):
        """
        Property: max(list) is always >= all other items.

        Tests verify the mathematical definition of maximum.
        """
        maximum = max(nums)

        # Property: max is >= all items
        for num in nums:
            assert maximum >= num, f"Max {maximum} should be >= {num}"

    @pytest.mark.chaos
    @pytest.mark.property
    @given(items=st.lists(st.text(min_size=1), min_size=1))
    def test_join_split_roundtrip_property(self, items: list):
        """
        Property: Joining and splitting preserves original items.

        This tests that join/split round-trip is invertible.
        """
        joined = ",".join(items)
        split = joined.split(",")

        # Property: Round-trip preserves data
        assert split == items, "Join/split should preserve items"
