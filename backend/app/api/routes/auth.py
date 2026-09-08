from fastapi import APIRouter, Depends

from app.api.deps import get_current_user
from app.models import User
from app.schemas.auth import MeOut

router = APIRouter()


@router.get("/me", response_model=MeOut)
async def me(user: User = Depends(get_current_user)) -> User:
    """Return (and lazily provision) the current user. The web/iOS clients call
    this right after login to confirm the session and get the profile."""
    return user
