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

    # Set for signed-in callers (a Receipt row was created); null for anonymous.
    id: str | None = None
    merchant: str
    date: str | None = None  # YYYY-MM-DD
    total: str
    tax: str
    category: str
    items: list[ExtractionItemOut] = Field(default_factory=list)
    confidence: float | None = None
    # Anonymous calls only: free scans left for this device. null when signed in.
    scans_remaining: int | None = None


class ReceiptUpdate(BaseModel):
    """PATCH /v1/receipts/{id} — every field optional; only those sent change."""

    model_config = ConfigDict(populate_by_name=True)

    merchant: str | None = None
    date: str | None = None  # YYYY-MM-DD
    total: str | None = None
    tax: str | None = None
    category: str | None = None
    items: list[ExtractionItemOut] | None = None


class ReceiptCreate(BaseModel):
    """Body for `POST /v1/receipts` and each item of `POST /v1/receipts/import`
    — a confirmed receipt from a client (anonymous-device migration or a manual
    add). Camel-case `imageBase64` is accepted for the iOS client."""

    model_config = ConfigDict(populate_by_name=True)

    merchant: str = ""
    date: str | None = None  # YYYY-MM-DD
    total: str = "0"
    tax: str = "0"
    category: str = "other"
    currency: str = "USD"
    items: list[ExtractionItemOut] = Field(default_factory=list)
    image_base64: str | None = Field(default=None, alias="imageBase64")
    confidence: float | None = None
    note: str = ""


class ImportIn(BaseModel):
    receipts: list[ReceiptCreate]


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


class RecurringGroupOut(BaseModel):
    """A merchant that looks like a recurring charge — appears in at least two
    different months at roughly the same amount. Heuristic, not a bank feed."""

    merchant: str
    category_slug: str
    average_amount: str
    occurrences: int
    last_purchased_at: date
    receipt_ids: list[UUID]
