from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class EmailSuppression(Base):
    """An address that unsubscribed from all Tally email (services/unsubscribe.py)."""

    __tablename__ = "email_suppressions"

    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
