"""Local demo API for App Store screenshots: made-up people, no Auth0.
Pairs with the iOS Debug launch argument -demoAccount (docs/APP_STORE.md).

Run from backend/:  PYTHONPATH=. .venv/bin/python ../brand/app-store/demo_server.py ; serves http://127.0.0.1:8765.
Every request is "Alex" (the bearer is ignored). Data lives in memory.
"""

import asyncio
import os
from datetime import date, timedelta

os.environ["AI_RECEIPT_TEST"] = "1"  # no .env, no background jobs
os.environ["AUTO_CREATE_TABLES"] = "false"

import uvicorn
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.api.deps import get_current_user, get_current_user_optional, get_extractor
from app.schemas.extraction import ExtractedReceipt
from app.db import get_session
from app.main import app
from app.models import Base, User

TODAY = date(2026, 10, 30)


def d(days_ago: int) -> str:
    return (TODAY - timedelta(days=days_ago)).isoformat()


async def main() -> None:
    engine = create_async_engine(
        "sqlite+aiosqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    maker = async_sessionmaker(engine, expire_on_commit=False)

    async with maker() as s:
        alex = User(email="alex@example.com", display_name="Alex", auth0_sub="demo|alex",
                    email_verified=True, currency="CAD")
        sam = User(email="sam@example.com", display_name="Sam", auth0_sub="demo|sam",
                   email_verified=True, currency="CAD")
        priya = User(email="priya@example.com", display_name="Priya", auth0_sub="demo|priya",
                     email_verified=True, currency="CAD", interac="priya@example.com")
        s.add_all([alex, sam, priya])
        await s.commit()

    current = {"user": alex}

    async def _session():
        async with maker() as session:
            yield session

    app.dependency_overrides[get_session] = _session
    app.dependency_overrides[get_current_user] = lambda: current["user"]
    app.dependency_overrides[get_current_user_optional] = lambda: current["user"]

    class Northfield:
        def extract(self, **_):
            return ExtractedReceipt(
                merchant="Northfield Market", purchased_at=d(1), total="42.75", tax="0.65",
                category="groceries", currency="CAD", confidence=0.96,
                line_items=[{"name": n, "price": p, "quantity": 1} for n, p in (
                    ("Oat milk 1L", "4.49"), ("Sourdough loaf", "6.50"),
                    ("Honeycrisp apples 1.2kg", "5.14"), ("Greek yogurt 750g", "5.99"),
                    ("Coffee beans 340g", "14.99"), ("Spinach 312g", "4.99"))],
            )

    app.dependency_overrides[get_extractor] = Northfield

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://demo") as c:

        async def ok(r):
            assert r.status_code < 300, r.text
            return r.json()

        # ── Tofino weekend ──
        g = await ok(await c.post("/v1/groups", json={
            "name": "Tofino weekend", "currency": "CAD", "members": ["Sam", "Priya", "Jordan"]}))
        me, sam_m, priya_m, jordan_m = g["members"]
        token = g["invite_url"].rsplit("/", 1)[1]
        for user, m in ((sam, sam_m), (priya, priya_m)):
            current["user"] = user
            await ok(await c.post(f"/v1/groups/join/{token}", json={"member_id": m["id"]}))
        current["user"] = alex

        async def expense(who, desc, total, parts, days, **extra):
            current["user"] = who
            r = await ok(await c.post("/v1/splits", json={
                "group_id": g["id"], "description": desc, "total": total, "currency": "CAD",
                "date": d(days), "participants": parts, **extra}))
            current["user"] = alex
            return r

        everyone = [me, sam_m, priya_m, jordan_m]

        def even(payer):
            return [{"member_id": m["id"], "is_payer": m["id"] == payer["id"]} for m in everyone]

        await expense(priya, "Cabin on Chesterman Beach", "520.00", even(priya_m), 40)
        await expense(sam, "Groceries, Save-On-Foods", "186.40", even(sam_m), 39)
        await expense(alex, "Surf lessons", "360.00", even(me), 38)
        current["user"] = alex
        await expense(alex, "Gas, both cars", "92.30", even(jordan_m), 37)

        # A receipt split item by item, in the group.
        items = [
            {"name": "Seafood chowder", "price": "16.00"},
            {"name": "Ling cod tacos", "price": "24.00"},
            {"name": "Halibut & chips", "price": "29.00"},
            {"name": "Steak frites", "price": "38.00"},
            {"name": "Oysters (half dozen)", "price": "21.00"},
            {"name": "Local IPA x3", "price": "27.00"},
        ]
        receipt = await ok(await c.post("/v1/receipts", json={
            "merchant": "Wolf in the Fog", "date": d(2), "total": "176.75", "tax": "21.75",
            "category": "restaurants", "currency": "CAD", "items": items}))
        await ok(await c.post("/v1/splits", json={
            "receipt_id": receipt["id"], "group_id": g["id"], "mode": "items",
            "participants": [
                {"is_me": True, "is_payer": True, "item_indexes": [0, 4]},
                {"member_id": sam_m["id"], "item_indexes": [3, 5]},
                {"member_id": priya_m["id"], "item_indexes": [2]},
                {"member_id": jordan_m["id"], "item_indexes": [1]},
            ]}))

        # Sam paid back part of it.
        current["user"] = sam
        await ok(await c.post(f"/v1/groups/{g['id']}/settlements", json={
            "from_member_id": sam_m["id"], "to_member_id": me["id"], "amount": "60.00"}))
        current["user"] = alex

        # ── Roommates ──
        h = await ok(await c.post("/v1/groups", json={
            "name": "Apartment", "currency": "CAD", "members": ["Maya"]}))
        hm, maya = h["members"]
        for desc, total, days in (("Hydro", "96.40", 12), ("Internet", "75.00", 6)):
            await ok(await c.post("/v1/splits", json={
                "group_id": h["id"], "description": desc, "total": total, "currency": "CAD",
                "date": d(days), "repeat": "monthly",
                "participants": [{"member_id": hm["id"], "is_payer": True},
                                 {"member_id": maya["id"]}]}))

        # ── One person, no group ──
        noah = await ok(await c.post("/v1/people", json={"name": "Noah"}))
        await ok(await c.post("/v1/splits", json={
            "description": "Raptors tickets", "total": "184.00", "currency": "CAD", "date": d(9),
            "participants": [{"is_me": True, "is_payer": True}, {"person_id": noah["id"]}]}))
        emma = await ok(await c.post("/v1/people", json={"name": "Emma"}))
        await ok(await c.post("/v1/splits", json={
            "description": "Brunch, Lady Marmalade", "total": "64.80", "currency": "CAD",
            "date": d(4), "participants": [{"is_me": True},
                                           {"person_id": emma["id"], "is_payer": True}]}))

    print("demo data ready", flush=True)
    server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=8765, log_level="warning"))
    await server.serve()


asyncio.run(main())
