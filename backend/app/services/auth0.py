"""Minimal Auth0 helpers beyond token verification."""

import httpx

from app.config import get_settings


async def fetch_userinfo(access_token: str) -> dict:
    """Call Auth0 `/userinfo` with the caller's access token.

    Used once, the first time we see a given identity, to learn their email and
    name so we can create the local `users` row. Subsequent requests hit the DB
    only.
    """
    settings = get_settings()
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(
            settings.auth0_userinfo_url,
            headers={"authorization": f"Bearer {access_token}"},
        )
        resp.raise_for_status()
        return resp.json()
