"""Saving splits and reading groups — the persistence side of docs/SPLITS.md.

The arithmetic lives in `services/splits.py`; this module turns requests into
rows, keeps a split receipt's `my_share` and expense row in step with the
split, and assembles group views (members, balances, settle-up payments).
"""

import calendar
import secrets
import uuid
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal, InvalidOperation

from fastapi import HTTPException, status
from sqlalchemy import delete as sa_delete
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models import (
    Expense,
    Group,
    GroupMember,
    Person,
    Receipt,
    Settlement,
    Split,
    SplitComment,
    SplitEvent,
    SplitParticipant,
    User,
)
from app.schemas.receipt import ExtractionItemOut
from app.schemas.split import (
    GroupDetailOut,
    GroupSummaryOut,
    MemberOut,
    ParticipantOut,
    PayDetails,
    PaymentOut,
    SettlementOut,
    SplitAdjustIn,
    SplitIn,
    SplitOut,
)
from app.services import activity, realtime
from app.services.splits import (
    ShareInput,
    SplitError,
    SplitLedger,
    balances,
    compute_shares,
    direct_debts,
)
from app.services.splits import settle_up as suggest_payments


def new_token() -> str:
    """128 bits of randomness, URL-safe."""
    return secrets.token_urlsafe(16)


async def next_position(session: AsyncSession, group_id: uuid.UUID) -> int:
    current = await session.scalar(
        select(func.max(GroupMember.position)).where(GroupMember.group_id == group_id)
    )
    return (current or 0) + 1


def display_name_for(user: User) -> str:
    return (user.display_name or "").strip() or user.email.split("@")[0]


def _money(value: str | None, field: str) -> Decimal:
    try:
        amount = Decimal(str(value).replace(",", "").strip())
    except (InvalidOperation, AttributeError) as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"Invalid {field}.") from exc
    if amount < 0 or amount != amount:  # negative or NaN
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"Invalid {field}.")
    return amount.quantize(Decimal("0.01"))


def _weight(value: str | None) -> Decimal | None:
    """A shares-mode weight: blank means 1 part (left as None)."""
    if value is None or not str(value).strip():
        return None
    try:
        weight = Decimal(str(value).strip())
    except InvalidOperation as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Invalid share.") from exc
    if not weight.is_finite() or weight < 0 or weight > 1_000_000:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Invalid share.")
    return weight.quantize(Decimal("0.01"))


def _bad(message: str, code: int = status.HTTP_422_UNPROCESSABLE_CONTENT) -> HTTPException:
    return HTTPException(code, message)


def share_url(token: str) -> str:
    return f"{get_settings().public_web_url}/s/{token}"


def invite_url(token: str) -> str:
    return f"{get_settings().public_web_url}/join/{token}"


# ─────────────────────────── groups: access ───────────────────────────


async def require_member(
    session: AsyncSession, group_id: uuid.UUID, user: User
) -> tuple[Group, GroupMember]:
    """The group and the caller's membership, or 404 (non-members can't tell
    the group exists)."""
    group = await session.get(Group, group_id)
    member = None
    if group is not None:
        member = await session.scalar(
            select(GroupMember).where(
                GroupMember.group_id == group_id, GroupMember.user_id == user.id
            )
        )
    if group is None or member is None:
        raise _bad("Group not found.", status.HTTP_404_NOT_FOUND)
    return group, member


async def _members(session: AsyncSession, group_id: uuid.UUID) -> list[GroupMember]:
    return list(
        await session.scalars(
            select(GroupMember)
            .where(GroupMember.group_id == group_id)
            .order_by(GroupMember.position, GroupMember.created_at)
        )
    )


# ─────────────────────────── splits ───────────────────────────


async def _person_named(session: AsyncSession, user: User, name: str) -> Person:
    """Your saved person with this name (any case), or a new one."""
    person = await session.scalar(
        select(Person)
        .where(Person.owner_user_id == user.id, func.lower(Person.display_name) == name.lower())
        .order_by(Person.created_at)
        .limit(1)
    )
    if person is None:
        person = Person(owner_user_id=user.id, display_name=name[:120], invite_token=new_token())
        session.add(person)
        await session.flush()
    return person


