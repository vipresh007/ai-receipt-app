"""Outbound email (Azure Communication Services).

Every email that's sent to a person (not the operator) passes `unsubscribe`
(the scope, see services/unsubscribe.py): the mailer adds the footer link and
the List-Unsubscribe headers."""

import asyncio
import logging
from functools import lru_cache
from typing import Protocol

from app.config import get_settings

log = logging.getLogger(__name__)


class Mailer(Protocol):
    async def send(
        self, *, to: str, subject: str, text: str, html: str, unsubscribe: str | None = None
    ) -> None: ...


def with_unsubscribe(to: str, scope: str, text: str, html: str) -> tuple[str, str, dict]:
    """The message with its unsubscribe footer, and the headers to send it with."""
    from html import escape

    from app.config import get_settings
    from app.services import unsubscribe as unsub

    page = unsub.page_url(to, scope)
    account = f"{get_settings().public_web_url}/account"
    text = f"{text.rstrip()}\n\n--\nUnsubscribe: {page}\n"
    links = f'<a href="{escape(page)}" style="color:#8A8F88">Unsubscribe</a>'
    if scope != "all":
        text += f"Choose which emails you get: {account}\n"
        links += (
            f' &middot; <a href="{escape(account)}" style="color:#8A8F88">'
            "Choose which emails you get</a>"
        )
    html = (
        f"{html}"
        '<p style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;'
        'font-size:12px;color:#8A8F88;max-width:520px;margin:28px auto 0">'
        f"{links}</p>"
    )
    headers = {
        "List-Unsubscribe": f"<{unsub.one_click_url(to, scope)}>",
        "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
    }
    return text, html, headers


class AcsMailer:
    def __init__(self, connection_string: str, sender: str) -> None:
        self._connection_string = connection_string
        self._sender = sender

    async def send(
        self, *, to: str, subject: str, text: str, html: str, unsubscribe: str | None = None
    ) -> None:
        headers: dict = {}
        if unsubscribe:
            text, html, headers = with_unsubscribe(to, unsubscribe, text, html)
        message = {
            "senderAddress": self._sender,
            "recipients": {"to": [{"address": to}]},
            "content": {"subject": subject, "plainText": text, "html": html},
        }
        if headers:
            message["headers"] = headers
        # The SDK's async client needs aiohttp; one request in a worker
        # thread is simpler than another dependency.
        try:
            await asyncio.to_thread(self._send_sync, message)
        except Exception:
            if not headers:
                raise
            # If the service ever refuses the headers, the footer link still works.
            log.warning("email headers refused; sending without them", exc_info=True)
            message.pop("headers", None)
            await asyncio.to_thread(self._send_sync, message)
        log.info("email queued")

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
