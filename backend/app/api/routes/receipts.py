import base64
import binascii

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_extractor
from app.db import get_session
from app.models import Receipt, User
from app.schemas.receipt import ExtractionIn, ExtractionItemOut, ExtractionOut, ReceiptOut
from app.services.azure_openai import AzureOpenAIExtractor, ExtractionError
from app.services.extraction import process_receipt, receipt_to_extraction_out

router = APIRouter()


@router.post("/extract", response_model=ExtractionOut)
async def extract(
    payload: ExtractionIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    extractor: AzureOpenAIExtractor = Depends(get_extractor),
) -> ExtractionOut:
    try:
        image_bytes = base64.b64decode(payload.image_base64, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Invalid image data.") from exc
    if not image_bytes:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Empty image.")

    # TODO: enforce the monthly free-scan limit for user.plan == "free" here.

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
    return [
        ReceiptOut(
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
        for r in rows
    ]
