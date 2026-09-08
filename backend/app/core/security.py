"""Auth0 access-token verification.

The app no longer stores passwords or mints tokens — Auth0 does. Here we only
verify the RS256 access tokens Auth0 issues, against its published JWKS.
"""

from functools import lru_cache

import jwt

from app.config import get_settings


class TokenError(Exception):
    """Raised when an access token is missing, malformed, or fails validation."""


@lru_cache
def _jwks_client() -> jwt.PyJWKClient:
    return jwt.PyJWKClient(get_settings().auth0_jwks_url)


def verify_access_token(token: str) -> dict:
    """Return the validated claims, or raise `TokenError`."""
    settings = get_settings()
    if not settings.auth_configured:
        raise TokenError("Auth is not configured on the server.")
    try:
        signing_key = _jwks_client().get_signing_key_from_jwt(token)
        return jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience=settings.auth0_audience,
            issuer=settings.auth0_issuer,
        )
    except Exception as exc:  # noqa: BLE001 - normalize every failure to TokenError
        raise TokenError(str(exc)) from exc
