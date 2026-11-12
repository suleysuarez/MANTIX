"""Delivery of the verification and password-recovery codes.

Two transports. By default, SMTP with mandatory STARTTLS and certificate checks:
personal SMTP (e.g. a Gmail app password) is meant for development and demos, not for
production. When `BREVO_API_KEY` is set, the codes go through Brevo's HTTPS API instead,
which works on hosts that block outbound SMTP ports (Render's free plan, for one).
"""

import asyncio
import logging
import smtplib
import ssl
from email.message import EmailMessage
from email.utils import parseaddr
from typing import Protocol

import httpx

from app.core.config import Settings

logger = logging.getLogger("mantix.mail")

_TIMEOUT_SECONDS = 15
_BREVO_URL = "https://api.brevo.com/v3/smtp/email"
_SETTING_NAMES = {
    "SMTP_HOST": "smtp_host",
    "SMTP_PORT": "smtp_port",
    "SMTP_USERNAME": "smtp_username",
    "SMTP_PASSWORD": "smtp_password",
    "SMTP_FROM": "smtp_from",
}


class EmailConfigurationError(RuntimeError):
    """The SMTP settings are missing or inconsistent. Names only, never values."""


class EmailDeliveryError(RuntimeError):
    """The mail API answered with an error. Only the status is kept: replies can echo addresses."""

    def __init__(self, http_status: int):
        super().__init__(f"El proveedor de correo respondió HTTP {http_status}.")
        self.http_status = http_status


class EmailSender(Protocol):
    async def send(self, *, to: str, subject: str, text: str, html: str) -> None: ...


def mask_email(email: str) -> str:
    """`ana@example.com` -> `a***@example.com`, for logs."""
    local, _, domain = email.partition("@")
    if not domain:
        return "***"
    return f"{local[:1]}***@{domain}"


def smtp_configuration_problem(settings: Settings) -> str | None:
    missing = [
        name for name, field in _SETTING_NAMES.items() if not getattr(settings, field)
    ]
    if missing:
        return "Faltan variables SMTP: " + ", ".join(missing) + "."
    sender_address = parseaddr(settings.smtp_from or "")[1].strip().lower()
    if sender_address != (settings.smtp_username or "").strip().lower():
        return (
            "SMTP_FROM debe ser la misma cuenta que SMTP_USERNAME: "
            "el proveedor rechaza o reescribe otros remitentes."
        )
    return None


def api_sender(settings: Settings) -> tuple[str, str]:
    """`(display name, address)` of the sender for the mail API: `EMAIL_FROM`, else `SMTP_FROM`."""
    name, address = parseaddr(settings.email_from or settings.smtp_from or "")
    return name.strip(), address.strip()


def mail_api_configuration_problem(settings: Settings) -> str | None:
    if not settings.email_api_key:
        return "Falta BREVO_API_KEY."
    if not api_sender(settings)[1]:
        return "Falta EMAIL_FROM (o SMTP_FROM): el remitente que verificaste en Brevo."
    return None


def log_mail_startup_notice(settings: Settings) -> None:
    if settings.email_api_key:
        problem = mail_api_configuration_problem(settings)
        if problem is not None:
            logger.warning(
                "El envío de códigos por correo no está listo: %s "
                "El registro y la recuperación de contraseña no podrán enviar códigos.",
                problem,
            )
        else:
            logger.info("Los códigos se envían por la API HTTPS de Brevo (sin SMTP).")
        return
    problem = smtp_configuration_problem(settings)
    if problem is not None:
        logger.warning(
            "El envío de códigos por correo no está listo: %s "
            "El registro y la recuperación de contraseña no podrán enviar códigos.",
            problem,
        )
    logger.warning(
        "El SMTP personal es solo para desarrollo o demostración; "
        "no lo uses en producción (cuota y reputación de la cuenta)."
    )