async def _participants(session: AsyncSession, split_id: uuid.UUID) -> list[SplitParticipant]:
    return list(
        await session.scalars(
            select(SplitParticipant)
            .where(SplitParticipant.split_id == split_id)
            .order_by(SplitParticipant.position, SplitParticipant.created_at)
        )
    )


async def save_split(
    session: AsyncSession, user: User, split: Split | None, data: SplitIn
) -> Split:
    """Create (`split` None) or replace a split from `data`, compute shares, and
    sync the receipt's share. Caller commits."""
    group: Group | None = None
    members_by_id: dict[uuid.UUID, GroupMember] = {}
    if data.group_id is not None:
        group, _ = await require_member(session, data.group_id, user)
        members_by_id = {m.id: m for m in await _members(session, group.id)}

    receipt: Receipt | None = None
    if data.receipt_id is not None:
        receipt = await session.get(Receipt, data.receipt_id)
        if receipt is None or receipt.user_id != user.id:
            raise _bad("Receipt not found.", status.HTTP_404_NOT_FOUND)
        existing = await session.scalar(select(Split).where(Split.receipt_id == receipt.id))
        if existing is not None and (split is None or existing.id != split.id):
            raise _bad("This receipt is already split.", status.HTTP_409_CONFLICT)
        total = receipt.total
        description = receipt.merchant or "Receipt"
        spent_at = receipt.purchased_at or date.today()
        currency = receipt.currency or (group.currency if group else "CAD")
        items = list(receipt.line_items or [])
    else:
        if not data.description.strip():
            raise _bad("Add a description.")
        total = _money(data.total, "total")
        description = data.description.strip()
        try:
            spent_at = date.fromisoformat(data.date) if data.date else date.today()
        except ValueError as exc:
            raise _bad("Invalid date.") from exc
        currency = (data.currency or (group.currency if group else "CAD")).upper()[:3]
        items = [item.model_dump() for item in data.items]

    # Build participants.
    rows: list[SplitParticipant] = []
    seen_members: set[uuid.UUID] = set()
    seen_people: set[uuid.UUID] = set()
    for position, p in enumerate(data.participants):
        member_id: uuid.UUID | None = None
        person_id: uuid.UUID | None = None
        user_id: uuid.UUID | None = None
        if group is not None:
            if p.is_me:
                me = next((m for m in members_by_id.values() if m.user_id == user.id), None)
                member_id = me.id if me else None
            else:
                member_id = p.member_id
            if member_id is None or member_id not in members_by_id:
                raise _bad("Everyone in a group split must be in the group.")
            if member_id in seen_members:
                raise _bad("Someone is in this split twice.")
            seen_members.add(member_id)
            member = members_by_id[member_id]
            user_id = member.user_id
            name = member.display_name
        else:
            if p.member_id is not None:
                raise _bad("Pick a group to split with its members.")
            if p.is_me:
                user_id = user.id
                name = display_name_for(user)
            else:
                # Everyone else is a saved person: picked, or saved now by name.
                if p.person_id is not None:
                    person = await session.get(Person, p.person_id)
                    if person is None or person.owner_user_id != user.id:
                        raise _bad("Person not found.", status.HTTP_404_NOT_FOUND)
                elif p.name.strip():
                    person = await _person_named(session, user, p.name.strip())
                else:
                    raise _bad("Every person needs a name.")
                if person.id in seen_people:
                    raise _bad("Someone is in this split twice.")
                seen_people.add(person.id)
                person_id = person.id
                user_id = person.user_id
                name = person.display_name
        custom, weight = _mode_inputs(data.mode, p.amount, p.weight)
        rows.append(
            SplitParticipant(
                member_id=member_id,
                person_id=person_id,
                user_id=user_id,
                display_name=name[:120],
                position=position,
                is_payer=p.is_payer,
                item_indexes=sorted(set(p.item_indexes)),
                custom_amount=custom,
                weight=weight,
                share_token=new_token(),
            )
        )

    if sum(1 for r in rows if r.user_id == user.id) > 1:
        raise _bad("You're in this split twice.")
    mine = next((r for r in rows if r.user_id == user.id), None)
    _set_payers(rows, total, [p.paid for p in data.participants], default=mine, required=group)
    _set_shares(rows, total, data.mode, items)

    before = None
    if split is None:
        split = Split(owner_user_id=user.id)
        session.add(split)
    else:
        old = await _participants(session, split.id)
        before = _snapshot(split, old)
        # Keep each person's link when they're still on the split.
        old_by_key = {(o.member_id, o.person_id, o.user_id): o for o in old}
        for row in rows:
            prior = old_by_key.get((row.member_id, row.person_id, row.user_id))
            if prior is not None:
                row.share_token = prior.share_token
                row.settled_at = prior.settled_at
        await session.execute(
            sa_delete(SplitParticipant).where(SplitParticipant.split_id == split.id)
        )
        await session.flush()
    split.group_id = group.id if group else None
    split.receipt_id = receipt.id if receipt else None
    split.description = description[:200]
    split.total = total
    split.currency = currency
    split.spent_at = spent_at
    split.mode = data.mode
    split.line_items = items
    _set_repeat(split, "" if receipt else data.repeat)
    await session.flush()
    for row in rows:
        row.split_id = split.id
        session.add(row)
    await session.flush()

    if receipt is not None:
        await set_receipt_share(session, receipt, split.id, mine.share if mine else Decimal("0"))
    await _log_and_notify(session, split, rows, user, before)
    return split


