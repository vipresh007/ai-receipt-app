import asyncio
import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.routes import (
    activity,
    auth,
    budgets,
    events,
    expenses,
    export,
    groups,
    health,
    people,
    public,
    receipts,
    splits,
)
from app.config import get_settings
from app.telemetry import configure_telemetry

logger = logging.getLogger(__name__)
settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    configure_telemetry(app)
    if settings.auto_create_tables:
        try:
            from app.db_migrate import bootstrap_schema

            await bootstrap_schema()
        except Exception:  # noqa: BLE001 - don't crash if the DB isn't up yet
            logger.warning("schema bootstrap failed on startup", exc_info=True)
    repeat_task = None
    if not os.environ.get("AI_RECEIPT_TEST"):
        from app.db import SessionLocal
        from app.services.repeating import run_forever

        repeat_task = asyncio.create_task(run_forever(SessionLocal))
        from app.db import engine
        from app.services.realtime import listen_forever

        listen_task = asyncio.create_task(listen_forever(engine))
    yield
    if repeat_task is not None:
        repeat_task.cancel()
        listen_task.cancel()


app = FastAPI(title="AI Receipt API", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def limit_body_size(request: Request, call_next):
    """Refuse oversized bodies from Content-Length, before reading them, so a
    huge upload can't tie up memory. Schemas cap individual fields as well."""
    declared = request.headers.get("content-length")
    if declared and declared.isdigit():
        is_import = request.url.path == "/v1/receipts/import"
        cap = settings.max_import_body_bytes if is_import else settings.max_body_bytes
        if int(declared) > cap:
            return JSONResponse(status_code=413, content={"detail": "Request is too large."})
    return await call_next(request)


@app.middleware("http")
async def security_headers(request: Request, call_next):
    """Baseline hardening on every response. No CSP: this is a JSON API, and
    /docs loads Swagger UI from a CDN."""
    response = await call_next(request)
    response.headers.setdefault("Strict-Transport-Security", "max-age=63072000; includeSubDomains")
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "no-referrer")
    # Receipts are personal data: keep them out of shared/proxy caches.
    if request.url.path.startswith("/v1/"):
        response.headers.setdefault("Cache-Control", "no-store")
    return response


app.include_router(health.router)
app.include_router(auth.router, prefix="/v1/auth", tags=["auth"])
app.include_router(receipts.router, prefix="/v1", tags=["receipts"])
app.include_router(expenses.router, prefix="/v1/expenses", tags=["expenses"])
app.include_router(budgets.router, prefix="/v1/budgets", tags=["budgets"])
app.include_router(splits.router, prefix="/v1", tags=["splits"])
app.include_router(groups.router, prefix="/v1/groups", tags=["groups"])
app.include_router(people.router, prefix="/v1/people", tags=["people"])
app.include_router(activity.router, prefix="/v1/activity", tags=["activity"])
app.include_router(events.router, prefix="/v1/events", tags=["events"])
app.include_router(export.router, prefix="/v1/export", tags=["export"])
app.include_router(public.router, prefix="/v1/public", tags=["public"])


@app.get("/")
async def root() -> dict:
    return {"name": "AI Receipt API", "docs": "/docs", "health": "/healthz"}
