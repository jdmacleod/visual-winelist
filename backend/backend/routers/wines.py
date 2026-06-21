import os
from typing import Literal

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy import asc, desc, func, or_, select

from backend.db import session as db_session
from backend.db.models import WineCacheRecord
from backend.models.wine import SearchResponse, WineRecord
from backend.services import cache

router = APIRouter()

_SORT_COLS = {
    "name": WineCacheRecord.name,
    "producer": WineCacheRecord.producer,
    "created_at": WineCacheRecord.created_at,
    "updated_at": WineCacheRecord.updated_at,
}


@router.get("/wines/search", response_model=SearchResponse)
async def search_wines(
    q: str = "",
    page: int = 1,
    page_size: int = 20,
    status: Literal["all", "verified", "unverified", "no_image"] = "all",
    sort: Literal["name", "producer", "created_at", "updated_at"] = "created_at",
    order: Literal["asc", "desc"] = "desc",
) -> SearchResponse:
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

        if status == "verified":
            stmt = stmt.where(WineCacheRecord.verified == True)  # noqa: E712
        elif status == "unverified":
            stmt = stmt.where(WineCacheRecord.verified == False)  # noqa: E712
        elif status == "no_image":
            stmt = stmt.where(WineCacheRecord.image_path.is_(None))

        order_fn = asc if order == "asc" else desc
        stmt = stmt.order_by(order_fn(_SORT_COLS[sort]))

        total: int = (
            await session.execute(select(func.count()).select_from(stmt.subquery()))
        ).scalar_one()

        verified_total: int = (
            await session.execute(
                select(func.count()).where(WineCacheRecord.verified == True)  # noqa: E712
            )
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
    return SearchResponse(
        results=results,
        total=total,
        page=page,
        page_size=page_size,
        verified_total=verified_total,
    )


@router.get("/wines/{wine_id}/image")
async def get_wine_image(wine_id: str) -> FileResponse:
    record = await cache.lookup(wine_id)
    if record is None or record.image_path is None:
        raise HTTPException(status_code=404, detail="Image not found")
    if not os.path.exists(record.image_path):
        raise HTTPException(status_code=404, detail="Image file missing")
    # Images are content-addressed (wine_id = sha256 of producer+name+vintage) and
    # never mutate, so a 1-year immutable cache is safe.
    return FileResponse(
        record.image_path,
        media_type="image/jpeg",
        headers={"Cache-Control": "public, max-age=31536000, immutable"},
    )


@router.delete("/wines/{wine_id}", status_code=204)
async def delete_wine(wine_id: str) -> None:
    deleted = await cache.delete(wine_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Wine record not found")
