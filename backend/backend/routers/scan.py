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
from backend.routers.wines import _generate_variant
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


def _write_scan_image(image_data: bytes, scan_id: str, retention: int | None = None) -> None:
    """Persist the uploaded scan photo to scans/{scan_id}.jpg for later inspection.

    When `retention` is a positive int, prune the scans dir to the newest N files
    (E13) so opt-in saving doesn't grow disk without bound.
    """
    scans_dir = os.path.join(config.IMAGE_CACHE_DIR, "scans")
    os.makedirs(scans_dir, exist_ok=True)
    with open(os.path.join(scans_dir, f"{scan_id}.jpg"), "wb") as f:
        f.write(image_data)
    if retention is not None and retention > 0:
        _prune_scan_images(scans_dir, retention)


def _prune_scan_images(scans_dir: str, keep: int) -> None:
    """Delete the oldest scan photos beyond the newest `keep` (by mtime)."""
    try:
        entries = [
            os.path.join(scans_dir, name) for name in os.listdir(scans_dir) if name.endswith(".jpg")
        ]
    except OSError:
        return
    if len(entries) <= keep:
        return
    entries.sort(key=lambda path: os.path.getmtime(path), reverse=True)
    for stale in entries[keep:]:
        try:
            os.remove(stale)
        except OSError:
            log.warning("scan-image prune failed for %s", stale, exc_info=True)


