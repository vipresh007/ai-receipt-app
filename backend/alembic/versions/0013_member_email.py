"""group members: an email for their invite, and when it was sent

Revision ID: 0013
Revises: 0012
Create Date: 2026-10-30
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0013"
down_revision: str | None = "0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("group_members", sa.Column("email", sa.String(320)))
    op.add_column("group_members", sa.Column("invited_at", sa.DateTime(timezone=True)))


def downgrade() -> None:
    op.drop_column("group_members", "invited_at")
    op.drop_column("group_members", "email")
