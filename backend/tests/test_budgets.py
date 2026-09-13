async def _spend(client, category: str, total: str, date: str = "2026-09-05"):
    resp = await client.post(
        "/v1/receipts",
        json={
            "merchant": "Test",
            "date": date,
            "total": total,
            "category": category,
        },
    )
    assert resp.status_code == 201, resp.text


async def test_no_budgets_returns_empty_list(client):
    resp = await client.get("/v1/budgets")
    assert resp.status_code == 200
    assert resp.json() == []


async def test_set_then_list_budget_computes_spend(client):
    resp = await client.put("/v1/budgets/groceries", json={"monthly_limit": "300.00"})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["category_slug"] == "groceries"
    assert body["monthly_limit"] == "300.00"
    assert body["spent"] == "0.00"

    await _spend(client, "groceries", "45.00")
    await _spend(client, "groceries", "30.00")
    # a different category shouldn't leak into this budget's spend
    await _spend(client, "restaurants", "100.00")

    listed = (await client.get("/v1/budgets")).json()
    assert len(listed) == 1
    groceries = listed[0]
    assert groceries["spent"] == "75.00"
    assert groceries["remaining"] == "225.00"
    assert groceries["percent_used"] == 25.0


async def test_set_budget_is_an_upsert(client):
    await client.put("/v1/budgets/groceries", json={"monthly_limit": "300.00"})
    resp = await client.put("/v1/budgets/groceries", json={"monthly_limit": "400.00"})
    assert resp.status_code == 200
    listed = (await client.get("/v1/budgets")).json()
    assert len(listed) == 1
    assert listed[0]["monthly_limit"] == "400.00"


async def test_set_budget_rejects_unknown_category(client):
    resp = await client.put("/v1/budgets/not-a-category", json={"monthly_limit": "100.00"})
    assert resp.status_code == 422


async def test_set_budget_rejects_zero_or_negative(client):
    resp = await client.put("/v1/budgets/groceries", json={"monthly_limit": "0.00"})
    assert resp.status_code == 422
    resp = await client.put("/v1/budgets/groceries", json={"monthly_limit": "-5.00"})
    assert resp.status_code == 422


async def test_delete_budget(client):
    await client.put("/v1/budgets/groceries", json={"monthly_limit": "300.00"})
    resp = await client.delete("/v1/budgets/groceries")
    assert resp.status_code == 204
    assert (await client.get("/v1/budgets")).json() == []
    # deleting again is a no-op, not an error
    resp = await client.delete("/v1/budgets/groceries")
    assert resp.status_code == 204


async def test_budget_month_param_scopes_spend(client):
    await client.put("/v1/budgets/groceries", json={"monthly_limit": "300.00"})
    await _spend(client, "groceries", "50.00", date="2026-08-15")
    await _spend(client, "groceries", "20.00", date="2026-09-15")

    august = (await client.get("/v1/budgets?month=2026-08")).json()[0]
    assert august["spent"] == "50.00"

    september = (await client.get("/v1/budgets?month=2026-09")).json()[0]
    assert september["spent"] == "20.00"


async def test_budgets_require_auth(anon_client):
    resp = await anon_client.get("/v1/budgets")
    assert resp.status_code in (401, 403)
