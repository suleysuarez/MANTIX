"""Role inheritance, the `recurso:accion` catalogue, data scope and what the migration seeds."""

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest

from app.core.authz import ADMIN, AUDITOR, EMPLOYEE, SUPERVISOR, TECHNICIAN, AuthContext
from app.core.permissions import (
    ACTION_LABELS,
    CATALOG,
    CATALOG_SET,
    RESOURCE_ACTIONS,
    RESOURCE_LABELS,
    ROLE_LABELS,
    ROLE_OWN_PERMISSIONS,
    ROLE_PARENTS,
    permission_name,
)
from app.core.rbac import (
    MAX_DEPTH,
    RoleCycleError,
    chain_of,
    depth_after,
    effective,
    effective_for_roles,
    effective_permission_objects,
    lineage,
    provenance,
    would_create_cycle,
)
from app.core.scope import DataScope, ScopeKind, kind_from_permissions
from app.models.auth import Permission, Role, User, UserRole
from app.repositories.maintenance import MaintenanceRepository
from app.services.auth import user_response

PARENTS = {"A": None, "B": "A", "C": "B"}
OWN = {"A": frozenset({"x"}), "B": frozenset({"y"}), "C": frozenset({"z"})}


# -- pure inheritance --------------------------------------------------------------------


def test_a_role_has_its_own_permissions_plus_every_ancestors():
    assert effective("A", PARENTS, OWN) == {"x"}
    assert effective("B", PARENTS, OWN) == {"x", "y"}
    assert effective("C", PARENTS, OWN) == {"x", "y", "z"}


def test_lineage_is_nearest_first_and_unknown_roles_have_no_permissions():
    assert lineage("C", PARENTS) == ["C", "B", "A"]
    assert effective("ghost", PARENTS, OWN) == frozenset()


def test_provenance_names_who_grants_each_permission():
    own = {**OWN, "C": frozenset({"z", "x"})}  # C also grants x itself
    result = provenance("C", PARENTS, own)
    assert result == {"z": "C", "x": "C", "y": "B"}


def test_a_cycle_is_detected_and_never_loops():
    loop = {"A": "C", "B": "A", "C": "B"}
    with pytest.raises(RoleCycleError, match="ciclos"):
        lineage("A", loop)
    with pytest.raises(RoleCycleError):
        effective("B", loop, OWN)


def test_would_create_cycle():
    assert would_create_cycle("A", "C", PARENTS)  # A under its own descendant
    assert would_create_cycle("B", "B", PARENTS)  # its own parent
    assert not would_create_cycle("C", "A", PARENTS)  # sideways is fine
    assert not would_create_cycle("A", None, PARENTS)
    assert would_create_cycle("X", "A", {"A": "B", "B": "A"})  # already corrupt


def test_depth_after_counts_the_role_itself():
    assert depth_after("D", None, PARENTS) == 1
    assert depth_after("D", "C", PARENTS) == 4
    assert depth_after("D", "C", PARENTS) <= MAX_DEPTH


# -- ORM roles ---------------------------------------------------------------------------


def role(code, permissions, parent=None, *, active=True):
    return SimpleNamespace(
        code=code,
        is_active=active,
        permissions=[
            SimpleNamespace(code=p, name=p.upper(), is_active=True) for p in permissions
        ],
        parent=parent,
    )


def test_chain_of_walks_the_parents_of_an_orm_role():
    base = role("base", ["a"])
    child = role("child", ["b"], parent=base)
    assert chain_of(child) == (("child", frozenset({"b"})), ("base", frozenset({"a"})))
    assert effective_for_roles([child]) == {"a", "b"}


def test_an_inactive_role_grants_nothing_and_cuts_the_chain():
    base = role("base", ["a"])
    off = role("off", ["m"], parent=base, active=False)
    child = role("child", ["b"], parent=off)
    assert effective_for_roles([child]) == {"b"}
    assert effective_for_roles([off]) == frozenset()


