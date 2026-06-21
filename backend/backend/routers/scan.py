import asyncio
import json
import logging
import os
import uuid
from collections.abc import AsyncIterator
from typing import Any

from fastapi import APIRouter, HTTPException, Request, UploadFile
from fastapi.responses import StreamingResponse

from backend import config
from backend.models.wine import CompleteEvent, ErrorEvent, ImageEvent, NotesEvent, WineObject
from backend.services import brave_client, cache, ollama_client, sommelier

log = logging.getLogger(__name__)

router = APIRouter()

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
    _scanning = True

    queue: asyncio.Queue[tuple[str, Any]] = asyncio.Queue()
    wines: list[WineObject] = []
    cache_hits = 0
    pending_images = 0
    wine_index = 0

    async def run_extraction() -> None:
        nonlocal wine_index
        try:
            async for wine in ollama_client.extract_wines(image_data):
                await queue.put(("wine", wine))
                wine_index += 1
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
            await queue.put(("extraction_done", None))

    asyncio.ensure_future(run_extraction())

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
                    asyncio.ensure_future(_fetch_image_to_queue(wine, queue, scan_id))

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
        return
    finally:
        _scanning = False

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

    yield _sse(
        "complete",
        CompleteEvent(
            wine_count=len(wines),
            cache_hits=cache_hits,
            scan_id=scan_id,
        ).model_dump(),
    )


@router.post("/scan")
async def scan(image: UploadFile, request: Request) -> StreamingResponse:
    log.info("[DIAG] /scan: content_type=%s", image.content_type)
    if image.content_type not in ("image/jpeg", "image/jpg"):
        log.warning("[DIAG] /scan: rejected content_type=%s", image.content_type)
        raise HTTPException(
            status_code=400,
            detail={"code": "INVALID_CONTENT_TYPE", "message": "JPEG required"},
        )

    image_data = await image.read()
    magic = " ".join(f"{b:02X}" for b in image_data[:4])
    log.info("[DIAG] /scan: received %d bytes, magic=%s", len(image_data), magic)
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
