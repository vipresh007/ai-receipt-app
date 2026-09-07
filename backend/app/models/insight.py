import uuid
from datetime import date

from sqlalchemy import Date, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Insight(Base):
    __tablename__ = "insights"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[str] = mapped_column(String(30))  # up | down | streak | summary
    message: Mapped[str] = mapped_column(String(500))
    period_start: Mapped[date] = mapped_column(Date)
    period_end: Mapped[date] = mapped_column(Date)
    generated_by: Mapped[str] = mapped_column(String(40), default="rules")  # rules | azure_openai
