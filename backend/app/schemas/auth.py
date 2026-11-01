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
    # Your home currency: set by you, else the one your receipts use most,
    # else null (the app guesses from the device).
    currency: str | None = None
    currency_is_set: bool = False
    # Forward receipts here (null when forwarding isn't set up on the server).
    receipts_email: str | None = None
    receipts_personal_email: str | None = None
    # Every notification kind × channel → on/off, e.g. "comments.push".
    notify_prefs: dict[str, bool] = {}


class MeSettingsIn(BaseModel):
    email_notifications: bool | None = None
    # Only the keys sent change.
    notify_prefs: dict[str, bool] | None = None
    # Interac e-Transfer email or phone; "" removes it.
    interac: str | None = Field(default=None, max_length=120)
    # ISO code like "CAD"; "" goes back to automatic.
    currency: str | None = Field(default=None, max_length=3)
