from dataclasses import dataclass
from functools import lru_cache
from typing import Any

import httpx
from clerk_backend_api import Clerk
from clerk_backend_api.security import authenticate_request
from clerk_backend_api.security.types import AuthenticateRequestOptions
from fastapi import HTTPException, Request, status

from app.core.config import Settings


@dataclass(frozen=True)
class VerifiedClerkIdentity:
    user_id: str
    claims: dict[str, Any]


@dataclass(frozen=True)
class ClerkProfile:
    clerk_user_id: str
    email: str
    full_name: str


@lru_cache
def get_clerk_client(secret_key: str) -> Clerk:
    return Clerk(bearer_auth=secret_key)


def verify_clerk_request(request: Request, settings: Settings) -> VerifiedClerkIdentity:
    if not settings.clerk_secret_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="El inicio de sesión no está disponible por ahora.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    http_request = httpx.Request(
        method=request.method,
        url=str(request.url),
        headers=dict(request.headers),
    )
    state = authenticate_request(
        http_request,
        AuthenticateRequestOptions(
            secret_key=settings.clerk_secret_key,
            authorized_parties=settings.clerk_authorized_party_list,
        ),
    )
    if not state.is_signed_in or not state.payload or not state.payload.get("sub"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Tu sesión no es válida o expiró. Inicia sesión de nuevo.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return VerifiedClerkIdentity(
        user_id=str(state.payload["sub"]),
        claims=state.payload,
    )


async def get_clerk_profile(
    identity: VerifiedClerkIdentity, settings: Settings
) -> ClerkProfile:
    claims = identity.claims
    email = claims.get("email")
    full_name = claims.get("name") or claims.get("full_name") or "Clerk user"
    if email:
        return ClerkProfile(identity.user_id, str(email).lower(), str(full_name))

    if not settings.clerk_secret_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="No pudimos verificar tu perfil. Inicia sesión de nuevo.",
        )
    client = get_clerk_client(settings.clerk_secret_key)
    clerk_user = await client.users.get_async(user_id=identity.user_id)
    email_addresses = getattr(clerk_user, "email_addresses", []) or []
    primary_email_id = getattr(clerk_user, "primary_email_address_id", None)
    selected_email = next(
        (
            item
            for item in email_addresses
            if getattr(item, "id", None) == primary_email_id
        ),
        email_addresses[0] if email_addresses else None,
    )
    resolved_email = getattr(selected_email, "email_address", None)
    if not resolved_email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Tu cuenta no tiene un correo válido. Contacta a un administrador.",
        )
    first_name = getattr(clerk_user, "first_name", None) or ""
    last_name = getattr(clerk_user, "last_name", None) or ""
    resolved_name = " ".join(part for part in (first_name, last_name) if part).strip()
    return ClerkProfile(
        identity.user_id,
        str(resolved_email).lower(),
        resolved_name or "Clerk user",
    )
