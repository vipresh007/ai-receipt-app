"""initial schema

Revision ID: 0001
Revises:
Create Date: 2026-09-07
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

CATEGORY = sa.String(40)


def _common() -> list[sa.Column]:
    return [
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
    ]


def upgrade() -> None:
    op.create_table(
        "users",
        *_common(),
        sa.Column("email", sa.String(320), nullable=False),
        sa.Column("hashed_password", sa.String(255), nullable=False),
        sa.Column("display_name", sa.String(120), nullable=False, server_default=""),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("plan", sa.String(20), nullable=False, server_default="free"),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)

    op.create_table(
        "categories",
        *_common(),
        sa.Column(
            "user_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=True,
        ),
        sa.Column("slug", CATEGORY, nullable=False),
        sa.Column("name", sa.String(80), nullable=False),
    )
    op.create_index("ix_categories_user_id", "categories", ["user_id"])
    op.create_index("ix_categories_slug", "categories", ["slug"])

    op.create_table(
        "receipts",
        *_common(),
        sa.Column(
            "user_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("merchant", sa.String(200), nullable=False, server_default=""),
        sa.Column("purchased_at", sa.Date(), nullable=True),
        sa.Column("total", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("tax", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("currency", sa.String(3), nullable=False, server_default="USD"),
        sa.Column("category_slug", CATEGORY, nullable=False, server_default="other"),
        sa.Column("image_blob_url", sa.String(1000), nullable=True),
        sa.Column("raw_ocr", sa.Text(), nullable=True),
        sa.Column("extraction_confidence", sa.Float(), nullable=True),
        sa.Column("line_items", sa.JSON(), nullable=False, server_default="[]"),
    )
    op.create_index("ix_receipts_user_id", "receipts", ["user_id"])

    op.create_table(
        "expenses",
        *_common(),
        sa.Column(
            "user_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "receipt_id",
            sa.Uuid(),
            sa.ForeignKey("receipts.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("merchant", sa.String(200), nullable=False),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("category_slug", CATEGORY, nullable=False, server_default="other"),
        sa.Column("spent_at", sa.Date(), nullable=False),
        sa.Column("note", sa.String(500), nullable=False, server_default=""),
    )
    op.create_index("ix_expenses_user_id", "expenses", ["user_id"])
    op.create_index("ix_expenses_spent_at", "expenses", ["spent_at"])

    op.create_table(
        "insights",
        *_common(),
        sa.Column(
            "user_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("kind", sa.String(30), nullable=False),
        sa.Column("message", sa.String(500), nullable=False),
        sa.Column("period_start", sa.Date(), nullable=False),
        sa.Column("period_end", sa.Date(), nullable=False),
        sa.Column("generated_by", sa.String(40), nullable=False, server_default="rules"),
    )
    op.create_index("ix_insights_user_id", "insights", ["user_id"])


def downgrade() -> None:
    for table in ("insights", "expenses", "receipts", "categories", "users"):
        op.drop_table(table)
