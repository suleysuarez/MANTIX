from urllib.parse import quote

from fastapi import APIRouter, Depends, File, Response, UploadFile, status

from app.api.dependencies import require_authenticated, require_permission
from app.api.providers import get_attachment_service
from app.core.authz import AuthContext
from app.core.errors import error_responses
from app.schemas.attachment import AttachmentResponse
from app.services.attachment import ALLOWED_EXTENSIONS, AttachmentService

router = APIRouter(tags=["attachments"])

_UPLOAD_NOTE = (
    "Allowed types: " + ", ".join(sorted(ALLOWED_EXTENSIONS)) + ". The size limit is "
    "set by `MAX_UPLOAD_MB` (default 10 MB) and the content must match the extension."
)


@router.post(
    "/maintenance/requests/{request_id}/attachments",
    response_model=AttachmentResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Attach a file to a ticket",
    description="Allowed for anyone who can view the ticket. " + _UPLOAD_NOTE,
    responses=error_responses(404, 409, 413, 415),
)
async def upload_request_attachment(
    request_id: int,
    file: UploadFile = File(description="The file to attach"),  # noqa: B008
    actor: AuthContext = Depends(require_permission("tickets:adjuntar")),  # noqa: B008
    service: AttachmentService = Depends(get_attachment_service),  # noqa: B008
) -> AttachmentResponse:
    return await service.add_to_request(request_id, file, actor)


@router.get(
    "/maintenance/requests/{request_id}/attachments",
    response_model=list[AttachmentResponse],
    summary="List a ticket's attachments",
    responses=error_responses(404),
)
async def list_request_attachments(
    request_id: int,
    actor: AuthContext = Depends(require_permission("tickets:ver")),  # noqa: B008
    service: AttachmentService = Depends(get_attachment_service),  # noqa: B008
) -> list[AttachmentResponse]:
    return await service.list_for_request(request_id, actor)


@router.post(
    "/equipment/{equipment_id}/attachments",
    response_model=AttachmentResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Attach a file to equipment",
    description="Requires `equipment.manage`. " + _UPLOAD_NOTE,
    responses=error_responses(404, 409, 413, 415),
)
async def upload_equipment_attachment(
    equipment_id: int,
    file: UploadFile = File(description="The file to attach"),  # noqa: B008
    actor: AuthContext = Depends(require_permission("equipos:adjuntar")),  # noqa: B008
    service: AttachmentService = Depends(get_attachment_service),  # noqa: B008
) -> AttachmentResponse:
    return await service.add_to_equipment(equipment_id, file, actor)


@router.get(
    "/equipment/{equipment_id}/attachments",
    response_model=list[AttachmentResponse],
    summary="List an equipment item's attachments",
    responses=error_responses(404),
)
async def list_equipment_attachments(
    equipment_id: int,
    _: AuthContext = Depends(require_permission("equipos:ver")),  # noqa: B008
    service: AttachmentService = Depends(get_attachment_service),  # noqa: B008
) -> list[AttachmentResponse]:
    return await service.list_for_equipment(equipment_id)


@router.get(
    "/attachments/{attachment_id}/download",
    summary="Download an attachment",
    description="Access follows the parent: ticket visibility or equipment access.",
    responses={
        200: {"description": "The file", "content": {"application/octet-stream": {}}},
        **error_responses(403, 404),
    },
    response_class=Response,
)
async def download_attachment(
    attachment_id: int,
    actor: AuthContext = Depends(require_authenticated()),  # noqa: B008
    service: AttachmentService = Depends(get_attachment_service),  # noqa: B008
) -> Response:
    file = await service.download(attachment_id, actor)
    disposition = f"attachment; filename*=UTF-8''{quote(file.file_name)}"
    return Response(
        content=file.content,
        media_type=file.mime_type,
        headers={
            "Content-Disposition": disposition,
            "X-Content-Type-Options": "nosniff",
            "Cache-Control": "private, no-store",
        },
    )


@router.delete(
    "/attachments/{attachment_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete an attachment",
    description="The uploader or an admin/supervisor.",
    responses=error_responses(403, 404),
)
async def delete_attachment(
    attachment_id: int,
    actor: AuthContext = Depends(require_authenticated()),  # noqa: B008
    service: AttachmentService = Depends(get_attachment_service),  # noqa: B008
) -> None:
    await service.delete(attachment_id, actor)
