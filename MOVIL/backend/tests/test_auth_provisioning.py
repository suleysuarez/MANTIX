"""Clerk identity -> local user provisioning, against the real repository.

`ClerkAuthService` with the real `AuthRepository` on a migrated database
(`MIGRATED_DATABASE_URL`, rolled back after each test), plus the Clerk profile
lookup with the Clerk SDK client faked.
"""

import os
from types import SimpleNamespace

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

from app.core import clerk as clerk_module
from app.core.clerk import (
    ClerkProfile,
    VerifiedClerkIdentity,
    get_clerk_profile,
    verify_clerk_request,
)
from app.core.config import Settings
from app.core.exceptions import ConflictError, ForbiddenError
from app.models.auth import Role, User, UserRole
from app.repositories.auth import AuthRepository
from app.services.auth import ClerkAuthService

MIGRATED_DATABASE_URL = os.environ.get("MIGRATED_DATABASE_URL", "")
needs_db = pytest.mark.skipif(
    not MIGRATED_DATABASE_URL, reason="MIGRATED_DATABASE_URL is not set"
)


@pytest.fixture
async def session():
    if not MIGRATED_DATABASE_URL:
        pytest.skip("MIGRATED_DATABASE_URL is not set")
    engine = create_async_engine(
        Settings(database_url=MIGRATED_DATABASE_URL).database_url
    )
    connection = await engine.connect()
    outer = await connection.begin()
    db = AsyncSession(
        bind=connection,
        join_transaction_mode="create_savepoint",
        expire_on_commit=False,
        autoflush=False,
    )
    yield db
    await db.close()
    await outer.rollback()
    await connection.close()
    await engine.dispose()


def identity(clerk_id, email="someone@example.com", name="Some One"):
    return VerifiedClerkIdentity(
        user_id=clerk_id, claims={"sub": clerk_id, "email": email, "name": name}
    )


@pytest.fixture
def service(session, monkeypatch):
    async def profile(identity, settings):
        claims = identity.claims
        return ClerkProfile(identity.user_id, claims["email"], claims["name"])

    async def verified_profile(identity, settings):
        claims = identity.claims
        return ClerkProfile(
            identity.user_id,
            claims["email"].lower(),
            claims["name"],
            email_verified=True,
        )

    monkeypatch.setattr("app.services.auth.get_clerk_profile", profile)
    monkeypatch.setattr(
        "app.services.auth.get_verified_clerk_profile", verified_profile
    )
    return ClerkAuthService(AuthRepository(session), Settings())


async def role_codes(session, user_id):
    rows = await session.execute(
        select(Role.code)
        .join(UserRole, UserRole.role_id == Role.id)
        .where(UserRole.user_id == user_id)
    )
    return list(rows.scalars().all())


@needs_db
async def test_first_ever_user_is_bootstrapped_as_admin_and_later_users_are_pending(
    session, service
):
    first = await service.resolve_local_user(identity("clerk_1", "first@example.com"))
    assert [r.code for r in first.roles] == ["ADMIN"]
    assert {p.code for p in first.roles[0].permissions} >= {
        "users.manage",
        "audit.read",
    }

    second = await service.resolve_local_user(identity("clerk_2", "second@example.com"))
    assert second.roles == []  # waits for an admin to grant a role
    assert await role_codes(session, second.id) == []

    # a returning user is found by their Clerk id, no duplicate row
    again = await service.resolve_local_user(identity("clerk_1", "first@example.com"))
    assert again.id == first.id
    count = (
        (await session.execute(select(User).where(User.clerk_user_id == "clerk_1")))
        .scalars()
        .all()
    )
    assert len(count) == 1


@needs_db
async def test_a_roleless_user_is_promoted_only_while_no_role_exists_anywhere(
    session, service
):
    orphan = User(
        clerk_user_id="clerk_o", email="o@example.com", full_name="O", is_active=True
    )
    session.add(orphan)
    await session.flush()
    promoted = await service.resolve_local_user(identity("clerk_o", "o@example.com"))
    assert [r.code for r in promoted.roles] == ["ADMIN"]

    late = User(
        clerk_user_id="clerk_l", email="l@example.com", full_name="L", is_active=True
    )
    session.add(late)
    await session.flush()
    still_pending = await service.resolve_local_user(
        identity("clerk_l", "l@example.com")
    )
    assert still_pending.roles == []


