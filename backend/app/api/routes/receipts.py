import base64
import binascii
from datetime import UTC, date, datetime, timedelta
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from sqlalchemy import Text, cast, or_, select
from sqlalchemy import delete as sa_delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_current_user_optional, get_extractor
from app.config import get_settings
from app.date_ranges import month_bounds, month_start
from app.db import get_session
from app.models import AnonDevice, AnonRateLimit, Expense, Receipt, User
from app.schemas.extraction import ExtractedReceipt
from app.schemas.receipt import (
    ExtractionIn,
    ExtractionItemOut,
    ExtractionOut,
    ImportIn,
    ReceiptCreate,
    ReceiptOut,
    ReceiptUpdate,
    RecurringGroupOut,
)
from app.services.azure_openai import AzureOpenAIExtractor, ExtractionError
from app.services.blob_storage import BlobStorage
from app.services.extraction import (
    _parse_date,
    _to_decimal,
    process_receipt,
    receipt_to_extraction_out,
)
from app.services.recurring import find_recurring

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


def _client_ip(request: Request) -> str:
    """Best-effort caller IP. Container Apps' ingress sets X-Forwarded-For; the
    left-most entry is the original client."""
    forwarded = request.headers.get("x-forwarded-for", "")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


async def _enforce_anon_ip_limit(session: AsyncSession, ip: str) -> None:
    """Fixed-window (1h) per-IP cap on anonymous extraction. Raises 429 when hit."""
    limit = get_settings().anon_ip_hourly_limit
    now = datetime.now(UTC)
    bucket = f"{ip}:{now:%Y%m%d%H}"
    row = await session.scalar(select(AnonRateLimit).where(AnonRateLimit.bucket == bucket))
    if row is None:
        # opportunistic prune of stale buckets (keeps the table tiny)
        await session.execute(
            sa_delete(AnonRateLimit).where(AnonRateLimit.created_at < now - timedelta(hours=2))
        )
        row = AnonRateLimit(bucket=bucket, count=0)
        session.add(row)
    if row.count >= limit:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Too many scans from this network right now. Try again later or sign in.",
        )
    row.count += 1
    await session.commit()


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
        await _enforce_anon_ip_limit(session, _client_ip(request))
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


async def _persist_receipt(
    session: AsyncSession, user: User, item: ReceiptCreate, blob: BlobStorage | None
) -> Receipt:
    """Create a Receipt + its linked Expense from a confirmed client payload."""
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
        extraction_confidence=item.confidence,
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
            note=item.note[:500],
        )
    )
    return receipt


async def _owned_receipt(session: AsyncSession, user: User, receipt_id: UUID) -> Receipt:
    receipt = await session.get(Receipt, receipt_id)
    if receipt is None or receipt.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Receipt not found.")
    return receipt


