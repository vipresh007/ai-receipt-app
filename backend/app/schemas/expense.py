from datetime import date
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class ExpenseOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    merchant: str
    amount: str  # decimal string
    category_slug: str
    spent_at: date
    note: str
    receipt_id: UUID | None


class CategoryTotal(BaseModel):
    category_slug: str
    amount: str


class SpendingSummaryOut(BaseModel):
    month: str  # YYYY-MM — the month this summary covers
    total: str
    by_category: list[CategoryTotal]
    previous_month_total: str
    # YYYY-MM of the user's oldest expense, so clients can cap "previous month"
    # navigation. null when there are no expenses.
    earliest_month: str | None = None
