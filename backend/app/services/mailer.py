"""Outbound email (Azure Communication Services). Only invites for now."""

import asyncio
import logging
from functools import lru_cache
from typing import Protocol

from app.config import get_settings

log = logging.getLogger(__name__)


class Mailer(Protocol):
    async def send(self, *, to: str, subject: str, text: str, html: str) -> None: ...


class AcsMailer:
    def __init__(self, connection_string: str, sender: str) -> None:
        self._connection_string = connection_string
        self._sender = sender

    async def send(self, *, to: str, subject: str, text: str, html: str) -> None:
        message = {
            "senderAddress": self._sender,
            "recipients": {"to": [{"address": to}]},
            "content": {"subject": subject, "plainText": text, "html": html},
        }
        # The SDK's async client needs aiohttp; one request in a worker
        # thread is simpler than another dependency.
        await asyncio.to_thread(self._send_sync, message)
        log.info("invite email queued")

    def _send_sync(self, message: dict) -> None:
        from azure.communication.email import EmailClient

        client = EmailClient.from_connection_string(self._connection_string)
        # Accepted for delivery once this returns; no need to wait it out.
        client.begin_send(message)


@lru_cache
def get_mailer() -> Mailer | None:
    """`None` when email isn't configured. Overridden in tests."""
    settings = get_settings()
    if not settings.email_configured:
        return None
    return AcsMailer(settings.acs_email_connection_string, settings.email_sender)
