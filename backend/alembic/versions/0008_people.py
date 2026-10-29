"""people: split with anyone without a group; invites (docs/SPLITS.md)

Revision ID: 0008
Revises: 0007
Create Date: 2026-10-29
"""

import secrets
import uuid
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0008"
down_revision: str | None = "0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _base() -> list[sa.Column]:
    return [
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    ]


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("email_verified", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.create_table(
        "people",
        *_base(),
        sa.Column(
            "owner_user_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("display_name", sa.String(120), nullable=False),
        sa.Column("email", sa.String(320), nullable=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True
        ),
        sa.Column("invite_token", sa.String(64), nullable=False, unique=True),
        sa.Column("invited_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("owner_user_id", "user_id", name="uq_person_owner_user"),
    )
    op.create_index("ix_people_owner_user_id", "people", ["owner_user_id"])
    op.create_index("ix_people_user_id", "people", ["user_id"])
    op.create_index("ix_people_invite_token", "people", ["invite_token"])

    op.create_table(
        "person_payments",
        *_base(),
        sa.Column(
            "owner_user_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "person_id", sa.Uuid(), sa.ForeignKey("people.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("from_owner", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("note", sa.String(200), nullable=False, server_default=""),
    )
    op.create_index("ix_person_payments_owner_user_id", "person_payments", ["owner_user_id"])
    op.create_index("ix_person_payments_person_id", "person_payments", ["person_id"])

    op.add_column(
        "split_participants",
        sa.Column(
            "person_id",
            sa.Uuid(),
            sa.ForeignKey("people.id", ondelete="SET NULL", name="fk_split_participants_person"),
            nullable=True,
        ),
    )
    op.create_index("ix_split_participants_person_id", "split_participants", ["person_id"])

    # Everyone already named on a one-off split becomes a saved person of the
    # split's owner (one per distinct name).
    bind = op.get_bind()
    rows = bind.execute(
        sa.text(
            "SELECT p.id, p.display_name, s.owner_user_id FROM split_participants p "
            "JOIN splits s ON s.id = p.split_id "
            "WHERE s.group_id IS NULL AND p.user_id IS NULL"
        )
    ).fetchall()
    people: dict[tuple, uuid.UUID] = {}
    for participant_id, name, owner_id in rows:
        key = (str(owner_id), (name or "").strip().lower())
        if key not in people:
            people[key] = uuid.uuid4()
            bind.execute(
                sa.text(
                    "INSERT INTO people (id, owner_user_id, display_name, invite_token) "
                    "VALUES (:id, :owner, :name, :token)"
                ),
                {
                    "id": people[key],
                    "owner": owner_id,
                    "name": (name or "Someone").strip()[:120],
                    "token": secrets.token_urlsafe(16),
                },
            )
        bind.execute(
            sa.text("UPDATE split_participants SET person_id = :person WHERE id = :id"),
            {"person": people[key], "id": participant_id},
        )


def downgrade() -> None:
    op.drop_index("ix_split_participants_person_id", "split_participants")
    op.drop_constraint("fk_split_participants_person", "split_participants", type_="foreignkey")
    op.drop_column("split_participants", "person_id")
    op.drop_table("person_payments")
    op.drop_table("people")
    op.drop_column("users", "email_verified")
