"""People you've blocked (services/safety.py)."""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db import get_session
from app.models import User, UserBlock
from app.schemas.split import BlockIn, BlockOut
from app.services import safety

router = APIRouter()


async def _list(session: AsyncSession, user: User) -> list[BlockOut]:
    rows = await session.scalars(
        select(UserBlock).where(UserBlock.blocker_id == user.id).order_by(UserBlock.created_at)
    )
    return [BlockOut(user_id=b.blocked_id, name=b.blocked_name) for b in rows]


@router.get("", response_model=list[BlockOut])
async def list_blocks(
    user: User = Depends(get_current_user), session: AsyncSession = Depends(get_session)
) -> list[BlockOut]:
    return await _list(session, user)


@router.post("", response_model=list[BlockOut], status_code=status.HTTP_201_CREATED)
async def add_block(
    data: BlockIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[BlockOut]:
    if data.user_id == user.id:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "You can't block yourself.")
    target = await session.get(User, data.user_id)
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Person not found.")
    await safety.block(session, user, target.id, data.name or (target.display_name or "Someone"))
    await session.commit()
    return await _list(session, user)


@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_block(
    user_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    await session.execute(
        delete(UserBlock).where(UserBlock.blocker_id == user.id, UserBlock.blocked_id == user_id)
    )
    await session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
