from fastapi import APIRouter, HTTPException

from backend.models.wine import CurateRequest
from backend.services import cache

router = APIRouter()


@router.post("/curate", status_code=200)
async def curate(body: CurateRequest) -> dict:
    # T4 implements real DB update; stub returns 404 since no records exist yet
    record = await cache.lookup(body.wine_id)
    if record is None:
        raise HTTPException(status_code=404, detail="Wine not found in cache")
    # T4: set record.verified = True, record.image_path = body.image_url (if provided)
    return {"wine_id": body.wine_id, "verified": True}
