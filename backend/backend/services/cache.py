"""
CacheService — SQLite-backed wine record cache with FS image store.
Stub for T1; full implementation in T4.

Cache key formula (D11):
  sha256(lower(producer or name) + ":" + lower(name) + ":" + (vintage or "nv"))
  where "producer or name" means: use name if producer is None or empty string.
"""

from backend.db.models import WineCacheRecord
from backend.models.wine import WineObject


async def lookup(wine_id: str) -> WineCacheRecord | None:
    """Return cached record if it exists, else None."""
    # Stub — T4 implements SQLAlchemy async lookup
    return None


async def write(
    wine: WineObject,
    image_path: str | None,
    tasting_note: str | None,
    pairings: list[str],
) -> None:
    """Persist wine record + image path + notes to SQLite cache."""
    # Stub — T4 implements SQLAlchemy async write
    pass


async def delete(wine_id: str) -> bool:
    """Delete a cache record. Returns True if it existed."""
    # Stub — T4 implements SQLAlchemy async delete
    return False
