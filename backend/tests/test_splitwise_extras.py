"""Several payers, percentages, edits by anyone on an expense (with history),
comments, activity and notification emails, one balance per person across
groups, reminders, payment details, repeating expenses and CSV export."""

from datetime import UTC, date, datetime, timedelta

import pytest_asyncio

from app.api.deps import get_current_user
from app.main import app
from app.models import User
from app.services import activity
from app.services.mailer import get_mailer
from app.services.repeating import materialize_due

TODAY = datetime.now(UTC).date()


class FakeMailer:
    def __init__(self) -> None:
        self.sent: list[dict] = []

    async def send(self, **message) -> None:
        self.sent.append(message)


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


def act_as(user: User) -> None:
    app.dependency_overrides[get_current_user] = lambda: user


async def _linked_sam(client, anon_client, test_user, sam):
    """A person "Sam" on my list who has accepted the invite."""
    person = (await client.post("/v1/people", json={"name": "Sam"})).json()
    act_as(sam)
    mirror = (
        await anon_client.post(f"/v1/people/claim/{person['invite_url'].rsplit('/', 1)[1]}")
    ).json()
    act_as(test_user)
    return person, mirror


async def _expense(client, total, participants, **extra):
    r = await client.post(
        "/v1/splits",
        json={
            "description": extra.pop("description", "Dinner"),
            "total": total,
            "date": extra.pop("date", TODAY.isoformat()),
            "participants": participants,
            **extra,
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


# ─────────────────────────── math ───────────────────────────


async def test_several_payers_in_a_group(client):
    group = (
        await client.post("/v1/groups", json={"name": "Trip", "members": ["Sam", "Kim"]})
    ).json()
    me, sam, kim = group["members"]
    # 90 split three ways; I paid 60 and Sam 30.
    await _expense(
        client,
        "90.00",
        [
            {"is_me": True, "paid": "60"},
            {"member_id": sam["id"], "paid": "30"},
            {"member_id": kim["id"]},
        ],
        group_id=group["id"],
    )
    detail = (await client.get(f"/v1/groups/{group['id']}")).json()
    assert [m["balance"] for m in detail["members"]] == ["30.00", "0.00", "-30.00"]
    assert detail["payments"] == [
        {"from_member_id": kim["id"], "to_member_id": me["id"], "amount": "30.00"}
    ]
    bad = await client.post(
        "/v1/splits",
        json={
            "group_id": group["id"],
            "description": "x",
            "total": "10",
            "participants": [{"is_me": True, "paid": "4"}, {"member_id": sam["id"], "paid": "4"}],
        },
    )
    assert bad.status_code == 422 and "add up to 10.00" in bad.json()["detail"]


async def test_percentages_must_make_100(client):
    split = await _expense(
        client,
        "50.00",
        [{"is_me": True, "weight": "40"}, {"name": "Zalak", "weight": "60"}],
        mode="percent",
    )
    assert [p["share"] for p in split["participants"]] == ["20.00", "30.00"]
    r = await client.post(
        "/v1/splits",
        json={
            "description": "x",
            "total": "10",
            "mode": "percent",
            "participants": [{"is_me": True, "weight": "40"}, {"name": "A", "weight": "50"}],
        },
    )
    assert r.status_code == 422 and "90%" in r.json()["detail"]


# ─────────────────────── edits, history, comments ───────────────────────


async def test_anyone_on_it_can_edit_and_everyone_sees_the_history(
    client, anon_client, test_user, sam
):
    person, _ = await _linked_sam(client, anon_client, test_user, sam)
    split = await _expense(client, "30.00", [{"is_me": True}, {"person_id": person["id"]}])
    me_row, sam_row = split["participants"]

    act_as(sam)
    seen = (await anon_client.get(f"/v1/splits/{split['id']}")).json()
    assert seen["can_edit"] and not seen["is_owner"]
    r = await anon_client.patch(
        f"/v1/splits/{split['id']}",
        json={
            "total": "40.00",
            "mode": "custom",
            "participants": [
                {"id": me_row["id"], "is_payer": True, "amount": "25"},
                {"id": sam_row["id"], "amount": "15"},
            ],
        },
    )
    assert r.status_code == 200, r.text
    assert [p["share"] for p in r.json()["participants"]] == ["25.00", "15.00"]
    # Who's on it isn't theirs to change.
    r = await anon_client.patch(
        f"/v1/splits/{split['id']}",
        json={"mode": "even", "participants": [{"id": me_row["id"], "is_payer": True}]},
    )
    assert r.status_code == 422
    await anon_client.post(f"/v1/splits/{split['id']}/comments", json={"body": "Tip was cash"})

    act_as(test_user)
    timeline = (await client.get(f"/v1/splits/{split['id']}/timeline")).json()
    assert [(e["kind"], e["author_name"]) for e in timeline] == [
        ("event", "T"),
        ("event", "Sam"),
        ("comment", "Sam"),
    ]
    assert "changed the total from $30.00 to $40.00" in timeline[1]["text"]
    assert "Sam's share $15.00 → $15.00" not in timeline[1]["text"]
    assert "T's share $15.00 → $25.00" in timeline[1]["text"]
    assert timeline[2]["text"] == "Tip was cash" and not timeline[2]["can_delete"]

    feed = (await client.get("/v1/activity")).json()
    assert feed["unread"] == 3  # accepted the invite, changed it, commented
    assert {a["kind"] for a in feed["items"]} == {"joined", "expense_edited", "comment"}
    assert (await client.post("/v1/activity/read")).json() == {"unread": 0}
    assert (await client.get("/v1/activity/unread")).json() == {"unread": 0}


async def test_strangers_cant_see_or_edit(client, anon_client, sam):
    split = await _expense(client, "10.00", [{"is_me": True}, {"name": "Alex"}])
    act_as(sam)
    assert (await anon_client.get(f"/v1/splits/{split['id']}/timeline")).status_code == 404
    r = await anon_client.patch(
        f"/v1/splits/{split['id']}",
        json={"mode": "even", "participants": [{"id": p["id"]} for p in split["participants"]]},
    )
    assert r.status_code == 404


# ─────────────────────── one balance per person ───────────────────────


async def test_balance_with_a_person_adds_up_groups_too(client, anon_client, test_user, sam):
    person, mirror = await _linked_sam(client, anon_client, test_user, sam)
    await _expense(client, "20.00", [{"is_me": True}, {"person_id": person["id"]}])  # +10

    group = (await client.post("/v1/groups", json={"name": "Flat", "members": ["Sam"]})).json()
    sam_member = group["members"][1]
    act_as(sam)
    await anon_client.post(
        f"/v1/groups/join/{group['invite_url'].rsplit('/', 1)[1]}",
        json={"member_id": sam_member["id"]},
    )
    act_as(test_user)
    await _expense(
        client,
        "60.00",
        [{"is_me": True}, {"member_id": sam_member["id"]}],
        group_id=group["id"],
    )  # +30 in the group

    mine = (await client.get(f"/v1/people/{person['id']}")).json()
    assert (mine["balance"], mine["outside_groups"]) == ("40.00", "10.00")
    assert mine["group_balances"] == [{"group_id": group["id"], "name": "Flat", "balance": "30.00"}]
    act_as(sam)
    theirs = (await anon_client.get(f"/v1/people/{mirror['id']}")).json()
    assert theirs["balance"] == "-40.00"


# ─────────────────────── reminders & payment details ───────────────────────


async def test_remind_someone_by_email(client):
    mailer = FakeMailer()
    app.dependency_overrides[get_mailer] = lambda: mailer
    person = (
        await client.post("/v1/people", json={"name": "Alex", "email": "alex@example.com"})
    ).json()
    assert (await client.post(f"/v1/people/{person['id']}/remind")).status_code == 409  # owes 0
    await _expense(client, "30.00", [{"is_me": True}, {"person_id": person["id"]}])
    r = await client.post(f"/v1/people/{person['id']}/remind")
    assert r.status_code == 200, r.text
    assert "you owe them $15.00" in mailer.sent[0]["text"]
    assert (await client.post(f"/v1/people/{person['id']}/remind")).status_code == 429


async def test_payment_details_show_to_people_who_owe_you(client, anon_client, test_user, sam):
    r = await client.patch("/v1/auth/me", json={"interac": "T@Example.com"})
    assert r.json()["interac"] == "t@example.com" and "paypal_me" not in r.json()
    assert (await client.patch("/v1/auth/me", json={"interac": "not it"})).status_code == 422

    _, mirror = await _linked_sam(client, anon_client, test_user, sam)
    act_as(sam)
    me_to_sam = (await anon_client.get(f"/v1/people/{mirror['id']}")).json()
    assert me_to_sam["pay_to"] == {"interac": "t@example.com"}


# ─────────────────────── notifications ───────────────────────


async def test_people_on_a_new_expense_get_an_email(
    client, anon_client, test_user, sam, monkeypatch
):
    mailer = FakeMailer()
    monkeypatch.setattr(activity, "get_mailer", lambda: mailer)
    person, _ = await _linked_sam(client, anon_client, test_user, sam)
    await _expense(client, "30.00", [{"is_me": True}, {"person_id": person["id"]}])
    await _expense(
        client, "8.00", [{"is_me": True}, {"person_id": person["id"]}], description="Tea"
    )
    await activity.drain()
    # One email (the second came within 10 minutes), to Sam's verified address.
    assert [m["to"] for m in mailer.sent] == ["sam@example.com"]
    assert 'added "Dinner": your share is $15.00' in mailer.sent[0]["subject"]

    act_as(sam)
    await anon_client.patch("/v1/auth/me", json={"email_notifications": False})
    feed = (await anon_client.get("/v1/activity")).json()
    assert {a["text"] for a in feed["items"]} >= {
        'added "Tea": your share is $4.00',
        'added "Dinner": your share is $15.00',
    }


# ─────────────────────── repeating & export ───────────────────────


async def test_repeating_expense_is_added_when_due(client, sessionmaker_):
    start = TODAY - timedelta(days=62)
    split = await _expense(
        client,
        "1200.00",
        [{"is_me": True}, {"name": "Flatmate"}],
        description="Rent",
        date=start.isoformat(),
        repeat="monthly",
    )
    assert split["repeat"] == "monthly" and split["next_at"] > start.isoformat()
    async with sessionmaker_() as session:
        added = await materialize_due(session, TODAY)
    async with sessionmaker_() as session:
        assert await materialize_due(session, TODAY) == 0
    rents = [s for s in (await client.get("/v1/splits")).json() if s["description"] == "Rent"]
    assert len(rents) == 1 + added and added in (2, 3)
    assert date.fromisoformat(rents[0]["date"]) <= TODAY


async def test_csv_export(client):
    await _expense(client, "12.00", [{"is_me": True}, {"name": "=cmd()"}], description="Lunch")
    r = await client.get("/v1/export/shared.csv")
    assert r.headers["content-type"].startswith("text/csv")
    assert "attachment" in r.headers["content-disposition"]
    lines = r.text.splitlines()
    assert lines[0].startswith("Date,Description,Group,Total")
    assert "Lunch" in lines[1] and "'=cmd() 6.00" not in lines[1]  # inside the joined cell
    r = await client.get("/v1/export/receipts.csv")
    assert r.text.startswith("Date,Merchant,Category")


# ─────────────────────── simplify debts ───────────────────────


async def test_simplify_debts_routes_a_chain_through(client, anon_client, test_user, sam):
    """I owe Sam 10 and Sam owes Kim 10: simplified, I pay Kim directly."""
    person, _ = await _linked_sam(client, anon_client, test_user, sam)
    group = (
        await client.post("/v1/groups", json={"name": "Trip", "members": ["Sam", "Kim"]})
    ).json()
    me, sam_m, kim = group["members"]
    act_as(sam)
    await anon_client.post(
        f"/v1/groups/join/{group['invite_url'].rsplit('/', 1)[1]}", json={"member_id": sam_m["id"]}
    )
    act_as(test_user)
    for payer, other in ((sam_m, me), (kim, sam_m)):
        await _expense(
            client,
            "20.00",
            [{"member_id": payer["id"], "is_payer": True}, {"member_id": other["id"]}],
            group_id=group["id"],
        )

    detail = (await client.get(f"/v1/groups/{group['id']}")).json()
    assert detail["simplify_debts"] is True
    assert detail["payments"] == [
        {"from_member_id": me["id"], "to_member_id": kim["id"], "amount": "10.00"}
    ]
    # With Sam, nothing's owed in this group once it's simplified.
    assert (await client.get(f"/v1/people/{person['id']}")).json()["balance"] == "0.00"

    off = (await client.patch(f"/v1/groups/{group['id']}", json={"simplify_debts": False})).json()
    assert {(p["from_member_id"], p["to_member_id"], p["amount"]) for p in off["payments"]} == {
        (me["id"], sam_m["id"], "10.00"),
        (sam_m["id"], kim["id"], "10.00"),
    }
    assert (await client.get(f"/v1/people/{person['id']}")).json()["balance"] == "-10.00"
    act_as(sam)
    feed = (await anon_client.get("/v1/activity")).json()
    assert any("turned off simplify debts" in a["text"] for a in feed["items"])


# ─────────────────────── live updates ───────────────────────


async def test_changes_wake_the_apps_of_the_people_they_affect(
    client, anon_client, test_user, sam, sessionmaker_
):
    from app.services import realtime

    person, _ = await _linked_sam(client, anon_client, test_user, sam)
    async with sessionmaker_() as session:
        stranger = User(email="x@example.com", display_name="X", auth0_sub="auth0|x")
        session.add(stranger)
        await session.commit()
        await session.refresh(stranger)
    sams_app = realtime.subscribe(sam.id)
    strangers_app = realtime.subscribe(stranger.id)
    try:
        split = await _expense(client, "20.00", [{"is_me": True}, {"person_id": person["id"]}])
        assert sams_app.get_nowait() == "changed"
        assert strangers_app.empty()
        # Marking Sam's share paid wakes Sam's app too (no notification email).
        sam_row = split["participants"][1]
        await client.post(
            f"/v1/splits/{split['id']}/participants/{sam_row['id']}/settled", json={"settled": True}
        )
        assert sams_app.get_nowait() == "changed"
    finally:
        realtime.unsubscribe(sam.id, sams_app)
        realtime.unsubscribe(stranger.id, strangers_app)


async def test_ticking_a_share_paid_in_a_group_settles_it(client):
    group = (
        await client.post("/v1/groups", json={"name": "Vegas", "members": ["Mit", "Smit"]})
    ).json()
    me, mit, smit = group["members"]
    split = await _expense(
        client,
        "300.00",
        [{"is_me": True}, {"member_id": mit["id"]}, {"member_id": smit["id"]}],
        group_id=group["id"],
        description="Hotel",
    )
    mit_row = split["participants"][1]
    r = await client.post(
        f"/v1/splits/{split['id']}/participants/{mit_row['id']}/settled", json={"settled": True}
    )
    assert r.json()["participants"][1]["settled"] is True
    detail = (await client.get(f"/v1/groups/{group['id']}")).json()
    assert [m["balance"] for m in detail["members"]] == ["100.00", "0.00", "-100.00"]
    assert detail["payments"] == [
        {"from_member_id": smit["id"], "to_member_id": me["id"], "amount": "100.00"}
    ]
    timeline = (await client.get(f"/v1/splits/{split['id']}/timeline")).json()
    assert timeline[-1]["text"] == "marked Mit's share paid"
    # Direct (not simplified) agrees.
    off = (await client.patch(f"/v1/groups/{group['id']}", json={"simplify_debts": False})).json()
    assert off["payments"] == detail["payments"]


async def test_home_currency_follows_your_receipts_until_you_set_it(client):
    assert (await client.get("/v1/auth/me")).json()["currency"] is None
    for _ in range(2):
        await client.post(
            "/v1/receipts",
            json={"merchant": "Loblaws", "total": "10", "currency": "CAD", "items": []},
        )
    await client.post(
        "/v1/receipts", json={"merchant": "Target", "total": "5", "currency": "USD", "items": []}
    )
    me = (await client.get("/v1/auth/me")).json()
    assert (me["currency"], me["currency_is_set"]) == ("CAD", False)
    me = (await client.patch("/v1/auth/me", json={"currency": "eur"})).json()
    assert (me["currency"], me["currency_is_set"]) == ("EUR", True)
    assert (await client.patch("/v1/auth/me", json={"currency": "E1"})).status_code == 422
    assert (await client.patch("/v1/auth/me", json={"currency": ""})).json()["currency"] == "CAD"
