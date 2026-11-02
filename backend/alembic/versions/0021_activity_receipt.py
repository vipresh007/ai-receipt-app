"""activity rows remember their receipt, so tapping one opens it

Revision ID: 0021
Revises: 0020
Create Date: 2026-11-02
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0021"
down_revision: str | None = "0020"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("activities", sa.Column("receipt_id", sa.Uuid(), nullable=True))


def downgrade() -> None:
    op.drop_column("activities", "receipt_id")
