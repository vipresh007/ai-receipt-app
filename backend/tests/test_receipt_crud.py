import base64
from uuid import uuid4

_IMG = base64.b64encode(b"pretend-jpeg").decode()


def _new(**over):
    body = {
        "merchant": "Corner Store",
        "date": "2026-09-03",
        "total": "9.99",
        "tax": "0.80",
        "category": "groceries",
        "items": [{"name": "Milk", "price": "3.50", "quantity": 1}],
    }
    body.update(over)
    return body


async def test_create_then_list(client):
    resp = await client.post("/v1/receipts", json=_new())
    assert resp.status_code == 201, resp.text
    created = resp.json()
    assert created["merchant"] == "Corner Store"
    assert created["total"] == "9.99"
    assert "id" in created

    listed = await client.get("/v1/receipts")
    assert [r["id"] for r in listed.json()] == [created["id"]]


async def test_manual_expense_note_reaches_the_expense(client):
    await client.post("/v1/receipts", json=_new(merchant="Split dinner", note="paid for 4"))
    expenses = (await client.get("/v1/expenses")).json()
    assert expenses[0]["note"] == "paid for 4"


async def test_patch_updates_receipt_and_expense(client):
    rid = (await client.post("/v1/receipts", json=_new())).json()["id"]

    resp = await client.patch(
        f"/v1/receipts/{rid}",
        json={"merchant": "Corner Deli", "total": "12.00", "category": "restaurants"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["merchant"] == "Corner Deli"
    assert body["total"] == "12.00"
    assert body["category_slug"] == "restaurants"

    # untouched fields survive
    assert body["tax"] == "0.80"

    # the linked expense followed the change
    summary = (await client.get("/v1/expenses/summary")).json()
    assert summary["by_category"] and summary["by_category"][0]["category_slug"] == "restaurants"


async def test_delete_removes_receipt_and_expense(client):
    rid = (await client.post("/v1/receipts", json=_new())).json()["id"]

    resp = await client.delete(f"/v1/receipts/{rid}")
    assert resp.status_code == 204

    assert (await client.get("/v1/receipts")).json() == []
    expenses = (await client.get("/v1/expenses")).json()
    assert expenses == []


async def test_patch_unknown_receipt_is_404(client):
    resp = await client.patch(f"/v1/receipts/{uuid4()}", json={"merchant": "x"})
    assert resp.status_code == 404


async def test_delete_unknown_receipt_is_404(client):
    resp = await client.delete(f"/v1/receipts/{uuid4()}")
    assert resp.status_code == 404


async def test_receipt_image_404_when_none_stored(client):
    rid = (await client.post("/v1/receipts", json=_new())).json()["id"]
    # No blob configured in tests → nothing was stored.
    resp = await client.get(f"/v1/receipts/{rid}/image")
    assert resp.status_code == 404


async def test_get_single_receipt(client):
    rid = (await client.post("/v1/receipts", json=_new())).json()["id"]
    resp = await client.get(f"/v1/receipts/{rid}")
    assert resp.status_code == 200, resp.text
    assert resp.json()["merchant"] == "Corner Store"


async def test_get_unknown_receipt_is_404(client):
    resp = await client.get(f"/v1/receipts/{uuid4()}")
    assert resp.status_code == 404


async def test_recurring_route_still_resolves_alongside_single_receipt_route(client):
    # Regression guard: "/receipts/{receipt_id}" is registered after
    # "/receipts/recurring" specifically so "recurring" never gets swallowed
    # as a (invalid) UUID path param.
    resp = await client.get("/v1/receipts/recurring")
    assert resp.status_code == 200
    assert resp.json() == []


async def test_search_filters_by_merchant_case_insensitive(client):
    await client.post("/v1/receipts", json=_new(merchant="Blue Bottle Coffee"))
    await client.post("/v1/receipts", json=_new(merchant="Corner Store"))

    resp = await client.get("/v1/receipts?q=blue")
    assert [r["merchant"] for r in resp.json()] == ["Blue Bottle Coffee"]


async def test_search_matches_line_item_names(client):
    await client.post(
        "/v1/receipts",
        json=_new(merchant="Corner Store", items=[{"name": "Sourdough Bread", "price": "5.00"}]),
    )
    await client.post(
        "/v1/receipts",
        json=_new(merchant="Corner Store", items=[{"name": "Milk", "price": "3.50"}]),
    )

    resp = await client.get("/v1/receipts?q=sourdough")
    matches = resp.json()
    assert len(matches) == 1
    assert matches[0]["line_items"][0]["name"] == "Sourdough Bread"


async def test_filter_by_category(client):
    await client.post("/v1/receipts", json=_new(merchant="A", category="groceries"))
    await client.post("/v1/receipts", json=_new(merchant="B", category="restaurants"))

    resp = await client.get("/v1/receipts?category=restaurants")
    assert [r["merchant"] for r in resp.json()] == ["B"]


async def test_filter_by_amount_range(client):
    await client.post("/v1/receipts", json=_new(merchant="Cheap", total="5.00"))
    await client.post("/v1/receipts", json=_new(merchant="Mid", total="50.00"))
    await client.post("/v1/receipts", json=_new(merchant="Pricey", total="500.00"))

    resp = await client.get("/v1/receipts?min_amount=10&max_amount=100")
    assert [r["merchant"] for r in resp.json()] == ["Mid"]


async def test_signed_in_extract_returns_receipt_id(client):
    resp = await client.post(
        "/v1/extract",
        json={"imageBase64": _IMG, "ocrLines": [], "clientRequestID": "r1"},
    )
    assert resp.status_code == 200
    rid = resp.json()["id"]
    assert rid

    listed = await client.get("/v1/receipts")
    assert [r["id"] for r in listed.json()] == [rid]
