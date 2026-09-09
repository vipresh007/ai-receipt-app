from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import TokenError, verify_access_token
from app.db import get_session
from app.models import User
from app.services.auth0 import fetch_userinfo
from app.services.azure_openai import AzureOpenAIExtractor

_bearer = HTTPBearer(auto_error=True)

_CREDS_ERROR = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Invalid or expired token.",
    headers={"WWW-Authenticate": "Bearer"},
)


def get_extractor() -> AzureOpenAIExtractor:
    """Overridable in tests."""
    return AzureOpenAIExtractor()


_bearer_optional = HTTPBearer(auto_error=False)


async def _user_from_token(session: AsyncSession, token: str) -> User:
    """Verify an Auth0 access token → local `users` row, provisioning on first sight."""
    try:
        claims = verify_access_token(token)
        sub = str(claims["sub"])
    except (TokenError, KeyError) as exc:
        raise _CREDS_ERROR from exc

    user = await session.scalar(select(User).where(User.auth0_sub == sub))
    if user is None:
        user = await _provision_user(session, sub, token)
    if not user.is_active:
        raise _CREDS_ERROR
    return user


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
    session: AsyncSession = Depends(get_session),
) -> User:
    return await _user_from_token(session, credentials.credentials)


async def get_current_user_optional(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_optional),
    session: AsyncSession = Depends(get_session),
) -> User | None:
    """`None` when no Authorization header is sent (anonymous / local-first
    client). A present-but-invalid token still 401s."""
    if credentials is None:
        return None
    return await _user_from_token(session, credentials.credentials)


async def _provision_user(session: AsyncSession, sub: str, access_token: str) -> User:
    try:
        info = await fetch_userinfo(access_token)
    except Exception as exc:  # noqa: BLE001
        raise _CREDS_ERROR from exc

    email = (info.get("email") or "").strip().lower()
    name = info.get("name") or info.get("nickname") or ""

    # Link an existing email/password-era row if the addresses match.
    existing = await session.scalar(select(User).where(User.email == email)) if email else None
    if existing is not None:
        existing.auth0_sub = sub
        if not existing.display_name:
            existing.display_name = name
        await session.commit()
        await session.refresh(existing)
        return existing

    user = User(
        auth0_sub=sub,
        email=email or f"{sub}@users.noreply.ai-receipt",
        display_name=name,
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user
