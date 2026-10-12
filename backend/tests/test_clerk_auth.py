import asyncio
from types import SimpleNamespace
from typing import ClassVar

import pytest
from fastapi import HTTPException

from app.api.dependencies import require_permission
from app.core.authz import AuthContext
from app.core.clerk import ClerkProfile, VerifiedClerkIdentity, verify_clerk_request
from app.core.config import Settings
from app.core.exceptions import ForbiddenError
from app.schemas.auth import UserResponse
from app.services.auth import ClerkAuthService, user_response


class FakeRepository:
    def __init__(self, user=None, role=None, shared=None):
        self.user = user
        self.role = role
        self.created = None
        self.assigned_role = None
        self.committed = False
        self.shared = shared or {"lock": asyncio.Lock(), "assigned": False}

    async def get_user_by_clerk_id(self, clerk_user_id):
        if self.user and self.user.clerk_user_id == clerk_user_id:
            return self.user
        return None

    async def get_user_by_email(self, email):
        if self.user and self.user.email == email:
            return self.user
        return None

    async def get_admin_role(self):
        return self.role if self.role and self.role.code == "ADMIN" else None

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

    def expire(self, entity, attributes):
        pass

    async def lock_admin_bootstrap(self):
        await self.shared["lock"].acquire()

    async def has_assigned_application_role(self):
        return self.shared["assigned"]

    async def assign_role(self, user, role):
        self.assigned_role = role
        self.shared["assigned"] = True
        user.roles = [role]

    async def commit(self):
        self.committed = True
        if self.shared["lock"].locked():
            self.shared["lock"].release()

    async def rollback(self):
        if self.shared["lock"].locked():
            self.shared["lock"].release()


def role(code="ADMIN"):
    permission = SimpleNamespace(
        code="equipment.read", name="Read equipment", is_active=True
    )
    return SimpleNamespace(
        code=code, name=code.title(), is_active=True, permissions=[permission]
    )


def identity(clerk_user_id="user_clerk_123", email="employee@example.com"):
    return VerifiedClerkIdentity(
        user_id=clerk_user_id,
        claims={"sub": clerk_user_id, "email": email},
    )


@pytest.mark.asyncio
async def test_first_clerk_user_is_provisioned_as_admin(monkeypatch) -> None:
    profile = ClerkProfile("user_clerk_123", "employee@example.com", "Example Employee")

    async def load_profile(*_):
        return profile

    monkeypatch.setattr("app.services.auth.get_clerk_profile", load_profile)
    repository = FakeRepository(role=role())
    service = ClerkAuthService(object(), Settings())
    service.repository = repository

    user = await service.resolve_local_user(identity())

    assert user.clerk_user_id == "user_clerk_123"
    assert repository.assigned_role.code == "ADMIN"
    assert repository.committed


@pytest.mark.asyncio
async def test_subsequent_clerk_user_is_pending_without_role(monkeypatch) -> None:
    profile = ClerkProfile("user_clerk_456", "second@example.com", "Second User")

    async def load_profile(*_):
        return profile

    monkeypatch.setattr("app.services.auth.get_clerk_profile", load_profile)
    shared = {"lock": asyncio.Lock(), "assigned": True}
    repository = FakeRepository(role=role(), shared=shared)
    service = ClerkAuthService(object(), Settings())
    service.repository = repository

    user = await service.resolve_local_user(
        identity("user_clerk_456", "second@example.com")
    )

    assert user.roles == []
    assert repository.assigned_role is None
    assert repository.committed


@pytest.mark.asyncio
async def test_concurrent_first_logins_assign_admin_only_once(monkeypatch) -> None:
    async def load_profile(identity, _settings):
        return ClerkProfile(
            identity.user_id, f"{identity.user_id}@example.com", identity.user_id
        )

    monkeypatch.setattr("app.services.auth.get_clerk_profile", load_profile)
    shared = {"lock": asyncio.Lock(), "assigned": False}
    repositories = [FakeRepository(role=role(), shared=shared) for _ in range(2)]
    services = [ClerkAuthService(object(), Settings()) for _ in repositories]
    for service, repository in zip(services, repositories, strict=True):
        service.repository = repository

    users = await asyncio.gather(
        services[0].resolve_local_user(identity("user_one")),
        services[1].resolve_local_user(identity("user_two")),
    )

    assert sum(bool(user.roles) for user in users) == 1
    assert sum(repository.assigned_role is not None for repository in repositories) == 1


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

    with pytest.raises(ForbiddenError) as error:
        await service.resolve_local_user(identity())
    assert error.value.status_code == 403


def test_missing_clerk_authentication_returns_401() -> None:
    from starlette.requests import Request

    scope = {"type": "http", "method": "GET", "path": "/auth/me", "headers": []}
    with pytest.raises(HTTPException) as error:
        verify_clerk_request(Request(scope), Settings(clerk_secret_key="test-secret"))
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


def test_auth_me_response_contains_empty_pending_collections() -> None:
    user = SimpleNamespace(
        id=17,
        email="employee@example.com",
        full_name="Example Employee",
        employee_code=None,
        is_active=True,
        roles=[],
    )
    response = user_response(user)
    assert isinstance(response, UserResponse)
    assert response.roles == []
    assert response.permissions == []


@pytest.mark.asyncio
async def test_permission_granted_and_missing_permission_returns_403() -> None:
    user = SimpleNamespace(roles=[role()])
    context = AuthContext.from_user(user)
    allowed = await require_permission("equipment.read")(context)
    assert allowed is context
    with pytest.raises(HTTPException) as error:
        await require_permission("equipment.write")(context)
    assert error.value.status_code == 403


@pytest.mark.asyncio
async def test_require_permission_and_user_response_against_real_permission_orm() -> (
    None
):
    """Regression test for the `Permission.is_active` bug: the column didn't
    exist on the model but was read in `require_permission` and
    `user_response`, raising AttributeError for any user with an assigned
    permission. Every other test in this file uses `SimpleNamespace` fakes
    with `is_active` baked in, so none of them caught it - this one builds
    real mapped `Role`/`Permission` instances instead."""
    from app.models.auth import Permission, Role

    permission = Permission(
        code="equipment.read",
        name="Read equipment",
        module="equipment",
        is_active=True,
    )
    real_role = Role(code="ADMIN", name="Administrator", is_active=True)
    real_role.permissions = [permission]
    user = SimpleNamespace(
        id=1,
        email="admin@example.com",
        full_name="Admin",
        employee_code=None,
        is_active=True,
        roles=[real_role],
    )

    context = AuthContext.from_user(user)
    allowed = await require_permission("equipment.read")(context)
    assert allowed is context

    response = user_response(user)
    assert [item.code for item in response.permissions] == ["equipment.read"]
