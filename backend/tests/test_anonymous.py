import base64

from app.config import get_settings

_IMG = base64.b64encode(b"pretend-jpeg").decode()


def _payload(rid="r"):
    return {"imageBase64": _IMG, "ocrLines": [], "clientRequestID": rid}


async def test_anonymous_extract_works_and_is_not_persisted(anon_client):
    resp = await anon_client.post(
        "/v1/extract", json=_payload(), headers={"X-Device-Id": "device-A"}
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["merchant"] == "Blue Bottle Coffee"
    assert body["scans_remaining"] == 14  # limit 15, one used

    # nothing was written server-side (listing needs auth, so 401/403)
    listed = await anon_client.get("/v1/receipts")
    assert listed.status_code in (401, 403)


async def test_anonymous_extract_requires_device_id(anon_client):
    resp = await anon_client.post("/v1/extract", json=_payload())
    assert resp.status_code == 400


async def test_anonymous_quota_runs_out(anon_client):
    for i in range(15):
        r = await anon_client.post(
            "/v1/extract", json=_payload(f"r{i}"), headers={"X-Device-Id": "device-B"}
        )
        assert r.status_code == 200, (i, r.text)
    r = await anon_client.post(
        "/v1/extract", json=_payload("r15"), headers={"X-Device-Id": "device-B"}
    )
    assert r.status_code == 402
    assert "sign in" in r.json()["detail"].lower()


async def test_anonymous_extract_is_rate_limited_per_ip(anon_client, monkeypatch):
    monkeypatch.setattr(get_settings(), "anon_ip_hourly_limit", 3)
    for i in range(3):
        r = await anon_client.post(
            "/v1/extract", json=_payload(f"ip{i}"), headers={"X-Device-Id": f"dev-{i}"}
        )
        assert r.status_code == 200, (i, r.text)
    # 4th call from the same IP (different device) is refused
    r = await anon_client.post(
        "/v1/extract", json=_payload("ip3"), headers={"X-Device-Id": "dev-3"}
    )
    assert r.status_code == 429
    assert "network" in r.json()["detail"].lower()


async def test_quota_is_per_device(anon_client):
    for i in range(15):
        await anon_client.post(
            "/v1/extract", json=_payload(f"c{i}"), headers={"X-Device-Id": "device-C"}
        )
    # a different device still has its full allowance
    r = await anon_client.post(
        "/v1/extract", json=_payload("d0"), headers={"X-Device-Id": "device-D"}
    )
    assert r.status_code == 200
    assert r.json()["scans_remaining"] == 14


async def test_signed_in_extract_ignores_quota_and_persists(client):
    resp = await client.post("/v1/extract", json=_payload("s1"))
    assert resp.status_code == 200
    assert resp.json()["scans_remaining"] is None

    listed = await client.get("/v1/receipts")
    assert listed.status_code == 200
    assert len(listed.json()) == 1


async def test_import_receipts_migrates_local_data(client):
    resp = await client.post(
        "/v1/receipts/import",
        json={
            "receipts": [
                {
                    "merchant": "Corner Store",
                    "date": "2026-09-03",
                    "total": "9.99",
                    "tax": "0.80",
                    "category": "groceries",
                    "items": [{"name": "Milk", "price": "3.50", "quantity": 1}],
                },
                {"merchant": "Bus", "total": "2.75", "category": "transport"},
            ]
        },
    )
    assert resp.status_code == 201, resp.text
    assert len(resp.json()) == 2

    listed = await client.get("/v1/receipts")
    merchants = {r["merchant"] for r in listed.json()}
    assert merchants == {"Corner Store", "Bus"}


async def test_spoofed_forwarded_for_does_not_reset_the_ip_limit(anon_client, monkeypatch):
    # The ingress appends the real address to X-Forwarded-For; a caller who
    # puts a fresh fake IP at the front of the header each time must still
    # count against their real one.
    monkeypatch.setattr(get_settings(), "anon_ip_hourly_limit", 2)
    for i in range(2):
        r = await anon_client.post(
            "/v1/extract",
            json=_payload(f"spoof{i}"),
            headers={
                "X-Device-Id": f"spoof-dev-{i}",
                "X-Forwarded-For": f"10.0.0.{i}, 203.0.113.7",
            },
        )
        assert r.status_code == 200, (i, r.text)
    r = await anon_client.post(
        "/v1/extract",
        json=_payload("spoof2"),
        headers={"X-Device-Id": "spoof-dev-2", "X-Forwarded-For": "10.0.0.99, 203.0.113.7"},
    )
    assert r.status_code == 429


async def test_oversized_request_is_refused_before_reading(anon_client):
    r = await anon_client.post(
        "/v1/extract",
        content=b"{}",
        headers={
            "X-Device-Id": "big",
            "Content-Type": "application/json",
            "Content-Length": "999999999",
        },
    )
    assert r.status_code == 413


async def test_too_many_ocr_lines_is_rejected(anon_client):
    payload = _payload("ocr") | {"ocrLines": ["x"] * 501}
    r = await anon_client.post("/v1/extract", json=payload, headers={"X-Device-Id": "ocr"})
    assert r.status_code == 422