def _mode_inputs(
    mode: str, amount: str | None, weight: str | None
) -> tuple[Decimal | None, Decimal | None]:
    """A person's input for the split's mode: an exact amount, or a weight."""
    if mode == "custom":
        return _money(amount, "amount"), None
    if mode == "shares":
        return None, _weight(weight)
    if mode == "percent":
        return None, _weight(weight) or Decimal("0")
    return None, None


def _set_payers(
    rows: list[SplitParticipant],
    total: Decimal,
    paid: list[str | None],
    *,
    default: SplitParticipant | None,
    required: object,
) -> None:
    """Who paid what. Several payers: their amounts must add up to the total.
    One payer (or none given): they paid it all; by default whoever splits it."""
    if any(v not in (None, "") for v in paid):
        for row, value in zip(rows, paid, strict=True):
            row.paid = _money(value or "0", "amount paid")
            row.is_payer = row.paid > 0
        if sum(r.paid for r in rows) != total:
            raise _bad(f"What everyone paid must add up to {total:.2f}.")
        return
    payers = [r for r in rows if r.is_payer]
    if len(payers) > 1:
        raise _bad("Enter how much each person paid.")
    if not payers:
        if default is not None:
            default.is_payer = True
        elif required:
            raise _bad("Choose who paid.")
    for row in rows:
        row.paid = total if row.is_payer else None


def _set_shares(rows: list[SplitParticipant], total: Decimal, mode: str, items: list[dict]) -> None:
    try:
        shares = compute_shares(
            total,
            mode,
            [ShareInput(r.item_indexes or [], r.custom_amount, r.weight) for r in rows],
            [Decimal(str(i.get("price", "0"))) for i in items],
        )
    except SplitError as exc:
        raise _bad(str(exc)) from exc
    for row, share in zip(rows, shares, strict=True):
        row.share = share


def _set_repeat(split: Split, repeat: str) -> None:
    if repeat != split.repeat or (repeat and split.next_at is None):
        split.repeat = repeat
        split.next_at = next_date(split.spent_at, repeat) if repeat else None


def next_date(day: date, repeat: str) -> date:
    if repeat == "weekly":
        return day + timedelta(days=7)
    month = day.month % 12 + 1
    year = day.year + (day.month == 12)
    last = calendar.monthrange(year, month)[1]
    return date(year, month, min(day.day, last))


