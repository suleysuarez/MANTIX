from datetime import UTC, datetime
from types import SimpleNamespace

import pytest
from pydantic import ValidationError

from app.core.authz import AuthContext
from app.core.exceptions import (
    ConflictError,
    ForbiddenError,
    NotFoundError,
    UnprocessableError,
)
from app.schemas.user_management import PasswordReset, UserCreate, UserUpdate
from app.services.user_management import UserManagementService
from tests.support import expand


class FakeAudit:
    def __init__(self):
        self.records = []

    def record(self, **kwargs):
        self.records.append(kwargs)


class FakeNotifications:
    def __init__(self):
        self.sent = []

    def notify(self, **kwargs):
        self.sent.append(kwargs)


def role(role_id, code):
    return SimpleNamespace(id=role_id, code=code, name=code.title(), is_active=True)


ADMIN = role(1, "ADMIN")
EMPLOYEE = role(2, "EMPLOYEE")


def person(user_id, email, *, roles=(), active=True, clerk="clerk"):
    return SimpleNamespace(
        id=user_id,
        email=email,
        full_name=f"Persona {user_id}",
        phone=None,
        employee_code=None,
        is_active=active,
        clerk_user_id=clerk,
        created_at=datetime(2026, 1, 1, tzinfo=UTC),
        last_login_at=None,
        user_roles=[SimpleNamespace(role=r, role_id=r.id) for r in roles],
    )


class FakeRepository:
    def __init__(self, users):
        self.users = {u.id: u for u in users}
        self.roles = {1: ADMIN, 2: EMPLOYEE}
        self.committed = 0

    async def get(self, user_id):
        return self.users.get(user_id)

    async def email_taken(self, email, *, excluding=None):
        return any(
            u.email.lower() == email.lower() and u.id != excluding
            for u in self.users.values()
        )

    async def code_taken(self, code, *, excluding=None):
        return any(
            (u.employee_code or "").upper() == code.upper() and u.id != excluding
            for u in self.users.values()
        )

    async def roles_by_ids(self, role_ids):
        return [self.roles[i] for i in role_ids if i in self.roles]

    async def count_active_admins(self):
        return sum(
            1
            for u in self.users.values()
            if u.is_active and any(link.role.code == "ADMIN" for link in u.user_roles)
        )

    async def create(
        self, *, email, full_name, phone, employee_code, roles, assigned_by
    ):
        user = person(max(self.users, default=0) + 1, email, roles=roles, clerk=None)
        user.full_name, user.phone, user.employee_code = full_name, phone, employee_code
        self.users[user.id] = user
        return user

    async def replace_roles(self, user, roles, assigned_by):
        user.user_roles = [SimpleNamespace(role=r, role_id=r.id) for r in roles]

    async def commit(self):
        self.committed += 1


def build(users, sink=None):
    repository = FakeRepository(users)
    audit, notifications = FakeAudit(), FakeNotifications()
    passwords = sink if sink is not None else []

    async def set_password(clerk_id, password):
        passwords.append((clerk_id, password))

    service = UserManagementService(repository, audit, notifications, set_password)
    return service, repository, audit, notifications, passwords


def actor(user_id=99):
    return AuthContext(
        user=SimpleNamespace(id=user_id),
        roles=frozenset({"ADMIN"}),
        permissions=expand("users.manage"),
    )


# -- schemas -----------------------------------------------------------------------------


def test_create_requires_valid_email_name_and_a_role():
    ok = UserCreate(email="Ana@Example.com", full_name="  Ana   Pérez ", role_ids=[2])
    assert ok.full_name == "Ana Pérez"
    for bad in (
        {"email": "no-es-correo", "full_name": "Ana Pérez", "role_ids": [2]},
        {"email": "a@example.com", "full_name": "A", "role_ids": [2]},
        {"email": "a@example.com", "full_name": "Ana Pérez", "role_ids": []},
        {
            "email": "a@example.com",
            "full_name": "Ana Pérez",
            "phone": "abc",
            "role_ids": [2],
        },
    ):
        with pytest.raises(ValidationError):
            UserCreate(**bad)


