from types import SimpleNamespace

from fastapi.testclient import TestClient

from app.api.dependencies import get_authenticated_user
from app.api.providers import get_maintenance_service
from app.main import app
from app.repositories.base import Page
from tests.support import perm_objects


class StubMaintenanceService:
    async def list_requests(self, **kwargs):
        self.kwargs = kwargs
        return Page(items=[], total=0, page=1, size=20)


def test_route_uses_injected_service_without_a_database():
    stub = StubMaintenanceService()
    user = SimpleNamespace(
        id=1,
        roles=[
            SimpleNamespace(
                code="EMPLOYEE",
                is_active=True,
                permissions=perm_objects("maintenance.read"),
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
    assert response.headers["X-Total-Count"] == "0"
    assert response.headers["X-Total-Pages"] == "0"
    assert stub.kwargs["status"] == "resolved"
    assert stub.kwargs["actor"].user is user
    assert stub.kwargs["actor"].has_permission("tickets:ver")
