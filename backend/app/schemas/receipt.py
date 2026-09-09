from datetime import date
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ExtractionIn(BaseModel):
    """Request body for POST /v1/extract — matches the iOS client's JSON
    (camelCase keys)."""

    model_config = ConfigDict(populate_by_name=True)

    image_base64: str = Field(alias="imageBase64")
    ocr_lines: list[str] = Field(default_factory=list, alias="ocrLines")
    client_request_id: str = Field(alias="clientRequestID")


class ExtractionItemOut(BaseModel):
    name: str
    price: str  # decimal string
    quantity: int = 1


class ExtractionOut(BaseModel):
    """Response body for POST /v1/extract — matches what the iOS
    `ReceiptExtractionAPIClient` decodes."""

    merchant: str
    date: str | None = None  # YYYY-MM-DD
    total: str
    tax: str
    category: str
    items: list[ExtractionItemOut] = Field(default_factory=list)
    confidence: float | None = None
    # Anonymous calls only: free scans left for this device. null when signed in.
    scans_remaining: int | None = None


class ImportItem(BaseModel):
    """One receipt migrated from an anonymous iOS device on sign-in."""

    model_config = ConfigDict(populate_by_name=True)

    merchant: str = ""
    date: str | None = None  # YYYY-MM-DD
    total: str = "0"
    tax: str = "0"
    category: str = "other"
    currency: str = "USD"
    items: list[ExtractionItemOut] = Field(default_factory=list)
    image_base64: str | None = Field(default=None, alias="imageBase64")


class ImportIn(BaseModel):
    receipts: list[ImportItem]


class ReceiptOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    merchant: str
    purchased_at: date | None
    total: str
    tax: str
    currency: str
    category_slug: str
    image_blob_url: str | None
    extraction_confidence: float | None
    line_items: list[ExtractionItemOut]
