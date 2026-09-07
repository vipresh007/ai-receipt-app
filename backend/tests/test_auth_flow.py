async def test_register_then_login(client):
    reg = await client.post(
        "/v1/auth/register",
        json={"email": "New@Example.com", "password": "abcd1234!x", "display_name": "New"},
    )
    assert reg.status_code == 201, reg.text
    assert reg.json()["access_token"]
    assert reg.json()["token_type"] == "bearer"

    dup = await client.post(
        "/v1/auth/register",
        json={"email": "new@example.com", "password": "abcd1234!x"},
    )
    assert dup.status_code == 409

    login = await client.post(
        "/v1/auth/login",
        json={"email": "new@example.com", "password": "abcd1234!x"},
    )
    assert login.status_code == 200
    assert login.json()["access_token"]

    bad = await client.post(
        "/v1/auth/login",
        json={"email": "new@example.com", "password": "nope"},
    )
    assert bad.status_code == 401


async def test_register_rejects_short_password(client):
    resp = await client.post(
        "/v1/auth/register",
        json={"email": "a@b.com", "password": "short"},
    )
    assert resp.status_code == 422
