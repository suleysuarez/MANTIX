from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.middleware import RateLimitMiddleware, RequestLoggingMiddleware


def build_app(limit: int) -> TestClient:
    app = FastAPI()
    app.add_middleware(RateLimitMiddleware, limit_per_minute=limit)
    app.add_middleware(RequestLoggingMiddleware)

    @app.get("/ping")
    def ping() -> dict[str, str]:
        return {"ok": "yes"}

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    return TestClient(app)


def test_requests_over_the_limit_get_429_with_retry_after():
    client = build_app(limit=2)

    assert client.get("/ping").status_code == 200
    assert client.get("/ping").status_code == 200
    blocked = client.get("/ping")

    assert blocked.status_code == 429
    assert int(blocked.headers["Retry-After"]) >= 1


def test_health_check_is_never_rate_limited():
    client = build_app(limit=1)

    assert all(client.get("/health").status_code == 200 for _ in range(5))


def test_limit_of_zero_disables_rate_limiting():
    client = build_app(limit=0)

    assert all(client.get("/ping").status_code == 200 for _ in range(20))


def test_every_response_carries_a_request_id_and_echoes_a_given_one():
    client = build_app(limit=0)

    assert client.get("/ping").headers["X-Request-ID"]
    echoed = client.get("/ping", headers={"X-Request-ID": "abc123"})
    assert echoed.headers["X-Request-ID"] == "abc123"
