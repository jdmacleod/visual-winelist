from collections.abc import AsyncIterator
from unittest.mock import AsyncMock, patch

from backend.models.wine import NotesEvent, WineObject
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
            new=AsyncMock(return_value=None),
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

    import json

    complete_data = json.loads(next(d for e, d in events if e == "complete"))
    assert complete_data["wine_count"] == 2
    assert "scan_id" in complete_data


async def test_scan_ollama_down(client):
    async def raise_connection_error(image_data: bytes) -> AsyncIterator[WineObject]:
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

    import json

    error_data = json.loads(next(d for e, d in events if e == "error"))
    assert error_data["code"] == "OLLAMA_DOWN"


async def test_two_phase_sse_order(client):
    """ALL wine events precede ALL notes events."""

    with (
        patch(
            "backend.routers.scan.ollama_client.extract_wines",
            return_value=_wine_stream(MARGAUX, OPUS),
        ),
        patch(
            "backend.routers.scan.brave_client.fetch_image",
            new=AsyncMock(return_value=None),
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
            new=AsyncMock(return_value=None),
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

    import json

    events = _collect_sse(body.decode())
    complete = json.loads(next(d for e, d in events if e == "complete"))
    assert "scan_id" in complete
    assert complete["wine_count"] == 1