@router.post("/receipts", response_model=ReceiptOut, status_code=status.HTTP_201_CREATED)
async def create_receipt(
    payload: ReceiptCreate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ReceiptOut:
    settings = get_settings()
    blob = BlobStorage(settings) if settings.blob_configured else None
    receipt = await _persist_receipt(session, user, payload, blob)
    await session.commit()
    await session.refresh(receipt)
    return _receipt_out(receipt)


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

    created = [await _persist_receipt(session, user, item, blob) for item in payload.receipts]
    await session.commit()
    for receipt in created:
        await session.refresh(receipt)
    return [_receipt_out(r) for r in created]


@router.get("/receipts", response_model=list[ReceiptOut])
async def list_receipts(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    limit: int = 50,
    month: str | None = None,
    q: str | None = None,
    category: str | None = None,
    min_amount: str | None = None,
    max_amount: str | None = None,
) -> list[ReceiptOut]:
    """Newest first. `month` (YYYY-MM) filters by purchase date; `q` searches
    the merchant name and line-item names (case-insensitive substring);
    `category` filters by slug; `min_amount`/`max_amount` bound the total
    (decimal strings)."""
    query = select(Receipt).where(Receipt.user_id == user.id)
    if month:
        start, end = month_bounds(month_start(month))
        query = query.where(Receipt.purchased_at >= start, Receipt.purchased_at < end)
    if q:
        # line_items is JSON ({"name": ..., ...} per item) — casting to text and
        # substring-matching works the same way on SQLite (tests) and Postgres
        # (prod) without relying on either dialect's native JSON operators.
        query = query.where(
            or_(
                Receipt.merchant.ilike(f"%{q}%"),
                cast(Receipt.line_items, Text).ilike(f"%{q}%"),
            )
        )
    if category:
        query = query.where(Receipt.category_slug == category)
    if min_amount:
        query = query.where(Receipt.total >= _to_decimal(min_amount))
    if max_amount:
        query = query.where(Receipt.total <= _to_decimal(max_amount))
    rows = await session.scalars(query.order_by(Receipt.created_at.desc()).limit(min(limit, 200)))
    return [_receipt_out(r) for r in rows]


@router.get("/receipts/recurring", response_model=list[RecurringGroupOut])
async def list_recurring(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[RecurringGroupOut]:
    """Merchants that look like a recurring charge — see `services/recurring.py`
    for the heuristic. Most recently charged first."""
    receipts = list(await session.scalars(select(Receipt).where(Receipt.user_id == user.id)))
    return [
        RecurringGroupOut(
            merchant=g.merchant,
            category_slug=g.category_slug,
            average_amount=f"{g.average_amount:.2f}",
            occurrences=g.occurrences,
            last_purchased_at=g.last_purchased_at,
            receipt_ids=g.receipt_ids,
        )
        for g in find_recurring(receipts)
    ]


@router.get("/receipts/{receipt_id}", response_model=ReceiptOut)
async def get_receipt(
    receipt_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ReceiptOut:
    receipt = await _owned_receipt(session, user, receipt_id)
    return _receipt_out(receipt)


@router.get("/receipts/{receipt_id}/image")
async def receipt_image(
    receipt_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    """Stream a receipt's stored image so other devices can show it after a
    pull (the bytes never live in SwiftData across devices)."""
    receipt = await _owned_receipt(session, user, receipt_id)
    settings = get_settings()
    if not receipt.image_blob_url or not settings.blob_configured:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No image for this receipt.")
    data = await BlobStorage(settings).download_by_url(receipt.image_blob_url)
    if data is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No image for this receipt.")
    return Response(
        content=data,
        media_type="image/jpeg",
        headers={"Cache-Control": "private, max-age=86400"},
    )


@router.patch("/receipts/{receipt_id}", response_model=ReceiptOut)
async def update_receipt(
    receipt_id: UUID,
    payload: ReceiptUpdate,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ReceiptOut:
    receipt = await _owned_receipt(session, user, receipt_id)
    fields = payload.model_dump(exclude_unset=True)

    if "merchant" in fields:
        receipt.merchant = fields["merchant"] or ""
    if "date" in fields:
        receipt.purchased_at = _parse_date(fields["date"])
    if "total" in fields:
        receipt.total = _to_decimal(fields["total"])
    if "tax" in fields:
        receipt.tax = _to_decimal(fields["tax"])
    if "category" in fields:
        receipt.category_slug = fields["category"] or "other"
    if "items" in fields:
        receipt.line_items = [li.model_dump() for li in (payload.items or [])]

    expense = await session.scalar(select(Expense).where(Expense.receipt_id == receipt.id))
    if expense is not None:
        expense.merchant = receipt.merchant or "Unknown"
        expense.amount = receipt.total
        expense.category_slug = receipt.category_slug
        expense.spent_at = receipt.purchased_at or expense.spent_at

    await session.commit()
    await session.refresh(receipt)
    return _receipt_out(receipt)


@router.delete("/receipts/{receipt_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_receipt(
    receipt_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    receipt = await _owned_receipt(session, user, receipt_id)
    for expense in await session.scalars(select(Expense).where(Expense.receipt_id == receipt.id)):
        await session.delete(expense)
    await session.delete(receipt)
    await session.commit()


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
