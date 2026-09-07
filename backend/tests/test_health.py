async def test_healthz(client):
    resp = await client.get("/healthz")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["azure_openai_configured"] is False


async def test_root(client):
    resp = await client.get("/")
    assert resp.status_code == 200
    assert resp.json()["name"] == "AI Receipt API"
