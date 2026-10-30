"""activity, comments, several payers, repeating expenses, reminders, payment
details (docs/SPLITS.md)

Revision ID: 0010
Revises: 0009
Create Date: 2026-10-30
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0010"
down_revision: str | None = "0009"
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
    op.add_column("users", sa.Column("email_checked_at", sa.DateTime(timezone=True)))
    op.add_column(
        "users",
        sa.Column("email_notifications", sa.Boolean(), nullable=False, server_default=sa.true()),
    )
    op.add_column("users", sa.Column("last_notified_at", sa.DateTime(timezone=True)))
    op.add_column("users", sa.Column("paypal_me", sa.String(40), nullable=False, server_default=""))
    op.add_column("users", sa.Column("interac", sa.String(120), nullable=False, server_default=""))

    op.add_column("split_participants", sa.Column("paid", sa.Numeric(12, 2)))
    # One payer, as before: they paid the whole total.
    op.execute(
        "UPDATE split_participants SET paid = "
        "(SELECT total FROM splits WHERE splits.id = split_participants.split_id) "
        "WHERE is_payer"
    )
    op.add_column("splits", sa.Column("repeat", sa.String(10), nullable=False, server_default=""))
    op.add_column("splits", sa.Column("next_at", sa.Date()))
    op.create_index("ix_splits_next_at", "splits", ["next_at"])
    op.add_column("group_members", sa.Column("reminded_at", sa.DateTime(timezone=True)))
    op.add_column(
        "groups",
        sa.Column("simplify_debts", sa.Boolean(), nullable=False, server_default=sa.true()),
    )
    op.add_column("people", sa.Column("reminded_at", sa.DateTime(timezone=True)))

    op.create_table(
        "split_comments",
        *_base(),
        sa.Column(
            "split_id", sa.Uuid(), sa.ForeignKey("splits.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("author_name", sa.String(120), nullable=False),
        sa.Column("body", sa.String(1000), nullable=False),
    )
    op.create_index("ix_split_comments_split_id", "split_comments", ["split_id"])

    op.create_table(
        "split_events",
        *_base(),
        sa.Column(
            "split_id", sa.Uuid(), sa.ForeignKey("splits.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("actor_name", sa.String(120), nullable=False),
        sa.Column("text", sa.String(1000), nullable=False),
    )
    op.create_index("ix_split_events_split_id", "split_events", ["split_id"])

    op.create_table(
        "activities",
        *_base(),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("actor_name", sa.String(120), nullable=False),
        sa.Column("kind", sa.String(30), nullable=False),
        sa.Column("text", sa.String(300), nullable=False),
        sa.Column("split_id", sa.Uuid()),
        sa.Column("group_id", sa.Uuid()),
        sa.Column("person_id", sa.Uuid()),
        sa.Column("read_at", sa.DateTime(timezone=True)),
    )
    op.create_index("ix_activities_user_id", "activities", ["user_id"])


def downgrade() -> None:
    op.drop_table("activities")
    op.drop_table("split_events")
    op.drop_table("split_comments")
    op.drop_column("people", "reminded_at")
    op.drop_column("groups", "simplify_debts")
    op.drop_column("group_members", "reminded_at")
    op.drop_index("ix_splits_next_at", "splits")
    op.drop_column("splits", "next_at")
    op.drop_column("splits", "repeat")
    op.drop_column("split_participants", "paid")
    for column in ("interac", "paypal_me", "last_notified_at", "email_notifications"):
        op.drop_column("users", column)
    op.drop_column("users", "email_checked_at")
