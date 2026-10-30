"""Live updates: tell someone's open apps that something of theirs changed,
so they re-fetch what's on screen instead of polling (docs/SPLITS.md).

Each signed-in app keeps one Server-Sent Events stream open
(`GET /v1/events`). A change calls `publish(session, user_ids)`, which sends a
Postgres NOTIFY inside the change's own transaction, so it goes out only if
the change is committed. Every API replica LISTENs and wakes the streams it
holds for those people. (SQLite, in tests: delivered in-process at once.)
"""

import asyncio
import json
import logging
import uuid
from collections.abc import Iterable

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession

log = logging.getLogger(__name__)

CHANNEL = "tally_events"

# user id → the queues of that person's open streams on this replica.
_streams: dict[uuid.UUID, set[asyncio.Queue]] = {}


def subscribe(user_id: uuid.UUID) -> asyncio.Queue:
    queue: asyncio.Queue = asyncio.Queue(maxsize=1)
    _streams.setdefault(user_id, set()).add(queue)
    return queue


def unsubscribe(user_id: uuid.UUID, queue: asyncio.Queue) -> None:
    streams = _streams.get(user_id)
    if streams is not None:
        streams.discard(queue)
        if not streams:
            _streams.pop(user_id, None)


def _wake(user_ids: Iterable[str | uuid.UUID]) -> None:
    for raw in user_ids:
        try:
            user_id = raw if isinstance(raw, uuid.UUID) else uuid.UUID(str(raw))
        except ValueError:
            continue
        for queue in _streams.get(user_id, ()):
            # One pending "changed" is enough: the app re-fetches everything
            # on screen, so a burst of changes collapses into one refresh.
            if queue.empty():
                queue.put_nowait("changed")


async def publish(session: AsyncSession, user_ids: Iterable[uuid.UUID | None]) -> None:
    """Wake these people's apps once the current transaction commits."""
    ids = sorted({str(u) for u in user_ids if u is not None})
    if not ids:
        return
    if session.bind is not None and session.bind.dialect.name == "postgresql":
        # NOTIFY payloads max out near 8 KB; ~36 bytes per id.
        for start in range(0, len(ids), 150):
            await session.execute(
                text("SELECT pg_notify(:channel, :payload)"),
                {"channel": CHANNEL, "payload": json.dumps(ids[start : start + 150])},
            )
    else:
        _wake(ids)


async def listen_forever(engine: AsyncEngine) -> None:
    """Hold a LISTEN connection on this replica and fan NOTIFYs out to the
    streams open here. Reconnects if the connection drops."""
    if engine.dialect.name != "postgresql":
        return
    delay = 1.0
    while True:
        try:
            async with engine.connect() as conn:
                raw = await conn.get_raw_connection()
                driver = raw.driver_connection

                def on_notify(_conn, _pid, _channel, payload: str) -> None:
                    try:
                        _wake(json.loads(payload))
                    except (ValueError, TypeError):
                        log.warning("bad realtime payload")

                await driver.add_listener(CHANNEL, on_notify)
                log.info("listening for live updates")
                delay = 1.0
                while not driver.is_closed():
                    await asyncio.sleep(30)
                    await conn.execute(text("SELECT 1"))  # keep it alive
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - reconnect
            log.warning("live updates listener dropped; reconnecting", exc_info=True)
        await asyncio.sleep(delay)
        delay = min(delay * 2, 30)
