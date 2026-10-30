"""People you split with outside groups: their running balance, payments,
and invites (docs/SPLITS.md).

A person starts as a name on your list. Their invite link (shared by you, or
emailed by Tally) lets them sign in and accept, which links the person to
their account: splits you shared show up for them, and they get a person of
their own pointing back at you. The balance between you two is the same
whichever side looks at it, just negated.
"""

import html
import re
import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from fractions import Fraction

from fastapi import HTTPException, status
from sqlalchemy import delete as sa_delete
from sqlalchemy import func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models import Group, GroupMember, Person, PersonPayment, Split, SplitParticipant, User
from app.schemas.split import (
    PayDetails,
    PersonDetailOut,
    PersonGroupBalance,
    PersonOut,
    PersonPaymentOut,
)
from app.services import activity, split_store
from app.services.split_store import display_name_for, new_token, split_out
from app.services.splits import owed_between

_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

# Invites Tally emails: one per person per 10 minutes, 20 per sender per day.
INVITE_COOLDOWN = timedelta(minutes=10)
DAILY_INVITES = 20


def invite_url(token: str) -> str:
    return f"{get_settings().public_web_url}/p/{token}"


def clean_email(value: str | None) -> str | None:
    """Normalized address, `None` for blank; 422 if it isn't one."""
    email = (value or "").strip().lower()
    if not email:
        return None
    if not _EMAIL.match(email):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "That email doesn't look right.")
    return email


def _aware(moment: datetime | None) -> datetime | None:
    # SQLite hands back naive datetimes; Postgres aware ones.
    if moment is not None and moment.tzinfo is None:
        return moment.replace(tzinfo=UTC)
    return moment


async def require_person(session: AsyncSession, person_id: uuid.UUID, user: User) -> Person:
    person = await session.get(Person, person_id)
    if person is None or person.owner_user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Person not found.")
    return person


# ─────────────────────────── ledger ───────────────────────────


def _is_them(row: SplitParticipant, person: Person) -> bool:
    return row.person_id == person.id or (
        person.user_id is not None and row.user_id == person.user_id
    )


