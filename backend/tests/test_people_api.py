"""People outside groups: balances, payments, invites, accepting them, and
email linking only for verified addresses (docs/SPLITS.md)."""

from datetime import UTC, datetime

import pytest_asyncio
from sqlalchemy import select

from app.api import deps
from app.api.deps import get_current_user
from app.main import app
from app.models import Person, User
from app.services.mailer import get_mailer

TODAY = datetime.now(UTC).date().isoformat()


class FakeMailer:
    def __init__(self) -> None:
        self.sent: list[dict] = []

    async def send(self, **message) -> None:
        self.sent.append(message)


@pytest_asyncio.fixture
async def sam(sessionmaker_) -> User:
    async with sessionmaker_() as session:
        user = User(email="sam@example.com", display_name="Sam", auth0_sub="auth0|sam")
        session.add(user)
        await session.commit()
        await session.refresh(user)
        return user


def act_as(user: User) -> None:
    app.dependency_overrides[get_current_user] = lambda: user


async def _expense(client, total, participants, description="Dinner"):
    r = await client.post(
        "/v1/splits",
        json={
            "description": description,
            "total": total,
            "date": TODAY,
            "participants": participants,
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


async def _people(client):
    return {p["name"]: p for p in (await client.get("/v1/people")).json()}


async def test_names_become_people_with_a_running_balance(client):
    await _expense(client, "60.00", [{"is_me": True}, {"name": "Alex"}, {"name": "Kim"}])
    # Same name, any case: the same person.
    await _expense(client, "30.00", [{"is_me": True}, {"name": "alex"}])
    people = await _people(client)
    assert set(people) == {"Alex", "Kim"}
    assert people["Alex"]["balance"] == "35.00"  # 20 + 15
    assert people["Kim"]["balance"] == "20.00"
    assert not people["Alex"]["has_account"]
    assert "/p/" in people["Alex"]["invite_url"]


async def test_they_paid_and_payments_move_the_balance(client):
    alex = (await client.post("/v1/people", json={"name": "Alex"})).json()
    # Alex paid 50 for both of us: I owe 25.
    await _expense(
        client, "50.00", [{"is_me": True}, {"person_id": alex["id"], "is_payer": True}], "Cab"
    )
    detail = (await client.get(f"/v1/people/{alex['id']}")).json()
    assert detail["balance"] == "-25.00"
    assert [s["description"] for s in detail["splits"]] == ["Cab"]

    r = await client.post(
        f"/v1/people/{alex['id']}/payments", json={"you_paid": True, "amount": "25"}
    )
    assert r.json()["balance"] == "0.00"
    payment = r.json()["payments"][0]
    assert payment["you_paid"] and payment["can_delete"]
    r = await client.delete(f"/v1/people/{alex['id']}/payments/{payment['id']}")
    assert r.json()["balance"] == "-25.00"


async def test_invite_email_needs_an_address_and_is_rate_limited(client):
    alex = (await client.post("/v1/people", json={"name": "Alex"})).json()
    # Email not configured: share the link instead.
    assert (await client.post(f"/v1/people/{alex['id']}/invite")).status_code == 503

    mailer = FakeMailer()
    app.dependency_overrides[get_mailer] = lambda: mailer
    assert (await client.post(f"/v1/people/{alex['id']}/invite")).status_code == 422
    await client.patch(f"/v1/people/{alex['id']}", json={"email": "Alex@Example.com "})
    await _expense(client, "40.00", [{"is_me": True}, {"person_id": alex["id"]}])

    r = await client.post(f"/v1/people/{alex['id']}/invite")
    assert r.status_code == 200, r.text
    assert r.json()["invited_at"] is not None
    (message,) = mailer.sent
    assert message["to"] == "alex@example.com"
    assert "you owe T 20.00 CAD" in message["text"]
    assert alex["invite_url"] in message["text"]
    # Again straight away: no second email.
    assert (await client.post(f"/v1/people/{alex['id']}/invite")).status_code == 429

    bad = await client.patch(f"/v1/people/{alex['id']}", json={"email": "not-an-email"})
    assert bad.status_code == 422


async def test_accepting_an_invite_shows_both_sides(client, anon_client, test_user, sam):
    alex = (await client.post("/v1/people", json={"name": "Sam"})).json()
    split = await _expense(client, "90.00", [{"is_me": True}, {"person_id": alex["id"]}])
    token = alex["invite_url"].rsplit("/", 1)[1]

    # The link works signed out: who's asking and where you stand.
    public = (await anon_client.get(f"/v1/public/people/{token}")).json()
    assert public == {
        "from_name": "T",
        "name": "Sam",
        "claimed": False,
        "balance": "-45.00",
        "currency": "CAD",
        "expense_count": 1,
    }

    # Your own invite can't be accepted by you.
    assert (await client.post(f"/v1/people/claim/{token}")).status_code == 409

    act_as(sam)
    mine = (await anon_client.post(f"/v1/people/claim/{token}")).json()
    assert (mine["name"], mine["balance"], mine["has_account"]) == ("T", "-45.00", True)
    # The split is visible to Sam, with Sam as "you".
    seen = (await anon_client.get(f"/v1/splits/{split['id']}")).json()
    assert seen["my_share"] == "45.00" and not seen["is_owner"]
    # Sam pays back; the inviter sees it too.
    await anon_client.post(
        f"/v1/people/{mine['id']}/payments", json={"you_paid": True, "amount": "45"}
    )

    act_as(test_user)
    back = (await client.get(f"/v1/people/{alex['id']}")).json()
    assert back["has_account"] and back["balance"] == "0.00"
    assert back["payments"][0]["can_delete"] is False

    # New splits with Sam reach Sam's account directly.
    await _expense(client, "10.00", [{"is_me": True}, {"person_id": alex["id"]}], "Coffee")
    act_as(sam)
    assert (await anon_client.get(f"/v1/people/{mine['id']}")).json()["balance"] == "-5.00"


async def test_someone_else_cant_take_an_accepted_invite(client, anon_client, sam, sessionmaker_):
    alex = (await client.post("/v1/people", json={"name": "Sam"})).json()
    token = alex["invite_url"].rsplit("/", 1)[1]
    act_as(sam)
    assert (await anon_client.post(f"/v1/people/claim/{token}")).status_code == 200
    async with sessionmaker_() as session:
        kim = User(email="kim@example.com", display_name="Kim", auth0_sub="auth0|kim")
        session.add(kim)
        await session.commit()
        await session.refresh(kim)
    act_as(kim)
    assert (await anon_client.post(f"/v1/people/claim/{token}")).status_code == 409


async def test_deleting_a_person_keeps_their_name_on_splits(client):
    split = await _expense(client, "20.00", [{"is_me": True}, {"name": "Alex"}])
    alex = (await _people(client))["Alex"]
    assert (await client.delete(f"/v1/people/{alex['id']}")).status_code == 204
    again = (await client.get(f"/v1/splits/{split['id']}")).json()
    assert [p["display_name"] for p in again["participants"]] == ["T", "Alex"]
    assert again["participants"][1]["person_id"] is None


# ─────────────────────────── signing in by email ───────────────────────────


async def _provision(sessionmaker_, monkeypatch, sub, email, verified):
    async def fake_userinfo(_token):
        return {"email": email, "email_verified": verified, "name": "New"}

    monkeypatch.setattr(deps, "fetch_userinfo", fake_userinfo)
    async with sessionmaker_() as session:
        user = await deps._provision_user(session, sub, "token")
        return user.id, user.email


async def test_unverified_email_never_takes_over_an_existing_account(
    sessionmaker_, monkeypatch, test_user
):
    user_id, email = await _provision(
        sessionmaker_, monkeypatch, "auth0|attacker", test_user.email, verified=False
    )
    assert user_id != test_user.id
    assert email != test_user.email


async def test_verified_email_links_an_older_account(sessionmaker_, monkeypatch, test_user):
    user_id, _ = await _provision(
        sessionmaker_, monkeypatch, "google|t", test_user.email, verified=True
    )
    assert user_id == test_user.id


async def test_verified_signup_accepts_invites_sent_to_that_email(
    client, sessionmaker_, monkeypatch
):
    alex = (
        await client.post("/v1/people", json={"name": "Alex", "email": "alex@example.com"})
    ).json()

    # Someone signing up with that address unverified gets nothing.
    await _provision(sessionmaker_, monkeypatch, "auth0|fake", "alex@example.com", verified=False)
    assert not (await client.get(f"/v1/people/{alex['id']}")).json()["has_account"]

    user_id, _ = await _provision(
        sessionmaker_, monkeypatch, "google|alex", "alex@example.com", verified=True
    )
    assert (await client.get(f"/v1/people/{alex['id']}")).json()["has_account"]
    async with sessionmaker_() as session:
        mirror = await session.scalar(select(Person).where(Person.owner_user_id == user_id))
        assert mirror is not None and mirror.display_name == "T"