@needs_db
async def test_inactive_local_users_are_refused(session, service):
    session.add(
        User(
            clerk_user_id="clerk_x",
            email="x@example.com",
            full_name="X",
            is_active=False,
        )
    )
    await session.flush()
    with pytest.raises(ForbiddenError):
        await service.resolve_local_user(identity("clerk_x", "x@example.com"))


@needs_db
async def test_verified_same_email_relinks_existing_user_without_losing_roles(
    session, service
):
    existing = User(
        clerk_user_id="clerk_a",
        email="shared@example.com",
        full_name="Existing Account",
        is_active=True,
    )
    session.add(existing)
    await session.flush()
    user_id = existing.id

    resolved = await service.resolve_local_user(
        identity("clerk_b", "shared@example.com")
    )

    assert resolved.id == user_id
    assert resolved.clerk_user_id == "clerk_b"
    assert resolved.email == "shared@example.com"
    assert resolved.full_name == "Existing Account"


@needs_db
async def test_unverified_email_cannot_relink_existing_user(
    session, service, monkeypatch
):
    async def unverified_profile(identity, settings):
        return ClerkProfile(
            identity.user_id,
            identity.claims["email"].lower(),
            identity.claims["name"],
            email_verified=False,
        )

    monkeypatch.setattr(
        "app.services.auth.get_verified_clerk_profile", unverified_profile
    )
    session.add(
        User(
            clerk_user_id="clerk_a",
            email="shared@example.com",
            full_name="A",
            is_active=True,
        )
    )
    await session.flush()

    with pytest.raises(ConflictError, match="not verified"):
        await service.resolve_local_user(identity("clerk_b", "shared@example.com"))


@needs_db
async def test_repository_lookups(session):
    repo = AuthRepository(session)
    assert await repo.get_user_by_clerk_id("nope") is None
    assert await repo.get_user_by_email("nope@example.com") is None
    assert (await repo.get_admin_role()).code == "ADMIN"
    assert (await repo.get_employee_role()).code == "EMPLOYEE"
    assert await repo.has_assigned_application_role() is False


# -- Clerk profile lookup (SDK faked) ----------------------------------------------------


class FakeUsers:
    def __init__(self, user):
        self.user = user
        self.calls = []

    async def get_async(self, user_id):
        self.calls.append(user_id)
        return self.user


def fake_clerk(user):
    return SimpleNamespace(users=FakeUsers(user))


SETTINGS = Settings(clerk_secret_key="sk_test_x")


async def test_profile_comes_from_token_claims_when_they_include_an_email():
    profile = await get_clerk_profile(
        identity("u1", "MiXeD@Example.com", "Ana"), SETTINGS
    )
    assert profile == ClerkProfile("u1", "mixed@example.com", "Ana")


async def test_verified_profile_uses_clerk_primary_email_and_verification(monkeypatch):
    clerk_user = SimpleNamespace(
        email_addresses=[
            SimpleNamespace(
                id="e1",
                email_address="Primary@Example.com",
                verification=SimpleNamespace(status="verified"),
            )
        ],
        primary_email_address_id="e1",
        first_name="Ana",
        last_name="Ruiz",
    )
    client = fake_clerk(clerk_user)
    monkeypatch.setattr(clerk_module, "get_clerk_client", lambda key: client)
    profile = await clerk_module.get_verified_clerk_profile(
        VerifiedClerkIdentity("u1", {"sub": "u1", "email": "untrusted@example.com"}),
        SETTINGS,
    )
    assert profile.email == "primary@example.com"
    assert profile.email_verified is True
    assert client.users.calls == ["u1"]


