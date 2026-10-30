"""Groups — people who share expenses, with balances and settle-up (docs/SPLITS.md)."""

import html
from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.config import get_settings
from app.db import get_session
from app.models import Group, GroupMember, Settlement, User
from app.schemas.split import (
    GroupDetailOut,
    GroupIn,
    GroupPatch,
    GroupSummaryOut,
    JoinIn,
    MemberIn,
    MemberPatch,
    SettlementIn,
)
from app.services import activity, people_store, split_store
from app.services.mailer import Mailer, get_mailer

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
    await split_store.publish_group(session, group.id)
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
    """Rename it, or switch simplify debts (any member, like Splitwise)."""
    group, _ = await split_store.require_member(session, group_id, user)
    if data.name is not None:
        group.name = data.name.strip()
    if data.simplify_debts is not None and data.simplify_debts != group.simplify_debts:
        group.simplify_debts = data.simplify_debts
        others = await session.scalars(
            select(GroupMember.user_id).where(
                GroupMember.group_id == group.id, GroupMember.user_id.is_not(None)
            )
        )
        state = "on" if data.simplify_debts else "off"
        await activity.notify(
            session,
            set(others),
            user,
            "group_changed",
            f"turned {state} simplify debts in {group.name}",
            group_id=group.id,
        )
    await split_store.publish_group(session, group.id)
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
    await split_store.publish_group(session, group.id)
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
    mailer: Mailer | None = Depends(get_mailer),
) -> GroupDetailOut:
    group, _ = await split_store.require_member(session, group_id, user)
    position = await split_store.next_position(session, group.id)
    member = GroupMember(
        group_id=group.id,
        display_name=data.name.strip()[:120],
        position=position,
        email=people_store.clean_email(data.email),
    )
    session.add(member)
    await split_store.publish_group(session, group.id)
    # Saved even if the invite below can't go out (the link still works).
    await session.commit()
    if data.send_invite:
        await _send_member_invite(session, user, group, member, mailer)
        await session.commit()
    return await split_store.group_detail(session, group, user)


@router.patch("/{group_id}/members/{member_id}", response_model=GroupDetailOut)
async def edit_member(
    group_id: UUID,
    member_id: UUID,
    data: MemberPatch,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> GroupDetailOut:
    """Rename someone who hasn't joined, or set the email their invite goes to."""
    group, _ = await split_store.require_member(session, group_id, user)
    member = await session.get(GroupMember, member_id)
    if member is None or member.group_id != group.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Member not found.")
    if member.user_id is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "They've joined; their name is their own.")
    if data.name is not None:
        member.display_name = data.name.strip()[:120]
    if data.email is not None:
        email = people_store.clean_email(data.email)
        if email != member.email:
            member.email = email
            member.invited_at = None
    await split_store.publish_group(session, group.id)
    await session.commit()
    return await split_store.group_detail(session, group, user)


@router.post("/{group_id}/members/{member_id}/invite", response_model=GroupDetailOut)
async def invite_member(
    group_id: UUID,
    member_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    mailer: Mailer | None = Depends(get_mailer),
) -> GroupDetailOut:
    """Email someone the group's invite, with their name already chosen."""
    group, _ = await split_store.require_member(session, group_id, user)
    member = await session.get(GroupMember, member_id)
    if member is None or member.group_id != group.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Member not found.")
    await _send_member_invite(session, user, group, member, mailer)
    await session.commit()
    return await split_store.group_detail(session, group, user)


GROUP_DAILY_INVITES = 20


