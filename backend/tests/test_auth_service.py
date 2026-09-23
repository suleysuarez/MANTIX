from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.core.config import Settings
from app.core.security import hash_password, hash_token
from app.schemas.auth import LoginRequest, RefreshRequest
from app.services.auth import AuthService

REFRESH_TOKEN = "refresh-token-012345678901234567890123456"


class FakeRepository:
    def __init__(self, user: SimpleNamespace, refresh_token: SimpleNamespace):
        self.user = user
        self.refresh_token = refresh_token
        self.revoked = False
        self.commits = 0

    async def get_user_by_email(self, email: str):
        return self.user if email == self.user.email else None

    async def get_refresh_token(self, token_hash: str):
        return (
            self.refresh_token if token_hash == self.refresh_token.token_hash else None
        )

    async def add_refresh_token(
        self, user_id: int, token_hash: str, expires_at: datetime
    ):
        return SimpleNamespace(
            user_id=user_id, token_hash=token_hash, expires_at=expires_at
        )

    async def revoke_refresh_token(self, token: SimpleNamespace, now: datetime):
        token.revoked_at = now
        self.revoked = True

    async def commit(self):
        self.commits += 1


def make_user() -> SimpleNamespace:
    permission = SimpleNamespace(
        code="equipment.read", name="Read equipment", is_active=True
    )
    role = SimpleNamespace(
        code="EMPLOYEE", name="Employee", is_active=True, permissions=[permission]
    )
    credentials = SimpleNamespace(password_hash=hash_password("password123"))
    return SimpleNamespace(
        id=7,
        email="employee@example.com",
        full_name="Example Employee",
        employee_code="E-7",
        is_active=True,
        credentials=credentials,
        roles=[role],
    )


def make_service() -> tuple[AuthService, FakeRepository]:
    user = make_user()
    stored = SimpleNamespace(
        token_hash=hash_token(REFRESH_TOKEN),
        expires_at=datetime.now(UTC) + timedelta(days=1),
        revoked_at=None,
        user=user,
    )
    repository = FakeRepository(user, stored)
    service = AuthService(object(), Settings(jwt_secret_key="test-secret"))
    service.repository = repository
    return service, repository


@pytest.mark.asyncio
async def test_login_returns_tokens_for_valid_credentials() -> None:
    service, _ = make_service()
    response = await service.login(
        LoginRequest(email="employee@example.com", password="password123")
    )
    assert response.access_token
    assert response.refresh_token
    assert response.user.roles[0].code == "EMPLOYEE"


@pytest.mark.asyncio
async def test_invalid_password_returns_401() -> None:
    service, _ = make_service()
    with pytest.raises(HTTPException) as error:
        await service.login(
            LoginRequest(email="employee@example.com", password="wrongpass")
        )
    assert error.value.status_code == 401


@pytest.mark.asyncio
async def test_inactive_user_is_rejected() -> None:
    service, _ = make_service()
    service.repository.user.is_active = False
    with pytest.raises(HTTPException) as error:
        await service.login(
            LoginRequest(email="employee@example.com", password="password123")
        )
    assert error.value.status_code == 401


@pytest.mark.asyncio
async def test_nonexistent_user_is_rejected() -> None:
    service, _ = make_service()
    with pytest.raises(HTTPException) as error:
        await service.login(
            LoginRequest(email="missing@example.com", password="password123")
        )
    assert error.value.status_code == 401


@pytest.mark.asyncio
async def test_refresh_revokes_old_token_before_issuing_new_tokens() -> None:
    service, repository = make_service()
    response = await service.refresh(RefreshRequest(refresh_token=REFRESH_TOKEN))
    assert response.access_token
    assert repository.revoked
    assert repository.refresh_token.revoked_at is not None


@pytest.mark.asyncio
async def test_revoked_refresh_token_is_rejected() -> None:
    service, repository = make_service()
    repository.refresh_token.revoked_at = datetime.now(UTC)
    with pytest.raises(HTTPException) as error:
        await service.refresh(RefreshRequest(refresh_token=REFRESH_TOKEN))
    assert error.value.status_code == 401


@pytest.mark.asyncio
async def test_expired_refresh_token_is_rejected() -> None:
    service, repository = make_service()
    repository.refresh_token.expires_at = datetime.now(UTC) - timedelta(minutes=1)
    with pytest.raises(HTTPException) as error:
        await service.refresh(RefreshRequest(refresh_token=REFRESH_TOKEN))
    assert error.value.status_code == 401


@pytest.mark.asyncio
async def test_logout_revokes_refresh_token() -> None:
    service, repository = make_service()
    response = await service.logout(RefreshRequest(refresh_token=REFRESH_TOKEN))
    assert response.message == "logged out"
    assert repository.revoked