async def adjust_split(
    session: AsyncSession, user: User, split: Split, data: SplitAdjustIn
) -> Split:
    """An edit by anyone on the expense: amounts, who paid, how it's divided
    (and the description, amount and date if it isn't a receipt's). Caller
    commits."""
    rows = await _participants(session, split.id)
    by_id = {r.id: r for r in rows}
    if {p.id for p in data.participants} != set(by_id) or len(data.participants) != len(rows):
        raise _bad("Only the person who added it can change who's on it.")
    before = _snapshot(split, rows)

    receipt = await session.get(Receipt, split.receipt_id) if split.receipt_id else None
    if receipt is None:
        if data.description is not None:
            if not data.description.strip():
                raise _bad("Add a description.")
            split.description = data.description.strip()[:200]
        if data.total is not None:
            split.total = _money(data.total, "total")
        if data.date:
            try:
                split.spent_at = date.fromisoformat(data.date)
            except ValueError as exc:
                raise _bad("Invalid date.") from exc

    ordered = [by_id[p.id] for p in data.participants]
    for row, p in zip(ordered, data.participants, strict=True):
        row.is_payer = p.is_payer
        row.item_indexes = sorted(set(p.item_indexes))
        row.custom_amount, row.weight = _mode_inputs(data.mode, p.amount, p.weight)
    split.mode = data.mode
    paid = [p.paid for p in data.participants]
    _set_payers(ordered, split.total, paid, default=None, required=True)
    _set_shares(ordered, split.total, data.mode, list(split.line_items or []))
    await session.flush()

    if receipt is not None:
        owner_row = next((r for r in rows if r.user_id == receipt.user_id), None)
        await set_receipt_share(
            session, receipt, split.id, owner_row.share if owner_row else Decimal("0")
        )
    await _log_and_notify(session, split, rows, user, before)
    return split


# ─────────────────────────── history ───────────────────────────

_MODE_NAMES = {
    "even": "evenly",
    "items": "by item",
    "shares": "by shares",
    "percent": "by percentage",
    "custom": "by exact amounts",
}


def _snapshot(split: Split, rows: list[SplitParticipant]) -> dict:
    return {
        "description": split.description,
        "total": split.total,
        "date": split.spent_at,
        "mode": split.mode,
        "people": {
            r.member_id or r.person_id or r.user_id or r.display_name: (
                r.display_name,
                r.share,
                r.paid or Decimal("0"),
            )
            for r in rows
        },
    }


def _changes(before: dict, after: dict, currency: str) -> list[str]:
    """What an edit changed, in words."""

    def money(value: Decimal) -> str:
        return _money_text(value, currency)

    out: list[str] = []
    if before["description"] != after["description"]:
        out.append(f'renamed it "{after["description"]}"')
    if before["total"] != after["total"]:
        out.append(f"changed the total from {money(before['total'])} to {money(after['total'])}")
    if before["date"] != after["date"]:
        out.append(f"moved it to {after['date'].strftime('%b %-d')}")
    if before["mode"] != after["mode"]:
        out.append(f"now splits it {_MODE_NAMES.get(after['mode'], after['mode'])}")
    old, new = before["people"], after["people"]
    for key in new.keys() - old.keys():
        out.append(f"added {new[key][0]}")
    for key in old.keys() - new.keys():
        out.append(f"removed {old[key][0]}")
    paid_before = {k: v[2] for k, v in old.items() if v[2]}
    paid_after = {k: v[2] for k, v in new.items() if v[2]}
    if paid_before != paid_after:
        if len(paid_after) > 1:
            names = [f"{new[k][0]} {money(v)}" for k, v in paid_after.items()]
        else:
            names = [new[k][0] for k in paid_after]
        out.append(f"now paid by {', '.join(names)}")
    for key in new.keys() & old.keys():
        if old[key][1] != new[key][1]:
            out.append(f"{new[key][0]}'s share {money(old[key][1])} → {money(new[key][1])}")
    return out


async def publish_split(session: AsyncSession, split: Split) -> None:
    """Wake the apps of everyone who sees this expense: the people on it and,
    for a group expense, the whole group (their balances move)."""
    ids = set(
        await session.scalars(
            select(SplitParticipant.user_id).where(SplitParticipant.split_id == split.id)
        )
    )
    if split.group_id is not None:
        await publish_group(session, split.group_id, ids)
    else:
        await realtime.publish(session, ids | {split.owner_user_id})


async def publish_group(
    session: AsyncSession, group_id: uuid.UUID, also: set | None = None
) -> None:
    members = await session.scalars(
        select(GroupMember.user_id).where(GroupMember.group_id == group_id)
    )
    await realtime.publish(session, set(members) | (also or set()))


