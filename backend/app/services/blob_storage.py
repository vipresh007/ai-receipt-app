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
