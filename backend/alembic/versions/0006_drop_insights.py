"""drop the unused insights table

Insights are computed client-side (web `lib/insights.ts`, iOS
`SpendingSummary`) from category totals the dashboards already load; nothing
ever wrote to this table, and the /v1/insights routes that read it are gone.

Revision ID: 0006
Revises: 0005
Create Date: 2026-09-25
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0006"
down_revision: str | None = "0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # IF EXISTS: a database bootstrapped by create_all() after the model was
    # removed never had this table.
    op.execute("DROP TABLE IF EXISTS insights")


def downgrade() -> None:
    op.create_table(
        "insights",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("kind", sa.String(30), nullable=False),
        sa.Column("message", sa.String(500), nullable=False),
        sa.Column("period_start", sa.Date(), nullable=False),
        sa.Column("period_end", sa.Date(), nullable=False),
        sa.Column("generated_by", sa.String(40), nullable=False, server_default="rules"),
    )
    op.create_index("ix_insights_user_id", "insights", ["user_id"])
