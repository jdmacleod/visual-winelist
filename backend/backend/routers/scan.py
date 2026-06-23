import asyncio
import json
import logging
import os
import time
import uuid
from collections.abc import AsyncIterator
from typing import Any

from fastapi import APIRouter, HTTPException, Query, Request, UploadFile
from fastapi.responses import StreamingResponse
from sqlalchemy import desc, select

from backend import config
from backend.db import session as db_session
from backend.db.models import ScanLog
from backend.models.wine import (
    CompleteEvent,
    ErrorEvent,
    ImageEvent,
    NotesEvent,
    ScanSummary,
    WineObject,
)
from backend.services import brave_client, cache, ollama_client, sommelier

log = logging.getLogger(__name__)

router = APIRouter()

# Process-local lock: requires --workers 1 in uvicorn CMD (enforced in Dockerfile).
# With multiple workers each process has its own _scanning copy, allowing simultaneous
# scans. The Dockerfile CMD pins workers=1 so this is a deployment-level invariant.
_scanning = False


def _sse(event: str, data: Any) -> str:
    payload = data if isinstance(data, str) else json.dumps(data)
    return f"event: {event}\ndata: {payload}\n\n"


async def _fetch_image_to_queue(
    wine: WineObject,
    queue: asyncio.Queue,
    scan_id: str,
) -> None:
    try:
        result = await brave_client.fetch_image(wine)
        if result is not None:
            # Persist to cache so future scans skip Brave for this wine.
            image_path = os.path.join(config.IMAGE_CACHE_DIR, f"{wine.wine_id}.jpg")
            try:
                await cache.write(wine, image_path, None, [])
            except Exception:
                log.warning("cache.write failed for %s", wine.wine_id, exc_info=True)
            await queue.put(("image", result))
        else:
            placeholder = ImageEvent(
                wine_id=wine.wine_id,
                url=f"/wines/{wine.wine_id}/image",
                placeholder=True,
            )
            await queue.put(("image", placeholder))
    except Exception:
        placeholder = ImageEvent(
            wine_id=wine.wine_id,
            url=f"/wines/{wine.wine_id}/image",
            placeholder=True,
        )
        await queue.put(("image", placeholder))
    finally:
        await queue.put(("image_done", None))


async def _scan_sse(image_data: bytes, scan_id: str) -> AsyncIterator[str]:
    global _scanning
    extraction_task: asyncio.Task[None] | None = None
    image_tasks: list[asyncio.Task[None]] = []

    t_scan_start = time.perf_counter()
    t_extraction_end: float | None = None
    t_phase1_end: float | None = None

    try:
        queue: asyncio.Queue[tuple[str, Any]] = asyncio.Queue()
        wines: list[WineObject] = []
        cache_hits = 0
        pending_images = 0
        wine_index = 0

        async def run_extraction() -> None:
            nonlocal wine_index, t_extraction_end
            try:
                async for wine in ollama_client.extract_wines(image_data):
                    await queue.put(("wine", wine))
                    wine_index += 1
            except TimeoutError as exc:
                await queue.put(
                    (
                        "error",
                        ErrorEvent(
                            code="OLLAMA_TIMEOUT",
                            wine_index=wine_index,
                            message=str(exc),
                        ),
                    )
                )
            except Exception as exc:
                await queue.put(
                    (
                        "error",
                        ErrorEvent(
                            code="OLLAMA_DOWN",
                            wine_index=wine_index,
                            message=str(exc),
                        ),
                    )
                )
            finally:
                t_extraction_end = time.perf_counter()
                await queue.put(("extraction_done", None))

        extraction_task = asyncio.ensure_future(run_extraction())

        # Phase 1: drain queue until extraction + all image tasks complete
        # Keepalive: send SSE comment every 15s to prevent proxy/iOS from closing connection
        extraction_done = False
        try:
            while True:
                try:
                    item = await asyncio.wait_for(queue.get(), timeout=15.0)
                except TimeoutError:
                    yield ": ping\n\n"
                    continue

                event_type, data = item

                if event_type == "wine":
                    wine: WineObject = data
                    cached = await cache.lookup(wine.wine_id)
                    if cached is not None:
                        cache_hits += 1
                        wines.append(wine)
                        yield _sse("wine", wine.model_dump_with_id())
                        image_event = ImageEvent(
                            wine_id=wine.wine_id,
                            url=f"/wines/{wine.wine_id}/image",
                            placeholder=False,
                        )
                        yield _sse("image", image_event.model_dump())
                    else:
                        wines.append(wine)
                        yield _sse("wine", wine.model_dump_with_id())
                        pending_images += 1
                        image_tasks.append(
                            asyncio.ensure_future(_fetch_image_to_queue(wine, queue, scan_id))
                        )

                elif event_type == "image":
                    img_event: ImageEvent = data
                    yield _sse("image", img_event.model_dump())

                elif event_type == "image_done":
                    pending_images -= 1

                elif event_type == "error":
                    error: ErrorEvent = data
                    yield _sse("error", error.model_dump())

                elif event_type == "extraction_done":
                    extraction_done = True

                if extraction_done and pending_images == 0:
                    break

        except Exception as exc:
            yield _sse(
                "error",
                ErrorEvent(code="INTERNAL_ERROR", message=str(exc)).model_dump(),
            )
            yield _sse(
                "complete",
                CompleteEvent(
                    wine_count=len(wines),
                    cache_hits=cache_hits,
                    scan_id=scan_id,
                ).model_dump(),
            )
            try:
                async with db_session.SessionLocal() as _s:
                    _s.add(
                        ScanLog(
                            scan_id=scan_id,
                            wine_count=len(wines),
                            cache_hits=cache_hits,
                            ollama_ms=None,
                            image_ms=None,
                            sommelier_ms=None,
                            total_ms=None,
                        )
                    )
                    await _s.commit()
            except Exception:
                log.warning("ScanLog write failed for %s", scan_id, exc_info=True)
            return

        t_phase1_end = time.perf_counter()

        # Phase 2: sommelier notes (serial — Ollama single-instance)
        for wine in wines:
            try:
                notes = await sommelier.get_notes(wine)
                yield _sse("notes", notes.model_dump())
                # Update cache record with notes; image_path already set by Phase 1.
                try:
                    await cache.write(wine, None, notes.tasting_note, notes.pairings)
                except Exception:
                    log.warning("cache.write (notes) failed for %s", wine.wine_id, exc_info=True)
            except Exception:
                yield _sse(
                    "notes",
                    NotesEvent(wine_id=wine.wine_id).model_dump(),
                )

        t_scan_end = time.perf_counter()

        ollama_ms = (
            int((t_extraction_end - t_scan_start) * 1000) if t_extraction_end is not None else None
        )
        image_ms = (
            int((t_phase1_end - t_extraction_end) * 1000)
            if t_extraction_end is not None and t_phase1_end is not None
            else None
        )
        sommelier_ms = int((t_scan_end - t_phase1_end) * 1000) if t_phase1_end is not None else None
        total_ms = int((t_scan_end - t_scan_start) * 1000)

        log.info(
            "[scan:%s] complete wines=%d cache_hits=%d"
            " ollama_ms=%s image_ms=%s sommelier_ms=%s total_ms=%d",
            scan_id,
            len(wines),
            cache_hits,
            ollama_ms,
            image_ms,
            sommelier_ms,
            total_ms,
        )

        yield _sse(
            "complete",
            CompleteEvent(
                wine_count=len(wines),
                cache_hits=cache_hits,
                scan_id=scan_id,
                ollama_ms=ollama_ms,
                image_ms=image_ms,
                sommelier_ms=sommelier_ms,
                total_ms=total_ms,
            ).model_dump(),
        )
        try:
            async with db_session.SessionLocal() as _s:
                _s.add(
                    ScanLog(
                        scan_id=scan_id,
                        wine_count=len(wines),
                        cache_hits=cache_hits,
                        ollama_ms=ollama_ms,
                        image_ms=image_ms,
                        sommelier_ms=sommelier_ms,
                        total_ms=total_ms,
                    )
                )
                await _s.commit()
        except Exception:
            log.warning("ScanLog write failed for %s", scan_id, exc_info=True)

    finally:
        # Always release the lock — even on client disconnect (GeneratorExit/CancelledError
        # are BaseException, not Exception, so inner except blocks don't catch them).
        _scanning = False
        if extraction_task is not None and not extraction_task.done():
            extraction_task.cancel()
        for _task in image_tasks:
            if not _task.done():
                _task.cancel()