async def log_event(session: AsyncSession, split: Split, actor: User | None, text: str) -> None:
    await session.flush()
    await publish_split(session, split)
    session.add(
        SplitEvent(
            split_id=split.id,
            user_id=actor.id if actor else None,
            actor_name=(display_name_for(actor) if actor else "Tally")[:120],
            text=text[:1000],
        )
    )


async def _log_and_notify(
    session: AsyncSession,
    split: Split,
    rows: list[SplitParticipant],
    actor: User,
    before: dict | None,
) -> None:
    """Record what happened in the expense's history, and tell the people on it."""
    accounts = {r.user_id for r in rows}
    link = f"{get_settings().public_web_url}/groups"
    if before is None:
        total = _money_text(split.total, split.currency)
        await log_event(session, split, actor, f"added it ({total})")
        for row in rows:
            if row.user_id and row.user_id != actor.id:
                await activity.notify(
                    session,
                    [row.user_id],
                    actor,
                    "expense_added",
                    f'added "{split.description}": your share is '
                    f"{_money_text(row.share, split.currency)}",
                    split_id=split.id,
                    group_id=split.group_id,
                    link=link,
                )
        return
    changes = _changes(before, _snapshot(split, rows), split.currency)
    if not changes:
        return
    text = "; ".join(changes)
    await log_event(session, split, actor, text)
    await activity.notify(
        session,
        accounts,
        actor,
        "expense_edited",
        f'changed "{split.description}": {text}',
        split_id=split.id,
        group_id=split.group_id,
    )


def _money_text(value: Decimal, currency: str) -> str:
    if currency in ("CAD", "USD", "AUD", "NZD"):
        return f"${value:,.2f}"
    return f"{value:,.2f} {currency}"


async def set_receipt_share(
    session: AsyncSession, receipt: Receipt, split_id: uuid.UUID | None, share: Decimal | None
) -> None:
    """Record the owner's share on the receipt and make it their spending
    (the expense row); `None` restores the full total."""
    receipt.split_id = split_id
    receipt.my_share = share
    expense = await session.scalar(select(Expense).where(Expense.receipt_id == receipt.id))
    if expense is not None:
        expense.amount = share if share is not None else receipt.total


async def recompute_receipt_split(session: AsyncSession, receipt: Receipt) -> None:
    """After a split receipt's total or items change, recompute the shares
    from the split's own rule and update the owner's spending."""
    split = await session.scalar(select(Split).where(Split.receipt_id == receipt.id))
    if split is None:
        return
    rows = await _participants(session, split.id)
    items = list(receipt.line_items or [])
    mode = split.mode
    if mode == "custom" and sum((r.custom_amount or 0) for r in rows) != receipt.total:
        mode = "even"  # fixed amounts no longer fit the new total
    if mode == "items":
        for r in rows:
            r.item_indexes = [i for i in (r.item_indexes or []) if i < len(items)]
    try:
        shares = compute_shares(
            receipt.total,
            mode,
            [ShareInput(r.item_indexes or [], r.custom_amount, r.weight) for r in rows],
            [Decimal(str(i.get("price", "0"))) for i in items],
        )
    except SplitError:
        return
    before = _snapshot(split, rows)
    for r, share in zip(rows, shares, strict=True):
        r.share = share
    # Who paid follows the new total: one payer paid it all, several keep
    # their proportions.
    payers = [r for r in rows if r.paid]
    if len(payers) == 1:
        payers[0].paid = receipt.total
    elif payers:
        old_total = sum(r.paid for r in payers)
        cents = _allocate_cents(receipt.total, [r.paid / old_total for r in payers])
        for r, amount in zip(payers, cents, strict=True):
            r.paid = amount
    split.mode = mode
    split.total = receipt.total
    split.line_items = items
    split.description = (receipt.merchant or split.description)[:200]
    if receipt.purchased_at:
        split.spent_at = receipt.purchased_at
    mine = next((r for r in rows if r.user_id == receipt.user_id), None)
    await set_receipt_share(session, receipt, split.id, mine.share if mine else Decimal("0"))
    owner = await session.get(User, receipt.user_id)
    if owner is not None:
        await _log_and_notify(session, split, rows, owner, before)