async def test_verified_profile_marks_unverified_primary_email(monkeypatch):
    clerk_user = SimpleNamespace(
        email_addresses=[
            SimpleNamespace(
                id="e1",
                email_address="primary@example.com",
                verification=SimpleNamespace(status="unverified"),
            )
        ],
        primary_email_address_id="e1",
        first_name="Ana",
        last_name="Ruiz",
    )
    monkeypatch.setattr(
        clerk_module, "get_clerk_client", lambda key: fake_clerk(clerk_user)
    )
    profile = await clerk_module.get_verified_clerk_profile(
        VerifiedClerkIdentity("u1", {"sub": "u1"}), SETTINGS
    )
    assert profile.email_verified is False


async def test_profile_is_fetched_from_clerk_using_the_primary_email(monkeypatch):
    clerk_user = SimpleNamespace(
        email_addresses=[
            SimpleNamespace(id="e1", email_address="Other@Example.com"),
            SimpleNamespace(id="e2", email_address="Primary@Example.com"),
        ],
        primary_email_address_id="e2",
        first_name="Ana",
        last_name="Ruiz",
    )
    client = fake_clerk(clerk_user)
    monkeypatch.setattr(clerk_module, "get_clerk_client", lambda key: client)
    bare = VerifiedClerkIdentity("u1", {"sub": "u1"})
    profile = await get_clerk_profile(bare, SETTINGS)
    assert profile == ClerkProfile("u1", "primary@example.com", "Ana Ruiz")
    assert client.users.calls == ["u1"]


async def test_profile_falls_back_to_first_email_and_default_name(monkeypatch):
    clerk_user = SimpleNamespace(
        email_addresses=[SimpleNamespace(id="e1", email_address="only@example.com")],
        primary_email_address_id=None,
        first_name=None,
        last_name=None,
    )
    monkeypatch.setattr(
        clerk_module, "get_clerk_client", lambda key: fake_clerk(clerk_user)
    )
    profile = await get_clerk_profile(
        VerifiedClerkIdentity("u2", {"sub": "u2"}), SETTINGS
    )
    assert profile == ClerkProfile("u2", "only@example.com", "Clerk user")


async def test_profile_without_any_email_is_rejected(monkeypatch):
    from fastapi import HTTPException

    clerk_user = SimpleNamespace(email_addresses=[], primary_email_address_id=None)
    monkeypatch.setattr(
        clerk_module, "get_clerk_client", lambda key: fake_clerk(clerk_user)
    )
    with pytest.raises(HTTPException) as error:
        await get_clerk_profile(VerifiedClerkIdentity("u3", {"sub": "u3"}), SETTINGS)
    assert error.value.status_code == 401


async def test_profile_cannot_be_resolved_without_a_secret_key():
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as error:
        await get_clerk_profile(
            VerifiedClerkIdentity("u4", {"sub": "u4"}), Settings(clerk_secret_key="")
        )
    assert error.value.status_code == 401


def request_stub():
    return SimpleNamespace(
        method="GET",
        url="http://testserver/auth/me",
        headers={"authorization": "Bearer token"},
    )


def test_verification_accepts_a_signed_in_session(monkeypatch):
    state = SimpleNamespace(
        is_signed_in=True, payload={"sub": "user_9", "email": "a@b.co"}
    )
    monkeypatch.setattr(
        clerk_module, "authenticate_request", lambda req, options: state
    )
    result = verify_clerk_request(request_stub(), SETTINGS)
    assert result.user_id == "user_9" and result.claims["email"] == "a@b.co"


@pytest.mark.parametrize(
    "state",
    [
        SimpleNamespace(is_signed_in=False, payload=None),
        SimpleNamespace(is_signed_in=True, payload=None),
        SimpleNamespace(is_signed_in=True, payload={"email": "no-subject@x.co"}),
    ],
)
def test_verification_rejects_unsigned_or_subjectless_sessions(monkeypatch, state):
    from fastapi import HTTPException

    monkeypatch.setattr(
        clerk_module, "authenticate_request", lambda req, options: state
    )
    with pytest.raises(HTTPException) as error:
        verify_clerk_request(request_stub(), SETTINGS)
    assert error.value.status_code == 401
    assert error.value.headers == {"WWW-Authenticate": "Bearer"}
