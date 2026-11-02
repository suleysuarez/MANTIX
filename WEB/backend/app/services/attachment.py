import uuid
from dataclasses import dataclass

from fastapi import UploadFile

from app.core.authz import AuthContext
from app.core.exceptions import ConflictError, ForbiddenError, NotFoundError
from app.core.storage import FileStorage
from app.core.uploads import (
    extension_of,
    read_limited,
    safe_filename,
    validate_content,
)
from app.models.attachment import Attachment
from app.repositories.attachment import AttachmentRepository
from app.repositories.equipment import EquipmentRepository
from app.schemas.attachment import AttachmentResponse
from app.services.audit import AuditService
from app.services.maintenance import MaintenanceService

ALLOWED_EXTENSIONS = frozenset({".pdf", ".png", ".jpg", ".jpeg", ".txt"})
MAX_ATTACHMENTS_PER_PARENT = 20


@dataclass(frozen=True, slots=True)
class DownloadedFile:
    content: bytes
    file_name: str
    mime_type: str


class AttachmentService:
    """Attach files to tickets and equipment.

    * Tickets: whoever may *view* the ticket (requester, assigned technician,
      admin/supervisor) may attach files and read them.
    * Equipment: attaching needs `equipment.manage`; reading needs `equipment.read`
      (enforced by the route).
    * Deleting: the uploader, or an admin/supervisor.
    """

    def __init__(
        self,
        repository: AttachmentRepository,
        storage: FileStorage,
        maintenance: MaintenanceService,
        equipment: EquipmentRepository,
        audit: AuditService,
        *,
        max_bytes: int,
    ):
        self.repository = repository
        self.storage = storage
        self.maintenance = maintenance
        self.equipment = equipment
        self.audit = audit
        self.max_bytes = max_bytes

    # -- Tickets ---------------------------------------------------------------

    async def add_to_request(
        self, request_id: int, upload: UploadFile, actor: AuthContext
    ) -> AttachmentResponse:
        await self.maintenance.ensure_can_view(request_id, actor)
        return await self._store(upload, actor, request_id=request_id)

    async def list_for_request(
        self, request_id: int, actor: AuthContext
    ) -> list[AttachmentResponse]:
        await self.maintenance.ensure_can_view(request_id, actor)
        items = await self.repository.list_for_parent(request_id=request_id)
        return [AttachmentResponse.model_validate(item) for item in items]

    # -- Equipment ----------------------------------------------------------------

    async def add_to_equipment(
        self, equipment_id: int, upload: UploadFile, actor: AuthContext
    ) -> AttachmentResponse:
        if not actor.has_permission("equipos:adjuntar"):
            raise ForbiddenError("attaching files to equipment needs equipment.manage")
        await self._require_equipment(equipment_id)
        return await self._store(upload, actor, equipment_id=equipment_id)

    async def list_for_equipment(self, equipment_id: int) -> list[AttachmentResponse]:
        await self._require_equipment(equipment_id)
        items = await self.repository.list_for_parent(equipment_id=equipment_id)
        return [AttachmentResponse.model_validate(item) for item in items]

    # -- Download / delete -----------------------------------------------------------

    async def download(self, attachment_id: int, actor: AuthContext) -> DownloadedFile:
        attachment = await self._authorised(attachment_id, actor, reading=True)
        content = await self.storage.read(attachment.file_path)
        return DownloadedFile(content, attachment.file_name, attachment.mime_type)

    async def delete(self, attachment_id: int, actor: AuthContext) -> None:
        attachment = await self._authorised(attachment_id, actor, reading=False)
        sees_all = actor.has_permission("tickets:ver_todos") or actor.has_permission(
            "equipos:editar"
        )
        if not sees_all and attachment.uploaded_by_user_id != actor.id:
            raise ForbiddenError(
                "Solo quien subió el archivo o un supervisor puede eliminarlo."
            )
        key = attachment.file_path
        await self.repository.delete(attachment)
        self.audit.record(
            user_id=actor.id,
            action="attachment.deleted",
            entity_type="attachment",
            entity_id=attachment_id,
            old_values={"file_name": attachment.file_name},
        )
        await self.repository.commit()
        await self.storage.delete(
            key
        )  # after commit: a leftover file beats a dangling row

    # -- Internals -----------------------------------------------------------------------

    async def _require_equipment(self, equipment_id: int) -> None:
        if await self.equipment.get(equipment_id) is None:
            raise NotFoundError("equipment not found")

    async def _authorised(
        self, attachment_id: int, actor: AuthContext, *, reading: bool
    ) -> Attachment:
        attachment = await self.repository.get(attachment_id)
        if attachment is None:
            raise NotFoundError("attachment not found")
        if attachment.request_id is not None:
            await self.maintenance.ensure_can_view(attachment.request_id, actor)
        elif attachment.equipment_id is not None:
            needed = "equipos:ver" if reading else "equipos:adjuntar"
            if not actor.has_permission(needed):
                raise ForbiddenError("No tienes acceso a este archivo.")
        return attachment

    async def _store(
        self,
        upload: UploadFile,
        actor: AuthContext,
        *,
        request_id: int | None = None,
        equipment_id: int | None = None,
    ) -> AttachmentResponse:
        count = len(
            await self.repository.list_for_parent(
                request_id=request_id, equipment_id=equipment_id
            )
        )
        if count >= MAX_ATTACHMENTS_PER_PARENT:
            raise ConflictError(
                f"at most {MAX_ATTACHMENTS_PER_PARENT} attachments are allowed"
            )

        file_name = safe_filename(upload.filename)
        content = await read_limited(upload, max_bytes=self.max_bytes)
        mime_type = validate_content(file_name, content, ALLOWED_EXTENSIONS)

        parent = f"requests/{request_id}" if request_id else f"equipment/{equipment_id}"
        key = f"{parent}/{uuid.uuid4().hex}{extension_of(file_name)}"
        await self.storage.save(key, content)
        try:
            attachment = await self.repository.add_and_flush(
                Attachment(
                    request_id=request_id,
                    equipment_id=equipment_id,
                    file_name=file_name,
                    file_path=key,
                    file_size=len(content),
                    mime_type=mime_type,
                    uploaded_by_user_id=actor.id,
                )
            )
            self.audit.record(
                user_id=actor.id,
                action="attachment.uploaded",
                entity_type="attachment",
                entity_id=attachment.id,
                new_values={
                    "file_name": file_name,
                    "size": len(content),
                    "request_id": request_id,
                    "equipment_id": equipment_id,
                },
            )
            await self.repository.commit()
        except Exception:
            await self.repository.rollback()
            await self.storage.delete(key)
            raise
        return AttachmentResponse.model_validate(attachment)
