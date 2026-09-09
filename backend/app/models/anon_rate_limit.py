from sqlalchemy import Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class AnonRateLimit(Base):
    """Fixed-window counter for anonymous extraction, keyed by
    ``"<client-ip>:<YYYYMMDDHH>"``. One row per IP per hour; rows age out."""

    __tablename__ = "anon_rate_limits"

    bucket: Mapped[str] = mapped_column(String(80), unique=True, index=True)
    count: Mapped[int] = mapped_column(Integer, default=0)
