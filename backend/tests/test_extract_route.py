import base64


async def test_extract_matches_ios_contract(client):
    payload = {
        "imageBase64": base64.b64encode(b"pretend-jpeg-bytes").decode(),
        "ocrLines": ["WHOLE FOODS MARKET", "TOTAL 12.50"],
        "clientRequestID": "req-abc-1",
    }
    resp = await client.post("/v1/extract", json=payload)
    assert resp.status_code == 200, resp.text

    body = resp.json()
    assert body["merchant"] == "Blue Bottle Coffee"
    assert body["date"] == "2026-09-01"
    assert body["total"] == "12.50"
    assert body["tax"] == "1.03"
    assert body["category"] == "restaurants"
    assert body["items"] == []
    assert body["confidence"] == 0.94


async def test_extract_rejects_bad_base64(client):
    resp = await client.post(
        "/v1/extract",
        json={"imageBase64": "!!!not base64!!!", "ocrLines": [], "clientRequestID": "x"},
    )
    assert resp.status_code == 422


async def test_extracted_receipt_is_persisted_and_listed(client):
    await client.post(
        "/v1/extract",
        json={
            "imageBase64": base64.b64encode(b"img").decode(),
            "ocrLines": [],
            "clientRequestID": "req-1",
        },
    )
    resp = await client.get("/v1/receipts")
    assert resp.status_code == 200
    receipts = resp.json()
    assert len(receipts) == 1
    assert receipts[0]["merchant"] == "Blue Bottle Coffee"
    assert receipts[0]["total"] == "12.50"


async def test_expense_summary_after_extract(client):
    await client.post(
        "/v1/extract",
        json={
            "imageBase64": base64.b64encode(b"img").decode(),
            "ocrLines": [],
            "clientRequestID": "req-2",
        },
    )
    resp = await client.get("/v1/expenses/summary")
    assert resp.status_code == 200
    body = resp.json()
    # The mock receipt is dated 2026-09-01; it only lands in "this month"
    # totals when the test runs in Sep 2026, so just assert the shape here.
    assert "total" in body
    assert "by_category" in body
