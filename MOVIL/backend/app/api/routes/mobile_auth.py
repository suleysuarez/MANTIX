from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.schemas.mobile_auth import (
    MobileAuthResponse, MobileForgotPasswordRequest, MobileLoginRequest,
    MobileRegisterRequest, MobileResendCodeRequest, MobileResetPasswordRequest,
    MobileVerifyEmailRequest,
)
from app.services.mobile_auth import MobileAuthService

router = APIRouter(prefix="/mobile-auth", tags=["mobile-authentication"])

def get_mobile_auth_service(
    session: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> MobileAuthService:
    return MobileAuthService(session, settings)

Service = Annotated[MobileAuthService, Depends(get_mobile_auth_service)]

@router.post("/register", status_code=status.HTTP_202_ACCEPTED)
async def register(body: MobileRegisterRequest, service: Service) -> dict[str, str]:
    await service.register(email=body.email, full_name=body.full_name, password=body.password)
    return {"message": "Te enviamos un código para verificar tu correo."}

@router.post("/verify-email", response_model=MobileAuthResponse)
async def verify_email(body: MobileVerifyEmailRequest, service: Service) -> dict:
    return await service.verify_email(email=body.email, code=body.code)

@router.post("/resend-verification", status_code=status.HTTP_202_ACCEPTED)
async def resend_verification(body: MobileResendCodeRequest, service: Service) -> dict[str, str]:
    await service.resend_verification(body.email)
    return {"message": "Si la cuenta necesita verificación, enviaremos un código."}

@router.post("/login", response_model=MobileAuthResponse)
async def login(body: MobileLoginRequest, service: Service) -> dict:
    return await service.login(email=body.email, password=body.password)

@router.post("/forgot-password", status_code=status.HTTP_202_ACCEPTED)
async def forgot_password(body: MobileForgotPasswordRequest, service: Service) -> dict[str, str]:
    await service.forgot_password(body.email)
    return {"message": "Si existe una cuenta elegible, enviaremos instrucciones."}

@router.post("/reset-password", status_code=status.HTTP_204_NO_CONTENT)
async def reset_password(body: MobileResetPasswordRequest, service: Service) -> None:
    await service.reset_password(email=body.email, code=body.code, new_password=body.new_password)
