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
