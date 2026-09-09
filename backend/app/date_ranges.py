"""Month-window helpers shared by the expenses + receipts routes."""

from datetime import date, datetime


def month_start(value: str | None) -> date:
    """First day of a ``YYYY-MM`` month, or of the current month when the string
    is missing or unparseable."""
    if value:
        try:
            return datetime.strptime(value, "%Y-%m").date().replace(day=1)
        except ValueError:
            pass
    return date.today().replace(day=1)


def month_bounds(anchor: date) -> tuple[date, date]:
    """``[first-of-month, first-of-next-month)`` for ``anchor``'s month."""
    start = anchor.replace(day=1)
    end = (
        start.replace(year=start.year + 1, month=1)
        if start.month == 12
        else start.replace(month=start.month + 1)
    )
    return start, end
