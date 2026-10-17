"""Roles administration: hierarchy, grants and the rules that protect them (Phase 4)."""

import pytest
from sqlalchemy import select

from app.core.authz import ADMIN, EMPLOYEE, SUPERVISOR, TECHNICIAN, AuthContext
from app.core.exceptions import ConflictError, ForbiddenError, NotFoundError
from app.core.rbac import MAX_DEPTH
from app.models.audit import AuditLog
from app.models.auth import User, UserRole
from app.repositories.admin import AdminRepository
from app.repositories.audit import AuditRepository
from app.schemas.admin import (
    RoleCreateRequest,
    RolePermissionsRequest,
    RoleUpdateRequest,
)
from app.services.audit import AuditService
from app.services.role_admin import RoleAdminService
from scripts.seed_rbac import sync


@pytest.fixture
async def world(db_session):
    await sync(db_session)
    admin = User(email="admin@x.co", full_name="Admin", is_active=True)
    other = User(email="other@x.co", full_name="Other", is_active=True)
    db_session.add_all([admin, other])
    await db_session.commit()
    repository = AdminRepository(db_session)
    service = RoleAdminService(repository, AuditService(AuditRepository(db_session)))
    roles = {r.code: r for r in await repository.list_all_roles()}
    return service, AuthContext.for_roles(admin, ADMIN), roles, db_session, other


async def audit_actions(session):
    rows = await session.execute(select(AuditLog).order_by(AuditLog.id))
    return [(row.action, row.new_values, row.old_values) for row in rows.scalars()]


async def test_the_roles_screen_shows_hierarchy_and_where_each_permission_comes_from(
    world,
):
    service, _, roles, *_ = world
    views = {v.code: v for v in await service.list_roles()}

    assert [
        v.depth
        for v in (views[EMPLOYEE], views[TECHNICIAN], views[SUPERVISOR], views[ADMIN])
    ] == [1, 2, 3, 4]
    assert views[TECHNICIAN].parent_name == views[EMPLOYEE].name
    technician = {p.code: p for p in views[TECHNICIAN].effective}
    assert technician["tickets:ver"].inherited is True
    assert technician["tickets:ver"].source_role_id == roles[EMPLOYEE].id
    assert all(p.inherited is False for p in views[EMPLOYEE].effective)
    assert views[ADMIN].children_count == 0 and views[EMPLOYEE].children_count == 1


async def test_a_custom_role_is_created_with_a_parent_and_its_own_grants(world):
    service, admin, roles, session, _ = world
    created = await service.create_role(
        RoleCreateRequest(
            name="Jefe de Almacén",
            description="Controla el inventario",
            parent_role_id=roles[EMPLOYEE].id,
            permissions=["inventario:ver", "inventario:editar"],
        ),
        admin,
    )
    assert created.code == "JEFE_DE_ALMACEN" and created.is_system is False
    assert created.own_permissions == ["inventario:editar", "inventario:ver"]
    inherited = [p for p in created.effective if p.inherited]
    assert inherited and all(p.source_role_id == roles[EMPLOYEE].id for p in inherited)
    action, new, _ = (await audit_actions(session))[-1]
    assert action == "roles.created" and new["parent"] == EMPLOYEE


async def test_names_are_unique_ignoring_case_and_codes_never_collide(world):
    service, admin, *_ = world
    await service.create_role(RoleCreateRequest(name="Compras"), admin)
    with pytest.raises(ConflictError, match="Ya existe"):
        await service.create_role(RoleCreateRequest(name="compras"), admin)
    with pytest.raises(ConflictError, match="Ya existe"):
        await service.create_role(RoleCreateRequest(name="TÉCNICO"), admin)
    twin = await service.create_role(RoleCreateRequest(name="Compras!"), admin)
    assert twin.code == "COMPRAS_2"


async def test_unknown_legacy_or_missing_parents_are_refused(world):
    service, admin, *_ = world
    with pytest.raises(NotFoundError, match="desconocidos"):
        await service.create_role(
            RoleCreateRequest(name="Raro", permissions=["equipment.read"]), admin
        )
    with pytest.raises(NotFoundError, match="padre"):
        await service.create_role(
            RoleCreateRequest(name="Huérfano", parent_role_id=99999), admin
        )