def test_inactive_permissions_are_ignored():
    r = role("r", ["a"])
    r.permissions.append(SimpleNamespace(code="b", name="B", is_active=False))
    assert effective_for_roles([r]) == {"a"}


def test_a_corrupt_cycle_in_orm_objects_grants_nothing_extra():
    a = role("a", ["x"])
    b = role("b", ["y"], parent=a)
    a.parent = b  # corrupt data
    assert effective_for_roles([b]) == {"x", "y"}  # finite, no extra


def test_test_doubles_without_a_parent_attribute_have_no_ancestors():
    plain = SimpleNamespace(
        code="P",
        is_active=True,
        permissions=[SimpleNamespace(code="a", is_active=True)],
    )
    assert effective_for_roles([plain]) == {"a"}


def test_several_roles_add_up():
    assert effective_for_roles([role("a", ["x"]), role("b", ["y"])]) == {"x", "y"}


def test_auth_context_resolves_inherited_permissions():
    base = role("EMPLOYEE", ["tickets:ver"])
    tech = role("TECHNICIAN", ["tickets:cambiar_estado"], parent=base)
    user = SimpleNamespace(id=1, roles=[tech])
    context = AuthContext.from_user(user)
    assert context.permissions == {"tickets:ver", "tickets:cambiar_estado"}
    assert context.has_role("TECHNICIAN")


def test_auth_me_lists_inherited_permissions_with_names():
    base = role("EMPLOYEE", ["tickets:ver"])
    tech = role("TECHNICIAN", ["tickets:editar"], parent=base)
    tech.name = "Técnico"
    user = SimpleNamespace(
        id=1,
        email="a@x.com",
        full_name="Ana",
        employee_code=None,
        is_active=True,
        roles=[tech],
    )
    response = user_response(user)
    assert [p.code for p in response.permissions] == ["tickets:editar", "tickets:ver"]
    assert effective_permission_objects([tech])["tickets:ver"].name == "TICKETS:VER"


# -- the catalogue and the five roles ----------------------------------------------------


def effective_by_role():
    codes = {c: p for c, p in ROLE_PARENTS.items()}
    return {r: effective(r, codes, ROLE_OWN_PERMISSIONS) for r in ROLE_PARENTS}


def test_every_granted_permission_exists_in_the_catalogue():
    for role_code, granted in ROLE_OWN_PERMISSIONS.items():
        assert granted <= CATALOG_SET, (role_code, granted - CATALOG_SET)


def test_the_catalogue_has_labels_and_no_orphans():
    assert len(CATALOG) == len(CATALOG_SET)
    for resource, actions in RESOURCE_ACTIONS.items():
        assert resource in RESOURCE_LABELS
        for action in actions:
            assert action in ACTION_LABELS
            assert permission_name(resource, action).startswith(
                RESOURCE_LABELS[resource]
            )
    assert permission_name("tickets", "ver") == "Tickets: Ver lo propio"
    assert permission_name("equipos", "ver") == "Equipos: Ver"


def test_every_permission_is_granted_to_somebody():
    granted = set().union(*ROLE_OWN_PERMISSIONS.values())
    assert granted == CATALOG_SET


def test_the_chain_is_solicitante_tecnico_supervisor_administrador():
    assert ROLE_PARENTS[TECHNICIAN] == EMPLOYEE
    assert ROLE_PARENTS[SUPERVISOR] == TECHNICIAN
    assert ROLE_PARENTS[ADMIN] == SUPERVISOR
    assert ROLE_PARENTS[EMPLOYEE] is None and ROLE_PARENTS[AUDITOR] is None
    assert set(ROLE_LABELS) == set(ROLE_PARENTS)


def test_each_role_has_everything_its_parent_has_and_more():
    by_role = effective_by_role()
    for child, parent in ROLE_PARENTS.items():
        if parent:
            assert by_role[parent] < by_role[child], (child, parent)


def test_administrator_has_the_whole_catalogue():
    assert effective_by_role()[ADMIN] == CATALOG_SET


