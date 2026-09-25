"""Orchestration: image → (blob) → Azure OpenAI → persisted Receipt + Expense."""

import asyncio
import logging
from datetime import date, datetime
from decimal import Decimal, InvalidOperation

from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool

from app.config import Settings, get_settings
from app.models import Expense, Receipt, User
from app.schemas.extraction import ExtractedReceipt
from app.schemas.receipt import ExtractionItemOut, ExtractionOut
from app.services.azure_openai import AzureOpenAIExtractor, ExtractionError
from app.services.blob_storage import BlobStorage

logger = logging.getLogger(__name__)

__all__ = ["ExtractionError", "process_receipt", "receipt_to_extraction_out"]


def _to_decimal(value: str | None) -> Decimal:
    if not value:
        return Decimal("0")
    try:
        return Decimal(value.replace(",", "").strip())
    except (InvalidOperation, AttributeError):
        return Decimal("0")


def _parse_date(value: str | None) -> date | None:
    if not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError:
        return None


async def process_receipt(
    *,
    session: AsyncSession,
    user: User,
    image_bytes: bytes,
    ocr_lines: list[str],
    request_id: str,
    extractor: AzureOpenAIExtractor,
    blob: BlobStorage | None = None,
    settings: Settings | None = None,
) -> Receipt:
    settings = settings or get_settings()

    async def upload() -> str | None:
        if not settings.blob_configured:
            return None
        try:
            store = blob or BlobStorage(settings)
            return await store.upload_receipt_image(
                user_id=user.id, request_id=request_id, data=image_bytes
            )
        except Exception:  # noqa: BLE001 - image storage is best-effort
            logger.warning("Receipt image upload failed", exc_info=True)
            return None

    # The image upload and the model call don't depend on each other, so run
    # them together; the SDK call is blocking, so it goes to a worker thread.
    upload_task = asyncio.create_task(upload())
    try:
        extracted: ExtractedReceipt = await run_in_threadpool(
            extractor.extract, image_bytes=image_bytes, ocr_lines=ocr_lines
        )
    finally:
        blob_url = await upload_task

    receipt = Receipt(
        user_id=user.id,
        merchant=extracted.merchant,
        purchased_at=_parse_date(extracted.purchased_at),
        total=_to_decimal(extracted.total),
        tax=_to_decimal(extracted.tax),
        currency=(extracted.currency or "USD")[:3].upper(),
        category_slug=extracted.category or "other",
        image_blob_url=blob_url,
        raw_ocr="\n".join(ocr_lines) or None,
        extraction_confidence=extracted.confidence,
        line_items=[item.model_dump() for item in extracted.line_items],
    )
    session.add(receipt)
    await session.flush()

    expense = Expense(
        user_id=user.id,
        receipt_id=receipt.id,
        merchant=receipt.merchant or "Unknown",
        amount=receipt.total,
        category_slug=receipt.category_slug,
        spent_at=receipt.purchased_at or date.today(),
        note="",
    )
    session.add(expense)
    await session.commit()
    await session.refresh(receipt)
    return receipt


def receipt_to_extraction_out(receipt: Receipt) -> ExtractionOut:
    return ExtractionOut(
        id=str(receipt.id),
        merchant=receipt.merchant,
        date=receipt.purchased_at.isoformat() if receipt.purchased_at else None,
        total=f"{receipt.total:.2f}",
        tax=f"{receipt.tax:.2f}",
        category=receipt.category_slug,
        items=[ExtractionItemOut(**item) for item in (receipt.line_items or [])],
        confidence=receipt.extraction_confidence,
    )
