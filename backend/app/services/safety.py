"""Blocks and reports (models/safety.py)."""

import html
import logging
import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models import ContentReport, User, UserBlock
from app.services.mailer import get_mailer

log = logging.getLogger(__name__)

REASONS = {
    "spam": "Spam",
    "abuse": "Harassment or hate",
    "inappropriate": "Inappropriate",
    "other": "Something else",
}


async def blocked_by(session: AsyncSession, user_id: uuid.UUID) -> set[uuid.UUID]:
    """The people this user has blocked."""
    rows = await session.scalars(
        select(UserBlock.blocked_id).where(UserBlock.blocker_id == user_id)
    )
    return set(rows)


async def blockers_of(session: AsyncSession, user_id: uuid.UUID) -> set[uuid.UUID]:
    """The people who have blocked this user (and so don't hear from them)."""
    rows = await session.scalars(
        select(UserBlock.blocker_id).where(UserBlock.blocked_id == user_id)
    )
    return set(rows)


async def block(session: AsyncSession, blocker: User, blocked_id: uuid.UUID, name: str) -> None:
    if blocked_id == blocker.id:
        return
    existing = await session.scalar(
        select(UserBlock).where(
            UserBlock.blocker_id == blocker.id, UserBlock.blocked_id == blocked_id
        )
    )
    if existing is None:
        session.add(
            UserBlock(
                blocker_id=blocker.id, blocked_id=blocked_id, blocked_name=name[:120] or "Someone"
            )
        )


async def report(
    session: AsyncSession,
    reporter: User,
    *,
    reason: str,
    body: str,
    reported_user_id: uuid.UUID | None,
    reported_name: str,
    comment_id: uuid.UUID | None = None,
    split_id: uuid.UUID | None = None,
) -> None:
    """Keep a copy for review and send it to the reviewer, if one is set."""
    session.add(
        ContentReport(
            reporter_id=reporter.id,
            reported_user_id=reported_user_id,
            comment_id=comment_id,
            split_id=split_id,
            reason=reason,
            body=body[:1000],
        )
    )
    log.warning("content reported (%s) on split %s", reason, split_id)
    to = get_settings().report_email
    mailer = get_mailer()
    if not to or mailer is None:
        return
    label = REASONS.get(reason, reason)
    lines = [
        f"Reason: {label}",
        f"Written by: {reported_name} (user {reported_user_id})",
        f"Reported by: user {reporter.id}",
        f"Expense: {split_id}  Comment: {comment_id}",
        "",
        body,
    ]
    try:
        await mailer.send(
            to=to,
            subject=f"Tally report: {label}",
            text="\n".join(lines),
            html='<pre style="font-family:monospace;white-space:pre-wrap">'
            + html.escape("\n".join(lines))
            + "</pre>",
        )
    except Exception:  # noqa: BLE001 - the report is saved either way
        log.warning("report email failed", exc_info=True)
