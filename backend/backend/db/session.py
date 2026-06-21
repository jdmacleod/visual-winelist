from collections.abc import AsyncIterator

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from backend import config
from backend.db.models import Base

engine = create_async_engine(config.DATABASE_URL, echo=False)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)

_INDEX_DDL = [
    "CREATE INDEX IF NOT EXISTS idx_wine_name ON wine_cache (name)",
    "CREATE INDEX IF NOT EXISTS idx_wine_producer ON wine_cache (producer)",
    "CREATE INDEX IF NOT EXISTS idx_wine_appellation ON wine_cache (appellation)",
    "CREATE INDEX IF NOT EXISTS idx_wine_verified ON wine_cache (verified)",
    "CREATE INDEX IF NOT EXISTS idx_wine_created_at ON wine_cache (created_at)",
]


async def init_db() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        for ddl in _INDEX_DDL:
            await conn.execute(text(ddl))


async def get_db() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session
