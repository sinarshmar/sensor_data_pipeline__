"""
Database connection management with pooling and retry logic.

Provides:
- Connection pooling (reuse connections)
- Automatic retry on transient failures
- Health check functionality
"""

import logging
import time
from contextlib import contextmanager
from typing import Any, Generator

from psycopg2 import pool, OperationalError, Error
from psycopg2.extensions import connection as PgConnection, cursor as PgCursor
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential,
    retry_if_exception_type,
)

from src.config.settings import get_settings, Settings

logger: logging.Logger = logging.getLogger(__name__)

_connection_pool: pool.ThreadedConnectionPool | None = None
_test_pool_override: pool.ThreadedConnectionPool | None = None


def set_test_pool(test_pool: pool.ThreadedConnectionPool | None) -> None:
    """Set a test pool override for unit testing."""
    global _test_pool_override
    _test_pool_override = test_pool


def get_pool() -> pool.ThreadedConnectionPool:
    """Get or create the connection pool."""
    global _connection_pool

    if _test_pool_override is not None:
        return _test_pool_override
    
    if _connection_pool is None:
        settings: Settings = get_settings()
        _connection_pool = pool.ThreadedConnectionPool(
            minconn=settings.db_pool_min,
            maxconn=settings.db_pool_max,
            dsn=settings.database_url,
        )
        logger.info(
            "Database connection pool created (min=%d, max=%d)",
            settings.db_pool_min,
            settings.db_pool_max,
        )
    
    return _connection_pool


def close_pool() -> None:
    """Close all connections in the pool."""
    global _connection_pool

    if _connection_pool is not None:
        _connection_pool.closeall()
        _connection_pool = None
        logger.info("Connection pool closed")


@contextmanager
def get_connection() -> Generator[PgConnection, None, None]:
    """Get a database connection from the pool."""
    pool_instance: pool.ThreadedConnectionPool = get_pool()
    # Note: types-psycopg2 stubs don't fully cover the pool module.
    # The stubs still provide type coverage for most of psycopg2 (cursors,
    # exceptions, etc.), so we keep them and use targeted ignores here.
    conn: PgConnection = pool_instance.getconn()  # type: ignore[assignment]

    try:
        yield conn
        conn.commit()  # type: ignore[union-attr]
    except Exception:
        # Catch all exceptions to ensure rollback before re-raising.
        # This prevents leaving transactions open on any error type.
        conn.rollback()  # type: ignore[union-attr]
        raise
    finally:
        pool_instance.putconn(conn)  # type: ignore[arg-type]


@contextmanager
def timed_cursor(conn: PgConnection) -> Generator["TimedCursor", None, None]:
    """Context manager that logs query execution time."""
    with conn.cursor() as cur:
        yield TimedCursor(cur)


class TimedCursor:
    """Wrapper around cursor that logs query timing."""

    def __init__(self, cursor: PgCursor) -> None:
        self._cursor: PgCursor = cursor

    def execute(self, query: str, params: tuple[Any, ...] | None = None) -> None:
        start: float = time.perf_counter()
        self._cursor.execute(query, params)
        duration_ms: float = (time.perf_counter() - start) * 1000

        # Log query timing (truncate query for readability)
        query_preview: str = query[:50].replace('\n', ' ')
        logger.debug("Query: %s... - %.2fms", query_preview, duration_ms)

    def fetchone(self) -> tuple[Any, ...] | None:
        return self._cursor.fetchone()  # type: ignore[no-any-return]

    def fetchall(self) -> list[tuple[Any, ...]]:
        return self._cursor.fetchall()  # type: ignore[no-any-return]

    @property
    def description(self) -> Any:
        return self._cursor.description


@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=1, max=10),
    retry=retry_if_exception_type(OperationalError),
)
def execute_with_retry(
    conn: PgConnection,
    query: str,
    params: tuple[Any, ...] | None = None
) -> list[tuple[Any, ...]]:
    """Execute a query with automatic retry on connection errors."""
    with conn.cursor() as cur:
        cur.execute(query, params)
        
        if cur.description is not None:
            rows: list[tuple[Any, ...]] = cur.fetchall()
            return rows
        return []


def check_database_health() -> bool:
    """Check if database is reachable."""
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
        return True
    except (Error, OSError) as e:
        logger.error("Database health check failed: %s", e)
        return False