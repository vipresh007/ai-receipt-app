"""Groups — people who share expenses, with balances and settle-up (docs/SPLITS.md)."""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db import get_session
from app.models import Group, GroupMember, Settlement, User
from app.schemas.split import (
    GroupDetailOut,
    GroupIn,
    GroupPatch,
    GroupSummaryOut,
    JoinIn,
    MemberIn,
    SettlementIn,
)
from app.services import split_store

router = APIRouter()


@router.get("", response_model=list[GroupSummaryOut])
async def list_groups(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[GroupSummaryOut]:
    groups = await session.scalars(
        select(Group)
        .join(GroupMember, GroupMember.group_id == Group.id)
        .where(GroupMember.user_id == user.id)
        .order_by(Group.created_at.desc())
    )
    return [await split_store.group_summary(session, g, user) for g in groups]


@router.post("", response_model=GroupDetailOut, status_code=status.HTTP_201_CREATED)
async def create_group(
    data: GroupIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> GroupDetailOut:
    group = Group(
        name=data.name.strip(),
        owner_user_id=user.id,
        currency=(data.currency or "CAD").upper()[:3],
        invite_token=split_store.new_token(),
    )
    session.add(group)
    await session.flush()
    session.add(
        GroupMember(
            group_id=group.id,
            user_id=user.id,
            display_name=split_store.display_name_for(user),
            position=0,
        )
    )
    names = [n.strip()[:120] for n in data.members if n.strip()]
    for position, name in enumerate(names, start=1):
        session.add(GroupMember(group_id=group.id, display_name=name, position=position))
    await session.commit()
    return await split_store.group_detail(session, group, user)


@router.get("/{group_id}", response_model=GroupDetailOut)
async def get_group(
    group_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> GroupDetailOut:
    group, _ = await split_store.require_member(session, group_id, user)
    return await split_store.group_detail(session, group, user)


@router.patch("/{group_id}", response_model=GroupDetailOut)
async def rename_group(
    group_id: UUID,
    data: GroupPatch,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> GroupDetailOut:
    group, _ = await split_store.require_member(session, group_id, user)
    group.name = data.name.strip()
    await session.commit()
    return await split_store.group_detail(session, group, user)


@router.delete("/{group_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_group(
    group_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    group, _ = await split_store.require_member(session, group_id, user)
    if group.owner_user_id != user.id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "Only the person who made the group can delete it."
        )
    await split_store.delete_group(session, group)
    await session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/{group_id}/members", response_model=GroupDetailOut, status_code=status.HTTP_201_CREATED
)
async def add_member(
    group_id: UUID,
    data: MemberIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> GroupDetailOut:
    group, _ = await split_store.require_member(session, group_id, user)
    position = await split_store.next_position(session, group.id)
    session.add(
        GroupMember(group_id=group.id, display_name=data.name.strip()[:120], position=position)
    )
    await session.commit()
    return await split_store.group_detail(session, group, user)


@router.delete("/{group_id}/members/{member_id}", response_model=GroupDetailOut)
async def remove_member(
    group_id: UUID,
    member_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> GroupDetailOut:
    """Remove someone who isn't on any expense yet (otherwise balances would
    change under everyone)."""
    group, me = await split_store.require_member(session, group_id, user)
    member = await session.get(GroupMember, member_id)
    if member is None or member.group_id != group.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Member not found.")
    if await split_store.member_in_use(session, member.id):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "They're on an expense or payment in this group, so they can't be removed.",
        )
    if member.user_id is not None and member.id != me.id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "People with an account leave the group themselves."
        )
    await session.delete(member)
    await session.commit()
    return await split_store.group_detail(session, group, user)


@router.post(
    "/{group_id}/settlements", response_model=GroupDetailOut, status_code=status.HTTP_201_CREATED
)
async def add_settlement(
    group_id: UUID,
    data: SettlementIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> GroupDetailOut:
    """Record a payment between two members ("Kim paid Alex $45")."""
    group, _ = await split_store.require_member(session, group_id, user)
    ids = {data.from_member_id, data.to_member_id}
    found = await session.scalars(
        select(GroupMember.id).where(GroupMember.group_id == group.id, GroupMember.id.in_(ids))
    )
    if len(ids) != 2 or len(set(found)) != 2:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "Pick two different people in this group."
        )
    amount = split_store._money(data.amount, "amount")
    if amount == 0:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Enter an amount.")
    session.add(
        Settlement(
            group_id=group.id,
            from_member_id=data.from_member_id,
            to_member_id=data.to_member_id,
            amount=amount,
            note=data.note.strip(),
            created_by_user_id=user.id,
        )
    )
    await session.commit()
    return await split_store.group_detail(session, group, user)


@router.delete("/{group_id}/settlements/{settlement_id}", response_model=GroupDetailOut)
async def delete_settlement(
    group_id: UUID,
    settlement_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> GroupDetailOut:
    group, _ = await split_store.require_member(session, group_id, user)
    settlement = await session.get(Settlement, settlement_id)
    if settlement is None or settlement.group_id != group.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Payment not found.")
    await session.delete(settlement)
    await session.commit()
    return await split_store.group_detail(session, group, user)


@router.post("/join/{invite_token}", response_model=GroupDetailOut)
async def join_group(
    invite_token: str,
    data: JoinIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> GroupDetailOut:
    """Join through an invite link, optionally as the placeholder with your name."""
    group = await session.scalar(select(Group).where(Group.invite_token == invite_token))
    if group is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "This invite link isn't valid any more.")
    existing = await session.scalar(
        select(GroupMember).where(GroupMember.group_id == group.id, GroupMember.user_id == user.id)
    )
    if existing is None:
        if data.member_id is not None:
            member = await session.get(GroupMember, data.member_id)
            if member is None or member.group_id != group.id or member.user_id is not None:
                raise HTTPException(status.HTTP_409_CONFLICT, "That name has already been claimed.")
            member.user_id = user.id
        else:
            session.add(
                GroupMember(
                    group_id=group.id,
                    user_id=user.id,
                    display_name=split_store.display_name_for(user),
                    position=await split_store.next_position(session, group.id),
                )
            )
        await session.commit()
    return await split_store.group_detail(session, group, user)
