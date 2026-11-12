"""Last access of the native mobile sign-in. No database: only fakes."""

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest

from app.core.config import Settings
from app.services.audit import AuditService
from app.services.code_email_limiter import CodeEmailLimiter
from app.services.login_tracking import SESSION_GAP, record_login
from app.services.mobile_auth import MobileAuthService

NOW = datetime(2026, 11, 11, 12, 0, tzinfo=UTC)
SECRET = "test-only-secret-" + "x" * 32


class RecordingAudit:
    def __init__(self) -> None:
        self.records: list[dict] = []

    def record(self, **kwargs) -> None:
        self.records.append(kwargs)


class Commits:
    def __init__(self) -> None:
        self.count = 0

    async def __call__(self) -> None:
        self.count += 1


class FakeSession:
    def __init__(self) -> None:
        self.commits = 0

    async def commit(self) -> None:
        self.commits += 1


def user(last_login_at: datetime | None) -> SimpleNamespace:
    return SimpleNamespace(id=3, last_login_at=last_login_at)


async def test_the_first_sign_in_stamps_the_last_access_audits_and_commits() -> None:
    audit, commit, person = RecordingAudit(), Commits(), user(None)

    recorded = await record_login(person, commit=commit, audit=audit, now=NOW)

    assert recorded is True
    assert person.last_login_at == NOW
    assert commit.count == 1
    assert audit.records == [
        {"user_id": 3, "action": "auth.login", "entity_type": "user", "entity_id": 3}
    ]


async def test_a_second_sign_in_inside_the_gap_changes_nothing() -> None:
    audit, commit = RecordingAudit(), Commits()
    first = NOW - timedelta(minutes=5)
    person = user(first)

    recorded = await record_login(person, commit=commit, audit=audit, now=NOW)

    assert recorded is False
    assert person.last_login_at == first
    assert commit.count == 0
    assert audit.records == []


async def test_a_new_session_after_the_gap_is_recorded_again() -> None:
    audit, commit = RecordingAudit(), Commits()
    old = NOW - timedelta(hours=2)
    person = user(old)

    recorded = await record_login(person, commit=commit, audit=audit, now=NOW)

    assert recorded is True
    assert person.last_login_at == NOW
    assert len(audit.records) == 1
    assert commit.count == 1


async def test_exactly_at_the_gap_counts_as_a_new_session() -> None:
    person = user(NOW - SESSION_GAP)
    assert await record_login(person, commit=Commits(), now=NOW) is True
    assert person.last_login_at == NOW


async def test_without_an_audit_recorder_it_still_stamps_and_commits() -> None:
    commit, person = Commits(), user(None)

    assert await record_login(person, commit=commit, now=NOW) is True
    assert person.last_login_at == NOW
    assert commit.count == 1


async def test_the_clock_defaults_to_now() -> None:
    person = user(None)
    before = datetime.now(UTC)

    await record_login(person, commit=Commits())

    assert before <= person.last_login_at <= datetime.now(UTC)


def mobile_service(
    audit: RecordingAudit | None = None,
) -> tuple[MobileAuthService, FakeSession]:
    session = FakeSession()
    service = MobileAuthService(
        session,  # type: ignore[arg-type]
        Settings(_env_file=None, MOBILE_JWT_SECRET=SECRET),
        sender=object(),  # type: ignore[arg-type]
        limiter=CodeEmailLimiter(min_interval_seconds=0),
        audit=audit,  # type: ignore[arg-type]
    )
    return service, session


async def test_the_native_sign_in_records_the_access_in_its_own_transaction() -> None:
    audit = RecordingAudit()
    service, session = mobile_service(audit)
    person = user(None)

    await service._record_login(person)  # type: ignore[arg-type]

    assert person.last_login_at is not None
    assert session.commits == 1
    assert [r["action"] for r in audit.records] == ["auth.login"]


async def test_signing_in_twice_in_a_row_records_one_session() -> None:
    audit = RecordingAudit()
    service, session = mobile_service(audit)
    person = user(None)

    await service._record_login(person)  # type: ignore[arg-type]
    await service._record_login(person)  # type: ignore[arg-type]

    assert session.commits == 1
    assert len(audit.records) == 1


def test_without_an_audit_recorder_the_service_builds_its_own() -> None:
    service, _ = mobile_service()
    assert isinstance(service.audit, AuditService)


@pytest.mark.parametrize("path", ["app/services/auth.py"])
def test_nothing_that_reads_clerk_stamps_the_last_access(path: str) -> None:
    from pathlib import Path

    source = Path(path).read_text(encoding="utf-8")
    assert "last_login_at" not in source
    assert "_touch_login" not in source