@router.post("/scan")
async def scan(image: UploadFile, request: Request) -> StreamingResponse:
    global _scanning
    log.info("/scan: content_type=%s", image.content_type)
    if image.content_type not in ("image/jpeg", "image/jpg"):
        log.warning("/scan: rejected content_type=%s", image.content_type)
        raise HTTPException(
            status_code=400,
            detail={"code": "INVALID_CONTENT_TYPE", "message": "JPEG required"},
        )

    image_data = await image.read()
    magic = " ".join(f"{b:02X}" for b in image_data[:4])
    log.info("/scan: received %d bytes, magic=%s", len(image_data), magic)
    if image_data[:2] != b"\xff\xd8":
        raise HTTPException(
            status_code=415,
            detail={"code": "INVALID_IMAGE", "message": "JPEG magic bytes required (0xFF 0xD8)"},
        )
    if len(image_data) > config.MAX_UPLOAD_SIZE:
        raise HTTPException(
            status_code=413,
            detail={
                "code": "UPLOAD_TOO_LARGE",
                "message": f"Max {config.MAX_UPLOAD_SIZE} bytes",
            },
        )

    if _scanning:
        raise HTTPException(
            status_code=503,
            detail={"code": "SCANNER_BUSY", "queue_position": 1},
        )
    # Claim the lock synchronously — no await between here and StreamingResponse creation,
    # so the asyncio event loop cannot service a second request in between. _scan_sse
    # resets _scanning = False in its finally block (covers both clean exit and
    # GeneratorExit on client disconnect).
    _scanning = True

    scan_id = uuid.uuid4().hex[:8]
    return StreamingResponse(
        _scan_sse(image_data, scan_id),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "X-Scan-Id": scan_id,
        },
    )


@router.get("/scans/recent")
async def get_recent_scans(limit: int = Query(default=10, ge=1, le=100)) -> dict[str, Any]:
    async with db_session.SessionLocal() as session:
        rows = await session.execute(select(ScanLog).order_by(desc(ScanLog.timestamp)).limit(limit))
        scans = rows.scalars().all()

    total_wines = sum(s.wine_count for s in scans)
    total_hits = sum(s.cache_hits for s in scans)
    hit_rate = min(100, round(total_hits / total_wines * 100)) if total_wines > 0 else None

    return {
        "scans": [
            ScanSummary(
                scan_id=s.scan_id,
                timestamp=s.timestamp.isoformat(),
                wine_count=s.wine_count,
                cache_hits=s.cache_hits,
            ).model_dump()
            for s in scans
        ],
        "hit_rate": hit_rate,
    }
