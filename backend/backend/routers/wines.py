import os

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from backend.models.wine import SearchResponse
from backend.services import cache

router = APIRouter()


@router.get("/wines/search", response_model=SearchResponse)
async def search_wines(q: str = "", page: int = 1, page_size: int = 20) -> SearchResponse:
    # T4 implements real SQLite search; stub returns empty results
    return SearchResponse(results=[], total=0, page=page, page_size=page_size)


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
