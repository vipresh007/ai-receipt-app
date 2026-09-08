async def test_healthz(client):
    resp = await client.get("/healthz")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert {"auth_configured", "azure_openai_configured", "blob_configured"} <= body.keys()


async def test_root(client):
    resp = await client.get("/")
    assert resp.status_code == 200
    assert resp.json()["name"] == "AI Receipt API"
