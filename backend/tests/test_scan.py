import asyncio
import json
from collections.abc import AsyncIterator
from unittest.mock import AsyncMock, patch

from backend.db import session as db_session
from backend.db.models import ScanLog
from backend.models.wine import ImageEvent, NotesEvent, WineObject
from backend.services import cache
from tests.conftest import make_jpeg

MARGAUX = WineObject(
    name="Château Margaux",
    producer="Château Margaux",
    vintage="2018",
    variety="Cabernet Sauvignon blend",
    appellation="Margaux, Bordeaux",
    price="$240",
    confidence=0.94,
)
OPUS = WineObject(
    name="Opus One",
    producer="Opus One",
    vintage="2019",
    confidence=0.91,
)


async def _wine_stream(*wines: WineObject) -> AsyncIterator[WineObject]:
    for wine in wines:
        yield wine


def _collect_sse(text: str) -> list[tuple[str, str]]:
    """Parse raw SSE text into [(event_type, data), ...] ignoring comments."""
    events = []
    current_event = "message"
    current_data = ""
    for line in text.splitlines():
        if line.startswith(": "):
            continue
        if line.startswith("event: "):
            current_event = line[7:]
        elif line.startswith("data: "):
            current_data = line[6:]
        elif line == "":
            if current_data:
                events.append((current_event, current_data))
            current_event = "message"
            current_data = ""
    return events


async def test_scan_non_jpeg(client):
    r = await client.post(
        "/scan",
        files={"image": ("list.png", b"fake-png", "image/png")},
    )
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "INVALID_CONTENT_TYPE"


async def test_scan_gif_rejected(client):
    r = await client.post(
        "/scan",
        files={"image": ("list.gif", b"GIF89a", "image/gif")},
    )
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "INVALID_CONTENT_TYPE"


async def test_scan_octet_stream_rejected(client):
    r = await client.post(
        "/scan",
        files={"image": ("list.jpg", b"binary", "application/octet-stream")},
    )
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "INVALID_CONTENT_TYPE"


async def test_scan_image_jpg_alias_accepted(client):
    """image/jpg is a valid alias for image/jpeg and must not be rejected."""
    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        r = await client.post(
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpg")},
        )
    assert r.status_code == 200


async def test_scan_jpeg_wrong_magic_bytes_rejected(client):
    """image/jpeg MIME type with non-JPEG content (e.g. PNG) must be rejected with 415."""
    png_magic = b"\x89PNG\r\n\x1a\n" + b"\x00" * 100
    r = await client.post(
        "/scan",
        files={"image": ("list.jpg", png_magic, "image/jpeg")},
    )
    assert r.status_code == 415
    assert r.json()["detail"]["code"] == "INVALID_IMAGE"


async def test_scan_empty_body_rejected(client):
    """Zero-byte upload with image/jpeg content type must be rejected with 415 INVALID_IMAGE."""
    r = await client.post(
        "/scan",
        files={"image": ("list.jpg", b"", "image/jpeg")},
    )
    assert r.status_code == 415
    assert r.json()["detail"]["code"] == "INVALID_IMAGE"


async def test_scan_oversized(client):
    big = make_jpeg(26 * 1024 * 1024)
    r = await client.post(
        "/scan",
        files={"image": ("list.jpg", big, "image/jpeg")},
    )
    assert r.status_code == 413
    assert r.json()["detail"]["code"] == "UPLOAD_TOO_LARGE"


async def test_scan_upload_error_includes_max_size(client):
    """The 413 detail message mentions the size limit."""
    big = make_jpeg(26 * 1024 * 1024)
    r = await client.post(
        "/scan",
        files={"image": ("list.jpg", big, "image/jpeg")},
    )
    assert r.status_code == 413
    assert "Max" in r.json()["detail"]["message"]


async def test_scan_scanner_busy(client):
    import backend.routers.scan as scan_mod

    scan_mod._scanning = True
    try:
        r = await client.post(
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        )
        assert r.status_code == 503
        assert r.json()["detail"]["code"] == "SCANNER_BUSY"
    finally:
        scan_mod._scanning = False


