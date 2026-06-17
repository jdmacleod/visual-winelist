"""
Tests for SommelierService (T5): tasting notes + pairings via Ollama.
All tests mock at the httpx transport layer — no Ollama installation required.
"""

import json
from unittest.mock import patch

import httpx

from backend.models.wine import WineObject
from backend.services import sommelier

# ---------------------------------------------------------------------------
# Transport helpers
# ---------------------------------------------------------------------------


class _MockTransport(httpx.AsyncBaseTransport):
    """Captures outbound requests and returns a canned JSONL response."""

    def __init__(self, status: int = 200, body: bytes = b'{"done":true}\n'):
        self.status = status
        self.body = body
        self.captured_requests: list[httpx.Request] = []

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        self.captured_requests.append(request)
        return httpx.Response(self.status, content=self.body)


def _with_transport(transport: _MockTransport):
    return patch(
        "backend.services.sommelier._make_client",
        lambda: httpx.AsyncClient(transport=transport),
    )


def _notes_response(tasting_note: str, pairings: list[str]) -> bytes:
    """
    Build a fake Ollama sommelier streaming response.
    Pre-fill provides "{"; model continues from there.
    The content token is everything after the opening "{".
    """
    full = json.dumps({"tasting_note": tasting_note, "pairings": pairings})
    content = full[1:]  # strip "{" — pre-fill already provides it
    lines = [
        json.dumps({"message": {"content": content}, "done": False}),
        json.dumps({"done": True}),
    ]
    return "\n".join(lines).encode()


def _wine(
    name: str = "Château Margaux",
    producer: str | None = "Château Margaux",
    vintage: str | None = "2018",
    variety: str | None = "Cabernet Sauvignon blend",
    appellation: str | None = "Margaux, Bordeaux",
) -> WineObject:
    return WineObject(
        name=name,
        producer=producer,
        vintage=vintage,
        variety=variety,
        appellation=appellation,
        confidence=0.92,
    )


# ---------------------------------------------------------------------------
# D4 — CRITICAL: pre-fill trick must be present in every /api/chat request
# ---------------------------------------------------------------------------


async def test_sommelier_prefill_in_request():
    """
    {"role":"assistant","content":"{"} MUST be the final message in every request.
    Without it Qwen3-VL exhausts its generation budget on CoT and produces zero tokens.
    """
    transport = _MockTransport()
    with _with_transport(transport):
        await sommelier.get_notes(_wine())

    assert transport.captured_requests, "no HTTP request was made"
    body = json.loads(transport.captured_requests[0].content)

    prefill = {"role": "assistant", "content": "{"}
    assert prefill in body["messages"], (
        "assistant pre-fill missing — Qwen3-VL will produce zero tokens without it"
    )
    assert body["messages"][-1] == prefill, "pre-fill must be the final message"


# ---------------------------------------------------------------------------
# Request shape
# ---------------------------------------------------------------------------


async def test_request_is_text_only_no_images():
    """Sommelier calls are text-only — no base64 image in the user message."""
    transport = _MockTransport()
    with _with_transport(transport):
        await sommelier.get_notes(_wine())

    body = json.loads(transport.captured_requests[0].content)
    user_msg = next(m for m in body["messages"] if m["role"] == "user")
    assert "images" not in user_msg, "sommelier must not send image data to Ollama"


async def test_request_uses_correct_model():
    transport = _MockTransport()
    with _with_transport(transport):
        await sommelier.get_notes(_wine())

    body = json.loads(transport.captured_requests[0].content)
    assert body["model"] == "qwen3-vl:8b"
    assert body["stream"] is True


async def test_prompt_includes_wine_name():
    """User prompt must contain the wine name so the model knows what to describe."""
    transport = _MockTransport()
    with _with_transport(transport):
        await sommelier.get_notes(_wine(name="Opus One"))

    body = json.loads(transport.captured_requests[0].content)
    user_msg = next(m for m in body["messages"] if m["role"] == "user")
    assert "Opus One" in user_msg["content"]


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------