def _allocate_cents(total: Decimal, weights: list[Decimal]) -> list[Decimal]:
    from fractions import Fraction

    from app.services.splits import _allocate, _cents, _decimal

    cents = _cents(total)
    exact = [Fraction(cents) * Fraction(w) for w in weights]
    return [_decimal(c) for c in _allocate(cents, exact)]


async def delete_split(session: AsyncSession, split: Split, actor: User | None = None) -> None:
    """Delete a split; a split receipt goes back to counting in full. The
    people on it hear about it (when `actor` deleted it by hand)."""
    if split.receipt_id is not None:
        receipt = await session.get(Receipt, split.receipt_id)
        if receipt is not None:
            await set_receipt_share(session, receipt, None, None)
    rows = await _participants(session, split.id)
    await publish_split(session, split)
    if actor is not None:
        await activity.notify(
            session,
            {r.user_id for r in rows},
            actor,
            "expense_deleted",
            f'deleted "{split.description}"',
            group_id=split.group_id,
        )
    await session.execute(sa_delete(SplitEvent).where(SplitEvent.split_id == split.id))
    await session.execute(sa_delete(SplitComment).where(SplitComment.split_id == split.id))
    await session.execute(sa_delete(SplitParticipant).where(SplitParticipant.split_id == split.id))
    await session.execute(sa_delete(Split).where(Split.id == split.id))


async def split_out(
    session: AsyncSession,
    split: Split,
    viewer: User,
    rows: list[SplitParticipant] | None = None,
    members: dict[uuid.UUID, GroupMember] | None = None,
) -> SplitOut:
    if rows is None:
        rows = await _participants(session, split.id)
    if members is None and split.group_id is not None:
        members = {m.id: m for m in await _members(session, split.group_id)}

    def is_me(r: SplitParticipant) -> bool:
        if r.user_id == viewer.id:
            return True
        member = (members or {}).get(r.member_id) if r.member_id else None
        return member is not None and member.user_id == viewer.id

    mine = next((r for r in rows if is_me(r)), None)
    return SplitOut(
        id=split.id,
        receipt_id=split.receipt_id,
        group_id=split.group_id,
        description=split.description,
        total=f"{split.total:.2f}",
        currency=split.currency,
        date=split.spent_at.isoformat(),
        mode=split.mode,
        items=[ExtractionItemOut(**i) for i in (split.line_items or [])],
        participants=[
            ParticipantOut(
                id=r.id,
                display_name=(members or {}).get(r.member_id).display_name
                if r.member_id and r.member_id in (members or {})
                else r.display_name,
                member_id=r.member_id,
                person_id=r.person_id,
                is_me=is_me(r),
                is_payer=r.is_payer,
                item_indexes=list(r.item_indexes or []),
                amount=f"{r.custom_amount:.2f}" if r.custom_amount is not None else None,
                weight=f"{r.weight.normalize():f}" if r.weight is not None else None,
                paid=f"{r.paid:.2f}" if r.paid is not None else None,
                share=f"{r.share:.2f}",
                settled=r.settled_at is not None,
                share_url=share_url(r.share_token),
            )
            for r in rows
        ],
        my_share=f"{mine.share:.2f}" if mine else None,
        is_owner=split.owner_user_id == viewer.id,
        # Seeing it means being on it (or in its group): that's enough to edit.
        can_edit=True,
        repeat=split.repeat or "",
        next_at=split.next_at.isoformat() if split.next_at else None,
    )


async def require_split(session: AsyncSession, split_id: uuid.UUID, user: User) -> Split:
    """A split the caller may see: their own, one they're on, or one in a
    group they're in."""
    split = await session.get(Split, split_id)
    if split is not None and split.owner_user_id != user.id:
        visible = await session.scalar(
            select(SplitParticipant.id).where(
                SplitParticipant.split_id == split.id, SplitParticipant.user_id == user.id
            )
        ) or (
            split.group_id is not None
            and await session.scalar(
                select(GroupMember.id).where(
                    GroupMember.group_id == split.group_id, GroupMember.user_id == user.id
                )
            )
        )
        if not visible:
            split = None
    if split is None:
        raise _bad("Split not found.", status.HTTP_404_NOT_FOUND)
    return split


