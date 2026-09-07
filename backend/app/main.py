import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import auth, expenses, health, insights, receipts
from app.config import get_settings
from app.telemetry import configure_telemetry

logger = logging.getLogger(__name__)
settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    configure_telemetry(app)
    if settings.auto_create_tables:
        try:
            from app.db import create_all

            await create_all()
            logger.info("Ensured database tables exist (AUTO_CREATE_TABLES).")
        except Exception:  # noqa: BLE001 - don't crash if the DB isn't up yet
            logger.warning("create_all() failed on startup", exc_info=True)
    yield


app = FastAPI(title="AI Receipt API", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(auth.router, prefix="/v1/auth", tags=["auth"])
app.include_router(receipts.router, prefix="/v1", tags=["receipts"])
app.include_router(expenses.router, prefix="/v1/expenses", tags=["expenses"])
app.include_router(insights.router, prefix="/v1/insights", tags=["insights"])


@app.get("/")
async def root() -> dict:
    return {"name": "AI Receipt API", "docs": "/docs", "health": "/healthz"}
