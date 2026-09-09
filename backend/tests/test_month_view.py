"""Viewing spending for a month other than the current one."""


def _receipt(month_day: str, total: str, category: str = "groceries"):
    return {
        "merchant": "Shop",
        "date": f"2026-{month_day}",
        "total": total,
        "tax": "0",
        "category": category,
    }


async def _seed(client):
    # three months of history
    await client.post("/v1/receipts", json=_receipt("07-04", "40.00", "groceries"))
    await client.post("/v1/receipts", json=_receipt("08-10", "70.00", "restaurants"))
    await client.post("/v1/receipts", json=_receipt("08-20", "30.00", "groceries"))
    await client.post("/v1/receipts", json=_receipt("09-02", "12.00", "transport"))


async def test_summary_defaults_to_requested_month(client):
    await _seed(client)

    aug = (await client.get("/v1/expenses/summary?month=2026-08")).json()
    assert aug["month"] == "2026-08"
    assert aug["total"] == "100.00"
    assert aug["previous_month_total"] == "40.00"  # July
    assert {c["category_slug"] for c in aug["by_category"]} == {"restaurants", "groceries"}
    assert aug["earliest_month"] == "2026-07"

    jul = (await client.get("/v1/expenses/summary?month=2026-07")).json()
    assert jul["total"] == "40.00"
    assert jul["previous_month_total"] == "0.00"


async def test_bad_month_param_falls_back_to_current(client):
    await _seed(client)
    resp = await client.get("/v1/expenses/summary?month=not-a-month")
    assert resp.status_code == 200


async def test_trend_returns_zero_filled_months_oldest_first(client):
    await _seed(client)

    trend = (await client.get("/v1/expenses/trend?months=4")).json()
    assert [p["month"] for p in trend] == sorted(p["month"] for p in trend)  # oldest first
    assert len(trend) == 4
    by_month = {p["month"]: p["total"] for p in trend}
    assert by_month.get("2026-07") == "40.00"
    assert by_month.get("2026-08") == "100.00"
    # a month with no data in the window is present and zero
    assert all(p["total"] == f"{float(p['total']):.2f}" for p in trend)


async def test_receipts_can_be_filtered_by_month(client):
    await _seed(client)

    aug = (await client.get("/v1/receipts?month=2026-08")).json()
    assert len(aug) == 2
    assert all(r["purchased_at"].startswith("2026-08") for r in aug)

    assert (await client.get("/v1/receipts?month=2026-01")).json() == []
    assert len((await client.get("/v1/receipts")).json()) == 4  # unfiltered
