from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.api import providers
from app.api.dependencies import get_authenticated_user, require_role
from app.core.authz import AuthContext
from app.core.exceptions import InvalidTransitionError
from app.main import app
from app.schemas.maintenance import MaintenanceStatusTransitionRequest
from app.services.audit import AuditService
from app.services.auth import ClerkAuthService
from app.services.notification import NotificationService
from tests.test_maintenance import (
    create_ticket,
    make_actor,
    make_technician,
    service_with_fakes,
)


def make_user(*roles):
    return SimpleNamespace(
        id=1,
        roles=[
            SimpleNamespace(code=code, is_active=active, permissions=[])
            for code, active in roles
        ],
    )


def test_context_only_counts_active_roles():
    context = AuthContext.from_user(make_user(("ADMIN", False), ("EMPLOYEE", True)))
    assert context.roles == {"EMPLOYEE"}
    assert not context.is_elevated


@pytest.mark.parametrize(
    ("roles", "elevated"),
    [
        (("ADMIN",), True),
        (("SUPERVISOR",), True),
        (("TECHNICIAN",), False),
        ((), False),
    ],
)
def test_is_elevated_depends_only_on_admin_or_supervisor(roles, elevated):
    context = AuthContext(user=SimpleNamespace(id=1), roles=frozenset(roles))
    assert context.is_elevated is elevated


async def test_require_role_allows_listed_roles_and_rejects_others():
    dependency = require_role("ADMIN", "SUPERVISOR")
    supervisor = AuthContext(
        user=SimpleNamespace(id=1), roles=frozenset({"SUPERVISOR"})
    )
    assert await dependency(supervisor) is supervisor
    with pytest.raises(HTTPException) as error:
        await dependency(AuthContext(user=SimpleNamespace(id=2), roles=frozenset()))
    assert error.value.status_code == 403


def test_service_providers_are_built_from_repository_providers():
    repo = SimpleNamespace()
    assert isinstance(providers.get_audit_service(repo), AuditService)
    assert isinstance(providers.get_notification_service(repo), NotificationService)
    service = providers.get_auth_service(
        repo, SimpleNamespace(), providers.get_audit_service(repo)
    )
    assert isinstance(service, ClerkAuthService)
    assert service.repository is repo


def test_repository_provider_can_be_overridden_for_a_route():
    class FakeInboxRepository:
        async def list_for_user(self, user_id, **kwargs):
            return []

        async def count_unread(self, user_id):
            return 0

    app.dependency_overrides[providers.get_notification_repository] = lambda: (
        FakeInboxRepository()
    )
    app.dependency_overrides[get_authenticated_user] = lambda: SimpleNamespace(id=5)
    try:
        response = TestClient(app).get("/notifications")
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 200
    assert response.json()["items"] == []


async def test_assigned_cannot_be_reached_through_status_without_a_technician():
    service = service_with_fakes()
    created = await create_ticket(service)
    admin = make_actor(1, role_codes=("ADMIN",))
    with pytest.raises(InvalidTransitionError, match="without an assigned technician"):
        await service.transition_status(
            created.id, MaintenanceStatusTransitionRequest(status="assigned"), admin
        )


async def test_reassigning_a_technician_mid_work_keeps_status_and_history():
    from app.schemas.maintenance import TicketAssignmentCreateRequest

    technicians = [make_technician(1, 10), make_technician(2, 20)]
    service = service_with_fakes(technicians=technicians)
    created = await create_ticket(service)
    admin = make_actor(1, role_codes=("ADMIN",))
    first = await service.assign_technician(
        created.id, TicketAssignmentCreateRequest(technician_id=1), admin
    )
    assert first.status == "assigned"
    again = await service.assign_technician(
        created.id, TicketAssignmentCreateRequest(technician_id=2), admin
    )
    assert again.status == "assigned"
    assert again.current_assignment.technician.id == 2
    assert [h.to_status for h in again.status_history] == ["submitted", "assigned"]
