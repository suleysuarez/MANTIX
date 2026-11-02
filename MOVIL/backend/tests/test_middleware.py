from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
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


def build_cors_app(limit: int = 0) -> TestClient:
    """Same layering as `app.main`: CORS is the outermost middleware."""
    app = FastAPI()
    app.add_middleware(RateLimitMiddleware, limit_per_minute=limit)
    app.add_middleware(RequestLoggingMiddleware)
    app.add_middleware(
        CORSMiddleware, allow_origins=["http://localhost:4200"], allow_methods=["*"]
    )

    @app.get("/boom")
    def boom() -> None:
        raise RuntimeError("database exploded")

    @app.get("/ping")
    def ping() -> dict[str, str]:
        return {"ok": "yes"}

    return TestClient(app, raise_server_exceptions=False)


ORIGIN = {"Origin": "http://localhost:4200"}


def test_unhandled_errors_return_a_readable_json_500_with_cors_headers():
    client = build_cors_app()

    response = client.get("/boom", headers={**ORIGIN, "X-Request-ID": "req-9"})

    assert response.status_code == 500
    assert response.headers["access-control-allow-origin"] == "http://localhost:4200"
    body = response.json()
    assert body["code"] == "internal_error"
    assert body["request_id"] == "req-9"
    assert "database exploded" not in response.text


def test_rate_limited_responses_also_carry_cors_headers():
    client = build_cors_app(limit=1)
    client.get("/ping", headers=ORIGIN)

    blocked = client.get("/ping", headers=ORIGIN)

    assert blocked.status_code == 429
    assert blocked.headers["access-control-allow-origin"] == "http://localhost:4200"
