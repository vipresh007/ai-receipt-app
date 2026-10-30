"""Your activity: what people did with expenses you share (docs/SPLITS.md)."""

from datetime import UTC, datetime

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db import get_session
from app.models import Activity, User

router = APIRouter()


class ActivityOut(BaseModel):
    id: str
    actor_name: str
    kind: str
    text: str
    at: str
    read: bool
    split_id: str | None
    group_id: str | None
    person_id: str | None


class ActivityFeedOut(BaseModel):
    unread: int
    items: list[ActivityOut]


async def _unread(session: AsyncSession, user: User) -> int:
    return (
        await session.scalar(
            select(func.count(Activity.id)).where(
                Activity.user_id == user.id, Activity.read_at.is_(None)
            )
        )
    ) or 0


def _iso(moment: datetime) -> str:
    return (moment if moment.tzinfo else moment.replace(tzinfo=UTC)).isoformat()


@router.get("", response_model=ActivityFeedOut)
async def feed(
    limit: int = 50,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ActivityFeedOut:
    rows = await session.scalars(
        select(Activity)
        .where(Activity.user_id == user.id)
        .order_by(Activity.created_at.desc())
        .limit(max(1, min(limit, 100)))
    )
    return ActivityFeedOut(
        unread=await _unread(session, user),
        items=[
            ActivityOut(
                id=str(a.id),
                actor_name=a.actor_name,
                kind=a.kind,
                text=a.text,
                at=_iso(a.created_at),
                read=a.read_at is not None,
                split_id=str(a.split_id) if a.split_id else None,
                group_id=str(a.group_id) if a.group_id else None,
                person_id=str(a.person_id) if a.person_id else None,
            )
            for a in rows
        ],
    )


@router.get("/unread", response_model=dict)
async def unread(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    return {"unread": await _unread(session, user)}


@router.post("/read", response_model=dict)
async def mark_read(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    await session.execute(
        update(Activity)
        .where(Activity.user_id == user.id, Activity.read_at.is_(None))
        .values(read_at=datetime.now(UTC))
    )
    await session.commit()
    return {"unread": 0}