async def test_scan_lock_released_on_generator_close():
    """_scanning must reset to False when the client disconnects mid-scan.

    Simulates iOS navigating away: the StreamingResponse generator is closed
    early (GeneratorExit is a BaseException, not Exception, so the inner
    `except Exception` blocks do NOT catch it). Without the outer try/finally
    the lock stays True forever and every subsequent scan gets 503.
    """
    import backend.routers.scan as scan_mod
    from backend.routers.scan import _scan_sse

    async def _no_wines(_image_data: bytes, on_first_token=None) -> AsyncIterator[WineObject]:
        return
        yield  # makes this an async generator function

    assert not scan_mod._scanning, "pre-condition: lock must start False"

    with patch("backend.routers.scan.ollama_client.extract_wines", _no_wines):
        # Simulate the scan() handler: it sets _scanning = True synchronously
        # before handing the generator to StreamingResponse (TOCTOU fix).
        scan_mod._scanning = True
        gen = _scan_sse(make_jpeg(), "test-disconnect")
        # First chunk is the immediate ": ready" flush; drain until the complete event.
        # The generator runs Phase 1+2, yields complete, then suspends — at that suspend
        # point the finally block has NOT run, so _scanning is still True.
        chunks: list[str] = []
        async for chunk in gen:
            chunks.append(chunk)
            if "complete" in chunk:
                break
        assert chunks and chunks[0].startswith(": ready"), (
            f"stream must open with ': ready'; got {chunks[:1]!r}"
        )
        assert any("complete" in c for c in chunks), f"expected complete event, got: {chunks!r}"
        assert scan_mod._scanning, "lock must be True while generator is suspended"

        # Simulate client disconnect: close the generator before it is exhausted.
        await gen.aclose()

    assert not scan_mod._scanning, "_scanning must be False after generator.aclose()"


async def test_scan_happy_path(client):
    """Two wines extracted; SSE stream has wine events, notes events, complete sentinel."""

    async def mock_notes(wine: WineObject) -> NotesEvent:
        return NotesEvent(
            wine_id=wine.wine_id,
            tasting_note="Rich and complex.",
            pairings=["lamb", "duck"],
        )

    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX, OPUS),
        ),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=(None, 0, 0)),
        ),
        patch(
            "backend.routers.scan.sommelier.get_notes",
            new=AsyncMock(side_effect=mock_notes),
        ),
        patch(
            "backend.routers.scan.cache.lookup",
            new=AsyncMock(return_value=None),
        ),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            assert r.status_code == 200
            assert "text/event-stream" in r.headers["content-type"]
            body = await r.aread()

    events = _collect_sse(body.decode())
    event_types = [e for e, _ in events]

    # wine events come before notes events (two-phase SSE — D1)
    wine_indices = [i for i, (e, _) in enumerate(events) if e == "wine"]
    notes_indices = [i for i, (e, _) in enumerate(events) if e == "notes"]
    assert wine_indices, "no wine events"
    assert notes_indices, "no notes events"
    assert max(wine_indices) < min(notes_indices), "notes events must follow all wine events"

    # complete sentinel present (D9)
    assert "complete" in event_types

    complete_data = json.loads(next(d for e, d in events if e == "complete"))
    assert complete_data["wine_count"] == 2
    assert "scan_id" in complete_data


async def test_notes_run_concurrently_with_image_fetch(client):
    """Sommelier notes must start as soon as extraction ends, concurrent with the
    Brave image fetches — not serially after them. fetch_image blocks on an event
    that only get_notes sets: if notes still ran after all images (the old serial
    Phase 2), the fetch would unblock via its timeout, not via notes."""
    notes_started = asyncio.Event()
    unblocked_by_notes: list[bool] = []

    async def mock_notes(wine: WineObject) -> NotesEvent:
        notes_started.set()
        return NotesEvent(wine_id=wine.wine_id, tasting_note="Lush.", pairings=["beef"])

    async def mock_fetch(wine: WineObject):
        try:
            await asyncio.wait_for(notes_started.wait(), timeout=8.0)
            unblocked_by_notes.append(True)
        except TimeoutError:
            unblocked_by_notes.append(False)
        return (None, 0, 0)

    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX, OPUS),
        ),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(side_effect=mock_fetch),
        ),
        patch(
            "backend.routers.scan.sommelier.get_notes",
            new=AsyncMock(side_effect=mock_notes),
        ),
        patch(
            "backend.routers.scan.cache.lookup",
            new=AsyncMock(return_value=None),
        ),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            assert r.status_code == 200
            body = await r.aread()

    events = _collect_sse(body.decode())
    types = [e for e, _ in events]
    assert "notes" in types, "notes must be emitted"
    assert "image" in types, "image events must be emitted"
    assert "complete" in types
    assert unblocked_by_notes, "image fetch was never attempted"
    assert all(unblocked_by_notes), (
        "image fetch must be unblocked by notes running concurrently, "
        "not by its own timeout (proves notes no longer wait for images)"
    )


