from sqlalchemy import Boolean, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class User(Base):
    __tablename__ = "users"

    # Auth0 subject (`sub` claim). Null only for rows created before Auth0.
    auth0_sub: Mapped[str | None] = mapped_column(
        String(255), unique=True, index=True, nullable=True
    )
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    display_name: Mapped[str] = mapped_column(String(120), default="")
    # From the sign-in provider. Only a verified address may link this account
    # to anything that was keyed by email (an older row, people invited by it).
    email_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    plan: Mapped[str] = mapped_column(String(20), default="free")  # free | pro
