import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import Date, ForeignKey, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Expense(Base):
    """Normalized spending record. Usually derived from a Receipt, but a
    manual entry (no receipt) is allowed."""

    __tablename__ = "expenses"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    receipt_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("receipts.id", ondelete="SET NULL"), nullable=True
    )
    merchant: Mapped[str] = mapped_column(String(200))
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    category_slug: Mapped[str] = mapped_column(String(40), default="other")
    spent_at: Mapped[date] = mapped_column(Date, index=True)
    note: Mapped[str] = mapped_column(String(500), default="")
