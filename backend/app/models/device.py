import uuid

from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class DeviceToken(Base):
    """An iPhone that wants push notifications for this user (services/push.py)."""

    __tablename__ = "device_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    token: Mapped[str] = mapped_column(String(200), unique=True)
    # "production" (App Store / TestFlight) or "sandbox" (Xcode debug builds).
    environment: Mapped[str] = mapped_column(String(20), default="production")
