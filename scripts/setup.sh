#!/bin/bash

# =============================================================================
# Sensor Data Pipeline - Initial Setup Script
# =============================================================================
# Sets up the development environment on a new system.
# Usage: ./scripts/setup.sh
# =============================================================================

set -e  # Exit on first error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

print_header() {
    echo ""
    echo "==========================================================================="
    echo -e "${BLUE}$1${NC}"
    echo "==========================================================================="
}

print_step() {
    echo ""
    echo -e "${YELLOW}[$1] $2${NC}"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

error() {
    echo -e "${RED}✗ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        success "$1 is installed"
        return 0
    else
        error "$1 is not installed"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Step 1: Check Prerequisites
# -----------------------------------------------------------------------------

print_header "STEP 1: CHECKING PREREQUISITES"

MISSING_DEPS=()

print_step "1.1" "Checking Docker..."
if ! check_command docker; then
    MISSING_DEPS+=("docker")
fi

print_step "1.2" "Checking Docker Compose..."
if docker compose version &> /dev/null; then
    success "docker compose is available"
elif check_command docker-compose; then
    warn "Using standalone docker-compose (consider upgrading to Docker Compose V2)"
else
    MISSING_DEPS+=("docker-compose")
fi

print_step "1.3" "Checking Poetry..."
if ! check_command poetry; then
    MISSING_DEPS+=("poetry")
fi

print_step "1.4" "Checking Python version..."
if check_command python3; then
    PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
    PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d'.' -f1)
    PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d'.' -f2)
    if [ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -ge 11 ]; then
        success "Python $PYTHON_VERSION (3.11+ required)"
    else
        error "Python 3.11+ required, found $PYTHON_VERSION"
        MISSING_DEPS+=("python3.11+")
    fi
else
    MISSING_DEPS+=("python3")
fi

print_step "1.5" "Checking Terraform (optional)..."
if check_command terraform; then
    :  # Terraform found
else
    warn "Terraform not installed (optional, only needed for deployment)"
fi

# Exit if missing required dependencies
if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo ""
    error "Missing required dependencies: ${MISSING_DEPS[*]}"
    echo ""
    echo "Installation instructions:"
    echo ""
    for dep in "${MISSING_DEPS[@]}"; do
        case $dep in
            docker)
                echo "  Docker: https://docs.docker.com/get-docker/"
                ;;
            docker-compose)
                echo "  Docker Compose: https://docs.docker.com/compose/install/"
                ;;
            poetry)
                echo "  Poetry: curl -sSL https://install.python-poetry.org | python3 -"
                ;;
            python3|python3.11+)
                echo "  Python 3.11+: https://www.python.org/downloads/"
                echo "  Or with pyenv: pyenv install 3.11"
                ;;
        esac
    done
    echo ""
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 2: Check Docker is Running
# -----------------------------------------------------------------------------

print_header "STEP 2: VERIFYING DOCKER"

print_step "2.1" "Checking Docker daemon..."
if docker info > /dev/null 2>&1; then
    success "Docker daemon is running"
else
    error "Docker daemon is not running"
    echo ""
    echo "Please start Docker and run this script again."
    echo "  - macOS: Open Docker Desktop"
    echo "  - Linux: sudo systemctl start docker"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 3: Install Python Dependencies
# -----------------------------------------------------------------------------

print_header "STEP 3: INSTALLING PYTHON DEPENDENCIES"

print_step "3.1" "Installing Poetry dependencies..."
poetry install
success "Python dependencies installed"

# -----------------------------------------------------------------------------
# Step 4: Environment Configuration
# -----------------------------------------------------------------------------

print_header "STEP 4: ENVIRONMENT CONFIGURATION"

print_step "4.1" "Checking .env file..."
if [ -f .env ]; then
    success ".env file exists"
else
    if [ -f .env.example ]; then
        cp .env.example .env
        success "Created .env from .env.example"
    else
        # Create default .env
        cat > .env << 'EOF'
# PostgreSQL Configuration
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=sensor_data

# API Configuration
API_HOST=0.0.0.0
API_PORT=5001
API_DEBUG=false
EOF
        success "Created default .env file"
    fi
fi

# -----------------------------------------------------------------------------
# Step 5: Start Docker Services
# -----------------------------------------------------------------------------

print_header "STEP 5: STARTING DOCKER SERVICES"

print_step "5.1" "Stopping any existing containers..."
docker compose down -v 2>/dev/null || true
success "Cleaned up existing containers"

print_step "5.2" "Building and starting services..."
docker compose up -d --build
success "Docker services started"

print_step "5.3" "Waiting for PostgreSQL to be ready..."
WAIT_COUNT=0
while [ $WAIT_COUNT -lt 30 ]; do
    if docker exec sensor_data_postgres pg_isready -U postgres -d sensor_data > /dev/null 2>&1; then
        success "PostgreSQL is ready"
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 1))
done
if [ $WAIT_COUNT -ge 30 ]; then
    error "PostgreSQL failed to start"
    exit 1
fi

print_step "5.4" "Waiting for Airflow initialization..."
WAIT_COUNT=0
while [ $WAIT_COUNT -lt 60 ]; do
    if docker compose logs airflow-init 2>&1 | grep -q "complete"; then
        success "Airflow initialization complete"
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 1))
done
if [ $WAIT_COUNT -ge 60 ]; then
    warn "Airflow init timeout (may still be initializing)"
fi

# Give services a moment to stabilize
sleep 5

print_step "5.5" "Waiting for API to be healthy..."
WAIT_COUNT=0
while [ $WAIT_COUNT -lt 30 ]; do
    if curl -s http://localhost:5001/health | grep -q '"status":"healthy"'; then
        success "API is healthy"
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 1))
done
if [ $WAIT_COUNT -ge 30 ]; then
    error "API failed to become healthy"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 6: Verify Installation
# -----------------------------------------------------------------------------

print_header "STEP 6: VERIFYING INSTALLATION"

print_step "6.1" "Checking all containers are running..."
CONTAINERS_OK=true

for container in sensor_data_postgres sensor_data_api sensor_data_airflow_scheduler sensor_data_airflow_webserver; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        success "$container is running"
    else
        error "$container is not running"
        CONTAINERS_OK=false
    fi
done

print_step "6.2" "Testing database connection..."
if docker exec sensor_data_postgres psql -U postgres -d sensor_data -c "SELECT 1;" > /dev/null 2>&1; then
    success "Database connection OK"
else
    error "Database connection failed"
fi

print_step "6.3" "Testing API endpoint..."
if curl -s http://localhost:5001/health | grep -q '"status":"healthy"'; then
    success "API endpoint responding"
else
    error "API endpoint not responding"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

print_header "SETUP COMPLETE"

echo ""
echo -e "${GREEN}The development environment is ready!${NC}"
echo ""
echo "Services available:"
echo "  - API:             http://localhost:5001"
echo "  - API Health:      http://localhost:5001/health"
echo "  - Airflow UI:      http://localhost:8080 (admin/admin)"
echo "  - PostgreSQL:      localhost:5432 (postgres/postgres)"
echo ""
echo "Useful commands:"
echo "  - Run tests:       ./scripts/test_all.sh"
echo "  - Stop services:   docker compose down"
echo "  - View logs:       docker compose logs -f [service]"
echo "  - Run linting:     poetry run ruff check ."
echo "  - Run type check:  poetry run pyright"
echo "  - Run unit tests:  poetry run pytest -v"
echo ""
echo "To post test data:"
echo '  curl -X POST http://localhost:5001/data \'
echo '    -H "Content-Type: text/plain" \'
echo '    -d "1649941817 Voltage 1.34"'
echo ""
