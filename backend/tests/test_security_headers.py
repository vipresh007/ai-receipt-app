async def test_api_responses_carry_security_headers(client):
    resp = await client.get("/v1/receipts")
    assert resp.headers["x-content-type-options"] == "nosniff"
    assert resp.headers["x-frame-options"] == "DENY"
    assert resp.headers["strict-transport-security"].startswith("max-age=")
    assert resp.headers["cache-control"] == "no-store"


async def test_health_is_not_marked_no_store(client):
    resp = await client.get("/healthz")
    assert resp.status_code == 200
    assert "cache-control" not in resp.headers
    assert resp.headers["x-content-type-options"] == "nosniff"
