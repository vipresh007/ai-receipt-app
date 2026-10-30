"""home currency on the account (empty = from your receipts)

Revision ID: 0012
Revises: 0011
Create Date: 2026-10-30
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0012"
down_revision: str | None = "0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("currency", sa.String(3), nullable=False, server_default=""))


def downgrade() -> None:
    op.drop_column("users", "currency")
