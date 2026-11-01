"""Push notifications to iPhones through APNs (token auth, HTTP/2).

Everything that lands in someone's activity feed is also pushed to their
signed-in iPhones (`activity.notify` calls `send`). Off until `APNS_KEY` and
`APNS_KEY_ID` are set; tokens Apple says are gone are dropped.
"""

import asyncio
import logging
import time
import uuid
from collections.abc import Iterable

import httpx
import jwt
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models import DeviceToken

log = logging.getLogger(__name__)

HOSTS = {
    "production": "https://api.push.apple.com",
    "sandbox": "https://api.sandbox.push.apple.com",
}

_token: tuple[float, str] | None = None
_client: httpx.AsyncClient | None = None
_sending: set[asyncio.Task] = set()


def configured() -> bool:
    s = get_settings()
    return bool(s.apns_key and s.apns_key_id and s.apns_team_id)


def _bearer() -> str:
    """Apple wants a fresh-ish JWT: reuse one for 50 minutes (max 60)."""
    global _token
    now = time.time()
    if _token is None or now - _token[0] > 50 * 60:
        s = get_settings()
        key = s.apns_key.replace("\\n", "\n")
        signed = jwt.encode(
            {"iss": s.apns_team_id, "iat": int(now)},
            key,
            algorithm="ES256",
            headers={"kid": s.apns_key_id},
        )
        _token = (now, signed)
    return _token[1]


def _http() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(http2=True, timeout=10)
    return _client


async def send(
    session: AsyncSession, user_ids: Iterable[uuid.UUID], body: str, *, link: str = ""
) -> None:
    """Queue a push to every device of these users (fire and forget)."""
    if not configured():
        return
    ids = set(user_ids)
    if not ids:
        return
    rows = (
        await session.execute(
            select(DeviceToken.token, DeviceToken.environment).where(DeviceToken.user_id.in_(ids))
        )
    ).all()
    if not rows:
        return
    task = asyncio.create_task(_deliver([(t, e) for t, e in rows], body[:180], link))
    _sending.add(task)
    task.add_done_callback(_sending.discard)


async def _deliver(devices: list[tuple[str, str]], body: str, link: str) -> None:
    s = get_settings()
    payload = {"aps": {"alert": {"title": "Tally", "body": body}, "sound": "default"}}
    if link:
        payload["link"] = link
    gone: list[str] = []
    for token, environment in devices:
        try:
            r = await _http().post(
                f"{HOSTS.get(environment, HOSTS['production'])}/3/device/{token}",
                json=payload,
                headers={
                    "authorization": f"bearer {_bearer()}",
                    "apns-topic": s.apns_topic,
                    "apns-push-type": "alert",
                },
            )
            if r.status_code == 410 or (r.status_code == 400 and "BadDeviceToken" in r.text):
                gone.append(token)
            elif r.status_code >= 300:
                log.warning("APNs %s: %s", r.status_code, r.text[:200])
        except Exception:  # noqa: BLE001 - a push never fails anything else
            log.warning("APNs send failed", exc_info=True)
    if gone:
        from app.db import SessionLocal

        async with SessionLocal() as session:
            await session.execute(delete(DeviceToken).where(DeviceToken.token.in_(gone)))
            await session.commit()


async def drain() -> None:
    """Wait for queued pushes (tests)."""
    if _sending:
        await asyncio.gather(*list(_sending), return_exceptions=True)