async def _write_scan_log(
    scan_id: str,
    wine_count: int,
    cache_hits: int,
    ollama_ms: int | None = None,
    image_ms: int | None = None,
    sommelier_ms: int | None = None,
    total_ms: int | None = None,
) -> None:
    try:
        async with db_session.SessionLocal() as _s:
            _s.add(
                ScanLog(
                    scan_id=scan_id,
                    wine_count=wine_count,
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


async def _fetch_image_to_queue(
    wine: WineObject,
    queue: asyncio.Queue,
    scan_id: str,
    timing_acc: dict[str, int],
) -> None:
    try:
        result, search_ms, download_ms = await brave_client.fetch_image(wine)
        # timing_acc is shared across all per-wine fetch tasks; mutation is safe
        # without a lock because they all run on the single event-loop thread.
        timing_acc["brave_search_ms"] += search_ms
        timing_acc["image_download_ms"] += download_ms
        if result is not None:
            # Persist to cache so future scans skip Brave for this wine.
            image_path = os.path.join(config.IMAGE_CACHE_DIR, f"{wine.wine_id}.jpg")
            try:
                await cache.write(wine, image_path, None, [])
            except Exception:
                log.warning("cache.write failed for %s", wine.wine_id, exc_info=True)
            # Pre-generate the card variant now so the iOS image fetch hits an
            # existing file (immediate FileResponse) instead of triggering
            # on-demand WebP generation inside get_wine_image. Non-fatal on
            # failure: get_wine_image still falls back to on-demand generation.
            variant_path = os.path.join(config.IMAGE_CACHE_DIR, f"{wine.wine_id}_card.webp")
            try:
                await asyncio.to_thread(
                    _generate_variant, image_path, variant_path, config.IMAGE_CARD_WIDTH
                )
            except Exception:
                log.warning(
                    "card variant pre-generation failed for %s", wine.wine_id, exc_info=True
                )
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


async def _scan_sse(
    image_data: bytes,
    scan_id: str,
    receive_ms: int | None = None,
    save_image: bool = False,
    retention: int | None = None,
) -> AsyncIterator[str]:
    global _scanning
    extraction_task: asyncio.Task[None] | None = None
    sommelier_task: asyncio.Task[None] | None = None
    image_tasks: list[asyncio.Task[None]] = []

    t_scan_start = time.perf_counter()
    t_first_wine: float | None = None
    t_extraction_end: float | None = None
    t_images_end: float | None = None
    t_sommelier_end: float | None = None

    # Shared accumulator for per-wine Brave timing, summed across all fetch tasks.
    timing_acc: dict[str, int] = {"brave_search_ms": 0, "image_download_ms": 0}

    try:
        # Flush an SSE comment immediately so the HTTP 200 + first byte leave the
        # server now, instead of riding out with the first real event (or the 15s
        # keepalive). This makes the iOS http_ok/ttfb reflect true network time and
        # exposes Ollama's first-wine latency as the gap to the first wine event.
        yield ": ready\n\n"

        # Optionally persist the raw scan photo (keyed by scan_id) so telemetry rows
        # can be correlated to what the model actually saw. Non-fatal on failure.
        if config.SAVE_SCAN_IMAGES or save_image:
            # Always bound disk: if no valid per-request retention was given, fall
            # back to the server default so "save" can't mean "keep forever".
            effective_retention = (
                retention
                if retention is not None and retention > 0
                else config.SCAN_IMAGE_RETENTION_DEFAULT
            )
            try:
                await asyncio.to_thread(_write_scan_image, image_data, scan_id, effective_retention)
            except Exception:
                log.warning("save_scan_image failed for %s", scan_id, exc_info=True)

        queue: asyncio.Queue[tuple[str, Any]] = asyncio.Queue()
        wines: list[WineObject] = []
        cache_hits = 0
        pending_images = 0
        wine_index = 0

        async def run_extraction() -> None:
            nonlocal wine_index, t_extraction_end, t_first_wine

            def _on_first_token() -> None:
                # First byte from Ollama → analysis is now underway (vs still
                # loading the model / encoding the image). Drives the client's
                # "Getting ready…" → "Analyzing…" transition.
                queue.put_nowait(("analyzing", None))

            try:
                async for wine in ollama_client.extract_wines(
                    image_data, on_first_token=_on_first_token
                ):
                    if t_first_wine is None:
                        t_first_wine = time.perf_counter()
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
            except (ConnectionRefusedError, OSError) as exc:
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

        async def run_sommelier(target_wines: list[WineObject]) -> None:
            # Tasting notes use Ollama, which is free the moment extraction ends.
            # Run this concurrently with the still-in-flight Brave image fetches
            # (HTTP, no Ollama) instead of waiting for them — notes start sooner.
            nonlocal t_sommelier_end
            # finally guarantees sommelier_done even if the body raises (symmetric
            # with run_extraction): otherwise the drain loop would spin on keepalive
            # pings forever, holding the _scanning lock until the client disconnects.
            try:
                for note_wine in target_wines:
                    try:
                        notes = await sommelier.get_notes(note_wine)
                        await queue.put(("notes", notes))
                        try:
                            await cache.write(note_wine, None, notes.tasting_note, notes.pairings)
                        except Exception:
                            log.warning(
                                "cache.write (notes) failed for %s",
                                note_wine.wine_id,
                                exc_info=True,
                            )
                    except Exception:
                        await queue.put(("notes", NotesEvent(wine_id=note_wine.wine_id)))
            finally:
                t_sommelier_end = time.perf_counter()
                await queue.put(("sommelier_done", None))

        extraction_task = asyncio.ensure_future(run_extraction())

        # Single drain loop: stream wines + images, and the moment extraction
        # finishes, kick off the sommelier pass so notes overlap image fetching.
        # Keepalive: send SSE comment every 15s to prevent proxy/iOS from closing connection
        extraction_done = False
        sommelier_done = False
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
                            asyncio.ensure_future(
                                _fetch_image_to_queue(wine, queue, scan_id, timing_acc)
                            )
                        )

                elif event_type == "image":
                    img_event: ImageEvent = data
                    yield _sse("image", img_event.model_dump())

                elif event_type == "notes":
                    notes_event: NotesEvent = data
                    yield _sse("notes", notes_event.model_dump())

                elif event_type == "analyzing":
                    yield _sse("status", "analyzing")

                elif event_type == "image_done":
                    pending_images -= 1
                    if extraction_done and pending_images == 0 and t_images_end is None:
                        t_images_end = time.perf_counter()

                elif event_type == "error":
                    error: ErrorEvent = data
                    yield _sse("error", error.model_dump())

                elif event_type == "extraction_done":
                    extraction_done = True
                    # Extraction is complete, so `wines` holds the full set and
                    # Ollama is free. Start notes now, concurrent with images.
                    if t_images_end is None and pending_images == 0:
                        t_images_end = time.perf_counter()
                    sommelier_task = asyncio.ensure_future(run_sommelier(list(wines)))

                elif event_type == "sommelier_done":
                    sommelier_done = True

                if extraction_done and pending_images == 0 and sommelier_done:
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
                    receive_ms=receive_ms,
                    first_wine_ms=(
                        max(0, int((t_first_wine - t_scan_start) * 1000))
                        if t_first_wine is not None
                        else None
                    ),
                    brave_search_ms=timing_acc["brave_search_ms"],
                    image_download_ms=timing_acc["image_download_ms"],
                ).model_dump(),
            )
            await _write_scan_log(scan_id=scan_id, wine_count=len(wines), cache_hits=cache_hits)
            return

        # Notes + images both completed inside the loop above (sommelier now runs
        # concurrent with image fetches), so the stream is fully drained here.
        t_scan_end = time.perf_counter()

        first_wine_ms = (
            max(0, int((t_first_wine - t_scan_start) * 1000)) if t_first_wine is not None else None
        )
        ollama_ms = (
            int((t_extraction_end - t_scan_start) * 1000) if t_extraction_end is not None else None
        )
        # image_ms and sommelier_ms are now wall-clock durations measured from the
        # end of extraction; they overlap (notes run during image fetching) rather
        # than summing serially, which is the whole point of the change.
        image_ms = (
            max(0, int((t_images_end - t_extraction_end) * 1000))
            if t_extraction_end is not None and t_images_end is not None
            else None
        )
        sommelier_ms = (
            max(0, int((t_sommelier_end - t_extraction_end) * 1000))
            if t_extraction_end is not None and t_sommelier_end is not None
            else None
        )
        total_ms = int((t_scan_end - t_scan_start) * 1000)

        log.info(
            "[scan:%s] complete wines=%d cache_hits=%d"
            " first_wine_ms=%s ollama_ms=%s image_ms=%s sommelier_ms=%s total_ms=%d",
            scan_id,
            len(wines),
            cache_hits,
            first_wine_ms,
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
                receive_ms=receive_ms,
                first_wine_ms=first_wine_ms,
                ollama_ms=ollama_ms,
                image_ms=image_ms,
                sommelier_ms=sommelier_ms,
                total_ms=total_ms,
                brave_search_ms=timing_acc["brave_search_ms"],
                image_download_ms=timing_acc["image_download_ms"],
            ).model_dump(),
        )
        await _write_scan_log(
            scan_id=scan_id,
            wine_count=len(wines),
            cache_hits=cache_hits,
            ollama_ms=ollama_ms,
            image_ms=image_ms,
            sommelier_ms=sommelier_ms,
            total_ms=total_ms,
        )

    finally:
        # Always release the lock — even on client disconnect (GeneratorExit/CancelledError
        # are BaseException, not Exception, so inner except blocks don't catch them).
        _scanning = False
        if extraction_task is not None and not extraction_task.done():
            extraction_task.cancel()
        if sommelier_task is not None and not sommelier_task.done():
            sommelier_task.cancel()
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

    # receive_ms measures how long the request body takes to arrive. In ASGI the
    # body streams lazily from the socket via receive() events, so on a slow
    # connection this correlates with network transfer time (not just a buffer copy).
    t_receive_start = time.perf_counter()
    image_data = await image.read()
    receive_ms = max(0, int((time.perf_counter() - t_receive_start) * 1000))
    magic = " ".join(f"{b:02X}" for b in image_data[:4])
    log.info("/scan: received %d bytes in %d ms, magic=%s", len(image_data), receive_ms, magic)
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

    # Per-request opt-in scan-image saving (E13), set by the iOS Preferences toggle.
    save_image = request.headers.get("X-Save-Scan-Image", "").strip() in ("1", "true", "yes")
    retention: int | None = None
    raw_retention = request.headers.get("X-Scan-Image-Retention", "").strip()
    if raw_retention.isdigit():
        retention = int(raw_retention)

    scan_id = uuid.uuid4().hex[:8]
    return StreamingResponse(
        _scan_sse(image_data, scan_id, receive_ms, save_image=save_image, retention=retention),
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
