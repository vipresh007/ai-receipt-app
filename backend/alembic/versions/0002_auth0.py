"""switch auth to Auth0

Adds users.auth0_sub, drops users.hashed_password (Auth0 owns credentials now).

Revision ID: 0002
Revises: 0001
Create Date: 2026-09-07
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("auth0_sub", sa.String(255), nullable=True))
    op.create_index("ix_users_auth0_sub", "users", ["auth0_sub"], unique=True)
    op.drop_column("users", "hashed_password")


def downgrade() -> None:
    op.add_column(
        "users",
        sa.Column("hashed_password", sa.String(255), nullable=False, server_default=""),
    )
    op.drop_index("ix_users_auth0_sub", table_name="users")
    op.drop_column("users", "auth0_sub")
