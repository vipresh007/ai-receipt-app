"""The same receipt added twice: scanned and also emailed, forwarded twice,
scanned twice. Same store (loosely: "FRESHCO" = "FreshCo", "Eggholic" =
"Eggholic- Indian Street Food (Brampton)", "FreshCo" = "CHALO! FRESH CO"),
same day, same total.

Mirrored on iOS in `DuplicateFinder` (keep the matching rules in step)."""

import re
import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Expense, Receipt, Split
from app.services import split_store


def store_key(name: str | None) -> str:
    return re.sub(r"[^a-z0-9]", "", (name or "").lower())


def same_store(a: str | None, b: str | None) -> bool:
    ka, kb = store_key(a), store_key(b)
    if not ka or not kb:
        return False
    if ka == kb:
        return True
    short, long = sorted((ka, kb), key=len)
    return len(short) >= 4 and short in long


async def find(
    session: AsyncSession,
    user_id: uuid.UUID,
    merchant: str | None,
    day: date | None,
    total: Decimal,
    exclude: uuid.UUID | None = None,
) -> Receipt | None:
    """The earliest other receipt that looks like this one, if any."""
    if day is None or not total:
        return None
    rows = await session.scalars(
        select(Receipt)
        .where(Receipt.user_id == user_id, Receipt.purchased_at == day, Receipt.total == total)
        .order_by(Receipt.created_at)
    )
    return next((r for r in rows if r.id != exclude and same_store(r.merchant, merchant)), None)


async def merge(session: AsyncSession, new: Receipt, into: Receipt) -> list[str]:
    """Keep `into`, take what only `new` has, and remove `new`. Returns what
    was taken ("photo", "items")."""
    took = []
    if not into.image_blob_url and new.image_blob_url:
        into.image_blob_url = new.image_blob_url
        took.append("photo")
    if not into.line_items and new.line_items:
        into.line_items = new.line_items
        took.append("items")
    if into.return_by is None and new.return_by is not None:
        into.return_by = new.return_by
    split = await session.scalar(select(Split).where(Split.receipt_id == new.id))
    if split is not None:
        await split_store.delete_split(session, split)
    for expense in await session.scalars(select(Expense).where(Expense.receipt_id == new.id)):
        await session.delete(expense)
    await session.delete(new)
    return took


def groups(receipts: list[Receipt]) -> list[list[Receipt]]:
    """Receipts that look like the same one, oldest first in each group."""
    buckets: dict[tuple, list[Receipt]] = {}
    for r in receipts:
        if r.purchased_at is not None and r.total:
            buckets.setdefault((r.purchased_at, r.total), []).append(r)
    out = []
    for bucket in buckets.values():
        bucket.sort(key=lambda r: r.created_at)
        seen: set[uuid.UUID] = set()
        for r in bucket:
            if r.id in seen:
                continue
            group = [r] + [
                o
                for o in bucket
                if o.id != r.id and o.id not in seen and same_store(r.merchant, o.merchant)
            ]
            if len(group) > 1:
                seen.update(o.id for o in group)
                out.append(group)
    out.sort(key=lambda g: g[0].purchased_at, reverse=True)
    return out
