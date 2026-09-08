from uuid import UUID

from pydantic import BaseModel, ConfigDict


class MeOut(BaseModel):
    """The current user (identity comes from Auth0; this row holds app data)."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: str
    display_name: str
    plan: str
