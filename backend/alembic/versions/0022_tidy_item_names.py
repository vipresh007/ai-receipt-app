"""tidy saved line items: product codes out of names, weights/counts into detail

Revision ID: 0022
Revises: 0021
Create Date: 2026-11-05
"""

import json
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op
from app.services.items import tidy_line

revision: str = "0022"
down_revision: str | None = "0021"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    conn = op.get_bind()
    rows = conn.execute(sa.text("SELECT id, line_items FROM receipts")).fetchall()
    for rid, raw in rows:
        lines = json.loads(raw) if isinstance(raw, str) else (raw or [])
        tidied = [tidy_line(li) for li in lines]
        if tidied != lines:
            conn.execute(
                sa.text("UPDATE receipts SET line_items = :items WHERE id = :id").bindparams(
                    sa.bindparam("items", type_=sa.JSON)
                ),
                {"items": tidied, "id": rid},
            )


def downgrade() -> None:
    pass  # names were only tidied
