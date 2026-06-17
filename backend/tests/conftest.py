import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from backend.db import session as db_session
from backend.db.models import Base
from backend.main import app


@pytest.fixture(autouse=True)
async def use_test_db(tmp_path, monkeypatch):
    """
    Replace the module-level SessionLocal with one backed by a per-test temp
    SQLite file, then create all tables.  Runs for every test automatically.
    """
    db_url = f"sqlite+aiosqlite:///{tmp_path / 'test.db'}"
    engine = create_async_engine(db_url, echo=False)
    factory = async_sessionmaker(engine, expire_on_commit=False)

    monkeypatch.setattr(db_session, "engine", engine)
    monkeypatch.setattr(db_session, "SessionLocal", factory)

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    yield

    await engine.dispose()


@pytest.fixture
async def client():
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as c:
        yield c


def make_jpeg(size: int = 1024) -> bytes:
    """Return a minimal valid-looking JPEG payload of approximately `size` bytes."""
    header = bytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]) + b"JFIF\x00"
    return header + b"\x00" * max(0, size - len(header) - 2) + bytes([0xFF, 0xD9])
