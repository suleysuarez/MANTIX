from datetime import datetime

from fastapi import APIRouter, Depends, Query, Response

from app.api.dependencies import require_permission
from app.api.pagination import page_params, set_page_headers
from app.api.providers import get_audit_service
from app.core.authz import AuthContext
from app.core.pagination import PageParams
from app.schemas.audit import AuditLogResponse
from app.services.audit import AuditService

router = APIRouter(prefix="/audit-logs", tags=["audit"])


@router.get(
    "",
    response_model=list[AuditLogResponse],
    summary="Query the audit trail",
    description=(
        "Who changed what and when, newest first, with the previous and new "
        "values. Combine `entity_type` + `entity_id` for one record's history. "
        "Sort fields: `created_at`, `action`, `entity_type`."
    ),
)
async def list_audit_logs(
    response: Response,
    user_id: int | None = Query(default=None, description="Acting user"),
    action: str | None = Query(default=None, examples=["equipment.updated"]),
    entity_type: str | None = Query(default=None, examples=["maintenance_request"]),
    entity_id: int | None = Query(default=None),
    date_from: datetime | None = Query(default=None),  # noqa: B008
    date_to: datetime | None = Query(default=None),  # noqa: B008
    params: PageParams = Depends(page_params()),  # noqa: B008
    _: AuthContext = Depends(require_permission("audit.read")),  # noqa: B008
    service: AuditService = Depends(get_audit_service),  # noqa: B008
) -> list[AuditLogResponse]:
    page = await service.search(
        user_id=user_id,
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        date_from=date_from,
        date_to=date_to,
        params=params,
    )
    set_page_headers(response, page)
    return page.items
