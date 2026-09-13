async def _receipt(client, merchant: str, total: str, date: str, category: str = "entertainment"):
    resp = await client.post(
        "/v1/receipts",
        json={"merchant": merchant, "date": date, "total": total, "category": category},
    )
    assert resp.status_code == 201, resp.text


async def test_no_receipts_no_recurring(client):
    resp = await client.get("/v1/receipts/recurring")
    assert resp.status_code == 200
    assert resp.json() == []


async def test_same_merchant_two_months_same_amount_is_recurring(client):
    await _receipt(client, "Netflix", "15.49", "2026-07-01")
    await _receipt(client, "Netflix", "15.49", "2026-08-01")

    resp = await client.get("/v1/receipts/recurring")
    assert resp.status_code == 200
    groups = resp.json()
    assert len(groups) == 1
    assert groups[0]["merchant"] == "Netflix"
    assert groups[0]["occurrences"] == 2
    assert groups[0]["average_amount"] == "15.49"


async def test_one_off_purchase_is_not_recurring(client):
    await _receipt(client, "Corner Store", "12.00", "2026-09-01")
    resp = (await client.get("/v1/receipts/recurring")).json()
    assert resp == []


async def test_same_month_twice_is_not_recurring(client):
    # Two visits in the same calendar month shouldn't count as "recurring" —
    # that's just going to the same place twice, not a subscription.
    await _receipt(client, "Corner Store", "12.00", "2026-09-01")
    await _receipt(client, "Corner Store", "12.00", "2026-09-15")
    resp = (await client.get("/v1/receipts/recurring")).json()
    assert resp == []


async def test_wildly_different_amounts_are_not_recurring(client):
    await _receipt(client, "Amazon", "10.00", "2026-07-01")
    await _receipt(client, "Amazon", "300.00", "2026-08-01")
    resp = (await client.get("/v1/receipts/recurring")).json()
    assert resp == []


async def test_merchant_matching_is_case_insensitive(client):
    await _receipt(client, "spotify", "9.99", "2026-07-01")
    await _receipt(client, "Spotify", "9.99", "2026-08-01")
    groups = (await client.get("/v1/receipts/recurring")).json()
    assert len(groups) == 1
    assert groups[0]["occurrences"] == 2


async def test_recurring_requires_auth(anon_client):
    resp = await anon_client.get("/v1/receipts/recurring")
    assert resp.status_code in (401, 403)
