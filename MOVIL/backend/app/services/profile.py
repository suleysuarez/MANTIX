"""The signed-in person's profile: data, photo, password and history.

The e-mail is the sign-in identity and is never edited here. The password lives in the sign-in
service, which is asked to check the current one and to store the new one; Mantix keeps neither.
"""

import io
import uuid
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime

from fastapi import UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError

from app.core.authz import AuthContext
from app.core.exceptions import (
    ForbiddenError,
    NotFoundError,
    UnprocessableError,
    UnsupportedMediaTypeError,
)
from app.core.pagination import DEFAULT_PAGE, PageParams
from app.core.storage import FileStorage
from app.core.uploads import read_limited, validate_content
from app.models.audit import AuditLog
from app.models.auth import User
from app.repositories.base import Page
from app.repositories.profile import SECURITY_ACTIONS, ProfileRepository
from app.schemas.auth import RoleResponse
from app.schemas.profile import (
    HistoryEntry,
    PasswordChange,
    ProfileResponse,
    ProfileUpdate,
)
from app.services.audit import AuditService

PasswordVerifier = Callable[[str, str], Awaitable[bool]]
PasswordSetter = Callable[[str, str], Awaitable[None]]

AVATAR_EXTENSIONS = frozenset({".png", ".jpg", ".jpeg"})
AVATAR_MAX_BYTES = 2 * 1024 * 1024
AVATAR_MIN_SIDE = 64
AVATAR_MAX_SIDE = 6000
AVATAR_SIZE = 256


def history_kind(action: str) -> str:
    if action.startswith("auth."):
        return "session"
    if action in SECURITY_ACTIONS:
        return "security"
    if action.startswith("profile."):
        return "profile"
    return "activity"


def to_profile(user: User) -> ProfileResponse:
    roles = sorted(
        (link.role for link in user.user_roles if link.role.is_active),
        key=lambda role: role.code,
    )
    has_avatar = user.avatar_key is not None
    return ProfileResponse(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        phone=user.phone,
        employee_code=user.employee_code,
        roles=[RoleResponse(code=r.code, name=r.name) for r in roles],
        has_avatar=has_avatar,
        avatar_version=int(user.avatar_updated_at.timestamp())
        if has_avatar and user.avatar_updated_at
        else None,
        last_login_at=user.last_login_at,
        created_at=user.created_at,
    )


def process_avatar(content: bytes) -> bytes:
    """Decode the upload as a real image, crop it square and re-encode it as a small JPEG.

    Re-encoding drops metadata (GPS, camera) and anything that is not pixels.
    """
    try:
        with Image.open(io.BytesIO(content)) as probe:
            probe.verify()
        with Image.open(io.BytesIO(content)) as opened:
            width, height = opened.size
            if min(width, height) < AVATAR_MIN_SIDE:
                raise UnprocessableError(
                    f"la foto es muy pequeña: mínimo {AVATAR_MIN_SIDE}×{AVATAR_MIN_SIDE} píxeles"
                )
            if max(width, height) > AVATAR_MAX_SIDE:
                raise UnprocessableError(
                    f"la foto es muy grande: máximo {AVATAR_MAX_SIDE} píxeles por lado"
                )
            image = ImageOps.exif_transpose(opened).convert("RGB")
            square = ImageOps.fit(
                image, (AVATAR_SIZE, AVATAR_SIZE), Image.Resampling.LANCZOS
            )
            out = io.BytesIO()
            square.save(out, format="JPEG", quality=88, optimize=True)
            return out.getvalue()
    except (UnidentifiedImageError, OSError, SyntaxError) as exc:
        raise UnsupportedMediaTypeError("el archivo no es una imagen válida") from exc
    except Image.DecompressionBombError as exc:
        raise UnprocessableError("la imagen es demasiado grande") from exc


