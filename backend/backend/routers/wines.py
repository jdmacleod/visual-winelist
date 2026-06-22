import asyncio
import os
from typing import Literal

from fastapi import APIRouter, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import asc, desc, func, or_, select

from backend import config
from backend.db import session as db_session
from backend.db.models import WineCacheRecord
from backend.models.wine import SearchResponse, WinePatch, WineRecord
from backend.services import cache

router = APIRouter()

_SORT_COLS = {
    "name": WineCacheRecord.name,
    "producer": WineCacheRecord.producer,
    "created_at": WineCacheRecord.created_at,
    "updated_at": WineCacheRecord.updated_at,
    "verified": WineCacheRecord.verified,
}


@router.get("/wines/search", response_model=SearchResponse)
async def search_wines(
    q: str = "",
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=200),
    status: Literal["all", "verified", "unverified", "no_image"] = "all",
    sort: Literal["name", "producer", "created_at", "updated_at", "verified"] = "created_at",
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
    # Curator can replace images, so skip 'immutable' and cap at 24h.
    return FileResponse(
        record.image_path,
        media_type="image/jpeg",
        headers={"Cache-Control": "public, max-age=86400"},
    )


@router.post("/wines/{wine_id}/image")
async def upload_wine_image(wine_id: str, file: UploadFile) -> dict[str, str]:
    record = await cache.lookup(wine_id)
    if record is None:
        raise HTTPException(status_code=404, detail="Wine record not found")

    allowed_types = {"image/jpeg", "image/jpg"}
    if file.content_type not in allowed_types:
        raise HTTPException(status_code=400, detail="JPEG image required")

    max_bytes = 10 * 1024 * 1024
    data = await file.read(max_bytes + 1)
    if len(data) > max_bytes:
        raise HTTPException(status_code=413, detail="Image must be under 10 MB")
    if not data.startswith(b"\xff\xd8"):
        raise HTTPException(status_code=400, detail="JPEG image required")

    image_path = os.path.join(config.IMAGE_CACHE_DIR, f"{wine_id}.jpg")
    cache_dir = os.path.realpath(config.IMAGE_CACHE_DIR)
    if not os.path.realpath(image_path).startswith(cache_dir + os.sep):
        raise HTTPException(status_code=400, detail="Invalid wine ID")

    def _write(path: str, content: bytes) -> None:
        with open(path, "wb") as fp:
            fp.write(content)

    await asyncio.to_thread(_write, image_path, data)

    if not await cache.update_image(wine_id, image_path):
        await asyncio.to_thread(
            lambda: os.unlink(image_path) if os.path.exists(image_path) else None
        )
        raise HTTPException(status_code=404, detail="Wine record not found")
    return {"wine_id": wine_id, "image_url": f"/wines/{wine_id}/image"}


@router.patch("/wines/{wine_id}", response_model=WineRecord)
async def update_wine(wine_id: str, patch: WinePatch) -> WineRecord:
    fields = patch.model_dump(exclude_unset=True)
    updated = await cache.update_fields(wine_id, fields)
    if updated is None:
        raise HTTPException(status_code=404, detail="Wine record not found")
    return WineRecord(
        wine_id=updated.wine_id,
        name=updated.name,
        producer=updated.producer,
        vintage=updated.vintage,
        variety=updated.variety,
        appellation=updated.appellation,
        tasting_note=updated.tasting_note,
        pairings=updated.pairings,
        verified=updated.verified,
        image_url=f"/wines/{updated.wine_id}/image" if updated.image_path else None,
    )


@router.delete("/wines/{wine_id}", status_code=204)
async def delete_wine(wine_id: str) -> None:
    deleted = await cache.delete(wine_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Wine record not found")
