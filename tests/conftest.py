"""
Pytest configuration and shared fixtures.

Fixtures defined here are available to all test files automatically.
"""

import pytest


@pytest.fixture
def sample_valid_lines() -> list[str]:
    """Valid sensor reading lines."""
    return [
        "1649941817 Voltage 1.34",
        "1649941818 Voltage 1.35",
        "1649941817 Current 12.0",
        "1649941818 Current 14.0",
    ]


@pytest.fixture
def sample_invalid_lines() -> list[str]:
    """Invalid sensor reading lines."""
    return [
        "",                              # Empty
        "   ",                           # Whitespace only
        "1649941817 Voltage",            # Missing value
        "1649941817",                    # Missing name and value
        "Voltage 1.34",                  # Missing timestamp
        "-123 Voltage 1.34",             # Negative timestamp
        "1649941817 123Invalid 1.34",    # Name starts with number
        "1649941817 Voltage abc",        # Non-numeric value
        "not a number Voltage 1.34",     # Non-numeric timestamp
    ]


@pytest.fixture
def sample_readings_data() -> list[dict[str, str | float]]:
    """Sample readings for power calculation tests."""
    return [
        {"metric": "Voltage", "value": 1.34},
        {"metric": "Voltage", "value": 1.35},
        {"metric": "Current", "value": 12.0},
        {"metric": "Current", "value": 14.0},
    ]