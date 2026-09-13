from pydantic import BaseModel


class BudgetIn(BaseModel):
    monthly_limit: str  # decimal string


class BudgetOut(BaseModel):
    category_slug: str
    monthly_limit: str
    # Spend + limit are both scoped to the month the request asked about
    # (default: the current month) — see GET /v1/budgets.
    spent: str
    remaining: str
    percent_used: float
