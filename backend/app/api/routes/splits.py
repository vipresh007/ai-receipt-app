"""Splits — divide a receipt or expense between people (docs/SPLITS.md)."""

from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db import get_session
from app.models import Split, SplitParticipant, User
from app.schemas.split import SettledIn, SplitIn, SplitOut
from app.services import split_store

router = APIRouter()


@router.post("/splits", response_model=SplitOut, status_code=status.HTTP_201_CREATED)
async def create_split(
    data: SplitIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> SplitOut:
    split = await split_store.save_split(session, user, None, data)
    await session.commit()
    return await split_store.split_out(session, split, user)


@router.get("/splits", response_model=list[SplitOut])
async def list_splits(
    group_id: UUID | None = None,
    receipt_id: UUID | None = None,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[SplitOut]:
    """Your splits, or a group's (if you're in it), or a receipt's."""
    query = select(Split)
    if group_id is not None:
        await split_store.require_member(session, group_id, user)
        query = query.where(Split.group_id == group_id)
    else:
        query = query.where(Split.owner_user_id == user.id)
    if receipt_id is not None:
        query = query.where(Split.receipt_id == receipt_id)
    splits = await session.scalars(query.order_by(Split.spent_at.desc(), Split.created_at.desc()))
    return [await split_store.split_out(session, s, user) for s in splits]


@router.get("/splits/{split_id}", response_model=SplitOut)
async def get_split(
    split_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> SplitOut:
    split = await split_store.require_split(session, split_id, user)
    return await split_store.split_out(session, split, user)


@router.put("/splits/{split_id}", response_model=SplitOut)
async def replace_split(
    split_id: UUID,
    data: SplitIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> SplitOut:
    split = await split_store.require_split(session, split_id, user)
    if split.owner_user_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Only the person who added it can edit it.")
    split = await split_store.save_split(session, user, split, data)
    await session.commit()
    return await split_store.split_out(session, split, user)


@router.delete("/splits/{split_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_split(
    split_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    split = await split_store.require_split(session, split_id, user)
    if split.owner_user_id != user.id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "Only the person who added it can delete it."
        )
    await split_store.delete_split(session, split)
    await session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/splits/{split_id}/participants/{participant_id}/settled", response_model=SplitOut)
async def set_settled(
    split_id: UUID,
    participant_id: UUID,
    data: SettledIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> SplitOut:
    """Tick a person's share paid on a one-off split (groups use settlements)."""
    split = await split_store.require_split(session, split_id, user)
    if split.owner_user_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Only the person who added it can do that.")
    row = await session.get(SplitParticipant, participant_id)
    if row is None or row.split_id != split.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Person not found on this split.")
    row.settled_at = datetime.now(UTC) if data.settled else None
    await session.commit()
    return await split_store.split_out(session, split, user)
