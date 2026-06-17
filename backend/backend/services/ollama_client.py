"""
OllamaClient — streams WineObjects from Ollama via /api/chat JSONL.
Port of OllamaClient.swift.

CRITICAL — assistant pre-fill trick:
  The request messages array MUST end with {"role": "assistant", "content": "{"}.
  Without it, Qwen3-VL's thinking mode exhausts its entire generation budget on
  internal chain-of-thought reasoning and produces zero visible response tokens.
  This is not an Ollama bug — it is intentional model behavior. The pre-fill forces
  the model to begin its response mid-JSON-object, bypassing the CoT preamble.
  See also: test_ollama_prefill_in_request in tests/test_ollama_client.py.
"""

import base64
import json
from collections.abc import AsyncIterator

import httpx

from backend import config
from backend.models.wine import WineObject
from backend.prompts.wine_extraction import WINE_EXTRACTION_PROMPT

_MODEL = "qwen3-vl:8b"
_TIMEOUT = 120.0


def _make_client() -> httpx.AsyncClient:
    """Thin factory so tests can inject a mock transport without patching httpx globally."""
    return httpx.AsyncClient(timeout=_TIMEOUT)


def _make_health_client() -> httpx.AsyncClient:
    return httpx.AsyncClient(timeout=3.0)


async def extract_wines(image_data: bytes) -> AsyncIterator[WineObject]:
    """
    Stream WineObjects from a JPEG wine list photo via Ollama JSONL.

    Mirrors OllamaClient.swift:extractWines — same token buffer logic,
    same pre-fill trick, same 120s timeout.
    """
    body = {
        "model": _MODEL,
        "messages": [
            {
                "role": "user",
                "content": WINE_EXTRACTION_PROMPT,
                "images": [base64.b64encode(image_data).decode()],
            },
            # WARNING: removing this pre-fill breaks extraction — see module docstring.
            {
                "role": "assistant",
                "content": "{",
            },
        ],
        "stream": True,
        "options": {"temperature": 0.1},
    }

    try:
        async with _make_client() as client:
            async with client.stream(
                "POST",
                f"{config.OLLAMA_BASE_URL}/api/chat",
                json=body,
            ) as response:
                if response.status_code != 200:
                    raise ConnectionError(
                        f"Ollama returned HTTP {response.status_code}"
                    )

                token_buffer = ""
                first_token = True

                async for raw_line in response.aiter_lines():
                    if not raw_line:
                        continue

                    token = _parse_chunk_token(raw_line)
                    if token is None:
                        continue

                    # First token continues the pre-filled "{" — prepend it.
                    if first_token:
                        token = "{" + token
                        first_token = False

                    token_buffer += token

                    # Emit any complete JSON lines.
                    while "\n" in token_buffer:
                        idx = token_buffer.index("\n")
                        line = token_buffer[:idx].strip()
                        token_buffer = token_buffer[idx + 1 :]
                        wine = _try_parse(line)
                        if wine is not None:
                            yield wine

                # Flush: complete JSON object without a trailing newline.
                trimmed = token_buffer.strip()
                if trimmed.startswith("{") and trimmed.endswith("}"):
                    wine = _try_parse(trimmed)
                    if wine is not None:
                        yield wine

    except httpx.ConnectError as exc:
        raise ConnectionRefusedError(
            f"Ollama not reachable at {config.OLLAMA_BASE_URL}"
        ) from exc
    except httpx.TimeoutException as exc:
        raise TimeoutError("Ollama extraction timed out after 120s") from exc


async def check_reachable(base_url: str | None = None) -> bool:
    """Probe Ollama /api/tags. Used by GET /health."""
    url = base_url or config.OLLAMA_BASE_URL
    try:
        async with _make_health_client() as client:
            r = await client.get(f"{url}/api/tags")
            return r.status_code == 200
    except Exception:
        return False


def _parse_chunk_token(raw_line: str) -> str | None:
    """Extract the content token from one Ollama JSONL streaming chunk."""
    try:
        chunk = json.loads(raw_line)
    except json.JSONDecodeError:
        return None
    if chunk.get("done"):
        return None
    return chunk.get("message", {}).get("content") or None


def _try_parse(json_str: str) -> WineObject | None:
    try:
        return WineObject.model_validate_json(json_str)
    except Exception:
        return None