def render_auth_code_email(
    *, code: str, purpose: str, expires_minutes: int
) -> tuple[str, str, str]:
    """Return `(subject, text, html)` for a `verify` or `reset` code."""
    if purpose == "verify":
        subject = "Verifica tu correo electrónico - Mantix"
        heading = "Verifica tu correo"
        explanation = "Usa este código para verificar tu dirección de correo y continuar con tu registro."
    else:
        subject = "Recupera tu contraseña - Mantix"
        heading = "Restablece tu contraseña"
        explanation = (
            "Usa este código para confirmar que solicitaste restablecer tu contraseña."
        )

    html = f"""
        <!doctype html>
        <html lang="es">
          <body style="margin:0;padding:32px;background:#f3f6f8;font-family:Arial,sans-serif;color:#172b3a">
            <main style="max-width:480px;margin:auto;padding:32px;background:#fff;border-radius:16px">
              <h1 style="margin-top:0;color:#203b52">MANTIX</h1>
              <h2>{heading}</h2>
              <p>{explanation}</p>
              <p style="margin:28px 0;padding:18px;text-align:center;background:#edf3f8;border-radius:10px;font-size:32px;font-weight:700;letter-spacing:8px">{code}</p>
              <p>Este código vence en {expires_minutes} minutos. Si no solicitaste este código, puedes ignorar este mensaje.</p>
              <p style="font-size:12px;color:#687887">Por seguridad, no compartas este código con nadie.</p>
            </main>
          </body>
        </html>
        """
    text = (
        f"{heading}\n\n{explanation}\n\nCódigo: {code}\n"
        f"Vence en {expires_minutes} minutos. No compartas este código."
    )
    return subject, text, html


class SmtpEmailSender:
    """Sends through the configured SMTP account with mandatory STARTTLS."""

    def __init__(self, settings: Settings):
        self._settings = settings

    async def send(self, *, to: str, subject: str, text: str, html: str) -> None:
        problem = smtp_configuration_problem(self._settings)
        if problem is not None:
            raise EmailConfigurationError(problem)
        message = EmailMessage()
        message["From"] = self._settings.smtp_from
        message["To"] = to
        message["Subject"] = subject
        message.set_content(text)
        message.add_alternative(html, subtype="html")
        # smtplib is blocking: keep it off the event loop.
        await asyncio.to_thread(self._deliver, message)

    def _deliver(self, message: EmailMessage) -> None:
        settings = self._settings
        context = ssl.create_default_context()
        with smtplib.SMTP(
            settings.smtp_host, settings.smtp_port, timeout=_TIMEOUT_SECONDS
        ) as smtp:
            smtp.ehlo()
            smtp.starttls(context=context)
            smtp.ehlo()
            smtp.login(settings.smtp_username, settings.smtp_password)
            smtp.send_message(message)


class BrevoEmailSender:
    """Sends through Brevo's transactional HTTPS API (no SMTP port involved)."""

    def __init__(
        self, settings: Settings, transport: httpx.AsyncBaseTransport | None = None
    ):
        self._settings = settings
        self._transport = transport

    async def send(self, *, to: str, subject: str, text: str, html: str) -> None:
        problem = mail_api_configuration_problem(self._settings)
        if problem is not None:
            raise EmailConfigurationError(problem)
        name, address = api_sender(self._settings)
        sender = {"email": address, **({"name": name} if name else {})}
        async with httpx.AsyncClient(
            timeout=_TIMEOUT_SECONDS, transport=self._transport
        ) as client:
            response = await client.post(
                _BREVO_URL,
                headers={
                    "api-key": self._settings.email_api_key or "",
                    "accept": "application/json",
                },
                json={
                    "sender": sender,
                    "to": [{"email": to}],
                    "subject": subject,
                    "htmlContent": html,
                    "textContent": text,
                },
            )
        if response.status_code >= 300:
            raise EmailDeliveryError(response.status_code)


def build_email_sender(settings: Settings) -> EmailSender:
    """The mail API when `BREVO_API_KEY` is set; otherwise SMTP."""
    if settings.email_api_key:
        return BrevoEmailSender(settings)
    return SmtpEmailSender(settings)
