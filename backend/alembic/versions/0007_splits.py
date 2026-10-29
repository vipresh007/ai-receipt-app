"""splits and groups (docs/SPLITS.md)

Revision ID: 0007
Revises: 0006
Create Date: 2026-10-29
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0007"
down_revision: str | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _base() -> list[sa.Column]:
    return [
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    ]


def upgrade() -> None:
    op.create_table(
        "groups",
        *_base(),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column(
            "owner_user_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("currency", sa.String(3), nullable=False, server_default="CAD"),
        sa.Column("invite_token", sa.String(64), nullable=False, unique=True),
    )
    op.create_index("ix_groups_owner_user_id", "groups", ["owner_user_id"])
    op.create_index("ix_groups_invite_token", "groups", ["invite_token"])

    op.create_table(
        "group_members",
        *_base(),
        sa.Column(
            "group_id", sa.Uuid(), sa.ForeignKey("groups.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True
        ),
        sa.Column("display_name", sa.String(120), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
        sa.UniqueConstraint("group_id", "user_id", name="uq_group_member_user"),
    )
    op.create_index("ix_group_members_group_id", "group_members", ["group_id"])
    op.create_index("ix_group_members_user_id", "group_members", ["user_id"])

    op.create_table(
        "splits",
        *_base(),
        sa.Column(
            "owner_user_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "group_id", sa.Uuid(), sa.ForeignKey("groups.id", ondelete="CASCADE"), nullable=True
        ),
        sa.Column(
            "receipt_id",
            sa.Uuid(),
            sa.ForeignKey("receipts.id", ondelete="CASCADE"),
            nullable=True,
            unique=True,
        ),
        sa.Column("description", sa.String(200), nullable=False, server_default=""),
        sa.Column("total", sa.Numeric(12, 2), nullable=False),
        sa.Column("currency", sa.String(3), nullable=False, server_default="CAD"),
        sa.Column("spent_at", sa.Date(), nullable=False),
        sa.Column("mode", sa.String(10), nullable=False, server_default="even"),
        sa.Column("line_items", sa.JSON(), nullable=False),
    )
    op.create_index("ix_splits_owner_user_id", "splits", ["owner_user_id"])
    op.create_index("ix_splits_group_id", "splits", ["group_id"])

    op.create_table(
        "split_participants",
        *_base(),
        sa.Column(
            "split_id", sa.Uuid(), sa.ForeignKey("splits.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "member_id",
            sa.Uuid(),
            sa.ForeignKey("group_members.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True
        ),
        sa.Column("display_name", sa.String(120), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_payer", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("item_indexes", sa.JSON(), nullable=False),
        sa.Column("custom_amount", sa.Numeric(12, 2), nullable=True),
        sa.Column("share", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("settled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("share_token", sa.String(64), nullable=False, unique=True),
    )
    op.create_index("ix_split_participants_split_id", "split_participants", ["split_id"])
    op.create_index("ix_split_participants_member_id", "split_participants", ["member_id"])
    op.create_index("ix_split_participants_user_id", "split_participants", ["user_id"])
    op.create_index("ix_split_participants_share_token", "split_participants", ["share_token"])

    op.create_table(
        "settlements",
        *_base(),
        sa.Column(
            "group_id", sa.Uuid(), sa.ForeignKey("groups.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "from_member_id",
            sa.Uuid(),
            sa.ForeignKey("group_members.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "to_member_id",
            sa.Uuid(),
            sa.ForeignKey("group_members.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("note", sa.String(200), nullable=False, server_default=""),
        sa.Column(
            "created_by_user_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.create_index("ix_settlements_group_id", "settlements", ["group_id"])

    op.add_column("receipts", sa.Column("my_share", sa.Numeric(12, 2), nullable=True))
    op.add_column("receipts", sa.Column("split_id", sa.Uuid(), nullable=True))


def downgrade() -> None:
    op.drop_column("receipts", "split_id")
    op.drop_column("receipts", "my_share")
    op.drop_table("settlements")
    op.drop_table("split_participants")
    op.drop_table("splits")
    op.drop_table("group_members")
    op.drop_table("groups")
