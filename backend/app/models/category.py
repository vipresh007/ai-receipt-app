import uuid

from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base

# Canonical slugs shared with the iOS app's ExpenseCategory raw values.
DEFAULT_CATEGORY_SLUGS: tuple[str, ...] = (
    "groceries",
    "restaurants",
    "transport",
    "shopping",
    "entertainment",
    "health",
    "utilities",
    "travel",
    "other",
)


class Category(Base):
    __tablename__ = "categories"

    # NULL user_id => built-in/system category.
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True
    )
    slug: Mapped[str] = mapped_column(String(40), index=True)
    name: Mapped[str] = mapped_column(String(80))
