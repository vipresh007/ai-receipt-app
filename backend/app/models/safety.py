"""Keeping shared spaces civil: blocking someone, and reporting what they wrote.

Blocking hides that person's comments from you and stops their activity
reaching you (feed and emails). It doesn't undo shared expenses: what's owed
stays owed. Reports keep a copy of what was written so it can be reviewed
even if it's deleted afterwards.
"""

import uuid

from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class UserBlock(Base):
    __tablename__ = "user_blocks"
    __table_args__ = (UniqueConstraint("blocker_id", "blocked_id"),)

    blocker_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    blocked_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    # The name you knew them by, for the list you unblock from.
    blocked_name: Mapped[str] = mapped_column(String(120))


class ContentReport(Base):
    __tablename__ = "content_reports"

    reporter_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    reported_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    comment_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    split_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    reason: Mapped[str] = mapped_column(String(40))
    body: Mapped[str] = mapped_column(String(1000))  # what was written, as reported
