import uuid
from decimal import Decimal as D

import pytest

from app.services.splits import (
    ShareInput,
    SplitError,
    SplitLedger,
    balances,
    compute_shares,
    settle_up,
)


def test_even_split_hands_out_leftover_cents_and_adds_up():
    shares = compute_shares(D("100.00"), "even", [ShareInput()] * 3, [])
    assert shares == [D("33.34"), D("33.33"), D("33.33")]
    assert sum(shares) == D("100.00")


def test_items_split_shares_tax_in_proportion():
    # Pasta 20 (A), salad 10 (B), bread 6 (both); total 39.60 incl. 3.60 tax.
    items = [D("20.00"), D("10.00"), D("6.00")]
    inputs = [ShareInput(item_indexes=[0, 2]), ShareInput(item_indexes=[1, 2])]
    a, b = compute_shares(D("39.60"), "items", inputs, items)
    # Subtotals 23 and 13 of 36; tax 3.60 → 2.30 and 1.30.
    assert (a, b) == (D("25.30"), D("14.30"))
    assert a + b == D("39.60")


def test_unassigned_items_are_shared_by_everyone():
    items = [D("10.00"), D("6.00")]
    a, b = compute_shares(D("16.00"), "items", [ShareInput([0]), ShareInput([])], items)
    assert (a, b) == (D("13.00"), D("3.00"))


def test_discount_reduces_shares_proportionally():
    items = [D("30.00"), D("10.00")]  # 40 of items, paid 36 after a coupon
    a, b = compute_shares(D("36.00"), "items", [ShareInput([0]), ShareInput([1])], items)
    assert (a, b) == (D("27.00"), D("9.00"))


def test_shares_divide_the_total_by_parts():
    # 2 parts for me, 3 for Zalak: 2/5 and 3/5 of 30.72.
    a, b = compute_shares(
        D("30.72"), "shares", [ShareInput(weight=D("2")), ShareInput(weight=D("3"))], []
    )
    assert (a, b) == (D("12.29"), D("18.43"))
    assert a + b == D("30.72")
    # Blank counts as one part.
    assert compute_shares(D("9"), "shares", [ShareInput(), ShareInput(weight=D("2"))], []) == [
        D("3.00"),
        D("6.00"),
    ]
    with pytest.raises(SplitError):
        compute_shares(D("9"), "shares", [ShareInput(weight=D("0"))], [])


def test_custom_amounts_must_add_up():
    with pytest.raises(SplitError, match="add up to 50.00"):
        compute_shares(
            D("50.00"),
            "custom",
            [ShareInput(custom_amount=D("20")), ShareInput(custom_amount=D("20"))],
            [],
        )
    shares = compute_shares(
        D("50.00"),
        "custom",
        [ShareInput(custom_amount=D("30")), ShareInput(custom_amount=D("20"))],
        [],
    )
    assert shares == [D("30.00"), D("20.00")]


def test_item_index_out_of_range_is_rejected():
    with pytest.raises(SplitError):
        compute_shares(D("5"), "items", [ShareInput([3])], [D("5")])


def test_balances_and_settle_up():
    alex, sam, kim = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    # Alex paid 90 split three ways; Sam paid 30 split with Kim.
    ledger = [
        SplitLedger(alex, [(alex, D("30")), (sam, D("30")), (kim, D("30"))]),
        SplitLedger(sam, [(sam, D("15")), (kim, D("15"))]),
    ]
    net = balances(ledger, [])
    assert net == {alex: D("60.00"), sam: D("-15.00"), kim: D("-45.00")}
    payments = settle_up(net)
    assert payments == [(kim, alex, D("45.00")), (sam, alex, D("15.00"))]

    # Kim pays Alex 45: Kim is square.
    net = balances(ledger, [(kim, alex, D("45"))])
    assert net[kim] == D("0.00")
    assert settle_up(net) == [(sam, alex, D("15.00"))]