async def test_scan_ollama_down(client):
    async def raise_connection_error(
        image_data: bytes, on_first_token=None
    ) -> AsyncIterator[WineObject]:
        raise ConnectionRefusedError("Ollama not running")
        yield  # pragma: no cover

    with patch(
        "backend.routers.scan.ollama_client.extract_wines",
        side_effect=raise_connection_error,
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            assert r.status_code == 200
            body = await r.aread()

    events = _collect_sse(body.decode())
    event_types = [e for e, _ in events]
    assert "error" in event_types
    assert "complete" in event_types

    error_data = json.loads(next(d for e, d in events if e == "error"))
    assert error_data["code"] == "OLLAMA_DOWN"
    complete_data = json.loads(next(d for e, d in events if e == "complete"))
    scan_id = complete_data["scan_id"]

    from sqlalchemy import select as sa_select

    async with db_session.SessionLocal() as s:
        row = await s.scalar(sa_select(ScanLog).where(ScanLog.scan_id == scan_id))
    assert row is not None, "ScanLog must be written even on OLLAMA_DOWN"


async def test_two_phase_sse_order(client):
    """ALL wine events precede ALL notes events."""

    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX, OPUS),
        ),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=(None, 0, 0)),
        ),
        patch(
            "backend.routers.scan.sommelier.get_notes",
            new=AsyncMock(side_effect=lambda w: NotesEvent(wine_id=w.wine_id)),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            body = await r.aread()

    events = _collect_sse(body.decode())
    wine_idx = [i for i, (e, _) in enumerate(events) if e == "wine"]
    notes_idx = [i for i, (e, _) in enumerate(events) if e == "notes"]
    assert wine_idx and notes_idx
    assert max(wine_idx) < min(notes_idx)


async def test_event_complete_has_scan_id(client):
    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX),
        ),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=(None, 0, 0)),
        ),
        patch(
            "backend.routers.scan.sommelier.get_notes",
            new=AsyncMock(side_effect=lambda w: NotesEvent(wine_id=w.wine_id)),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            body = await r.aread()

    events = _collect_sse(body.decode())
    complete = json.loads(next(d for e, d in events if e == "complete"))
    assert "scan_id" in complete
    assert complete["wine_count"] == 1


async def test_scan_ollama_timeout(client):
    """TimeoutError from Ollama extraction → SSE error event with OLLAMA_TIMEOUT code."""

    async def raise_timeout(image_data: bytes, on_first_token=None) -> AsyncIterator[WineObject]:
        raise TimeoutError("Ollama extraction timed out")
        yield  # pragma: no cover

    with patch(
        "backend.routers.scan.ollama_client.extract_wines",
        side_effect=raise_timeout,
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            assert r.status_code == 200
            body = await r.aread()

    events = _collect_sse(body.decode())
    event_types = [e for e, _ in events]
    assert "error" in event_types
    assert "complete" in event_types
    error_data = json.loads(next(d for e, d in events if e == "error"))
    assert error_data["code"] == "OLLAMA_TIMEOUT"
    complete_data = json.loads(next(d for e, d in events if e == "complete"))
    assert complete_data["wine_count"] == 0
    assert isinstance(complete_data["total_ms"], int)
    assert complete_data["total_ms"] >= 0
    scan_id = complete_data["scan_id"]

    from sqlalchemy import select as sa_select

    async with db_session.SessionLocal() as s:
        row = await s.scalar(sa_select(ScanLog).where(ScanLog.scan_id == scan_id))
    assert row is not None, "ScanLog must be written even on OLLAMA_TIMEOUT"


async def test_scan_cache_miss_writes_to_db(client):
    """Cache miss → Brave finds an image → cache.write called → record exists in test DB."""
    fake_image = ImageEvent(
        wine_id=MARGAUX.wine_id,
        url=f"/wines/{MARGAUX.wine_id}/image",
        placeholder=False,
    )
    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX),
        ),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=(fake_image, 18, 42)),
        ),
        patch(
            "backend.routers.scan.sommelier.get_notes",
            new=AsyncMock(side_effect=lambda w: NotesEvent(wine_id=w.wine_id)),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            assert r.status_code == 200
            await r.aread()

    record = await cache.lookup(MARGAUX.wine_id)
    assert record is not None, (
        "cache.write must be called on a Brave cache-miss with an image result"
    )
    assert record.name == MARGAUX.name


async def test_scan_id_in_response_header(client):
    """X-Scan-Id response header is present and matches scan_id in event:complete payload."""
    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX),
        ),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=(None, 0, 0)),
        ),
        patch(
            "backend.routers.scan.sommelier.get_notes",
            new=AsyncMock(side_effect=lambda w: NotesEvent(wine_id=w.wine_id)),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            assert r.status_code == 200
            scan_id_header = r.headers.get("x-scan-id")
            body = await r.aread()

    assert scan_id_header is not None, "X-Scan-Id header must be present on /scan response"

    events = _collect_sse(body.decode())
    complete = json.loads(next(d for e, d in events if e == "complete"))
    assert complete["scan_id"] == scan_id_header, (
        "scan_id in event:complete must match X-Scan-Id response header"
    )


async def test_scan_saves_image_when_header_set(client, tmp_path):
    """X-Save-Scan-Image header opts this request into persisting the photo (E13)."""
    with (
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        patch("backend.config.SAVE_SCAN_IMAGES", False),
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        r = await client.post(
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
            headers={"X-Save-Scan-Image": "1"},
        )
        assert r.status_code == 200
    saved = list((tmp_path / "scans").glob("*.jpg"))
    assert len(saved) == 1, "header should persist exactly one scan photo"


async def test_scan_does_not_save_without_header_or_config(client, tmp_path):
    """No header and SAVE_SCAN_IMAGES off => nothing is written."""
    with (
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        patch("backend.config.SAVE_SCAN_IMAGES", False),
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        r = await client.post(
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        )
        assert r.status_code == 200
    assert not (tmp_path / "scans").exists() or not list((tmp_path / "scans").glob("*.jpg"))


async def test_scan_image_retention_prunes_oldest(client, tmp_path):
    """X-Scan-Image-Retention keeps only the newest N photos (oldest pruned)."""
    import os

    scans_dir = tmp_path / "scans"
    scans_dir.mkdir()
    # Three pre-existing photos with strictly increasing mtimes.
    for i, name in enumerate(["old1.jpg", "old2.jpg", "old3.jpg"]):
        path = scans_dir / name
        path.write_bytes(b"x")
        os.utime(path, (1000 + i, 1000 + i))

    with (
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        patch("backend.config.SAVE_SCAN_IMAGES", False),
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        r = await client.post(
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
            headers={"X-Save-Scan-Image": "1", "X-Scan-Image-Retention": "2"},
        )
        assert r.status_code == 200

    remaining = {p.name for p in scans_dir.glob("*.jpg")}
    assert len(remaining) == 2, f"retention=2 must keep 2 photos, got {remaining}"
    assert "old1.jpg" not in remaining, "oldest photo must be pruned"


async def test_recent_scans_empty(client):
    """GET /scans/recent returns empty list and null hit_rate when no scans logged."""
    r = await client.get("/scans/recent")
    assert r.status_code == 200
    body = r.json()
    assert body["scans"] == []
    assert body["hit_rate"] is None


async def test_recent_scans_with_data(client):
    """GET /scans/recent returns scans ordered newest-first and computes hit_rate."""
    async with db_session.SessionLocal() as s:
        s.add(ScanLog(scan_id="aaa00001", wine_count=4, cache_hits=1))
        s.add(ScanLog(scan_id="bbb00002", wine_count=6, cache_hits=3))
        await s.commit()

    r = await client.get("/scans/recent")
    assert r.status_code == 200
    body = r.json()
    assert len(body["scans"]) == 2
    # hit_rate = round((1+3)/(4+6)*100) = round(40) = 40
    assert body["hit_rate"] == 40
    # scans ordered newest-first (bbb was inserted last, so has a later timestamp)
    assert body["scans"][0]["scan_id"] == "bbb00002"
    assert body["scans"][1]["scan_id"] == "aaa00001"


async def test_recent_scans_hit_rate_capped(client):
    """hit_rate is capped at 100 even if cache_hits exceeds wine_count."""
    async with db_session.SessionLocal() as s:
        s.add(ScanLog(scan_id="ccc00003", wine_count=2, cache_hits=5))
        await s.commit()

    r = await client.get("/scans/recent")
    assert r.status_code == 200
    assert r.json()["hit_rate"] == 100


async def test_recent_scans_limit_param(client):
    """limit query param restricts how many scans are returned."""
    async with db_session.SessionLocal() as s:
        for i in range(5):
            s.add(ScanLog(scan_id=f"scan{i:04d}", wine_count=1, cache_hits=0))
        await s.commit()

    r = await client.get("/scans/recent?limit=3")
    assert r.status_code == 200
    assert len(r.json()["scans"]) == 3


async def test_scan_happy_path_timing_fields_in_complete_event(client):
    """complete event includes integer timing fields populated by the scan pipeline."""
    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX),
        ),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=(None, 0, 0)),
        ),
        patch(
            "backend.routers.scan.sommelier.get_notes",
            new=AsyncMock(side_effect=lambda w: NotesEvent(wine_id=w.wine_id)),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            assert r.status_code == 200
            body = await r.aread()

    events = _collect_sse(body.decode())
    complete = json.loads(next(d for e, d in events if e == "complete"))

    assert "total_ms" in complete
    assert isinstance(complete["total_ms"], int)
    assert complete["total_ms"] >= 0
    assert "ollama_ms" in complete
    assert complete["ollama_ms"] is None or isinstance(complete["ollama_ms"], int)
    assert "image_ms" in complete
    assert complete["image_ms"] is None or isinstance(complete["image_ms"], int)
    assert "sommelier_ms" in complete
    assert complete["sommelier_ms"] is None or isinstance(complete["sommelier_ms"], int)


async def test_scan_happy_path_timing_persisted_in_db(client):
    """ScanLog row written by the happy path has total_ms populated."""
    from sqlalchemy import select as sa_select

    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX),
        ),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=(None, 0, 0)),
        ),
        patch(
            "backend.routers.scan.sommelier.get_notes",
            new=AsyncMock(side_effect=lambda w: NotesEvent(wine_id=w.wine_id)),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            body = await r.aread()

    events = _collect_sse(body.decode())
    complete = json.loads(next(d for e, d in events if e == "complete"))
    scan_id = complete["scan_id"]

    async with db_session.SessionLocal() as s:
        row = await s.scalar(sa_select(ScanLog).where(ScanLog.scan_id == scan_id))

    assert row is not None, "ScanLog row must be persisted after a successful scan"
    assert row.total_ms is not None, "total_ms must be populated in ScanLog"
    assert isinstance(row.total_ms, int)
    assert row.total_ms >= 0


async def test_scan_internal_error_scanlog_written_with_null_timing(client):
    """INTERNAL_ERROR path (queue loop exception) writes ScanLog with all timing fields as None."""
    from sqlalchemy import select as sa_select

    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX),
        ),
        patch(
            "backend.routers.scan.cache.lookup",
            new=AsyncMock(side_effect=RuntimeError("forced internal error")),
        ),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            body = await r.aread()

    events = _collect_sse(body.decode())
    event_types = [e for e, _ in events]
    assert "error" in event_types, f"expected error event, got: {event_types}"
    error_events = [d for e, d in events if e == "error"]
    assert error_events, "expected at least one error event"
    error_data = json.loads(error_events[0])
    assert error_data["code"] == "INTERNAL_ERROR"

    complete_events = [d for e, d in events if e == "complete"]
    assert complete_events, "expected complete event after INTERNAL_ERROR"
    complete = json.loads(complete_events[0])
    # INTERNAL_ERROR path emits complete without timing fields
    assert complete.get("ollama_ms") is None
    assert complete.get("image_ms") is None
    assert complete.get("sommelier_ms") is None
    assert complete.get("total_ms") is None
    scan_id = complete["scan_id"]

    async with db_session.SessionLocal() as s:
        row = await s.scalar(sa_select(ScanLog).where(ScanLog.scan_id == scan_id))

    assert row is not None, "ScanLog row must be written even on INTERNAL_ERROR"
    assert row.ollama_ms is None
    assert row.image_ms is None
    assert row.sommelier_ms is None
    assert row.total_ms is None


