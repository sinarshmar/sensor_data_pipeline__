# Sensor Data Engineering Assessment

Sensor data ingestion and analytics API with dbt transformations.

> **Note:** This setup has been tested on macOS only. Windows users should use WSL2.

## Quick Start

### First-Time Setup

```bash
./scripts/setup.sh
```

This checks prerequisites (Docker, Poetry, Python 3.11+), installs dependencies, and starts all services.

### Manual Setup

```bash
# 1. Start services
docker compose up -d

# 2. Wait for initialization (first run only)
docker compose logs -f airflow-init

# 3. Run dbt transformations
docker exec -it sensor_data_airflow_scheduler bash -c \
  "cd /opt/airflow/dbt && dbt run --profiles-dir ."

# 4. Test the API
# POST data
curl -X POST http://localhost:5001/data \
  -H "Content-Type: text/plain" \
  -d '1649941817 Voltage 1.34
1649941818 Voltage 1.35
1649941817 Current 12.0
1649941818 Current 14.0'
# Expected: {"success": true}

# GET data
curl "http://localhost:5001/data?from=2022-04-14&to=2022-04-15"
# Expected: JSON array with 4 readings + 1 Power calculation
```

**Access:**
- API: http://localhost:5001
- Airflow UI: http://localhost:8080 (admin/admin)

---

## Architecture

```
POST /data → Bronze (raw) → dbt → Silver (typed) → Gold (Power) → GET /data
```

| Layer | Table | Purpose |
|-------|-------|---------|
| Bronze | `bronze.raw_readings` | Raw data as received (audit trail) |
| Silver | `silver.stg_readings` | Parsed, validated, typed |
| Gold | `gold.mart_daily_power` | Daily Power = avg(V) × avg(I) |

---

## Key Decisions

### Why Medallion Architecture?
Raw data preserved for reprocessing; each layer has single responsibility with clear lineage.

### Why dbt (not Spark)?
Sufficient for current scale. SQL-based transformations are easier to maintain and review. Can convert to Spark SQL later if data volume demands.

### Why Incremental Loading?
Both dbt models use `materialized='incremental'` with watermarks. Avoids full table scans. Addresses common feedback about "full reload instead of incremental."

### Why Modular Airflow?
Separates DAGs, operators, hooks, and config. New pipelines can reuse `DbtRunOperator` and `DbtTestOperator` without copy-paste. Pipeline runs hourly — balances data freshness vs compute cost.

### Why No Custom Dockerfile for Airflow?
Airflow is local-only; production uses Cloud Composer. Using official image + init-time package install is simpler than maintaining a custom Dockerfile.

### Why Terraform Not Deployed?
Included to demonstrate IaC practices (targeting GCP: Cloud SQL, Cloud Run, Secret Manager), not deployed. Cloud Composer costs ~$300/month. Code is validated and ready to deploy.

### Why Separate Database Connections (src/ vs airflow/)?
Airflow runs in separate container with no access to `src/`. Health check is one-off (no pooling needed). Both read from same env vars — no duplication.

### Why Clean Schema Names (silver, gold)?
Custom `generate_schema_name` macro overrides dbt default. Simpler for single-environment development. Can add environment prefixes (`dev_silver`, `prod_silver`) later.

---

## Type Safety

| Pattern | Usage | Benefit |
|---------|-------|---------|
| `@dataclass(frozen=True)` | `ParsedReading` | Immutable, hashable, prevents accidental mutation |
| `TypedDict` | `ReadingResponse`, `SuccessResponse` | Type-safe JSON responses with IDE autocompletion |
| `Pydantic BaseSettings` | `Settings` | Validated config from env vars with defaults |
| Return type unions | `SuccessResponse \| tuple[...]` | Explicit error handling paths |

---

## Connection Resilience

