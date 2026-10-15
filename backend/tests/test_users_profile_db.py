"""SQL of the Users screen, the profile history and the users export, against real PostgreSQL."""

from datetime import UTC, datetime, timedelta

from app.core.pagination import PageParams
from app.models.audit import AuditLog
from app.models.auth import Role, User, UserRole
from app.repositories.export import ExportRepository
from app.repositories.profile import ProfileRepository
from app.repositories.user_management import UserManagementRepository
from app.schemas.export import ExportFilters

NOW = datetime(2026, 10, 15, 12, 0, tzinfo=UTC)


async def seed(session):
    admin = Role(code="ADMIN", name="Administrador", is_active=True)
    employee = Role(code="EMPLOYEE", name="Empleado", is_active=True)
    retired = Role(code="OLD", name="Antiguo", is_active=False)
    session.add_all([admin, employee, retired])
    await session.flush()
    users = [
        User(
            email="ana@x.com",
            full_name="Ana Pérez",
            employee_code="E-1",
            clerk_user_id="c1",
            is_active=True,
            last_login_at=NOW,
        ),
        User(
            email="luis@x.com",
            full_name="Luis Gómez",
            employee_code="E-2",
            clerk_user_id="c2",
            is_active=False,
            last_login_at=NOW - timedelta(days=3),
        ),
        User(email="eva@x.com", full_name="Eva Ríos", is_active=True),
    ]
    session.add_all(users)
    await session.flush()
    ana, luis, eva = users
    session.add_all(
        [
            UserRole(user_id=ana.id, role_id=admin.id),
            UserRole(user_id=ana.id, role_id=employee.id),
            UserRole(user_id=luis.id, role_id=employee.id),
        ]
    )
    await session.flush()
    return admin, employee, ana, luis, eva


async def test_user_search_filters_sorts_and_paginates(db_session):
    _, _, ana, luis, eva = await seed(db_session)
    repo = UserManagementRepository(db_session)

    everyone = await repo.search()
    assert everyone.total == 3

    by_name = await repo.search(params=PageParams(sort="name"))
    assert [u.full_name for u in by_name.items] == [
        "Ana Pérez",
        "Eva Ríos",
        "Luis Gómez",
    ]
    newest_login = await repo.search(params=PageParams(sort="-last_login_at"))
    assert newest_login.items[0].id in {
        ana.id,
        eva.id,
    }  # nulls sort first in PostgreSQL desc

    assert (await repo.search(role_code="ADMIN")).total == 1
    assert (await repo.search(role_code="EMPLOYEE")).total == 2
    assert [u.id for u in (await repo.search(is_active=False)).items] == [luis.id]
    assert (await repo.search(search="gómez")).total == 1
    assert (await repo.search(search="E-1")).total == 1
    assert (await repo.search(created_from=NOW + timedelta(days=1))).total == 0

    page = await repo.search(params=PageParams(page=2, size=2, sort="name"))
    assert page.total == 3 and [u.id for u in page.items] == [luis.id]
    assert eva.id  # the unlinked, role-less person is still listed above


async def test_user_roles_are_loaded_with_each_user(db_session):
    await seed(db_session)
    repo = UserManagementRepository(db_session)

    ana = (await repo.search(search="Ana")).items[0]
    assert sorted(link.role.code for link in ana.user_roles) == ["ADMIN", "EMPLOYEE"]


async def test_uniqueness_checks_ignore_case_and_the_person_being_edited(db_session):
    _, _, ana, luis, _ = await seed(db_session)
    repo = UserManagementRepository(db_session)

    assert await repo.email_taken("ANA@X.COM")
    assert not await repo.email_taken("ana@x.com", excluding=ana.id)
    assert await repo.email_taken("ana@x.com", excluding=luis.id)
    assert await repo.code_taken("e-2")
    assert not await repo.code_taken("e-2", excluding=luis.id)
    assert not await repo.code_taken("E-99")


async def test_only_active_roles_can_be_assigned(db_session):
    admin, employee, *_ = await seed(db_session)
    repo = UserManagementRepository(db_session)

    found = await repo.roles_by_ids([admin.id, employee.id, 9999])
    assert {r.code for r in found} == {"ADMIN", "EMPLOYEE"}
    old = (
        await db_session.execute(Role.__table__.select().where(Role.code == "OLD"))
    ).one()
    assert await repo.roles_by_ids([old.id]) == []


