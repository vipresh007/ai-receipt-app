import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.api.deps import get_current_user, get_extractor
from app.db import get_session
from app.main import app
from app.models import Base, User
from app.schemas.extraction import ExtractedReceipt


class FakeExtractor:
    """Stand-in for AzureOpenAIExtractor — no network."""

    def extract(self, *, image_bytes: bytes, ocr_lines: list[str], media_type: str = "image/jpeg"):
        return ExtractedReceipt(
            merchant="Blue Bottle Coffee",
            purchased_at="2026-09-01",
            total="12.50",
            tax="1.03",
            category="restaurants",
            currency="USD",
            line_items=[],
            confidence=0.94,
        )


@pytest_asyncio.fixture
async def sessionmaker_():
    engine = create_async_engine(
        "sqlite+aiosqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield async_sessionmaker(engine, expire_on_commit=False)
    await engine.dispose()


@pytest_asyncio.fixture
async def test_user(sessionmaker_) -> User:
    async with sessionmaker_() as session:
        user = User(email="t@example.com", hashed_password="x", display_name="T")
        session.add(user)
        await session.commit()
        await session.refresh(user)
        return user


@pytest_asyncio.fixture
async def client(sessionmaker_, test_user):
    async def _get_session():
        async with sessionmaker_() as session:
            yield session

    app.dependency_overrides[get_session] = _get_session
    app.dependency_overrides[get_current_user] = lambda: test_user
    app.dependency_overrides[get_extractor] = FakeExtractor

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c

    app.dependency_overrides.clear()