async def test_a_cycle_is_refused(world):
    service, admin, _roles, *_ = world
    a = await service.create_role(RoleCreateRequest(name="Rol A"), admin)
    b = await service.create_role(
        RoleCreateRequest(name="Rol B", parent_role_id=a.id), admin
    )
    with pytest.raises(ConflictError, match="ciclo"):
        await service.update_role(a.id, RoleUpdateRequest(parent_role_id=b.id), admin)
    with pytest.raises(ConflictError, match="ciclo"):
        await service.update_role(a.id, RoleUpdateRequest(parent_role_id=a.id), admin)


async def test_the_chain_cannot_grow_past_the_limit(world):
    service, admin, roles, *_ = world
    parent = roles[TECHNICIAN].id  # depth 2
    for n in range(MAX_DEPTH - 2):
        parent = (
            await service.create_role(
                RoleCreateRequest(name=f"Nivel {n}", parent_role_id=parent), admin
            )
        ).id
    with pytest.raises(ConflictError, match="niveles"):
        await service.create_role(
            RoleCreateRequest(name="Demasiado profundo", parent_role_id=parent), admin
        )


async def test_moving_a_role_changes_what_it_inherits_and_is_audited(world):
    service, admin, roles, session, _ = world
    role = await service.create_role(
        RoleCreateRequest(name="Móvil", parent_role_id=roles[EMPLOYEE].id), admin
    )
    before = {p.code for p in role.effective}
    moved = await service.update_role(
        role.id, RoleUpdateRequest(parent_role_id=roles[SUPERVISOR].id), admin
    )
    assert {p.code for p in moved.effective} > before
    root = await service.update_role(
        role.id, RoleUpdateRequest(parent_role_id=None), admin
    )
    assert root.parent_role_id is None and root.effective == []
    updates = [a for a in await audit_actions(session) if a[0] == "roles.updated"]
    assert updates[0][2]["parent"] == EMPLOYEE and updates[0][1]["parent"] == SUPERVISOR


async def test_system_roles_keep_their_place_and_cannot_go(world):
    service, admin, roles, *_ = world
    tech = roles[TECHNICIAN]
    with pytest.raises(ConflictError, match="base"):
        await service.update_role(
            tech.id, RoleUpdateRequest(parent_role_id=None), admin
        )
    with pytest.raises(ConflictError, match="base"):
        await service.update_role(tech.id, RoleUpdateRequest(is_active=False), admin)
    with pytest.raises(ConflictError, match="base"):
        await service.delete_role(tech.id, admin)


async def test_the_permissions_of_a_role_are_replaced_and_the_diff_is_audited(world):
    service, admin, _roles, session, _ = world
    role = await service.create_role(
        RoleCreateRequest(name="Analista", permissions=["reportes:ver", "tickets:ver"]),
        admin,
    )
    updated = await service.set_permissions(
        role.id,
        RolePermissionsRequest(permissions=["tickets:ver", "tickets:exportar"]),
        admin,
    )
    assert updated.own_permissions == ["tickets:exportar", "tickets:ver"]
    action, new, old = (await audit_actions(session))[-1]
    assert action == "roles.permissions_changed"
    assert new == {"added": ["tickets:exportar"]} and old["removed"] == ["reportes:ver"]


async def test_saving_the_same_permissions_writes_no_audit_entry(world):
    service, admin, _roles, session, _ = world
    role = await service.create_role(
        RoleCreateRequest(name="Igual", permissions=["tickets:ver"]), admin
    )
    count = len(await audit_actions(session))
    await service.set_permissions(
        role.id, RolePermissionsRequest(permissions=["tickets:ver"]), admin
    )
    assert len(await audit_actions(session)) == count


async def test_changing_a_base_role_never_touches_inheritance_of_others(world):
    service, admin, roles, *_ = world
    updated = await service.set_permissions(
        roles[EMPLOYEE].id,
        RolePermissionsRequest(
            permissions=[
                p
                for p in (await service.list_roles())[0].own_permissions
                if p != "perfil:ver"
            ]
        ),
        admin,
    )
    assert "perfil:ver" not in updated.own_permissions
    views = {v.code: v for v in await service.list_roles()}
    assert "perfil:ver" not in {p.code for p in views[TECHNICIAN].effective}


