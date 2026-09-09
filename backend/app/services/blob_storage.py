import logging
from uuid import UUID

from azure.storage.blob.aio import BlobServiceClient

from app.config import Settings, get_settings

logger = logging.getLogger(__name__)


class BlobStorage:
    def __init__(self, settings: Settings | None = None) -> None:
        self.settings = settings or get_settings()

    async def upload_receipt_image(
        self,
        *,
        user_id: UUID,
        request_id: str,
        data: bytes,
        content_type: str = "image/jpeg",
    ) -> str:
        if not self.settings.blob_configured:
            raise RuntimeError("Blob storage is not configured.")

        blob_name = f"{user_id}/{request_id}.jpg"
        async with BlobServiceClient.from_connection_string(
            self.settings.azure_storage_connection_string
        ) as service:
            container = service.get_container_client(self.settings.azure_storage_container)
            blob = container.get_blob_client(blob_name)
            await blob.upload_blob(data, overwrite=True, content_type=content_type)
            return blob.url

    def _blob_name(self, blob_url: str) -> str | None:
        marker = f"/{self.settings.azure_storage_container}/"
        idx = blob_url.find(marker)
        if idx == -1:
            return None
        return blob_url[idx + len(marker) :].split("?", 1)[0]

    async def delete_by_url(self, blob_url: str) -> None:
        """Best-effort delete of a stored receipt image (used on account deletion)."""
        name = self._blob_name(blob_url)
        if not name or not self.settings.blob_configured:
            return
        try:
            async with BlobServiceClient.from_connection_string(
                self.settings.azure_storage_connection_string
            ) as service:
                container = service.get_container_client(self.settings.azure_storage_container)
                await container.get_blob_client(name).delete_blob(delete_snapshots="include")
        except Exception:  # noqa: BLE001 - best effort
            logger.warning("Receipt image delete failed", exc_info=True)

    async def download_by_url(self, blob_url: str) -> bytes | None:
        """Fetch bytes for a blob previously stored by ``upload_receipt_image``.

        Takes the URL we persisted on the receipt; returns ``None`` if the blob
        can't be located or read (deleted, wrong container, misconfigured)."""
        blob_name = self._blob_name(blob_url)
        if not blob_name or not self.settings.blob_configured:
            return None
        try:
            async with BlobServiceClient.from_connection_string(
                self.settings.azure_storage_connection_string
            ) as service:
                container = service.get_container_client(self.settings.azure_storage_container)
                stream = await container.get_blob_client(blob_name).download_blob()
                return await stream.readall()
        except Exception:  # noqa: BLE001 - treat any failure as "no image"
            logger.warning("Receipt image download failed", exc_info=True)
            return None
