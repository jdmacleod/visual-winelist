"""
Tests for OllamaClient.
All tests mock at the httpx transport layer — no Ollama installation required.
"""

import json
from unittest.mock import patch

import httpx
import pytest

from backend.services import ollama_client

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
    """
    Context manager: patches ollama_client._make_client to inject the transport.
    Avoids patching httpx.AsyncClient globally (which causes recursive calls).
    """
    return patch(
        "backend.services.ollama_client._make_client",
        lambda: httpx.AsyncClient(transport=transport),
    )


def _with_health_transport(transport: _MockTransport):
    return patch(
        "backend.services.ollama_client._make_health_client",
        lambda: httpx.AsyncClient(transport=transport),
    )


def _jsonl_response(*wine_dicts: dict) -> bytes:
    """
    Build a fake Ollama /api/chat streaming response.

    The assistant pre-fill {"role":"assistant","content":"{"} consumed the opening
    "{" of the FIRST wine. The client prepends "{" to the first token it receives.
    Subsequent wines are emitted with their own "{" by the model (they're new JSONL
    lines that the model starts fresh).
    """
    lines = []
    for i, wine in enumerate(wine_dicts):
        wine_json = json.dumps(wine)
        # First wine: strip the "{" that the pre-fill already provided
        # Subsequent wines: include the full JSON (model emits "{" itself)
        content = wine_json[1:] if i == 0 else wine_json
        half = len(content) // 2
        lines.append(json.dumps({"message": {"content": content[:half]}, "done": False}))
        lines.append(json.dumps({"message": {"content": content[half:] + "\n"}, "done": False}))
    lines.append(json.dumps({"done": True}))
    return "\n".join(lines).encode()


# ---------------------------------------------------------------------------
# D4 — CRITICAL: pre-fill trick must be present in every /api/chat request
# ---------------------------------------------------------------------------


async def test_ollama_prefill_in_request():
    """
    {"role":"assistant","content":"{"} MUST be the final message in every request.
    Without it Qwen3-VL exhausts its generation budget on CoT and produces zero tokens.
    """
    transport = _MockTransport()
    with _with_transport(transport):
        _ = [w async for w in ollama_client.extract_wines(b"fake-jpeg")]

    assert transport.captured_requests, "no HTTP request was made"
    body = json.loads(transport.captured_requests[0].content)

    prefill = {"role": "assistant", "content": "{"}
    assert prefill in body["messages"], (
        "assistant pre-fill missing — Qwen3-VL will produce zero tokens without it"
    )
    assert body["messages"][-1] == prefill, "pre-fill must be the final message"


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

_MARGAUX = {
    "name": "Château Margaux",
    "producer": "Château Margaux",
    "vintage": "2018",
    "variety": "Cabernet Sauvignon blend",
    "appellation": "Margaux, Bordeaux",
    "price": "$240",
    "description": None,
    "listSection": "Red Wines",
    "rawText": "Château Margaux 2018 · $240",
    "confidence": 0.94,
}
_OPUS = {
    "name": "Opus One",
    "producer": "Opus One",
    "vintage": "2019",
    "variety": None,
    "appellation": "Napa Valley",
    "price": "$360",
    "description": None,
    "listSection": None,
    "rawText": "Opus One 2019 · $360",
    "confidence": 0.91,
}


async def test_extract_wines_happy_path():
    transport = _MockTransport(body=_jsonl_response(_MARGAUX, _OPUS))
    with _with_transport(transport):
        wines = [w async for w in ollama_client.extract_wines(b"fake-jpeg")]

    assert len(wines) == 2
    assert wines[0].name == "Château Margaux"
    assert wines[0].vintage == "2018"
    assert wines[1].name == "Opus One"
    assert wines[1].vintage == "2019"


async def test_extract_wines_single_no_trailing_newline():
    """Wine JSON without a trailing \\n is parsed via the flush path."""
    content = json.dumps(_MARGAUX)[1:]  # strip "{" — pre-fill provides it
    body = (
        json.dumps({"message": {"content": content[:10]}, "done": False})
        + "\n"
        + json.dumps({"message": {"content": content[10:]}, "done": False})
        + "\n"
        + json.dumps({"done": True})
        + "\n"
    ).encode()
    transport = _MockTransport(body=body)
    with _with_transport(transport):
        wines = [w async for w in ollama_client.extract_wines(b"fake-jpeg")]

    assert len(wines) == 1
    assert wines[0].name == "Château Margaux"


