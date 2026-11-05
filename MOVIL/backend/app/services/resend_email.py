"""Transactional email delivery through Resend for native mobile authentication."""

import logging

import httpx

from app.core.config import Settings

logger = logging.getLogger(__name__)


class ResendEmailService:
    """Small Resend HTTP client; secrets and sender identity stay on the backend."""

    endpoint = "https://api.resend.com/emails"

    def __init__(self, settings: Settings):
        self.api_key = settings.resend_api_key
        self.from_email = settings.resend_from_email

    async def send_auth_code(
        self, *, recipient: str, code: str, purpose: str, expires_minutes: int
    ) -> None:
        if not self.api_key or not self.from_email:
            raise RuntimeError("Resend is not configured on the backend")

        if purpose == "verify":
            subject = "Verifica tu correo electrónico - Mantix"
            heading = "Verifica tu correo"
            explanation = "Usa este código para verificar tu dirección de correo y continuar con tu registro."
        else:
            subject = "Recupera tu contraseña - Mantix"
            heading = "Restablece tu contraseña"
            explanation = "Usa este código para confirmar que solicitaste restablecer tu contraseña."

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
        payload = {
            "from": self.from_email,
            "to": [recipient],
            "subject": subject,
            "html": html,
            "text": f"{heading}\n\n{explanation}\n\nCódigo: {code}\nVence en {expires_minutes} minutos. No compartas este código.",
        }
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(
                self.endpoint,
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                },
                json=payload,
            )
        if response.is_error:
            logger.error("Resend rejected an authentication email (status=%s)", response.status_code)
            raise RuntimeError("No se pudo enviar el correo de autenticación")
