import json
import logging
from typing import Any

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import desc, select

from backend import config
from backend.db import session as db_session
from backend.db.models import ScanTelemetryRecord
from backend.models.telemetry import ScanTelemetry

log = logging.getLogger(__name__)

router = APIRouter()


@router.post("/telemetry/scan", status_code=204)
async def post_scan_telemetry(payload: ScanTelemetry) -> None:
    """Accept one opt-in scan-diagnostics report from the iOS client.

    Best-effort: a write failure is logged but still returns 204 so the
    fire-and-forget client never treats telemetry as part of the scan.
    Upserts by scan_id (a re-post for the same scan overwrites).
    """
    if not config.TELEMETRY_ENABLED:
        raise HTTPException(status_code=404, detail="telemetry disabled")

    try:
        async with db_session.SessionLocal() as s:
            await s.merge(
                ScanTelemetryRecord(
                    scan_id=payload.scan_id,
                    outcome=payload.outcome,
                    app_version=payload.app_version,
                    git_sha=payload.git_sha,
                    device_model=payload.device_model,
                    wine_count=payload.wine_count,
                    ttfb_ms=payload.ttfb_ms,
                    first_wine_ms=payload.first_wine_ms,
                    ollama_ms=payload.ollama_ms,
                    total_ms=payload.total_ms,
                    payload=payload.model_dump_json(),
                )
            )
            await s.commit()
    except Exception:
        log.warning("telemetry write failed for %s", payload.scan_id, exc_info=True)

    return None


@router.get("/telemetry/scans")
async def list_scan_telemetry(
    limit: int = Query(default=20, ge=1, le=200),
    outcome: str | None = Query(default=None),
) -> dict[str, Any]:
    """Recent telemetry reports, newest first. Returns the full stored payloads
    (plus the server-side received timestamp) so you can inspect a run directly."""
    async with db_session.SessionLocal() as s:
        stmt = select(ScanTelemetryRecord).order_by(desc(ScanTelemetryRecord.timestamp))
        if outcome is not None:
            stmt = stmt.where(ScanTelemetryRecord.outcome == outcome)
        rows = (await s.execute(stmt.limit(limit))).scalars().all()

    scans = [{**json.loads(r.payload), "received_at": r.timestamp.isoformat()} for r in rows]
    return {"scans": scans, "count": len(scans)}
