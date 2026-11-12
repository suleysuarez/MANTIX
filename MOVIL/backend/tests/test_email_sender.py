"""SMTP sender, configuration checks and logging. No real SMTP connection is opened."""

import json
import logging
import smtplib
import ssl
from typing import ClassVar

import httpx
import pytest

from app.core.config import Settings
from app.services.email_sender import (
    BrevoEmailSender,
    EmailDeliveryError,
    EmailConfigurationError,
    SmtpEmailSender,
    build_email_sender,
    log_mail_startup_notice,
    mail_api_configuration_problem,
    mask_email,
    render_auth_code_email,
    smtp_configuration_problem,
)
from app.services.mobile_auth import MobileAuthService

SMTP_PASSWORD = "Zq9-fake-app-password"
API_KEY = "xkeysib-fake-0123456789"
CODE = "482916"
RECIPIENT = "ana.perez@example.com"
SENDER = "mantix.demo@example.org"


def make_settings(**overrides: str) -> Settings:
    values = {
        "SMTP_HOST": "smtp.example.org",
        "SMTP_PORT": "587",
        "SMTP_USERNAME": SENDER,
        "SMTP_PASSWORD": SMTP_PASSWORD,
        "SMTP_FROM": SENDER,
    }
    values.update(overrides)
    return Settings(
        _env_file=None, **{k: v for k, v in values.items() if v is not None}
    )  # type: ignore[arg-type]


class FakeSMTP:
    instances: ClassVar[list["FakeSMTP"]] = []

    def __init__(self, host, port, timeout=None):
        self.host, self.port, self.timeout = host, port, timeout
        self.calls: list[str] = []
        self.sent = []
        self.context = None
        self.credentials = None
        FakeSMTP.instances.append(self)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def ehlo(self):
        self.calls.append("ehlo")

    def starttls(self, context=None):
        self.calls.append("starttls")
        self.context = context

    def login(self, user, password):
        self.calls.append("login")
        self.credentials = (user, password)

    def send_message(self, message):
        self.calls.append("send")
        self.sent.append(message)


@pytest.fixture
def fake_smtp(monkeypatch: pytest.MonkeyPatch) -> type[FakeSMTP]:
    FakeSMTP.instances = []
    monkeypatch.setattr(smtplib, "SMTP", FakeSMTP)
    return FakeSMTP


async def test_the_message_goes_to_the_recipient_from_the_configured_sender(fake_smtp):
    sender = SmtpEmailSender(make_settings())
    await sender.send(to=RECIPIENT, subject="Asunto", text="texto", html="<p>html</p>")

    (connection,) = fake_smtp.instances
    (message,) = connection.sent
    assert message["To"] == RECIPIENT
    assert message["From"] == SENDER
    assert message["Subject"] == "Asunto"
    assert (connection.host, connection.port) == ("smtp.example.org", 587)
    assert connection.timeout and connection.timeout > 0


async def test_starttls_with_certificate_checks_comes_before_the_login(fake_smtp):
    await SmtpEmailSender(make_settings()).send(
        to=RECIPIENT, subject="s", text="t", html="h"
    )

    (connection,) = fake_smtp.instances
    assert connection.calls == ["ehlo", "starttls", "ehlo", "login", "send"]
    assert connection.context.verify_mode == ssl.CERT_REQUIRED
    assert connection.context.check_hostname is True
    assert connection.credentials == (SENDER, SMTP_PASSWORD)


@pytest.mark.parametrize("purpose", ["verify", "reset"])
async def test_verification_and_recovery_emails_use_the_configured_sender(
    fake_smtp, purpose
):
    service = MobileAuthService(None, make_settings())  # type: ignore[arg-type]
    await service._send_code(RECIPIENT, CODE, purpose)

    (message,) = fake_smtp.instances[0].sent
    assert message["From"] == SENDER
    assert message["To"] == RECIPIENT
    assert CODE in message.get_body(("plain",)).get_content()


