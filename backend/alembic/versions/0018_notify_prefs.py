"""users: per-kind push/email notification preferences

Revision ID: 0018
Revises: 0017
Create Date: 2026-11-01
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0018"
down_revision: str | None = "0017"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("notify_prefs", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "notify_prefs")
