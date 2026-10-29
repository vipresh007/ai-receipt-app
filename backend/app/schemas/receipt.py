from datetime import date
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

# One OCR row; generous for long store names, short enough to bound the prompt.
OcrLine = Annotated[str, Field(max_length=500)]


class ExtractionIn(BaseModel):
    """Request body for POST /v1/extract — matches the iOS client's JSON
    (camelCase keys)."""

    model_config = ConfigDict(populate_by_name=True)

    # ~10 MB decoded. The app sends ~0.5 MB (2048 px JPEG).
    image_base64: str = Field(alias="imageBase64", max_length=14_000_000)
    ocr_lines: list[OcrLine] = Field(default_factory=list, alias="ocrLines", max_length=500)
    client_request_id: str = Field(alias="clientRequestID", max_length=100)


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

    merchant: str = Field(default="", max_length=300)
    date: str | None = None  # YYYY-MM-DD
    total: str = "0"
    tax: str = "0"
    category: str = "other"
    currency: str = "USD"
    items: list[ExtractionItemOut] = Field(default_factory=list, max_length=500)
    image_base64: str | None = Field(default=None, alias="imageBase64", max_length=14_000_000)
    confidence: float | None = None
    note: str = Field(default="", max_length=2000)


class ImportIn(BaseModel):
    receipts: list[ReceiptCreate] = Field(max_length=5000)


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
    # Set while the receipt is split: your share, which is what counts as spending.
    my_share: str | None = None
    split_id: UUID | None = None


class RecurringGroupOut(BaseModel):
    """A merchant that looks like a recurring charge — appears in at least two
    different months at roughly the same amount. Heuristic, not a bank feed."""

    merchant: str
    category_slug: str
    average_amount: str
    occurrences: int
    last_purchased_at: date
    receipt_ids: list[UUID]