# ─────────────────────────── groups: views ───────────────────────────


async def group_ledger(
    session: AsyncSession, group_id: uuid.UUID
) -> tuple[list[Split], dict[uuid.UUID, list[SplitParticipant]], list[Settlement]]:
    splits = list(
        await session.scalars(
            select(Split)
            .where(Split.group_id == group_id)
            .order_by(Split.spent_at.desc(), Split.created_at.desc())
        )
    )
    rows: dict[uuid.UUID, list[SplitParticipant]] = {s.id: [] for s in splits}
    if splits:
        for r in await session.scalars(
            select(SplitParticipant)
            .where(SplitParticipant.split_id.in_(list(rows)))
            .order_by(SplitParticipant.position, SplitParticipant.created_at)
        ):
            rows[r.split_id].append(r)
    settlements = list(
        await session.scalars(
            select(Settlement)
            .where(Settlement.group_id == group_id)
            .order_by(Settlement.created_at.desc())
        )
    )
    return splits, rows, settlements


def _paid(row: SplitParticipant, split: Split) -> Decimal:
    """What this person put in (rows from before `paid`: the payer paid all)."""
    if row.paid is not None:
        return row.paid
    return split.total if row.is_payer else Decimal("0")


def group_payments(
    group: Group,
    splits: list[Split],
    rows: dict[uuid.UUID, list[SplitParticipant]],
    settlements: list[Settlement],
) -> list[tuple[uuid.UUID, uuid.UUID, Decimal]]:
    """Who should pay whom to settle the group: the fewest payments when
    simplify debts is on (A owes B, B owes C → A pays C), otherwise who owes
    whom directly from the expenses."""
    if group.simplify_debts:
        return suggest_payments(_net(splits, rows, settlements))
    return direct_debts(
        [
            [
                (r.member_id, r.share, _paid(r, s), r.settled_at is not None)
                for r in rows[s.id]
                if r.member_id
            ]
            for s in splits
        ],
        [(x.from_member_id, x.to_member_id, x.amount) for x in settlements],
    )


def _net(
    splits: list[Split],
    rows: dict[uuid.UUID, list[SplitParticipant]],
    settlements: list[Settlement],
) -> dict[uuid.UUID, Decimal]:
    ledger = []
    for s in splits:
        payer = next((r for r in rows[s.id] if r.is_payer), None)
        ledger.append(
            SplitLedger(
                payer.member_id if payer else None,
                [(r.member_id, r.share) for r in rows[s.id]],
                paid=[(r.member_id, _paid(r, s)) for r in rows[s.id] if _paid(r, s)],
            )
        )
    recorded = [(x.from_member_id, x.to_member_id, x.amount) for x in settlements]
    return balances(ledger, recorded + _ticked_shares(splits, rows))


def _ticked_shares(
    splits: list[Split], rows: dict[uuid.UUID, list[SplitParticipant]]
) -> list[tuple[uuid.UUID, uuid.UUID, Decimal]]:
    """A share ticked paid on a group expense counts as that person paying it
    to whoever paid the bill (split between several payers by what each put in)."""
    out: list[tuple[uuid.UUID, uuid.UUID, Decimal]] = []
    for s in splits:
        payers = [r for r in rows[s.id] if r.member_id and _paid(r, s) > 0]
        if not payers:
            continue
        for r in rows[s.id]:
            if r.settled_at is None or r.member_id is None or r in payers:
                continue
            if len(payers) == 1:
                out.append((r.member_id, payers[0].member_id, r.share))
                continue
            put_in = sum(_paid(p, s) for p in payers)
            parts = _allocate_cents(r.share, [_paid(p, s) / put_in for p in payers])
            out += [(r.member_id, p.member_id, a) for p, a in zip(payers, parts, strict=True)]
    return out


async def group_summary(session: AsyncSession, group: Group, user: User) -> GroupSummaryOut:
    members = await _members(session, group.id)
    me = next((m for m in members if m.user_id == user.id), None)
    splits, rows, settlements = await group_ledger(session, group.id)
    net = _net(splits, rows, settlements)
    return GroupSummaryOut(
        id=group.id,
        name=group.name,
        currency=group.currency,
        member_count=len(members),
        my_balance=f"{net.get(me.id, Decimal('0')) if me else Decimal('0'):.2f}",
        invite_url=invite_url(group.invite_token),
        is_owner=group.owner_user_id == user.id,
        simplify_debts=group.simplify_debts,
    )