async def shared_splits(
    session: AsyncSession, viewer: User, person: Person
) -> tuple[list[Split], dict[uuid.UUID, list[SplitParticipant]]]:
    """One-off splits that both you and this person are on, newest first."""
    them = SplitParticipant.person_id == person.id
    if person.user_id is not None:
        them = or_(them, SplitParticipant.user_id == person.user_id)
    splits = list(
        await session.scalars(
            select(Split)
            .where(
                Split.group_id.is_(None),
                Split.id.in_(select(SplitParticipant.split_id).where(them)),
                Split.id.in_(
                    select(SplitParticipant.split_id).where(SplitParticipant.user_id == viewer.id)
                ),
            )
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
    return splits, rows


async def payments(
    session: AsyncSession, viewer: User, person: Person
) -> list[tuple[PersonPayment, bool, bool]]:
    """Payments between you and this person: (row, you paid, recorded by you).
    Includes the ones they recorded on their side once they've joined."""
    found: list[tuple[PersonPayment, bool, bool]] = [
        (p, p.from_owner, True)
        for p in await session.scalars(
            select(PersonPayment).where(
                PersonPayment.owner_user_id == viewer.id, PersonPayment.person_id == person.id
            )
        )
    ]
    if person.user_id is not None:
        mirrors = select(Person.id).where(
            Person.owner_user_id == person.user_id, Person.user_id == viewer.id
        )
        found += [
            (p, not p.from_owner, False)
            for p in await session.scalars(
                select(PersonPayment).where(
                    PersonPayment.owner_user_id == person.user_id,
                    PersonPayment.person_id.in_(mirrors),
                )
            )
        ]
    found.sort(key=lambda x: x[0].created_at, reverse=True)
    return found


def net_balance(
    viewer: User,
    person: Person,
    splits: list[Split],
    rows: dict[uuid.UUID, list[SplitParticipant]],
    paid: list[tuple[PersonPayment, bool, bool]],
) -> Decimal:
    """What they owe you outside groups (negative: what you owe them): on
    each expense you're both on, whoever's short owes whoever's over (see
    `splits.owed_between`), less shares ticked paid, plus payments between you."""
    total = Fraction(0)
    for split in splits:
        me = next((r for r in rows[split.id] if r.user_id == viewer.id), None)
        them = next((r for r in rows[split.id] if r is not me and _is_them(r, person)), None)
        if me is None or them is None:
            continue
        entries = [
            (r.id, r.share, split_store._paid(r, split), r.settled_at is not None)
            for r in rows[split.id]
        ]
        total += owed_between(entries, me.id, them.id)
    for payment, you_paid, _ in paid:
        total += Fraction(payment.amount) if you_paid else -Fraction(payment.amount)
    return _round(total)


def _round(value: Fraction) -> Decimal:
    return (Decimal(value.numerator) / Decimal(value.denominator)).quantize(Decimal("0.01"))


async def group_balances(
    session: AsyncSession, viewer: User, person: Person
) -> list[tuple[Group, Decimal]]:
    """Once they have an account: what they owe you in each group you're both
    in, as that group settles up (simplified or direct, its setting)."""
    if person.user_id is None:
        return []
    mine = {
        m.group_id: m.id
        for m in await session.scalars(select(GroupMember).where(GroupMember.user_id == viewer.id))
    }
    theirs = {
        m.group_id: m.id
        for m in await session.scalars(
            select(GroupMember).where(GroupMember.user_id == person.user_id)
        )
    }
    out: list[tuple[Group, Decimal]] = []
    for group_id in sorted(mine.keys() & theirs.keys(), key=str):
        group = await session.get(Group, group_id)
        if group is None:
            continue
        me, them = mine[group_id], theirs[group_id]
        splits, rows, settlements = await split_store.group_ledger(session, group_id)
        # Follow the group's own settle-up, so both screens agree.
        payments = split_store.group_payments(group, splits, rows, settlements)
        between = sum(
            (amount for a, b, amount in payments if a == them and b == me), Decimal("0")
        ) - sum((amount for a, b, amount in payments if a == me and b == them), Decimal("0"))
        out.append((group, between))
    return out


async def balance(
    session: AsyncSession, viewer: User, person: Person
) -> tuple[Decimal, Decimal, list[tuple[Group, Decimal]], str]:
    """(overall, outside groups, per group, currency) between you two."""
    splits, rows = await shared_splits(session, viewer, person)
    paid = await payments(session, viewer, person)
    outside = net_balance(viewer, person, splits, rows, paid)
    groups = await group_balances(session, viewer, person)
    currency = splits[0].currency if splits else (groups[0][0].currency if groups else "CAD")
    return outside + sum((b for _, b in groups), Decimal("0")), outside, groups, currency


async def person_out(
    session: AsyncSession, viewer: User, person: Person, *, detail: bool = False
) -> PersonOut | PersonDetailOut:
    splits, rows = await shared_splits(session, viewer, person)
    paid = await payments(session, viewer, person)
    outside = net_balance(viewer, person, splits, rows, paid)
    groups = await group_balances(session, viewer, person)
    them = await session.get(User, person.user_id) if person.user_id else None
    currency = splits[0].currency if splits else (groups[0][0].currency if groups else "CAD")
    fields = {
        "id": person.id,
        "name": person.display_name,
        "email": person.email,
        "has_account": person.user_id is not None,
        "invite_url": invite_url(person.invite_token),
        "invited_at": _aware(person.invited_at).isoformat() if person.invited_at else None,
        "balance": f"{outside + sum((b for _, b in groups), Decimal('0')):.2f}",
        "outside_groups": f"{outside:.2f}",
        "group_balances": [
            PersonGroupBalance(group_id=g.id, name=g.name, balance=f"{b:.2f}") for g, b in groups
        ],
        "currency": currency,
        "can_email": bool(person.email) and get_settings().email_configured,
        "pay_to": pay_details(them),
        "last_shared": splits[0].spent_at.isoformat() if splits else None,
    }
    if not detail:
        return PersonOut(**fields)
    return PersonDetailOut(
        **fields,
        splits=[await split_out(session, s, viewer, rows[s.id]) for s in splits],
        payments=[
            PersonPaymentOut(
                id=p.id,
                you_paid=you_paid,
                amount=f"{p.amount:.2f}",
                note=p.note,
                date=_aware(p.created_at).date().isoformat(),
                can_delete=mine,
            )
            for p, you_paid, mine in paid
        ],
    )


def pay_details(user: User | None) -> PayDetails | None:
    """How to pay this person back, if they've said."""
    if user is None or not user.interac:
        return None
    return PayDetails(interac=user.interac)


# ─────────────────────────── invites ───────────────────────────


async def claim(session: AsyncSession, person: Person, user: User) -> Person:
    """`user` accepts `person`'s invite: link them, and give them a person of
    their own for the inviter. Returns that one. Caller commits."""
    if person.owner_user_id == user.id:
        raise HTTPException(status.HTTP_409_CONFLICT, "This is your own invite link.")
    if person.user_id not in (None, user.id):
        raise HTTPException(status.HTTP_409_CONFLICT, "Someone else already accepted this invite.")

    if person.user_id is None:
        # The inviter may already have you under another name: fold this one in.
        other = await session.scalar(
            select(Person).where(
                Person.owner_user_id == person.owner_user_id, Person.user_id == user.id
            )
        )
        if other is not None:
            await session.execute(
                update(SplitParticipant)
                .where(SplitParticipant.person_id == person.id)
                .values(person_id=other.id)
            )
            await session.execute(
                update(PersonPayment)
                .where(PersonPayment.person_id == person.id)
                .values(person_id=other.id)
            )
            await session.delete(person)
            person = other
        else:
            person.user_id = user.id
        # Their spots on the inviter's splits become theirs (where they're not
        # already on that split as themselves).
        await session.execute(
            update(SplitParticipant)
            .where(
                SplitParticipant.person_id == person.id,
                SplitParticipant.user_id.is_(None),
                SplitParticipant.split_id.not_in(
                    select(SplitParticipant.split_id).where(SplitParticipant.user_id == user.id)
                ),
            )
            .values(user_id=user.id)
        )

    mirror = await session.scalar(
        select(Person).where(
            Person.owner_user_id == user.id, Person.user_id == person.owner_user_id
        )
    )
    if mirror is None:
        inviter = await session.get(User, person.owner_user_id)
        mirror = Person(
            owner_user_id=user.id,
            display_name=display_name_for(inviter)[:120] if inviter else "Someone",
            user_id=person.owner_user_id,
            invite_token=new_token(),
        )
        session.add(mirror)
    await session.flush()
    await activity.notify(
        session, [person.owner_user_id], user, "joined", "accepted your invite", person_id=person.id
    )
    return mirror


async def link_invited_email(session: AsyncSession, user: User) -> None:
    """A new account with a verified email: accept every invite sent to it."""
    if not user.email_verified:
        return
    invited = list(
        await session.scalars(
            select(Person).where(
                func.lower(Person.email) == user.email,
                Person.user_id.is_(None),
                Person.owner_user_id != user.id,
            )
        )
    )
    for person in invited:
        await claim(session, person, user)


async def delete_person(session: AsyncSession, person: Person) -> None:
    """Remove from your list. Splits keep their name; payments go."""
    await session.execute(
        update(SplitParticipant)
        .where(SplitParticipant.person_id == person.id)
        .values(person_id=None)
    )
    await session.execute(sa_delete(PersonPayment).where(PersonPayment.person_id == person.id))
    await session.execute(sa_delete(Person).where(Person.id == person.id))


async def check_invite_allowed(session: AsyncSession, person: Person) -> None:
    now = datetime.now(UTC)
    last = _aware(person.invited_at)
    if last is not None and now - last < INVITE_COOLDOWN:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "An invite just went to them. Try again in a few minutes, or share the link.",
        )
    sent_today = await session.scalar(
        select(func.count(Person.id)).where(
            Person.owner_user_id == person.owner_user_id,
            Person.invited_at > now - timedelta(days=1),
        )
    )
    if (sent_today or 0) >= DAILY_INVITES:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "That's the most invite emails for today. You can still share the link.",
        )


