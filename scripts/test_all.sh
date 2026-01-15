#!/bin/bash

# =============================================================================
# Sensor Data Data Pipeline - Full Test Script
# =============================================================================
# Runs all tests: containers, API, dbt, Airflow, unit tests, linting
# Usage: ./scripts/test_all.sh
# =============================================================================

set -e  # Exit on first error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

print_header() {
    echo ""
    echo "==========================================================================="
    echo -e "${YELLOW}$1${NC}"
    echo "==========================================================================="
}

print_step() {
    echo ""
    echo -e "${YELLOW}[$1] $2${NC}"
}

pass() {
    echo -e "${GREEN}✓ PASSED${NC}"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}✗ FAILED: $1${NC}"
    FAILED=$((FAILED + 1))
}

# -----------------------------------------------------------------------------
# Pre-flight Checks
# -----------------------------------------------------------------------------

print_header "PRE-FLIGHT CHECKS"

print_step "0.1" "Checking Docker is running..."
if docker info > /dev/null 2>&1; then
    pass
else
    fail "Docker is not running"
    exit 1
fi

print_step "0.2" "Checking Poetry is installed..."
if command -v poetry &> /dev/null; then
    pass
else
    fail "Poetry is not installed"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 1: Clean Start
# -----------------------------------------------------------------------------

print_header "STEP 1: CLEAN START"

print_step "1.1" "Stopping existing containers..."
docker compose down -v 2>/dev/null || true
pass

print_step "1.2" "Starting all services..."
docker compose up -d
sleep 5  # Wait for services to initialize
pass

print_step "1.3" "Waiting for Airflow init to complete..."
# Wait for airflow-init to complete (macOS doesn't have timeout, use loop with counter)
WAIT_COUNT=0
while [ $WAIT_COUNT -lt 60 ]; do
    if docker compose logs airflow-init 2>&1 | grep -q "complete"; then
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 1))
done
sleep 5
pass

# -----------------------------------------------------------------------------
# Step 2: Container Health
# -----------------------------------------------------------------------------

print_header "STEP 2: CONTAINER HEALTH"

print_step "2.1" "Checking PostgreSQL..."
if docker exec sensor_data_postgres pg_isready -U postgres -d sensor_data > /dev/null 2>&1; then
    pass
else
    fail "PostgreSQL not ready"
fi

print_step "2.2" "Checking API container..."
if docker compose ps api | grep -q "healthy"; then
    pass
else
    # Give it more time
    sleep 10
    if docker compose ps api | grep -q "Up"; then
        pass
    else
        fail "API container not healthy"
    fi
fi

print_step "2.3" "Checking Airflow scheduler..."
if docker compose ps airflow-scheduler | grep -q "Up"; then
    pass
else
    fail "Airflow scheduler not running"
fi

# -----------------------------------------------------------------------------
# Step 3: API Tests
# -----------------------------------------------------------------------------

print_header "STEP 3: API TESTS"

