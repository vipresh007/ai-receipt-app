"""blocking people and reporting comments

Revision ID: 0014
Revises: 0013
Create Date: 2026-11-01
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0014"
down_revision: str | None = "0013"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _stamps() -> list[sa.Column]:
    return [
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    ]


def upgrade() -> None:
    op.create_table(
        "user_blocks",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "blocker_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "blocked_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("blocked_name", sa.String(120), nullable=False),
        *_stamps(),
        sa.UniqueConstraint("blocker_id", "blocked_id"),
    )
    op.create_index("ix_user_blocks_blocker_id", "user_blocks", ["blocker_id"])
    op.create_table(
        "content_reports",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("reporter_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("reported_user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("comment_id", sa.Uuid()),
        sa.Column("split_id", sa.Uuid()),
        sa.Column("reason", sa.String(40), nullable=False),
        sa.Column("body", sa.String(1000), nullable=False),
        *_stamps(),
    )


def downgrade() -> None:
    op.drop_table("content_reports")
    op.drop_index("ix_user_blocks_blocker_id", table_name="user_blocks")
    op.drop_table("user_blocks")
