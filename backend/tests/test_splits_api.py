"""Splits and groups end to end (docs/SPLITS.md)."""

from datetime import UTC, datetime

import pytest_asyncio

from app.api.deps import get_current_user
from app.main import app
from app.models import User

TODAY = datetime.now(UTC).date().isoformat()


@pytest_asyncio.fixture
async def other_user(sessionmaker_) -> User:
    async with sessionmaker_() as session:
        user = User(email="sam@example.com", display_name="Sam", auth0_sub="auth0|sam")
        session.add(user)
        await session.commit()
        await session.refresh(user)
        return user


def act_as(user: User) -> None:
    app.dependency_overrides[get_current_user] = lambda: user


async def _receipt(client, total="60.00", items=None):
    r = await client.post(
        "/v1/receipts",
        json={
            "merchant": "Pizzeria",
            "date": TODAY,
            "total": total,
            "category": "restaurants",
            "items": items or [],
        },
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


async def _my_expense_amount(client, receipt_id):
    expenses = (await client.get("/v1/expenses")).json()
    return next(e["amount"] for e in expenses if e["receipt_id"] == receipt_id)


# ─────────────────────────── one-off splits ───────────────────────────


async def test_split_receipt_evenly_counts_only_my_share(client, anon_client):
    rid = await _receipt(client, "60.00")
    r = await client.post(
        "/v1/splits",
        json={
            "receipt_id": rid,
            "mode": "even",
            "participants": [{"is_me": True}, {"name": "Alex"}, {"name": "Kim"}],
        },
    )
    assert r.status_code == 201, r.text
    split = r.json()
    assert [p["share"] for p in split["participants"]] == ["20.00", "20.00", "20.00"]
    assert split["my_share"] == "20.00"
    me = next(p for p in split["participants"] if p["is_me"])
    assert me["is_payer"] and me["display_name"] == "T"

    # My spending is my share; the receipt keeps its full total.
    assert await _my_expense_amount(client, rid) == "20.00"
    receipt = next(x for x in (await client.get("/v1/receipts")).json() if x["id"] == rid)
    assert (receipt["total"], receipt["my_share"], receipt["split_id"]) == (
        "60.00",
        "20.00",
        split["id"],
    )

    # Alex's link works without an account and shows a snapshot.
    alex = next(p for p in split["participants"] if p["display_name"] == "Alex")
    token = alex["share_url"].rsplit("/", 1)[1]
    public = (await anon_client.get(f"/v1/public/splits/{token}")).json()
    assert public["your_share"] == "20.00"
    assert public["payer_name"] == "T"
    assert [p["is_you"] for p in public["participants"]] == [False, True, False]


async def test_items_split_and_editing_the_receipt_recomputes(client):
    items = [
        {"name": "Pasta", "price": "20.00", "quantity": 1},
        {"name": "Salad", "price": "10.00", "quantity": 1},
    ]
    rid = await _receipt(client, "33.00", items)  # 3.00 of tax
    split = (
        await client.post(
            "/v1/splits",
            json={
                "receipt_id": rid,
                "mode": "items",
                "participants": [
                    {"is_me": True, "item_indexes": [0]},
                    {"name": "Alex", "item_indexes": [1]},
                ],
            },
        )
    ).json()
    assert [p["share"] for p in split["participants"]] == ["22.00", "11.00"]

    # Fix the total (tax was really 6.00): shares follow, and so does my spending.
    r = await client.patch(f"/v1/receipts/{rid}", json={"total": "36.00"})
    assert r.json()["my_share"] == "24.00"
    assert await _my_expense_amount(client, rid) == "24.00"


async def test_unsplitting_restores_the_full_total(client):
    rid = await _receipt(client, "40.00")
    split = (
        await client.post(
            "/v1/splits",
            json={"receipt_id": rid, "participants": [{"is_me": True}, {"name": "Alex"}]},
        )
    ).json()
    assert await _my_expense_amount(client, rid) == "20.00"
    assert (await client.delete(f"/v1/splits/{split['id']}")).status_code == 204
    assert await _my_expense_amount(client, rid) == "40.00"


async def test_a_receipt_can_only_be_split_once(client):
    rid = await _receipt(client)
    body = {"receipt_id": rid, "participants": [{"is_me": True}, {"name": "A"}]}
    assert (await client.post("/v1/splits", json=body)).status_code == 201
    assert (await client.post("/v1/splits", json=body)).status_code == 409


async def test_settle_a_one_off_share(client):
    rid = await _receipt(client)
    split = (
        await client.post(
            "/v1/splits",
            json={"receipt_id": rid, "participants": [{"is_me": True}, {"name": "Alex"}]},
        )
    ).json()
    alex = split["participants"][1]
    r = await client.post(
        f"/v1/splits/{split['id']}/participants/{alex['id']}/settled", json={"settled": True}
    )
    assert r.json()["participants"][1]["settled"] is True


async def test_split_by_shares_and_editing_the_total_keeps_the_ratio(client):
    rid = await _receipt(client, "30.72")
    r = await client.post(
        "/v1/splits",
        json={
            "receipt_id": rid,
            "mode": "shares",
            "participants": [{"is_me": True, "weight": "2"}, {"name": "Zalak", "weight": "3"}],
        },
    )
    assert r.status_code == 201, r.text
    split = r.json()
    assert [(p["weight"], p["share"]) for p in split["participants"]] == [
        ("2", "12.29"),
        ("3", "18.43"),
    ]
    r = await client.patch(f"/v1/receipts/{rid}", json={"total": "50.00"})
    assert r.json()["my_share"] == "20.00"
    bad = await client.post(
        "/v1/splits",
        json={
            "description": "x",
            "total": "10",
            "mode": "shares",
            "participants": [{"is_me": True, "weight": "NaN"}, {"name": "A"}],
        },
    )
    assert bad.status_code == 422


async def test_custom_amounts_that_dont_add_up_are_rejected(client):
    rid = await _receipt(client, "50.00")
    r = await client.post(
        "/v1/splits",
        json={
            "receipt_id": rid,
            "mode": "custom",
            "participants": [{"is_me": True, "amount": "10"}, {"name": "A", "amount": "10"}],
        },
    )
    assert r.status_code == 422
    assert "add up" in r.json()["detail"]


async def test_deleting_a_split_receipt_removes_the_split(client, anon_client):
    rid = await _receipt(client)
    split = (
        await client.post(
            "/v1/splits",
            json={"receipt_id": rid, "participants": [{"is_me": True}, {"name": "A"}]},
        )
    ).json()
    token = split["participants"][1]["share_url"].rsplit("/", 1)[1]
    assert (await client.delete(f"/v1/receipts/{rid}")).status_code == 204
    assert (await anon_client.get(f"/v1/public/splits/{token}")).status_code == 404


# ─────────────────────────── groups ───────────────────────────


async def test_group_balances_join_and_settle(client, anon_client, test_user, other_user):
    group = (await client.post("/v1/groups", json={"name": "Ski trip", "members": ["Sam"]})).json()
    me = next(m for m in group["members"] if m["is_me"])
    sam = next(m for m in group["members"] if m["display_name"] == "Sam")
    assert not sam["has_account"]

    # I paid 90 for the cabin, split evenly.
    r = await client.post(
        "/v1/splits",
        json={
            "group_id": group["id"],
            "description": "Cabin",
            "total": "90.00",
            "participants": [{"is_me": True}, {"member_id": sam["id"]}],
        },
    )
    assert r.status_code == 201, r.text
    detail = (await client.get(f"/v1/groups/{group['id']}")).json()
    assert detail["my_balance"] == "45.00"
    assert detail["payments"] == [
        {"from_member_id": sam["id"], "to_member_id": me["id"], "amount": "45.00"}
    ]

    # Sam opens the invite, signs in, and claims the "Sam" placeholder.
    token = group["invite_url"].rsplit("/", 1)[1]
    public = (await anon_client.get(f"/v1/public/groups/{token}")).json()
    assert [m["claimed"] for m in public["members"]] == [True, False]
    act_as(other_user)
    joined = (
        await anon_client.post(f"/v1/groups/join/{token}", json={"member_id": sam["id"]})
    ).json()
    assert joined["my_balance"] == "-45.00"
    assert [g["name"] for g in (await anon_client.get("/v1/groups")).json()] == ["Ski trip"]

    # Sam pays me back: everyone's square.
    r = await anon_client.post(
        f"/v1/groups/{group['id']}/settlements",
        json={"from_member_id": sam["id"], "to_member_id": me["id"], "amount": "45.00"},
    )
    assert r.json()["payments"] == []
    act_as(test_user)
    assert (await client.get(f"/v1/groups/{group['id']}")).json()["my_balance"] == "0.00"

    # Sam is on an expense, so he can't be removed out from under the balances.
    assert (await client.delete(f"/v1/groups/{group['id']}/members/{sam['id']}")).status_code == 409


async def test_non_members_cant_see_a_group(client, test_user, other_user):
    group = (await client.post("/v1/groups", json={"name": "Flat"})).json()
    act_as(other_user)
    assert (await client.get(f"/v1/groups/{group['id']}")).status_code == 404
    act_as(test_user)


async def test_group_split_needs_members_of_that_group(client):
    group = (await client.post("/v1/groups", json={"name": "Flat"})).json()
    r = await client.post(
        "/v1/splits",
        json={
            "group_id": group["id"],
            "description": "Rent",
            "total": "100",
            "participants": [{"is_me": True}, {"name": "Stranger"}],
        },
    )
    assert r.status_code == 422


async def test_deleting_a_group_unsplits_its_receipts(client):
    group = (await client.post("/v1/groups", json={"name": "Flat", "members": ["Kim"]})).json()
    kim = next(m for m in group["members"] if not m["is_me"])
    rid = await _receipt(client, "30.00")
    await client.post(
        "/v1/splits",
        json={
            "receipt_id": rid,
            "group_id": group["id"],
            "participants": [{"is_me": True}, {"member_id": kim["id"]}],
        },
    )
    assert await _my_expense_amount(client, rid) == "15.00"
    assert (await client.delete(f"/v1/groups/{group['id']}")).status_code == 204
    assert await _my_expense_amount(client, rid) == "30.00"