async def test_init_db_migration_idempotent():
    """init_db() must not raise when called against a DB that already has all columns.

    use_test_db autouse fixture creates tables via Base.metadata.create_all
    (all columns present). Calling init_db() again exercises the ALTER TABLE
    swallow-except path in _SCAN_LOG_MIGRATION_DDL.
    """
    from backend.db.session import init_db

    await init_db()


async def test_scan_ollama_error_timing_fields_in_complete(client):
    """complete event after Ollama failure includes total_ms as a non-negative integer."""

    async def raise_connection_error(
        image_data: bytes, on_first_token=None
    ) -> AsyncIterator[WineObject]:
        raise ConnectionRefusedError("Ollama not running")
        yield  # pragma: no cover

    with patch(
        "backend.routers.scan.ollama_client.extract_wines",
        side_effect=raise_connection_error,
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            body = await r.aread()

    events = _collect_sse(body.decode())
    complete = json.loads(next(d for e, d in events if e == "complete"))

    assert "total_ms" in complete
    assert isinstance(complete["total_ms"], int)
    assert complete["total_ms"] >= 0


# ---------------------------------------------------------------------------
# T7 (perf-ttfi): receive_ms + variant pre-generation + Brave timing
# ---------------------------------------------------------------------------


def _real_jpeg_bytes(width: int = 40, height: int = 60) -> bytes:
    """A real, PIL-openable JPEG so _generate_variant can decode it."""
    from io import BytesIO

    from PIL import Image as _Image

    buf = BytesIO()
    _Image.new("RGB", (width, height), (120, 30, 40)).save(buf, "JPEG")
    return buf.getvalue()


async def _drain_scan_sse(gen: AsyncIterator[str]) -> list[tuple[str, str]]:
    """Collect a raw _scan_sse async generator into parsed SSE events."""
    chunks: list[str] = []
    async for chunk in gen:
        chunks.append(chunk)
    return _collect_sse("".join(chunks))


async def test_scan_happy_path_includes_receive_ms(client):
    """happy-path complete event carries receive_ms as a non-negative integer (T1)."""
    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX),
        ),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=(None, 0, 0)),
        ),
        patch(
            "backend.routers.scan.sommelier.get_notes",
            new=AsyncMock(side_effect=lambda w: NotesEvent(wine_id=w.wine_id)),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            body = await r.aread()

    complete = json.loads(next(d for e, d in _collect_sse(body.decode()) if e == "complete"))
    assert "receive_ms" in complete
    assert isinstance(complete["receive_ms"], int)
    assert complete["receive_ms"] >= 0


async def test_scan_error_path_includes_receive_ms(client):
    """INTERNAL_ERROR complete event still carries receive_ms (threaded to error yield site)."""
    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX),
        ),
        patch(
            "backend.routers.scan.cache.lookup",
            new=AsyncMock(side_effect=RuntimeError("forced internal error")),
        ),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            body = await r.aread()

    complete = json.loads(next(d for e, d in _collect_sse(body.decode()) if e == "complete"))
    assert "receive_ms" in complete
    assert complete["receive_ms"] is None or isinstance(complete["receive_ms"], int)


