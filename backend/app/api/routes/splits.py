"""Splits — divide a receipt or expense between people (docs/SPLITS.md)."""

from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db import get_session
from app.models import Split, SplitComment, SplitEvent, SplitParticipant, User
from app.schemas.split import (
    CommentIn,
    SettledIn,
    SplitAdjustIn,
    SplitIn,
    SplitOut,
    TimelineEntry,
)
from app.services import activity, split_store

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
    await split_store.delete_split(session, split, actor=user)
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
    if (row.settled_at is not None) != data.settled:
        row.settled_at = datetime.now(UTC) if data.settled else None
        state = "paid" if data.settled else "not paid"
        await split_store.log_event(
            session, split, user, f"marked {row.display_name}'s share {state}"
        )
    await session.commit()
    return await split_store.split_out(session, split, user)


@router.patch("/splits/{split_id}", response_model=SplitOut)
async def adjust_split(
    split_id: UUID,
    data: SplitAdjustIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> SplitOut:
    """Anyone on the expense (or in its group) changes the amounts, who paid,
    or how it's divided. Logged in its history; the others are told."""
    split = await split_store.require_split(session, split_id, user)
    split = await split_store.adjust_split(session, user, split, data)
    await session.commit()
    return await split_store.split_out(session, split, user)


@router.get("/splits/{split_id}/timeline", response_model=list[TimelineEntry])
async def timeline(
    split_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[TimelineEntry]:
    """The expense's history (added, every change) and its comments, oldest first."""
    split = await split_store.require_split(session, split_id, user)
    entries = [
        TimelineEntry(
            id=e.id,
            kind="event",
            author_name=e.actor_name,
            text=e.text,
            at=_iso(e.created_at),
            can_delete=False,
        )
        for e in await session.scalars(select(SplitEvent).where(SplitEvent.split_id == split.id))
    ] + [
        TimelineEntry(
            id=c.id,
            kind="comment",
            author_name=c.author_name,
            text=c.body,
            at=_iso(c.created_at),
            can_delete=c.user_id == user.id,
        )
        for c in await session.scalars(
            select(SplitComment).where(SplitComment.split_id == split.id)
        )
    ]
    return sorted(entries, key=lambda e: e.at)


@router.post(
    "/splits/{split_id}/comments",
    response_model=list[TimelineEntry],
    status_code=status.HTTP_201_CREATED,
)
async def add_comment(
    split_id: UUID,
    data: CommentIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[TimelineEntry]:
    split = await split_store.require_split(session, split_id, user)
    body = data.body.strip()
    if not body:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Write something first.")
    session.add(
        SplitComment(
            split_id=split.id,
            user_id=user.id,
            author_name=split_store.display_name_for(user)[:120],
            body=body,
        )
    )
    rows = await session.scalars(
        select(SplitParticipant.user_id).where(SplitParticipant.split_id == split.id)
    )
    preview = body if len(body) <= 80 else body[:77] + "…"
    await activity.notify(
        session,
        set(rows),
        user,
        "comment",
        f'commented on "{split.description}": {preview}',
        split_id=split.id,
        group_id=split.group_id,
    )
    await session.commit()
    return await timeline(split_id, user, session)


@router.delete("/splits/{split_id}/comments/{comment_id}", response_model=list[TimelineEntry])
async def delete_comment(
    split_id: UUID,
    comment_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[TimelineEntry]:
    split = await split_store.require_split(session, split_id, user)
    comment = await session.get(SplitComment, comment_id)
    if comment is None or comment.split_id != split.id or comment.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Comment not found.")
    await session.delete(comment)
    await session.commit()
    return await timeline(split_id, user, session)


def _iso(moment: datetime | None) -> str:
    moment = moment or datetime.now(UTC)
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=UTC)
    return moment.isoformat()
