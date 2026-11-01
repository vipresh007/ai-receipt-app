"""Reporting a comment and blocking its author (services/safety.py)."""

import pytest_asyncio

from app.models import ContentReport, User
from tests.test_splitwise_extras import _expense, _linked_sam, act_as


@pytest_asyncio.fixture
async def sam(sessionmaker_) -> User:
    async with sessionmaker_() as session:
        user = User(
            email="sam@example.com", display_name="Sam", auth0_sub="auth0|sam", email_verified=True
        )
        session.add(user)
        await session.commit()
        await session.refresh(user)
        return user


async def test_report_and_block_hides_their_comments_and_activity(
    client, anon_client, test_user, sam, sessionmaker_
):
    person, _ = await _linked_sam(client, anon_client, test_user, sam)
    split = await _expense(client, "30.00", [{"is_me": True}, {"person_id": person["id"]}])

    act_as(sam)
    await anon_client.post(f"/v1/splits/{split['id']}/comments", json={"body": "rude thing"})

    act_as(test_user)
    timeline = (await client.get(f"/v1/splits/{split['id']}/timeline")).json()
    comment = next(e for e in timeline if e["kind"] == "comment")
    assert comment["can_report"] and comment["author_id"] == str(sam.id)

    r = await client.post(
        f"/v1/splits/{split['id']}/comments/{comment['id']}/report",
        json={"reason": "abuse", "block": True},
    )
    assert r.status_code == 200, r.text
    assert all(e["kind"] != "comment" for e in r.json())
    async with sessionmaker_() as session:
        (saved,) = (await session.scalars(ContentReport.__table__.select())).all() or [None]
    assert saved is not None

    blocks = (await client.get("/v1/blocks")).json()
    assert blocks == [{"user_id": str(sam.id), "name": "Sam"}]

    # Sam's later comments don't reach me.
    before = len((await client.get("/v1/activity")).json()["items"])
    act_as(sam)
    await anon_client.post(f"/v1/splits/{split['id']}/comments", json={"body": "again"})
    act_as(test_user)
    assert len((await client.get("/v1/activity")).json()["items"]) == before

    # Unblock: their comments are back.
    assert (await client.delete(f"/v1/blocks/{sam.id}")).status_code == 204
    timeline = (await client.get(f"/v1/splits/{split['id']}/timeline")).json()
    assert [e["text"] for e in timeline if e["kind"] == "comment"] == ["rude thing", "again"]


async def test_own_comments_cant_be_reported(client, test_user):
    split = await _expense(client, "10.00", [{"is_me": True}, {"name": "Kim"}])
    r = await client.post(f"/v1/splits/{split['id']}/comments", json={"body": "mine"})
    assert not r.json()[-1]["can_report"]
    assert (await client.post("/v1/blocks", json={"user_id": str(test_user.id)})).status_code == 422
