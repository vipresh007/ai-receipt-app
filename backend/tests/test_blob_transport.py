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
