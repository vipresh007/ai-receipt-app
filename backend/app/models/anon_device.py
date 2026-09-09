from sqlalchemy import Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class AnonDevice(Base):
    """Per-device counter for anonymous (not-signed-in) extraction calls.

    `created_at` / `updated_at` (from Base) double as first-seen / last-seen.
    """

    __tablename__ = "anon_devices"

    device_id: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    scan_count: Mapped[int] = mapped_column(Integer, default=0)
