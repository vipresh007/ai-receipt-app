"""Item prices across receipts (services/prices.py)."""

from app.services.prices import key


def test_key_matches_names_across_stores():
    assert key("OAT MILK 1L") == key("Oat milk, 1L") == "oat milk 1l"
    assert key("Honeycrisp 1.2kg") == "honeycrisp 1.2kg"


async def _receipt(client, merchant, day, items):
    r = await client.post(
        "/v1/receipts",
        json={
            "merchant": merchant,
            "date": day,
            "total": "20",
            "category": "groceries",
            "items": items,
        },
    )
    assert r.status_code == 201, r.text


async def test_prices_track_what_you_buy_again(client):
    await _receipt(client, "Loblaws", "2026-06-02", [{"name": "Oat milk 1L", "price": "3.99"}])
    await _receipt(
        client,
        "Farm Boy",
        "2026-08-10",
        [{"name": "OAT MILK 1L", "price": "8.98", "quantity": 2}, {"name": "Bread", "price": "5"}],
    )
    await _receipt(client, "Loblaws", "2026-10-01", [{"name": "oat milk 1l", "price": "4.49"}])

    items = (await client.get("/v1/receipts/prices")).json()
    assert [i["key"] for i in items] == ["oat milk 1l"]  # bread was bought once
    milk = items[0]
    assert milk["latest_price"] == "4.49"
    assert [p["unit_price"] for p in milk["purchases"]] == ["3.99", "4.49", "4.49"]
    # The two latest are the same price, so it compares with June's.
    assert milk["previous_price"] == "3.99" and milk["previous_date"] == "2026-06-02"
    assert round(milk["change"], 3) == 0.125
