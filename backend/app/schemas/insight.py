from datetime import date
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class InsightOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    kind: str
    message: str
    period_start: date
    period_end: date
    generated_by: str
