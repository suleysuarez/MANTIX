"""Revocation of mobile access tokens through `users.token_version`.

Needs TEST_DATABASE_URL pointing to a disposable local `*_test` database
(see tests/conftest.py). Delivery is always faked.
"""

import re
from datetime import UTC, datetime, timedelta

import jwt
import pytest
from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.models.auth import Role, User
from app.services import mobile_auth
from app.services.code_email_limiter import CodeEmailLimiter
from app.services.mobile_auth import MobileAuthService

EMAIL = "ana.perez@example.com"
PASSWORD = "Duena1234567"
NEW_PASSWORD = "Nueva1234567"
SECRET = "test-only-secret-" + "x" * 32


class RecordingSender:
    def __init__(self):
        self.sent: list[dict] = []

    async def send(self, **kwargs):
        self.sent.append(kwargs)

    def last_code(self) -> str:
        match = re.search(r"Código: (\d{6})", self.sent[-1]["text"])
        assert match
        return match.group(1)


@pytest.fixture(autouse=True)
async def admin_role(db_session: AsyncSession) -> None:
    db_session.add(Role(code="ADMIN", name="Administrador", is_active=True))
    await db_session.commit()


@pytest.fixture
async def user(db_session: AsyncSession) -> User:
    account = User(
        email=EMAIL, full_name="Ana", is_active=True,
        password_hash=mobile_auth._passwords.hash(PASSWORD),
        email_verified_at=datetime.now(UTC),
    )
    db_session.add(account)
    await db_session.commit()
    return account


def build(session: AsyncSession, sender: RecordingSender | None = None) -> MobileAuthService:
    return MobileAuthService(
        session,
        Settings(_env_file=None, MOBILE_JWT_SECRET=SECRET),
        sender=sender or RecordingSender(),
        limiter=CodeEmailLimiter(min_interval_seconds=0),
    )


async def token_for(service: MobileAuthService) -> str:
    return (await service.login(email=EMAIL, password=PASSWORD))["access_token"]


async def assert_revoked(service: MobileAuthService, token: str) -> None:
    with pytest.raises(HTTPException) as error:
        await service.user_from_token(token)
    assert error.value.status_code == 401


async def test_a_new_account_starts_at_version_zero_and_its_token_carries_it(db_session, user):
    token = await token_for(build(db_session))
    claims = jwt.decode(token[5:], SECRET, algorithms=["HS256"], issuer="mantix-mobile")

    assert user.token_version == 0
    assert claims["ver"] == 0


async def test_a_fresh_token_is_accepted(db_session, user):
    service = build(db_session)
    assert (await service.user_from_token(await token_for(service))).id == user.id


async def test_logout_revokes_every_token_of_the_account(db_session, user):
    service = build(db_session)
    phone, tablet = await token_for(service), await token_for(service)
    await service.logout(phone)

    await assert_revoked(service, phone)
    await assert_revoked(service, tablet)
    assert (await service.user_from_token(await token_for(service))).id == user.id


async def test_resetting_the_password_revokes_the_tokens_issued_before(db_session, user):
    sender = RecordingSender()
    service = build(db_session, sender)
    old = await token_for(service)

    await service.forgot_password(EMAIL)
    await service.reset_password(email=EMAIL, code=sender.last_code(), new_password=NEW_PASSWORD)

    await assert_revoked(service, old)
    fresh = (await service.login(email=EMAIL, password=NEW_PASSWORD))["access_token"]
    assert (await service.user_from_token(fresh)).id == user.id


async def test_a_token_without_the_claim_counts_as_version_zero(db_session, user):
    service = build(db_session)
    now = datetime.now(UTC)
    legacy = "mjwt." + jwt.encode(
        {"sub": str(user.id), "iss": "mantix-mobile", "iat": now, "exp": now + timedelta(hours=1)},
        SECRET, algorithm="HS256",
    )

    assert (await service.user_from_token(legacy)).id == user.id
    await service.logout(legacy)
    await assert_revoked(service, legacy)


async def test_logout_with_an_invalid_token_changes_nothing(db_session, user):
    service = build(db_session)
    with pytest.raises(HTTPException):
        await service.logout("not-a-mobile-token")

    stored = (await db_session.execute(select(User.token_version).where(User.id == user.id))).scalar_one()
    assert stored == 0
