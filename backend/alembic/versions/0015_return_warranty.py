"""receipts: return-by and warranty dates, and when each was reminded

Revision ID: 0015
Revises: 0014
Create Date: 2026-11-01
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0015"
down_revision: str | None = "0014"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("receipts", sa.Column("return_by", sa.Date()))
    op.add_column("receipts", sa.Column("warranty_until", sa.Date()))
    op.add_column("receipts", sa.Column("return_reminded_at", sa.DateTime(timezone=True)))
    op.add_column("receipts", sa.Column("warranty_reminded_at", sa.DateTime(timezone=True)))


def downgrade() -> None:
    for column in ("warranty_reminded_at", "return_reminded_at", "warranty_until", "return_by"):
        op.drop_column("receipts", column)
