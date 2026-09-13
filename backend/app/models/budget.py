import uuid
from decimal import Decimal

from sqlalchemy import ForeignKey, Numeric, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Budget(Base):
    """A user's monthly spending limit for one category. One row per
    (user, category); the limit applies every month until changed."""

    __tablename__ = "budgets"
    __table_args__ = (UniqueConstraint("user_id", "category_slug", name="uq_budget_user_category"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    category_slug: Mapped[str] = mapped_column(String(40))
    monthly_limit: Mapped[Decimal] = mapped_column(Numeric(12, 2))
