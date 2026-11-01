"""Push notifications (services/push.py) with a fake APNs."""

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from app.config import get_settings
from app.services import activity, push
from tests.test_safety import sam  # noqa: F401
from tests.test_splitwise_extras import _expense, _linked_sam, act_as


class FakeAPNs:
    def __init__(self, status: int = 200) -> None:
        self.sent: list[tuple[str, dict]] = []
        self.status = status

    async def post(self, url, json, headers):
        self.sent.append((url, json))

        class R:
            status_code = self.status
            text = '{"reason":"Unregistered"}'

        return R()


@pytest.fixture
def apns(monkeypatch):
    key = ec.generate_private_key(ec.SECP256R1())
    pem = key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    ).decode()
    settings = get_settings()
    monkeypatch.setattr(settings, "apns_key", pem)
    monkeypatch.setattr(settings, "apns_key_id", "ABC123DEFG")
    fake = FakeAPNs()
    monkeypatch.setattr(push, "_http", lambda: fake)
    monkeypatch.setattr(push, "_token", None)
    return fake


async def test_activity_is_pushed_to_their_iphone(client, anon_client, test_user, sam, apns):  # noqa: F811
    person, _ = await _linked_sam(client, anon_client, test_user, sam)
    act_as(sam)
    token = "ab" * 32
    r = await anon_client.post("/v1/devices", json={"token": token, "environment": "sandbox"})
    assert r.status_code == 204
    act_as(test_user)
    await _expense(client, "30.00", [{"is_me": True}, {"person_id": person["id"]}])
    await push.drain()
    await activity.drain()
    assert apns.sent, "no push went out"
    url, payload = apns.sent[-1]
    assert url == f"https://api.sandbox.push.apple.com/3/device/{token}"
    assert payload["aps"]["alert"]["body"].startswith("T added")


async def test_no_key_no_push(client, test_user, monkeypatch):
    fake = FakeAPNs()
    monkeypatch.setattr(push, "_http", lambda: fake)
    await client.post("/v1/devices", json={"token": "cd" * 32})
    await _expense(client, "10.00", [{"is_me": True}, {"name": "Kim"}])
    await push.drain()
    assert fake.sent == []


async def test_bad_tokens_are_refused(client):
    r = await client.post("/v1/devices", json={"token": "not-hex!"})
    assert r.status_code == 422
