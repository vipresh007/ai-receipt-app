"""Saving splits and reading groups — the persistence side of docs/SPLITS.md.

The arithmetic lives in `services/splits.py`; this module turns requests into
rows, keeps a split receipt's `my_share` and expense row in step with the
split, and assembles group views (members, balances, settle-up payments).
"""

import secrets
import uuid
from datetime import date, datetime
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
    SplitParticipant,
    User,
)
from app.schemas.receipt import ExtractionItemOut
from app.schemas.split import (
    GroupDetailOut,
    GroupSummaryOut,
    MemberOut,
    ParticipantOut,
    PaymentOut,
    SettlementOut,
    SplitIn,
    SplitOut,
)
from app.services.splits import ShareInput, SplitError, SplitLedger, balances, compute_shares
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
        custom = _money(p.amount, "amount") if data.mode == "custom" else None
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
                share_token=new_token(),
            )
        )

    if sum(1 for r in rows if r.user_id == user.id) > 1:
        raise _bad("You're in this split twice.")
    payers = [r for r in rows if r.is_payer]
    if len(payers) > 1:
        raise _bad("Only one person can have paid.")
    if not payers:
        # Default: whoever is splitting it paid.
        mine = next((r for r in rows if r.user_id == user.id), None)
        if mine is not None:
            mine.is_payer = True
        elif group is not None:
            raise _bad("Choose who paid.")

    try:
        shares = compute_shares(
            total,
            data.mode,
            [ShareInput(r.item_indexes, r.custom_amount) for r in rows],
            [Decimal(str(i.get("price", "0"))) for i in items],
        )
    except SplitError as exc:
        raise _bad(str(exc)) from exc
    for row, share in zip(rows, shares, strict=True):
        row.share = share

    if split is None:
        split = Split(owner_user_id=user.id)
        session.add(split)
    else:
        # Keep each person's link when they're still on the split.
        old = await _participants(session, split.id)
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
    await session.flush()
    for row in rows:
        row.split_id = split.id
        session.add(row)
    await session.flush()

    if receipt is not None:
        mine = next((r for r in rows if r.user_id == user.id), None)
        await set_receipt_share(session, receipt, split.id, mine.share if mine else Decimal("0"))
    return split


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
            [ShareInput(r.item_indexes or [], r.custom_amount) for r in rows],
            [Decimal(str(i.get("price", "0"))) for i in items],
        )
    except SplitError:
        return
    for r, share in zip(rows, shares, strict=True):
        r.share = share
    split.mode = mode
    split.total = receipt.total
    split.line_items = items
    split.description = (receipt.merchant or split.description)[:200]
    if receipt.purchased_at:
        split.spent_at = receipt.purchased_at
    mine = next((r for r in rows if r.user_id == receipt.user_id), None)
    await set_receipt_share(session, receipt, split.id, mine.share if mine else Decimal("0"))


async def delete_split(session: AsyncSession, split: Split) -> None:
    """Delete a split; a split receipt goes back to counting in full."""
    if split.receipt_id is not None:
        receipt = await session.get(Receipt, split.receipt_id)
        if receipt is not None:
            await set_receipt_share(session, receipt, None, None)
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
                share=f"{r.share:.2f}",
                settled=r.settled_at is not None,
                share_url=share_url(r.share_token),
            )
            for r in rows
        ],
        my_share=f"{mine.share:.2f}" if mine else None,
        is_owner=split.owner_user_id == viewer.id,
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
            )
        )
    return balances(ledger, [(x.from_member_id, x.to_member_id, x.amount) for x in settlements])


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
    )


async def group_detail(session: AsyncSession, group: Group, user: User) -> GroupDetailOut:
    members = await _members(session, group.id)
    by_id = {m.id: m for m in members}
    splits, rows, settlements = await group_ledger(session, group.id)
    net = _net(splits, rows, settlements)
    me = next((m for m in members if m.user_id == user.id), None)
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
            )
            for m in members
        ],
        payments=[
            PaymentOut(from_member_id=a, to_member_id=b, amount=f"{amount:.2f}")
            for a, b, amount in suggest_payments(net)
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