async def test_receive_ms_value_threaded_to_both_complete_sites():
    """The receive_ms parameter passed to _scan_sse surfaces verbatim at both yield sites."""
    from backend.routers.scan import _scan_sse

    # Happy path: extraction yields no wines → happy-path complete event.
    with patch(
        "backend.routers.scan.ollama_client.extract_wines",
        return_value=_wine_stream(),
    ):
        events = await _drain_scan_sse(_scan_sse(make_jpeg(), "tid-happy", 123))
    complete = json.loads(next(d for e, d in events if e == "complete"))
    assert complete["receive_ms"] == 123

    # Error path: cache.lookup raises → INTERNAL_ERROR complete event.
    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX),
        ),
        patch(
            "backend.routers.scan.cache.lookup",
            new=AsyncMock(side_effect=RuntimeError("boom")),
        ),
    ):
        events = await _drain_scan_sse(_scan_sse(make_jpeg(), "tid-error", 77))
    complete = json.loads(next(d for e, d in events if e == "complete"))
    assert complete["receive_ms"] == 77


async def test_fetch_image_to_queue_calls_variant_pregeneration():
    """_fetch_image_to_queue pre-generates the card variant via asyncio.to_thread (T3)."""
    import asyncio as _asyncio

    import backend.routers.scan as scan_mod
    from backend.routers.scan import _fetch_image_to_queue

    fake_image = ImageEvent(
        wine_id=MARGAUX.wine_id,
        url=f"/wines/{MARGAUX.wine_id}/image",
        placeholder=False,
    )
    queue = _asyncio.Queue()
    acc = {"brave_search_ms": 0, "image_download_ms": 0}

    with (
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=(fake_image, 7, 3)),
        ),
        patch("backend.routers.scan.cache.write", new=AsyncMock(return_value=None)),
        patch(
            "backend.routers.scan.asyncio.to_thread",
            new=AsyncMock(return_value=None),
        ) as mock_to_thread,
    ):
        await _fetch_image_to_queue(MARGAUX, queue, "tid", acc)

    mock_to_thread.assert_awaited_once()
    assert mock_to_thread.await_args.args[0] is scan_mod._generate_variant


