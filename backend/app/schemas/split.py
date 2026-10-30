"""Request/response shapes for splits and groups (docs/SPLITS.md). Money is
decimal strings on the wire, like everywhere else."""

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

from app.schemas.receipt import ExtractionItemOut

Mode = Literal["even", "items", "shares", "percent", "custom"]
Repeat = Literal["", "weekly", "monthly"]


class ParticipantIn(BaseModel):
    """One person on a split: yourself (`is_me`), a group member (`member_id`),
    or just a name (one-off splits)."""

    is_me: bool = False
    member_id: UUID | None = None
    # One-off splits: a saved person, or a new `name` (saved as a person).
    person_id: UUID | None = None
    name: str = Field(default="", max_length=120)
    is_payer: bool = False
    item_indexes: list[int] = Field(default_factory=list, max_length=500)
    amount: str | None = None  # custom mode
    weight: str | None = Field(default=None, max_length=12)  # shares (blank = 1) / percent
    # Several payers: what this person put in (all must add up to the total).
    paid: str | None = Field(default=None, max_length=20)


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
    # Hand-entered expenses only: add it again every week / month.
    repeat: Repeat = ""


class ParticipantAdjust(BaseModel):
    """An existing person on the split (by id): their part, not who they are."""

    id: UUID
    is_payer: bool = False
    paid: str | None = Field(default=None, max_length=20)
    item_indexes: list[int] = Field(default_factory=list, max_length=500)
    amount: str | None = Field(default=None, max_length=20)
    weight: str | None = Field(default=None, max_length=12)


class SplitAdjustIn(BaseModel):
    """An edit by anyone on the expense: how it's divided and who paid, plus
    the description, amount and date of a hand-entered one. Who's on it stays
    with whoever added it."""

    description: str | None = Field(default=None, max_length=200)
    total: str | None = Field(default=None, max_length=20)
    date: str | None = None
    mode: Mode
    participants: list[ParticipantAdjust] = Field(min_length=1, max_length=50)


class ParticipantOut(BaseModel):
    id: UUID
    display_name: str
    member_id: UUID | None
    person_id: UUID | None
    is_me: bool
    is_payer: bool
    item_indexes: list[int]
    amount: str | None
    weight: str | None
    paid: str | None
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
    # Anyone on it (or in its group) can change the amounts; only the owner
    # changes who's on it or deletes it.
    can_edit: bool
    repeat: Repeat
    next_at: str | None


class CommentIn(BaseModel):
    body: str = Field(min_length=1, max_length=1000)


class TimelineEntry(BaseModel):
    """An expense's history and comments, oldest first."""

    id: UUID
    kind: Literal["event", "comment"]
    author_name: str
    text: str
    at: str  # ISO datetime
    can_delete: bool


class SettledIn(BaseModel):
    settled: bool


# ─────────────────────────── groups ───────────────────────────


class GroupIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    currency: str | None = Field(default=None, max_length=3)
    # Names of other people to add now (you're added automatically).
    members: list[str] = Field(default_factory=list, max_length=50)


class GroupPatch(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    simplify_debts: bool | None = None


class MemberIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    email: str | None = Field(default=None, max_length=320)
    send_invite: bool = False


class MemberPatch(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    # "" removes it.
    email: str | None = Field(default=None, max_length=320)


class PayDetails(BaseModel):
    """How someone likes to be paid back (they set it under Account)."""

    interac: str | None


class MemberOut(BaseModel):
    id: UUID
    display_name: str
    is_me: bool
    has_account: bool
    balance: str  # positive = is owed, negative = owes
    pay_to: PayDetails | None = None
    # Before they join: where their invite goes, and when it last went.
    email: str | None = None
    invited_at: str | None = None
    can_email: bool = False


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
    # Settle up with the fewest payments, or who owes whom directly.
    simplify_debts: bool


class GroupDetailOut(GroupSummaryOut):
    members: list[MemberOut]
    payments: list[PaymentOut]
    splits: list[SplitOut]
    settlements: list[SettlementOut]


class JoinIn(BaseModel):
    # Claim this placeholder (your name, added before you had an account).
    member_id: UUID | None = None


# ─────────────────────────── people ───────────────────────────


class PersonIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    email: str | None = Field(default=None, max_length=320)
    send_invite: bool = False


class PersonPatch(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    # "" removes it.
    email: str | None = Field(default=None, max_length=320)


class PersonGroupBalance(BaseModel):
    group_id: UUID
    name: str
    balance: str


class PersonOut(BaseModel):
    id: UUID
    name: str
    email: str | None
    # They accepted the invite: they see what you share from their side.
    has_account: bool
    invite_url: str
    invited_at: str | None
    # Positive = they owe you; negative = you owe them. Overall: outside
    # groups plus every group you're both in (once they've joined).
    balance: str
    outside_groups: str
    group_balances: list[PersonGroupBalance]
    currency: str
    # Tally can email this person their invite (an address is set and email
    # is configured).
    can_email: bool
    # Their Interac details, when they've joined and set them.
    pay_to: PayDetails | None
    # The most recent expense you share outside groups (for "recent" picks).
    last_shared: str | None = None


class PersonPaymentIn(BaseModel):
    # True: you paid them. False: they paid you.
    you_paid: bool
    amount: str = Field(max_length=20)
    note: str = Field(default="", max_length=200)


class PersonPaymentOut(BaseModel):
    id: UUID
    you_paid: bool
    amount: str
    note: str
    date: str
    # Recorded by you (the other side's records are theirs to remove).
    can_delete: bool


class PersonDetailOut(PersonOut):
    splits: list[SplitOut]
    payments: list[PersonPaymentOut]


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
    # The payer's Interac details, if they've set them.
    pay_to: PayDetails | None = None
    mode: Mode = "even"
    # A split receipt's tax, for showing the whole receipt.
    tax: str | None = None
    # Who added it, and the link to everything shared with them (their invite
    # to you, or the group's).
    owner_name: str = ""
    invite_url: str | None = None


class PublicMemberOut(BaseModel):
    id: UUID
    display_name: str
    claimed: bool


class PublicGroupOut(BaseModel):
    name: str
    members: list[PublicMemberOut]


class PublicPersonOut(BaseModel):
    """What an invite link shows: who invited you and where you stand."""

    from_name: str
    name: str
    claimed: bool
    # From the invitee's side: positive = you're owed; negative = you owe.
    balance: str
    currency: str
    expense_count: int
