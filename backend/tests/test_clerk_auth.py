from types import SimpleNamespace
from typing import ClassVar

import pytest
from fastapi import HTTPException

from app.api.dependencies import require_permission
from app.core.clerk import ClerkProfile, VerifiedClerkIdentity, verify_clerk_request
from app.core.config import Settings
from app.schemas.auth import UserResponse
from app.services.auth import ClerkAuthService, user_response


class FakeRepository:
    def __init__(self, user=None, role=None):
        self.user = user
        self.role = role
        self.created = None
        self.assigned_role = None
        self.committed = False

    async def get_user_by_clerk_id(self, clerk_user_id):
        if self.user and self.user.clerk_user_id == clerk_user_id:
            return self.user
        return None

    async def get_user_by_email(self, email):
        if self.user and self.user.email == email:
            return self.user
        return None

    async def get_employee_role(self):
        return self.role

    async def create_user(self, profile):
        self.created = SimpleNamespace(
            id=17,
            clerk_user_id=profile.clerk_user_id,
            email=profile.email,
            full_name=profile.full_name,
            employee_code=None,
            is_active=True,
            roles=[],
        )
        self.user = self.created
        return self.created

    async def assign_role(self, user, role):
        self.assigned_role = role
        user.roles = [role]

    async def commit(self):
        self.committed = True

    async def rollback(self):
        pass


def role():
    permission = SimpleNamespace(
        code="equipment.read", name="Read equipment", is_active=True
    )
    return SimpleNamespace(
        code="EMPLOYEE", name="Employee", is_active=True, permissions=[permission]
    )


def identity() -> VerifiedClerkIdentity:
    return VerifiedClerkIdentity(
        user_id="user_clerk_123",
        claims={"sub": "user_clerk_123", "email": "employee@example.com"},
    )


@pytest.mark.asyncio
async def test_first_clerk_user_is_provisioned_as_employee(monkeypatch) -> None:
    profile = ClerkProfile("user_clerk_123", "employee@example.com", "Example Employee")

    async def load_profile(*_):
        return profile

    monkeypatch.setattr("app.services.auth.get_clerk_profile", load_profile)
    repository = FakeRepository(role=role())
    service = ClerkAuthService(object(), Settings())
    service.repository = repository

    user = await service.resolve_local_user(identity())

    assert user.clerk_user_id == "user_clerk_123"
    assert repository.assigned_role.code == "EMPLOYEE"
    assert repository.committed


@pytest.mark.asyncio
async def test_existing_clerk_link_is_preserved() -> None:
    existing = SimpleNamespace(
        id=3,
        clerk_user_id="user_clerk_123",
        email="employee@example.com",
        full_name="Existing Profile",
        employee_code="E-3",
        is_active=True,
        roles=[role()],
    )
    repository = FakeRepository(user=existing)
    service = ClerkAuthService(object(), Settings())
    service.repository = repository

    user = await service.resolve_local_user(identity())

    assert user is existing
    assert repository.created is None


@pytest.mark.asyncio
async def test_inactive_local_user_is_denied() -> None:
    existing = SimpleNamespace(
        clerk_user_id="user_clerk_123",
        email="employee@example.com",
        is_active=False,
        roles=[],
    )
    service = ClerkAuthService(object(), Settings())
    service.repository = FakeRepository(user=existing)

    with pytest.raises(HTTPException) as error:
        await service.resolve_local_user(identity())
    assert error.value.status_code == 403


def test_missing_clerk_authentication_returns_401() -> None:
    from starlette.requests import Request

    scope = {"type": "http", "method": "GET", "path": "/auth/me", "headers": []}
    request = Request(scope)
    with pytest.raises(HTTPException) as error:
        verify_clerk_request(request, Settings(clerk_secret_key="test-secret"))
    assert error.value.status_code == 401


def test_invalid_clerk_token_returns_401(monkeypatch) -> None:
    from starlette.requests import Request

    class InvalidState:
        is_signed_in = False
        payload = None

    monkeypatch.setattr(
        "app.core.clerk.authenticate_request", lambda *_: InvalidState()
    )
    scope = {
        "type": "http",
        "method": "GET",
        "path": "/auth/me",
        "headers": [(b"authorization", b"Bearer invalid")],
    }
    with pytest.raises(HTTPException) as error:
        verify_clerk_request(Request(scope), Settings(clerk_secret_key="test-secret"))
    assert error.value.status_code == 401


def test_verified_clerk_token_returns_identity(monkeypatch) -> None:
    from starlette.requests import Request

    class ValidState:
        is_signed_in = True
        payload: ClassVar = {"sub": "user_clerk_123", "sid": "sess_123"}

    monkeypatch.setattr("app.core.clerk.authenticate_request", lambda *_: ValidState())
    scope = {
        "type": "http",
        "method": "GET",
        "path": "/auth/me",
        "headers": [(b"authorization", b"Bearer valid")],
    }
    verified = verify_clerk_request(
        Request(scope), Settings(clerk_secret_key="test-secret")
    )
    assert verified.user_id == "user_clerk_123"


def test_auth_me_response_contains_local_roles_and_permissions() -> None:
    user = SimpleNamespace(
        id=17,
        email="employee@example.com",
        full_name="Example Employee",
        employee_code="E-17",
        is_active=True,
        roles=[role()],
    )
    response = user_response(user)
    assert isinstance(response, UserResponse)
    assert response.roles[0].code == "EMPLOYEE"
    assert response.permissions[0].code == "equipment.read"


@pytest.mark.asyncio
async def test_permission_granted_and_missing_permission_returns_403() -> None:
    user = SimpleNamespace(roles=[role()])
    allowed = await require_permission("equipment.read")(user)
    assert allowed is user
    with pytest.raises(HTTPException) as error:
        await require_permission("equipment.write")(user)
    assert error.value.status_code == 403