async def test_get_notes_happy_path():
    wine = _wine()
    body = _notes_response(
        tasting_note="Rich dark fruit with cedar and tobacco notes. Long, silky finish.",
        pairings=["lamb", "duck", "aged cheese"],
    )
    transport = _MockTransport(body=body)
    with _with_transport(transport):
        notes = await sommelier.get_notes(wine)

    assert notes.wine_id == wine.wine_id
    assert notes.tasting_note == "Rich dark fruit with cedar and tobacco notes. Long, silky finish."
    assert notes.pairings == ["lamb", "duck", "aged cheese"]


async def test_get_notes_empty_pairings():
    """Model may return empty pairings list — should parse cleanly."""
    wine = _wine()
    body = _notes_response(tasting_note="Delicate floral aromas. Crisp acidity.", pairings=[])
    transport = _MockTransport(body=body)
    with _with_transport(transport):
        notes = await sommelier.get_notes(wine)

    assert notes.tasting_note == "Delicate floral aromas. Crisp acidity."
    assert notes.pairings == []


async def test_get_notes_chunked_response():
    """Tokens may arrive in multiple chunks — accumulation must work correctly."""
    wine = _wine()
    expected_note = "Deep garnet with notes of black cherry. Velvety tannins."
    full = json.dumps({"tasting_note": expected_note, "pairings": ["beef", "venison"]})
    content = full[1:]  # strip pre-fill "{"
    mid = len(content) // 2
    body = (
        json.dumps({"message": {"content": content[:mid]}, "done": False})
        + "\n"
        + json.dumps({"message": {"content": content[mid:]}, "done": False})
        + "\n"
        + json.dumps({"done": True})
        + "\n"
    ).encode()
    transport = _MockTransport(body=body)
    with _with_transport(transport):
        notes = await sommelier.get_notes(wine)

    assert notes.tasting_note == expected_note
    assert notes.pairings == ["beef", "venison"]


# ---------------------------------------------------------------------------
# Graceful degrade
# ---------------------------------------------------------------------------


async def test_get_notes_degrade_on_connection_error():
    """Ollama unreachable → empty NotesEvent, no exception raised."""

    class _DownTransport(httpx.AsyncBaseTransport):
        async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
            raise httpx.ConnectError("connection refused")

    wine = _wine()
    with patch(
        "backend.services.sommelier._make_client",
        lambda: httpx.AsyncClient(transport=_DownTransport()),
    ):
        notes = await sommelier.get_notes(wine)

    assert notes.wine_id == wine.wine_id
    assert notes.tasting_note is None
    assert notes.pairings == []


async def test_get_notes_degrade_on_timeout():
    """Ollama timeout → empty NotesEvent, no exception raised."""

    class _TimeoutTransport(httpx.AsyncBaseTransport):
        async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
            raise httpx.ReadTimeout("timed out")

    wine = _wine()
    with patch(
        "backend.services.sommelier._make_client",
        lambda: httpx.AsyncClient(transport=_TimeoutTransport()),
    ):
        notes = await sommelier.get_notes(wine)

    assert notes.wine_id == wine.wine_id
    assert notes.tasting_note is None
    assert notes.pairings == []


async def test_get_notes_degrade_on_500():
    """HTTP 500 from Ollama → empty NotesEvent, no exception raised."""
    wine = _wine()
    transport = _MockTransport(status=500, body=b"internal error")
    with _with_transport(transport):
        notes = await sommelier.get_notes(wine)

    assert notes.wine_id == wine.wine_id
    assert notes.tasting_note is None
    assert notes.pairings == []


async def test_get_notes_degrade_on_malformed_json():
    """Ollama emits garbage — should degrade gracefully, not raise."""
    wine = _wine()
    body = (
        json.dumps({"message": {"content": "NOT JSON AT ALL"}, "done": False})
        + "\n"
        + json.dumps({"done": True})
        + "\n"
    ).encode()
    transport = _MockTransport(body=body)
    with _with_transport(transport):
        notes = await sommelier.get_notes(wine)

    assert notes.wine_id == wine.wine_id
    assert notes.tasting_note is None
    assert notes.pairings == []


async def test_get_notes_degrade_on_empty_stream():
    """Ollama returns only a done message (no content) — degrade gracefully."""
    wine = _wine()
    transport = _MockTransport(body=b'{"done":true}\n')
    with _with_transport(transport):
        notes = await sommelier.get_notes(wine)

    assert notes.wine_id == wine.wine_id
    assert notes.tasting_note is None
    assert notes.pairings == []
