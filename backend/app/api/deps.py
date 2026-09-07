from uuid import UUID

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.core.security import decode_access_token
from app.db import get_session
from app.models import User
from app.services.azure_openai import AzureOpenAIExtractor

_bearer = HTTPBearer(auto_error=True)


def get_extractor() -> AzureOpenAIExtractor:
    """Overridable in tests."""
    return AzureOpenAIExtractor()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
    session: AsyncSession = Depends(get_session),
) -> User:
    settings = get_settings()
    creds_error = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired token.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = decode_access_token(
            credentials.credentials,
            secret=settings.jwt_secret,
            algorithm=settings.jwt_algorithm,
        )
        user_id = UUID(str(payload["sub"]))
    except Exception as exc:  # noqa: BLE001
        raise creds_error from exc

    user = await session.get(User, user_id)
    if user is None or not user.is_active:
        raise creds_error
    return user