async def _send_member_invite(
    session: AsyncSession, user: User, group: Group, member: GroupMember, mailer: Mailer | None
) -> None:
    if mailer is None:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Email invites aren't available right now. Send the invite link instead.",
        )
    if not member.email:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Add their email first.")
    if member.user_id is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "They've already joined.")
    now = datetime.now(UTC)
    last = member.invited_at
    if last is not None and last.tzinfo is None:
        last = last.replace(tzinfo=UTC)
    if last is not None and now - last < people_store.INVITE_COOLDOWN:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "An invite just went to them. Try again in a few minutes, or send the link.",
        )
    sent_today = await session.scalar(
        select(func.count(GroupMember.id)).where(
            GroupMember.group_id == group.id, GroupMember.invited_at > now - timedelta(days=1)
        )
    )
    if (sent_today or 0) >= GROUP_DAILY_INVITES:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "That's the most invite emails for this group today. You can still send the link.",
        )
    inviter = split_store.display_name_for(user)[:60]
    url = split_store.member_invite_url(group, member)
    e = html.escape
    try:
        await mailer.send(
            to=member.email,
            subject=f"{inviter} invited you to {group.name} on Tally",
            text=(
                f"Hi {member.display_name},\n\n{inviter} added you to {group.name} on Tally, "
                "to keep track of what you spend together and who owes whom.\n\n"
                f"Join here (your name's already picked):\n{url}\n\n"
                f"You got this because {inviter} added your email. "
                "If you don't know them, ignore this email and nothing else will be sent.\n"
            ),
            html=(
                '<div style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;'
                'max-width:520px;margin:0 auto;color:#1E2321">'
                f'<p style="font-size:16px">Hi {e(member.display_name)},</p>'
                f'<p style="font-size:16px">{e(inviter)} added you to <strong>{e(group.name)}'
                "</strong> on Tally, to keep track of what you spend together and who owes "
                "whom.</p>"
                f'<p style="margin:28px 0"><a href="{e(url)}" style="background:#8A5E0F;'
                "color:#fff;text-decoration:none;padding:12px 22px;border-radius:999px;"
                f'font-weight:600;display:inline-block">Join {e(group.name)}</a></p>'
                '<p style="font-size:13px;color:#5B5F59">You got this because '
                f"{e(inviter)} added your email. If you don't know them, ignore this email "
                "and nothing else will be sent.</p></div>"
            ),
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, "Couldn't send the email. Send the invite link instead."
        ) from exc
    member.invited_at = now


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
    await split_store.publish_group(session, group.id)
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
    payer = await session.get(GroupMember, data.from_member_id)
    payee = await session.get(GroupMember, data.to_member_id)
    await activity.notify(
        session,
        [payer.user_id, payee.user_id],
        user,
        "payment",
        f"recorded that {payer.display_name} paid {payee.display_name} "
        f"{split_store._money_text(amount, group.currency)} in {group.name}",
        group_id=group.id,
        link=f"{get_settings().public_web_url}/groups/{group.id}",
    )
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
    await split_store.publish_group(session, group.id)
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
    await split_store.publish_group(session, group.id)
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
        others = await session.scalars(
            select(GroupMember.user_id).where(
                GroupMember.group_id == group.id, GroupMember.user_id.is_not(None)
            )
        )
        await activity.notify(
            session, set(others), user, "joined", f"joined {group.name}", group_id=group.id
        )
        await split_store.publish_group(session, group.id)
    await session.commit()
    return await split_store.group_detail(session, group, user)


@router.post("/{group_id}/members/{member_id}/remind", response_model=GroupDetailOut)
async def remind_member(
    group_id: UUID,
    member_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> GroupDetailOut:
    """Nudge someone who owes you in this group (in the app, and by email)."""
    group, me = await split_store.require_member(session, group_id, user)
    member = await session.get(GroupMember, member_id)
    if member is None or member.group_id != group.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Member not found.")
    if member.user_id is None:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "They haven't joined yet. Send them the invite link instead.",
        )
    owes = await split_store.member_owes(session, group, member.id, me.id)
    if owes <= 0:
        raise HTTPException(status.HTTP_409_CONFLICT, "They don't owe you anything here.")
    last = member.reminded_at
    if last is not None and last.tzinfo is None:
        last = last.replace(tzinfo=UTC)
    if last is not None and datetime.now(UTC) - last < timedelta(days=1):
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "You reminded them today already.")
    member.reminded_at = datetime.now(UTC)
    await activity.notify(
        session,
        [member.user_id],
        user,
        "reminder",
        f"sent a reminder: you owe them "
        f"{split_store._money_text(owes, group.currency)} in {group.name}",
        group_id=group.id,
        link=f"{get_settings().public_web_url}/groups/{group.id}",
    )
    await split_store.publish_group(session, group.id)
    await session.commit()
    return await split_store.group_detail(session, group, user)
