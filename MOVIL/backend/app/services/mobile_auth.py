"""Native email/password authentication for the Mantix mobile app.

This service is deliberately separate from ClerkAuthService. The Angular web
application continues to authenticate with Clerk.
"""
import functools
import hashlib
import hmac
import logging
import secrets
from datetime import UTC, datetime, timedelta

import jwt
from fastapi import HTTPException, status
from pwdlib import PasswordHash
from sqlalchemy import select, text, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import Settings
from app.core.exceptions import AppError, ConflictError, ForbiddenError
from app.models.auth import AuthEmailCode, Role, User, UserRole
from app.services.auth import user_response
from app.services.code_email_limiter import CodeEmailLimiter, code_email_limiter
from app.services.email_sender import (
    EmailConfigurationError,
    EmailSender,
    SmtpEmailSender,
    mask_email,
    render_auth_code_email,
)

logger = logging.getLogger("mantix.mail")
_passwords = PasswordHash.recommended()
_CODE_MAX_ATTEMPTS = 5


@functools.cache
def _timing_decoy_hash() -> str:
    """A real hash to verify against when the account does not exist (same cost)."""
    return _passwords.hash(secrets.token_urlsafe(16))


class MobileAuthService:
    def __init__(
        self,
        session: AsyncSession,
        settings: Settings,
        sender: EmailSender | None = None,
        limiter: CodeEmailLimiter | None = None,
    ):
        self.session = session
        self.settings = settings
        self.sender: EmailSender = sender or SmtpEmailSender(settings)
        self.limiter = limiter or code_email_limiter

    @staticmethod
    def _normalize_email(email: str) -> str:
        return email.strip().lower()

    def _secret(self) -> str:
        secret = self.settings.mobile_jwt_secret
        if len(secret.encode("utf-8")) < 32:
            raise AppError("MOBILE_JWT_SECRET debe tener al menos 32 bytes.")
        return secret

    def _code_key(self) -> bytes:
        # Derived, so a code hash never uses the raw key that signs the access tokens.
        return hmac.new(self._secret().encode(), b"mantix-auth-code-v1", hashlib.sha256).digest()

    def _code_hash(self, code: str) -> str:
        return hmac.new(self._code_key(), code.encode(), hashlib.sha256).hexdigest()

    async def _invalidate_code(self, user: User, purpose: str) -> None:
        """Make the current code of this purpose unusable (it stays until a new one is issued)."""
        result = await self.session.execute(
            select(AuthEmailCode).where(
                AuthEmailCode.user_id == user.id,
                AuthEmailCode.purpose == purpose,
            ).with_for_update()
        )
        record = result.scalar_one_or_none()
        if record is not None and record.consumed_at is None:
            record.consumed_at = datetime.now(UTC)

    async def _user_by_email(self, email: str, *, lock: bool = False) -> User | None:
        query = select(User).where(User.email == email)
        if lock:
            query = query.with_for_update()
        result = await self.session.execute(query)
        return result.scalar_one_or_none()

    async def _assign_bootstrap_admin(self, user: User) -> bool:
        """Grant ADMIN once, to the first account claiming an application role."""
        # Match the legacy bootstrap rule while serializing concurrent sign-ups.
        await self.session.execute(text("SELECT pg_advisory_xact_lock(85219401)"))
        assigned = await self.session.execute(select(UserRole.id).limit(1))
        if assigned.scalar_one_or_none() is not None:
            return False

        result = await self.session.execute(
            select(Role).where(Role.code == "ADMIN", Role.is_active.is_(True))
        )
        admin_role = result.scalar_one_or_none()
        if admin_role is None:
            raise AppError("bootstrap ADMIN role is not configured")
        self.session.add(UserRole(user_id=user.id, role_id=admin_role.id))
        await self.session.flush()
        return True

    async def _issue_code(self, user: User, purpose: str) -> None:
        # Checked first: a blocked request leaves the current code and its attempt
        # counter untouched, so asking again cannot be used to reset the attempts.
        if not self.limiter.allow(user.email):
            logger.warning(
                "auth code email skipped by the send limit (account=%s purpose=%s)",
                mask_email(user.email), purpose,
            )
            return
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
        await self._send_code(user.email, code, purpose)

    async def _send_code(self, email: str, code: str, purpose: str) -> None:
        """Deliver a code. A failed delivery is logged and never changes the API answer."""
        subject, text, html = render_auth_code_email(
            code=code, purpose=purpose,
            expires_minutes=self.settings.auth_verification_expire_minutes,
        )
        try:
            await self.sender.send(to=email, subject=subject, text=text, html=html)
        except EmailConfigurationError as exc:
            logger.error("auth code email not sent (purpose=%s): %s", purpose, exc)
        except Exception as exc:  # noqa: BLE001 - delivery must never change the API answer
            # Never log str(exc): provider replies can echo addresses. No code, no password.
            logger.error(
                "auth code email not sent (account=%s purpose=%s error=%s smtp_code=%s)",
                mask_email(email), purpose, type(exc).__name__, getattr(exc, "smtp_code", None),
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

    async def register(self, *, email: str, password: str) -> None:
        email = self._normalize_email(email)
        existing_user = await self._user_by_email(email)
        if existing_user is not None:
            # A previous attempt may have persisted the account before the
            # transactional email provider failed. Let that unverified mobile
            # account request a fresh code instead of trapping it as a duplicate.
            if (
                existing_user.password_hash is not None
                and existing_user.email_verified_at is None
                and existing_user.clerk_user_id is None
            ):
                # The latest registration wins: whoever pre-registered this address
                # must not keep a password that the mailbox owner verifies later, and
                # a code sent for the previous password cannot complete this one.
                existing_user.password_hash = _passwords.hash(password)
                await self._invalidate_code(existing_user, "verify")
                await self.session.commit()
                await self._issue_code(existing_user, "verify")
                return
            raise ConflictError("Ya existe una cuenta con este correo.", code="user_email_taken")
        user = User(
            email=email, full_name=email.split("@", 1)[0][:255] or "Usuario",
            password_hash=_passwords.hash(password), is_active=True,
            clerk_user_id=None, email_verified_at=None,
        )
        self.session.add(user)
        try:
            await self.session.flush()
            await self.session.commit()
        except IntegrityError as exc:
            await self.session.rollback()
            raise ConflictError("Ya existe una cuenta con este correo.", code="user_email_taken") from exc
        await self._issue_code(user, "verify")

    async def resend_verification(self, email: str) -> None:
        user = await self._user_by_email(self._normalize_email(email))
        if user is None or user.email_verified_at is not None or user.password_hash is None:
            return
        await self._issue_code(user, "verify")

    async def verify_email(self, *, email: str, code: str, password: str) -> dict:
        user = await self._user_by_email(self._normalize_email(email), lock=True)
        if user is None or user.password_hash is None:
            raise ForbiddenError("El código no es válido o ha vencido.", code="auth_code_invalid")
        if user.email_verified_at is not None:
            raise ForbiddenError("Este correo ya fue verificado. Inicia sesión.", code="auth_email_already_verified")
        await self._consume_code(user, "verify", code)
        # The holder of the code chooses the password: it replaces whatever was stored
        # when the address was first registered, possibly by someone else.
        user.password_hash = _passwords.hash(password)
        user.email_verified_at = datetime.now(UTC)
        await self._assign_bootstrap_admin(user)
        await self.session.commit()
        return await self._session_response(user.id)

    async def login(self, *, email: str, password: str) -> dict:
        user = await self._user_by_email(self._normalize_email(email))
        # Same response, and the same hashing work, for unknown email and wrong password.
        stored_hash = user.password_hash if user is not None else None
        if user is None or stored_hash is None:
            _passwords.verify(password, _timing_decoy_hash())
        if user is None or stored_hash is None or not _passwords.verify(password, stored_hash):
            raise ForbiddenError("Correo o contraseña incorrectos.", code="auth_invalid_credentials")
        if user.email_verified_at is None:
            raise ForbiddenError("Verifica tu correo antes de iniciar sesión.", code="auth_email_not_verified")
        if not user.is_active:
            raise ForbiddenError("La cuenta está desactivada.", code="user_inactive")
        if await self._assign_bootstrap_admin(user):
            await self.session.commit()
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
        # Every token issued before the reset stops working.
        user.token_version += 1
        await self.session.commit()

    async def logout(self, token: str) -> None:
        """Revoke every mobile token of the account that owns `token`."""
        user = await self.user_from_token(token)
        await self.session.execute(
            update(User).where(User.id == user.id).values(token_version=User.token_version + 1)
        )
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
            "sub": str(user.id), "iss": "mantix-mobile", "ver": user.token_version,
            "iat": now, "exp": now + timedelta(minutes=self.settings.mobile_access_token_minutes),
        }
        encoded = jwt.encode(payload, self._secret(), algorithm="HS256")
        return {"access_token": f"mjwt.{encoded}", "token_type": "bearer", "user": user_response(user).model_dump(mode="json")}

    async def user_from_token(self, token: str) -> User:
        if not token.startswith("mjwt."):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token móvil no válido.", headers={"WWW-Authenticate": "Bearer"})
        try:
            payload = jwt.decode(
                token[5:], self._secret(), algorithms=["HS256"],
                issuer="mantix-mobile", options={"require": ["sub", "exp", "iat", "iss"]},
            )
            user_id = int(payload["sub"])
        except (jwt.PyJWTError, ValueError, KeyError) as exc:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="La sesión ha vencido. Inicia sesión nuevamente.", headers={"WWW-Authenticate": "Bearer"}) from exc
        result = await self.session.execute(
            select(User).options(
                selectinload(User.roles).selectinload(Role.permissions)
            ).where(User.id == user_id)
        )
        user = result.scalar_one_or_none()
        if user is None or not user.is_active or user.email_verified_at is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="La cuenta no está disponible.", headers={"WWW-Authenticate": "Bearer"})
        # Tokens issued before this claim existed count as version 0.
        if payload.get("ver", 0) != user.token_version:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="La sesión ha vencido. Inicia sesión nuevamente.", headers={"WWW-Authenticate": "Bearer"})
        return user
