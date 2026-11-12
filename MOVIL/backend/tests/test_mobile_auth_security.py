"""Registration without e-mail verification, code-key and login-timing hardening of MobileAuthService.

Needs TEST_DATABASE_URL pointing to a disposable local `*_test` database
(see tests/conftest.py). Delivery is always faked.
"""

import hashlib
import hmac
import re
from datetime import UTC, datetime

import pytest
from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.exceptions import ConflictError, ForbiddenError
from app.models.auth import Role, User, UserRole
from app.schemas.mobile_auth import MobileRegisterRequest, MobileVerifyEmailRequest
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
    return (
        await session.execute(select(func.count()).select_from(UserRole))
    ).scalar_one()


async def user_row(session: AsyncSession) -> User:
    return (await session.execute(select(User).where(User.email == EMAIL))).scalar_one()


async def test_the_first_account_becomes_administrator(db_session, admin_role):
    await build(db_session, RecordingSender()).register(
        email=EMAIL, password=PASSWORD_OWNER, first_name="Ana"
    )

    assert await role_assignments(db_session) == 1


async def test_later_accounts_get_no_role_until_an_administrator_approves_them(
    db_session, admin_role
):
    service = build(db_session, RecordingSender())
    await service.register(
        email="admin@example.com", password=PASSWORD_OWNER, first_name="Admin"
    )
    await service.register(email=EMAIL, password=PASSWORD_OWNER, first_name="Ana")

    assert await role_assignments(db_session) == 1  # only the first one


async def test_registering_creates_a_ready_account_and_sends_no_email(
    db_session, admin_role
):
    sender = RecordingSender()
    await build(db_session, sender).register(
        email=EMAIL, password=PASSWORD_OWNER, first_name="Ana"
    )

    account = await user_row(db_session)
    assert account.is_active and account.email_verified_at is not None
    assert sender.sent == []


async def test_registering_an_existing_email_is_a_conflict_and_keeps_the_account(
    db_session, admin_role
):
    service = build(db_session, RecordingSender())
    await service.register(email=EMAIL, password=PASSWORD_OWNER, first_name="Ana")

    with pytest.raises(ConflictError) as error:
        await service.register(
            email=EMAIL, password=PASSWORD_ATTACKER, first_name="Otra"
        )

    assert error.value.code == "user_email_taken"
    account = await user_row(db_session)
    assert mobile_auth._passwords.verify(PASSWORD_OWNER, account.password_hash)
    assert not mobile_auth._passwords.verify(PASSWORD_ATTACKER, account.password_hash)
    assert account.full_name == "Ana"


async def test_an_account_left_unverified_by_the_old_flow_can_sign_in(db_session):
    db_session.add(
        User(
            email=EMAIL,
            full_name="Ana",
            is_active=True,
            password_hash=mobile_auth._passwords.hash(PASSWORD_OWNER),
            email_verified_at=None,
        )
    )
    await db_session.commit()

    session = await build(db_session, RecordingSender()).login(
        email=EMAIL, password=PASSWORD_OWNER
    )

    assert session["access_token"].startswith("mjwt.")


async def test_the_code_hash_does_not_use_the_raw_token_signing_key(db_session):
    service = build(db_session, RecordingSender())
    legacy = hmac.new(SECRET.encode(), b"123456", hashlib.sha256).hexdigest()

    assert service._code_hash("123456") != legacy


async def test_login_hashes_the_password_even_when_the_account_does_not_exist(
    db_session, monkeypatch
):
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
            email=EMAIL,
            full_name="Ana",
            is_active=True,
            password_hash=mobile_auth._passwords.hash(PASSWORD_OWNER),
            email_verified_at=datetime.now(UTC),
        )
    )
    await db_session.commit()

    with pytest.raises(ForbiddenError) as error:
        await build(db_session, RecordingSender()).login(
            email=EMAIL, password="Incorrecta123"
        )

    assert error.value.code == "auth_invalid_credentials"


def test_verify_email_requires_a_strong_password():
    ok = {"email": EMAIL, "code": "123456", "password": PASSWORD_OWNER}
    assert MobileVerifyEmailRequest(**ok).password == PASSWORD_OWNER
    for bad in (
        None,
        "corta1A",
        "sinmayusculas123",
        "SINMINUSCULAS123",
        "SinNumeros-aqui",
    ):
        with pytest.raises(ValidationError):
            MobileVerifyEmailRequest(**{**ok, "password": bad})


async def test_the_first_name_is_required_and_the_last_name_optional_when_registering(
    db_session, admin_role
):
    service = build(db_session, RecordingSender())
    await service.register(
        email=EMAIL, password=PASSWORD_OWNER, first_name="  Ana ", last_name=" Pérez "
    )
    assert (await user_row(db_session)).full_name == "Ana Pérez"


async def test_registering_without_a_last_name_stores_only_the_first_name(
    db_session, admin_role
):
    await build(db_session, RecordingSender()).register(
        email=EMAIL, password=PASSWORD_OWNER, first_name="Ana"
    )
    assert (await user_row(db_session)).full_name == "Ana"


def test_register_request_validates_the_names():
    base = {"email": EMAIL, "password": PASSWORD_OWNER}
    ok = MobileRegisterRequest(**base, first_name=" Ana ", last_name="  ")
    assert (ok.first_name, ok.last_name) == ("Ana", None)
    assert (
        MobileRegisterRequest(**base, first_name="Ana", last_name="Pérez").last_name
        == "Pérez"
    )
    for bad in (None, "", "   ", "x" * 101):
        with pytest.raises(ValidationError):
            MobileRegisterRequest(**base, first_name=bad)
    with pytest.raises(ValidationError):
        MobileRegisterRequest(**base, first_name="Ana", last_name="x" * 101)
