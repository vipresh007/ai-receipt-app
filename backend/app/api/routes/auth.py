from fastapi import APIRouter, Depends, Response, status
from sqlalchemy import delete as sa_delete
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.config import get_settings
from app.db import get_session
from app.models import (
    Budget,
    Expense,
    Group,
    GroupMember,
    Receipt,
    Settlement,
    Split,
    SplitParticipant,
    User,
)
from app.schemas.auth import MeOut
from app.services.blob_storage import BlobStorage

router = APIRouter()


@router.get("/me", response_model=MeOut)
async def me(user: User = Depends(get_current_user)) -> User:
    """Return (and lazily provision) the current user. The web/iOS clients call
    this right after login to confirm the session and get the profile."""
    return user


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
