"""Flask application factory."""

import atexit
import logging
import time

from flask import Flask, Response, g, request

from src.api.routes.data import data_bp
from src.api.routes.health import health_bp
from src.config.settings import get_settings
from src.db.connection import close_pool

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)

logger: logging.Logger = logging.getLogger(__name__)


def create_app() -> Flask:
    app: Flask = Flask(__name__)
    app.register_blueprint(data_bp)
    app.register_blueprint(health_bp)
    
    # Register request timing hooks
    register_request_timing(app)
    
    # Cleanup on shutdown
    atexit.register(close_pool)
    return app


def register_request_timing(app: Flask) -> None:
    """Add request timing middleware for performance monitoring."""

    @app.before_request
    def _start_timer() -> None:  # pyright: ignore[reportUnusedFunction]
        g.start_time = time.perf_counter()

    @app.after_request
    def _log_request_time(response: Response) -> Response:  # pyright: ignore[reportUnusedFunction]
        if hasattr(g, "start_time"):
            duration_ms: float = (time.perf_counter() - g.start_time) * 1000
            logger.info(
                "%s %s - %d - %.2fms",
                request.method,
                request.path,
                response.status_code,
                duration_ms
            )
        return response


# Create app instance
app: Flask = create_app()


if __name__ == "__main__":
    settings = get_settings()
    app.run(
        host=settings.api_host,
        port=settings.api_port,
        debug=settings.api_debug
    )