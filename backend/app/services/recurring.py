"""Recurring-expense detection.

A lightweight, no-bank-linking stand-in for the "find my subscriptions"
feature every finance app has — instead of scanning a linked bank feed, it
looks for the same merchant showing up in your own scanned/entered receipts
across separate months at roughly the same amount. Deterministic and
rule-based, same spirit as `app/services/insights.py`.
"""

from collections import defaultdict
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from uuid import UUID

from app.models import Receipt

_TOLERANCE = Decimal("0.15")  # amounts within 15% of the group average still count
_MIN_OCCURRENCES = 2  # must show up in at least this many distinct months


@dataclass
class RecurringGroup:
    merchant: str
    category_slug: str
    average_amount: Decimal
    occurrences: int
    last_purchased_at: date
    receipt_ids: list[UUID]


def find_recurring(receipts: Sequence[Receipt]) -> list[RecurringGroup]:
    """Group receipts by normalized merchant name and keep the groups that
    span at least `_MIN_OCCURRENCES` distinct calendar months with amounts
    close enough together to plausibly be the same recurring charge."""
    by_merchant: dict[str, list[Receipt]] = defaultdict(list)
    for r in receipts:
        key = r.merchant.strip().lower()
        if not key or r.purchased_at is None:
            continue
        by_merchant[key].append(r)

    groups: list[RecurringGroup] = []
    for items in by_merchant.values():
        distinct_months = {(r.purchased_at.year, r.purchased_at.month) for r in items}
        if len(distinct_months) < _MIN_OCCURRENCES:
            continue

        average = sum((Decimal(r.total) for r in items), Decimal("0")) / len(items)
        if average <= 0:
            continue
        if not all(abs(Decimal(r.total) - average) <= average * _TOLERANCE for r in items):
            continue

        latest = max(items, key=lambda r: r.purchased_at)
        groups.append(
            RecurringGroup(
                merchant=latest.merchant,
                category_slug=latest.category_slug,
                average_amount=average,
                occurrences=len(items),
                last_purchased_at=latest.purchased_at,
                receipt_ids=[r.id for r in items],
            )
        )

    return sorted(groups, key=lambda g: g.last_purchased_at, reverse=True)
