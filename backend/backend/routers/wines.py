import os

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy import func, or_, select

from backend.db import session as db_session
from backend.db.models import WineCacheRecord
from backend.models.wine import SearchResponse, WineRecord
from backend.services import cache

router = APIRouter()


@router.get("/wines/search", response_model=SearchResponse)
async def search_wines(q: str = "", page: int = 1, page_size: int = 20) -> SearchResponse:
    async with db_session.SessionLocal() as session:
        stmt = select(WineCacheRecord)
        if q:
            pattern = f"%{q}%"
            stmt = stmt.where(
                or_(
                    WineCacheRecord.name.ilike(pattern),
                    WineCacheRecord.producer.ilike(pattern),
                    WineCacheRecord.appellation.ilike(pattern),
                )
            )

        total: int = (
            await session.execute(select(func.count()).select_from(stmt.subquery()))
        ).scalar_one()

        rows = (
            (await session.execute(stmt.offset((page - 1) * page_size).limit(page_size)))
            .scalars()
            .all()
        )

    results = [
        WineRecord(
            wine_id=r.wine_id,
            name=r.name,
            producer=r.producer,
            vintage=r.vintage,
            variety=r.variety,
            appellation=r.appellation,
            tasting_note=r.tasting_note,
            pairings=r.pairings,
            verified=r.verified,
            image_url=f"/wines/{r.wine_id}/image" if r.image_path else None,
        )
        for r in rows
    ]
    return SearchResponse(results=results, total=total, page=page, page_size=page_size)


@router.get("/wines/{wine_id}/image")
async def get_wine_image(wine_id: str) -> FileResponse:
    record = await cache.lookup(wine_id)
    if record is None or record.image_path is None:
        raise HTTPException(status_code=404, detail="Image not found")
    if not os.path.exists(record.image_path):
        raise HTTPException(status_code=404, detail="Image file missing")
    return FileResponse(record.image_path, media_type="image/jpeg")


@router.delete("/wines/{wine_id}", status_code=204)
async def delete_wine(wine_id: str) -> None:
    deleted = await cache.delete(wine_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Wine record not found")
