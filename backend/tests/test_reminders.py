"""Return and warranty dates, and their reminders (services/reminders.py)."""

from datetime import date

from sqlalchemy import select

from app.models import Activity
from app.services import reminders
from app.services.extraction import return_by


def test_return_window_from_the_receipt():
    assert return_by(date(2026, 10, 1), 30) == date(2026, 10, 31)
    assert return_by(date(2026, 10, 1), None) is None
    assert return_by(None, 30) is None


async def test_dates_are_saved_and_reminded_once(client, sessionmaker_, test_user):
    r = await client.post(
        "/v1/receipts",
        json={
            "merchant": "Best Buy",
            "date": "2026-10-20",
            "total": "199",
            "return_by": "2026-11-04",
        },
    )
    rid = r.json()["id"]
    assert r.json()["return_by"] == "2026-11-04"
    r = await client.patch(f"/v1/receipts/{rid}", json={"warranty_until": "2026-11-20"})
    assert r.json()["warranty_until"] == "2026-11-20"

    async with sessionmaker_() as session:
        assert await reminders.send_due(session, date(2026, 10, 15)) == 0  # too early
    async with sessionmaker_() as session:
        assert await reminders.send_due(session, date(2026, 11, 2)) == 2  # both due
    async with sessionmaker_() as session:
        assert await reminders.send_due(session, date(2026, 11, 3)) == 0  # once each
        texts = sorted((await session.scalars(select(Activity.text))).all())
    assert texts == [
        "Last day to return your Best Buy purchase is Wed, Nov 4.",
        "The warranty on your Best Buy purchase ends Fri, Nov 20.",
    ]

    # Clearing a date (and setting it again) re-arms its reminder.
    await client.patch(f"/v1/receipts/{rid}", json={"return_by": None})
    assert (await client.get(f"/v1/receipts/{rid}")).json()["return_by"] is None


async def test_coming_up_lists_what_closes_soon(client):
    from datetime import timedelta

    soon = (date.today() + timedelta(days=5)).isoformat()
    later = (date.today() + timedelta(days=200)).isoformat()
    await client.post("/v1/receipts", json={"merchant": "Soon", "total": "1", "return_by": soon})
    await client.post("/v1/receipts", json={"merchant": "Later", "total": "1", "return_by": later})
    rows = (await client.get("/v1/receipts/coming-up")).json()
    assert [r["merchant"] for r in rows] == ["Soon"]
