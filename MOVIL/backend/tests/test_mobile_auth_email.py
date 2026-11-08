"""Code emails through MobileAuthService against a disposable local database.

Skipped unless TEST_DATABASE_URL points to a local database ending in `_test`
(see tests/conftest.py). Delivery is always faked.
"""

from datetime import UTC, datetime

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.models.auth import AuthEmailCode, User
from app.services.code_email_limiter import CodeEmailLimiter
from app.services.mobile_auth import MobileAuthService

EMAIL = "ana.perez@example.com"


class RecordingSender:
    def __init__(self, error: Exception | None = None):
        self.error = error
        self.sent: list[dict] = []

    async def send(self, **kwargs):
        self.sent.append(kwargs)
        if self.error is not None:
            raise self.error


@pytest.fixture
async def user(db_session: AsyncSession) -> User:
    account = User(
        email=EMAIL, full_name="Ana", is_active=True, password_hash="x",
        email_verified_at=datetime.now(UTC),
    )
    db_session.add(account)
    await db_session.commit()
    return account


def service(session: AsyncSession, sender: RecordingSender) -> MobileAuthService:
    return MobileAuthService(
        session, Settings(_env_file=None), sender=sender, limiter=CodeEmailLimiter()
    )


async def record(session: AsyncSession, user: User, purpose: str) -> AuthEmailCode:
    result = await session.execute(
        select(AuthEmailCode).where(AuthEmailCode.user_id == user.id, AuthEmailCode.purpose == purpose)
    )
    return result.scalar_one()


async def test_forgot_password_answers_normally_when_the_delivery_fails(db_session, user):
    sender = RecordingSender(error=RuntimeError("smtp down"))
    await service(db_session, sender).forgot_password(EMAIL)  # must not raise

    assert len(sender.sent) == 1
    assert (await record(db_session, user, "reset")).attempts == 0


async def test_resend_verification_for_a_verified_or_unknown_account_sends_nothing(db_session, user):
    sender = RecordingSender()
    svc = service(db_session, sender)
    await svc.resend_verification(EMAIL)  # already verified
    await svc.resend_verification("nobody@example.com")
    await svc.forgot_password("nobody@example.com")
    assert sender.sent == []


async def test_a_second_request_inside_the_wait_does_not_reset_the_attempts(db_session, user):
    sender = RecordingSender()
    svc = service(db_session, sender)
    await svc.forgot_password(EMAIL)
    row = await record(db_session, user, "reset")
    row.attempts = 3
    await db_session.commit()
    first_hash = row.code_hash

    await svc.forgot_password(EMAIL)  # blocked by the 60 s wait

    row = await record(db_session, user, "reset")
    assert len(sender.sent) == 1
    assert row.attempts == 3 and row.code_hash == first_hash


async def test_the_recovery_email_carries_the_account_address_as_recipient(db_session, user):
    sender = RecordingSender()
    await service(db_session, sender).forgot_password(EMAIL)

    assert sender.sent[0]["to"] == EMAIL
    assert "Recupera" in sender.sent[0]["subject"]
