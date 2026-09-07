from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.core.security import create_access_token, hash_password, verify_password
from app.db import get_session
from app.models import User
from app.schemas.auth import LoginIn, RegisterIn, TokenOut

router = APIRouter()


def _issue_token(user: User) -> TokenOut:
    s = get_settings()
    token = create_access_token(
        str(user.id),
        secret=s.jwt_secret,
        ttl_minutes=s.access_token_ttl_minutes,
        algorithm=s.jwt_algorithm,
    )
    return TokenOut(access_token=token, expires_in=s.access_token_ttl_minutes * 60)


@router.post("/register", response_model=TokenOut, status_code=status.HTTP_201_CREATED)
async def register(body: RegisterIn, session: AsyncSession = Depends(get_session)) -> TokenOut:
    email = body.email.lower()
    exists = await session.scalar(select(User).where(User.email == email))
    if exists:
        raise HTTPException(status.HTTP_409_CONFLICT, "Email already registered.")
    user = User(
        email=email,
        hashed_password=hash_password(body.password),
        display_name=body.display_name,
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return _issue_token(user)


@router.post("/login", response_model=TokenOut)
async def login(body: LoginIn, session: AsyncSession = Depends(get_session)) -> TokenOut:
    user = await session.scalar(select(User).where(User.email == body.email.lower()))
    if user is None or not verify_password(body.password, user.hashed_password):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Incorrect email or password.")
    return _issue_token(user)
