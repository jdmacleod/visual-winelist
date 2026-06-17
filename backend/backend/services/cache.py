"""
CacheService — SQLite-backed wine record cache with filesystem image store.

Cache key formula (D11):
  sha256(lower(producer or name) + ":" + lower(name) + ":" + (vintage or "nv"))
  Computed by WineObject.wine_id — see backend/models/wine.py.

write() is an upsert keyed on wine_id:
  - Creates a new record on first write.
  - On subsequent writes, updates only non-None / non-empty fields so Phase 1
    (image) and Phase 2 (sommelier notes) can each call write() independently.
"""

from datetime import UTC, datetime

from backend.db import session as db_session
from backend.db.models import WineCacheRecord
from backend.models.wine import WineObject


async def lookup(wine_id: str) -> WineCacheRecord | None:
    """Return cached record if it exists, else None."""
    async with db_session.SessionLocal() as session:
        return await session.get(WineCacheRecord, wine_id)


async def write(
    wine: WineObject,
    image_path: str | None,
    tasting_note: str | None,
    pairings: list[str],
) -> None:
    """
    Upsert a wine record.

    - image_path: stored when Brave finds an image; pass None to leave unchanged.
    - tasting_note: stored after Phase-2 sommelier call; pass None to leave unchanged.
    - pairings: stored after Phase-2 sommelier call; pass [] to leave unchanged.
    """
    async with db_session.SessionLocal() as session:
        existing = await session.get(WineCacheRecord, wine.wine_id)
        if existing is None:
            record = WineCacheRecord(
                wine_id=wine.wine_id,
                name=wine.name,
                producer=wine.producer,
                vintage=wine.vintage,
                variety=wine.variety,
                appellation=wine.appellation,
                image_path=image_path,
                tasting_note=tasting_note,
            )
            record.pairings = pairings
            session.add(record)
        else:
            if image_path is not None:
                existing.image_path = image_path
            if tasting_note is not None:
                existing.tasting_note = tasting_note
            if pairings:
                existing.pairings = pairings
            existing.updated_at = datetime.now(UTC)
        await session.commit()


async def delete(wine_id: str) -> bool:
    """Delete a cache record. Returns True if it existed."""
    async with db_session.SessionLocal() as session:
        record = await session.get(WineCacheRecord, wine_id)
        if record is None:
            return False
        await session.delete(record)
        await session.commit()
        return True