async def group_detail(session: AsyncSession, group: Group, user: User) -> GroupDetailOut:
    members = await _members(session, group.id)
    by_id = {m.id: m for m in members}
    splits, rows, settlements = await group_ledger(session, group.id)
    net = _net(splits, rows, settlements)
    me = next((m for m in members if m.user_id == user.id), None)
    ids = [m.user_id for m in members if m.user_id]
    accounts = (
        {u.id: u for u in await session.scalars(select(User).where(User.id.in_(ids)))}
        if ids
        else {}
    )
    return GroupDetailOut(
        id=group.id,
        name=group.name,
        currency=group.currency,
        member_count=len(members),
        my_balance=f"{net.get(me.id, Decimal('0')) if me else Decimal('0'):.2f}",
        invite_url=invite_url(group.invite_token),
        is_owner=group.owner_user_id == user.id,
        members=[
            MemberOut(
                id=m.id,
                display_name=m.display_name,
                is_me=m.user_id == user.id,
                has_account=m.user_id is not None,
                balance=f"{net.get(m.id, Decimal('0')):.2f}",
                pay_to=_pay_to(accounts.get(m.user_id)),
                email=m.email if m.user_id is None else None,
                invited_at=_iso_or_none(m.invited_at),
                can_email=bool(m.email) and m.user_id is None and get_settings().email_configured,
            )
            for m in members
        ],
        simplify_debts=group.simplify_debts,
        payments=[
            PaymentOut(from_member_id=a, to_member_id=b, amount=f"{amount:.2f}")
            for a, b, amount in group_payments(group, splits, rows, settlements)
        ],
        splits=[await split_out(session, s, user, rows[s.id], by_id) for s in splits],
        settlements=[
            SettlementOut(
                id=x.id,
                from_member_id=x.from_member_id,
                to_member_id=x.to_member_id,
                amount=f"{x.amount:.2f}",
                note=x.note,
                date=(x.created_at or datetime.now()).date().isoformat(),
            )
            for x in settlements
        ],
    )


def _iso_or_none(moment: datetime | None) -> str | None:
    if moment is None:
        return None
    return (moment if moment.tzinfo else moment.replace(tzinfo=UTC)).isoformat()


def member_invite_url(group: Group, member: GroupMember) -> str:
    """The group's invite with this person's name already chosen."""
    return f"{invite_url(group.invite_token)}?member={member.id}"


def _pay_to(user: User | None) -> PayDetails | None:
    if user is None or not user.interac:
        return None
    return PayDetails(interac=user.interac)


async def member_owes(session: AsyncSession, group: Group, debtor_id, creditor_id) -> Decimal:
    """What one member owes another in the group's settle-up payments."""
    splits, rows, settlements = await group_ledger(session, group.id)
    return sum(
        (
            amount
            for a, b, amount in group_payments(group, splits, rows, settlements)
            if a == debtor_id and b == creditor_id
        ),
        Decimal("0"),
    )


async def member_in_use(session: AsyncSession, member_id: uuid.UUID) -> bool:
    used = await session.scalar(
        select(SplitParticipant.id).where(SplitParticipant.member_id == member_id).limit(1)
    )
    if used is None:
        used = await session.scalar(
            select(Settlement.id)
            .where(
                (Settlement.from_member_id == member_id) | (Settlement.to_member_id == member_id)
            )
            .limit(1)
        )
    return used is not None


async def delete_group(session: AsyncSession, group: Group) -> None:
    """Delete a group with its splits and settlements; split receipts go back
    to counting in full for their owners."""
    for split in list(await session.scalars(select(Split).where(Split.group_id == group.id))):
        await delete_split(session, split)
    await session.execute(sa_delete(Settlement).where(Settlement.group_id == group.id))
    await session.execute(sa_delete(GroupMember).where(GroupMember.group_id == group.id))
    await session.execute(sa_delete(Group).where(Group.id == group.id))
