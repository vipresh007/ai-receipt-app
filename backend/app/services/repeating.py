"""Repeating expenses: each time one comes due, add a copy (docs/SPLITS.md).

Runs from a loop in the app (hourly). With more than one replica, each due
date is claimed with a conditional update, so only one of them adds it.
"""

import asyncio
import logging
from datetime import date

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Split, SplitParticipant
from app.services import activity, split_store

log = logging.getLogger(__name__)

# Never add more than this many missed copies in one go (e.g. after downtime).
MAX_CATCH_UP = 12


async def materialize_due(session: AsyncSession, today: date) -> int:
    """Add a copy of every repeating expense that's due. Returns how many."""
    added = 0
    due = list(
        await session.scalars(
            select(Split).where(
                Split.repeat != "", Split.next_at.is_not(None), Split.next_at <= today
            )
        )
    )
    for template in due:
        for _ in range(MAX_CATCH_UP):
            when = template.next_at
            if when is None or when > today:
                break
            following = split_store.next_date(when, template.repeat)
            claimed = await session.execute(
                update(Split)
                .where(Split.id == template.id, Split.next_at == when)
                .values(next_at=following)
                .execution_options(synchronize_session=False)
            )
            if claimed.rowcount != 1:
                break  # another replica got it
            template.next_at = following
            await _copy(session, template, when)
            added += 1
    await session.commit()
    return added


async def _copy(session: AsyncSession, template: Split, when: date) -> None:
    copy = Split(
        owner_user_id=template.owner_user_id,
        group_id=template.group_id,
        description=template.description,
        total=template.total,
        currency=template.currency,
        spent_at=when,
        mode=template.mode,
        line_items=list(template.line_items or []),
    )
    session.add(copy)
    await session.flush()
    rows = await session.scalars(
        select(SplitParticipant)
        .where(SplitParticipant.split_id == template.id)
        .order_by(SplitParticipant.position)
    )
    accounts = set()
    for r in rows:
        accounts.add(r.user_id)
        session.add(
            SplitParticipant(
                split_id=copy.id,
                member_id=r.member_id,
                person_id=r.person_id,
                user_id=r.user_id,
                display_name=r.display_name,
                position=r.position,
                is_payer=r.is_payer,
                item_indexes=list(r.item_indexes or []),
                custom_amount=r.custom_amount,
                weight=r.weight,
                paid=r.paid,
                share=r.share,
                share_token=split_store.new_token(),
            )
        )
    await split_store.log_event(session, copy, None, f"added again ({template.repeat})")
    await activity.notify(
        session,
        accounts | {template.owner_user_id},
        None,
        "repeated",
        f'"{template.description}" repeated for {when.strftime("%b %-d")}',
        split_id=copy.id,
        group_id=copy.group_id,
    )


async def run_forever(sessionmaker, every_seconds: int = 3600) -> None:
    await asyncio.sleep(30)
    while True:
        try:
            async with sessionmaker() as session:
                count = await materialize_due(session, date.today())
                if count:
                    log.info("added %s repeating expenses", count)
        except Exception:  # noqa: BLE001 - try again next round
            log.warning("repeating expenses run failed", exc_info=True)
        await asyncio.sleep(every_seconds)
