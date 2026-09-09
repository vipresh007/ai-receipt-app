"""anonymous device scan counter

Revision ID: 0003
Revises: 0002
Create Date: 2026-09-09
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "anon_devices",
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
        sa.Column("device_id", sa.String(64), nullable=False),
        sa.Column("scan_count", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_index("ix_anon_devices_device_id", "anon_devices", ["device_id"], unique=True)


def downgrade() -> None:
    op.drop_table("anon_devices")
