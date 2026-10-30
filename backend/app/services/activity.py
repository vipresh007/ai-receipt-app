"""Activity: what happened that concerns someone ("Sam added Dinner, your
share $20"), shown in the app, and for the things that need a nudge, emailed.

Emails go only to verified addresses of people who haven't turned them off,
at most one per person every 10 minutes (the feed still gets everything).
"""

import asyncio
import html
import logging
import uuid
from collections.abc import Iterable
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models import Activity, User
from app.services import realtime
from app.services.mailer import get_mailer

log = logging.getLogger(__name__)

EMAIL_GAP = timedelta(minutes=10)
EMAILED_KINDS = {"expense_added", "payment", "reminder"}

# Fire-and-forget sends, kept referenced until they finish.
_sending: set[asyncio.Task] = set()


def _aware(moment: datetime | None) -> datetime | None:
    if moment is not None and moment.tzinfo is None:
        return moment.replace(tzinfo=UTC)
    return moment


async def notify(
    session: AsyncSession,
    recipients: Iterable[uuid.UUID | None],
    actor: User | None,
    kind: str,
    text: str,
    *,
    split_id: uuid.UUID | None = None,
    group_id: uuid.UUID | None = None,
    person_id: uuid.UUID | None = None,
    link: str = "",
) -> None:
    """Add `text` to each recipient's activity (never the actor's own) and,
    for `EMAILED_KINDS`, email them. `text` reads after the actor's name."""
    actor_name = (actor.display_name or actor.email.split("@")[0]) if actor else "Tally"
    ids = {r for r in recipients if r is not None and (actor is None or r != actor.id)}
    # Their open apps refresh now (and the actor's other devices).
    await realtime.publish(session, ids | ({actor.id} if actor else set()))
    if not ids:
        return
    for user_id in ids:
        session.add(
            Activity(
                user_id=user_id,
                actor_name=actor_name[:120],
                kind=kind,
                text=text[:300],
                split_id=split_id,
                group_id=group_id,
                person_id=person_id,
            )
        )
    if kind in EMAILED_KINDS:
        await _email(session, ids, actor_name, text, link)


async def _email(
    session: AsyncSession, ids: set[uuid.UUID], actor_name: str, text: str, link: str
) -> None:
    mailer = get_mailer()
    if mailer is None:
        return
    now = datetime.now(UTC)
    users = await session.scalars(
        select(User).where(
            User.id.in_(ids), User.email_verified.is_(True), User.email_notifications.is_(True)
        )
    )
    url = link or f"{get_settings().public_web_url}/groups"
    for user in users:
        last = _aware(user.last_notified_at)
        if last is not None and now - last < EMAIL_GAP:
            continue
        user.last_notified_at = now
        line = f"{actor_name} {text}"
        message = {
            "subject": line if len(line) <= 90 else line[:87] + "…",
            "text": f"{line}\n\nSee it in Tally: {url}\n\n"
            "You get these because someone shares expenses with you on Tally. "
            "Turn them off in Tally under Account.\n",
            "html": (
                '<div style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;'
                'max-width:520px;margin:0 auto;color:#1E2321">'
                f'<p style="font-size:16px">{html.escape(line)}</p>'
                f'<p style="margin:24px 0"><a href="{html.escape(url)}" style="background:#8A5E0F;'
                "color:#fff;text-decoration:none;padding:12px 22px;border-radius:999px;"
                'font-weight:600;display:inline-block">Open Tally</a></p>'
                '<p style="font-size:13px;color:#5B5F59">You get these because someone shares '
                "expenses with you on Tally. Turn them off in Tally under Account.</p></div>"
            ),
        }
        task = asyncio.create_task(_send(mailer, user.email, message))
        _sending.add(task)
        task.add_done_callback(_sending.discard)


async def _send(mailer, to: str, message: dict) -> None:
    try:
        await mailer.send(to=to, **message)
    except Exception:  # noqa: BLE001 - a failed notification never fails the request
        log.warning("notification email failed", exc_info=True)


async def drain() -> None:
    """Wait for queued emails (tests)."""
    if _sending:
        await asyncio.gather(*list(_sending), return_exceptions=True)
