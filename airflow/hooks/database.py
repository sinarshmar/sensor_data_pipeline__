"""Database hook for health checks and connectivity."""

import psycopg2
from psycopg2.extensions import connection as PgConnection

from config.settings import (
    POSTGRES_HOST,
    POSTGRES_PORT,
    POSTGRES_USER,
    POSTGRES_PASSWORD,
    POSTGRES_DB,
)


def get_database_connection() -> PgConnection:
    """
    Create a database connection using centralized config.
    
    Returns:
        psycopg2 connection object
        
    Raises:
        psycopg2.OperationalError: If connection fails
    """
    return psycopg2.connect(
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD,
        dbname=POSTGRES_DB,
    )


def check_database_health() -> bool:
    """
    Verify database connectivity before running pipeline.
    
    Used as a pre-flight check to fail fast if DB is unreachable,
    rather than failing mid-pipeline during dbt execution.
    
    Returns:
        True if database is healthy
        
    Raises:
        Exception: If health check fails (triggers Airflow retry)
    """
    conn: PgConnection = get_database_connection()
    
    try:
        # Exception intentionally not caught — propagates to Airflow
        # which handles retries. Finally ensures connection cleanup.

        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            result = cur.fetchone()
            
            if result is None or result[0] != 1:
                raise Exception("Database health check: unexpected result")
                
        return True
        
    finally:
        conn.close()


def check_bronze_table_exists() -> bool:
    """
    Verify bronze.raw_readings table exists.
    
    Additional validation to ensure schema is initialized
    before running transformations.
    
    Returns:
        True if table exists
        
    Raises:
        Exception: If table doesn't exist
    """
    conn: PgConnection = get_database_connection()
    
    try:
        # Exception intentionally not caught — propagates to Airflow
        # which handles retries. Finally ensures connection cleanup.

        with conn.cursor() as cur:
            cur.execute("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables 
                    WHERE table_schema = 'bronze' 
                    AND table_name = 'raw_readings'
                )
            """)
            result = cur.fetchone()
            
            if result is None or not result[0]:
                raise Exception("Table bronze.raw_readings does not exist")
                
        return True
        
    finally:
        conn.close()