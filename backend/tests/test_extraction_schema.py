import pytest
from pydantic import ValidationError

from app.schemas.extraction import ExtractedReceipt
from app.services.extraction import _parse_date, _to_decimal


def test_defaults_are_safe():
    r = ExtractedReceipt()
    assert r.merchant == ""
    assert r.total == "0"
    assert r.tax == "0"
    assert r.category == "other"


def test_rejects_unknown_category():
    with pytest.raises(ValidationError):
        ExtractedReceipt(category="snacks")


def test_rejects_extra_fields():
    with pytest.raises(ValidationError):
        ExtractedReceipt(surprise="nope")


def test_to_decimal_handles_junk():
    from decimal import Decimal

    assert _to_decimal("12.50") == Decimal("12.50")
    assert _to_decimal("1,299.00") == Decimal("1299.00")
    assert _to_decimal("") == Decimal("0")
    assert _to_decimal("abc") == Decimal("0")
    assert _to_decimal(None) == Decimal("0")


def test_parse_date():
    from datetime import date

    assert _parse_date("2026-09-01") == date(2026, 9, 1)
    assert _parse_date("not-a-date") is None
    assert _parse_date(None) is None
