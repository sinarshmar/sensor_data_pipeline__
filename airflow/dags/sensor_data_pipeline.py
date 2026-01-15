"""
Sensor Data Pipeline DAG.

Transforms sensor data: Bronze → Silver → Gold using dbt.
Runs hourly.
"""

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.utils.task_group import TaskGroup

# Modular imports
from config.settings import DEFAULT_ARGS, SCHEDULE_HOURLY, DAG_START_DATE
from hooks.database import check_database_health
from operators.dbt import DbtRunOperator, DbtTestOperator


# =============================================================================
# DAG Definition
# =============================================================================

with DAG(
    dag_id="sensor_data_pipeline",
    description="Transform sensor data: Bronze → Silver → Gold",
    default_args=DEFAULT_ARGS,
    schedule_interval=SCHEDULE_HOURLY,
    start_date=DAG_START_DATE,
    catchup=False,
    tags=["dbt", "sensor_data", "sensor-data"],
    doc_md="""
    ## Sensor Data Pipeline

    Orchestrates the dbt transformation pipeline for sensor data.

    ### Tasks
    1. **health_check**: Verify database connectivity
    2. **dbt_run_staging**: Transform Bronze → Silver
    3. **dbt_run_marts**: Transform Silver → Gold
    4. **dbt_test**: Run data quality tests

    ### Schedule
    Runs every hour to process new sensor readings.

    ### On Failure
    Tasks retry 3 times with exponential backoff (2min → 4min → 8min).

    ### Architecture
    This DAG uses modular components:
    - `config/settings.py` - Centralized configuration
    - `hooks/database.py` - Database health checks
    - `operators/dbt.py` - Reusable dbt operators

    ### dbt Packages
    dbt-utils is installed during Docker image build (not at runtime)
    to avoid external dependencies during pipeline execution.
    """,
) as dag:

    # -------------------------------------------------------------------------
    # Task: Health Check
    # -------------------------------------------------------------------------
    health_check = PythonOperator(
        task_id="health_check",
        python_callable=check_database_health,
        doc="Verify database is reachable before running transformations",
    )

    # -------------------------------------------------------------------------
    # Task Group: dbt Transformations
    # -------------------------------------------------------------------------
    with TaskGroup(group_id="dbt_transformations") as dbt_group:

        # Bronze → Silver (staging)
        dbt_run_staging = DbtRunOperator(
            task_id="dbt_run_staging",
            select="staging",
            doc="Transform raw readings from Bronze to Silver layer",
        )

        # Silver → Gold (marts)
        dbt_run_marts = DbtRunOperator(
            task_id="dbt_run_marts",
            select="marts",
            doc="Calculate daily Power aggregations in Gold layer",
        )

        # Task dependencies within group
        dbt_run_staging >> dbt_run_marts

    # -------------------------------------------------------------------------
    # Task: dbt Tests
    # -------------------------------------------------------------------------
    dbt_test = DbtTestOperator(
        task_id="dbt_test",
        doc="Run data quality tests on Silver and Gold layers",
    )

    # -------------------------------------------------------------------------
    # DAG Dependencies
    # -------------------------------------------------------------------------
    health_check >> dbt_group >> dbt_test
