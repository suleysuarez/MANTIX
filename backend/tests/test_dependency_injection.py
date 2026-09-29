from types import SimpleNamespace

from fastapi.testclient import TestClient

from app.api.dependencies import get_authenticated_user
from app.api.providers import get_maintenance_service
from app.main import app


class StubMaintenanceService:
    async def list_requests(self, **kwargs):
        self.kwargs = kwargs
        return []


def test_route_uses_injected_service_without_a_database():
    stub = StubMaintenanceService()
    user = SimpleNamespace(
        id=1,
        roles=[
            SimpleNamespace(
                is_active=True,
                permissions=[SimpleNamespace(is_active=True, code="maintenance.read")],
            )
        ],
    )
    app.dependency_overrides[get_maintenance_service] = lambda: stub
    app.dependency_overrides[get_authenticated_user] = lambda: user
    try:
        response = TestClient(app).get("/maintenance/requests?status=resolved")
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json() == []
    assert stub.kwargs["status"] == "resolved"
    assert stub.kwargs["actor"] is user