async def test_create_and_replace_roles(db_session):
    admin, employee, *_ = await seed(db_session)
    repo = UserManagementRepository(db_session)

    user = await repo.create(
        email="nuevo@x.com",
        full_name="Nuevo Usuario",
        phone=None,
        employee_code="N-1",
        roles=[employee],
        assigned_by=None,  # type: ignore[arg-type]
    )
    loaded = await repo.get(user.id)
    assert loaded and loaded.clerk_user_id is None and loaded.is_active
    assert [link.role.code for link in loaded.user_roles] == ["EMPLOYEE"]

    await repo.replace_roles(loaded, [admin], assigned_by=user.id)
    again = await repo.get(user.id)
    assert again and [link.role.code for link in again.user_roles] == ["ADMIN"]


async def test_indicators(db_session):
    await seed(db_session)
    repo = UserManagementRepository(db_session)

    total, active, never, without_role = await repo.totals()
    assert (total, active, never, without_role) == (3, 2, 1, 1)
    by_role = {code: count for code, _, count in await repo.count_by_role()}
    assert by_role == {"ADMIN": 1, "EMPLOYEE": 1}  # only active people are counted
    assert [u.full_name for u in await repo.recent_access()] == [
        "Ana Pérez",
        "Luis Gómez",
    ]
    assert await repo.count_active_admins() == 1


async def test_history_covers_what_you_did_and_what_was_done_to_you(db_session):
    _, _, ana, luis, _ = await seed(db_session)
    rows = [
        AuditLog(
            user_id=ana.id, action="auth.login", entity_type="user", entity_id=ana.id
        ),
        AuditLog(
            user_id=ana.id,
            action="profile.updated",
            entity_type="user",
            entity_id=ana.id,
        ),
        AuditLog(
            user_id=ana.id,
            action="profile.password_changed",
            entity_type="user",
            entity_id=ana.id,
        ),
        AuditLog(
            user_id=luis.id,
            action="roles.replaced",
            entity_type="user",
            entity_id=ana.id,
        ),
        AuditLog(
            user_id=ana.id,
            action="maintenance.status_changed",
            entity_type="maintenance_request",
            entity_id=7,
        ),
        AuditLog(
            user_id=luis.id, action="auth.login", entity_type="user", entity_id=luis.id
        ),
    ]
    db_session.add_all(rows)
    await db_session.flush()
    repo = ProfileRepository(db_session)

    mine = await repo.history(ana.id)
    assert mine.total == 5  # luis's own login is not mine
    actions = {r.action for r in mine.items}
    assert "roles.replaced" in actions and actions.isdisjoint({"x"})
    assert (
        next(r for r in mine.items if r.action == "roles.replaced").user.full_name
        == "Luis Gómez"
    )

    assert {r.action for r in (await repo.history(ana.id, kind="session")).items} == {
        "auth.login"
    }
    assert {r.action for r in (await repo.history(ana.id, kind="profile")).items} == {
        "profile.updated"
    }
    assert {r.action for r in (await repo.history(ana.id, kind="security")).items} == {
        "profile.password_changed",
        "roles.replaced",
    }
    assert {r.action for r in (await repo.history(ana.id, kind="activity")).items} == {
        "maintenance.status_changed"
    }


async def test_history_filters_by_date_and_paginates_newest_first(db_session):
    _, _, ana, *_ = await seed(db_session)
    for days in range(5):
        db_session.add(
            AuditLog(
                user_id=ana.id,
                action="auth.login",
                entity_type="user",
                entity_id=ana.id,
                created_at=NOW - timedelta(days=days),
            )
        )
    await db_session.flush()
    repo = ProfileRepository(db_session)

    page = await repo.history(ana.id, params=PageParams(page=1, size=2))
    assert page.total == 5 and len(page.items) == 2
    assert page.items[0].created_at > page.items[1].created_at
    recent = await repo.history(ana.id, date_from=NOW - timedelta(days=1, hours=1))
    assert recent.total == 2
    old = await repo.history(ana.id, date_to=NOW - timedelta(days=3, hours=1))
    assert old.total == 1


async def test_users_export_query_matches_the_screen_filters(db_session):
    await seed(db_session)
    repo = ExportRepository(db_session)

    assert await repo.count_users(ExportFilters()) == 3
    rows = await repo.export_users(ExportFilters(role="EMPLOYEE", is_active=True))
    assert [r["full_name"] for r in rows] == ["Ana Pérez"]
    assert rows[0]["roles"] and "Administrador" in rows[0]["roles"]
    assert (await repo.export_users(ExportFilters(is_active=False)))[0][
        "full_name"
    ] == "Luis Gómez"
    assert await repo.count_users(ExportFilters(search="eva")) == 1
    never = await repo.export_users(ExportFilters(search="eva"))
    assert never[0]["roles"] is None and never[0]["last_login_at"] is None