| Feature | Implementation | Purpose |
|---------|----------------|---------|
| Connection pooling | `psycopg2.pool.ThreadedConnectionPool` (2-10 connections) | Reuse connections, handle concurrent requests |
| Automatic retry | `tenacity` with exponential backoff (3 attempts, 1-10s) | Recover from transient database failures |
| Query timing | `TimedCursor` wrapper logs execution duration | Performance monitoring and slow query detection |
| Safe transactions | Context manager with auto commit/rollback | Prevent partial writes on errors |

---

## Data Quality Checks

| Column | Test | Business Impact if Violated |
|--------|------|----------------------------|
| `raw_id` | unique, not_null | Prevents duplicate readings, maintains audit trail |
| `reading_time` | not_null | GET /data filters by time — incomplete results if null |
| `metric_name` | not_null, accepted_values | Power calculation requires knowing Voltage vs Current |
| `metric_value` | not_null | Readings without values are meaningless |
| `reading_date` | unique (gold), not_null | One Power calculation per day |

---

## Running Tests

### Full Test Suite (Recommended)

```bash
./scripts/test_all.sh
```

Runs everything: containers, API, dbt, database verification, unit tests, linting, Terraform.

### Individual Tests

```bash
# Unit tests
poetry run pytest -v

# Type checking (strict mode)
poetry run pyright

# Linting
poetry run ruff check .

# dbt data quality tests
cd dbt && dbt test --profiles-dir .

# Terraform validation
cd terraform && terraform init -backend=false && terraform validate
```

---

## Additional Considerations

### Performance Measurement
Query timing implemented via `TimedCursor`. For production: add Datadog/Prometheus integration.

### POST-Heavy Optimization
- Batch inserts (reduce round trips)
- Async processing with queue
- Write-optimized indexes

### GET-Heavy Optimization
- Read replicas
- Caching layer (Redis)
- Materialized views for common queries

### Scaling to Millions of Connections
- Horizontal scaling (Cloud Run auto-scales)
- Database: Cloud SQL with read replicas
- CDC + streaming (Kafka) for real-time ingestion

---

## Future Considerations

### Cloud Deployment
| Component | Local | Production |
|-----------|-------|------------|
| Database | Docker PostgreSQL | Cloud SQL or Supabase |
| API | Docker container | Cloud Run |
| Orchestration | Docker Airflow | Cloud Composer |

### Terraform Improvements (Not Deployed)
Terraform configs are validated but symbolic — no cloud resources provisioned.
- Add Cloud SQL and Cloud Run modules when deploying
- Enable GCS backend for remote state
- Add IAM roles and service accounts
- Environment-specific tfvars (dev, staging, prod)

### CI/CD Enhancements (Partially Implemented)
CI workflow runs tests/linting; CD (deployment) is not implemented.
- Add CD workflow for automated deployment
- Docker image build and push to Container Registry
- Terraform plan/apply in pipeline
- dbt docs generation and hosting

### Observability
- Structured logging with correlation IDs
- Metrics collection (request latency, error rates)
- Alerting on pipeline failures
- Data quality dashboards

### Data Pipeline Enhancements
- Add data validation before bronze insert (schema enforcement)
- Implement CDC for real-time updates
- Add data lineage tracking
- Consider Apache Iceberg for lakehouse architecture (per job description)

---

## Project Structure

```
├── src/                  # Flask API
│   ├── api/              # Routes and app factory
│   ├── db/               # Connection pooling, repositories
│   └── config/           # Pydantic settings
├── dbt/                  # Transformations
│   ├── models/           # staging (silver), marts (gold)
│   └── macros/           # Custom schema naming
├── airflow/              # Orchestration
│   ├── dags/             # Pipeline definitions
│   ├── operators/        # Reusable dbt operators
│   ├── hooks/            # Database health checks
│   └── config/           # Centralized settings
├── terraform/            # IaC (GCP) - validated, not deployed
├── tests/unit/           # Unit tests
├── scripts/              # Setup and test scripts
├── .github/workflows/    # CI pipeline (tests, linting, pyright)
└── docker-compose.yml    # Local environment
```
