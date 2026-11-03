import io
from datetime import UTC, datetime
from types import SimpleNamespace

import pytest
from fastapi import UploadFile
from PIL import Image
from pydantic import ValidationError

from app.core.authz import AuthContext
from app.core.exceptions import (
    ForbiddenError,
    NotFoundError,
    PayloadTooLargeError,
    UnprocessableError,
    UnsupportedMediaTypeError,
)
from app.schemas.profile import (
    PasswordChange,
    ProfileUpdate,
)
from app.services.profile import ProfileService, history_kind, process_avatar

ROLE = SimpleNamespace(code="EMPLOYEE", name="Empleado", is_active=True)


class FakeAudit:
    def __init__(self):
        self.records = []

    def record(self, **kwargs):
        self.records.append(kwargs)


class FakeStorage:
    def __init__(self):
        self.files = {}

    async def save(self, key, content):
        self.files[key] = content

    async def read(self, key):
        return self.files[key]

    async def delete(self, key):
        self.files.pop(key, None)


def make_user(**over):
    data = {
        "id": 7,
        "email": "ana@x.com",
        "clerk_user_id": "clerk_7",
        "full_name": "Ana Pérez",
        "phone": None,
        "employee_code": "E-7",
        "avatar_key": None,
        "avatar_media_type": None,
        "avatar_updated_at": None,
        "last_login_at": None,
        "created_at": datetime(2026, 1, 1, tzinfo=UTC),
        "user_roles": [SimpleNamespace(role=ROLE)],
    }
    return SimpleNamespace(**{**data, **over})


class FakeRepository:
    def __init__(self, user):
        self.user = user
        self.commits = 0

    async def get(self, user_id):
        return self.user if self.user and self.user.id == user_id else None

    async def commit(self):
        self.commits += 1


def build(user=None, *, password_ok=True):
    user = user or make_user()
    storage, audit = FakeStorage(), FakeAudit()
    calls = SimpleNamespace(set=[], verified=[])

    async def verify(clerk_id, password):
        calls.verified.append((clerk_id, password))
        return password_ok

    async def setter(clerk_id, password):
        calls.set.append((clerk_id, password))

    service = ProfileService(FakeRepository(user), audit, storage, verify, setter)
    return service, user, audit, storage, calls


def actor(user_id=7):
    return AuthContext(
        user=SimpleNamespace(id=user_id), roles=frozenset(), permissions=frozenset()
    )


def image_bytes(size=(300, 200), fmt="PNG", color=(10, 120, 200)):
    out = io.BytesIO()
    Image.new("RGB", size, color).save(out, format=fmt)
    return out.getvalue()


def upload(content, filename="foto.png"):
    return UploadFile(file=io.BytesIO(content), filename=filename)


# -- schemas -----------------------------------------------------------------------------


def test_profile_update_normalises_and_validates():
    ok = ProfileUpdate(full_name="  Ana   María  ", phone="+57 300 123 4567")
    assert ok.full_name == "Ana María"
    for bad in ({"full_name": "A"}, {"phone": "abc"}, {"full_name": "x" * 121}):
        with pytest.raises(ValidationError):
            ProfileUpdate(**bad)
    with pytest.raises(ValidationError):
        ProfileUpdate(employee_code="E-1")  # not editable by the person


@pytest.mark.parametrize(
    "password", ["Corta1A", "sinnumeroABCDEF", "SINMINUSCULA1234", "con espacio 1Aa"]
)
def test_new_password_policy(password):
    with pytest.raises(ValidationError):
        PasswordChange(current_password="Actual-2026", new_password=password)


# -- data --------------------------------------------------------------------------------


async def test_profile_shows_the_roles_and_no_photo_yet():
    service, *_ = build()
    profile = await service.get(actor())
    assert profile.email == "ana@x.com"
    assert [r.code for r in profile.roles] == ["EMPLOYEE"]
    assert profile.has_avatar is False and profile.avatar_version is None


async def test_update_changes_name_and_phone_and_audits_only_what_changed():
    service, user, audit, *_ = build()
    await service.update(
        ProfileUpdate(full_name="Ana María Pérez", phone="+57 300 123 4567"), actor()
    )
    assert user.full_name == "Ana María Pérez" and user.phone == "+57 300 123 4567"
    record = audit.records[-1]
    assert record["action"] == "profile.updated"
    assert record["old_values"] == {"full_name": "Ana Pérez", "phone": None}
    await service.update(ProfileUpdate(full_name="Ana María Pérez"), actor())
    assert len(audit.records) == 1  # nothing changed, nothing audited


async def test_the_email_cannot_be_changed_but_resending_it_is_harmless():
    service, user, audit, *_ = build()
    with pytest.raises(ForbiddenError):
        await service.update(ProfileUpdate(email="otra@x.com"), actor())
    assert user.email == "ana@x.com" and audit.records == []
    await service.update(ProfileUpdate(email="ANA@x.com", full_name="Ana P"), actor())
    assert user.email == "ana@x.com" and user.full_name == "Ana P"


async def test_unknown_person_is_not_found():
    service, *_ = build()
    with pytest.raises(NotFoundError):
        await service.get(actor(user_id=999))


# -- photo -------------------------------------------------------------------------------


