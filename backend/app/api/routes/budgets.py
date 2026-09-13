from decimal import Decimal, InvalidOperation

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.date_ranges import month_bounds, month_start
from app.db import get_session
from app.models import DEFAULT_CATEGORY_SLUGS, Budget, Expense, User
from app.schemas.budget import BudgetIn, BudgetOut

router = APIRouter()


def _to_decimal(value: str) -> Decimal:
    try:
        amount = Decimal(value)
    except InvalidOperation as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Invalid amount.") from exc
    if amount <= 0:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "Budget must be greater than zero."
        )
    return amount


async def _spent_by_category(session: AsyncSession, user_id, start, end) -> dict[str, Decimal]:
    rows = await session.execute(
        select(Expense.category_slug, func.coalesce(func.sum(Expense.amount), 0))
        .where(Expense.user_id == user_id, Expense.spent_at >= start, Expense.spent_at < end)
        .group_by(Expense.category_slug)
    )
    return {slug: Decimal(total) for slug, total in rows.all()}


def _out(category_slug: str, monthly_limit: Decimal, spent: Decimal) -> BudgetOut:
    percent = float(spent / monthly_limit * 100) if monthly_limit > 0 else 0.0
    return BudgetOut(
        category_slug=category_slug,
        monthly_limit=f"{monthly_limit:.2f}",
        spent=f"{spent:.2f}",
        remaining=f"{(monthly_limit - spent):.2f}",
        percent_used=round(percent, 1),
    )


@router.get("", response_model=list[BudgetOut])
async def list_budgets(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    month: str | None = None,
) -> list[BudgetOut]:
    """Every category with a budget set, plus how much of it is spent in
    `month` (YYYY-MM, default the current month). Highest usage first."""
    budgets = list(await session.scalars(select(Budget).where(Budget.user_id == user.id)))
    if not budgets:
        return []

    start, end = month_bounds(month_start(month))
    spent = await _spent_by_category(session, user.id, start, end)

    out = [
        _out(b.category_slug, Decimal(b.monthly_limit), spent.get(b.category_slug, Decimal("0")))
        for b in budgets
    ]
    return sorted(out, key=lambda b: b.percent_used, reverse=True)


@router.put("/{category_slug}", response_model=BudgetOut)
async def set_budget(
    category_slug: str,
    body: BudgetIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> BudgetOut:
    """Create or update the monthly limit for a category (upsert)."""
    if category_slug not in DEFAULT_CATEGORY_SLUGS:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Unknown category.")
    limit = _to_decimal(body.monthly_limit)

    existing = await session.scalar(
        select(Budget).where(Budget.user_id == user.id, Budget.category_slug == category_slug)
    )
    if existing:
        existing.monthly_limit = limit
    else:
        session.add(Budget(user_id=user.id, category_slug=category_slug, monthly_limit=limit))
    await session.commit()

    start, end = month_bounds(month_start(None))
    spent_by_category = await _spent_by_category(session, user.id, start, end)
    return _out(category_slug, limit, spent_by_category.get(category_slug, Decimal("0")))


@router.delete("/{category_slug}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_budget(
    category_slug: str,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    existing = await session.scalar(
        select(Budget).where(Budget.user_id == user.id, Budget.category_slug == category_slug)
    )
    if existing:
        await session.delete(existing)
        await session.commit()
