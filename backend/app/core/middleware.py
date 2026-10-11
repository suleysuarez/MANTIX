"""HTTP middleware: request logging with a correlation id and rate limiting."""

import logging
import time
import uuid
from collections import defaultdict, deque

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.types import ASGIApp

logger = logging.getLogger("mantix.request")

REQUEST_ID_HEADER = "X-Request-ID"


def configure_logging(level: str = "INFO") -> None:
    logging.basicConfig(
        level=level.upper(),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )


def _client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """Logs method, path, status and latency; never logs headers or bodies.

    Authorization tokens and request payloads therefore never reach the logs.
    """

    async def dispatch(self, request: Request, call_next) -> Response:
        request_id = request.headers.get(REQUEST_ID_HEADER) or uuid.uuid4().hex
        request.state.request_id = request_id
        started = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            logger.exception(
                "request_failed id=%s method=%s path=%s",
                request_id,
                request.method,
                request.url.path,
            )
            raise
        elapsed_ms = (time.perf_counter() - started) * 1000
        response.headers[REQUEST_ID_HEADER] = request_id
        logger.info(
            "id=%s method=%s path=%s status=%s ms=%.1f",
            request_id,
            request.method,
            request.url.path,
            response.status_code,
            elapsed_ms,
        )
        return response


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Sliding-window limit per client IP, kept in this process's memory.

    Good enough to blunt abuse of a single instance. With several workers or
    replicas each keeps its own counters, so a shared store (e.g. Redis) or the
    reverse proxy should take over there. `limit_per_minute <= 0` disables it.
    """

    EXEMPT_PATHS = frozenset({"/health"})

    def __init__(
        self,
        app: ASGIApp,
        limit_per_minute: int,
        window_seconds: float = 60.0,
    ):
        super().__init__(app)
        self.limit = limit_per_minute
        self.window = window_seconds
        self._hits: dict[str, deque[float]] = defaultdict(deque)

    async def dispatch(self, request: Request, call_next) -> Response:
        if (
            self.limit <= 0
            or request.method == "OPTIONS"
            or request.url.path in self.EXEMPT_PATHS
        ):
            return await call_next(request)

        now = time.monotonic()
        hits = self._hits[_client_ip(request)]
        while hits and now - hits[0] >= self.window:
            hits.popleft()
        if len(hits) >= self.limit:
            retry_after = max(1, int(self.window - (now - hits[0])))
            return JSONResponse(
                status_code=429,
                content={
                    "detail": "too many requests",
                    "code": "rate_limited",
                    "errors": None,
                    "request_id": getattr(request.state, "request_id", None),
                },
                headers={"Retry-After": str(retry_after)},
            )
        hits.append(now)
        return await call_next(request)