async def test_photo_is_cropped_square_reencoded_and_replaces_the_old_one():
    service, user, audit, storage, _ = build()
    first = await service.set_avatar(upload(image_bytes((400, 200))), actor())
    assert first.has_avatar and first.avatar_version
    old_key = user.avatar_key
    stored = Image.open(io.BytesIO(storage.files[old_key]))
    assert stored.size == (256, 256) and stored.format == "JPEG"

    await service.set_avatar(upload(image_bytes((100, 100), "JPEG"), "yo.jpg"), actor())
    assert old_key not in storage.files and len(storage.files) == 1
    assert [r["action"] for r in audit.records] == ["profile.avatar_updated"] * 2


async def test_photo_is_served_and_removed():
    service, user, audit, storage, _ = build()
    with pytest.raises(NotFoundError):
        await service.avatar(actor())
    await service.set_avatar(upload(image_bytes()), actor())
    content, media_type = await service.avatar(actor())
    assert media_type == "image/jpeg" and content[:3] == b"\xff\xd8\xff"
    after = await service.remove_avatar(actor())
    assert after.has_avatar is False and storage.files == {} and user.avatar_key is None
    assert audit.records[-1]["action"] == "profile.avatar_removed"


async def test_photo_validation():
    service, *_ = build()
    with pytest.raises(UnsupportedMediaTypeError):  # extension not allowed
        await service.set_avatar(upload(image_bytes(), "foto.gif"), actor())
    with pytest.raises(UnsupportedMediaTypeError):  # .png that is not a PNG
        await service.set_avatar(upload(b"%PDF-1.4 not an image", "foto.png"), actor())
    with pytest.raises(UnsupportedMediaTypeError):  # right magic bytes, broken body
        await service.set_avatar(
            upload(b"\x89PNG\r\n\x1a\n" + b"junk" * 20, "foto.png"), actor()
        )
    with pytest.raises(UnprocessableError, match="pequeña"):
        await service.set_avatar(upload(image_bytes((32, 32))), actor())
    with pytest.raises(PayloadTooLargeError):
        await service.set_avatar(
            upload(b"\x89PNG\r\n\x1a\n" + b"0" * (2 * 1024 * 1024 + 1)), actor()
        )


def test_process_avatar_strips_metadata():
    image = Image.new("RGB", (120, 120), (1, 2, 3))
    exif = Image.Exif()
    exif[0x010F] = "SecretCamera"
    out = io.BytesIO()
    image.save(out, format="JPEG", exif=exif)
    assert b"SecretCamera" in out.getvalue()
    assert b"SecretCamera" not in process_avatar(out.getvalue())


# -- password ----------------------------------------------------------------------------


async def test_password_change_checks_the_current_one_and_never_logs_either():
    service, _, audit, _, calls = build()
    await service.change_password(
        PasswordChange(
            current_password="Actual-2026", new_password="Nueva-2026-Segura"
        ),
        actor(),
    )
    assert calls.verified == [("clerk_7", "Actual-2026")]
    assert calls.set == [("clerk_7", "Nueva-2026-Segura")]
    assert audit.records[-1]["action"] == "profile.password_changed"
    assert "Nueva-2026" not in repr(audit.records) and "Actual-2026" not in repr(
        audit.records
    )


async def test_password_change_refuses_a_wrong_current_password_without_changing_anything():
    service, _, audit, _, calls = build(password_ok=False)
    with pytest.raises(UnprocessableError, match="actual no es correcta"):
        await service.change_password(
            PasswordChange(
                current_password="Mala-2026-abc", new_password="Nueva-2026-Segura"
            ),
            actor(),
        )
    assert calls.set == [] and audit.records == []


async def test_password_change_refuses_the_same_password_or_an_unlinked_account():
    service, *_ = build()
    with pytest.raises(UnprocessableError, match="distinta"):
        await service.change_password(
            PasswordChange(
                current_password="Misma-2026-Abc", new_password="Misma-2026-Abc"
            ),
            actor(),
        )
    unlinked, *_ = build(make_user(clerk_user_id=None))
    with pytest.raises(UnprocessableError, match="vinculada"):
        await unlinked.change_password(
            PasswordChange(
                current_password="Actual-2026", new_password="Nueva-2026-Segura"
            ),
            actor(),
        )


# -- history -----------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("action", "kind"),
    [
        ("auth.login", "session"),
        ("profile.updated", "profile"),
        ("profile.avatar_updated", "profile"),
        ("profile.password_changed", "security"),
        ("user.password_reset", "security"),
        ("roles.replaced", "security"),
        ("maintenance.status_changed", "activity"),
    ],
)
def test_history_kinds(action, kind):
    assert history_kind(action) == kind


async def test_history_rejects_an_inverted_range():
    service, *_ = build()
    with pytest.raises(UnprocessableError):
        await service.history(
            actor(),
            date_from=datetime(2026, 5, 10, tzinfo=UTC),
            date_to=datetime(2026, 5, 1, tzinfo=UTC),
        )


def test_history_entry_names_somebody_else_but_not_you():
    row = SimpleNamespace(
        id=1,
        action="roles.replaced",
        entity_type="user",
        entity_id=7,
        user_id=2,
        user=SimpleNamespace(full_name="Admin Uno"),
        ip_address=None,
        created_at=datetime(2026, 1, 1, tzinfo=UTC),
    )
    assert ProfileService._entry(row, 7).actor_name == "Admin Uno"
    mine = SimpleNamespace(
        **{**row.__dict__, "user_id": 7, "user": SimpleNamespace(full_name="Yo")}
    )
    assert ProfileService._entry(mine, 7).actor_name is None
