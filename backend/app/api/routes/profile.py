from datetime import datetime

from fastapi import APIRouter, Depends, File, Query, Response, UploadFile, status

from app.api.dependencies import get_auth_context
from app.api.pagination import page_params, set_page_headers
from app.api.providers import get_profile_service
from app.core.authz import AuthContext
from app.core.errors import error_responses
from app.core.pagination import PageParams
from app.schemas.profile import (
    HistoryEntry,
    HistoryKind,
    PasswordChange,
    ProfileResponse,
    ProfileUpdate,
)
from app.services.profile import ProfileService

router = APIRouter(prefix="/profile", tags=["profile"])

# Every route acts on the signed-in person only: there is no id in any path, so nobody can
# reach another person's profile through here.


@router.get(
    "",
    response_model=ProfileResponse,
    summary="My profile",
    responses=error_responses(401),
)
async def get_profile(
    actor: AuthContext = Depends(get_auth_context),  # noqa: B008
    service: ProfileService = Depends(get_profile_service),  # noqa: B008
) -> ProfileResponse:
    return await service.get(actor)


@router.patch(
    "",
    response_model=ProfileResponse,
    summary="Edit my personal data",
    description=(
        "Name and phone. The e-mail is the sign-in identity and cannot be changed here: "
        "sending a different one is a 403."
    ),
    responses=error_responses(403, 422),
)
async def update_profile(
    payload: ProfileUpdate,
    actor: AuthContext = Depends(get_auth_context),  # noqa: B008
    service: ProfileService = Depends(get_profile_service),  # noqa: B008
) -> ProfileResponse:
    return await service.update(payload, actor)


@router.put(
    "/avatar",
    response_model=ProfileResponse,
    summary="Upload my photo",
    description=(
        "PNG or JPEG up to 2 MB, at least 64×64 px. The server checks that it is a real "
        "image, crops it square and stores a 256×256 JPEG without metadata."
    ),
    responses=error_responses(413, 415, 422),
)
async def upload_avatar(
    file: UploadFile = File(...),  # noqa: B008
    actor: AuthContext = Depends(get_auth_context),  # noqa: B008
    service: ProfileService = Depends(get_profile_service),  # noqa: B008
) -> ProfileResponse:
    return await service.set_avatar(file, actor)


@router.get(
    "/avatar",
    summary="My photo",
    response_class=Response,
    responses={200: {"content": {"image/jpeg": {}}}, **error_responses(404)},
)
async def download_avatar(
    actor: AuthContext = Depends(get_auth_context),  # noqa: B008
    service: ProfileService = Depends(get_profile_service),  # noqa: B008
) -> Response:
    content, media_type = await service.avatar(actor)
    return Response(
        content=content,
        media_type=media_type,
        headers={
            "Cache-Control": "private, max-age=3600",
            "X-Content-Type-Options": "nosniff",
        },
    )


@router.delete(
    "/avatar",
    response_model=ProfileResponse,
    summary="Remove my photo",
)
async def remove_avatar(
    actor: AuthContext = Depends(get_auth_context),  # noqa: B008
    service: ProfileService = Depends(get_profile_service),  # noqa: B008
) -> ProfileResponse:
    return await service.remove_avatar(actor)


@router.post(
    "/password",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Change my password",
    description=(
        "Needs the current password. The sign-in service checks and stores it; Mantix "
        "never keeps it. Your other devices stay signed in until you close them."
    ),
    responses=error_responses(422),
)
async def change_password(
    payload: PasswordChange,
    actor: AuthContext = Depends(get_auth_context),  # noqa: B008
    service: ProfileService = Depends(get_profile_service),  # noqa: B008
) -> Response:
    await service.change_password(payload, actor)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get(
    "/history",
    response_model=list[HistoryEntry],
    summary="My history",
    description=(
        "What you did and what others did to your account, newest first. `kind`: "
        "`session` (sign-ins), `profile` (your data), `security` (password, roles, "
        "activation) or `activity` (everything else)."
    ),
    responses=error_responses(422),
)
async def history(
    response: Response,
    kind: HistoryKind | None = Query(default=None),  # noqa: B008
    date_from: datetime | None = Query(default=None),  # noqa: B008
    date_to: datetime | None = Query(default=None),  # noqa: B008
    params: PageParams = Depends(page_params(default_size=15)),  # noqa: B008
    actor: AuthContext = Depends(get_auth_context),  # noqa: B008
    service: ProfileService = Depends(get_profile_service),  # noqa: B008
) -> list[HistoryEntry]:
    page = await service.history(
        actor, kind=kind, date_from=date_from, date_to=date_to, params=params
    )
    set_page_headers(response, page)
    return page.items