print_step "3.1" "Testing GET /health..."
HEALTH_RESPONSE=$(curl -s http://localhost:5001/health)
if echo "$HEALTH_RESPONSE" | grep -q '"status":"healthy"'; then
    pass
else
    fail "Health check failed: $HEALTH_RESPONSE"
fi

print_step "3.2" "Testing POST /data (valid)..."
POST_RESPONSE=$(curl -s -X POST http://localhost:5001/data \
    -H "Content-Type: text/plain" \
    -d '1649941817 Voltage 1.34
1649941818 Voltage 1.35
1649941817 Current 12.0
1649941818 Current 14.0')
if echo "$POST_RESPONSE" | grep -q '"success":true'; then
    pass
else
    fail "POST valid data failed: $POST_RESPONSE"
fi

print_step "3.3" "Testing POST /data (invalid)..."
POST_INVALID=$(curl -s -X POST http://localhost:5001/data \
    -H "Content-Type: text/plain" \
    -d '1649941817 Voltage 1.34
1649941818 1.35 Voltage')
if echo "$POST_INVALID" | grep -q '"success":false'; then
    pass
else
    fail "POST invalid data should return false: $POST_INVALID"
fi

# -----------------------------------------------------------------------------
# Step 4: Database Verification
# -----------------------------------------------------------------------------

print_header "STEP 4: DATABASE VERIFICATION"

print_step "4.1" "Checking bronze layer..."
BRONZE_COUNT=$(docker exec sensor_data_postgres psql -U postgres -d sensor_data -t -c \
    "SELECT COUNT(*) FROM bronze.raw_readings;" | tr -d ' ')
if [ "$BRONZE_COUNT" -eq 4 ]; then
    pass
else
    fail "Expected 4 rows in bronze, got $BRONZE_COUNT"
fi

# -----------------------------------------------------------------------------
# Step 5: dbt Transformations
# -----------------------------------------------------------------------------

print_header "STEP 5: DBT TRANSFORMATIONS"

print_step "5.1" "Running dbt..."
if docker exec sensor_data_airflow_scheduler bash -c \
    "cd /opt/airflow/dbt && dbt run --profiles-dir ." > /dev/null 2>&1; then
    pass
else
    fail "dbt run failed"
fi

print_step "5.2" "Running dbt tests..."
if docker exec sensor_data_airflow_scheduler bash -c \
    "cd /opt/airflow/dbt && dbt test --profiles-dir ." > /dev/null 2>&1; then
    pass
else
    fail "dbt test failed"
fi

# -----------------------------------------------------------------------------
# Step 6: Silver/Gold Verification
# -----------------------------------------------------------------------------

print_header "STEP 6: SILVER/GOLD VERIFICATION"

print_step "6.1" "Checking silver layer..."
SILVER_COUNT=$(docker exec sensor_data_postgres psql -U postgres -d sensor_data -t -c \
    "SELECT COUNT(*) FROM silver.stg_readings;" | tr -d ' ')
if [ "$SILVER_COUNT" -eq 4 ]; then
    pass
else
    fail "Expected 4 rows in silver, got $SILVER_COUNT"
fi

print_step "6.2" "Checking gold layer..."
GOLD_COUNT=$(docker exec sensor_data_postgres psql -U postgres -d sensor_data -t -c \
    "SELECT COUNT(*) FROM gold.mart_daily_power;" | tr -d ' ')
if [ "$GOLD_COUNT" -eq 1 ]; then
    pass
else
    fail "Expected 1 row in gold, got $GOLD_COUNT"
fi

print_step "6.3" "Verifying Power calculation..."
POWER_VALUE=$(docker exec sensor_data_postgres psql -U postgres -d sensor_data -t -c \
    "SELECT ROUND(metric_value::numeric, 2) FROM gold.mart_daily_power;" | tr -d ' ')
if [ "$POWER_VALUE" = "17.49" ] || [ "$POWER_VALUE" = "17.48" ]; then
    pass
else
    fail "Expected Power ≈ 17.49, got $POWER_VALUE"
fi

# -----------------------------------------------------------------------------
# Step 7: GET /data API
# -----------------------------------------------------------------------------

print_header "STEP 7: GET /DATA API"

print_step "7.1" "Testing GET /data..."
GET_RESPONSE=$(curl -s "http://localhost:5001/data?from=2022-04-14&to=2022-04-15")
ITEM_COUNT=$(echo "$GET_RESPONSE" | grep -o '"name"' | wc -l | tr -d ' ')
if [ "$ITEM_COUNT" -eq 5 ]; then
    pass
else
    fail "Expected 5 items (4 readings + 1 Power), got $ITEM_COUNT"
fi

# -----------------------------------------------------------------------------
# Step 8: Unit Tests
# -----------------------------------------------------------------------------

print_header "STEP 8: UNIT TESTS"

print_step "8.1" "Running pytest..."
if poetry run pytest -v > /dev/null 2>&1; then
    pass
else
    fail "pytest failed"
fi

# -----------------------------------------------------------------------------
# Step 9: Code Quality
# -----------------------------------------------------------------------------

print_header "STEP 9: CODE QUALITY"

print_step "9.1" "Running ruff (linting)..."
if poetry run ruff check . > /dev/null 2>&1; then
    pass
else
    fail "ruff found issues"
fi

print_step "9.2" "Running pyright (type checking)..."
if poetry run pyright > /dev/null 2>&1; then
    pass
else
    fail "pyright found type errors"
fi

# -----------------------------------------------------------------------------
# Step 10: Terraform Validation
# -----------------------------------------------------------------------------

print_header "STEP 10: TERRAFORM VALIDATION"

print_step "10.1" "Checking Terraform format..."
if cd terraform && terraform fmt -check > /dev/null 2>&1; then
    pass
else
    fail "Terraform format check failed"
fi
cd ..

print_step "10.2" "Validating Terraform..."
if cd terraform && terraform init -backend=false > /dev/null 2>&1 && terraform validate > /dev/null 2>&1; then
    pass
else
    fail "Terraform validation failed"
fi
cd ..

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

print_header "TEST SUMMARY"

TOTAL=$((PASSED + FAILED))
echo ""
echo -e "Total:  $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}==========================================================================="
    echo "                           ALL TESTS PASSED! ✓"
    echo -e "===========================================================================${NC}"
    exit 0
else
    echo -e "${RED}==========================================================================="
    echo "                         SOME TESTS FAILED! ✗"
    echo -e "===========================================================================${NC}"
    exit 1
fi