from fastapi import APIRouter, Depends

from app.api.dependencies import require_session
from app.models.auth import User
from app.schemas.auth import UserResponse
from app.services.auth import user_response

router = APIRouter(prefix="/auth", tags=["authentication"])


@router.get("/me", response_model=UserResponse)
async def me(user: User = Depends(require_session())) -> UserResponse:  # noqa: B008
    return user_response(user)