def test_the_solicitante_only_creates_and_sees_what_is_theirs():
    mine = effective_by_role()[EMPLOYEE]
    assert {
        "solicitudes:crear",
        "tickets:ver",
        "perfil:editar",
        "dashboard:ver",
    } <= mine
    forbidden = {
        "tickets:ver_asignados",
        "tickets:ver_todos",
        "tickets:cambiar_estado",
        "tickets:asignar",
        "tecnicos:ver",
        "mantenimiento:ver",
        "usuarios:ver",
        "configuracion:ver",
        "auditoria:ver",
        "reportes:ver",
        "equipos:editar",
    }
    assert mine.isdisjoint(forbidden)


def test_the_tecnico_works_assigned_tickets_but_does_not_assign_or_see_all():
    mine = effective_by_role()[TECHNICIAN]
    assert {
        "solicitudes:crear",
        "tickets:ver_asignados",
        "tickets:cambiar_estado",
    } <= mine
    assert {"inventario:consumir", "equipos:ver", "mantenimiento:ver"} <= mine
    assert mine.isdisjoint({"tickets:asignar", "tickets:ver_todos", "inventario:crear"})


def test_only_the_administrator_manages_users_settings_audit_and_bulk_imports():
    by_role = effective_by_role()
    admin_only = {
        "usuarios:asignar",
        "usuarios:crear",
        "configuracion:editar",
        "auditoria:ver",
        "equipos:importar",
        "inventario:importar",
        "inventario:eliminar",
    }
    assert admin_only <= by_role[ADMIN]
    assert by_role[SUPERVISOR].isdisjoint(admin_only)


def test_the_auditor_reads_reports_and_audit_without_operational_rights():
    mine = effective_by_role()[AUDITOR]
    assert {"reportes:ver", "reportes:exportar", "auditoria:ver"} <= mine
    assert mine.isdisjoint(
        {"tickets:ver", "tickets:cambiar_estado", "equipos:ver", "solicitudes:crear"}
    )


# -- data scope --------------------------------------------------------------------------


def test_scope_comes_from_the_widest_permission():
    assert kind_from_permissions("tickets", frozenset({"tickets:ver"})) is ScopeKind.OWN
    assert (
        kind_from_permissions(
            "tickets", frozenset({"tickets:ver", "tickets:ver_asignados"})
        )
        is ScopeKind.ASSIGNED
    )
    assert (
        kind_from_permissions(
            "tickets", frozenset({"tickets:ver_asignados", "tickets:ver_todos"})
        )
        is ScopeKind.ALL
    )
    assert kind_from_permissions("tickets", frozenset({"equipos:ver"})) is None


def test_each_system_role_gets_the_scope_its_name_promises():
    by_role = effective_by_role()
    kinds = {r: kind_from_permissions("tickets", p) for r, p in by_role.items()}
    assert kinds[EMPLOYEE] is ScopeKind.OWN
    assert kinds[TECHNICIAN] is ScopeKind.ASSIGNED
    assert kinds[SUPERVISOR] is ScopeKind.ALL
    assert kinds[ADMIN] is ScopeKind.ALL
    assert kinds[AUDITOR] is None


def context(*permissions, roles=()):
    return AuthContext(
        user=SimpleNamespace(id=7),
        roles=frozenset(roles),
        permissions=frozenset(permissions),
    )


def test_scope_kind_prefers_permissions_over_role_names():
    custom = context("tickets:ver_todos", roles=["MY_CUSTOM_ROLE"])
    assert custom.scope_kind("tickets") is ScopeKind.ALL
    assert context("tickets:ver").scope_kind("tickets") is ScopeKind.OWN


def test_a_context_without_ticket_permissions_sees_nothing():
    assert context(roles=[SUPERVISOR]).scope_kind("tickets") is ScopeKind.NONE
    assert context("equipos:ver").scope_kind("tickets") is ScopeKind.NONE


def ticket(requested_by, technician_id=None, *, active=True):
    assignments = []
    if technician_id is not None:
        assignments.append(
            SimpleNamespace(
                technician_id=technician_id, unassigned_at=None if active else "x"
            )
        )
    return SimpleNamespace(
        requested_by_user_id=requested_by, ticket_assignments=assignments
    )


