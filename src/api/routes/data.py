"""
Data endpoints for sensor readings.

POST /data - Ingest raw sensor data
GET /data  - Retrieve readings by date range
"""

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, TypedDict

from flask import Blueprint, request
import psycopg2

from src.db.repositories.readings import save_to_bronze, get_readings_by_date_range

logger: logging.Logger = logging.getLogger(__name__)
data_bp: Blueprint = Blueprint("data", __name__)


class ReadingResponse(TypedDict):
    time: str
    name: str
    value: float


class SuccessResponse(TypedDict):
    success: bool


@dataclass(frozen=True)
class ParsedReading:
    timestamp: int
    name: str
    value: float


@data_bp.post("/data")
def post_data() -> SuccessResponse | tuple[SuccessResponse, int]:
    """Ingest sensor readings from plaintext format: {unix_timestamp} {metric_name} {value}"""
    content_type: str | None = request.content_type
    if not content_type or not content_type.startswith("text/plain"):
        return SuccessResponse(success=False)

    raw_data: str | None = request.get_data(as_text=True)
    if not raw_data or not raw_data.strip():
        return SuccessResponse(success=False)

    lines: list[str] = raw_data.strip().split("\n")

    parsed_readings: list[ParsedReading] = []
    for line in lines:
        if not line.strip():
            continue
        result: ParsedReading | None = parse_line(line)
        if result is None:
            return SuccessResponse(success=False)
        parsed_readings.append(result)

    if parsed_readings:
        try:
            save_to_bronze(lines)
        except psycopg2.Error as e:
            logger.error("POST /data: Database error - %s", e)
            return SuccessResponse(success=False)
    
    return SuccessResponse(success=True)


def parse_line(line: str) -> ParsedReading | None:
    """Parse a single line: {unix_timestamp} {metric_name} {value}"""
    parts: list[str] = line.strip().split()
    if len(parts) != 3:
        return None

    try:
        timestamp: int = int(parts[0])
        name: str = parts[1]
        value: float = float(parts[2])

        if timestamp < 0 or not name or not name[0].isalpha():
            return None
        return ParsedReading(timestamp=timestamp, name=name, value=value)
    except (ValueError, TypeError):
        return None


@data_bp.get("/data")
def get_data() -> list[ReadingResponse] | SuccessResponse:
    """Retrieve readings within a date range (from/to query params)."""
    from_str: str | None = request.args.get("from")
    to_str: str | None = request.args.get("to")

    if not from_str or not to_str:
        return SuccessResponse(success=False)

    from_dt: datetime | None = parse_iso_date(from_str)
    to_dt: datetime | None = parse_iso_date(to_str)

    if from_dt is None or to_dt is None:
        return SuccessResponse(success=False)

    from_dt = from_dt.replace(hour=0, minute=0, second=0, microsecond=0)
    to_dt = to_dt.replace(hour=0, minute=0, second=0, microsecond=0)

    if "T" not in to_str:
        to_dt = to_dt + timedelta(days=1)

    try:
        rows: list[tuple[Any, ...]] = get_readings_by_date_range(
            from_dt.date(),
            to_dt.date()
        )
        readings: list[ReadingResponse] = [
            ReadingResponse(
                time=format_timestamp(row[0]),
                name=row[1],
                value=row[2]
            )
            for row in rows
        ]
        return readings
    except psycopg2.Error as e:
        logger.error("GET /data: Database error - %s", e)
        return SuccessResponse(success=False)


def parse_iso_date(date_str: str) -> datetime | None:
    formats: list[str] = [
        "%Y-%m-%dT%H:%M:%S.%fZ",
        "%Y-%m-%dT%H:%M:%SZ",
        "%Y-%m-%dT%H:%M:%S.%f",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d",
    ]
    
    for fmt in formats:
        try:
            dt: datetime = datetime.strptime(date_str, fmt)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt
        except ValueError:
            continue
    
    return None


def format_timestamp(dt: datetime) -> str:
    base: str = dt.strftime("%Y-%m-%dT%H:%M:%S.")
    millis: str = f"{dt.microsecond // 1000:03d}"
    return f"{base}{millis}Z"