def test_the_two_emails_have_their_own_subject():
    verify, _, _ = render_auth_code_email(
        code=CODE, purpose="verify", expires_minutes=10
    )
    reset, _, _ = render_auth_code_email(code=CODE, purpose="reset", expires_minutes=10)
    assert "Verifica" in verify and "Recupera" in reset


def test_incomplete_settings_name_the_missing_variables_only():
    problem = smtp_configuration_problem(make_settings(SMTP_PASSWORD="", SMTP_HOST=""))
    assert problem is not None
    assert "SMTP_HOST" in problem and "SMTP_PASSWORD" in problem
    assert "SMTP_USERNAME" not in problem


def test_a_sender_different_from_the_account_is_reported_clearly():
    problem = smtp_configuration_problem(make_settings(SMTP_FROM="otra@example.org"))
    assert problem is not None and "SMTP_FROM" in problem and "SMTP_USERNAME" in problem


def test_a_display_name_in_smtp_from_is_accepted():
    assert (
        smtp_configuration_problem(make_settings(SMTP_FROM=f"Mantix <{SENDER}>"))
        is None
    )


def test_blank_values_count_as_missing_and_do_not_break_the_settings():
    settings = make_settings(SMTP_PORT="")
    assert settings.smtp_port is None
    assert "SMTP_PORT" in (smtp_configuration_problem(settings) or "")


async def test_incomplete_settings_fail_on_send_without_opening_a_connection(fake_smtp):
    with pytest.raises(EmailConfigurationError) as error:
        await SmtpEmailSender(make_settings(SMTP_HOST="")).send(
            to=RECIPIENT, subject="s", text="t", html="h"
        )
    assert "SMTP_HOST" in str(error.value)
    assert fake_smtp.instances == []


class FailingSender:
    def __init__(self, error: Exception):
        self.error = error

    async def send(self, **kwargs):
        raise self.error


async def test_a_failed_delivery_does_not_raise_and_logs_without_secrets(caplog):
    error = smtplib.SMTPAuthenticationError(
        535,
        f"5.7.8 Username and Password not accepted for {RECIPIENT} {SMTP_PASSWORD}".encode(),
    )
    service = MobileAuthService(None, make_settings(), sender=FailingSender(error))  # type: ignore[arg-type]
    with caplog.at_level(logging.DEBUG):
        await service._send_code(RECIPIENT, CODE, "verify")  # must not raise

    assert "SMTPAuthenticationError" in caplog.text and "535" in caplog.text
    assert mask_email(RECIPIENT) in caplog.text
    for secret in (SMTP_PASSWORD, CODE, RECIPIENT):
        assert secret not in caplog.text


async def test_a_configuration_error_is_logged_with_names_only(caplog):
    settings = make_settings(SMTP_PASSWORD="")
    service = MobileAuthService(None, settings, sender=SmtpEmailSender(settings))  # type: ignore[arg-type]
    with caplog.at_level(logging.DEBUG):
        await service._send_code(RECIPIENT, CODE, "reset")

    assert "SMTP_PASSWORD" in caplog.text
    assert CODE not in caplog.text and RECIPIENT not in caplog.text


def test_startup_warns_about_missing_variables_and_about_personal_smtp(caplog):
    with caplog.at_level(logging.DEBUG):
        log_mail_startup_notice(make_settings(SMTP_PASSWORD="", SMTP_FROM=""))
    assert "SMTP_PASSWORD" in caplog.text and "SMTP_FROM" in caplog.text
    assert "desarrollo o demostración" in caplog.text


def test_startup_with_complete_settings_only_gives_the_demo_notice_and_no_secrets(
    caplog,
):
    with caplog.at_level(logging.DEBUG):
        log_mail_startup_notice(make_settings())
    assert "desarrollo o demostración" in caplog.text
    assert "no está listo" not in caplog.text
    assert SMTP_PASSWORD not in caplog.text and SENDER not in caplog.text


def test_mask_email_hides_the_local_part():
    assert mask_email("ana.perez@example.com") == "a***@example.com"
    assert mask_email("sin-arroba") == "***"


# -- Brevo HTTPS API (used when BREVO_API_KEY is set) --------------------------------


