"""Stdlib-only SMTP adapter (no new runtime dependency)."""

import asyncio
import smtplib
import ssl
import uuid
from email.message import EmailMessage

from nebula_worker.adapters.base import EmailSendError
from nebula_worker.settings import Settings


class SmtpAdapter:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    async def send(self, *, to: str, subject: str, body: str) -> str:
        try:
            return await asyncio.to_thread(self._send_sync, to, subject, body)
        except (OSError, smtplib.SMTPException) as error:
            raise EmailSendError("SMTP delivery failed") from error

    def _send_sync(self, to: str, subject: str, body: str) -> str:
        message = EmailMessage()
        message["Subject"] = subject
        message["From"] = self._settings.email_from
        message["To"] = to
        message_id = f"<{uuid.uuid4()}@nebula-worker>"
        message["Message-ID"] = message_id
        message.set_content(body)

        settings = self._settings
        connection: smtplib.SMTP
        if settings.smtp_implicit_tls:
            connection = smtplib.SMTP_SSL(
                settings.smtp_host, settings.smtp_port, timeout=10, context=self._tls()
            )
        else:
            connection = smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10)
        with connection as smtp:
            if settings.smtp_starttls and not settings.smtp_implicit_tls:
                # Verified: smtplib's default context checks no certificate,
                # and a reset link is an account (audit AUD-001).
                smtp.starttls(context=self._tls())
            password = self._settings.smtp_password
            if self._settings.smtp_username and password:
                smtp.login(self._settings.smtp_username, password)
            smtp.send_message(message)
        return message_id

    def _tls(self) -> ssl.SSLContext:
        ca = self._settings.smtp_ca_file
        return ssl.create_default_context(cafile=str(ca) if ca else None)
