"""The async Azure Blob client needs aiohttp at runtime; without it every
receipt photo upload failed quietly (logged, receipt saved with no image)."""


def test_async_blob_transport_is_installed():
    import aiohttp  # noqa: F401
    from azure.core.pipeline.transport import AioHttpTransport  # noqa: F401


async def test_receipts_say_when_they_were_added_and_edited(client):
    r = await client.post(
        "/v1/receipts",
        json={
            "merchant": "FreshCo",
            "date": "2026-10-09",
            "total": "30.72",
            "category": "groceries",
        },
    )
    out = r.json()
    assert out["created_at"] and out["updated_at"]
    listed = (await client.get("/v1/receipts")).json()
    assert listed[0]["created_at"] == out["created_at"]


async def test_a_phone_can_attach_the_photo_the_server_missed(client, monkeypatch):
    import base64

    from app.api.routes import receipts as routes
    from app.config import get_settings

    stored: list[bytes] = []

    class FakeBlob:
        def __init__(self, settings):
            pass

        async def upload_receipt_image(self, *, user_id, request_id, data):
            stored.append(data)
            return f"https://blob.example/{request_id}.jpg"

    settings = get_settings()
    monkeypatch.setattr(type(settings), "blob_configured", property(lambda self: True))
    monkeypatch.setattr(routes, "BlobStorage", FakeBlob)

    rid = (
        await client.post("/v1/receipts", json={"merchant": "FreshCo", "total": "30.72"})
    ).json()["id"]
    body = {"image_base64": base64.b64encode(b"jpeg-bytes").decode()}
    out = (await client.put(f"/v1/receipts/{rid}/image", json=body)).json()
    assert out["image_blob_url"].startswith("https://blob.example/")
    assert stored == [b"jpeg-bytes"]
    # Already has one: left alone.
    await client.put(f"/v1/receipts/{rid}/image", json=body)
    assert len(stored) == 1
