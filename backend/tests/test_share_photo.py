"""Showing the receipt photo on share links, opt-in by the owner."""

import uuid

from sqlalchemy import select

from app.config import get_settings
from app.models import Receipt
from app.services import blob_storage


async def _receipt_with_photo(client, sessionmaker_):
    r = await client.post("/v1/receipts", json={"merchant": "Wolf in the Fog", "total": "60"})
    rid = r.json()["id"]
    async with sessionmaker_() as session:
        row = await session.scalar(select(Receipt).where(Receipt.id == uuid.UUID(rid)))
        row.image_blob_url = "https://blob.test/receipts/x.jpg"
        await session.commit()
    return rid


async def test_photo_is_private_until_the_owner_shares_it(
    client, anon_client, sessionmaker_, monkeypatch
):
    rid = await _receipt_with_photo(client, sessionmaker_)
    split = (
        await client.post(
            "/v1/splits",
            json={"receipt_id": rid, "participants": [{"is_me": True}, {"name": "Kim"}]},
        )
    ).json()
    assert split["has_photo"] is True and split["photo_shared"] is False
    token = split["participants"][1]["share_url"].rsplit("/", 1)[1]

    monkeypatch.setattr(get_settings(), "azure_storage_connection_string", "x")

    async def fake_download(self, url):
        return b"\xff\xd8jpeg"

    monkeypatch.setattr(blob_storage.BlobStorage, "download_by_url", fake_download)

    assert (await anon_client.get(f"/v1/public/splits/{token}")).json()["photo"] is False
    assert (await anon_client.get(f"/v1/public/splits/{token}/photo")).status_code == 404

    r = await client.patch(f"/v1/splits/{split['id']}/photo", json={"shared": True})
    assert r.status_code == 200 and r.json()["photo_shared"] is True
    assert (await anon_client.get(f"/v1/public/splits/{token}")).json()["photo"] is True
    photo = await anon_client.get(f"/v1/public/splits/{token}/photo")
    assert photo.status_code == 200 and photo.headers["content-type"] == "image/jpeg"

    await client.patch(f"/v1/splits/{split['id']}/photo", json={"shared": False})
    assert (await anon_client.get(f"/v1/public/splits/{token}/photo")).status_code == 404
