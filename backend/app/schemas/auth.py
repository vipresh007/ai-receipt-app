from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class MeOut(BaseModel):
    """The current user (identity comes from Auth0; this row holds app data)."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: str
    display_name: str
    plan: str
    email_notifications: bool
    interac: str


class MeSettingsIn(BaseModel):
    email_notifications: bool | None = None
    # Interac e-Transfer email or phone; "" removes it.
    interac: str | None = Field(default=None, max_length=120)
