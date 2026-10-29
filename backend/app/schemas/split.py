"""Request/response shapes for splits and groups (docs/SPLITS.md). Money is
decimal strings on the wire, like everywhere else."""

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

from app.schemas.receipt import ExtractionItemOut

Mode = Literal["even", "items", "custom"]


class ParticipantIn(BaseModel):
    """One person on a split: yourself (`is_me`), a group member (`member_id`),
    or just a name (one-off splits)."""

    is_me: bool = False
    member_id: UUID | None = None
    name: str = Field(default="", max_length=120)
    is_payer: bool = False
    item_indexes: list[int] = Field(default_factory=list, max_length=500)
    amount: str | None = None  # custom mode


class SplitIn(BaseModel):
    """Split a receipt (`receipt_id`) or a manual expense (description + total)."""

    receipt_id: UUID | None = None
    group_id: UUID | None = None
    description: str = Field(default="", max_length=200)
    total: str | None = None
    currency: str | None = Field(default=None, max_length=3)
    date: str | None = None  # YYYY-MM-DD
    mode: Mode = "even"
    items: list[ExtractionItemOut] = Field(default_factory=list, max_length=500)
    participants: list[ParticipantIn] = Field(min_length=1, max_length=50)


class ParticipantOut(BaseModel):
    id: UUID
    display_name: str
    member_id: UUID | None
    is_me: bool
    is_payer: bool
    item_indexes: list[int]
    amount: str | None
    share: str
    settled: bool
    share_url: str


class SplitOut(BaseModel):
    id: UUID
    receipt_id: UUID | None
    group_id: UUID | None
    description: str
    total: str
    currency: str
    date: str
    mode: Mode
    items: list[ExtractionItemOut]
    participants: list[ParticipantOut]
    my_share: str | None
    is_owner: bool


class SettledIn(BaseModel):
    settled: bool


# ─────────────────────────── groups ───────────────────────────


class GroupIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    currency: str | None = Field(default=None, max_length=3)
    # Names of other people to add now (you're added automatically).
    members: list[str] = Field(default_factory=list, max_length=50)


class GroupPatch(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class MemberIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class MemberOut(BaseModel):
    id: UUID
    display_name: str
    is_me: bool
    has_account: bool
    balance: str  # positive = is owed, negative = owes


class PaymentOut(BaseModel):
    """A suggested settle-up payment."""

    from_member_id: UUID
    to_member_id: UUID
    amount: str


class SettlementIn(BaseModel):
    from_member_id: UUID
    to_member_id: UUID
    amount: str
    note: str = Field(default="", max_length=200)


class SettlementOut(BaseModel):
    id: UUID
    from_member_id: UUID
    to_member_id: UUID
    amount: str
    note: str
    date: str


class GroupSummaryOut(BaseModel):
    id: UUID
    name: str
    currency: str
    member_count: int
    my_balance: str
    invite_url: str
    is_owner: bool


class GroupDetailOut(GroupSummaryOut):
    members: list[MemberOut]
    payments: list[PaymentOut]
    splits: list[SplitOut]
    settlements: list[SettlementOut]


class JoinIn(BaseModel):
    # Claim this placeholder (your name, added before you had an account).
    member_id: UUID | None = None


# ─────────────────────────── public (no account) ───────────────────────────


class PublicParticipantOut(BaseModel):
    display_name: str
    share: str
    is_you: bool
    is_payer: bool
    settled: bool
    item_indexes: list[int]


class PublicSplitOut(BaseModel):
    description: str
    date: str
    currency: str
    total: str
    items: list[ExtractionItemOut]
    participants: list[PublicParticipantOut]
    payer_name: str | None
    group_name: str | None
    your_share: str


class PublicMemberOut(BaseModel):
    id: UUID
    display_name: str
    claimed: bool


class PublicGroupOut(BaseModel):
    name: str
    members: list[PublicMemberOut]
