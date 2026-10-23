"""Administration of roles and of what each one grants (Phase 4).

Every rule that keeps the hierarchy sane lives here: unique names, no cycles, a bounded depth,
system roles that cannot be removed, nobody editing the role they hold, and nobody granting a
permission they do not have. Every change leaves an audit entry with what was before and after.
"""

import re
import unicodedata

from app.core.authz import ADMIN, AuthContext
from app.core.exceptions import ConflictError, ForbiddenError, NotFoundError
from app.core.rbac import (
    MAX_DEPTH,
    depth_after,
    lineage,
    provenance,
    would_create_cycle,
)
from app.models.auth import Permission, Role
from app.repositories.admin import AdminRepository
from app.schemas.admin import (
    EffectivePermission,
    RoleAdminResponse,
    RoleCreateRequest,
    RolePermissionsRequest,
    RoleUpdateRequest,
)
from app.services.audit import AuditService


def _code_from(name: str) -> str:
    ascii_name = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    code = re.sub(r"[^A-Z0-9]+", "_", ascii_name.upper()).strip("_")
    return (code or "ROL")[:44]


def _own(role: Role) -> frozenset[str]:
    """The `recurso:accion` permissions the role grants itself (legacy dotted ones excluded)."""
    return frozenset(
        permission.code
        for permission in role.permissions
        if permission.is_active and permission.action is not None
    )


