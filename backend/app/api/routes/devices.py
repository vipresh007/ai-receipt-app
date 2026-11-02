"""iPhones registering for push notifications (services/push.py)."""

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db import get_session
from app.models import DeviceToken, User
from app.services import push

router = APIRouter()


class DeviceIn(BaseModel):
    token: str = Field(min_length=20, max_length=200, pattern=r"^[0-9a-fA-F]+$")
    environment: Literal["production", "sandbox"] = "production"


@router.post("", status_code=status.HTTP_204_NO_CONTENT)
async def register(
    data: DeviceIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    token = data.token.lower()
    row = await session.scalar(select(DeviceToken).where(DeviceToken.token == token))
    if row is None:
        session.add(DeviceToken(user_id=user.id, token=token, environment=data.environment))
    else:  # the phone changed hands (or accounts): it follows the new sign-in
        row.user_id = user.id
        row.environment = data.environment
    await session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/test")
async def send_test(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Push "Notifications are working" to this account's iPhones."""
    if not push.configured():
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Push notifications aren't set up on the server yet.",
        )
    devices = await session.scalar(
        select(func.count(DeviceToken.id)).where(DeviceToken.user_id == user.id)
    )
    if not devices:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "This iPhone hasn't registered yet. Allow notifications for Tally, then try again.",
        )
    await push.send(
        session, [user.id], "Notifications are working. You'll hear about shared expenses here."
    )
    return {"devices": devices}


@router.delete("/{token}", status_code=status.HTTP_204_NO_CONTENT)
async def unregister(
    token: str,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    await session.execute(
        delete(DeviceToken).where(
            DeviceToken.token == token.lower(), DeviceToken.user_id == user.id
        )
    )
    await session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
