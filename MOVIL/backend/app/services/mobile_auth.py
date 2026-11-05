"""Native email/password authentication for the Mantix mobile app.

This service is deliberately separate from ClerkAuthService. The Angular web
application continues to authenticate with Clerk.
"""
import hashlib
import hmac
import secrets
from datetime import UTC, datetime, timedelta

import jwt
from pwdlib import PasswordHash
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import Settings
from app.core.exceptions import ConflictError, ForbiddenError, AppError
from app.models.auth import AuthEmailCode, Role, User
from app.services.resend_email import ResendEmailService
from app.services.auth import user_response

_passwords = PasswordHash.recommended()
_CODE_MAX_ATTEMPTS = 5


class MobileAuthService:
    def __init__(self, session: AsyncSession, settings: Settings):
        self.session = session
        self.settings = settings
        self.mailer = ResendEmailService(settings)

    @staticmethod
    def _normalize_email(email: str) -> str:
        return email.strip().lower()

    def _secret(self) -> str:
        secret = self.settings.mobile_jwt_secret
        if len(secret.encode("utf-8")) < 32:
            raise AppError("MOBILE_JWT_SECRET debe tener al menos 32 bytes.")
        return secret

    def _code_hash(self, code: str) -> str:
        return hmac.new(self._secret().encode(), code.encode(), hashlib.sha256).hexdigest()

    async def _user_by_email(self, email: str, *, lock: bool = False) -> User | None:
        query = select(User).where(User.email == email)
        if lock:
            query = query.with_for_update()
        result = await self.session.execute(query)
        return result.scalar_one_or_none()

    async def _issue_code(self, user: User, purpose: str) -> None:
        code = f"{secrets.randbelow(1_000_000):06d}"
        now = datetime.now(UTC)
        result = await self.session.execute(
            select(AuthEmailCode).where(
                AuthEmailCode.user_id == user.id,
                AuthEmailCode.purpose == purpose,
            ).with_for_update()
        )
        record = result.scalar_one_or_none()
        expires = now + timedelta(minutes=self.settings.auth_verification_expire_minutes)
        if record is None:
            record = AuthEmailCode(
                user_id=user.id, purpose=purpose, code_hash=self._code_hash(code),
                expires_at=expires, attempts=0, consumed_at=None,
            )
            self.session.add(record)
        else:
            record.code_hash = self._code_hash(code)
            record.expires_at = expires
            record.attempts = 0
            record.consumed_at = None
        await self.session.commit()
        await self.mailer.send_auth_code(
            recipient=user.email, code=code, purpose=purpose,
            expires_minutes=self.settings.auth_verification_expire_minutes,
        )

    async def _consume_code(self, user: User, purpose: str, code: str) -> None:
        result = await self.session.execute(
            select(AuthEmailCode).where(
                AuthEmailCode.user_id == user.id,
                AuthEmailCode.purpose == purpose,
            ).with_for_update()
        )
        record = result.scalar_one_or_none()
        now = datetime.now(UTC)
        if record is None or record.consumed_at is not None or record.expires_at <= now:
            raise ForbiddenError("El código no es válido o ha vencido.", code="auth_code_invalid")
        if record.attempts >= _CODE_MAX_ATTEMPTS:
            raise ForbiddenError("Se superó el número de intentos. Solicita otro código.", code="auth_code_attempts_exceeded")
        if not hmac.compare_digest(record.code_hash, self._code_hash(code)):
            record.attempts += 1
            await self.session.commit()
            raise ForbiddenError("El código no es válido o ha vencido.", code="auth_code_invalid")
        record.consumed_at = now
        await self.session.flush()

    async def register(self, *, email: str, full_name: str, password: str) -> None:
        email = self._normalize_email(email)
        if await self._user_by_email(email) is not None:
            raise ConflictError("Ya existe una cuenta con este correo.", code="user_email_taken")
        user = User(
            email=email, full_name=full_name.strip(),
            password_hash=_passwords.hash(password), is_active=True,
            clerk_user_id=None, email_verified_at=None,
        )
        self.session.add(user)
        try:
            await self.session.flush()
            await self.session.commit()
        except Exception:
            await self.session.rollback()
            raise
        await self._issue_code(user, "verify")

    async def resend_verification(self, email: str) -> None:
        user = await self._user_by_email(self._normalize_email(email))
        if user is None or user.email_verified_at is not None or user.password_hash is None:
            return
        await self._issue_code(user, "verify")

    async def verify_email(self, *, email: str, code: str) -> dict:
        user = await self._user_by_email(self._normalize_email(email), lock=True)
        if user is None or user.password_hash is None:
            raise ForbiddenError("El código no es válido o ha vencido.", code="auth_code_invalid")
        if user.email_verified_at is None:
            await self._consume_code(user, "verify", code)
            user.email_verified_at = datetime.now(UTC)
            await self.session.commit()
        return await self._session_response(user.id)

    async def login(self, *, email: str, password: str) -> dict:
        user = await self._user_by_email(self._normalize_email(email))
        # Same response for unknown email and wrong password.
        if user is None or user.password_hash is None or not _passwords.verify(password, user.password_hash):
            raise ForbiddenError("Correo o contraseña incorrectos.", code="auth_invalid_credentials")
        if user.email_verified_at is None:
            raise ForbiddenError("Verifica tu correo antes de iniciar sesión.", code="auth_email_not_verified")
        if not user.is_active:
            raise ForbiddenError("La cuenta está desactivada.", code="user_inactive")
        return await self._session_response(user.id)

    async def forgot_password(self, email: str) -> None:
        user = await self._user_by_email(self._normalize_email(email))
        if user is not None and user.password_hash is not None and user.email_verified_at is not None:
            await self._issue_code(user, "reset")

    async def reset_password(self, *, email: str, code: str, new_password: str) -> None:
        user = await self._user_by_email(self._normalize_email(email), lock=True)
        if user is None or user.password_hash is None:
            raise ForbiddenError("El código no es válido o ha vencido.", code="auth_code_invalid")
        await self._consume_code(user, "reset", code)
        user.password_hash = _passwords.hash(new_password)
        await self.session.commit()

    async def _session_response(self, user_id: int) -> dict:
        result = await self.session.execute(
            select(User).options(
                selectinload(User.roles).selectinload(Role.permissions)
            ).where(User.id == user_id)
        )
        user = result.scalar_one()
        now = datetime.now(UTC)
        payload = {
            "sub": str(user.id), "iss": "mantix-mobile",
            "iat": now, "exp": now + timedelta(minutes=self.settings.mobile_access_token_minutes),
        }
        encoded = jwt.encode(payload, self._secret(), algorithm="HS256")
        return {"access_token": f"mjwt.{encoded}", "token_type": "bearer", "user": user_response(user).model_dump(mode="json")}

    async def user_from_token(self, token: str) -> User:
        if not token.startswith("mjwt."):
            raise ForbiddenError("Token móvil no válido.", code="unauthorized")
        try:
            payload = jwt.decode(
                token[5:], self._secret(), algorithms=["HS256"],
                issuer="mantix-mobile", options={"require": ["sub", "exp", "iat", "iss"]},
            )
            user_id = int(payload["sub"])
        except (jwt.PyJWTError, ValueError, KeyError) as exc:
            raise ForbiddenError("La sesión ha vencido. Inicia sesión nuevamente.", code="unauthorized") from exc
        result = await self.session.execute(
            select(User).options(
                selectinload(User.roles).selectinload(Role.permissions)
            ).where(User.id == user_id)
        )
        user = result.scalar_one_or_none()
        if user is None or not user.is_active or user.email_verified_at is None:
            raise ForbiddenError("La cuenta no está disponible.", code="unauthorized")
        return user
