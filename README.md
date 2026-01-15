# Sensor Data Data Engineering Assessment

Sensor data ingestion and analytics API with dbt transformations.

## Quick Start

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
Raw data preserved for reprocessing and debugging. Each layer has single responsibility. Clear lineage from source to aggregation.

### Why dbt (not Spark)?
Sufficient for current scale. SQL-based transformations are easier to maintain and review. Can convert to Spark SQL later if data volume demands.

### Why Incremental Loading?
Both dbt models use `materialized='incremental'` with watermarks. Avoids full table scans. Addresses common feedback about "full reload instead of incremental."

### Why Modular Airflow?
Separates DAGs, operators, hooks, and config. New pipelines can reuse `DbtRunOperator` and `DbtTestOperator` without copy-paste.

### Why No Custom Dockerfile for Airflow?
Airflow is local-only; production uses Cloud Composer. Using official image + init-time package install is simpler than maintaining a custom Dockerfile.

### Why Terraform Not Deployed?
Cloud Composer costs ~$300/month (not in GCP free tier). Terraform code is validated and ready to deploy when budget allows.

### Why Separate Database Connections (src/ vs airflow/)?
Airflow runs in separate container with no access to `src/`. Health check is one-off (no pooling needed). Both read from same env vars — no duplication.

### Why Clean Schema Names (silver, gold)?
Custom `generate_schema_name` macro overrides dbt default. Simpler for single-environment development. Can add environment prefixes (`dev_silver`, `prod_silver`) later.

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

### Testing Strategy
- **Unit tests:** Parsing, validation, power calculation logic
- **dbt tests:** Schema tests (not_null, unique, accepted_values), custom tests (dbt_utils)
- **Integration:** Full pipeline tested via docker compose

### Performance Measurement
Add response time logging middleware. For production: integrate with observability tools (Datadog, CloudWatch, Prometheus).

### POST-Heavy Optimization
- Batch inserts (reduce round trips)
- Async processing with queue
- Write-optimized indexes

### GET-Heavy Optimization
- Read replicas
- Caching layer (Redis)
- Materialized views for common queries

### Scaling to Millions of Connections
- Connection pooling (implemented via psycopg2)
- Horizontal scaling (Cloud Run auto-scales)
- Database: Cloud SQL with read replicas
- Consider CDC + streaming (Kafka) for real-time ingestion

---

## Future Considerations

### Cloud Deployment
| Component | Local | Production |
|-----------|-------|------------|
| Database | Docker PostgreSQL | Cloud SQL or Supabase |
| API | Docker container | Cloud Run |
| Orchestration | Docker Airflow | Cloud Composer |

### Terraform Improvements
- Add Cloud SQL and Cloud Run modules when deploying
- Enable GCS backend for remote state
- Add IAM roles and service accounts
- Environment-specific tfvars (dev, staging, prod)

### CI/CD Enhancements
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
│   └── models/           # staging (silver), marts (gold)
├── airflow/              # Orchestration
│   ├── dags/             # Pipeline definitions
│   ├── operators/        # Reusable dbt operators
│   ├── hooks/            # Database health checks
│   └── config/           # Centralized settings
├── terraform/            # IaC (GCP) - validated, not deployed
├── tests/                # Unit tests
├── scripts/              # Database init
└── docker-compose.yml    # Local environment
```
