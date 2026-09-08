import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from app import config
from app.core import security
from app.core.security import TokenError, verify_access_token


@pytest.fixture
def rsa_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


@pytest.fixture
def auth_env(monkeypatch, rsa_key):
    monkeypatch.setenv("AUTH0_DOMAIN", "test.auth0.com")
    monkeypatch.setenv("AUTH0_AUDIENCE", "https://api.test")
    config.get_settings.cache_clear()

    public_key = rsa_key.public_key()

    class _Key:
        key = public_key

    class _Client:
        def get_signing_key_from_jwt(self, _token):
            return _Key()

    monkeypatch.setattr(security, "_jwks_client", lambda: _Client())
    yield
    config.get_settings.cache_clear()


def _token(key, **claims) -> str:
    payload = {
        "sub": "auth0|abc123",
        "aud": "https://api.test",
        "iss": "https://test.auth0.com/",
        **claims,
    }
    return jwt.encode(payload, key, algorithm="RS256")


def test_verify_accepts_a_valid_token(auth_env, rsa_key):
    claims = verify_access_token(_token(rsa_key))
    assert claims["sub"] == "auth0|abc123"


def test_verify_rejects_wrong_audience(auth_env, rsa_key):
    with pytest.raises(TokenError):
        verify_access_token(_token(rsa_key, aud="https://api.other"))


def test_verify_rejects_garbage():
    config.get_settings.cache_clear()
    with pytest.raises(TokenError):
        verify_access_token("not.a.jwt")
    config.get_settings.cache_clear()
