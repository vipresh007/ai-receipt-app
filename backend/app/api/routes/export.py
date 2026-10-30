"""CSV export of your receipts and shared expenses."""

import csv
import io
from datetime import date

from fastapi import APIRouter, Depends
from fastapi.responses import Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db import get_session
from app.models import Group, Receipt, Split, SplitParticipant, User

router = APIRouter()


def _csv(name: str, header: list[str], rows: list[list[object]]) -> Response:
    out = io.StringIO()
    writer = csv.writer(out)
    writer.writerow(header)
    for row in rows:
        # Keep spreadsheet apps from running cell text as a formula.
        writer.writerow(
            [f"'{v}" if isinstance(v, str) and v[:1] in ("=", "+", "-", "@") else v for v in row]
        )
    filename = f"tally-{name}-{date.today().isoformat()}.csv"
    return Response(
        out.getvalue(),
        media_type="text/csv; charset=utf-8",
        headers={"content-disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/receipts.csv")
async def receipts_csv(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    receipts = await session.scalars(
        select(Receipt)
        .where(Receipt.user_id == user.id)
        .order_by(Receipt.purchased_at.desc(), Receipt.created_at.desc())
    )
    return _csv(
        "receipts",
        ["Date", "Merchant", "Category", "Total", "Tax", "Your share", "Currency"],
        [
            [
                r.purchased_at.isoformat() if r.purchased_at else "",
                r.merchant,
                r.category_slug,
                f"{r.total:.2f}",
                f"{r.tax:.2f}",
                f"{(r.my_share if r.my_share is not None else r.total):.2f}",
                r.currency,
            ]
            for r in receipts
        ],
    )


@router.get("/shared.csv")
async def shared_csv(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    """Every expense you're on: who paid, everyone's share, yours."""
    mine = select(SplitParticipant.split_id).where(SplitParticipant.user_id == user.id)
    splits = list(
        await session.scalars(
            select(Split)
            .where((Split.owner_user_id == user.id) | Split.id.in_(mine))
            .order_by(Split.spent_at.desc(), Split.created_at.desc())
        )
    )
    groups = {g.id: g.name for g in await session.scalars(select(Group))} if splits else {}
    rows: list[list[object]] = []
    for split in splits:
        people = list(
            await session.scalars(
                select(SplitParticipant)
                .where(SplitParticipant.split_id == split.id)
                .order_by(SplitParticipant.position)
            )
        )
        me = next((p for p in people if p.user_id == user.id), None)
        payers = ", ".join(p.display_name for p in people if p.is_payer)
        shares = "; ".join(f"{p.display_name} {p.share:.2f}" for p in people)
        rows.append(
            [
                split.spent_at.isoformat(),
                split.description,
                groups.get(split.group_id, "") if split.group_id else "",
                f"{split.total:.2f}",
                split.currency,
                payers,
                f"{me.share:.2f}" if me else "",
                shares,
            ]
        )
    return _csv(
        "shared",
        ["Date", "Description", "Group", "Total", "Currency", "Paid by", "Your share", "Shares"],
        rows,
    )