def invite_email(inviter: str, person: Person, balance: Decimal, currency: str) -> dict:
    """Subject, plain text and HTML for an invite. `balance` is from the
    inviter's side (positive: the person owes them)."""
    inviter = inviter.strip()[:60] or "Someone"
    amount = f"{abs(balance):,.2f} {currency}"
    if balance > 0:
        standing = f"Right now you owe {inviter} {amount}."
    elif balance < 0:
        standing = f"Right now {inviter} owes you {amount}."
    else:
        standing = "You're all square right now."
    url = invite_url(person.invite_token)
    subject = f"{inviter} is sharing expenses with you on Tally"
    text = (
        f"Hi {person.display_name},\n\n"
        f"{inviter} uses Tally to keep track of what you two share. {standing}\n\n"
        f"See every expense and settle up here:\n{url}\n\n"
        "Tally is free on iPhone and the web. "
        f"You got this because {inviter} added your email. "
        "If you don't know them, ignore this email and nothing else will be sent.\n"
    )
    e = html.escape
    button = (
        "background:#8A5E0F;color:#fff;text-decoration:none;padding:12px 22px;"
        "border-radius:999px;font-weight:600;display:inline-block"
    )
    font = "font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif"
    body = "".join(
        [
            f'<div style="{font};max-width:520px;margin:0 auto;color:#1E2321">',
            f'<p style="font-size:16px">Hi {e(person.display_name)},</p>',
            f'<p style="font-size:16px">{e(inviter)} uses Tally to keep track of what you two',
            f" share. <strong>{e(standing)}</strong></p>",
            f'<p style="margin:28px 0"><a href="{e(url)}" style="{button}">',
            "See what you share</a></p>",
            '<p style="font-size:13px;color:#5B5F59">Tally is free on iPhone and the web.',
            f" You got this because {e(inviter)} added your email. If you don't know them,",
            " ignore this email and nothing else will be sent.</p></div>",
        ]
    )
    return {"subject": subject, "text": text, "html": body}
