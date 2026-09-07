"""Spending insights.

`generate_rule_based` is deterministic month-over-month analysis — the same
logic the iOS dashboard shows, computed server-side so it can be stored and
served. An Azure OpenAI pass for richer, natural-language insights can layer on
top later (`generated_by="azure_openai"`).
"""

from collections import defaultdict
from collections.abc import Sequence
from datetime import date
from decimal import Decimal

from app.models import Expense, Insight

_THRESHOLD = Decimal("0.15")  # 15% month-over-month change to be worth mentioning


def _month_bounds(anchor: date) -> tuple[date, date]:
    start = anchor.replace(day=1)
    end = (
        start.replace(year=start.year + 1, month=1)
        if start.month == 12
        else start.replace(month=start.month + 1)
    )
    return start, end


def _totals_by_category(expenses: Sequence[Expense], start: date, end: date) -> dict[str, Decimal]:
    totals: dict[str, Decimal] = defaultdict(lambda: Decimal("0"))
    for e in expenses:
        if start <= e.spent_at < end:
            totals[e.category_slug] += Decimal(e.amount)
    return dict(totals)


def generate_rule_based(
    *, user_id, expenses: Sequence[Expense], today: date | None = None
) -> list[Insight]:
    today = today or date.today()
    this_start, this_end = _month_bounds(today)
    prev_start, _ = _month_bounds(this_start.replace(day=1) - date.resolution)
    prev_end = this_start

    current = _totals_by_category(expenses, this_start, this_end)
    previous = _totals_by_category(expenses, prev_start, prev_end)

    insights: list[Insight] = []
    for slug, amount in sorted(current.items(), key=lambda kv: kv[1], reverse=True):
        prior = previous.get(slug)
        if not prior or prior <= 0:
            continue
        change = (amount - prior) / prior
        if abs(change) < _THRESHOLD:
            continue
        pct = int(abs(change) * 100)
        direction = "more" if change > 0 else "less"
        insights.append(
            Insight(
                user_id=user_id,
                kind="up" if change > 0 else "down",
                message=f"You spent {pct}% {direction} on {slug} this month.",
                period_start=this_start,
                period_end=this_end,
                generated_by="rules",
            )
        )
        if len(insights) >= 3:
            break
    return insights
