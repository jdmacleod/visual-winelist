from fastapi import APIRouter, HTTPException

from backend.db import session as db_session
from backend.db.models import WineCacheRecord
from backend.models.wine import CurateRequest

router = APIRouter()


@router.post("/curate", status_code=200)
async def curate(body: CurateRequest) -> dict:
    """Mark a cached wine as curator-verified."""
    async with db_session.SessionLocal() as session:
        record = await session.get(WineCacheRecord, body.wine_id)
        if record is None:
            raise HTTPException(status_code=404, detail="Wine not found in cache")
        record.verified = body.verified
        await session.commit()
        return {"wine_id": body.wine_id, "verified": record.verified}
