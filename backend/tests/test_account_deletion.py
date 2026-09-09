from sqlalchemy import select

from app.models import Expense, Receipt, User


def _receipt(merchant: str):
    return {
        "merchant": merchant,
        "date": "2026-09-03",
        "total": "9.99",
        "tax": "0",
        "category": "groceries",
    }


async def test_delete_me_requires_auth(anon_client):
    resp = await anon_client.delete("/v1/auth/me")
    assert resp.status_code in (401, 403)


async def test_delete_me_wipes_the_account(client, sessionmaker_, test_user):
    await client.post("/v1/receipts", json=_receipt("Store A"))
    await client.post("/v1/receipts", json=_receipt("Store B"))
    assert len((await client.get("/v1/receipts")).json()) == 2
    assert len((await client.get("/v1/expenses")).json()) == 2

    resp = await client.delete("/v1/auth/me")
    assert resp.status_code == 204

    # nothing left that belongs to the user
    assert (await client.get("/v1/receipts")).json() == []
    assert (await client.get("/v1/expenses")).json() == []

    async with sessionmaker_() as session:
        assert await session.scalar(select(User).where(User.id == test_user.id)) is None
        assert (
            await session.scalar(select(Receipt).where(Receipt.user_id == test_user.id))
        ) is None
        assert (
            await session.scalar(select(Expense).where(Expense.user_id == test_user.id))
        ) is None