async def test_administrator_is_untouchable_and_nobody_edits_a_role_they_hold(world):
    service, admin, roles, *_ = world
    with pytest.raises(ConflictError, match="Administrador"):
        await service.set_permissions(
            roles[ADMIN].id, RolePermissionsRequest(permissions=[]), admin
        )
    holder = AuthContext.for_roles(admin.user, ADMIN, SUPERVISOR)
    with pytest.raises(ForbiddenError, match="que tú tienes"):
        await service.set_permissions(
            roles[SUPERVISOR].id, RolePermissionsRequest(permissions=[]), holder
        )


async def test_nobody_grants_what_they_do_not_have(world):
    service, admin, _roles, *_ = world
    role = await service.create_role(RoleCreateRequest(name="Destino"), admin)
    limited = AuthContext.for_roles(admin.user, ADMIN)
    object.__setattr__(
        limited, "permissions", frozenset({"usuarios:asignar", "tickets:ver"})
    )
    with pytest.raises(ForbiddenError, match="no tienes"):
        await service.set_permissions(
            role.id, RolePermissionsRequest(permissions=["usuarios:crear"]), limited
        )
    with pytest.raises(ForbiddenError, match="no tienes"):
        await service.create_role(
            RoleCreateRequest(name="Otro", permissions=["usuarios:crear"]), limited
        )


async def test_only_whoever_may_assign_roles_manages_them(world):
    service, _, roles, _session, other = world
    nobody = AuthContext.for_roles(other, SUPERVISOR)
    with pytest.raises(ForbiddenError):
        await service.create_role(RoleCreateRequest(name="Intruso"), nobody)
    with pytest.raises(ForbiddenError):
        await service.delete_role(roles[EMPLOYEE].id, nobody)


async def test_a_role_with_users_or_children_is_neither_deleted_nor_deactivated(world):
    service, admin, _roles, session, other = world
    parent = await service.create_role(RoleCreateRequest(name="Padre"), admin)
    child = await service.create_role(
        RoleCreateRequest(name="Hijo", parent_role_id=parent.id), admin
    )
    with pytest.raises(ConflictError, match="padre"):
        await service.delete_role(parent.id, admin)
    with pytest.raises(ConflictError, match="padre"):
        await service.update_role(parent.id, RoleUpdateRequest(is_active=False), admin)

    session.add(UserRole(user_id=other.id, role_id=child.id))
    await session.commit()
    with pytest.raises(ConflictError, match="usuarios asignados"):
        await service.delete_role(child.id, admin)
    with pytest.raises(ConflictError, match="usuarios asignados"):
        await service.update_role(child.id, RoleUpdateRequest(is_active=False), admin)
    assert (
        next(v for v in await service.list_roles() if v.id == child.id).user_count == 1
    )


async def test_an_unused_custom_role_is_deactivated_reactivated_and_deleted_with_audit(
    world,
):
    service, admin, _roles, session, _ = world
    role = await service.create_role(
        RoleCreateRequest(name="Temporal", permissions=["tickets:ver"]), admin
    )
    off = await service.update_role(role.id, RoleUpdateRequest(is_active=False), admin)
    assert off.is_active is False
    assert (
        await service.update_role(role.id, RoleUpdateRequest(is_active=True), admin)
    ).is_active is True
    await service.delete_role(role.id, admin)
    assert all(v.id != role.id for v in await service.list_roles())
    action, _, old = (await audit_actions(session))[-1]
    assert action == "roles.deleted" and old["permissions"] == ["tickets:ver"]
    with pytest.raises(NotFoundError):
        await service.delete_role(role.id, admin)


async def test_renaming_checks_the_name_and_is_audited(world):
    service, admin, _roles, session, _ = world
    role = await service.create_role(RoleCreateRequest(name="Antes"), admin)
    renamed = await service.update_role(
        role.id, RoleUpdateRequest(name="Después", description="Nuevo"), admin
    )
    assert (renamed.name, renamed.description, renamed.code) == (
        "Después",
        "Nuevo",
        "ANTES",
    )
    with pytest.raises(ConflictError, match="Ya existe"):
        await service.update_role(role.id, RoleUpdateRequest(name="supervisor"), admin)
    action, new, old = (await audit_actions(session))[-1]
    assert (
        action == "roles.updated"
        and old["name"] == "Antes"
        and new["name"] == "Después"
    )
