"""Return and warranty reminders by email: "Your Best Buy return window
closes Friday." Once per receipt for each, 3 days before the last day to
return it and 30 days before the warranty ends. The iPhone app also
schedules its own local reminders, so this is mainly for web users; it goes
only to verified addresses with notification emails on, and lands in the
activity feed either way."""

import asyncio
import html
import logging
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import and_, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models import Activity, Receipt, User
from app.services import notify_prefs, unsubscribe
from app.services.mailer import get_mailer

log = logging.getLogger(__name__)

RETURN_AHEAD = timedelta(days=3)
WARRANTY_AHEAD = timedelta(days=30)


def _day(d: date) -> str:
    return d.strftime("%a, %b %-d")


async def _claim(session: AsyncSession, receipt: Receipt, column, now: datetime) -> bool:
    """Mark it reminded unless another replica got there first."""
    result = await session.execute(
        update(Receipt)
        .where(Receipt.id == receipt.id, column.is_(None))
        .values({column.key: now})
        .execution_options(synchronize_session=False)
    )
    return result.rowcount == 1


async def send_due(session: AsyncSession, today: date) -> int:
    """Remind about everything coming up; returns how many reminders went out."""
    rows = await session.execute(
        select(Receipt, User)
        .join(User, User.id == Receipt.user_id)
        .where(
            or_(
                and_(
                    Receipt.return_by.is_not(None),
                    Receipt.return_reminded_at.is_(None),
                    Receipt.return_by >= today,
                    Receipt.return_by <= today + RETURN_AHEAD,
                ),
                and_(
                    Receipt.warranty_until.is_not(None),
                    Receipt.warranty_reminded_at.is_(None),
                    Receipt.warranty_until >= today,
                    Receipt.warranty_until <= today + WARRANTY_AHEAD,
                ),
            )
        )
        .limit(500)
    )
    now = datetime.now(UTC)
    mailer = get_mailer()
    url = f"{get_settings().public_web_url}/receipts"
    sent = 0
    for receipt, user in rows.all():
        store = receipt.merchant or "a receipt"
        lines: list[str] = []
        rb = receipt.return_by
        if (
            rb
            and receipt.return_reminded_at is None
            and today <= rb <= today + RETURN_AHEAD
            and await _claim(session, receipt, Receipt.return_reminded_at, now)
        ):
            lines.append(
                f"Last day to return your {store} purchase is "
                + ("today" if rb == today else _day(rb))
                + "."
            )
        wu = receipt.warranty_until
        if (
            wu
            and receipt.warranty_reminded_at is None
            and today <= wu <= today + WARRANTY_AHEAD
            and await _claim(session, receipt, Receipt.warranty_reminded_at, now)
        ):
            lines.append(f"The warranty on your {store} purchase ends {_day(wu)}.")
        for line in lines:
            session.add(
                Activity(
                    user_id=user.id, actor_name="Tally", kind="return_reminder", text=line[:300]
                )
            )
            sent += 1
            if (
                mailer
                and user.email_verified
                and notify_prefs.allowed(user, "return_reminder", "email")
                and not await unsubscribe.is_suppressed(session, user.email)
            ):
                message = {
                    "subject": line,
                    "text": f"{line}\n\nSee the receipt: {url}/{receipt.id}\n",
                    "html": (
                        '<div style="font-family:-apple-system,Segoe UI,Helvetica,Arial,'
                        'sans-serif;max-width:520px;margin:0 auto;color:#1E2321">'
                        f'<p style="font-size:16px">{html.escape(line)}</p>'
                        f'<p><a href="{html.escape(f"{url}/{receipt.id}")}" style="background:'
                        "#8A5E0F;color:#fff;text-decoration:none;padding:12px 22px;"
                        'border-radius:999px;font-weight:600;display:inline-block">'
                        "See the receipt</a></p></div>"
                    ),
                }
                try:
                    await mailer.send(to=user.email, unsubscribe="returns", **message)
                except Exception:  # noqa: BLE001 - the feed still has it
                    log.warning("reminder email failed", exc_info=True)
    await session.commit()
    return sent


async def run_forever(sessionmaker, every_seconds: int = 3600) -> None:
    await asyncio.sleep(60)
    while True:
        try:
            async with sessionmaker() as session:
                count = await send_due(session, date.today())
                if count:
                    log.info("sent %s return/warranty reminders", count)
        except Exception:  # noqa: BLE001 - try again next round
            log.warning("reminders run failed", exc_info=True)
        await asyncio.sleep(every_seconds)
