from datetime import UTC, datetime
from types import SimpleNamespace

import pytest

from app.core.exceptions import NotFoundError
from app.services.notification_inbox import NotificationInboxService


def make(id_, user_id, is_read=False):
    return SimpleNamespace(
        id=id_,
        user_id=user_id,
        title=f"t{id_}",
        message="m",
        notification_type="role_assigned",
        is_read=is_read,
        read_at=None,
        link_url=None,
        created_at=datetime(2026, 1, 1, tzinfo=UTC),
    )


class FakeRepository:
    def __init__(self, items):
        self.items = items
        self.committed = 0

    async def list_for_user(self, user_id, *, unread_only, limit, offset):
        rows = [i for i in self.items if i.user_id == user_id]
        if unread_only:
            rows = [i for i in rows if not i.is_read]
        return rows[offset : offset + limit]

    async def count_unread(self, user_id):
        return sum(1 for i in self.items if i.user_id == user_id and not i.is_read)

    async def get_for_user(self, notification_id, user_id):
        return next(
            (i for i in self.items if i.id == notification_id and i.user_id == user_id),
            None,
        )

    async def mark_read(self, notification):
        notification.is_read = True
        notification.read_at = datetime(2026, 1, 2, tzinfo=UTC)
        return notification

    async def mark_all_read(self, user_id):
        for i in self.items:
            if i.user_id == user_id:
                i.is_read = True

    async def commit(self):
        self.committed += 1


ME = SimpleNamespace(id=1)


@pytest.mark.asyncio
async def test_list_only_returns_own_notifications_with_unread_count():
    service = NotificationInboxService(
        FakeRepository([make(1, 1), make(2, 1, is_read=True), make(3, 2)])
    )

    result = await service.list(ME, unread_only=False, limit=50, offset=0)

    assert [n.id for n in result.items] == [1, 2]
    assert result.unread_count == 1


@pytest.mark.asyncio
async def test_unread_only_filters_read_items():
    service = NotificationInboxService(FakeRepository([make(1, 1), make(2, 1, True)]))

    result = await service.list(ME, unread_only=True, limit=50, offset=0)

    assert [n.id for n in result.items] == [1]


@pytest.mark.asyncio
async def test_mark_read_updates_and_commits():
    repo = FakeRepository([make(1, 1)])

    result = await NotificationInboxService(repo).mark_read(ME, 1)

    assert result.is_read is True
    assert repo.committed == 1


@pytest.mark.asyncio
async def test_cannot_mark_another_users_notification():
    repo = FakeRepository([make(3, 2)])

    with pytest.raises(NotFoundError):
        await NotificationInboxService(repo).mark_read(ME, 3)

    assert repo.items[0].is_read is False


@pytest.mark.asyncio
async def test_mark_all_read_only_touches_own_rows():
    repo = FakeRepository([make(1, 1), make(2, 2)])

    await NotificationInboxService(repo).mark_all_read(ME)

    assert [i.is_read for i in repo.items] == [True, False]