async def test_fetch_image_to_queue_writes_card_variant_file(tmp_path):
    """After _fetch_image_to_queue completes, the card WebP variant exists on disk (T3)."""
    import asyncio as _asyncio

    from backend.routers.scan import _fetch_image_to_queue

    # Real source JPEG so _generate_variant can decode + resize it.
    source_path = tmp_path / f"{MARGAUX.wine_id}.jpg"
    source_path.write_bytes(_real_jpeg_bytes())

    fake_image = ImageEvent(
        wine_id=MARGAUX.wine_id,
        url=f"/wines/{MARGAUX.wine_id}/image",
        placeholder=False,
    )
    acc = {"brave_search_ms": 0, "image_download_ms": 0}

    with (
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=(fake_image, 7, 3)),
        ),
        patch("backend.routers.scan.cache.write", new=AsyncMock(return_value=None)),
    ):
        await _fetch_image_to_queue(MARGAUX, _asyncio.Queue(), "tid", acc)

    variant_path = tmp_path / f"{MARGAUX.wine_id}_card.webp"
    assert variant_path.exists(), "card variant must be pre-generated on disk"
    assert variant_path.read_bytes()[:4] == b"RIFF", "variant must be a WebP file"


async def test_scan_complete_includes_brave_timing(client):
    """complete event aggregates per-wine Brave search + download timing (T4)."""
    fake_image = ImageEvent(
        wine_id=MARGAUX.wine_id,
        url=f"/wines/{MARGAUX.wine_id}/image",
        placeholder=False,
    )
    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX),
        ),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=(fake_image, 100, 50)),
        ),
        patch(
            "backend.routers.scan.sommelier.get_notes",
            new=AsyncMock(side_effect=lambda w: NotesEvent(wine_id=w.wine_id)),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            body = await r.aread()

    complete = json.loads(next(d for e, d in _collect_sse(body.decode()) if e == "complete"))
    assert complete["brave_search_ms"] == 100
    assert complete["image_download_ms"] == 50


async def test_scan_emits_ready_comment_before_any_event(client):
    """_scan_sse flushes a ': ready' comment first so the 200/first byte leave immediately."""
    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX),
        ),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=(None, 0, 0)),
        ),
        patch(
            "backend.routers.scan.sommelier.get_notes",
            new=AsyncMock(side_effect=lambda w: NotesEvent(wine_id=w.wine_id)),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            body = await r.aread()

    text = body.decode()
    assert text.startswith(": ready"), f"stream must open with ': ready'; got {text[:40]!r}"
    assert text.index(": ready") < text.index("event:"), "ready comment must precede all events"


async def test_scan_complete_includes_first_wine_ms(client):
    """happy-path complete event carries first_wine_ms as a non-negative integer (Diagnostic 3)."""
    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX),
        ),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=(None, 0, 0)),
        ),
        patch(
            "backend.routers.scan.sommelier.get_notes",
            new=AsyncMock(side_effect=lambda w: NotesEvent(wine_id=w.wine_id)),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            body = await r.aread()

    complete = json.loads(next(d for e, d in _collect_sse(body.decode()) if e == "complete"))
    assert "first_wine_ms" in complete
    assert isinstance(complete["first_wine_ms"], int)
    assert complete["first_wine_ms"] >= 0


async def test_scan_emits_analyzing_status_on_first_ollama_token(client):
    """First Ollama token fires on_first_token → a 'status: analyzing' event precedes wines."""

    async def _extract(image_data: bytes, on_first_token=None) -> AsyncIterator[WineObject]:
        if on_first_token is not None:
            on_first_token()
        yield MARGAUX

    with (
        patch("backend.routers.scan.ollama_client.extract_wines", side_effect=_extract),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=(None, 0, 0)),
        ),
        patch(
            "backend.routers.scan.sommelier.get_notes",
            new=AsyncMock(side_effect=lambda w: NotesEvent(wine_id=w.wine_id)),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            body = await r.aread()

    events = _collect_sse(body.decode())
    types = [e for e, _ in events]
    assert ("status", "analyzing") in events, f"expected analyzing status; got {events}"
    assert types.index("status") < types.index("wine"), "analyzing must precede the first wine"


async def test_scan_saves_image_when_enabled(client, tmp_path):
    """With SAVE_SCAN_IMAGES on, /scan persists the upload to scans/{scan_id}.jpg."""
    with (
        patch("backend.config.SAVE_SCAN_IMAGES", True),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            scan_id = r.headers.get("x-scan-id")
            await r.aread()

    assert scan_id, "X-Scan-Id header must be present"
    assert (tmp_path / "scans" / f"{scan_id}.jpg").exists()


async def test_scan_does_not_save_image_when_disabled(client, tmp_path):
    """Default (SAVE_SCAN_IMAGES off): no scans/ directory is created."""
    with (
        patch("backend.config.SAVE_SCAN_IMAGES", False),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            await r.aread()

    assert not (tmp_path / "scans").exists()


async def test_scan_first_wine_ms_none_when_no_wines(client):
    """No wines extracted → first_wine_ms is None (nothing was ever yielded)."""
    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            body = await r.aread()

    complete = json.loads(next(d for e, d in _collect_sse(body.decode()) if e == "complete"))
    assert complete.get("first_wine_ms") is None


def test_prune_scan_images_listdir_oserror_is_swallowed():
    """_prune_scan_images returns quietly when the scans dir can't be listed (E13)."""
    from backend.routers import scan as scan_mod

    with patch("backend.routers.scan.os.listdir", side_effect=OSError("boom")):
        # Must not raise — a missing/unreadable dir is non-fatal.
        scan_mod._prune_scan_images("/nonexistent/scans", keep=2)


def test_prune_scan_images_remove_oserror_is_logged(tmp_path):
    """A failed os.remove during prune is logged, not raised (best-effort cleanup)."""
    import os

    from backend.routers import scan as scan_mod

    scans_dir = tmp_path / "scans"
    scans_dir.mkdir()
    for i, name in enumerate(["a.jpg", "b.jpg", "c.jpg"]):
        path = scans_dir / name
        path.write_bytes(b"x")
        os.utime(path, (1000 + i, 1000 + i))

    with patch("backend.routers.scan.os.remove", side_effect=OSError("denied")):
        # keep=1 → two files targeted for removal; both raise but are swallowed.
        scan_mod._prune_scan_images(str(scans_dir), keep=1)

    # Nothing was actually deleted because remove failed, and no exception escaped.
    assert len(list(scans_dir.glob("*.jpg"))) == 3


def test_prune_scan_images_noop_when_at_or_below_keep(tmp_path):
    """When file count <= keep, prune is a no-op (no sorting/removal)."""
    from backend.routers import scan as scan_mod

    scans_dir = tmp_path / "scans"
    scans_dir.mkdir()
    (scans_dir / "only.jpg").write_bytes(b"x")
    scan_mod._prune_scan_images(str(scans_dir), keep=5)
    assert {p.name for p in scans_dir.glob("*.jpg")} == {"only.jpg"}


def test_write_scan_image_without_retention_keeps_all(tmp_path):
    """retention=None skips pruning entirely — every saved photo is retained."""
    from backend.routers import scan as scan_mod

    with patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)):
        for i in range(3):
            scan_mod._write_scan_image(b"jpegbytes", f"scan{i}", retention=None)

    saved = list((tmp_path / "scans").glob("*.jpg"))
    assert len(saved) == 3


async def test_scan_saves_image_via_config_flag(client, tmp_path):
    """SAVE_SCAN_IMAGES config True persists the photo even with no request header."""
    with (
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        patch("backend.config.SAVE_SCAN_IMAGES", True),
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        r = await client.post(
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        )
        assert r.status_code == 200
    assert len(list((tmp_path / "scans").glob("*.jpg"))) == 1


async def test_scan_save_image_header_truthy_aliases(client, tmp_path):
    """'true'/'yes' (not just '1') opt into saving; non-digit retention is ignored."""
    with (
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        patch("backend.config.SAVE_SCAN_IMAGES", False),
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        r = await client.post(
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
            headers={"X-Save-Scan-Image": "true", "X-Scan-Image-Retention": "abc"},
        )
        assert r.status_code == 200
    # Saved (truthy alias) and not pruned (retention header was non-digit → None).
    assert len(list((tmp_path / "scans").glob("*.jpg"))) == 1


async def test_scan_save_image_failure_is_non_fatal(client, tmp_path):
    """If persisting the scan photo raises, the scan still completes (best-effort)."""
    with (
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        patch("backend.config.SAVE_SCAN_IMAGES", False),
        patch(
            "backend.routers.scan._write_scan_image",
            side_effect=OSError("disk full"),
        ),
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
            headers={"X-Save-Scan-Image": "1"},
        ) as r:
            body = await r.aread()
    types = [e for e, _ in _collect_sse(body.decode())]
    assert "complete" in types, "scan must finish even when image save fails"


async def test_notes_failure_emits_empty_notes_event(client):
    """If sommelier.get_notes raises during the concurrent pass, a fallback empty
    NotesEvent is still emitted for that wine and the scan completes (E13/F3b)."""
    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX),
        ),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=(None, 0, 0)),
        ),
        patch(
            "backend.routers.scan.sommelier.get_notes",
            new=AsyncMock(side_effect=RuntimeError("ollama exploded")),
        ),
        patch("backend.routers.scan.cache.lookup", new=AsyncMock(return_value=None)),
    ):
        async with client.stream(
            "POST",
            "/scan",
            files={"image": ("list.jpg", make_jpeg(), "image/jpeg")},
        ) as r:
            body = await r.aread()

    events = _collect_sse(body.decode())
    notes = [json.loads(d) for e, d in events if e == "notes"]
    assert notes, "a fallback notes event must be emitted even when get_notes fails"
    assert notes[0].get("tasting_note") in (None, ""), "fallback note carries no tasting text"
    assert any(e == "complete" for e, _ in events), "scan must complete despite notes failure"
