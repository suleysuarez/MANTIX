"""Bring the RBAC rows in line with `app/core/permissions.py` (idempotent; never removes anything).

    python -m scripts.seed_rbac             # show what is missing
    python -m scripts.seed_rbac --apply     # insert it (one transaction)

Adds the permissions, roles, parents and per-role grants of the catalogue that are not in the
database yet. It never deletes, renames or edits: what an administrator changed (a grant
removed from a role, a custom role, a different parent) stays as it is, and running it twice
does nothing the second time. The migration seeds the same data on a fresh database; this is
for catalogue changes made later.
"""

import argparse
import asyncio
from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.permissions import (
    CATALOG,
    ROLE_LABELS,
    ROLE_OWN_PERMISSIONS,
    ROLE_PARENTS,
    permission_name,
)
from app.db import session as db
from app.models.auth import Permission, Role, RolePermission


@dataclass
class SeedReport:
    permissions: list[str] = field(default_factory=list)
    roles: list[str] = field(default_factory=list)
    parents: list[str] = field(default_factory=list)
    grants: list[str] = field(default_factory=list)

    @property
    def changes(self) -> int:
        return (
            len(self.permissions)
            + len(self.roles)
            + len(self.parents)
            + len(self.grants)
        )


async def sync(session: AsyncSession) -> SeedReport:
    """Insert what is missing and report it. The caller commits."""
    report = SeedReport()

    known = {p.code: p for p in (await session.execute(select(Permission))).scalars()}
    for code in CATALOG:
        if code not in known:
            resource, action = code.split(":")
            permission = Permission(
                code=code,
                name=permission_name(resource, action),
                module=resource,
                resource=resource,
                action=action,
                is_active=True,
            )
            session.add(permission)
            known[code] = permission
            report.permissions.append(code)

    roles = {r.code: r for r in (await session.execute(select(Role))).scalars()}
    for code, (name, description) in ROLE_LABELS.items():
        if code not in roles:
            role = Role(
                code=code,
                name=name,
                description=description,
                is_active=True,
                is_system=True,
            )
            session.add(role)
            roles[code] = role
            report.roles.append(code)
    await session.flush()

    for code, parent in ROLE_PARENTS.items():
        role = roles[code]
        if parent is not None and role.parent_role_id is None:
            role.parent_role_id = roles[parent].id
            report.parents.append(f"{code} → {parent}")

    granted = {
        (link.role_id, link.permission_id)
        for link in (await session.execute(select(RolePermission))).scalars()
    }
    # Grants only for roles and permissions created now: a grant an administrator removed from
    # an existing role must not come back on its own.
    for code, permissions in ROLE_OWN_PERMISSIONS.items():
        role = roles[code]
        brand_new_role = code in report.roles
        for permission_code in sorted(permissions):
            permission = known[permission_code]
            is_new = permission_code in report.permissions
            if (brand_new_role or is_new) and (role.id, permission.id) not in granted:
                session.add(
                    RolePermission(role_id=role.id, permission_id=permission.id)
                )
                report.grants.append(f"{code} ← {permission_code}")
    await session.flush()
    return report


async def main(apply: bool) -> None:
    async with db.AsyncSessionLocal() as session:
        report = await sync(session)
        if apply:
            await session.commit()
        else:
            await session.rollback()
    mode = "aplicado" if apply else "pendiente (usa --apply)"
    print(f"Cambios {mode}: {report.changes}")
    for title, items in (
        ("Permisos", report.permissions),
        ("Roles", report.roles),
        ("Herencia", report.parents),
        ("Asignaciones", report.grants),
    ):
        if items:
            print(f"  {title}: {len(items)}")
            for item in items:
                print(f"    {item}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--apply", action="store_true", help="write the changes")
    asyncio.run(main(parser.parse_args().apply))
