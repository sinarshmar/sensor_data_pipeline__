"""Repository for readings database operations."""

from datetime import datetime, date

from src.config.settings import get_settings
from src.db.connection import get_connection


def save_to_bronze(lines: list[str]) -> int:
    """Save raw lines to bronze.raw_readings."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            count: int = 0
            for line in lines:
                stripped: str = line.strip()
                if stripped:
                    cur.execute(
                        "INSERT INTO bronze.raw_readings (raw_line) VALUES (%s)",
                        (stripped,)
                    )
                    count += 1
    return count


def get_readings_by_date_range(
    from_date: date,
    to_date: date
) -> list[tuple[datetime, str, float]]:
    """Get readings from silver and gold layers within date range."""
    settings = get_settings()

    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT reading_time, metric_name, metric_value
                FROM {settings.silver_schema}.stg_readings
                WHERE reading_date >= %s AND reading_date < %s

                UNION ALL

                SELECT reading_time, metric_name, metric_value
                FROM {settings.gold_schema}.mart_daily_power
                WHERE reading_date >= %s AND reading_date < %s

                ORDER BY 1, 2
            """, (from_date, to_date, from_date, to_date))

            rows: list[tuple[datetime, str, float]] = cur.fetchall()
    return rows