def api_settings(**overrides: str) -> Settings:
    return make_settings(BREVO_API_KEY=API_KEY, **overrides)


def api_transport(status: int = 201, seen: list | None = None) -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        if seen is not None:
            seen.append(request)
        return httpx.Response(status, json={"messageId": "<x@y>", "echo": RECIPIENT})

    return httpx.MockTransport(handler)


async def test_the_api_sender_posts_the_message_with_the_key_and_the_verified_sender():
    seen: list[httpx.Request] = []
    sender = BrevoEmailSender(api_settings(), transport=api_transport(seen=seen))

    await sender.send(to=RECIPIENT, subject="Asunto", text="texto", html="<p>h</p>")

    (request,) = seen
    assert request.method == "POST"
    assert str(request.url) == "https://api.brevo.com/v3/smtp/email"
    assert request.headers["api-key"] == API_KEY
    body = json.loads(request.content)
    assert body["sender"] == {"email": SENDER}
    assert body["to"] == [{"email": RECIPIENT}]
    assert body["subject"] == "Asunto"
    assert body["textContent"] == "texto" and body["htmlContent"] == "<p>h</p>"


async def test_email_from_wins_over_smtp_from_and_keeps_the_display_name():
    seen: list[httpx.Request] = []
    settings = api_settings(EMAIL_FROM="Mantix <verificado@example.org>")
    await BrevoEmailSender(settings, transport=api_transport(seen=seen)).send(
        to=RECIPIENT, subject="s", text="t", html="h"
    )
    assert json.loads(seen[0].content)["sender"] == {
        "name": "Mantix",
        "email": "verificado@example.org",
    }


async def test_an_error_status_raises_with_only_the_status_and_no_reply_body():
    sender = BrevoEmailSender(api_settings(), transport=api_transport(status=401))
    with pytest.raises(EmailDeliveryError) as error:
        await sender.send(to=RECIPIENT, subject="s", text="t", html="h")
    assert error.value.http_status == 401
    assert RECIPIENT not in str(error.value) and API_KEY not in str(error.value)


async def test_the_api_sender_without_a_sender_fails_before_any_request():
    seen: list[httpx.Request] = []
    settings = make_settings(BREVO_API_KEY=API_KEY, SMTP_FROM="")
    with pytest.raises(EmailConfigurationError) as error:
        await BrevoEmailSender(settings, transport=api_transport(seen=seen)).send(
            to=RECIPIENT, subject="s", text="t", html="h"
        )
    assert "EMAIL_FROM" in str(error.value)
    assert seen == []


def test_the_api_key_decides_which_transport_is_used():
    assert isinstance(build_email_sender(make_settings()), SmtpEmailSender)
    assert isinstance(build_email_sender(api_settings()), BrevoEmailSender)
    assert make_settings(BREVO_API_KEY="").email_api_key is None


def test_the_api_configuration_problem_names_the_variables_only():
    assert mail_api_configuration_problem(api_settings()) is None
    assert "BREVO_API_KEY" in (mail_api_configuration_problem(make_settings()) or "")


async def test_a_failed_api_delivery_logs_the_status_and_no_secrets(caplog):
    settings = api_settings()
    service = MobileAuthService(
        None,  # type: ignore[arg-type]
        settings,
        sender=BrevoEmailSender(settings, transport=api_transport(status=403)),
    )
    with caplog.at_level(logging.DEBUG):
        await service._send_code(RECIPIENT, CODE, "verify")  # must not raise

    assert "EmailDeliveryError" in caplog.text and "http_status=403" in caplog.text
    for secret in (API_KEY, CODE, RECIPIENT):
        assert secret not in caplog.text


def test_startup_with_the_api_does_not_give_the_smtp_demo_notice(caplog):
    with caplog.at_level(logging.DEBUG):
        log_mail_startup_notice(api_settings())
    assert "Brevo" in caplog.text
    assert "desarrollo o demostración" not in caplog.text
    assert API_KEY not in caplog.text and SENDER not in caplog.text