class RoleAdminService:
    def __init__(self, repository: AdminRepository, audit: AuditService):
        self.repository = repository
        self.audit = audit

    # -- reading -------------------------------------------------------------------------

    async def list_roles(self) -> list[RoleAdminResponse]:
        roles = await self.repository.list_all_roles()
        counts = await self.repository.user_counts()
        return self._views(roles, counts)

    async def _view(self, role_id: int) -> RoleAdminResponse:
        for view in await self.list_roles():
            if view.id == role_id:
                return view
        raise NotFoundError("Rol no encontrado.")

    @staticmethod
    def _views(roles: list[Role], counts: dict[int, int]) -> list[RoleAdminResponse]:
        by_id = {role.id: role for role in roles}
        by_code = {role.code: role for role in roles}
        parents = {
            role.code: by_id[role.parent_role_id].code
            if role.parent_role_id in by_id
            else None
            for role in roles
        }
        own = {role.code: _own(role) for role in roles}
        children: dict[int, int] = {}
        for role in roles:
            if role.parent_role_id is not None:
                children[role.parent_role_id] = children.get(role.parent_role_id, 0) + 1
        views = []
        for role in roles:
            origin = provenance(role.code, parents, own)
            views.append(
                RoleAdminResponse(
                    id=role.id,
                    code=role.code,
                    name=role.name,
                    description=role.description,
                    is_active=role.is_active,
                    is_system=role.is_system,
                    parent_role_id=role.parent_role_id,
                    parent_name=(
                        by_id[role.parent_role_id].name
                        if role.parent_role_id in by_id
                        else None
                    ),
                    depth=len(lineage(role.code, parents)),
                    user_count=counts.get(role.id, 0),
                    children_count=children.get(role.id, 0),
                    own_permissions=sorted(own[role.code]),
                    effective=[
                        EffectivePermission(
                            code=code,
                            source_role_id=by_code[source].id,
                            source_role_name=by_code[source].name,
                            inherited=source != role.code,
                        )
                        for code, source in sorted(origin.items())
                    ],
                )
            )
        return views

    # -- writing -------------------------------------------------------------------------

    async def create_role(
        self, payload: RoleCreateRequest, actor: AuthContext
    ) -> RoleAdminResponse:
        actor.require("usuarios:asignar", "Solo un administrador puede crear roles.")
        name = payload.name.strip()
        if len(name) < 3:
            raise ConflictError("El nombre del rol debe tener al menos 3 caracteres.")
        await self._ensure_name_free(name)
        roles = await self.repository.list_all_roles()
        parents = self._parents(roles)
        parent = self._parent_for(payload.parent_role_id, roles)
        code = await self._free_code(name)
        if parent is not None and depth_after(code, parent.code, parents) > MAX_DEPTH:
            raise ConflictError(
                f"La jerarquía admite como máximo {MAX_DEPTH} niveles de herencia."
            )
        permissions = await self._permissions(payload.permissions)
        self._ensure_actor_holds(actor, {p.code for p in permissions})
        if parent is not None:
            self._ensure_actor_holds_role(actor, parent)

        role = await self.repository.add_role(
            Role(
                code=code,
                name=name,
                description=(payload.description or "").strip() or None,
                parent_role_id=parent.id if parent else None,
                is_active=True,
                is_system=False,
            )
        )
        await self.repository.set_catalogue_permissions(role, permissions)
        self.audit.record(
            user_id=actor.id,
            action="roles.created",
            entity_type="role",
            entity_id=role.id,
            new_values={
                "code": code,
                "name": name,
                "parent": parent.code if parent else None,
                "permissions": sorted(p.code for p in permissions),
            },
        )
        await self.repository.commit()
        return await self._view(role.id)

    async def update_role(
        self, role_id: int, payload: RoleUpdateRequest, actor: AuthContext
    ) -> RoleAdminResponse:
        actor.require("usuarios:asignar", "Solo un administrador puede editar roles.")
        role = await self._get(role_id)
        sent = payload.model_fields_set
        roles = await self.repository.list_all_roles()
        before: dict[str, object] = {}
        after: dict[str, object] = {}

        if "name" in sent and payload.name is not None:
            name = payload.name.strip()
            if len(name) < 3:
                raise ConflictError(
                    "El nombre del rol debe tener al menos 3 caracteres."
                )
            if name != role.name:
                await self._ensure_name_free(name, exclude_id=role.id)
                before["name"], after["name"] = role.name, name
                role.name = name

        if "description" in sent:
            description = (payload.description or "").strip() or None
            if description != role.description:
                before["description"], after["description"] = (
                    role.description,
                    description,
                )
                role.description = description

        if "parent_role_id" in sent and payload.parent_role_id != role.parent_role_id:
            if role.is_system:
                raise ConflictError(
                    "La jerarquía de los roles base no se puede cambiar."
                )
            parent = self._parent_for(payload.parent_role_id, roles)
            parents = self._parents(roles)
            if parent is not None:
                if would_create_cycle(role.code, parent.code, parents):
                    raise ConflictError(
                        "Ese padre crearía un ciclo: un rol no puede heredar de sí mismo "
                        "ni de uno de sus descendientes."
                    )
                self._ensure_actor_holds_role(actor, parent)
            parents[role.code] = parent.code if parent else None
            deepest = max(len(lineage(code, parents)) for code in parents)
            if deepest > MAX_DEPTH:
                raise ConflictError(
                    f"La jerarquía admite como máximo {MAX_DEPTH} niveles de herencia."
                )
            old_parent = next((r for r in roles if r.id == role.parent_role_id), None)
            before["parent"] = old_parent.code if old_parent else None
            after["parent"] = parent.code if parent else None
            role.parent_role_id = parent.id if parent else None

        wants_active = payload.is_active
        if (
            "is_active" in sent
            and wants_active is not None
            and wants_active != role.is_active
        ):
            if not wants_active:
                await self._ensure_can_deactivate(role, roles)
            before["is_active"], after["is_active"] = role.is_active, wants_active
            role.is_active = wants_active

        if after:
            await self.repository.flush()
            self.audit.record(
                user_id=actor.id,
                action="roles.updated",
                entity_type="role",
                entity_id=role.id,
                old_values={"code": role.code, **before},
                new_values=after,
            )
            await self.repository.commit()
        return await self._view(role.id)

    async def set_permissions(
        self, role_id: int, payload: RolePermissionsRequest, actor: AuthContext
    ) -> RoleAdminResponse:
        actor.require(
            "usuarios:asignar", "Solo un administrador puede cambiar permisos."
        )
        role = await self._get(role_id)
        if role.code == ADMIN:
            raise ConflictError(
                "El rol Administrador siempre tiene todos los permisos y no se edita."
            )
        if role.code in actor.roles:
            raise ForbiddenError(
                "No puedes cambiar los permisos de un rol que tú tienes."
            )
        wanted = await self._permissions(payload.permissions)
        wanted_codes = frozenset(p.code for p in wanted)
        current = _own(role)
        added, removed = wanted_codes - current, current - wanted_codes
        self._ensure_actor_holds(actor, added)
        if added or removed:
            await self.repository.set_catalogue_permissions(role, wanted)
            self.audit.record(
                user_id=actor.id,
                action="roles.permissions_changed",
                entity_type="role",
                entity_id=role.id,
                old_values={"code": role.code, "removed": sorted(removed)},
                new_values={"added": sorted(added)},
            )
            await self.repository.commit()
        return await self._view(role.id)

    async def delete_role(self, role_id: int, actor: AuthContext) -> None:
        actor.require("usuarios:asignar", "Solo un administrador puede eliminar roles.")
        role = await self._get(role_id)
        if role.is_system:
            raise ConflictError("Los roles base no se pueden eliminar.")
        roles = await self.repository.list_all_roles()
        if any(other.parent_role_id == role.id for other in roles):
            raise ConflictError(
                "Este rol es padre de otros. Cambia primero el padre de esos roles."
            )
        if await self.repository.role_has_users(role.id):
            raise ConflictError(
                "Este rol tiene usuarios asignados. Reasígnalos antes de eliminarlo."
            )
        snapshot = {
            "code": role.code,
            "name": role.name,
            "parent": next(
                (r.code for r in roles if r.id == role.parent_role_id), None
            ),
            "permissions": sorted(_own(role)),
        }
        await self.repository.set_catalogue_permissions(role, [])
        await self.repository.delete_role(role)
        self.audit.record(
            user_id=actor.id,
            action="roles.deleted",
            entity_type="role",
            entity_id=role_id,
            old_values=snapshot,
        )
        await self.repository.commit()

    # -- helpers -------------------------------------------------------------------------

    async def _get(self, role_id: int) -> Role:
        role = await self.repository.get_role(role_id)
        if role is None:
            raise NotFoundError("Rol no encontrado.")
        return role

    @staticmethod
    def _parents(roles: list[Role]) -> dict[str, str | None]:
        by_id = {role.id: role for role in roles}
        return {
            role.code: by_id[role.parent_role_id].code
            if role.parent_role_id in by_id
            else None
            for role in roles
        }

    @staticmethod
    def _parent_for(parent_id: int | None, roles: list[Role]) -> Role | None:
        if parent_id is None:
            return None
        parent = next((role for role in roles if role.id == parent_id), None)
        if parent is None or not parent.is_active:
            raise NotFoundError("El rol padre no existe o está inactivo.")
        return parent

    async def _ensure_name_free(
        self, name: str, *, exclude_id: int | None = None
    ) -> None:
        if await self.repository.role_name_taken(name, exclude_id=exclude_id):
            raise ConflictError(f"Ya existe un rol llamado «{name}».")

    async def _free_code(self, name: str) -> str:
        base = _code_from(name)
        code, n = base, 2
        while await self.repository.role_code_taken(code):
            code, n = f"{base}_{n}", n + 1
        return code

    async def _permissions(self, codes: list[str]) -> list[Permission]:
        unique = list(dict.fromkeys(codes))
        found = await self.repository.catalogue_permissions(unique)
        missing = sorted(set(unique) - {p.code for p in found})
        if missing:
            raise NotFoundError("Permisos desconocidos: " + ", ".join(missing))
        return found

    @staticmethod
    def _ensure_actor_holds(
        actor: AuthContext, codes: set[str] | frozenset[str]
    ) -> None:
        lacking = sorted(set(codes) - actor.permissions)
        if lacking:
            raise ForbiddenError(
                "No puedes conceder permisos que tú no tienes: " + ", ".join(lacking)
            )

    @staticmethod
    def _ensure_actor_holds_role(actor: AuthContext, role: Role) -> None:
        from app.core.rbac import effective_for_roles

        RoleAdminService._ensure_actor_holds(actor, effective_for_roles([role]))

    async def _ensure_can_deactivate(self, role: Role, roles: list[Role]) -> None:
        if role.is_system:
            raise ConflictError("Los roles base no se pueden desactivar.")
        if await self.repository.role_has_users(role.id):
            raise ConflictError(
                "Este rol tiene usuarios asignados. Reasígnalos antes de desactivarlo."
            )
        if any(r.parent_role_id == role.id and r.is_active for r in roles):
            raise ConflictError("Este rol es padre de roles activos.")
