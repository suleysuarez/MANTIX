"""Administrator actions on the sign-in service (Clerk). Mantix never stores passwords."""

from app.core.clerk import get_clerk_client
from app.core.config import Settings
from app.core.exceptions import ConflictError


async def set_clerk_password(
    settings: Settings,
    clerk_user_id: str,
    password: str,
    *,
    sign_out_others: bool = True,
) -> None:
    """Set a person's password in the sign-in service and sign their other sessions out.

    Any failure is reported as a 409 whose message does not echo the service's answer (it could
    contain details about the account).
    """
    if not settings.clerk_secret_key:
        raise ConflictError("the sign-in service is not configured")
    client = get_clerk_client(settings.clerk_secret_key)
    try:
        await client.users.update_async(
            user_id=clerk_user_id,
            password=password,
            skip_password_checks=False,
            sign_out_of_other_sessions=sign_out_others,
        )
    except Exception as exc:  # the SDK raises several error types
        raise ConflictError(
            "the sign-in service rejected the new password or is unavailable"
        ) from exc


async def verify_clerk_password(
    settings: Settings, clerk_user_id: str, password: str
) -> bool:
    """Whether `password` is the person's current password (never raises for a wrong one)."""
    if not settings.clerk_secret_key:
        raise ConflictError("the sign-in service is not configured")
    client = get_clerk_client(settings.clerk_secret_key)
    try:
        await client.users.verify_password_async(
            user_id=clerk_user_id, password=password
        )
    except Exception:  # noqa: BLE001 - Clerk answers a wrong password with an error
        return False
    return True
