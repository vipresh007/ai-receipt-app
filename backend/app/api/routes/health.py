from fastapi import APIRouter

from app.config import get_settings

router = APIRouter(tags=["health"])


@router.get("/healthz")
async def healthz() -> dict:
    s = get_settings()
    return {
        "status": "ok",
        "environment": s.environment,
        "auth_configured": s.auth_configured,
        "azure_openai_configured": s.azure_openai_configured,
        "blob_configured": s.blob_configured,
    }
