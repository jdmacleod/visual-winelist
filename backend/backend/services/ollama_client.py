"""
OllamaClient — streams WineObjects from Ollama via /api/chat JSONL.
Port of OllamaClient.swift.

CRITICAL — Qwen3-VL thinking mode (two-layer defence):

Layer 1 — "think": False in options (primary, Ollama >= 0.6.x):
  Tells Ollama to disable CoT reasoning at the API level before the model
  generates anything. The model skips the thinking phase entirely and outputs
  JSON directly.

Layer 2 — assistant pre-fill {"role": "assistant", "content": "{"} (belt-and-suspenders):
  Forces the model to treat its response as already started with "{", bypassing
  the CoT preamble at the prompt level. Required when "think": False is not
  supported by the installed Ollama version (silently ignored on older builds).
  See test_ollama_prefill_in_request in tests/test_ollama_client.py.

If both layers fail (very old Ollama + model update), extraction returns zero
wines. The /health endpoint will still report ollama=true; upgrade Ollama and
re-pull qwen3-vl:8b to restore extraction.
"""

import base64
import json
import logging
from collections.abc import AsyncIterator, Callable
from io import BytesIO

import httpx
from PIL import Image

from backend import config
from backend.models.wine import WineObject
from backend.prompts.wine_extraction import WINE_EXTRACTION_PROMPT

log = logging.getLogger(__name__)

_MODEL = "qwen3-vl:8b"
_TIMEOUT = 120.0
_MAX_IMAGE_DIM = 2048  # longest side in pixels; keeps visual tokens within num_ctx=8192 budget


def _resize_for_model(image_data: bytes) -> bytes:
    """Downscale JPEG so longest side ≤ _MAX_IMAGE_DIM before sending to Ollama.

    iPhone 12MP photos (4032×3024) produce ~4200 visual tokens — more than
    qwen3-vl:8b's default 4096 context window. Resizing to 2048px drops that
    to ~1100 tokens, well within num_ctx=8192 while preserving fine print legibility.
    Returns original bytes unchanged if already within the limit.
    """
    try:
        img = Image.open(BytesIO(image_data))
    except Exception:
        log.warning(
            "_resize_for_model: could not decode image (%d bytes) — sending as-is", len(image_data)
        )
        return image_data
    w, h = img.size
    if max(w, h) <= _MAX_IMAGE_DIM:
        return image_data
    scale = _MAX_IMAGE_DIM / max(w, h)
    new_w, new_h = int(w * scale), int(h * scale)
    small = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    buf = BytesIO()
    small.save(buf, format="JPEG", quality=85)
    resized = buf.getvalue()
    log.info(
        "_resize_for_model: %dx%d → %dx%d (%d → %d bytes)",
        w,
        h,
        new_w,
        new_h,
        len(image_data),
        len(resized),
    )
    return resized


def _make_client() -> httpx.AsyncClient:
    """Thin factory so tests can inject a mock transport without patching httpx globally."""
    return httpx.AsyncClient(timeout=_TIMEOUT)


def _make_health_client() -> httpx.AsyncClient:
    return httpx.AsyncClient(timeout=3.0)


async def extract_wines(
    image_data: bytes, on_first_token: Callable[[], None] | None = None
) -> AsyncIterator[WineObject]:
    """
    Stream WineObjects from a JPEG wine list photo via Ollama JSONL.

    Mirrors OllamaClient.swift:extractWines — same token buffer logic,
    same pre-fill trick, same 120s timeout.

    on_first_token fires once, when the first content token arrives from Ollama
    (before any complete wine is parsed). Used to tell the client that analysis
    has started — the boundary between "getting ready" and "analyzing".
    """
    image_data = _resize_for_model(image_data)
    magic = " ".join(f"{b:02X}" for b in image_data[:4])
    log.info("extract_wines: %d bytes, magic=%s", len(image_data), magic)
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
        # "think": False disables Qwen3-VL's thinking mode at the API level
        # (Ollama >= 0.6.x). The assistant pre-fill above is belt-and-suspenders
        # for older Ollama installs that silently ignore this option.
        "options": {"temperature": 0.1, "think": False, "num_ctx": 8192},
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

                wine_count = 0
                token_buffer = ""
                first_token = True

                async for raw_line in response.aiter_lines():
                    if not raw_line:
                        continue

                    token = _parse_chunk_token(raw_line)
                    if token is None:
                        continue

                    # First token continues the pre-filled "{" — prepend it.
                    # Guard against future Ollama builds that echo the pre-fill
                    # in streamed tokens (would produce "{{..." and break JSON).
                    if first_token:
                        if on_first_token is not None:
                            on_first_token()
                        if not token.startswith("{"):
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
                            wine_count += 1
                            log.info("extract_wines: yielding wine #%d: %s", wine_count, wine.name)
                            yield wine

                # Flush: complete JSON object without a trailing newline.
                trimmed = token_buffer.strip()
                if trimmed.startswith("{") and trimmed.endswith("}"):
                    wine = _try_parse(trimmed)
                    if wine is not None:
                        wine_count += 1
                        log.info(
                            "extract_wines: flush yielded wine #%d: %s",
                            wine_count,
                            wine.name,
                        )
                        yield wine

                log.info("extract_wines: done, %d wines yielded", wine_count)

    except httpx.ConnectError as exc:
        raise ConnectionRefusedError(f"Ollama not reachable at {config.OLLAMA_BASE_URL}") from exc
    except httpx.TimeoutException as exc:
        raise TimeoutError("Ollama extraction timed out after 120s") from exc
    except httpx.HTTPError as exc:
        # Mid-stream network errors (RemoteProtocolError, ReadError, etc.) that
        # are not ConnectError or TimeoutException — treat as Ollama unreachable.
        raise OSError(f"Ollama stream error: {exc}") from exc


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