def test_update_rejects_unknown_fields():
    with pytest.raises(ValidationError):
        UserUpdate(is_active=False)  # activation has its own endpoint


@pytest.mark.parametrize(
    "password", ["corta1A", "sinnumeroABCDEF", "SINMINUSCULA1234", "tiene espacio 1Aa"]
)
def test_password_policy_rejects_weak_passwords(password):
    with pytest.raises(ValidationError):
        PasswordReset(password=password)


def test_password_policy_accepts_a_strong_password():
    assert PasswordReset(password="Segura12345").password == "Segura12345"


# -- create / update ---------------------------------------------------------------------


async def test_create_preregisters_with_roles_and_audits():
    service, repository, audit, _, _ = build([person(99, "root@x.com", roles=[ADMIN])])
    created = await service.create(
        UserCreate(email="nuevo@x.com", full_name="Nuevo Usuario", role_ids=[2]),
        actor(),
    )
    assert created.email == "nuevo@x.com"
    assert [r.code for r in created.roles] == ["EMPLOYEE"]
    assert created.linked is False
    assert audit.records[-1]["action"] == "user.created"
    assert repository.committed == 1


async def test_create_rejects_duplicate_email_ignoring_case():
    service, *_ = build([person(1, "dup@x.com", roles=[EMPLOYEE])])
    with pytest.raises(ConflictError):
        await service.create(
            UserCreate(email="DUP@x.com", full_name="Otra Persona", role_ids=[2]),
            actor(),
        )


async def test_create_rejects_unknown_role():
    service, *_ = build([])
    with pytest.raises(NotFoundError):
        await service.create(
            UserCreate(email="n@x.com", full_name="Nuevo Usuario", role_ids=[77]),
            actor(),
        )


async def test_email_can_only_change_before_first_sign_in():
    service, *_ = build(
        [
            person(1, "linked@x.com", clerk="c1"),
            person(2, "pending@x.com", clerk=None),
        ]
    )
    with pytest.raises(UnprocessableError):
        await service.update(1, UserUpdate(email="otro@x.com"), actor())
    updated = await service.update(2, UserUpdate(email="otro@x.com"), actor())
    assert updated.email == "otro@x.com"


async def test_update_audits_old_and_new_values():
    service, _, audit, _, _ = build([person(1, "a@x.com")])
    await service.update(1, UserUpdate(phone="+57 300 123 4567"), actor())
    record = audit.records[-1]
    assert record["action"] == "user.updated"
    assert record["new_values"] == {"phone": "+57 300 123 4567"}
    assert record["old_values"] == {"phone": None}


def test_the_name_is_not_editable_by_an_administrator():
    with pytest.raises(ValidationError):
        UserUpdate(
            full_name="Otro Nombre"
        )  # each person edits it from their own profile


# -- activation and roles ----------------------------------------------------------------


async def test_cannot_deactivate_yourself():
    service, *_ = build([person(5, "me@x.com", roles=[EMPLOYEE])])
    with pytest.raises(ConflictError):
        await service.set_active(5, False, actor(user_id=5))


async def test_cannot_deactivate_the_last_active_admin():
    service, *_ = build([person(1, "admin@x.com", roles=[ADMIN])])
    with pytest.raises(ConflictError):
        await service.set_active(1, False, actor())


async def test_deactivate_and_reactivate_are_audited():
    service, _, audit, _, _ = build(
        [person(1, "a@x.com", roles=[ADMIN]), person(2, "b@x.com", roles=[EMPLOYEE])]
    )
    off = await service.set_active(2, False, actor())
    on = await service.set_active(2, True, actor())
    assert off.is_active is False and on.is_active is True
    assert [r["action"] for r in audit.records] == [
        "user.deactivated",
        "user.activated",
    ]


async def test_cannot_remove_own_admin_role():
    service, *_ = build(
        [person(1, "a@x.com", roles=[ADMIN]), person(2, "b@x.com", roles=[ADMIN])]
    )
    with pytest.raises(ForbiddenError, match="propios roles"):
        await service.replace_roles(1, [2], actor(user_id=1))