def test_visibility_follows_the_scope():
    visible = MaintenanceRepository.visible_to
    everything = DataScope.everything()
    own = DataScope(ScopeKind.OWN, user_id=7)
    assigned = DataScope(ScopeKind.ASSIGNED, user_id=7, technician_id=3)
    assert visible(ticket(99), everything)
    assert visible(ticket(7), own) and not visible(ticket(99), own)
    assert not visible(ticket(99, technician_id=3), own)
    assert visible(ticket(99, technician_id=3), assigned)  # assigned to me
    assert visible(ticket(7), assigned)  # requested by me
    assert not visible(ticket(99, technician_id=4), assigned)
    assert not visible(
        ticket(99, technician_id=3, active=False), assigned
    )  # no longer assigned
    assert not visible(ticket(7), DataScope.nothing())


# -- what the migration seeded (needs the migrated database) -----------------------------

needs_db = pytest.mark.skipif(
    not __import__("os").environ.get("MIGRATED_DATABASE_URL"),
    reason="MIGRATED_DATABASE_URL is not set",
)


@pytest.fixture
async def migrated_session():
    import os

    from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

    from app.core.config import Settings

    engine = create_async_engine(
        Settings(database_url=os.environ["MIGRATED_DATABASE_URL"]).database_url
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


@needs_db
async def test_the_seed_matches_the_catalogue_and_roles_inherit_in_the_database(
    migrated_session,
):
    from sqlalchemy import select

    roles = {
        r.code: r for r in (await migrated_session.execute(select(Role))).scalars()
    }
    assert set(ROLE_PARENTS) <= set(roles)
    for code, parent in ROLE_PARENTS.items():
        assert roles[code].is_system
        assert (roles[code].parent.code if roles[code].parent else None) == parent
        assert roles[code].name == ROLE_LABELS[code][0]

    permissions = {
        p.code: p
        for p in (await migrated_session.execute(select(Permission))).scalars()
    }
    assert CATALOG_SET <= set(permissions)
    for code in CATALOG:
        resource, action = code.split(":")
        assert (permissions[code].resource, permissions[code].action) == (
            resource,
            action,
        )
        assert permissions[code].name == permission_name(resource, action)

    for code, expected in effective_by_role().items():
        resolved = {p for p in effective_for_roles([roles[code]]) if ":" in p}
        assert resolved == expected, code


@needs_db
async def test_a_user_with_the_tecnico_role_gets_the_solicitante_permissions(
    migrated_session,
):
    from sqlalchemy import select

    tech_role = (
        await migrated_session.execute(select(Role).where(Role.code == TECHNICIAN))
    ).scalar_one()
    user = User(email="rbac-tech@example.com", full_name="Tec Test", is_active=True)
    migrated_session.add(user)
    await migrated_session.flush()
    migrated_session.add(UserRole(user_id=user.id, role_id=tech_role.id))
    await migrated_session.flush()
    from app.repositories.auth import AuthRepository

    loaded = await AuthRepository(migrated_session).get_user_by_email(user.email)
    assert loaded is not None
    context = AuthContext.from_user(loaded)
    assert "solicitudes:crear" in context.permissions  # inherited from Solicitante
    assert "tickets:cambiar_estado" in context.permissions  # its own
    assert "usuarios:asignar" not in context.permissions


@needs_db
async def test_the_database_refuses_a_role_that_is_its_own_parent(migrated_session):
    from sqlalchemy import select, text
    from sqlalchemy.exc import IntegrityError

    role_id = (
        await migrated_session.execute(select(Role.id).where(Role.code == AUDITOR))
    ).scalar_one()
    with pytest.raises(IntegrityError):
        await migrated_session.execute(
            text("UPDATE roles SET parent_role_id = id WHERE id = :id"), {"id": role_id}
        )


# -- data scope in SQL (disposable database) ---------------------------------------------


async def seed_tickets(session):
    from app.models.equipment import Equipment, EquipmentType
    from app.models.maintenance import MaintenanceRequest, TicketAssignment
    from app.models.priority import Priority
    from app.models.technician import Technician

    session.add(
        Priority(code="low", name="Baja", level=1, sla_hours=100, is_active=True)
    )
    etype = EquipmentType(code="LAP", name="Laptop", is_active=True)
    ana = User(email="ana@x.co", full_name="Ana", is_active=True)
    eva = User(email="eva@x.co", full_name="Eva", is_active=True)
    tec = User(email="tec@x.co", full_name="Tec", is_active=True)
    session.add_all([etype, ana, eva, tec])
    await session.flush()
    laptop = Equipment(
        asset_tag="LT-1",
        equipment_type_id=etype.id,
        brand="Dell",
        model="X",
        status="assigned",
    )
    technician = Technician(user_id=tec.id, is_available=True)
    session.add_all([laptop, technician])
    await session.flush()

    def make(number, requester):
        return MaintenanceRequest(
            ticket_number=number,
            equipment_id=laptop.id,
            requested_by_user_id=requester.id,
            title=number,
            description="d",
            priority="low",
            status="submitted",
        )

    tickets = {
        n: make(n, u)
        for n, u in [("T-ANA", ana), ("T-EVA", eva), ("T-WORK", eva), ("T-OLD", eva)]
    }
    session.add_all(tickets.values())
    await session.flush()
    session.add_all(
        [
            TicketAssignment(
                request_id=tickets["T-WORK"].id, technician_id=technician.id
            ),
            TicketAssignment(
                request_id=tickets["T-OLD"].id,
                technician_id=technician.id,
                assigned_at=NOW_UTC - timedelta(days=2),
                unassigned_at=NOW_UTC - timedelta(days=1),
            ),
        ]
    )
    await session.flush()
    return ana, eva, tec


NOW_UTC = datetime(2026, 10, 15, tzinfo=UTC)


async def numbers(repo, scope):
    page = await repo.list_requests(scope=scope)
    return sorted(r.ticket_number for r in page.items)


async def test_the_repository_applies_the_scope_to_every_listing(db_session):
    ana, eva, _tec = await seed_tickets(db_session)
    repo = MaintenanceRepository(db_session)

    assert await numbers(repo, DataScope.everything()) == [
        "T-ANA",
        "T-EVA",
        "T-OLD",
        "T-WORK",
    ]
    assert await numbers(repo, DataScope(ScopeKind.OWN, user_id=ana.id)) == ["T-ANA"]
    assert await numbers(repo, DataScope(ScopeKind.OWN, user_id=eva.id)) == [
        "T-EVA",
        "T-OLD",
        "T-WORK",
    ]
    assert await numbers(repo, DataScope.nothing()) == []
    assert await numbers(repo, DataScope(ScopeKind.OWN)) == []  # no person, nothing


async def test_a_technician_sees_what_is_assigned_to_them_and_what_they_requested(
    db_session,
):
    ana, _eva, tec = await seed_tickets(db_session)
    repo = MaintenanceRepository(db_session)
    technician = await repo.get_technician_by_user_id(tec.id)
    assert technician is not None

    scope = DataScope(ScopeKind.ASSIGNED, user_id=tec.id, technician_id=technician.id)
    assert await numbers(repo, scope) == ["T-WORK"]  # T-OLD was unassigned
    assert await numbers(repo, DataScope(ScopeKind.ASSIGNED, user_id=ana.id)) == [
        "T-ANA"
    ]


async def test_scope_for_builds_the_scope_from_the_permissions_of_the_person(
    db_session,
):
    _ana, _eva, tec = await seed_tickets(db_session)
    repo = MaintenanceRepository(db_session)

    own = await repo.scope_for(context("tickets:ver"))
    assert own.kind is ScopeKind.OWN
    tech = AuthContext(
        user=SimpleNamespace(id=tec.id),
        roles=frozenset({TECHNICIAN}),
        permissions=frozenset({"tickets:ver", "tickets:ver_asignados"}),
    )
    scope = await repo.scope_for(tech)
    assert scope.kind is ScopeKind.ASSIGNED and scope.technician_id is not None
    assert (await repo.scope_for(context("tickets:ver_todos"))).sees_everything


async def test_a_listing_cannot_be_asked_for_without_a_scope(db_session):
    repo = MaintenanceRepository(db_session)
    with pytest.raises(TypeError):
        await repo.list_requests()  # type: ignore[call-arg]


# -- the idempotent seed script ----------------------------------------------------------


@needs_db
async def test_seed_is_a_no_op_on_a_migrated_database_and_never_undoes_admin_changes(
    migrated_session,
):
    from sqlalchemy import delete, select

    from app.models.auth import RolePermission
    from scripts.seed_rbac import sync

    assert (await sync(migrated_session)).changes == 0

    # An administrator removed a grant from a role: the seed must not bring it back.
    tecnico = (
        await migrated_session.execute(select(Role).where(Role.code == TECHNICIAN))
    ).scalar_one()
    perm = (
        await migrated_session.execute(
            select(Permission).where(Permission.code == "tickets:editar")
        )
    ).scalar_one()
    await migrated_session.execute(
        delete(RolePermission).where(
            RolePermission.role_id == tecnico.id,
            RolePermission.permission_id == perm.id,
        )
    )
    assert (await sync(migrated_session)).changes == 0


@needs_db
async def test_seed_adds_what_a_new_catalogue_entry_needs_and_runs_only_once(
    migrated_session,
):
    from sqlalchemy import delete, select

    from app.models.auth import RolePermission
    from scripts.seed_rbac import sync

    perm = (
        await migrated_session.execute(
            select(Permission).where(Permission.code == "auditoria:ver")
        )
    ).scalar_one()
    await migrated_session.execute(
        delete(RolePermission).where(RolePermission.permission_id == perm.id)
    )
    await migrated_session.delete(perm)
    await migrated_session.flush()

    first = await sync(migrated_session)
    assert first.permissions == ["auditoria:ver"]
    assert sorted(first.grants) == ["ADMIN ← auditoria:ver", "AUDITOR ← auditoria:ver"]
    assert (await sync(migrated_session)).changes == 0


def test_the_published_permission_table_is_up_to_date():
    from scripts.rbac_matrix import OUTPUT, build_markdown

    assert OUTPUT.read_text(encoding="utf-8") == build_markdown(), (
        "docs/rbac-matriz.md is stale: run `python -m scripts.rbac_matrix`"
    )


async def test_assigned_among_returns_only_current_assignments_of_that_technician(
    db_session,
):
    _ana, _eva, tec = await seed_tickets(db_session)
    repo = MaintenanceRepository(db_session)
    technician = await repo.get_technician_by_user_id(tec.id)
    assert technician is not None
    page = await repo.list_requests(scope=DataScope.everything())
    ids = {r.ticket_number: r.id for r in page.items}

    assigned = await repo.assigned_among(technician.id, list(ids.values()))

    assert assigned == {ids["T-WORK"]}  # T-OLD was unassigned
    assert await repo.assigned_among(technician.id, []) == set()
    assert await repo.assigned_among(technician.id + 999, list(ids.values())) == set()


async def test_the_dashboard_counts_only_what_a_requester_asked_for(db_session):
    from app.repositories.dashboard import DashboardRepository

    ana, eva, _tec = await seed_tickets(db_session)
    repo = DashboardRepository(db_session)

    everything = await repo.tickets_by_status()
    mine = await repo.tickets_by_status(requester_id=ana.id)
    eva_open = await repo.tickets_by_priority(requester_id=eva.id)

    assert sum(row.count for row in everything) == 4
    assert [(row.key, row.count) for row in mine] == [("submitted", 1)]
    assert [(row.key, row.count) for row in eva_open] == [("low", 3)]
    assert await repo.count_overdue(NOW_UTC, requester_id=ana.id) == 0
    stats = await repo.resolution_stats(
        date_from=NOW_UTC - timedelta(days=30), requester_id=ana.id
    )
    assert stats[0].resolved_count == 0
