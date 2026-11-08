"""Registration, code-key and login-timing hardening of MobileAuthService.

Needs TEST_DATABASE_URL pointing to a disposable local `*_test` database
(see tests/conftest.py). Delivery is always faked.
"""

import hashlib
import hmac
import re
from datetime import UTC, datetime

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.exceptions import ForbiddenError
from app.models.auth import Role, User, UserRole
from app.services import mobile_auth
from app.services.code_email_limiter import CodeEmailLimiter
from app.services.mobile_auth import MobileAuthService

EMAIL = "ana.perez@example.com"
SECRET = "test-only-secret-" + "x" * 32
PASSWORD_ATTACKER = "Atacante12345"
PASSWORD_OWNER = "Duena1234567"


class RecordingSender:
    def __init__(self):
        self.sent: list[dict] = []

    async def send(self, **kwargs):
        self.sent.append(kwargs)

    def last_code(self) -> str:
        match = re.search(r"Código: (\d{6})", self.sent[-1]["text"])
        assert match
        return match.group(1)


@pytest.fixture
async def admin_role(db_session: AsyncSession) -> Role:
    role = Role(code="ADMIN", name="Administrador", is_active=True)
    db_session.add(role)
    await db_session.commit()
    return role


def build(session: AsyncSession, sender: RecordingSender) -> MobileAuthService:
    return MobileAuthService(
        session,
        Settings(_env_file=None, MOBILE_JWT_SECRET=SECRET),
        sender=sender,
        limiter=CodeEmailLimiter(min_interval_seconds=0),
    )


async def role_assignments(session: AsyncSession) -> int:
    return (await session.execute(select(func.count()).select_from(UserRole))).scalar_one()


async def user_row(session: AsyncSession) -> User:
    return (await session.execute(select(User).where(User.email == EMAIL))).scalar_one()


async def test_registering_does_not_grant_a_role_before_the_email_is_verified(db_session, admin_role):
    await build(db_session, RecordingSender()).register(email=EMAIL, password=PASSWORD_OWNER)

    assert await role_assignments(db_session) == 0


async def test_the_first_verified_account_still_becomes_admin(db_session, admin_role):
    sender = RecordingSender()
    service = build(db_session, sender)
    await service.register(email=EMAIL, password=PASSWORD_OWNER)
    await service.verify_email(email=EMAIL, code=sender.last_code())

    assert await role_assignments(db_session) == 1


async def test_a_later_registration_replaces_the_password_set_by_a_pre_registration(db_session, admin_role):
    sender = RecordingSender()
    service = build(db_session, sender)
    await service.register(email=EMAIL, password=PASSWORD_ATTACKER)
    await service.register(email=EMAIL, password=PASSWORD_OWNER)  # the mailbox owner

    hash_ = (await user_row(db_session)).password_hash
    assert mobile_auth._passwords.verify(PASSWORD_OWNER, hash_)
    assert not mobile_auth._passwords.verify(PASSWORD_ATTACKER, hash_)


async def test_a_code_sent_for_the_previous_registration_cannot_verify_the_new_one(db_session, admin_role):
    sender = RecordingSender()
    service = build(db_session, sender)
    await service.register(email=EMAIL, password=PASSWORD_ATTACKER)
    stale_code = sender.last_code()
    # Blocked by the send limit: no new code, but the old one must be dead anyway.
    blocked = MobileAuthService(
        db_session, service.settings, sender=sender, limiter=CodeEmailLimiter()
    )
    blocked.limiter.allow(EMAIL)
    await blocked.register(email=EMAIL, password=PASSWORD_OWNER)

    with pytest.raises(ForbiddenError):
        await service.verify_email(email=EMAIL, code=stale_code)


async def test_the_fresh_code_verifies_the_new_registration(db_session, admin_role):
    sender = RecordingSender()
    service = build(db_session, sender)
    await service.register(email=EMAIL, password=PASSWORD_ATTACKER)
    await service.register(email=EMAIL, password=PASSWORD_OWNER)
    await service.verify_email(email=EMAIL, code=sender.last_code())

    assert (await user_row(db_session)).email_verified_at is not None


async def test_the_code_hash_does_not_use_the_raw_token_signing_key(db_session):
    service = build(db_session, RecordingSender())
    legacy = hmac.new(SECRET.encode(), b"123456", hashlib.sha256).hexdigest()

    assert service._code_hash("123456") != legacy


async def test_login_hashes_the_password_even_when_the_account_does_not_exist(db_session, monkeypatch):
    calls: list[str] = []
    real_verify = mobile_auth._passwords.verify

    def spy(password, hash_):
        calls.append(hash_)
        return real_verify(password, hash_)

    monkeypatch.setattr(mobile_auth._passwords, "verify", spy)
    service = build(db_session, RecordingSender())

    with pytest.raises(ForbiddenError) as error:
        await service.login(email="nobody@example.com", password="Cualquiera123")

    assert error.value.code == "auth_invalid_credentials"
    assert len(calls) == 1


async def test_login_with_a_wrong_password_gives_the_same_error(db_session):
    db_session.add(
        User(
            email=EMAIL, full_name="Ana", is_active=True,
            password_hash=mobile_auth._passwords.hash(PASSWORD_OWNER),
            email_verified_at=datetime.now(UTC),
        )
    )
    await db_session.commit()

    with pytest.raises(ForbiddenError) as error:
        await build(db_session, RecordingSender()).login(email=EMAIL, password="Incorrecta123")

    assert error.value.code == "auth_invalid_credentials"
