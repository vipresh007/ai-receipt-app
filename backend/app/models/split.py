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
