"""Unsubscribe links in every notification email (services/unsubscribe.py)."""

from urllib.parse import parse_qs, urlparse

from app.main import app
from app.models import User
from app.services import activity, unsubscribe
from app.services.mailer import get_mailer, with_unsubscribe
from tests.test_safety import sam  # noqa: F401
from tests.test_splitwise_extras import FakeMailer, _expense, _linked_sam, act_as


def _params(url: str) -> dict:
    return {k: v[0] for k, v in parse_qs(urlparse(url).query).items()}


def test_every_email_gets_a_footer_link_and_one_click_headers():
    text, html, headers = with_unsubscribe("Sam@Example.com", "expenses", "Hi", "<p>Hi</p>")
    assert "Unsubscribe: https://tally.dataeaver.ca/unsubscribe?" in text
    assert "Choose which emails you get" in text and "/account" in text
    assert ">Unsubscribe</a>" in html
    assert headers["List-Unsubscribe"].startswith(
        "<https://tally.dataeaver.ca/unsubscribe/one-click?"
    )
    assert headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
    # For people without an account there's nothing to choose, just "stop".
    text, _, _ = with_unsubscribe("kim@example.com", "all", "Hi", "<p>Hi</p>")
    assert "Choose which emails you get" not in text


async def test_unsubscribing_from_one_kind_stops_only_that_kind(
    client,
    anon_client,
    test_user,
    sam,  # noqa: F811
    monkeypatch,
    sessionmaker_,
):
    mailer = FakeMailer()
    monkeypatch.setattr(activity, "get_mailer", lambda: mailer)
    person, _ = await _linked_sam(client, anon_client, test_user, sam)
    await _expense(client, "30.00", [{"is_me": True}, {"person_id": person["id"]}])
    await activity.drain()
    (message,) = mailer.sent
    assert message["unsubscribe"] == "expenses"

    q = unsubscribe.params("sam@example.com", "expenses")
    info = (await anon_client.get("/v1/public/unsubscribe", params=q)).json()
    assert info["what"] == "emails about shared expenses" and info["has_account"] is True
    assert info["email"].startswith("s") and "example.com" in info["email"]
    # A tampered link does nothing.
    bad = {**q, "t": "0" * 32}
    assert (await anon_client.get("/v1/public/unsubscribe", params=bad)).status_code == 404

    r = await anon_client.post("/v1/public/unsubscribe", json=q)
    assert r.status_code == 200 and r.json()["done"] is True
    async with sessionmaker_() as session:
        row = await session.get(User, sam.id)
        assert row.notify_prefs.get("expenses.email") is False
        assert row.notify_prefs.get("payments.email", True) is True
        assert row.email_notifications is True
    act_as(test_user)


async def test_stop_all_blocks_invites_until_they_turn_email_back_on(client, anon_client):
    mailer = FakeMailer()
    app.dependency_overrides[get_mailer] = lambda: mailer
    kim = (await client.post("/v1/people", json={"name": "Kim", "email": "kim@example.com"})).json()
    await _expense(client, "20.00", [{"is_me": True}, {"person_id": kim["id"]}])

    q = unsubscribe.params("kim@example.com", "all")
    assert (await anon_client.get("/v1/public/unsubscribe", params=q)).json()[
        "has_account"
    ] is False
    await anon_client.post("/v1/public/unsubscribe", json=q)

    r = await client.post(f"/v1/people/{kim['id']}/invite")
    assert r.status_code == 422 and "asked not to get emails" in r.json()["detail"]
    assert mailer.sent == []


async def test_turning_email_back_on_lifts_stop_all(client, test_user, sessionmaker_):
    q = unsubscribe.params(test_user.email, "expenses")
    await client.post("/v1/public/unsubscribe", json={**q, "everything": True})
    async with sessionmaker_() as session:
        assert (await session.get(User, test_user.id)).email_notifications is False
        assert await unsubscribe.is_suppressed(session, test_user.email)
    await client.patch("/v1/auth/me", json={"email_notifications": True})
    async with sessionmaker_() as session:
        assert not await unsubscribe.is_suppressed(session, test_user.email)