async def test_extract_wines_zero_wines():
    """Empty stream produces an empty list, no exception."""
    transport = _MockTransport(body=b'{"done":true}\n')
    with _with_transport(transport):
        wines = [w async for w in ollama_client.extract_wines(b"fake-jpeg")]

    assert wines == []


# ---------------------------------------------------------------------------
# Error paths
# ---------------------------------------------------------------------------


async def test_extract_wines_non_200():
    transport = _MockTransport(status=500, body=b"internal error")
    with _with_transport(transport):
        with pytest.raises(ConnectionError):
            async for _ in ollama_client.extract_wines(b"fake-jpeg"):
                pass


async def test_extract_wines_ollama_down():
    """httpx.ConnectError → ConnectionRefusedError propagated to caller."""

    class _DownTransport(httpx.AsyncBaseTransport):
        async def handle_async_request(self, request):
            raise httpx.ConnectError("connection refused")

    with patch(
        "backend.services.ollama_client._make_client",
        lambda: httpx.AsyncClient(transport=_DownTransport()),
    ):
        with pytest.raises(ConnectionRefusedError):
            async for _ in ollama_client.extract_wines(b"fake-jpeg"):
                pass


async def test_extract_wines_malformed_json_skipped():
    """
    A line that parses as JSON but not as WineObject is skipped;
    valid subsequent lines are still yielded.

    Simulates: model emits '{"bad":true}\\n' as the first line (pre-fill recon),
    then emits a full valid wine JSON as the second line (model provides its own "{").
    """
    body = (
        # First line: pre-fill "{" + '"bad":true}\n' → '{"bad":true}' — invalid WineObject
        json.dumps({"message": {"content": '"bad":true}\n'}, "done": False})
        + "\n"
        # Second line: model emits full JSON with its own "{"
        + json.dumps({"message": {"content": json.dumps(_MARGAUX) + "\n"}, "done": False})
        + "\n"
        + json.dumps({"done": True})
        + "\n"
    ).encode()
    transport = _MockTransport(body=body)
    with _with_transport(transport):
        wines = [w async for w in ollama_client.extract_wines(b"fake-jpeg")]

    assert len(wines) == 1
    assert wines[0].name == "Château Margaux"


# ---------------------------------------------------------------------------
# check_reachable
# ---------------------------------------------------------------------------


async def test_check_reachable_ok():
    transport = _MockTransport(status=200, body=b'{"models":[]}')
    with _with_health_transport(transport):
        assert await ollama_client.check_reachable("http://localhost:11434") is True


async def test_check_reachable_down():
    class _DownTransport(httpx.AsyncBaseTransport):
        async def handle_async_request(self, request):
            raise httpx.ConnectError("refused")

    with patch(
        "backend.services.ollama_client._make_health_client",
        lambda: httpx.AsyncClient(transport=_DownTransport()),
    ):
        assert await ollama_client.check_reachable("http://localhost:11434") is False


# ---------------------------------------------------------------------------
# Request shape
# ---------------------------------------------------------------------------


async def test_request_uses_correct_model_and_options():
    transport = _MockTransport()
    with _with_transport(transport):
        _ = [w async for w in ollama_client.extract_wines(b"fake-jpeg")]

    body = json.loads(transport.captured_requests[0].content)
    assert body["model"] == "qwen3-vl:8b"
    assert body["stream"] is True
    assert body["options"]["temperature"] == 0.1
    # "think": false disables Qwen3-VL thinking mode at the Ollama API level.
    # Without it, the model may exhaust its token budget on CoT reasoning and
    # return zero visible JSON tokens. See module docstring for full context.
    assert body["options"]["think"] is False, (
        '"think": false missing — Qwen3-VL will use thinking mode and may produce zero wines'
    )


async def test_request_includes_base64_image():
    import base64

    image_bytes = b"fake-jpeg-data"
    transport = _MockTransport()
    with _with_transport(transport):
        _ = [w async for w in ollama_client.extract_wines(image_bytes)]

    body = json.loads(transport.captured_requests[0].content)
    user_msg = next(m for m in body["messages"] if m["role"] == "user")
    assert base64.b64decode(user_msg["images"][0]) == image_bytes
