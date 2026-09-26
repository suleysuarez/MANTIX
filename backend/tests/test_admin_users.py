from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.api.dependencies import require_permission
from app.services.admin import AdminUserService


class FakeAdminRepository:
    def __init__(self, users=None, roles=None):
        self.users = users or []
        self.roles = roles or []
        self.committed = False
        self.assignment_count = 0

    async def list_pending_users(self):
        return [user for user in self.users if user.is_active and not user.user_roles]

    async def list_active_roles(self):
        return [role for role in self.roles if role.is_active]

    async def get_active_user(self, user_id):
        return next(
            (user for user in self.users if user.id == user_id and user.is_active),
            None,
        )

    async def get_active_roles_by_ids(self, role_ids):
        return [role for role in self.roles if role.is_active and role.id in role_ids]

    async def add_missing_roles(self, user, roles, assigned_by_user_id):
        existing = {item.role_id for item in user.user_roles}
        for role in roles:
            if role.id not in existing:
                user.user_roles.append(SimpleNamespace(role_id=role.id))
                self.assignment_count += 1

    async def commit(self):
        self.committed = True

    async def reload_user(self, user_id):
        return await self.get_active_user(user_id)


def user(user_id, email, *, active=True, roles=None):
    return SimpleNamespace(
        id=user_id,
        email=email,
        full_name=email.split("@")[0].title(),
        is_active=active,
        user_roles=[SimpleNamespace(role_id=role_id) for role_id in roles or []],
    )


def role(role_id, code="EMPLOYEE", *, active=True):
    return SimpleNamespace(id=role_id, code=code, name=code.title(), is_active=active)


@pytest.mark.asyncio
async def test_pending_list_excludes_inactive_and_assigned_users():
    repository = FakeAdminRepository(
        users=[
            user(1, "pending@example.com"),
            user(2, "assigned@example.com", roles=[10]),
            user(3, "inactive@example.com", active=False),
        ]
    )
    service = AdminUserService(object())
    service.repository = repository

    result = await service.list_pending_users()

    assert [item.id for item in result] == [1]
    assert result[0].email == "pending@example.com"


@pytest.mark.asyncio
async def test_assign_roles_succeeds_and_is_idempotent():
    target = user(10, "pending@example.com")
    repository = FakeAdminRepository(users=[target], roles=[role(20)])
    service = AdminUserService(object())
    service.repository = repository
    admin = user(1, "admin@example.com", roles=[99])

    first = await service.assign_roles(10, [20], admin)
    second = await service.assign_roles(10, [20, 20], admin)

    assert first.role_ids == [20]
    assert second.role_ids == [20]
    assert repository.assignment_count == 1
    assert repository.committed


@pytest.mark.asyncio
async def test_assign_roles_rejects_missing_user_role_and_inactive_user():
    repository = FakeAdminRepository(
        users=[
            user(3, "inactive@example.com", active=False),
            user(4, "active@example.com"),
        ],
        roles=[role(20)],
    )
    service = AdminUserService(object())
    service.repository = repository
    admin = user(1, "admin@example.com")

    with pytest.raises(HTTPException) as missing_user:
        await service.assign_roles(99, [20], admin)
    assert missing_user.value.status_code == 404

    with pytest.raises(HTTPException) as inactive:
        await service.assign_roles(3, [20], admin)
    assert inactive.value.status_code == 404

    with pytest.raises(HTTPException) as missing_role:
        await service.assign_roles(4, [999], admin)
    assert missing_role.value.status_code == 404


def test_permission_boundary_distinguishes_403_from_authenticated_user():
    dependency = require_permission("users.manage")
    denied = SimpleNamespace(roles=[])
    allowed = SimpleNamespace(
        roles=[
            SimpleNamespace(
                is_active=True,
                permissions=[SimpleNamespace(code="users.manage", is_active=True)],
            )
        ]
    )

    with pytest.raises(HTTPException) as error:
        import asyncio

        asyncio.run(dependency(denied))
    assert error.value.status_code == 403
    import asyncio

    assert asyncio.run(dependency(allowed)) is allowed
