from app.core.security import (
    create_access_token,
    decode_access_token,
    hash_password,
    verify_password,
)


def test_password_hash_roundtrip():
    hashed = hash_password("s3cret-passw0rd")
    assert hashed != "s3cret-passw0rd"
    assert verify_password("s3cret-passw0rd", hashed)
    assert not verify_password("wrong", hashed)


def test_verify_rejects_garbage_hash():
    assert verify_password("x", "not-a-bcrypt-hash") is False


def test_jwt_roundtrip():
    token = create_access_token("user-123", secret="k", ttl_minutes=5)
    payload = decode_access_token(token, secret="k")
    assert payload["sub"] == "user-123"
    assert payload["exp"] > payload["iat"]
