"""Public views behind share and invite links — no account needed (docs/SPLITS.md).

A share link shows a snapshot of one split: description, date, items, names
and amounts. Never the receipt image or anything else in the account.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.models import Group, GroupMember, Split, SplitParticipant
from app.schemas.receipt import ExtractionItemOut
from app.schemas.split import (
    PublicGroupOut,
    PublicMemberOut,
    PublicParticipantOut,
    PublicSplitOut,
)

router = APIRouter()


@router.get("/splits/{share_token}", response_model=PublicSplitOut)
async def public_split(
    share_token: str, session: AsyncSession = Depends(get_session)
) -> PublicSplitOut:
    viewer = await session.scalar(
        select(SplitParticipant).where(SplitParticipant.share_token == share_token)
    )
    split = await session.get(Split, viewer.split_id) if viewer else None
    if viewer is None or split is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "This link isn't valid any more.")
    rows = list(
        await session.scalars(
            select(SplitParticipant)
            .where(SplitParticipant.split_id == split.id)
            .order_by(SplitParticipant.position, SplitParticipant.created_at)
        )
    )
    group = await session.get(Group, split.group_id) if split.group_id else None
    names: dict = {}
    if group is not None:
        names = {
            m.id: m.display_name
            for m in await session.scalars(
                select(GroupMember).where(GroupMember.group_id == group.id)
            )
        }

    def name(r: SplitParticipant) -> str:
        return names.get(r.member_id, r.display_name) if r.member_id else r.display_name

    payer = next((r for r in rows if r.is_payer), None)
    return PublicSplitOut(
        description=split.description,
        date=split.spent_at.isoformat(),
        currency=split.currency,
        total=f"{split.total:.2f}",
        items=[ExtractionItemOut(**i) for i in (split.line_items or [])],
        participants=[
            PublicParticipantOut(
                display_name=name(r),
                share=f"{r.share:.2f}",
                is_you=r.id == viewer.id,
                is_payer=r.is_payer,
                settled=r.settled_at is not None,
                item_indexes=list(r.item_indexes or []),
            )
            for r in rows
        ],
        payer_name=name(payer) if payer else None,
        group_name=group.name if group else None,
        your_share=f"{viewer.share:.2f}",
    )


@router.get("/groups/{invite_token}", response_model=PublicGroupOut)
async def public_group(
    invite_token: str, session: AsyncSession = Depends(get_session)
) -> PublicGroupOut:
    group = await session.scalar(select(Group).where(Group.invite_token == invite_token))
    if group is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "This invite link isn't valid any more.")
    members = await session.scalars(
        select(GroupMember)
        .where(GroupMember.group_id == group.id)
        .order_by(GroupMember.position, GroupMember.created_at)
    )
    return PublicGroupOut(
        name=group.name,
        members=[
            PublicMemberOut(id=m.id, display_name=m.display_name, claimed=m.user_id is not None)
            for m in members
        ],
    )
