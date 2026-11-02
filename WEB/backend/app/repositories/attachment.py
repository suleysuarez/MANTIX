from sqlalchemy import select

from app.models.attachment import Attachment
from app.repositories.base import BaseRepository


class AttachmentRepository(BaseRepository[Attachment]):
    model = Attachment

    async def list_for_parent(
        self,
        *,
        equipment_id: int | None = None,
        request_id: int | None = None,
        maintenance_record_id: int | None = None,
    ) -> list[Attachment]:
        query = select(Attachment)
        if equipment_id is not None:
            query = query.where(Attachment.equipment_id == equipment_id)
        if request_id is not None:
            query = query.where(Attachment.request_id == request_id)
        if maintenance_record_id is not None:
            query = query.where(
                Attachment.maintenance_record_id == maintenance_record_id
            )
        result = await self.session.execute(
            query.order_by(Attachment.created_at.desc(), Attachment.id.desc())
        )
        return list(result.scalars().all())
