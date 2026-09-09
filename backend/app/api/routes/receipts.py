import base64
import binascii
from datetime import date
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_current_user_optional, get_extractor
from app.config import get_settings
from app.db import get_session
from app.models import AnonDevice, Expense, Receipt, User
from app.schemas.extraction import ExtractedReceipt
from app.schemas.receipt import (
    ExtractionIn,
    ExtractionItemOut,
    ExtractionOut,
    ImportIn,
    ReceiptOut,
)
from app.services.azure_openai import AzureOpenAIExtractor, ExtractionError
from app.services.blob_storage import BlobStorage
from app.services.extraction import (
    _parse_date,
    _to_decimal,
    process_receipt,
    receipt_to_extraction_out,
)

router = APIRouter()

_PAYMENT_REQUIRED = 402


def _decode_image(image_base64: str) -> bytes:
    try:
        data = base64.b64decode(image_base64, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Invalid image data.") from exc
    if not data:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Empty image.")
    return data


def _extracted_to_out(ex: ExtractedReceipt) -> ExtractionOut:
    return ExtractionOut(
        merchant=ex.merchant,
        date=ex.purchased_at,
        total=ex.total,
        tax=ex.tax,
        category=ex.category,
        items=[
            ExtractionItemOut(name=li.name, price=li.price, quantity=li.quantity)
            for li in ex.line_items
        ],
        confidence=ex.confidence,
    )


async def _consume_anon_quota(session: AsyncSession, device_id: str) -> int:
    """Increment the device's counter; raise 402 when the free allowance is spent.
    Returns the number of scans left after this one."""
    limit = get_settings().anon_scan_limit
    device = await session.scalar(select(AnonDevice).where(AnonDevice.device_id == device_id))
    if device is None:
        device = AnonDevice(device_id=device_id, scan_count=0)
        session.add(device)
    if device.scan_count >= limit:
        raise HTTPException(
            _PAYMENT_REQUIRED,
            "You've used all your free scans. Sign in to keep scanning.",
        )
    device.scan_count += 1
    await session.commit()
    return max(0, limit - device.scan_count)


@router.post("/extract", response_model=ExtractionOut)
async def extract(
    payload: ExtractionIn,
    request: Request,
    user: User | None = Depends(get_current_user_optional),
    session: AsyncSession = Depends(get_session),
    extractor: AzureOpenAIExtractor = Depends(get_extractor),
) -> ExtractionOut:
    image_bytes = _decode_image(payload.image_base64)

    # ---- anonymous (local-first iOS): rate-limited, not persisted ----
    if user is None:
        device_id = (request.headers.get("x-device-id") or "").strip()
        if not device_id:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Missing X-Device-Id header.")
        remaining = await _consume_anon_quota(session, device_id)
        try:
            extracted = extractor.extract(image_bytes=image_bytes, ocr_lines=payload.ocr_lines)
        except ExtractionError as exc:
            raise HTTPException(status.HTTP_502_BAD_GATEWAY, str(exc)) from exc
        out = _extracted_to_out(extracted)
        out.scans_remaining = remaining
        return out

    # ---- signed in: persist Receipt + Expense as before ----
    # TODO: enforce a monthly free/pro scan limit for user.plan here.
    try:
        receipt = await process_receipt(
            session=session,
            user=user,
            image_bytes=image_bytes,
            ocr_lines=payload.ocr_lines,
            request_id=payload.client_request_id,
            extractor=extractor,
        )
    except ExtractionError as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, str(exc)) from exc
    return receipt_to_extraction_out(receipt)


@router.post(
    "/receipts/import", response_model=list[ReceiptOut], status_code=status.HTTP_201_CREATED
)
async def import_receipts(
    payload: ImportIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[ReceiptOut]:
    """Migrate a signed-out iOS device's local receipts into the account."""
    settings = get_settings()
    blob = BlobStorage(settings) if settings.blob_configured else None

    created: list[Receipt] = []
    for item in payload.receipts:
        blob_url: str | None = None
        if item.image_base64 and blob is not None:
            try:
                blob_url = await blob.upload_receipt_image(
                    user_id=user.id,
                    request_id=uuid4().hex,
                    data=base64.b64decode(item.image_base64),
                )
            except Exception:  # noqa: BLE001 - image is best-effort
                blob_url = None

        purchased = _parse_date(item.date)
        total = _to_decimal(item.total)
        receipt = Receipt(
            user_id=user.id,
            merchant=item.merchant,
            purchased_at=purchased,
            total=total,
            tax=_to_decimal(item.tax),
            currency=(item.currency or "USD")[:3].upper(),
            category_slug=item.category or "other",
            image_blob_url=blob_url,
            line_items=[li.model_dump() for li in item.items],
        )
        session.add(receipt)
        await session.flush()
        session.add(
            Expense(
                user_id=user.id,
                receipt_id=receipt.id,
                merchant=receipt.merchant or "Unknown",
                amount=total,
                category_slug=receipt.category_slug,
                spent_at=purchased or date.today(),
                note="",
            )
        )
        created.append(receipt)

    await session.commit()
    for receipt in created:
        await session.refresh(receipt)
    return [_receipt_out(r) for r in created]


@router.get("/receipts", response_model=list[ReceiptOut])
async def list_receipts(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    limit: int = 50,
) -> list[ReceiptOut]:
    rows = await session.scalars(
        select(Receipt)
        .where(Receipt.user_id == user.id)
        .order_by(Receipt.created_at.desc())
        .limit(min(limit, 200))
    )
    return [_receipt_out(r) for r in rows]


def _receipt_out(r: Receipt) -> ReceiptOut:
    return ReceiptOut(
        id=r.id,
        merchant=r.merchant,
        purchased_at=r.purchased_at,
        total=f"{r.total:.2f}",
        tax=f"{r.tax:.2f}",
        currency=r.currency,
        category_slug=r.category_slug,
        image_blob_url=r.image_blob_url,
        extraction_confidence=r.extraction_confidence,
        line_items=[ExtractionItemOut(**it) for it in (r.line_items or [])],
    )
