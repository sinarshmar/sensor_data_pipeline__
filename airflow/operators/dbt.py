"""Custom dbt operators for Airflow."""

from airflow.operators.bash import BashOperator

from config.settings import DBT_PROJECT_DIR, DBT_PROFILES_DIR


class DbtRunOperator(BashOperator):
    """
    Execute dbt run command with optional model selection.

    Examples:
        # Run all models
        DbtRunOperator(task_id="dbt_run_all")

        # Run specific folder
        DbtRunOperator(task_id="dbt_run_staging", select="staging")

        # Run specific model
        DbtRunOperator(task_id="dbt_run_power", select="mart_daily_power")

        # Full refresh (ignore incremental)
        DbtRunOperator(task_id="dbt_full_refresh", full_refresh=True)
    """

    def __init__(
        self,
        task_id: str,
        select: str | None = None,
        exclude: str | None = None,
        full_refresh: bool = False,
        **kwargs,
    ) -> None:
        """
        Initialize dbt run operator.

        Args:
            task_id: Unique task identifier
            select: dbt model selection (e.g., "staging", "mart_daily_power")
            exclude: Models to exclude from run
            full_refresh: If True, ignore incremental logic and rebuild
            **kwargs: Additional BashOperator arguments
        """
        command = self._build_command(select, exclude, full_refresh)

        super().__init__(
            task_id=task_id,
            bash_command=command,
            **kwargs,
        )

    def _build_command(
        self,
        select: str | None,
        exclude: str | None,
        full_refresh: bool,
    ) -> str:
        """Build the dbt run command string."""
        cmd = f"cd {DBT_PROJECT_DIR} && dbt run"

        if select:
            cmd += f" --select {select}"
        if exclude:
            cmd += f" --exclude {exclude}"
        if full_refresh:
            cmd += " --full-refresh"

        cmd += f" --profiles-dir {DBT_PROFILES_DIR}"

        return cmd


class DbtTestOperator(BashOperator):
    """
    Execute dbt test command for data quality validation.

    Examples:
        # Test all models
        DbtTestOperator(task_id="dbt_test_all")

        # Test specific folder
        DbtTestOperator(task_id="dbt_test_staging", select="staging")
    """

    def __init__(
        self,
        task_id: str,
        select: str | None = None,
        exclude: str | None = None,
        **kwargs,
    ) -> None:
        """
        Initialize dbt test operator.

        Args:
            task_id: Unique task identifier
            select: dbt model selection to test
            exclude: Models to exclude from testing
            **kwargs: Additional BashOperator arguments
        """
        command = self._build_command(select, exclude)

        super().__init__(
            task_id=task_id,
            bash_command=command,
            **kwargs,
        )

    def _build_command(self, select: str | None, exclude: str | None) -> str:
        """Build the dbt test command string."""
        cmd = f"cd {DBT_PROJECT_DIR} && dbt test"

        if select:
            cmd += f" --select {select}"
        if exclude:
            cmd += f" --exclude {exclude}"

        cmd += f" --profiles-dir {DBT_PROFILES_DIR}"

        return cmd


class DbtDepsOperator(BashOperator):
    """
    Execute dbt deps command to install packages.

    Note: Typically run during Docker image build, not at runtime.
    Included here for completeness and manual/emergency use.
    """

    def __init__(self, task_id: str = "dbt_deps", **kwargs) -> None:
        command = f"cd {DBT_PROJECT_DIR} && dbt deps --profiles-dir {DBT_PROFILES_DIR}"

        super().__init__(
            task_id=task_id,
            bash_command=command,
            **kwargs,
        )
