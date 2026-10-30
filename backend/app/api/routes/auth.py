import re

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import delete as sa_delete
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.config import get_settings
from app.db import get_session
from app.models import (
    Activity,
    Budget,
    Expense,
    Group,
    GroupMember,
    Person,
    PersonPayment,
    Receipt,
    Settlement,
    Split,
    SplitComment,
    SplitEvent,
    SplitParticipant,
    User,
)
from app.schemas.auth import MeOut, MeSettingsIn
from app.services.blob_storage import BlobStorage

router = APIRouter()


async def _me_out(session: AsyncSession, user: User) -> MeOut:
    out = MeOut.model_validate(user)
    if user.currency:
        out.currency, out.currency_is_set = user.currency, True
    else:
        # The currency your receipts use most.
        out.currency = await session.scalar(
            select(Receipt.currency)
            .where(Receipt.user_id == user.id, Receipt.currency != "")
            .group_by(Receipt.currency)
            .order_by(func.count().desc())
            .limit(1)
        )
    return out


@router.get("/me", response_model=MeOut)
async def me(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> MeOut:
    """Return (and lazily provision) the current user. The web/iOS clients call
    this right after login to confirm the session and get the profile."""
    return await _me_out(session, user)


@router.patch("/me", response_model=MeOut)
async def update_me(
    data: MeSettingsIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> MeOut:
    """Notification emails, how people pay you back, and your home currency."""
    me = await session.get(User, user.id)
    if data.email_notifications is not None:
        me.email_notifications = data.email_notifications
    if data.interac is not None:
        me.interac = _interac(data.interac)
    if data.currency is not None:
        code = data.currency.strip().upper()
        if code and not re.fullmatch(r"[A-Z]{3}", code):
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_CONTENT, "Use a currency code like CAD."
            )
        me.currency = code
    await session.commit()
    await session.refresh(me)
    return await _me_out(session, me)


def _interac(value: str) -> str:
    value = value.strip()
    if not value:
        return ""
    if re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value):
        return value.lower()
    digits = re.sub(r"[\s().-]", "", value)
    if re.fullmatch(r"\+?\d{10,15}", digits):
        return digits
    raise HTTPException(
        status.HTTP_422_UNPROCESSABLE_CONTENT, "Use the email or phone number your bank sends to."
    )


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_me(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    """Permanently delete the account and everything in it. Irreversible.

    The client should sign out afterwards; a later sign-in with the same
    identity provisions a fresh, empty account.
    """
    settings = get_settings()
    blob = BlobStorage(settings) if settings.blob_configured else None
    if blob is not None:
        urls = await session.scalars(
            select(Receipt.image_blob_url).where(
                Receipt.user_id == user.id, Receipt.image_blob_url.is_not(None)
            )
        )
        blob_urls = [u for u in urls if u]
    else:
        blob_urls = []

    # Explicit deletes — don't rely on DB ON DELETE CASCADE (SQLite tests skip it).
    # Splits and groups (docs/SPLITS.md): your splits go; your memberships stay
    # as placeholders under your name so other people's balances survive.
    owned = list(await session.scalars(select(Split.id).where(Split.owner_user_id == user.id)))
    await session.execute(sa_delete(Activity).where(Activity.user_id == user.id))
    await session.execute(
        sa_delete(SplitComment).where(
            (SplitComment.user_id == user.id) | SplitComment.split_id.in_(owned)
        )
    )
    await session.execute(sa_delete(SplitEvent).where(SplitEvent.split_id.in_(owned)))
    # Their edits on other people's expenses stay in the history, unnamed.
    await session.execute(
        update(SplitEvent)
        .where(SplitEvent.user_id == user.id)
        .values(user_id=None, actor_name="Someone")
    )
    if owned:
        await session.execute(
            sa_delete(SplitParticipant).where(SplitParticipant.split_id.in_(owned))
        )
        await session.execute(sa_delete(Split).where(Split.id.in_(owned)))
    await session.execute(
        update(SplitParticipant).where(SplitParticipant.user_id == user.id).values(user_id=None)
    )
    await session.execute(
        update(GroupMember).where(GroupMember.user_id == user.id).values(user_id=None)
    )
    # Your people and payments go; on other people's lists you go back to
    # being just a name.
    my_people = select(Person.id).where(Person.owner_user_id == user.id)
    await session.execute(
        update(SplitParticipant)
        .where(SplitParticipant.person_id.in_(my_people))
        .values(person_id=None)
    )
    await session.execute(
        sa_delete(PersonPayment).where(
            (PersonPayment.owner_user_id == user.id) | PersonPayment.person_id.in_(my_people)
        )
    )
    await session.execute(sa_delete(Person).where(Person.owner_user_id == user.id))
    await session.execute(update(Person).where(Person.user_id == user.id).values(user_id=None))
    await session.execute(
        update(Group).where(Group.owner_user_id == user.id).values(owner_user_id=None)
    )
    await session.execute(
        update(Settlement)
        .where(Settlement.created_by_user_id == user.id)
        .values(created_by_user_id=None)
    )
    await session.execute(sa_delete(Expense).where(Expense.user_id == user.id))
    await session.execute(sa_delete(Receipt).where(Receipt.user_id == user.id))
    await session.execute(sa_delete(Budget).where(Budget.user_id == user.id))
    await session.execute(sa_delete(User).where(User.id == user.id))
    await session.commit()

    for url in blob_urls:
        await blob.delete_by_url(url)  # type: ignore[union-attr]  (blob set when urls non-empty)

    return Response(status_code=status.HTTP_204_NO_CONTENT)
