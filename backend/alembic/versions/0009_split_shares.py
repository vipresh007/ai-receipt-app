"""split by shares: a weight per participant (docs/SPLITS.md)

Revision ID: 0009
Revises: 0008
Create Date: 2026-10-30
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0009"
down_revision: str | None = "0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("split_participants", sa.Column("weight", sa.Numeric(10, 2), nullable=True))


def downgrade() -> None:
    op.drop_column("split_participants", "weight")
