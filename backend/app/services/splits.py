"""Split arithmetic, group balances and settle-up suggestions (docs/SPLITS.md).

Everything is done in whole cents with exact fractions, then rounded with the
largest-remainder method, so shares always add up to the total exactly.
"""

import uuid
from dataclasses import dataclass, field
from decimal import Decimal
from fractions import Fraction

MODES = ("even", "items", "custom")


class SplitError(ValueError):
    """The split's inputs can't produce shares (shown to the user)."""


@dataclass
class ShareInput:
    item_indexes: list[int] = field(default_factory=list)
    custom_amount: Decimal | None = None


def _cents(value: Decimal) -> int:
    return int((Decimal(value) * 100).quantize(Decimal("1")))


def _decimal(cents: int) -> Decimal:
    return (Decimal(cents) / 100).quantize(Decimal("0.01"))


def _allocate(total_cents: int, exact: list[Fraction]) -> list[int]:
    """Round exact cent amounts so they sum to `total_cents`: floor each, then
    hand the leftover cents to the largest fractional parts (earliest first on
    ties)."""
    floors = [int(x // 1) for x in exact]
    leftover = total_cents - sum(floors)
    order = sorted(range(len(exact)), key=lambda i: (-(exact[i] - floors[i]), i))
    for i in order[: max(leftover, 0)]:
        floors[i] += 1
    return floors


def compute_shares(
    total: Decimal, mode: str, inputs: list[ShareInput], item_prices: list[Decimal]
) -> list[Decimal]:
    """Each participant's share of `total`, in input order."""
    if mode not in MODES:
        raise SplitError(f"Unknown split mode: {mode}")
    n = len(inputs)
    if n == 0:
        raise SplitError("Add at least one person to split with.")
    total_cents = _cents(total)

    if mode == "custom":
        amounts = [inp.custom_amount for inp in inputs]
        if any(a is None or a < 0 for a in amounts):
            raise SplitError("Enter an amount for everyone.")
        if sum(_cents(a) for a in amounts) != total_cents:
            raise SplitError(f"The amounts must add up to {_decimal(total_cents)}.")
        return [_decimal(_cents(a)) for a in amounts]

    if mode == "even":
        return [_decimal(c) for c in _allocate(total_cents, [Fraction(total_cents, n)] * n)]

    # items: each item shared by whoever had it (everyone, if nobody); the rest
    # of the total (tax, tip, fees, discounts) follows each person's subtotal.
    item_cents = [_cents(p) for p in item_prices]
    for inp in inputs:
        for idx in inp.item_indexes:
            if not 0 <= idx < len(item_cents):
                raise SplitError("That item isn't on this receipt.")
    base = [Fraction(0)] * n
    for idx, cents in enumerate(item_cents):
        holders = [i for i, inp in enumerate(inputs) if idx in inp.item_indexes] or list(range(n))
        for i in holders:
            base[i] += Fraction(cents, len(holders))
    rest = total_cents - sum(item_cents)
    subtotal = sum(base)
    if subtotal:
        exact = [b + Fraction(rest) * b / subtotal for b in base]
    else:
        exact = [b + Fraction(rest, n) for b in base]
    return [_decimal(c) for c in _allocate(total_cents, exact)]


# ─────────────────────────── groups ───────────────────────────


@dataclass
class SplitLedger:
    """One split's effect on a group: who paid, and each member's share."""

    payer_member_id: uuid.UUID | None
    shares: list[tuple[uuid.UUID | None, Decimal]]


def balances(
    splits: list[SplitLedger],
    settlements: list[tuple[uuid.UUID, uuid.UUID, Decimal]],
) -> dict[uuid.UUID, Decimal]:
    """Net balance per member: positive = is owed money, negative = owes.

    The payer is credited everyone else's shares; each other participant is
    debited theirs. A settlement (from paid to) moves the same amount back.
    """
    net: dict[uuid.UUID, int] = {}
    for s in splits:
        if s.payer_member_id is None:
            continue
        for member_id, share in s.shares:
            if member_id is None or member_id == s.payer_member_id:
                continue
            cents = _cents(share)
            net[member_id] = net.get(member_id, 0) - cents
            net[s.payer_member_id] = net.get(s.payer_member_id, 0) + cents
    for from_id, to_id, amount in settlements:
        cents = _cents(amount)
        net[from_id] = net.get(from_id, 0) + cents
        net[to_id] = net.get(to_id, 0) - cents
    return {member: _decimal(c) for member, c in net.items()}


def settle_up(net: dict[uuid.UUID, Decimal]) -> list[tuple[uuid.UUID, uuid.UUID, Decimal]]:
    """Payments that clear every balance: (debtor, creditor, amount), largest
    debtor paying largest creditor first — at most members − 1 payments."""
    debtors = sorted(((-_cents(v), m) for m, v in net.items() if v < 0), reverse=True)
    creditors = sorted(((_cents(v), m) for m, v in net.items() if v > 0), reverse=True)
    payments: list[tuple[uuid.UUID, uuid.UUID, Decimal]] = []
    d = c = 0
    debt = [list(x) for x in debtors]
    credit = [list(x) for x in creditors]
    while d < len(debt) and c < len(credit):
        amount = min(debt[d][0], credit[c][0])
        if amount > 0:
            payments.append((debt[d][1], credit[c][1], _decimal(amount)))
        debt[d][0] -= amount
        credit[c][0] -= amount
        if debt[d][0] == 0:
            d += 1
        if credit[c][0] == 0:
            c += 1
    return payments
