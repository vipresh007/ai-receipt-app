from collections import defaultdict
from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.date_ranges import month_bounds, month_start
from app.db import get_session
from app.models import Expense, User
from app.schemas.expense import CategoryTotal, ExpenseOut, SpendingSummaryOut

router = APIRouter()


@router.get("", response_model=list[ExpenseOut])
async def list_expenses(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    limit: int = 100,
) -> list[ExpenseOut]:
    rows = await session.scalars(
        select(Expense)
        .where(Expense.user_id == user.id)
        .order_by(Expense.spent_at.desc())
        .limit(min(limit, 500))
    )
    return [
        ExpenseOut(
            id=e.id,
            merchant=e.merchant,
            amount=f"{e.amount:.2f}",
            category_slug=e.category_slug,
            spent_at=e.spent_at,
            note=e.note,
            receipt_id=e.receipt_id,
        )
        for e in rows
    ]


@router.get("/summary", response_model=SpendingSummaryOut)
async def spending_summary(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    month: str | None = None,
) -> SpendingSummaryOut:
    """Spending for `month` (YYYY-MM, default the current month)."""
    rows = list(await session.scalars(select(Expense).where(Expense.user_id == user.id)))
    this_start, this_end = month_bounds(month_start(month))
    prev_start, _ = month_bounds(this_start - date.resolution)

    by_category: dict[str, Decimal] = defaultdict(lambda: Decimal("0"))
    total = Decimal("0")
    prev_total = Decimal("0")
    for e in rows:
        if this_start <= e.spent_at < this_end:
            total += Decimal(e.amount)
            by_category[e.category_slug] += Decimal(e.amount)
        elif prev_start <= e.spent_at < this_start:
            prev_total += Decimal(e.amount)

    earliest = min((e.spent_at for e in rows), default=None)
    ranked = sorted(by_category.items(), key=lambda kv: kv[1], reverse=True)
    return SpendingSummaryOut(
        month=this_start.strftime("%Y-%m"),
        total=f"{total:.2f}",
        by_category=[CategoryTotal(category_slug=s, amount=f"{a:.2f}") for s, a in ranked],
        previous_month_total=f"{prev_total:.2f}",
        earliest_month=earliest.strftime("%Y-%m") if earliest else None,
    )
