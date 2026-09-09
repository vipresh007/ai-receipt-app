"""anonymous per-IP rate-limit buckets

Revision ID: 0004
Revises: 0003
Create Date: 2026-09-09
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "anon_rate_limits",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("bucket", sa.String(80), nullable=False),
        sa.Column("count", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_index("ix_anon_rate_limits_bucket", "anon_rate_limits", ["bucket"], unique=True)


def downgrade() -> None:
    op.drop_table("anon_rate_limits")
