"""The same receipt added twice (services/duplicates.py)."""

import base64

from sqlalchemy import select

from app.models import Activity, Receipt
from app.services import duplicates, inbox
from tests.conftest import FakeExtractor
from tests.test_inbox import _user, mail
from tests.test_push import apns  # noqa: F401


def test_same_store_is_loose_about_case_punctuation_and_branch_names():
    assert duplicates.same_store("FRESHCO", "FreshCo")
    assert duplicates.same_store("Eggholic", "Eggholic- Indian Street Food (Brampton)")
    assert not duplicates.same_store("Loblaws", "Farm Boy")
    assert not duplicates.same_store("Bar", "Barbara's Bakery")  # too short to be a prefix
    assert not duplicates.same_store("", "")


async def _scan(client):
    body = {
        "imageBase64": base64.b64encode(b"jpeg").decode(),
        "ocrLines": [],
        "clientRequestID": "r",
    }
    return (await client.post("/v1/extract", json=body)).json()


async def test_scanning_a_receipt_you_have_says_so(client):
    first = await _scan(client)
    assert first["duplicate_of"] is None
    second = await _scan(client)
    assert second["duplicate_of"]["id"] == first["id"]
    assert second["duplicate_of"]["merchant"] == "Blue Bottle Coffee"
    assert second["duplicate_of"]["total"] == "12.50"


async def test_merging_keeps_the_original_and_takes_what_only_the_copy_had(client):
    original = (
        await client.post(
            "/v1/receipts", json={"merchant": "FreshCo", "date": "2026-10-09", "total": "30.72"}
        )
    ).json()
    copy = (
        await client.post(
            "/v1/receipts",
            json={
                "merchant": "FRESHCO",
                "date": "2026-10-09",
                "total": "30.72",
                "items": [{"name": "Bananas", "price": "1.57", "quantity": 1}],
            },
        )
    ).json()
    groups = (await client.get("/v1/receipts/duplicates")).json()
    assert [[r["id"] for r in g] for g in groups] == [[original["id"], copy["id"]]]

    kept = (
        await client.post(f"/v1/receipts/{copy['id']}/merge", json={"into": original["id"]})
    ).json()
    assert kept["id"] == original["id"]
    assert [i["name"] for i in kept["line_items"]] == ["Bananas"]
    assert (await client.get(f"/v1/receipts/{copy['id']}")).status_code == 404
    assert (await client.get("/v1/receipts/duplicates")).json() == []
    # Counted once.
    assert len((await client.get("/v1/receipts")).json()) == 1


async def test_merging_into_itself_is_refused(client):
    r = (await client.post("/v1/receipts", json={"merchant": "X", "total": "1.00"})).json()
    resp = await client.post(f"/v1/receipts/{r['id']}/merge", json={"into": r["id"]})
    assert resp.status_code == 422


async def test_an_email_of_a_receipt_you_have_isnt_added_again(
    client,
    sessionmaker_,
    test_user,
    apns,  # noqa: F811
):
    from app.services import push

    await client.post("/v1/devices", json={"token": "cc" * 32})
    await _user(sessionmaker_, inbox_token="0ddba11000")
    raw = mail("receipts+0ddba11000@dataeaver.ca", "someone@else.com", html="<p>Total $12.50</p>")
    async with sessionmaker_() as session:
        assert await inbox.handle(session, raw, FakeExtractor()) == "added"
    async with sessionmaker_() as session:
        assert await inbox.handle(session, raw, FakeExtractor()) == "duplicate"
    await push.drain()
    alert = apns.sent[-1][1]["aps"]["alert"]
    assert alert["title"] == "Already in Tally"
    assert alert["body"] == "Blue Bottle Coffee · $12.50 · Sep 1"
    async with sessionmaker_() as session:
        assert len((await session.scalars(select(Receipt))).all()) == 1
        texts = [a.text for a in await session.scalars(select(Activity))]
        assert "already had Blue Bottle Coffee, $12.50 on Sep 1" in texts