async def test_cannot_strip_admin_from_the_only_admin():
    service, *_ = build([person(1, "a@x.com", roles=[ADMIN])])
    with pytest.raises(ConflictError):
        await service.replace_roles(1, [2], actor())


async def test_replace_roles_audits_and_notifies():
    service, _, audit, notifications, _ = build(
        [person(1, "a@x.com", roles=[ADMIN]), person(2, "b@x.com", roles=[EMPLOYEE])]
    )
    updated = await service.replace_roles(2, [1, 2], actor())
    assert sorted(r.code for r in updated.roles) == ["ADMIN", "EMPLOYEE"]
    assert audit.records[-1]["action"] == "roles.replaced"
    assert notifications.sent[-1]["user_id"] == 2


# -- password ----------------------------------------------------------------------------


async def test_reset_password_goes_to_the_sign_in_service_and_is_not_logged():
    service, _, audit, notifications, passwords = build(
        [person(2, "b@x.com", roles=[EMPLOYEE], clerk="clerk_2")]
    )
    await service.reset_password(2, "Segura12345", actor())
    assert passwords == [("clerk_2", "Segura12345")]
    assert audit.records[-1]["action"] == "user.password_reset"
    assert "Segura12345" not in repr(audit.records) + repr(notifications.sent)


async def test_reset_password_refuses_self_unlinked_and_inactive():
    service, *_ = build(
        [
            person(5, "me@x.com", clerk="c5"),
            person(6, "new@x.com", clerk=None),
            person(7, "off@x.com", clerk="c7", active=False),
        ]
    )
    for user_id in (5, 6, 7):
        with pytest.raises(ConflictError):
            await service.reset_password(user_id, "Segura12345", actor(user_id=5))


async def test_unknown_user_is_not_found():
    service, *_ = build([])
    with pytest.raises(NotFoundError):
        await service.get(404)


# -- who may give which roles ----------------------------------------------------------------

AUDITOR_ROLE = SimpleNamespace(
    id=3,
    code="AUDITOR",
    name="Auditor",
    is_active=True,
    permissions=[SimpleNamespace(code="auditoria:ver", is_active=True)],
)


async def test_nobody_changes_their_own_roles():
    service, *_ = build([person(5, "me@x.com", roles=[EMPLOYEE])])
    with pytest.raises(ForbiddenError, match="propios roles"):
        await service.replace_roles(5, [1, 2], actor(user_id=5))


async def test_a_role_cannot_be_given_by_someone_who_lacks_its_permissions():
    service, repository, *_ = build([person(7, "x@x.com", roles=[EMPLOYEE])])
    repository.roles[3] = AUDITOR_ROLE
    # `actor()` manages users but has no `auditoria:ver`: it cannot hand out a role that has it.
    with pytest.raises(ForbiddenError, match="concede permisos"):
        await service.replace_roles(7, [2, 3], actor())
    with pytest.raises(ForbiddenError, match="concede permisos"):
        await service.create(
            UserCreate(email="n@x.com", full_name="Nuevo Usuario", role_ids=[3]),
            actor(),
        )


async def test_the_same_person_may_give_the_role_once_they_hold_its_permissions():
    service, repository, *_ = build([person(7, "x@x.com", roles=[EMPLOYEE])])
    repository.roles[3] = AUDITOR_ROLE
    rich = AuthContext(
        user=SimpleNamespace(id=99),
        roles=frozenset({"ADMIN"}),
        permissions=expand("users.manage") | {"auditoria:ver"},
    )
    updated = await service.replace_roles(7, [2, 3], rich)
    assert sorted(r.code for r in updated.roles) == ["AUDITOR", "EMPLOYEE"]


async def test_assigning_roles_needs_its_own_permission():
    service, *_ = build([person(7, "x@x.com", roles=[EMPLOYEE])])
    no_assign = AuthContext(
        user=SimpleNamespace(id=99),
        roles=frozenset(),
        permissions=frozenset({"usuarios:ver"}),
    )
    with pytest.raises(ForbiddenError, match="administrador"):
        await service.replace_roles(7, [1], no_assign)
