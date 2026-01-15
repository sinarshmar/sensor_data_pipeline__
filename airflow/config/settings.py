"""Centralized Airflow configuration."""

import os
from datetime import datetime, timedelta
from typing import Any


# =============================================================================
# Environment Variables
# =============================================================================

POSTGRES_HOST: str = os.environ.get("POSTGRES_HOST", "postgres")
POSTGRES_PORT: str = os.environ.get("POSTGRES_PORT", "5432")
POSTGRES_USER: str = os.environ.get("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD: str = os.environ.get("POSTGRES_PASSWORD", "postgres")
POSTGRES_DB: str = os.environ.get("POSTGRES_DB", "sensor_data")


# =============================================================================
# dbt Configuration
# =============================================================================

DBT_PROJECT_DIR: str = "/opt/airflow/dbt"
DBT_PROFILES_DIR: str = "/opt/airflow/dbt"


# =============================================================================
# DAG Default Arguments
# =============================================================================
# Applied to all tasks unless overridden at task level.
# See: https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/dags.html

DEFAULT_ARGS: dict[str, Any] = {
    "owner": "sensor_data",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 3,
    "retry_delay": timedelta(minutes=2),
    "retry_exponential_backoff": True,
    "max_retry_delay": timedelta(minutes=10),
}


# =============================================================================
# Schedule Interval
# =============================================================================

SCHEDULE_HOURLY: str = "@hourly"


# =============================================================================
# DAG Start Date
# =============================================================================

DAG_START_DATE: datetime = datetime(2024, 1, 1)