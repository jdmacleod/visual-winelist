"""
BraveSearchClient — port of BraveSearchClient.swift.

Portrait ranking: results are sorted by h/w ratio (descending) but not hard-filtered;
if every portrait candidate fails to download we fall back to lower-ranked shapes.

D3 — Content-Length pre-check:
  Check the response Content-Length header BEFORE reading body.
  Skip candidates with Content-Length > 2MB.
  If no Content-Length header, stream in chunks and abort at 2MB.
"""

import asyncio
import logging
import os
from typing import Any

import httpx

from backend import config
from backend.models.wine import ImageEvent, WineObject

_SEARCH_URL = "https://api.search.brave.com/res/v1/images/search"
_MAX_IMAGE_BYTES = 2 * 1024 * 1024  # 2MB
_CANDIDATE_LIMIT = 8
_SEARCH_COUNT = 20
_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
)

log = logging.getLogger(__name__)

# Token-bucket rate limiter (1 req/sec — Brave Free plan limit).
_rate_lock = asyncio.Lock()
_last_search_time: float = 0.0


def _make_http_client(timeout: float) -> httpx.AsyncClient:
    """Thin factory so tests can inject a mock transport without patching httpx globally."""
    return httpx.AsyncClient(timeout=timeout)


async def _wait_for_rate_limit() -> None:
    global _last_search_time
    async with _rate_lock:
        now = asyncio.get_running_loop().time()
        elapsed = now - _last_search_time
        if elapsed < 1.0:
            await asyncio.sleep(1.0 - elapsed)
        _last_search_time = asyncio.get_running_loop().time()


def _build_query(wine: WineObject) -> str:
    producer = wine.producer or wine.name
    variety = f" {wine.variety}" if wine.variety else ""
    vintage = f" {wine.vintage}" if wine.vintage else ""
    return f"{producer}{variety}{vintage} wine bottle"


def _portrait_score(result: dict[str, Any]) -> float:
    """Continuous h/w aspect ratio. Returns -1.0 if dimensions are missing or invalid."""
    props = result.get("properties") or {}
    h = props.get("height")
    w = props.get("width")
    if not h or not w or w == 0:
        return -1.0
    return float(h) / float(w)


async def _download_image(url: str) -> bytes | None:
    """
    Download image bytes with D3 Content-Length pre-check.
    Returns image bytes on success, None if oversized, unreachable, or non-200.
    """
    try:
        async with _make_http_client(8.0) as client:
            async with client.stream(
                "GET", url, headers={"User-Agent": _USER_AGENT}, follow_redirects=True
            ) as r:
                if r.status_code != 200:
                    return None
                # D3: Content-Length header check before reading body
                cl = r.headers.get("content-length")
                if cl is not None and int(cl) > _MAX_IMAGE_BYTES:
                    log.debug("skipping %s: Content-Length %s > 2MB", url, cl)
                    return None
                # D3: stream-abort at 2MB when no Content-Length header
                chunks: list[bytes] = []
                total = 0
                async for chunk in r.aiter_bytes(chunk_size=65536):
                    total += len(chunk)
                    if total > _MAX_IMAGE_BYTES:
                        log.debug("aborting %s: exceeded 2MB at %d bytes", url, total)
                        return None
                    chunks.append(chunk)
                data = b"".join(chunks)
                return data if data else None
    except Exception as exc:
        log.debug("download failed for %s: %s", url, exc)
        return None


async def fetch_image(wine: WineObject) -> ImageEvent | None:
    """
    Search Brave Image Search for a bottle image, download it, save to disk cache,
    and return an ImageEvent URL reference (D10). Returns None on total failure.
    """
    if not config.BRAVE_API_KEY:
        return None

    await _wait_for_rate_limit()

    query = _build_query(wine)
    log.debug("[Brave] query='%s'", query)

    try:
        async with _make_http_client(10.0) as client:
            r = await client.get(
                _SEARCH_URL,
                params={"q": query, "count": str(_SEARCH_COUNT), "search_lang": "en"},
                headers={
                    "X-Subscription-Token": config.BRAVE_API_KEY,
                    "Accept": "application/json",
                },
            )
    except Exception as exc:
        log.warning("[Brave] search request failed for '%s': %s", query, exc)
        return None

    if r.status_code != 200:
        log.warning("[Brave] HTTP %d for '%s'", r.status_code, query)
        return None

    try:
        body = r.json()
    except Exception:
        log.warning("[Brave] could not decode JSON for '%s'", query)
        return None

    results: list[dict[str, Any]] = body.get("results") or []
    if not results:
        log.debug("[Brave] 0 results for '%s'", query)
        return None

    ranked = sorted(results, key=_portrait_score, reverse=True)
    log.debug(
        "[Brave] %d results, top score=%.2f for '%s'",
        len(results),
        _portrait_score(ranked[0]),
        query,
    )

    wine_id = wine.wine_id
    cache_dir = config.IMAGE_CACHE_DIR
    cache_path = os.path.join(cache_dir, f"{wine_id}.jpg")

    for idx, candidate in enumerate(ranked[:_CANDIDATE_LIMIT]):
        thumb_url = (candidate.get("thumbnail") or {}).get("src") or ""
        if not thumb_url:
            continue

        image_data = await _download_image(thumb_url)
        if image_data is None:
            log.debug("[Brave] candidate %d download failed: %s", idx, thumb_url)
            continue

        try:
            os.makedirs(cache_dir, exist_ok=True)
            with open(cache_path, "wb") as f:
                f.write(image_data)
        except OSError as exc:
            log.warning("[Brave] failed to save image for %s: %s", wine_id, exc)
            continue

        log.debug(
            "[Brave] selected %s (%d bytes, attempt %d)",
            thumb_url,
            len(image_data),
            idx + 1,
        )
        return ImageEvent(
            wine_id=wine_id,
            url=f"/wines/{wine_id}/image",
            placeholder=False,
        )

    log.debug(
        "[Brave] no usable image for '%s' (%d results, %d candidates failed)",
        query,
        len(results),
        min(len(ranked), _CANDIDATE_LIMIT),
    )
    return None
