"""
Unit tests for Power calculation logic.

Power = AVG(Voltage) × AVG(Current)

Note: The actual Power calculation happens in dbt (mart_daily_power.sql).
These tests verify the formula logic and edge cases.
"""

import pytest


def calculate_power(voltage_readings: list[float], current_readings: list[float]) -> float | None:
    """Calculate Power = AVG(Voltage) × AVG(Current). Returns None if either list is empty."""
    if not voltage_readings or not current_readings:
        return None
    
    avg_voltage = sum(voltage_readings) / len(voltage_readings)
    avg_current = sum(current_readings) / len(current_readings)
    
    return avg_voltage * avg_current


class TestPowerCalculationBasic:
    """Basic Power calculation tests."""

    def test_single_reading_each(self) -> None:
        result = calculate_power([1.34], [12.0])
        
        assert result is not None
        assert result == pytest.approx(16.08)

    def test_multiple_readings(self) -> None:
        # AVG(1.34, 1.35) = 1.345
        # AVG(12.0, 14.0) = 13.0
        # Power = 1.345 × 13.0 = 17.485
        result = calculate_power([1.34, 1.35], [12.0, 14.0])
        
        assert result is not None
        assert result == pytest.approx(17.485)

    def test_sample_data_from_assessment(self) -> None:
        """Test with exact data from assessment sample."""
        voltages = [1.34, 1.35]
        currents = [12.0, 14.0]
        
        result = calculate_power(voltages, currents)
        
        # AVG(V) = 1.345, AVG(I) = 13.0
        # Power = 17.485
        assert result is not None
        assert result == pytest.approx(17.485)


class TestPowerCalculationEdgeCases:
    """Edge case tests for Power calculation."""

    def test_empty_voltage_list(self) -> None:
        result = calculate_power([], [12.0])
        assert result is None

    def test_empty_current_list(self) -> None:
        result = calculate_power([1.34], [])
        assert result is None

    def test_both_empty(self) -> None:
        result = calculate_power([], [])
        assert result is None

    def test_zero_voltage(self) -> None:
        result = calculate_power([0.0], [12.0])
        
        assert result is not None
        assert result == 0.0

    def test_zero_current(self) -> None:
        result = calculate_power([1.34], [0.0])
        
        assert result is not None
        assert result == 0.0

    def test_negative_values(self) -> None:
        """Negative values are technically valid (though unusual for V/I)."""
        result = calculate_power([-1.0], [10.0])
        
        assert result is not None
        assert result == pytest.approx(-10.0)

    def test_large_number_of_readings(self) -> None:
        """Test with many readings."""
        voltages = [1.0 + i * 0.01 for i in range(100)]  # 1.00 to 1.99
        currents = [10.0 + i * 0.1 for i in range(100)]  # 10.0 to 19.9
        
        result = calculate_power(voltages, currents)
        
        assert result is not None
        # AVG(V) ≈ 1.495, AVG(I) ≈ 14.95
        assert result == pytest.approx(1.495 * 14.95, rel=0.01)


class TestPowerCalculationPrecision:
    """Precision and rounding tests."""

    def test_floating_point_precision(self) -> None:
        """Ensure no floating point errors."""
        result = calculate_power([0.1, 0.2], [0.3, 0.4])
        
        # AVG(V) = 0.15, AVG(I) = 0.35
        # Power = 0.0525
        assert result is not None
        assert result == pytest.approx(0.0525)

    def test_very_small_values(self) -> None:
        result = calculate_power([0.001], [0.002])
        
        assert result is not None
        assert result == pytest.approx(0.000002)

    def test_very_large_values(self) -> None:
        result = calculate_power([1000.0], [2000.0])
        
        assert result is not None
        assert result == pytest.approx(2000000.0)