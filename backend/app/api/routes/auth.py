from fastapi import APIRouter, Depends

from app.api.dependencies import get_authenticated_user
from app.models.auth import User
from app.schemas.auth import UserResponse
from app.services.auth import user_response

router = APIRouter(prefix="/auth", tags=["authentication"])


@router.get("/me", response_model=UserResponse)
async def me(user: User = Depends(get_authenticated_user)) -> UserResponse:  # noqa: B008
    return user_response(user)
