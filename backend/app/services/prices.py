"""Item prices across your receipts: what the things you buy again cost now,
and how that moved. Matching is by name across stores; the same rule lives
in iOS `PriceTracker.key` and the web's `lib/prices.ts`, so keep them in sync.
A line's price is its total, so unit price = price ÷ quantity."""

import re
from dataclasses import dataclass, field
from datetime import date
from decimal import ROUND_HALF_EVEN, Decimal, InvalidOperation

from app.models import Receipt

_DROP = re.compile(r"[^\w.%]+", re.UNICODE)


def key(name: str) -> str:
    return " ".join(_DROP.sub(" ", name.lower().replace("_", " ")).split())


@dataclass
class Purchase:
    date: date
    merchant: str
    unit_price: Decimal
    receipt_id: str


@dataclass
class Tracked:
    key: str
    name: str
    purchases: list[Purchase] = field(default_factory=list)  # oldest first

    @property
    def latest(self) -> Purchase:
        return self.purchases[-1]

    @property
    def previous(self) -> Purchase | None:
        """The last purchase before the latest at a different price."""
        for p in reversed(self.purchases[:-1]):
            if p.unit_price != self.latest.unit_price:
                return p
        return None

    @property
    def change(self) -> float | None:
        prev = self.previous
        if prev is None or prev.unit_price <= 0:
            return None
        return float((self.latest.unit_price - prev.unit_price) / prev.unit_price)


def _money(value) -> Decimal | None:
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None


def tracked_items(receipts: list[Receipt]) -> list[Tracked]:
    """Items on at least two receipts, most recently bought first."""
    buckets: dict[str, Tracked] = {}
    for r in sorted(receipts, key=lambda r: (r.purchased_at or date.min, str(r.id))):
        if r.purchased_at is None:
            continue
        seen: set[str] = set()
        for item in r.line_items or []:
            price = _money(item.get("price"))
            k = key(str(item.get("name", "")))
            if price is None or price <= 0 or len(k) < 3 or k in seen:
                continue
            seen.add(k)
            qty = max(int(item.get("quantity") or 1), 1)
            unit = (price / qty).quantize(Decimal("0.01"), ROUND_HALF_EVEN)
            t = buckets.setdefault(k, Tracked(key=k, name=str(item.get("name"))))
            t.name = str(item.get("name"))
            t.purchases.append(Purchase(r.purchased_at, r.merchant or "", unit, str(r.id)))
    found = [t for t in buckets.values() if len(t.purchases) >= 2]
    return sorted(found, key=lambda t: t.latest.date, reverse=True)
