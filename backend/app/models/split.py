"""Splits and groups — see docs/SPLITS.md.

Tally tracks who owes whom; it never moves money. Shares are always derived
by `services/splits.py` from the split's mode and inputs, never trusted from a
client.
"""

import uuid
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (
    JSON,
    Date,
    DateTime,
    ForeignKey,
    Numeric,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Group(Base):
    """A named set of people sharing expenses (a trip, housemates)."""

    __tablename__ = "groups"

    name: Mapped[str] = mapped_column(String(120))
    # Null once the creator deletes their account; the group lives on.
    owner_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    currency: Mapped[str] = mapped_column(String(3), default="CAD")
    invite_token: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    # Settle up with the fewest payments (A owes B, B owes C → A pays C), or
    # show who owes whom directly from the expenses.
    simplify_debts: Mapped[bool] = mapped_column(default=True)


class GroupMember(Base):
    """A person in a group: a Tally account, or just a name until that person
    joins through the invite link and claims it."""

    __tablename__ = "group_members"
    __table_args__ = (UniqueConstraint("group_id", "user_id", name="uq_group_member_user"),)

    group_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("groups.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    display_name: Mapped[str] = mapped_column(String(120))
    # Order in the group (members added in one request share a timestamp).
    position: Mapped[int] = mapped_column(default=0)
    reminded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    # Before they join: an address to email their invite to (and to match a
    # verified sign-up to this name).
    email: Mapped[str | None] = mapped_column(String(320), nullable=True)
    invited_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class Split(Base):
    """One expense divided between participants; optionally a receipt's, and
    optionally inside a group. `mode` is even | items | custom."""

    __tablename__ = "splits"

    owner_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    group_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("groups.id", ondelete="CASCADE"), nullable=True, index=True
    )
    receipt_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("receipts.id", ondelete="CASCADE"), nullable=True, unique=True
    )
    description: Mapped[str] = mapped_column(String(200), default="")
    total: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    currency: Mapped[str] = mapped_column(String(3), default="CAD")
    spent_at: Mapped[date] = mapped_column(Date)
    mode: Mapped[str] = mapped_column(String(10), default="even")
    # Repeating expenses (rent, a subscription): "" | weekly | monthly. Each
    # time `next_at` comes round a copy is added and `next_at` moves on.
    repeat: Mapped[str] = mapped_column(String(10), default="")
    next_at: Mapped[date | None] = mapped_column(Date, nullable=True, index=True)
    # Line items the split was computed from (a receipt's, or entered with a
    # manual split): [{"name": str, "price": "12.34", "quantity": 1}, ...]
    line_items: Mapped[list[dict]] = mapped_column(JSON, default=list)


class SplitParticipant(Base):
    __tablename__ = "split_participants"

    split_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("splits.id", ondelete="CASCADE"), index=True
    )
    # Set in group splits.
    member_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("group_members.id", ondelete="SET NULL"), nullable=True, index=True
    )
    # One-off splits: the saved person this is (see `Person`).
    person_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("people.id", ondelete="SET NULL"), nullable=True, index=True
    )
    # Set when the participant is a Tally account (always for the split's owner).
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    display_name: Mapped[str] = mapped_column(String(120))
    # Order as entered (participants are written together).
    position: Mapped[int] = mapped_column(default=0)
    is_payer: Mapped[bool] = mapped_column(default=False)
    # Inputs: line-item indexes (items mode) or a fixed amount (custom mode).
    item_indexes: Mapped[list[int]] = mapped_column(JSON, default=list)
    custom_amount: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    # Shares mode: parts of the total (2 and 3 → 2/5 and 3/5); percent mode: %.
    weight: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    # What this person paid toward the total (one payer: the whole total).
    paid: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    # Output, computed by services/splits.py.
    share: Mapped[Decimal] = mapped_column(Numeric(12, 2), default=Decimal("0"))
    # One-off splits: when this person's share was marked paid.
    settled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    # The participant's link (/s/<token>): a snapshot of this split, no account needed.
    share_token: Mapped[str] = mapped_column(String(64), unique=True, index=True)


class Settlement(Base):
    """'from_member paid to_member' inside a group."""

    __tablename__ = "settlements"

    group_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("groups.id", ondelete="CASCADE"), index=True
    )
    from_member_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("group_members.id", ondelete="CASCADE")
    )
    to_member_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("group_members.id", ondelete="CASCADE")
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    note: Mapped[str] = mapped_column(String(200), default="")
    created_by_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )


class Person(Base):
    """Someone you split with outside a group. Starts as just a name; an email
    can be added later. Linked to their account (`user_id`) once they open
    their invite link and sign in, after which they see what you share from
    their side (as a `Person` of their own pointing back at you)."""

    __tablename__ = "people"
    __table_args__ = (UniqueConstraint("owner_user_id", "user_id", name="uq_person_owner_user"),)

    owner_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    display_name: Mapped[str] = mapped_column(String(120))
    email: Mapped[str | None] = mapped_column(String(320), nullable=True)
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    # Their invite link (/p/<token>); shared by you, or emailed by Tally.
    invite_token: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    invited_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    reminded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class PersonPayment(Base):
    """Money that changed hands between you and a person, outside groups."""

    __tablename__ = "person_payments"

    owner_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    person_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("people.id", ondelete="CASCADE"), index=True
    )
    # True: you paid them. False: they paid you.
    from_owner: Mapped[bool] = mapped_column(default=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    note: Mapped[str] = mapped_column(String(200), default="")


class SplitComment(Base):
    """A note on an expense, visible to everyone who can see it."""

    __tablename__ = "split_comments"

    split_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("splits.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    author_name: Mapped[str] = mapped_column(String(120))
    body: Mapped[str] = mapped_column(String(1000))


class SplitEvent(Base):
    """One line of an expense's history: added, or what an edit changed."""

    __tablename__ = "split_events"

    split_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("splits.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    actor_name: Mapped[str] = mapped_column(String(120))
    text: Mapped[str] = mapped_column(String(1000))


class Activity(Base):
    """Something that happened that concerns `user_id` ("Sam added Dinner")."""

    __tablename__ = "activities"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    actor_name: Mapped[str] = mapped_column(String(120))
    # expense_added | expense_edited | expense_deleted | comment | payment |
    # reminder | joined | repeated
    kind: Mapped[str] = mapped_column(String(30))
    text: Mapped[str] = mapped_column(String(300))
    split_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    group_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    person_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