class ProfileService:
    def __init__(
        self,
        repository: ProfileRepository,
        audit: AuditService,
        storage: FileStorage,
        verify_password: PasswordVerifier,
        set_password: PasswordSetter,
    ):
        self.repository = repository
        self.audit = audit
        self.storage = storage
        self.verify_password = verify_password
        self.set_password = set_password

    async def get(self, actor: AuthContext) -> ProfileResponse:
        return to_profile(await self._me(actor))

    async def update(
        self, payload: ProfileUpdate, actor: AuthContext
    ) -> ProfileResponse:
        user = await self._me(actor)
        changes = payload.model_dump(exclude_unset=True)
        email = changes.pop("email", None)
        if email is not None and email.strip().lower() != user.email.lower():
            raise ForbiddenError("tu correo no se puede modificar desde el perfil")
        if "full_name" in changes and not changes["full_name"]:
            raise UnprocessableError("el nombre es obligatorio")
        changes = {k: v for k, v in changes.items() if getattr(user, k) != v}
        if changes:
            old = {field: getattr(user, field) for field in changes}
            for field, value in changes.items():
                setattr(user, field, value)
            self.audit.record(
                user_id=user.id,
                action="profile.updated",
                entity_type="user",
                entity_id=user.id,
                old_values=old,
                new_values=changes,
            )
        await self.repository.commit()
        return await self.get(actor)

    # -- photo -------------------------------------------------------------------------

    async def set_avatar(
        self, upload: UploadFile, actor: AuthContext
    ) -> ProfileResponse:
        user = await self._me(actor)
        content = await read_limited(upload, max_bytes=AVATAR_MAX_BYTES)
        validate_content(upload.filename or "", content, AVATAR_EXTENSIONS)
        processed = process_avatar(content)
        previous = user.avatar_key
        key = f"avatars/{user.id}-{uuid.uuid4().hex}.jpg"
        await self.storage.save(key, processed)
        user.avatar_key = key
        user.avatar_media_type = "image/jpeg"
        user.avatar_updated_at = datetime.now(UTC)
        self.audit.record(
            user_id=user.id,
            action="profile.avatar_updated",
            entity_type="user",
            entity_id=user.id,
        )
        await self.repository.commit()
        if previous:
            await self.storage.delete(previous)
        return await self.get(actor)

    async def avatar(self, actor: AuthContext) -> tuple[bytes, str]:
        user = await self._me(actor)
        if not user.avatar_key:
            raise NotFoundError("no tienes foto de perfil")
        return await self.storage.read(user.avatar_key), (
            user.avatar_media_type or "image/jpeg"
        )

    async def remove_avatar(self, actor: AuthContext) -> ProfileResponse:
        user = await self._me(actor)
        previous = user.avatar_key
        if previous:
            user.avatar_key = None
            user.avatar_media_type = None
            user.avatar_updated_at = None
            self.audit.record(
                user_id=user.id,
                action="profile.avatar_removed",
                entity_type="user",
                entity_id=user.id,
            )
            await self.repository.commit()
            await self.storage.delete(previous)
        return await self.get(actor)

    # -- password ----------------------------------------------------------------------

    async def change_password(
        self, payload: PasswordChange, actor: AuthContext
    ) -> None:
        user = await self._me(actor)
        if user.clerk_user_id is None:
            raise UnprocessableError(
                "tu cuenta aún no está vinculada al servicio de acceso"
            )
        if payload.new_password == payload.current_password:
            raise UnprocessableError(
                "la nueva contraseña debe ser distinta de la actual"
            )
        if not await self.verify_password(user.clerk_user_id, payload.current_password):
            raise UnprocessableError("la contraseña actual no es correcta")
        await self.set_password(user.clerk_user_id, payload.new_password)
        self.audit.record(
            user_id=user.id,
            action="profile.password_changed",
            entity_type="user",
            entity_id=user.id,
        )
        await self.repository.commit()

    # -- history -----------------------------------------------------------------------

    async def history(
        self,
        actor: AuthContext,
        *,
        kind: str | None = None,
        date_from: datetime | None = None,
        date_to: datetime | None = None,
        params: PageParams = DEFAULT_PAGE,
    ) -> Page[HistoryEntry]:
        if date_from and date_to and date_to < date_from:
            raise UnprocessableError(
                "el rango de fechas no es válido: la final es anterior a la inicial"
            )
        me = actor.id
        page = await self.repository.history(
            me, kind=kind, date_from=date_from, date_to=date_to, params=params
        )
        return page.map(lambda row: self._entry(row, me))

    @staticmethod
    def _entry(row: AuditLog, me: int) -> HistoryEntry:
        by_other = row.user_id is not None and row.user_id != me
        return HistoryEntry(
            id=row.id,
            action=row.action,
            kind=history_kind(row.action),  # type: ignore[arg-type]
            entity_type=row.entity_type,
            entity_id=row.entity_id,
            actor_name=row.user.full_name if by_other and row.user else None,
            ip_address=row.ip_address,
            created_at=row.created_at,
        )

    async def _me(self, actor: AuthContext) -> User:
        user: User | None = await self.repository.get(actor.id)
        if user is None:
            raise NotFoundError("usuario no encontrado")
        return user
