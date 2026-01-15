"""
Unit tests for line parsing logic.

Tests the parse_line() function from src/api/routes/data.py
"""

from src.api.routes.data import parse_line


class TestParseLineValid:
    """Tests for valid input lines."""

    def test_parse_valid_voltage_reading(self) -> None:
        result = parse_line("1649941817 Voltage 1.34")
        
        assert result is not None
        assert result.timestamp == 1649941817
        assert result.name == "Voltage"
        assert result.value == 1.34

    def test_parse_valid_current_reading(self) -> None:
        result = parse_line("1649941818 Current 12.0")
        
        assert result is not None
        assert result.timestamp == 1649941818
        assert result.name == "Current"
        assert result.value == 12.0

    def test_parse_integer_value(self) -> None:
        result = parse_line("1649941817 Voltage 5")
        
        assert result is not None
        assert result.value == 5.0

    def test_parse_negative_value(self) -> None:
        result = parse_line("1649941817 Temperature -10.5")
        
        assert result is not None
        assert result.value == -10.5

    def test_parse_zero_timestamp(self) -> None:
        result = parse_line("0 Voltage 1.34")
        
        assert result is not None
        assert result.timestamp == 0

    def test_parse_with_extra_whitespace(self) -> None:
        result = parse_line("  1649941817 Voltage 1.34  ")
        
        assert result is not None
        assert result.timestamp == 1649941817


class TestParseLineInvalid:
    """Tests for invalid input lines."""

    def test_empty_line(self) -> None:
        result = parse_line("")
        assert result is None

    def test_whitespace_only(self) -> None:
        result = parse_line("   ")
        assert result is None

    def test_missing_value(self) -> None:
        result = parse_line("1649941817 Voltage")
        assert result is None

    def test_missing_name_and_value(self) -> None:
        result = parse_line("1649941817")
        assert result is None

    def test_too_many_parts(self) -> None:
        result = parse_line("1649941817 Voltage 1.34 extra")
        assert result is None

    def test_negative_timestamp(self) -> None:
        result = parse_line("-123 Voltage 1.34")
        assert result is None

    def test_name_starts_with_number(self) -> None:
        result = parse_line("1649941817 123Voltage 1.34")
        assert result is None

    def test_name_starts_with_special_char(self) -> None:
        result = parse_line("1649941817 _Voltage 1.34")
        assert result is None

    def test_non_numeric_timestamp(self) -> None:
        result = parse_line("notanumber Voltage 1.34")
        assert result is None

    def test_non_numeric_value(self) -> None:
        result = parse_line("1649941817 Voltage abc")
        assert result is None

    def test_float_timestamp(self) -> None:
        result = parse_line("1649941817.5 Voltage 1.34")
        assert result is None


class TestParseLineEdgeCases:
    """Edge case tests."""

    def test_very_large_timestamp(self) -> None:
        result = parse_line("9999999999 Voltage 1.34")
        
        assert result is not None
        assert result.timestamp == 9999999999

    def test_very_small_value(self) -> None:
        result = parse_line("1649941817 Voltage 0.0001")
        
        assert result is not None
        assert result.value == 0.0001

    def test_very_large_value(self) -> None:
        result = parse_line("1649941817 Voltage 999999.99")
        
        assert result is not None
        assert result.value == 999999.99

    def test_metric_name_with_underscore(self) -> None:
        result = parse_line("1649941817 Voltage_RMS 1.34")
        
        assert result is not None
        assert result.name == "Voltage_RMS"

    def test_single_char_metric_name(self) -> None:
        result = parse_line("1649941817 V 1.34")
        
        assert result is not None
        assert result.name == "V"