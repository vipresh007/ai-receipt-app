"""users: personal forwarding address token for emailed receipts

Revision ID: 0017
Revises: 0016
Create Date: 2026-11-01
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0017"
down_revision: str | None = "0016"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("inbox_token", sa.String(32)))
    op.create_unique_constraint("uq_users_inbox_token", "users", ["inbox_token"])


def downgrade() -> None:
    op.drop_constraint("uq_users_inbox_token", "users", type_="unique")
    op.drop_column("users", "inbox_token")
