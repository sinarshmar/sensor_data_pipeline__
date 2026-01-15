"""
Unit tests for date parsing and validation logic.

Tests the parse_iso_date() and format_timestamp() functions.
"""

from datetime import datetime, timezone

from src.api.routes.data import parse_iso_date, format_timestamp


class TestParseIsoDateValid:
    """Tests for valid date strings."""

    def test_date_only(self) -> None:
        result = parse_iso_date("2022-04-14")
        
        assert result is not None
        assert result.year == 2022
        assert result.month == 4
        assert result.day == 14

    def test_datetime_with_z(self) -> None:
        result = parse_iso_date("2022-04-14T13:10:17Z")
        
        assert result is not None
        assert result.hour == 13
        assert result.minute == 10
        assert result.second == 17

    def test_datetime_with_milliseconds_z(self) -> None:
        result = parse_iso_date("2022-04-14T13:10:17.123Z")
        
        assert result is not None
        assert result.microsecond == 123000

    def test_datetime_without_z(self) -> None:
        result = parse_iso_date("2022-04-14T13:10:17")
        
        assert result is not None
        assert result.hour == 13

    def test_datetime_with_milliseconds_no_z(self) -> None:
        result = parse_iso_date("2022-04-14T13:10:17.456")
        
        assert result is not None
        assert result.microsecond == 456000

    def test_result_has_utc_timezone(self) -> None:
        result = parse_iso_date("2022-04-14")
        
        assert result is not None
        assert result.tzinfo == timezone.utc


class TestParseIsoDateInvalid:
    """Tests for invalid date strings."""

    def test_empty_string(self) -> None:
        result = parse_iso_date("")
        assert result is None

    def test_invalid_format(self) -> None:
        result = parse_iso_date("14-04-2022")
        assert result is None

    def test_invalid_date(self) -> None:
        result = parse_iso_date("2022-13-45")
        assert result is None

    def test_random_string(self) -> None:
        result = parse_iso_date("not a date")
        assert result is None

    def test_timestamp_number(self) -> None:
        result = parse_iso_date("1649941817")
        assert result is None


class TestFormatTimestamp:
    """Tests for timestamp formatting."""

    def test_format_basic(self) -> None:
        dt = datetime(2022, 4, 14, 13, 10, 17, tzinfo=timezone.utc)
        result = format_timestamp(dt)
        
        assert result == "2022-04-14T13:10:17.000Z"

    def test_format_with_microseconds(self) -> None:
        dt = datetime(2022, 4, 14, 13, 10, 17, 123456, tzinfo=timezone.utc)
        result = format_timestamp(dt)
        
        # Microseconds truncated to milliseconds
        assert result == "2022-04-14T13:10:17.123Z"

    def test_format_midnight(self) -> None:
        dt = datetime(2022, 4, 14, 0, 0, 0, tzinfo=timezone.utc)
        result = format_timestamp(dt)
        
        assert result == "2022-04-14T00:00:00.000Z"

    def test_format_end_of_day(self) -> None:
        dt = datetime(2022, 4, 14, 23, 59, 59, tzinfo=timezone.utc)
        result = format_timestamp(dt)
        
        assert result == "2022-04-14T23:59:59.000Z"