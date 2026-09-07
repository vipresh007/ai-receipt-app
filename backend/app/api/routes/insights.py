from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db import get_session
from app.models import Expense, Insight, User
from app.schemas.insight import InsightOut
from app.services.insights import generate_rule_based

router = APIRouter()


@router.get("", response_model=list[InsightOut])
async def list_insights(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[Insight]:
    rows = await session.scalars(
        select(Insight)
        .where(Insight.user_id == user.id)
        .order_by(Insight.period_end.desc(), Insight.created_at.desc())
        .limit(50)
    )
    return list(rows)


@router.post("/generate", response_model=list[InsightOut], status_code=201)
async def generate_insights(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[Insight]:
    expenses = list(await session.scalars(select(Expense).where(Expense.user_id == user.id)))
    fresh = generate_rule_based(user_id=user.id, expenses=expenses)
    for ins in fresh:
        session.add(ins)
    await session.commit()
    for ins in fresh:
        await session.refresh(ins)
    return fresh
