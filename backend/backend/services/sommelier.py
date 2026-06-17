"""
SommelierService — per-wine Ollama calls for tasting notes + food pairings.

Runs in Phase 2 (after extraction stream closes) — Ollama is single-instance,
so sommelier calls are serial. Each call targets the same qwen3-vl:8b model
but uses a text-only prompt (no image), which is faster (~3-6s vs ~15-30s).

Graceful degrade: if the Ollama call fails, return NotesEvent with
tasting_note=None and pairings=[]. The wine is still shown to the user.
"""

import json
import logging

import httpx

from backend import config
from backend.models.wine import NotesEvent, WineObject
from backend.prompts.sommelier import make_sommelier_prompt

log = logging.getLogger(__name__)

_MODEL = "qwen3-vl:8b"
_TIMEOUT = 30.0


def _make_client() -> httpx.AsyncClient:
    """Thin factory so tests can inject a mock transport without patching httpx globally."""
    return httpx.AsyncClient(timeout=_TIMEOUT)


async def get_notes(wine: WineObject) -> NotesEvent:
    """
    Call Ollama for a 2-sentence tasting note and ≤3 food pairings.
    Gracefully degrades on any failure — wine is still shown without notes.
    """
    try:
        return await _fetch_notes(wine)
    except Exception:
        log.warning("sommelier call failed for %s", wine.wine_id, exc_info=True)
        return NotesEvent(wine_id=wine.wine_id, tasting_note=None, pairings=[])


async def _fetch_notes(wine: WineObject) -> NotesEvent:
    body = {
        "model": _MODEL,
        "messages": [
            {
                "role": "user",
                "content": make_sommelier_prompt(wine),
            },
            # WARNING: removing this pre-fill breaks extraction — see ollama_client.py docstring.
            {
                "role": "assistant",
                "content": "{",
            },
        ],
        "stream": True,
        "options": {"temperature": 0.3},
    }

    try:
        async with _make_client() as client:
            async with client.stream(
                "POST",
                f"{config.OLLAMA_BASE_URL}/api/chat",
                json=body,
            ) as response:
                if response.status_code != 200:
                    raise ConnectionError(f"Ollama returned HTTP {response.status_code}")

                # Pre-fill provides the opening "{"; accumulate the rest.
                token_buffer = "{"
                async for raw_line in response.aiter_lines():
                    if not raw_line:
                        continue
                    token = _parse_chunk_token(raw_line)
                    if token is not None:
                        token_buffer += token

                return _parse_notes(wine.wine_id, token_buffer)

    except httpx.ConnectError as exc:
        raise ConnectionRefusedError(f"Ollama not reachable at {config.OLLAMA_BASE_URL}") from exc
    except httpx.TimeoutException as exc:
        raise TimeoutError("Ollama sommelier timed out after 30s") from exc


def _parse_chunk_token(raw_line: str) -> str | None:
    """Extract the content token from one Ollama JSONL streaming chunk."""
    try:
        chunk = json.loads(raw_line)
    except json.JSONDecodeError:
        return None
    if chunk.get("done"):
        return None
    return chunk.get("message", {}).get("content") or None


def _parse_notes(wine_id: str, json_str: str) -> NotesEvent:
    """Parse Ollama's response into NotesEvent; degrade gracefully on bad JSON."""
    try:
        data = json.loads(json_str.strip())
        return NotesEvent(
            wine_id=wine_id,
            tasting_note=data.get("tasting_note") or None,
            pairings=data.get("pairings") or [],
        )
    except Exception:
        log.warning("failed to parse sommelier response: %r", json_str[:200])
        return NotesEvent(wine_id=wine_id, tasting_note=None, pairings=[])
