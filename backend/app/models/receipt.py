import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import JSON, Date, Float, ForeignKey, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Receipt(Base):
    __tablename__ = "receipts"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    merchant: Mapped[str] = mapped_column(String(200), default="")
    purchased_at: Mapped[date | None] = mapped_column(Date, nullable=True)
    total: Mapped[Decimal] = mapped_column(Numeric(12, 2), default=Decimal("0"))
    tax: Mapped[Decimal] = mapped_column(Numeric(12, 2), default=Decimal("0"))
    currency: Mapped[str] = mapped_column(String(3), default="USD")
    category_slug: Mapped[str] = mapped_column(String(40), default="other")

    image_blob_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    raw_ocr: Mapped[str | None] = mapped_column(Text, nullable=True)
    extraction_confidence: Mapped[float | None] = mapped_column(Float, nullable=True)

    # [{ "name": str, "price": "12.34", "quantity": 1 }, ...]
    line_items: Mapped[list[dict]] = mapped_column(JSON, default=list)
