"""drop PayPal.me details: Interac only for getting paid back

Revision ID: 0011
Revises: 0010
Create Date: 2026-10-30
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0011"
down_revision: str | None = "0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_column("users", "paypal_me")


def downgrade() -> None:
    op.add_column("users", sa.Column("paypal_me", sa.String(40), nullable=False, server_default=""))
