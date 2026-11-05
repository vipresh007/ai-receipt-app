"""Tidying receipt lines (services/items.py)."""

from app.services.items import tidy


def test_codes_go_and_weights_or_counts_become_the_detail():
    assert tidy("Bananas 4011 1.035 kg @ $1.91/kg") == ("Bananas", "1.035 kg @ $1.91/kg")
    assert tidy("Cilantro 4889 2 @ 1/ $0.99") == ("Cilantro", "2 @ 1/ $0.99")
    assert tidy("Milk Homo 6442000020") == ("Milk Homo", None)
    assert tidy("Wilderness Mix 77138622518") == ("Wilderness Mix", None)


def test_ordinary_names_are_left_alone():
    assert tidy("Coffee beans 340g") == ("Coffee beans 340g", None)
    assert tidy("Oat milk 1L") == ("Oat milk 1L", None)
    assert tidy("Greek yogurt 750g") == ("Greek yogurt 750g", None)
    assert tidy("Pad See Ew") == ("Pad See Ew", None)
    assert tidy("4011") == ("4011", None)  # nothing else to call it


async def test_saved_items_come_back_tidy(client):
    r = await client.post(
        "/v1/receipts",
        json={
            "merchant": "FreshCo",
            "total": "1.98",
            "items": [{"name": "Bananas 4011 1.035 kg @ $1.91/kg", "price": "1.98"}],
        },
    )
    (item,) = r.json()["line_items"]
    assert item["name"] == "Bananas" and item["detail"] == "1.035 kg @ $1.91/kg"
