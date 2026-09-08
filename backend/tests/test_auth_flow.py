async def test_me_returns_current_user(client):
    resp = await client.get("/v1/auth/me")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["email"] == "t@example.com"
    assert body["plan"] == "free"
    assert body["display_name"] == "T"
    assert "id" in body


async def test_me_requires_a_token(anon_client):
    resp = await anon_client.get("/v1/auth/me")
    # HTTPBearer(auto_error=True) → 403 when the header is absent.
    assert resp.status_code in (401, 403)


async def test_extract_requires_a_token(anon_client):
    resp = await anon_client.post(
        "/v1/extract",
        json={"imageBase64": "", "ocrLines": [], "clientRequestID": "x"},
    )
    assert resp.status_code in (401, 403)
