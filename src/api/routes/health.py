"""
Health check endpoint for monitoring and container orchestration.

Used by:
- Docker health checks
- Load balancers
- Kubernetes probes
"""

from typing import TypedDict

from flask import Blueprint

from src.db.connection import check_database_health

health_bp: Blueprint = Blueprint("health", __name__)


class HealthResponse(TypedDict):
    status: str
    database: str


@health_bp.get("/health")
def health_check() -> tuple[HealthResponse, int]:
    """
    Health check endpoint.
    
    Returns:
        200: All systems healthy
        503: One or more systems unhealthy
    """
    db_healthy: bool = check_database_health()
    
    response = HealthResponse(
        status="healthy" if db_healthy else "unhealthy",
        database="connected" if db_healthy else "disconnected",
    )
    
    status_code: int = 200 if db_healthy else 503
    
    return response, status_code