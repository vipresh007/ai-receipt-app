"""Live updates over Server-Sent Events: one open stream per app, told when
something of yours changed (services/realtime.py)."""

import asyncio

from fastapi import APIRouter, Depends, Request
from fastapi.responses import StreamingResponse

from app.api.deps import get_current_user
from app.models import User
from app.services import realtime

router = APIRouter()

# A comment line this often keeps proxies (Azure's ingress cuts idle
# connections at 240s) from closing a quiet stream.
HEARTBEAT_SECONDS = 25


@router.get("")
async def events(request: Request, user: User = Depends(get_current_user)) -> StreamingResponse:
    queue = realtime.subscribe(user.id)

    async def stream():
        try:
            yield "retry: 5000\n: connected\n\n"
            while True:
                if await request.is_disconnected():
                    return
                try:
                    kind = await asyncio.wait_for(queue.get(), timeout=HEARTBEAT_SECONDS)
                    yield f"event: {kind}\ndata: {{}}\n\n"
                except TimeoutError:
                    yield ": ping\n\n"
        finally:
            realtime.unsubscribe(user.id, queue)

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={"cache-control": "no-cache", "x-accel-buffering": "no"},
    )
