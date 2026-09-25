from fastapi import APIRouter, Depends, Response, status
from sqlalchemy import delete as sa_delete
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.config import get_settings
from app.db import get_session
from app.models import Budget, Expense, Receipt, User
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
    await session.execute(sa_delete(Expense).where(Expense.user_id == user.id))
    await session.execute(sa_delete(Receipt).where(Receipt.user_id == user.id))
    await session.execute(sa_delete(Budget).where(Budget.user_id == user.id))
    await session.execute(sa_delete(User).where(User.id == user.id))
    await session.commit()

    for url in blob_urls:
        await blob.delete_by_url(url)  # type: ignore[union-attr]  (blob set when urls non-empty)

    return Response(status_code=status.HTTP_204_NO_CONTENT)
