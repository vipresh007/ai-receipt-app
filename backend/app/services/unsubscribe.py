"""Unsubscribe links in every notification email.

Each email carries a signed link for its address and scope (a kind of
notification, or "all") in the footer and in the List-Unsubscribe header
(one-click, RFC 8058), so mail apps show their own Unsubscribe button. The
link opens a confirm page on the web app (a scanner opening it changes
nothing); confirming turns that kind of email off for an account, or, for
"all", turns email off and adds the address to `email_suppressions`, which
also stops invites and reminders to people without an account.
"""

import base64
import hashlib
import hmac
from urllib.parse import urlencode

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models import EmailSuppression, User
from app.services import notify_prefs

SCOPES = {
    "expenses": "emails about shared expenses",
    "payments": "emails about payments",
    "reminders": "reminders to pay",
    "returns": "return and warranty reminders",
    "all": "all emails from Tally",
}


def _key() -> bytes:
    s = get_settings()
    secret = s.unsubscribe_secret or s.acs_email_connection_string or "tally-unsubscribe"
    return hashlib.sha256(secret.encode()).digest()


def _b64(text: str) -> str:
    return base64.urlsafe_b64encode(text.encode()).decode().rstrip("=")


def _unb64(text: str) -> str:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4)).decode()


def sign(email: str, scope: str) -> str:
    message = f"{email.strip().lower()}|{scope}".encode()
    return hmac.new(_key(), message, hashlib.sha256).hexdigest()[:32]


def params(email: str, scope: str) -> dict:
    return {"e": _b64(email.strip().lower()), "s": scope, "t": sign(email, scope)}


def page_url(email: str, scope: str) -> str:
    """The footer link: a confirm page on the web app."""
    return f"{get_settings().public_web_url}/unsubscribe?{urlencode(params(email, scope))}"


def one_click_url(email: str, scope: str) -> str:
    """For the List-Unsubscribe header: a POST here unsubscribes at once."""
    base = get_settings().public_web_url
    return f"{base}/unsubscribe/one-click?{urlencode(params(email, scope))}"


def verify(e: str, scope: str, token: str) -> str | None:
    """The address, if the link is genuine."""
    if scope not in SCOPES:
        return None
    try:
        email = _unb64(e)
    except Exception:  # noqa: BLE001
        return None
    return email if hmac.compare_digest(sign(email, scope), token) else None


async def is_suppressed(session: AsyncSession, email: str | None) -> bool:
    if not email:
        return False
    found = await session.scalar(
        select(EmailSuppression.id).where(EmailSuppression.email == email.strip().lower())
    )
    return found is not None


async def suppressed_among(session: AsyncSession, emails: list[str]) -> set[str]:
    lowered = [e.strip().lower() for e in emails if e]
    if not lowered:
        return set()
    rows = await session.scalars(
        select(EmailSuppression.email).where(EmailSuppression.email.in_(lowered))
    )
    return set(rows)


async def has_account(session: AsyncSession, email: str) -> bool:
    found = await session.scalar(select(User.id).where(func.lower(User.email) == email))
    return found is not None


async def apply(session: AsyncSession, email: str, scope: str) -> None:
    email = email.strip().lower()
    user = await session.scalar(select(User).where(func.lower(User.email) == email))
    if scope == "all":
        if user is not None:
            user.email_notifications = False
        if not await is_suppressed(session, email):
            session.add(EmailSuppression(email=email))
    elif user is not None:
        user.notify_prefs = notify_prefs.merged(user, {f"{scope}.email": False})


async def resubscribe(session: AsyncSession, email: str | None) -> None:
    """Turning email back on in the app lifts an earlier "stop all"."""
    if email:
        await session.execute(
            delete(EmailSuppression).where(EmailSuppression.email == email.strip().lower())
        )
