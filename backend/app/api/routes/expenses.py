from collections import defaultdict
from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db import get_session
from app.models import Expense, User
from app.schemas.expense import CategoryTotal, ExpenseOut, SpendingSummaryOut

router = APIRouter()


def _month_bounds(anchor: date) -> tuple[date, date]:
    start = anchor.replace(day=1)
    end = (
        start.replace(year=start.year + 1, month=1)
        if start.month == 12
        else start.replace(month=start.month + 1)
    )
    return start, end


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
) -> SpendingSummaryOut:
    rows = list(await session.scalars(select(Expense).where(Expense.user_id == user.id)))
    today = date.today()
    this_start, this_end = _month_bounds(today)
    prev_start, _ = _month_bounds(this_start - date.resolution)

    by_category: dict[str, Decimal] = defaultdict(lambda: Decimal("0"))
    total = Decimal("0")
    prev_total = Decimal("0")
    for e in rows:
        if this_start <= e.spent_at < this_end:
            total += Decimal(e.amount)
            by_category[e.category_slug] += Decimal(e.amount)
        elif prev_start <= e.spent_at < this_start:
            prev_total += Decimal(e.amount)

    ranked = sorted(by_category.items(), key=lambda kv: kv[1], reverse=True)
    return SpendingSummaryOut(
        month=this_start.strftime("%Y-%m"),
        total=f"{total:.2f}",
        by_category=[CategoryTotal(category_slug=s, amount=f"{a:.2f}") for s, a in ranked],
        previous_month_total=f"{prev_total:.2f}",
    )
